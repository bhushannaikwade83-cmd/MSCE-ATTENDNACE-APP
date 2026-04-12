import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:http/http.dart' as http;
import '../core/app_db.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:image/image.dart' as img;
import 'face_recognition_service.dart';
import 'b2b_storage_service.dart';
import 'liveness_detection_service.dart';
import 'photo_verification_service.dart';

/// ML Kit + MobileFaceNet Face Recognition Service
/// 
/// Complete face recognition system using:
/// - ML Kit: Face detection
/// - MobileFaceNet (TFLite): Face embeddings (192-dim)
/// - Firebase Firestore: Store embeddings
/// - Backblaze B2: Store images
/// - FastAPI Backend + FAISS: Vector search for 300k+ students
/// 
/// Architecture:
/// Flutter → ML Kit → MobileFaceNet → Firebase/Backend → FAISS → Attendance
class MLKitFaceNetService {
  // Backend API URL for FAISS vector search
  static String get _baseUrl {
    final envUrl = dotenv.env['FACE_RECOGNITION_API_URL'];
    if (envUrl != null && envUrl.isNotEmpty) {
      return envUrl;
    }
    return const String.fromEnvironment(
      'FACE_RECOGNITION_API_URL',
      defaultValue: 'https://face-recognition-api-mv5fg3vmlq-uc.a.run.app/api/v1',
    );
  }


  /// Register a student's face
  /// 
  /// Pipeline:
  /// 1. ML Kit detects face
  /// 2. MobileFaceNet generates 192-dim embedding
  /// 3. Liveness detection (blink + head movement)
  /// 4. Store embedding in Firebase Firestore
  /// 5. Upload image to Backblaze B2
  /// 6. Send embedding to backend for FAISS indexing
  static Future<bool> registerStudentFace({
    required String imagePath,
    required String instituteId,
    required String studentId,
    required String srNo,
    required String name,
    String? batchYear,
    String? subject,
  }) async {
    try {
      if (kDebugMode) {
        debugPrint('📸 Registering face for SR NO $srNo...');
      }

      // Step 1: Extract face features using ML Kit
      final faceFeatures = await FaceRecognitionService.extractFaceFeatures(imagePath);
      if (faceFeatures == null) {
        if (kDebugMode) debugPrint('❌ No face detected or face quality check failed');
        return false;
      }

      // Step 2: Liveness detection (blink + head movement)
      final livenessResult = await LivenessDetectionService.detectLivenessFromPhoto(
        photoPath: imagePath,
      );
      
      if (!livenessResult['isLive'] || (livenessResult['confidence'] as double) < 0.5) {
        if (kDebugMode) {
          debugPrint('❌ Liveness detection failed: ${livenessResult['details']}');
        }
        throw Exception('Liveness check failed. Please use a live photo with eyes open and look at the camera.');
      }

      // Step 3: Ensure MobileFaceNet is initialized
      try {
        await FaceRecognitionService.initialize();
      } catch (e) {
        if (kDebugMode) {
        debugPrint('❌ Failed to initialize FaceNet: $e');
        debugPrint('   Make sure assets/models/facenet.tflite exists');
        }
        throw Exception('Face recognition model (FaceNet) not available. Please restart the app.');
      }

      // 🛡️ SECURITY CHECK: Verify this face doesn't already belong to another student
      // Use identifyStudent to check if face matches any existing student
      if (kDebugMode) {
        debugPrint('🔍 Checking if face already exists for another student...');
      }
      
      final identifiedStudent = await FaceRecognitionService.identifyStudent(
        imagePath,
        instituteId,
      );
      
      if (identifiedStudent != null) {
        final identifiedSrNo = identifiedStudent['srNo'] as String? ?? identifiedStudent['userId'] as String?;
        final identifiedName = identifiedStudent['name'] as String? ?? 'Unknown';
        final identifiedStudentId = identifiedStudent['studentId'] as String?;
        
        // Check if identified student is different from the current student being registered
        // For temp students, we can't compare by ID, so compare by SR NO
        if (identifiedSrNo != null && identifiedSrNo != srNo && identifiedStudentId != studentId) {
          if (kDebugMode) {
            debugPrint('🚨 SECURITY ALERT: Face already registered for another student!');
            debugPrint('   Existing student: $identifiedName (SR NO: $identifiedSrNo, ID: $identifiedStudentId)');
            debugPrint('   New student: $name (SR NO: $srNo, ID: $studentId)');
          }
          
          throw Exception(
            '❌ SECURITY: This face is already registered for another student!\n\n'
            'Existing student:\n'
            '• Name: $identifiedName\n'
            '• SR NO: $identifiedSrNo\n\n'
            'New student:\n'
            '• Name: $name\n'
            '• SR NO: $srNo\n\n'
            '⚠️ One face cannot be registered for multiple students!\n\n'
            'Please ensure you are registering a unique face for this student.'
          );
        } else if (identifiedSrNo == srNo || identifiedStudentId == studentId) {
          // Same student - this is okay (updating existing registration)
          if (kDebugMode) {
            debugPrint('✅ Face matches existing registration for same student - update allowed');
          }
        }
      } else {
        // Face not found in database - this is a new unique face
        if (kDebugMode) {
          debugPrint('✅ Face check passed: No duplicate face found in database');
        }
      }

      // Step 4: Extract embedding using FaceRecognitionService
      // Use saveFaceTemplate which internally extracts and saves embedding
      final saved = await FaceRecognitionService.saveFaceTemplate(
        imagePath,
        instituteId,
        srNo,
        studentId,
      );

      if (!saved) {
        if (kDebugMode) debugPrint('❌ Failed to save face template');
        return false;
      }

      final studentRow = await appDb
          .from('students')
          .select('face_embedding')
          .eq('id', studentId)
          .eq('institute_id', instituteId)
          .maybeSingle();
      final fe = studentRow?['face_embedding'];
      Map<String, dynamic>? faceTemplate;
      if (fe is Map) {
        faceTemplate = Map<String, dynamic>.from(fe);
      }
      final embedding = faceTemplate?['embedding'] as List<dynamic>?;

      // Step 5: Upload registration photo to Backblaze B2
      // Always upload registration photo, even if batchYear/subject are null
      // Use default values if not provided
      String? imageUrl;
      try {
        final date = DateTime.now().toIso8601String().split('T')[0]; // YYYY-MM-DD
        final imageFile = File(imagePath);
        
        // Check if file exists
        if (!await imageFile.exists()) {
          if (kDebugMode) {
            debugPrint('⚠️ Image file does not exist: $imagePath');
          }
          throw Exception('Image file not found: $imagePath');
        }
        
        Uint8List photoBytes = await imageFile.readAsBytes();
        
        if (photoBytes.isEmpty) {
          if (kDebugMode) {
            debugPrint('⚠️ Image file is empty: $imagePath');
          }
          throw Exception('Image file is empty');
        }
        
        // Compress image if too large (target: under 50KB)
        if (photoBytes.length > 50 * 1024) {
          photoBytes = _compressImage(photoBytes, maxSizeKB: 50);
          if (kDebugMode) {
            debugPrint('📸 Registration photo compressed: ${(photoBytes.length / 1024).toStringAsFixed(2)} KB');
          }
        }
        
        // Use provided batchYear/subject or defaults
        final uploadBatchYear = batchYear ?? DateTime.now().year.toString();
        final uploadSubject = subject ?? 'all'; // Default subject if not provided
        
        if (kDebugMode) {
          debugPrint('📤 Uploading registration photo...');
          debugPrint('   Institute: $instituteId');
          debugPrint('   Student ID: $studentId');
          debugPrint('   SR NO: $srNo');
          debugPrint('   Batch Year: $uploadBatchYear');
          debugPrint('   Subject: $uploadSubject');
          debugPrint('   Photo Size: ${photoBytes.length} bytes (${(photoBytes.length / 1024).toStringAsFixed(2)} KB)');
        }
        
        final uploadResult = await B2BStorageService.uploadAttendancePhoto(
          instituteId: instituteId,
          batchYear: uploadBatchYear,
          rollNumber: srNo, // Using srNo for backward compatibility
          subject: uploadSubject,
          date: date,
          photoBytes: photoBytes,
          photoType: 'registration',
        );
        imageUrl = uploadResult['url'] as String?;
        final storagePath = uploadResult['path'] as String?; // Get storage path for temporary URL generation
        
        if (kDebugMode) {
          debugPrint('✅ Registration photo uploaded successfully');
          debugPrint('   Upload result: $uploadResult');
          debugPrint('   URL: $imageUrl');
          debugPrint('   Storage Path: $storagePath');
          debugPrint('   URL type: ${imageUrl.runtimeType}');
          debugPrint('   URL length: ${imageUrl?.length ?? 0}');
        }
        
        // Validate storagePath before saving (this is what we'll use for temporary URL generation)
        if (storagePath == null || storagePath.isEmpty) {
          throw Exception('Photo storage path is null or empty after upload');
        }
        
        // Skip saving to Firestore if this is a temporary student ID
        // Temporary documents will be cleaned up, so we only save for actual student IDs
        if (studentId.startsWith('temp_')) {
          if (kDebugMode) {
            debugPrint('⏭️ Skipping Firestore save for temp student ID: $studentId');
            debugPrint('   Photo storage path will be saved when actual student is created');
          }
        } else {
          if (kDebugMode) {
            debugPrint('💾 Saving registration photo info (Supabase students):');
            debugPrint('   Student ID: $studentId');
            debugPrint('   Institute ID: $instituteId');
            debugPrint('   Storage Path: $storagePath');
            debugPrint('   URL: $imageUrl');
          }

          final existing = await appDb
              .from('students')
              .select('face_embedding')
              .eq('id', studentId)
              .eq('institute_id', instituteId)
              .maybeSingle();
          final feMap = Map<String, dynamic>.from((existing?['face_embedding'] as Map?) ?? {});
          feMap['registrationPhotoPath'] = storagePath;
          feMap['facePhotoPath'] = storagePath;
          feMap['photoUploadedAt'] = DateTime.now().toUtc().toIso8601String();

          await appDb.from('students').update({
            'face_photo_url': imageUrl,
            'photo_url': imageUrl,
            'face_embedding': feMap,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          }).eq('id', studentId).eq('institute_id', instituteId);

          final saved = await appDb
              .from('students')
              .select('face_embedding, face_photo_url')
              .eq('id', studentId)
              .eq('institute_id', instituteId)
              .maybeSingle();
          final savedFe = saved?['face_embedding'];
          String? savedStoragePath;
          if (savedFe is Map) {
            savedStoragePath = savedFe['registrationPhotoPath'] as String?;
          }

          if (kDebugMode) {
            debugPrint('✅ Registration photo info saved: $studentId');
            debugPrint('   Saved storage path: $savedStoragePath');
            debugPrint('   Storage path verification: ${savedStoragePath == storagePath ? 'MATCH' : 'MISMATCH'}');
          }

          if (savedStoragePath != storagePath) {
            throw Exception('Photo storage path was not saved correctly. Expected: $storagePath, Got: $savedStoragePath');
          }
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('❌ Failed to upload registration photo to B2: $e');
          debugPrint('   Image path: $imagePath');
          debugPrint('   This is non-critical, but photo will not be displayed in student list');
        }
        // Non-critical, continue without image URL
      }

      // Step 5: Send embedding to backend for FAISS indexing (if available)
      if (embedding != null) {
        try {
          final request = http.MultipartRequest(
            'POST',
            Uri.parse('$_baseUrl/api/v1/register-embedding'),
          );
          
          request.fields['institute_id'] = instituteId;
          request.fields['student_id'] = studentId;
          request.fields['roll_number'] = srNo; // Backend expects roll_number
          request.fields['name'] = name;
          request.fields['embedding'] = jsonEncode(embedding.cast<double>());
          
          final response = await request.send();
          final responseBody = await response.stream.bytesToString();
          
          if (response.statusCode == 200 || response.statusCode == 201) {
            if (kDebugMode) debugPrint('✅ Face embedding indexed in FAISS backend');
          } else {
            if (kDebugMode) {
              debugPrint('⚠️ Backend indexing failed: ${response.statusCode} - $responseBody');
            }
            // Non-critical - embedding is in Firestore, can be indexed later
          }
        } catch (e) {
          if (kDebugMode) debugPrint('⚠️ Failed to index in backend: $e');
          // Non-critical - embedding is in Firestore
        }
      }

      if (kDebugMode) {
        debugPrint('✅ Face registered successfully for SR NO $srNo');
        debugPrint('   - Embedding stored in Firestore');
        debugPrint('   - Image URL: ${imageUrl ?? "Not uploaded"}');
      }

      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error registering face: $e');
      rethrow;
    }
  }

  /// Recognize a student from face photo (1:N identification)
  /// 
  /// Pipeline:
  /// 1. ML Kit detects face
  /// 2. MobileFaceNet generates 192-dim embedding
  /// 3. Liveness detection
  /// 4. Search in Firebase Firestore (local) OR Backend FAISS (for 300k+ students)
  /// 5. Return best match if similarity >= threshold
  static Future<Map<String, dynamic>?> recognizeStudent({
    required String imagePath,
    required String instituteId,
    double threshold = 0.55,
    bool useBackend = true, // Use backend FAISS for large datasets
  }) async {
    try {
      if (kDebugMode) {
        debugPrint('🔍 Recognizing student from photo...');
      }

      // Step 1: Extract face features
      final faceFeatures = await FaceRecognitionService.extractFaceFeatures(imagePath);
      if (faceFeatures == null) {
        if (kDebugMode) debugPrint('❌ No face detected');
        return null;
      }

      // Step 2: Liveness detection
      final livenessResult = await LivenessDetectionService.detectLivenessFromPhoto(
        photoPath: imagePath,
      );
      
      if (!livenessResult['isLive'] || (livenessResult['confidence'] as double) < 0.5) {
        if (kDebugMode) debugPrint('❌ Liveness check failed');
        throw Exception('Liveness check failed. Please use a live photo.');
      }

      // Step 3: Search for match
      if (useBackend) {
        // Use backend FAISS for large-scale search (300k+ students)
        return await _recognizeWithBackend(
          imagePath: imagePath,
          instituteId: instituteId,
          threshold: threshold,
        );
      } else {
        // Use local Firestore search (for smaller datasets)
        return await FaceRecognitionService.identifyStudent(
          imagePath,
          instituteId,
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error recognizing student: $e');
      return null;
    }
  }

  /// Recognize using backend FAISS
  static Future<Map<String, dynamic>?> _recognizeWithBackend({
    required String imagePath,
    required String instituteId,
    required double threshold,
  }) async {
    try {
      // Extract embedding first
      final faceFeatures = await FaceRecognitionService.extractFaceFeatures(imagePath);
      if (faceFeatures == null) return null;

      // Get embedding from Firestore or extract directly
      // For now, we'll use FaceRecognitionService.identifyStudent which does local search
      // Backend integration can be added later when backend endpoint is ready
      return await FaceRecognitionService.identifyStudent(imagePath, instituteId);
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error in backend recognition: $e');
      return null;
    }
  }

  /// Verify a student's face (1:1 verification)
  /// 
  /// Pipeline:
  /// 1. ML Kit detects face
  /// 2. MobileFaceNet generates embedding
  /// 3. Liveness detection (enhanced - detects photo-of-photo)
  /// 4. Compare with stored embedding for the roll number
  /// 
  /// Returns:
  /// - true if face matches registration photo AND passes liveness checks
  /// - false if face doesn't match OR liveness check fails
  static Future<bool> verifyStudentFace({
    required String imagePath,
    required String instituteId,
    required String srNo,
    double threshold = 0.60,
  }) async {
    try {
      // Step 1: Enhanced liveness detection (includes photo-of-photo detection)
      final livenessResult = await LivenessDetectionService.detectLivenessFromPhoto(
        photoPath: imagePath,
      );
      
      // Strict liveness check - require both isLive=true AND confidence >= 0.6
      if (!livenessResult['isLive'] || (livenessResult['confidence'] as double) < 0.6) {
        if (kDebugMode) {
          debugPrint('❌ Liveness check failed:');
          debugPrint('   isLive: ${livenessResult['isLive']}');
          debugPrint('   confidence: ${livenessResult['confidence']}');
          debugPrint('   details: ${livenessResult['details']}');
        }
        return false;
      }

      // Step 2: Additional photo-of-photo detection (double-check)
      // This is already done in the calling code, but we keep it here as a safety net
      final isPhotoOfPhoto = await PhotoVerificationService.detectPhotoOfPhoto(imagePath);
      if (isPhotoOfPhoto) {
        if (kDebugMode) {
          debugPrint('🚨 SECURITY: Photo-of-photo detected during face verification');
        }
        return false;
      }

      // Step 3: Verify face matches registration photo
      final faceMatch = await FaceRecognitionService.verifyStudent(
        imagePath,
        instituteId,
        srNo,
      );
      
      if (!faceMatch) {
        if (kDebugMode) {
          debugPrint('❌ Face verification failed: Photo does not match registration photo for SR NO $srNo');
        }
      }
      
      return faceMatch;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error verifying student: $e');
      return false;
    }
  }

  /// Compress image to target size (max 50KB)
  static Uint8List _compressImage(Uint8List imageBytes, {required int maxSizeKB}) {
    try {
      final maxSizeBytes = maxSizeKB * 1024;
      var decodedImage = img.decodeImage(imageBytes);
      if (decodedImage == null) return imageBytes;

      // Start with quality 85 and reduce if needed
      int quality = 85;
      Uint8List compressedBytes = imageBytes;

      // If image is still too large, resize it
      if (imageBytes.length > maxSizeBytes * 2) {
        final scale = 0.7; // Reduce to 70% of original size
        final newWidth = (decodedImage.width * scale).round();
        final newHeight = (decodedImage.height * scale).round();
        decodedImage = img.copyResize(decodedImage, width: newWidth, height: newHeight);
      }

      // Try different quality levels until we get under the limit
      while (compressedBytes.length > maxSizeBytes && quality > 20) {
        compressedBytes = Uint8List.fromList(
          img.encodeJpg(decodedImage, quality: quality),
        );
        quality -= 10;
      }

      // If still too large, resize more aggressively
      if (compressedBytes.length > maxSizeBytes) {
        final scale = 0.5; // Reduce to 50% of original size
        final newWidth = (decodedImage.width * scale).round();
        final newHeight = (decodedImage.height * scale).round();
        decodedImage = img.copyResize(decodedImage, width: newWidth, height: newHeight);
        compressedBytes = Uint8List.fromList(
          img.encodeJpg(decodedImage, quality: 60),
        );
      }

      if (kDebugMode) {
        debugPrint('📸 Image compression: ${(imageBytes.length / 1024).toStringAsFixed(2)} KB -> ${(compressedBytes.length / 1024).toStringAsFixed(2)} KB');
      }

      return compressedBytes;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error compressing image: $e');
      return imageBytes; // Return original if compression fails
    }
  }

  /// Upload attendance photo to Backblaze B2
  static Future<String?> uploadAttendancePhoto({
    required String imagePath,
    required String instituteId,
    required String batchYear,
    required String srNo,
    required String subject,
    required String date, // YYYY-MM-DD
    String? photoType, // 'entry' or 'exit'
  }) async {
    try {
      final imageFile = File(imagePath);
      Uint8List photoBytes = await imageFile.readAsBytes();
      
      // Compress image if too large (target: under 50KB)
      if (photoBytes.length > 50 * 1024) {
        photoBytes = _compressImage(photoBytes, maxSizeKB: 50);
        if (kDebugMode) {
          debugPrint('📸 Attendance photo compressed: ${(photoBytes.length / 1024).toStringAsFixed(2)} KB');
        }
      }
      
      final uploadResult = await B2BStorageService.uploadAttendancePhoto(
        instituteId: instituteId,
        batchYear: batchYear,
        rollNumber: srNo, // Using srNo for backward compatibility
        subject: subject,
        date: date,
        photoBytes: photoBytes,
        photoType: photoType,
      );
      
      return uploadResult['url'];
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error uploading attendance photo: $e');
      return null;
    }
  }
}
