import 'dart:typed_data';
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import '../../services/face_recognition_service.dart';
import '../../services/image_quality_service.dart';
import '../../core/app_db.dart';
import '../../core/utils/professional_messaging.dart';
import '../widgets/session_monitor.dart';

/// AI-powered photo-based face registration
/// 1. Captures real photo using device mobile camera
/// 2. Extracts accurate face embedding using AI model (MobileFaceNet via FaceRecognitionService)
/// 3. Uses real face embeddings for attendance verification and duplicate detection
class VideoFaceRegistrationScreen extends StatefulWidget {
  final String studentId;
  final String studentName;
  final String instituteId;
  final VoidCallback onRegistrationComplete;

  const VideoFaceRegistrationScreen({
    super.key,
    required this.studentId,
    required this.studentName,
    required this.instituteId,
    required this.onRegistrationComplete,
  });

  @override
  State<VideoFaceRegistrationScreen> createState() => _VideoFaceRegistrationScreenState();
}

class _VideoFaceRegistrationScreenState extends State<VideoFaceRegistrationScreen> {
  late FaceDetector _faceDetector;
  late ImagePicker _imagePicker;
  bool _isProcessing = false;
  String _status = '📸 Ready to capture';
  XFile? _capturedPhoto;

  @override
  void initState() {
    super.initState();
    _imagePicker = ImagePicker();

    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableLandmarks: true,
        enableTracking: true,
      ),
    );

    if (kDebugMode) {
      debugPrint('📸 Opening camera for ${widget.studentName}');
    }

    // Open camera immediately
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _capturePhoto();
    });
  }

  /// Capture a single photo using device camera
  Future<void> _capturePhoto() async {
    if (_isProcessing) return;

    // Suppress PIN lock while camera is open
    SessionMonitor.beginSuppressResumeLock();
    try {
      setState(() {
        _isProcessing = true;
        _status = 'Processing...'; // Generic message - no detailed embedding info
      });

      // Capture photo from camera
      final photo = await _imagePicker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
      );

      if (photo == null) {
        // User cancelled
        setState(() {
          _isProcessing = false;
          _status = '📸 Position your face and capture';
        });
        return;
      }

      _capturedPhoto = photo;

      if (kDebugMode) {
        debugPrint('📸 Photo captured: ${photo.path}');
      }

      // Don't update status - keep generic loading message
      // Detailed extraction will be logged to console only
      // Status messages shown on add_student_screen instead

      await _processPhotoCapture();
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Camera error: $e');
      if (mounted) {
        ProfessionalMessaging.showError(
          context,
          title: 'Camera Error',
          message: 'Failed to access camera: $e',
        );
        setState(() {
          _isProcessing = false;
          _status = '📸 Position your face and capture';
        });
      }
    } finally {
      SessionMonitor.endSuppressResumeLock();
    }
  }

  /// Process captured photo to extract AI face embedding
  Future<void> _processPhotoCapture() async {
    try {
      if (_capturedPhoto == null) {
        throw Exception('No photo captured');
      }

      if (kDebugMode) {
        debugPrint('🧠 Extracting AI face embedding from real photo...');
      }

      // Read photo bytes from captured image
      final photoBytes = await _capturedPhoto!.readAsBytes();

      // Extract real AI face embedding using FaceRecognitionService
      List<double> embedding = await _generateRealEmbedding(photoBytes);

      if (kDebugMode) {
        debugPrint('✅ AI embedding extracted (${embedding.length} dimensions)');
      }

      // CHECK FOR DUPLICATE REGISTRATION before returning
      if (kDebugMode) {
        debugPrint('🔍 Checking if face is already registered to another student...');
      }

      final duplicateError = await FaceRecognitionService.duplicateRegistrationBlockedMessageForEmbedding(
        embedding,
        widget.instituteId,
        excludeStudentId: null, // New registration, check all students
      );

      if (duplicateError != null) {
        // Face is already registered to someone else - BLOCK registration
        if (kDebugMode) {
          debugPrint('❌ Duplicate face detected: $duplicateError');
        }

        if (mounted) {
          ProfessionalMessaging.showError(
            context,
            title: 'Face Already Registered',
            message: duplicateError,
            durationSeconds: 5,
          );
          setState(() {
            _isProcessing = false;
            _status = '📸 Position your face and capture';
            _capturedPhoto = null;
          });
        }
        return; // Block registration - don't return embedding
      }

      // No duplicate found - face is unique and safe to register
      if (kDebugMode) {
        debugPrint('✅ Face is unique - no duplicate found');
        debugPrint('✅ Safe to proceed with registration');
      }

      // Return embedding and photo data (duplicate check passed!)
      if (mounted) {
        Navigator.pop(context, {
          'success': true,
          'embedding': embedding,
          'photoBytes': photoBytes,
          'frameCount': 1,
        });
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Embedding extraction error: $e');
      if (mounted) {
        ProfessionalMessaging.showError(
          context,
          title: 'Processing Failed',
          message: 'Failed to extract embedding: $e\n\nPlease try again.',
        );
        setState(() {
          _isProcessing = false;
          _status = '📸 Position your face and capture';
          _capturedPhoto = null;
        });
      }
    }
  }

  /// Extract face embedding using MobileFaceNet (SAME as attendance)
  Future<List<double>> _generateRealEmbedding(Uint8List photoBytes) async {
    try {
      if (kDebugMode) {
        debugPrint('🧠 Extracting neural embedding using MobileFaceNet...');
      }

      // Use file path from captured photo (required for MobileFaceNet)
      if (_capturedPhoto == null) {
        throw Exception('Photo file not available');
      }

      final photoPath = _capturedPhoto!.path;

      if (kDebugMode) {
        debugPrint('📸 Processing photo: $photoPath');
      }

      // Decode image to get dimensions
      final image = img.decodeImage(photoBytes);
      if (image == null) {
        throw Exception('Failed to decode image');
      }

      if (kDebugMode) {
        debugPrint('📸 Image size: ${image.width}x${image.height}');
      }

      // Detect face using ML Kit (for bounding box only)
      final inputImage = InputImage.fromFile(File(photoPath));
      final faces = await _faceDetector.processImage(inputImage);

      if (faces.isEmpty) {
        if (kDebugMode) {
          debugPrint('⚠️ No face detected');
        }
        throw Exception('No face detected in photo');
      }

      final face = faces.first;
      if (kDebugMode) {
        debugPrint('✅ Face detected: ${face.boundingBox.width.toInt()}x${face.boundingBox.height.toInt()}');
      }

      // Extract face features for MobileFaceNet
      final faceFeatures = {
        'boundingBox': {
          'left': face.boundingBox.left,
          'top': face.boundingBox.top,
          'right': face.boundingBox.right,
          'bottom': face.boundingBox.bottom,
          'width': face.boundingBox.width,
          'height': face.boundingBox.height,
        },
      };

      // Use MobileFaceNet to extract embedding (SAME method as attendance)
      if (kDebugMode) {
        debugPrint('🔄 Calling FaceRecognitionService.extractNeuralEmbedding()...');
        debugPrint('   Face features: ${faceFeatures.toString()}');
      }

      final embedding = await FaceRecognitionService.extractNeuralEmbedding(
        photoPath,
        faceFeatures,
      );

      if (kDebugMode) {
        if (embedding == null) {
          debugPrint('❌ MobileFaceNet returned NULL embedding');
        } else {
          debugPrint('✅ REGISTRATION: Neural embedding extracted (${embedding.length}-dim)');
          debugPrint('   Method: MobileFaceNet TFLite (SAME as attendance)');
          if (embedding.isNotEmpty) {
            debugPrint('   First 10 values: ${embedding.sublist(0, math.min(10, embedding.length)).map((v) => v.toStringAsFixed(3)).join(", ")}');
            // Check if all zeros
            final hasNonZero = embedding.any((v) => v.abs() > 0.0001);
            if (!hasNonZero) {
              debugPrint('⚠️ WARNING: Embedding is all zeros!');
            }
          } else {
            debugPrint('❌ ERROR: Embedding is empty!');
          }
        }
      }

      if (embedding == null || embedding.isEmpty) {
        if (kDebugMode) {
          debugPrint('❌ MobileFaceNet returned null/empty - cannot proceed');
        }
        throw Exception('MobileFaceNet extraction failed - embedding is null or empty');
      }

      return embedding;
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('❌ Registration embedding extraction error: $e');
        debugPrint('   Stack: $stackTrace');
      }
      throw Exception('Failed to extract neural embedding: $e');
    }
  }




  @override
  void dispose() {
    _faceDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => !_isProcessing,
      child: Scaffold(
        backgroundColor: Colors.black.withValues(alpha: 0.7),
        body: Center(
          child: _isProcessing
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      strokeWidth: 3,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      _status,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                )
              : const SizedBox.expand(),
        ),
      ),
    );
  }
}
