import 'dart:io';
import 'dart:math' as math;
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint, kIsWeb;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:path_provider/path_provider.dart';
import '../core/app_db.dart';
import '../core/student_face_embedding_utils.dart';
import 'package:image/image.dart' as img;
import 'tflite_interpreter_stub.dart'
    if (dart.library.io) 'tflite_interpreter_native.dart';

/// Result of verifying an attendance photo against the selected student (includes cross-student check).
class StudentFaceVerifyResult {
  final bool isMatch;
  /// User-facing reason when [isMatch] is false.
  final String message;

  const StudentFaceVerifyResult._(this.isMatch, this.message);

  const StudentFaceVerifyResult.match() : isMatch = true, message = '';

  factory StudentFaceVerifyResult.reject(String message) =>
      StudentFaceVerifyResult._(false, message);
}

/// Thrown when a registration photo matches another student's saved face template.
class DuplicateFaceRegistrationException implements Exception {
  final String message;
  DuplicateFaceRegistrationException(this.message);
  @override
  String toString() => message;
}

/// Face + neural embedding computed on-device only — **nothing written to Supabase** until [commitFaceRegistrationOnePhoto].
class PreparedFaceRegistrationOnePhoto {
  final Map<String, dynamic> embeddingPayload;

  PreparedFaceRegistrationOnePhoto({required this.embeddingPayload});
}

/// Face Recognition Service
///
/// Implements complete face recognition system with:
/// ✅ MobileFaceNet TFLite - 192-dim on-device neural embeddings
/// ✅ Registration embedding - Stores face embeddings during student registration
/// ✅ Attendance embedding - Extracts face embeddings during attendance marking
/// ✅ Cosine similarity - Uses proper cosine similarity for face matching
/// ✅ Threshold 0.60 - Neural embedding threshold (stricter than old 0.85 landmark threshold)
/// ✅ Face analysis - detects landmarks, pose, and usable enrollment quality
/// ✅ Geo fencing - Location-based restrictions (implemented in geofence_service.dart)
/// ✅ Entry/Exit logic - Entry/exit photo system (implemented in admin_attendance_screen.dart)
class FaceRecognitionService {
  // Google ML Kit Face Detector - Optimized for face recognition
  // Configuration:
  // - enableContours: true - Detects face contours for better feature extraction
  // - enableClassification: true - Classifies eyes open/closed, smiling
  // - enableLandmarks: true - Detects facial landmarks for feature comparison
  // - enableTracking: false - No tracking needed for static image processing
  // - minFaceSize: 0.05 - Minimum face size (5% of image) for detection
  // - performanceMode: accurate - Prioritizes accuracy for recognition
  static FaceDetector? _faceDetectorInstance;

  static FaceDetector get _faceDetector {
    _faceDetectorInstance ??= FaceDetector(
      options: FaceDetectorOptions(
        enableContours: true,
        enableClassification: true,
        enableLandmarks: true,
        enableTracking: false,
        minFaceSize: 0.05,
        performanceMode: FaceDetectorMode.accurate,
      ),
    );
    return _faceDetectorInstance!;
  }

  // MobileFaceNet TFLite interpreter for neural face embeddings
  // Input: [1, 112, 112, 3] float32, normalized to [-1, 1]
  // Output: [1, 192] float32 face embedding
  static Interpreter? _interpreter;
  static bool _isInitialized = false;

  /// Web has no FFI TFLite; iOS/Android use [tflite_flutter] (standard TFLite runtime).
  static bool get _skipMobileFaceNetNative => kIsWeb;

  // Similarity thresholds for neural embeddings (192-dim)
  // RELAXED THRESHOLDS for better real-world performance
  // Lower numbers are MORE strict with neural embeddings because
  // the 192-dim vectors are far more discriminative than 24-dim hand-crafted vectors
  static const double _identificationThreshold = 0.50; // For 1:N attendance matching (recall-oriented)

  /// Stricter than [_identificationThreshold]: only block **new** registration when the new
  /// face is the SAME person as an existing template (accounts for embedding variations).
  // BALANCED: 0.85 - blocks real duplicates (same person) but allows different people
  // At 85%: Same face registered twice = BLOCKED ❌ (cheating prevented)
  // At 85%: Different faces but similar = ALLOWED ✅ (legitimate new students not blocked)
  // Photo hash check FIRST catches exact duplicates (100% reliable)
  static const double _registrationDuplicateThreshold = 0.75;
  static const double _registrationReviewThreshold = 0.68;

  // Balanced: high enough to reject wrong faces, low enough to tolerate
  // lighting/angle variation for genuine students.
  static const double _verificationThreshold = 0.55;   // For 1:1 verification

  // Hard block only for very strong cross-student matches.
  static const double _crossStudentHardBlockThreshold = 0.88;

  static Map<String, dynamic>? _faceTemplateMap(Map<String, dynamic> row) {
    final raw = row['face_embedding'];
    if (raw is! Map) return null;
    return Map<String, dynamic>.from(raw);
  }

  /// Initialize the MobileFaceNet TFLite model.
  /// Call this once at app startup (e.g., in main.dart).
  /// Model loading takes ~200ms.
  static Future<void> initialize() async {
    if (_isInitialized) return;
    if (_skipMobileFaceNetNative) {
      if (kDebugMode) {
        debugPrint('ℹ️ MobileFaceNet skipped on web (no on-device TFLite FFI).');
      }
      return;
    }
    try {
      _interpreter = await Interpreter.fromAsset('assets/models/mobilefacenet.tflite');
      _isInitialized = true;
      if (kDebugMode) debugPrint('✅ MobileFaceNet model loaded successfully');
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Failed to load MobileFaceNet model: $e');
      rethrow;
    }
  }

  /// Decodes a still image, applies EXIF orientation via [img.bakeOrientation], writes JPEG to a temp file.
  ///
  /// iOS (and some Android) camera JPEGs are often stored with orientation tags; [InputImage.fromFilePath]
  /// and [img.decodeImage] can disagree, causing "no face" or wrong crops. Use the **returned** path for
  /// both [extractFaceFeatures] and [extractNeuralEmbedding] so boxes match pixels.
  ///
  /// If decoding fails (e.g. HEIC not supported by the `image` package), returns [imagePath] unchanged.
  static Future<String> ensureNormalizedJpegForFacePipeline(String imagePath) async {
    if (kIsWeb) return imagePath;
    try {
      final file = File(imagePath);
      if (!await file.exists()) {
        if (kDebugMode) debugPrint('⚠️ ensureNormalized: file not found: $imagePath');
        return imagePath;
      }
      final bytes = await file.readAsBytes();
      var image = img.decodeImage(bytes);
      if (image == null) {
        if (kDebugMode) {
          debugPrint('⚠️ ensureNormalized: decodeImage failed — using original (ML Kit may still work)');
        }
        return imagePath;
      }
      image = img.bakeOrientation(image);
      final dir = await getTemporaryDirectory();
      final out = File('${dir.path}/face_norm_${DateTime.now().microsecondsSinceEpoch}.jpg');
      await out.writeAsBytes(img.encodeJpg(image, quality: 92));
      if (kDebugMode) {
        debugPrint('✅ Normalized still image for face pipeline → ${out.path} (${image.width}×${image.height})');
      }
      return out.path;
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ ensureNormalized failed: $e');
      return imagePath;
    }
  }

  /// Dispose the TFLite interpreter. Call on app shutdown if needed.
  static void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isInitialized = false;
    _faceDetectorInstance?.close();
    _faceDetectorInstance = null;
  }

  /// Check if face is too far from camera based on face-to-image ratio.
  /// Returns error message if face is too distant, null if acceptable.
  static String? _checkFaceDistanceTooFar(String imagePath, Face face) {
    try {
      final bytes = File(imagePath).readAsBytesSync();
      var image = img.decodeImage(bytes);
      if (image == null) return null;

      final imageArea = image.width * image.height;
      final faceArea = face.boundingBox.width * face.boundingBox.height;
      final ratio = faceArea / imageArea;

      // Require face to be at least 8% of the image for close-up requirement
      // (~90×90 px on typical 1080p image)
      const minRatio = 0.08;
      if (ratio < minRatio) {
        return 'Face is too far away. Take a close-up photo with your face filling more of the frame.';
      }

      return null;
    } catch (_) {
      // If we can't check, allow (image loading failed)
      return null;
    }
  }

  /// Heuristic: very low edge energy in the face crop often means motion blur or misfocus.
  static String? _blurMessageIfFaceRegionTooSoft(String imagePath, Face face) {
    try {
      if (face.boundingBox.width * face.boundingBox.height < 2500) {
        return null;
      }
      final bytes = File(imagePath).readAsBytesSync();
      var image = img.decodeImage(bytes);
      if (image == null) return null;
      image = img.bakeOrientation(image);
      final left = face.boundingBox.left.floor().clamp(0, image.width - 1);
      final top = face.boundingBox.top.floor().clamp(0, image.height - 1);
      final fw = face.boundingBox.width.ceil().clamp(1, image.width - left);
      final fh = face.boundingBox.height.ceil().clamp(1, image.height - top);
      final crop = img.copyCrop(image, x: left, y: top, width: fw, height: fh);
      final g = img.grayscale(crop);
      final small = img.copyResize(g, width: 48, height: 48);
      var energy = 0.0;
      var n = 0;
      for (var y = 1; y < small.height - 1; y++) {
        for (var x = 1; x < small.width - 1; x++) {
          final cx = small.getPixel(x, y).luminance.toDouble();
          final gx = (cx - small.getPixel(x - 1, y).luminance.toDouble()).abs();
          final gy = (cx - small.getPixel(x, y - 1).luminance.toDouble()).abs();
          energy += gx + gy;
          n += 2;
        }
      }
      if (n == 0) return null;
      final avg = energy / n;
      if (avg < 2.8) {
        return 'Photo looks blurry or out of focus. Hold the phone steady, use more light, and take the picture again.';
      }
    } catch (_) {
      // ignore heuristic failures
    }
    return null;
  }

  /// Diagnostic: why a still photo is not acceptable for standard (front) face capture.
  /// Returns null only if the face would pass [extractFaceFeatures] checks.
  static Future<String?> getDiagnosticReasonForInvalidFace(String imagePath) async {
    if (kIsWeb) return 'Web platform not supported';

    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final faces = await _faceDetector.processImage(inputImage);

      if (faces.isEmpty) {
        return 'No face detected. Use good lighting, hold the camera still, and keep one face in the frame.';
      }

      if (faces.length > 1) {
        return 'Multiple faces detected (${faces.length}). Only one person is allowed. Ask others to move out of the frame.';
      }

      final face = faces.first;
      final qualityCheck = _checkFaceQuality(face);
      if (!qualityCheck['isValid']) {
        return qualityCheck['reason'] as String? ?? 'Face not accepted. Adjust position and try again.';
      }
      final blur = _blurMessageIfFaceRegionTooSoft(imagePath, face);
      if (blur != null) return blur;

      return null;
    } catch (e) {
      return 'Error analyzing photo: $e';
    }
  }

  /// Like [getDiagnosticReasonForInvalidFace] but for [extractFaceFeaturesForRegistrationAngle] rules.
  static Future<String?> getDiagnosticReasonForRegistrationAngle(
    String imagePath,
    String angle,
  ) async {
    if (kIsWeb) return 'Web platform not supported';
    final normalized = angle.toLowerCase().trim();

    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final faces = await _faceDetector.processImage(inputImage);

      if (faces.isEmpty) {
        return 'No face detected. Center the face, improve lighting, and try again.'
            ' (${_angleLabel(normalized)} photo)';
      }
      if (faces.length > 1) {
        return 'Multiple faces detected (${faces.length}). Only one person in the frame, please.'
            ' (${_angleLabel(normalized)} photo)';
      }

      final face = faces.first;
      final qualityCheck = _checkFaceQualityForRegistrationAngle(face, normalized);
      if (!qualityCheck['isValid']) {
        return qualityCheck['reason'] as String? ?? 'Face not accepted for ${_angleLabel(normalized)}. Try again.';
      }
      final blur = _blurMessageIfFaceRegionTooSoft(imagePath, face);
      if (blur != null) return blur;

      return null;
    } catch (e) {
      return 'Error analyzing photo: $e';
    }
  }

  static String _angleLabel(String angle) {
    switch (angle) {
      case 'left':
        return 'left side';
      case 'right':
        return 'right side';
      case 'front':
        return 'front';
      default:
        return angle;
    }
  }

  // Extract face features from an image using Google ML Kit Face Detection
  // Returns face features including landmarks, angles, and quality metrics
  static Future<Map<String, dynamic>?> extractFaceFeatures(String imagePath) async {
    if (kIsWeb) return null;

    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final faces = await _faceDetector.processImage(inputImage);

      if (faces.isEmpty) {
        if (kDebugMode) debugPrint('❌ No face detected in image');
        return null;
      }

      // If multiple faces detected, use the largest one (main person in frame)
      // This allows exit photos in crowded/background situations while keeping main student check
      Face face;
      if (faces.length > 1) {
        if (kDebugMode) {
          debugPrint('⚠️ Multiple faces detected (${faces.length}). Using largest face for verification.');
        }
        // Sort by face size and use largest
        faces.sort((a, b) =>
          (b.boundingBox.width * b.boundingBox.height)
          .compareTo(a.boundingBox.width * a.boundingBox.height));
        face = faces.first;
      } else {
        face = faces.first;
      }

      final qualityCheck = _checkFaceQuality(face);
      if (!qualityCheck['isValid']) {
        if (kDebugMode) {
          debugPrint('❌ Face quality check failed: ${qualityCheck['reason']}');
        }
        return null;
      }

      final distanceCheck = _checkFaceDistanceTooFar(imagePath, face);
      if (distanceCheck != null) {
        if (kDebugMode) debugPrint('❌ $distanceCheck');
        return null;
      }

      final blurEarly = _blurMessageIfFaceRegionTooSoft(imagePath, face);
      if (blurEarly != null) {
        if (kDebugMode) debugPrint('❌ $blurEarly');
        return null;
      }

      final features = {
        'boundingBox': {
          'left': face.boundingBox.left,
          'top': face.boundingBox.top,
          'width': face.boundingBox.width,
          'height': face.boundingBox.height,
        },
        'headEulerAngleY': face.headEulerAngleY,
        'headEulerAngleZ': face.headEulerAngleZ,
        'headEulerAngleX': face.headEulerAngleX,
        'leftEyeOpenProbability': face.leftEyeOpenProbability,
        'rightEyeOpenProbability': face.rightEyeOpenProbability,
        'smilingProbability': face.smilingProbability,
        'landmarks': _extractLandmarks(face),
        'faceSize': face.boundingBox.width * face.boundingBox.height,
        'qualityScore': qualityCheck['qualityScore'],
      };

      if (kDebugMode) debugPrint('✅ Face features extracted successfully (Quality: ${qualityCheck['qualityScore']})');
      return features;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error extracting face features: $e');
      return null;
    }
  }

  /// Extract face features for guided registration angles.
  /// Side-angle captures should not be forced through the exact same
  /// front-face validation rules as the main FRONT photo.
  static Future<Map<String, dynamic>?> extractFaceFeaturesForRegistrationAngle(
    String imagePath,
    String angle,
  ) async {
    if (kIsWeb) return null;

    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final faces = await _faceDetector.processImage(inputImage);

      if (faces.isEmpty) {
        if (kDebugMode) debugPrint('❌ No face detected in image');
        return null;
      }

      if (faces.length > 1) {
        if (kDebugMode) {
          debugPrint('🚫 SECURITY REJECTION: Multiple faces detected (${faces.length}).');
        }
        return null;
      }

      final face = faces.first;
      final qualityCheck = _checkFaceQualityForRegistrationAngle(face, angle);
      if (!qualityCheck['isValid']) {
        if (kDebugMode) {
          debugPrint('❌ $angle face quality check failed: ${qualityCheck['reason']}');
        }
        return null;
      }

      final blurReg = _blurMessageIfFaceRegionTooSoft(imagePath, face);
      if (blurReg != null) {
        if (kDebugMode) debugPrint('❌ $blurReg');
        return null;
      }

      final features = {
        'boundingBox': {
          'left': face.boundingBox.left,
          'top': face.boundingBox.top,
          'width': face.boundingBox.width,
          'height': face.boundingBox.height,
        },
        'headEulerAngleY': face.headEulerAngleY,
        'headEulerAngleZ': face.headEulerAngleZ,
        'headEulerAngleX': face.headEulerAngleX,
        'leftEyeOpenProbability': face.leftEyeOpenProbability,
        'rightEyeOpenProbability': face.rightEyeOpenProbability,
        'smilingProbability': face.smilingProbability,
        'landmarks': _extractLandmarks(face),
        'faceSize': face.boundingBox.width * face.boundingBox.height,
        'qualityScore': qualityCheck['qualityScore'],
      };

      if (kDebugMode) {
        debugPrint('✅ $angle face features extracted successfully (Quality: ${qualityCheck['qualityScore']})');
      }
      return features;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error extracting $angle face features: $e');
      return null;
    }
  }

  // Face ID-like quality checks
  static Map<String, dynamic> _checkFaceQuality(Face face) {
    final checks = <String, dynamic>{
      'isValid': true,
      'reason': '',
      'qualityScore': 0.0,
    };

    double qualityScore = 0.0;
    int checksPassed = 0;

    // 1. Face size check - STRICT for attendance: only accept close-up photos
    // Minimum 2500 pixels ensures face is clear and close (not from distance)
    final faceSize = face.boundingBox.width * face.boundingBox.height;
    const minFaceSize = 2500.0;  // STRICT: 50×50 px minimum face area for close-up requirement
    if (faceSize < minFaceSize) {
      checks['isValid'] = false;
      checks['reason'] = 'Face too small or too far. Please take a close-up photo with your face filling the frame.';
      return checks;
    }
    qualityScore += 0.2;
    checksPassed++;

    // 2. Face angle check - RELAXED from 30° to 45° for better tolerance
    final angleY = face.headEulerAngleY?.abs() ?? 0.0;
    final angleZ = face.headEulerAngleZ?.abs() ?? 0.0;
    final angleX = face.headEulerAngleX?.abs() ?? 0.0;

    if (angleY > 45 || angleZ > 45 || angleX > 45) {  // RELAXED: was 30
      checks['isValid'] = false;
      checks['reason'] = 'Face not looking at camera. Look straight ahead.';
      return checks;
    }
    qualityScore += 0.2;
    checksPassed++;

    // 3. Eye open check (liveness) - RELAXED from 0.18 to 0.10 for glasses/lighting tolerance
    final leftEyeOpen = face.leftEyeOpenProbability ?? 0.0;
    final rightEyeOpen = face.rightEyeOpenProbability ?? 0.0;
    final bestEyeOpen = math.max(leftEyeOpen, rightEyeOpen);

    // Glasses can reduce ML eye-open confidence on one eye.
    // Allow if at least one eye has reasonable confidence.
    if (bestEyeOpen < 0.10) {  // RELAXED: was 0.18
      checks['isValid'] = false;
      checks['reason'] =
          'Eyes are not clearly visible. Please look at camera and keep eyes open.';
      return checks;
    }
    qualityScore += 0.2;
    checksPassed++;

    // 4. Face position check
    qualityScore += 0.2;
    checksPassed++;

    // 5. Landmark completeness check
    final landmarks = _extractLandmarks(face);
    final requiredLandmarkTypes = [
      FaceLandmarkType.leftEye,
      FaceLandmarkType.rightEye,
      FaceLandmarkType.noseBase,
    ];
    int landmarksFound = 0;
    for (var landmarkType in requiredLandmarkTypes) {
      if (landmarks.containsKey(landmarkType.toString())) {
        landmarksFound++;
      }
    }

    if (landmarksFound < 2) {
      checks['isValid'] = false;
      checks['reason'] = 'Face not fully visible. Ensure good lighting and clear view.';
      return checks;
    }
    qualityScore += 0.2;
    checksPassed++;

    // 6. Mask/covered-mouth check (strict): block likely masked faces.
    // If mouth landmarks are not visible, the face may be covered.
    final mouthLandmarkTypes = [
      FaceLandmarkType.leftMouth,
      FaceLandmarkType.rightMouth,
      FaceLandmarkType.bottomMouth,
    ];
    var mouthFound = 0;
    for (final type in mouthLandmarkTypes) {
      if (landmarks.containsKey(type.toString())) {
        mouthFound++;
      }
    }
    if (mouthFound < 2) {
      checks['isValid'] = false;
      checks['reason'] =
          'Mask/face covering detected. Please keep mouth and nose clearly visible.';
      return checks;
    }

    checks['qualityScore'] = qualityScore;
    checks['checksPassed'] = checksPassed;
    return checks;
  }

  static Map<String, dynamic> _checkFaceQualityForRegistrationAngle(
    Face face,
    String angle,
  ) {
    final normalizedAngle = angle.toLowerCase();
    if (normalizedAngle == 'front') {
      return _checkFaceQuality(face);
    }

    final checks = <String, dynamic>{
      'isValid': true,
      'reason': '',
      'qualityScore': 0.0,
    };

    double qualityScore = 0.0;
    int checksPassed = 0;

    final faceSize = face.boundingBox.width * face.boundingBox.height;
    const minFaceSize = 1500.0;
    if (faceSize < minFaceSize) {
      checks['isValid'] = false;
      checks['reason'] = 'Face too small. Move closer to camera.';
      return checks;
    }
    qualityScore += 0.25;
    checksPassed++;

    final angleZ = face.headEulerAngleZ?.abs() ?? 0.0;
    final angleX = face.headEulerAngleX?.abs() ?? 0.0;
    if (angleZ > 15 || angleX > 25) {
      checks['isValid'] = false;
      checks['reason'] = 'Keep your head upright and avoid tilting during side-angle capture.';
      return checks;
    }
    qualityScore += 0.25;
    checksPassed++;

    final landmarks = _extractLandmarks(face);
    final hasNose = landmarks.containsKey(FaceLandmarkType.noseBase.toString());
    final hasAnyEye = landmarks.containsKey(FaceLandmarkType.leftEye.toString()) ||
        landmarks.containsKey(FaceLandmarkType.rightEye.toString());
    if (!hasNose || !hasAnyEye) {
      checks['isValid'] = false;
      checks['reason'] = 'Side face is not clear enough. Keep one eye and nose visible.';
      return checks;
    }
    qualityScore += 0.25;
    checksPassed++;

    final hasAnyCheek = landmarks.containsKey(FaceLandmarkType.leftCheek.toString()) ||
        landmarks.containsKey(FaceLandmarkType.rightCheek.toString());
    if (!hasAnyCheek) {
      checks['isValid'] = false;
      checks['reason'] = 'Side face is not clear enough. Keep your side profile fully visible.';
      return checks;
    }
    qualityScore += 0.25;
    checksPassed++;

    checks['qualityScore'] = qualityScore;
    checks['checksPassed'] = checksPassed;
    return checks;
  }

  // Extract face landmarks
  static Map<String, dynamic> _extractLandmarks(Face face) {
    final landmarks = <String, dynamic>{};

    final landmarkTypes = [
      FaceLandmarkType.leftEye,
      FaceLandmarkType.rightEye,
      FaceLandmarkType.noseBase,
      FaceLandmarkType.leftCheek,
      FaceLandmarkType.rightCheek,
      FaceLandmarkType.leftMouth,
      FaceLandmarkType.rightMouth,
      FaceLandmarkType.bottomMouth,
    ];

    for (var type in landmarkTypes) {
      final landmark = face.landmarks[type];
      if (landmark != null) {
        landmarks[type.toString()] = {
          'x': landmark.position.x,
          'y': landmark.position.y,
        };
      }
    }

    return landmarks;
  }

  /// Extract 192-dim face embedding using MobileFaceNet TFLite model.
  ///
  /// Pipeline:
  /// 1. Read image from file
  /// 2. Crop to face bounding box (from ML Kit) with 20% padding
  /// 3. Resize cropped face to 112x112
  /// 4. Normalize pixels: (pixel - 127.5) / 128.0
  /// 5. Run TFLite inference
  /// 6. L2-normalize the output embedding
  ///
  /// Returns null if model not initialized or inference fails.
  // Public method for extracting neural embeddings (used in attendance verification)
  static Future<List<double>?> extractNeuralEmbedding(
    String imagePath,
    Map<String, dynamic> faceFeatures,
  ) async {
    return _extractNeuralEmbeddingInternal(imagePath, faceFeatures);
  }

  static Future<List<double>?> _extractNeuralEmbeddingInternal(
    String imagePath,
    Map<String, dynamic> faceFeatures,
  ) async {
    if (_skipMobileFaceNetNative) {
      if (kDebugMode) debugPrint('❌ Neural embedding unavailable on web.');
      return null;
    }
    await initialize();
    if (!_isInitialized || _interpreter == null) {
      if (kDebugMode) {
        debugPrint('❌ MobileFaceNet not available (init skipped or failed).');
      }
      return null;
    }

    try {
      // 1. Read image file
      final imageFile = File(imagePath);
      final imageBytes = await imageFile.readAsBytes();
      final originalImage = img.decodeImage(imageBytes);
      if (originalImage == null) {
        if (kDebugMode) debugPrint('❌ Could not decode image');
        return null;
      }

      // 2. Crop face from image using ML Kit bounding box with 20% padding
      final box = faceFeatures['boundingBox'] as Map<String, dynamic>;
      final left = (box['left'] as double).round();
      final top = (box['top'] as double).round();
      final width = (box['width'] as double).round();
      final height = (box['height'] as double).round();

      // Keep crop tighter around the face so background similarity influences embeddings less.
      final padX = (width * 0.10).round();
      final padY = (height * 0.10).round();
      final cropLeft = (left - padX).clamp(0, originalImage.width - 1);
      final cropTop = (top - padY).clamp(0, originalImage.height - 1);
      final cropWidth = (width + padX * 2).clamp(1, originalImage.width - cropLeft);
      final cropHeight = (height + padY * 2).clamp(1, originalImage.height - cropTop);

      final croppedFace = img.copyCrop(
        originalImage,
        x: cropLeft,
        y: cropTop,
        width: cropWidth,
        height: cropHeight,
      );

      // 3. Resize to 112x112 (MobileFaceNet input size)
      final resizedFace = img.copyResize(croppedFace, width: 112, height: 112);

      // 4. Normalize pixels to [-1, 1]: (pixel - 127.5) / 128.0
      // Create input tensor [1, 112, 112, 3]
      final input = List.generate(
        1,
        (_) => List.generate(
          112,
          (y) => List.generate(
            112,
            (x) {
              final pixel = resizedFace.getPixel(x, y);
              return [
                (pixel.r.toDouble() - 127.5) / 128.0,
                (pixel.g.toDouble() - 127.5) / 128.0,
                (pixel.b.toDouble() - 127.5) / 128.0,
              ];
            },
          ),
        ),
      );

      // 5. Run TFLite inference; output: [1, 192] float32
      final output = List.generate(1, (_) => List.filled(192, 0.0));
      _interpreter!.run(input, output);

      final embedding = output[0];

      // 6. L2-normalize the embedding
      double norm = 0.0;
      for (final val in embedding) {
        norm += val * val;
      }
      norm = math.sqrt(norm);
      if (norm > 0) {
        for (int i = 0; i < embedding.length; i++) {
          embedding[i] = embedding[i] / norm;
        }
      }

      if (kDebugMode) debugPrint('✅ Neural embedding extracted (192-dim, L2-normalized)');
      return embedding;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error extracting neural embedding: $e');
      return null;
    }
  }

  // Calculate cosine similarity between two L2-normalized face embeddings.
  // For L2-normalized neural embeddings, result is already in [0, 1] range.
  static double calculateCosineSimilarity(List<double> embedding1, List<double> embedding2) {
    if (embedding1.length != embedding2.length) {
      if (kDebugMode) debugPrint('⚠️ Embedding length mismatch: ${embedding1.length} vs ${embedding2.length}');
      return 0.0;
    }

    double dotProduct = 0.0;
    double norm1 = 0.0;
    double norm2 = 0.0;

    for (int i = 0; i < embedding1.length; i++) {
      dotProduct += embedding1[i] * embedding2[i];
      norm1 += embedding1[i] * embedding1[i];
      norm2 += embedding2[i] * embedding2[i];
    }

    final magnitude1 = math.sqrt(norm1);
    final magnitude2 = math.sqrt(norm2);

    if (magnitude1 == 0.0 || magnitude2 == 0.0) {
      return 0.0;
    }

    final cosineSimilarity = dotProduct / (magnitude1 * magnitude2);

    // For L2-normalized neural embeddings, cosine similarity is already [0, 1]
    return cosineSimilarity.clamp(0.0, 1.0);
  }

  // Find matching student from attendance photo (1:N identification)
  static Future<Map<String, dynamic>?> identifyStudent(
    String attendancePhotoPath,
    String instituteId,
  ) async {
    if (kIsWeb) return null;

    try {
      // Extract features from attendance photo
      final attendanceFeatures = await extractFaceFeatures(attendancePhotoPath);
      if (attendanceFeatures == null) {
        if (kDebugMode) debugPrint('❌ Could not extract features from attendance photo');
        return null;
      }

      // Extract neural embedding from attendance photo
      final attendanceEmbedding = await _extractNeuralEmbeddingInternal(attendancePhotoPath, attendanceFeatures);
      if (attendanceEmbedding == null) {
        if (kDebugMode) debugPrint('❌ Could not extract neural embedding');
        return null;
      }

      final rows = await appDb
          .from('students')
          .select('id, name, user_id, sr_no, face_embedding')
          .eq('institute_id', instituteId);

      if (rows.isEmpty) {
        if (kDebugMode) debugPrint('⚠️ No students found in institute');
        return null;
      }

      double bestSimilarity = 0.0;
      Map<String, dynamic>? bestMatch;

      for (final studentData in rows) {
        final faceTemplate = _faceTemplateMap(studentData);
        if (faceTemplate == null) continue;

        final templateVersion = faceTemplate['version'] as int? ?? 1;
        if (templateVersion < 2) continue;

        final storedEmbedding = (faceTemplate['embedding'] as List<dynamic>?)?.cast<double>().toList();
        if (storedEmbedding == null) continue;

        final similarity = calculateCosineSimilarity(attendanceEmbedding, storedEmbedding);
        final roll = studentData['user_id'] ?? studentData['sr_no'];
        if (kDebugMode) {
          debugPrint('🎯 Student $roll: Similarity = ${(similarity * 100).toStringAsFixed(1)}%');
        }

        if (similarity > bestSimilarity) {
          bestSimilarity = similarity;
          bestMatch = {
            'rollNumber': roll,
            'name': studentData['name'] ?? 'Unknown',
            'similarity': similarity,
            'studentId': studentData['id'],
          };
        }
      }

      if (bestMatch != null && bestSimilarity >= _identificationThreshold) {
        if (kDebugMode) {
          debugPrint('✅ Student identified: ${bestMatch['name']} (Roll ${bestMatch['rollNumber']}) - ${(bestSimilarity * 100).toStringAsFixed(1)}% match');
        }
        return bestMatch;
      } else {
        if (kDebugMode) {
          debugPrint('⚠️ No confident match found. Best similarity: ${(bestSimilarity * 100).toStringAsFixed(1)}%');
        }
        return null;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error identifying student: $e');
      return null;
    }
  }

  /// Computes embedding and duplicate checks locally. **Does not write to Supabase.**
  static Future<PreparedFaceRegistrationOnePhoto?> prepareFaceRegistrationOnePhoto(
    String imagePath,
    String instituteId,
    String rollNumber,
    String studentId,
  ) async {
    if (kIsWeb) return null;

    try {
      final features = await extractFaceFeatures(imagePath);
      if (features == null) {
        if (kDebugMode) debugPrint('❌ Could not extract face features');
        return null;
      }

      final embedding = await _extractNeuralEmbeddingInternal(imagePath, features);
      if (embedding == null) {
        if (kDebugMode) debugPrint('❌ Could not extract neural embedding');
        return null;
      }

      if (!registrationEmbeddingVectorValid(embedding)) {
        if (kDebugMode) {
          debugPrint(
            '❌ Face embedding missing or invalid '
            '(need ≥$kMobileFaceNetEmbeddingDimensions dims, non-trivial magnitude)',
          );
        }
        return null;
      }

      if (kDebugMode) {
        debugPrint('🔍 REGISTRATION EMBEDDING EXTRACTED:');
        debugPrint('   Length: ${embedding.length} dimensions');
        debugPrint('   Type: ${embedding.runtimeType}');
        if (embedding.isNotEmpty) {
          final firstTen = embedding.take(10).toList();
          debugPrint('   First 10 values: ${firstTen.map((v) => v.toStringAsFixed(4)).join(", ")}');
          final hasNonZero = embedding.any((v) => v.abs() > 0.0001);
          if (!hasNonZero) {
            debugPrint('   ⚠️ WARNING: All embedding values are near zero!');
          } else {
            debugPrint('   ✅ Has non-zero values (good)');
          }
          double norm = 0.0;
          for (final val in embedding) {
            norm += val * val;
          }
          norm = math.sqrt(norm);
          debugPrint('   L2 Norm: ${norm.toStringAsFixed(4)} (should be ~1.0 if L2-normalized)');
        }
      }

      final dupMsg = await _duplicateRegistrationBlockedMessageForEmbedding(
        embedding,
        instituteId,
        excludeStudentId: studentId,
        photoPath: imagePath,
      );
      if (dupMsg != null) {
        throw DuplicateFaceRegistrationException(dupMsg);
      }

      final photoHash = await _calculatePhotoHash(imagePath);

      if (kDebugMode) {
        debugPrint('💾 Prepared face registration locally (not persisted until commit)');
        debugPrint('   Student ID: $studentId');
        debugPrint('   Institute ID: $instituteId');
        debugPrint('   Roll: $rollNumber');
      }

      final List<double> cleanEmbedding = List<double>.from(embedding);

      final embeddingPayload = <String, dynamic>{
        'embedding': cleanEmbedding,
        'qualityScore': features['qualityScore'],
        'photoHash': photoHash,
        'version': 2,
        'modelVersion': 'mobilefacenet_tflite_v1',
      };

      if (kDebugMode) {
        debugPrint('📊 EMBEDDING MAP (will commit after B2 photo upload):');
        debugPrint('   Quality Score: ${features['qualityScore']}');
        debugPrint('   Embedding length: ${cleanEmbedding.length}');
        if (cleanEmbedding.isNotEmpty) {
          debugPrint(
            '   First 5 values: ${cleanEmbedding.take(5).map((v) => v.toStringAsFixed(4)).join(", ")}',
          );
        }
      }

      final checkStudent = await appDb
          .from('students')
          .select('id')
          .eq('id', studentId)
          .eq('institute_id', instituteId)
          .maybeSingle();

      if (checkStudent == null) {
        if (kDebugMode) debugPrint('❌ Student ID "$studentId" not found in students table!');
        return null;
      }

      return PreparedFaceRegistrationOnePhoto(embeddingPayload: embeddingPayload);
    } on DuplicateFaceRegistrationException {
      rethrow;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error preparing face registration: $e');
      return null;
    }
  }

  /// Single Supabase PATCH for [face_embedding] (+ [facePhotoUrl] when non-empty) after offline steps succeed.
  static Future<bool> commitFaceRegistrationOnePhoto({
    required String studentId,
    required String instituteId,
    required Map<String, dynamic> embeddingPayload,
    String? facePhotoUrl,
  }) async {
    if (kIsWeb) return false;

    try {
      final now = DateTime.now().toUtc().toIso8601String();
      final patch = <String, dynamic>{
        'face_embedding': embeddingPayload,
        'updated_at': now,
      };
      final trimmedUrl = facePhotoUrl?.trim();
      if (trimmedUrl != null && trimmedUrl.isNotEmpty) {
        patch['face_photo_url'] = trimmedUrl;
      }

      await appDb
          .from('students')
          .update(patch)
          .eq('id', studentId)
          .eq('institute_id', instituteId);

      await Future<void>.delayed(const Duration(milliseconds: 1200));

      for (var attempt = 1; attempt <= 3; attempt++) {
        final verifyRows = await appDb
            .from('students')
            .select('face_embedding')
            .eq('id', studentId)
            .eq('institute_id', instituteId)
            .limit(1);

        if (verifyRows.isEmpty) {
          if (kDebugMode) {
            debugPrint('❌ commit verify: student not found (attempt $attempt)');
          }
          await Future<void>.delayed(const Duration(milliseconds: 500));
          continue;
        }

        final savedFe = verifyRows.first['face_embedding'];
        if (registrationFaceEmbeddingFieldValid(savedFe)) {
          if (kDebugMode) debugPrint('✅ Face registration committed and verified on attempt $attempt');
          return true;
        }

        if (kDebugMode) debugPrint('⏳ commit verify attempt $attempt: embedding invalid or missing');
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }

      if (kDebugMode) debugPrint('❌ commitFaceRegistrationOnePhoto: embedding not confirmed after retries');
      return false;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ commitFaceRegistrationOnePhoto error: $e');
      return false;
    }
  }

  /// Persists embedding only (no registration photo URL). Prefer [prepareFaceRegistrationOnePhoto] + B2 + [commitFaceRegistrationOnePhoto].
  static Future<bool> saveFaceTemplate(
    String imagePath,
    String instituteId,
    String rollNumber,
    String studentId,
  ) async {
    if (kIsWeb) return false;

    try {
      final prepared = await prepareFaceRegistrationOnePhoto(
        imagePath,
        instituteId,
        rollNumber,
        studentId,
      );
      if (prepared == null) return false;
      return commitFaceRegistrationOnePhoto(
        studentId: studentId,
        instituteId: instituteId,
        embeddingPayload: prepared.embeddingPayload,
        facePhotoUrl: null,
      );
    } on DuplicateFaceRegistrationException {
      rethrow;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error in saveFaceTemplate: $e');
      return false;
    }
  }

  // Save multiple face templates (multi-angle registration)
  static Future<bool> saveMultiAngleFaceTemplates(
    List<String> imagePaths,
    String instituteId,
    String rollNumber,
    String studentId,
  ) async {
    if (kIsWeb) return false;

    try {
      final List<Map<String, dynamic>> templates = [];

      for (int i = 0; i < imagePaths.length; i++) {
        final features = await extractFaceFeatures(imagePaths[i]);
        if (features != null) {
          final embedding = await _extractNeuralEmbeddingInternal(imagePaths[i], features);
          if (embedding != null) {
            if (!registrationEmbeddingVectorValid(embedding)) {
              if (kDebugMode) {
                debugPrint(
                  '⚠️ Skipping angle $i: embedding invalid '
                  '(need ≥$kMobileFaceNetEmbeddingDimensions dims)',
                );
              }
            } else {
              templates.add({
                'angle': i,
                'embedding': embedding,
                'version': 2,
              });
              if (kDebugMode) debugPrint('✅ Extracted neural embedding for angle $i');
            }
          } else {
            if (kDebugMode) debugPrint('⚠️ Could not extract neural embedding for angle $i');
          }
        } else {
          if (kDebugMode) debugPrint('⚠️ Could not extract features for angle $i');
        }
      }

      if (templates.isEmpty) {
        if (kDebugMode) debugPrint('❌ No valid face templates extracted');
        return false;
      }

      final firstEmb = (templates[0]['embedding'] as List<dynamic>).cast<double>().toList();
      if (!registrationEmbeddingVectorValid(firstEmb)) {
        if (kDebugMode) {
          debugPrint(
            '❌ Face embedding missing or invalid for multi-angle registration '
            '(need ≥$kMobileFaceNetEmbeddingDimensions dims) — not sending to Supabase',
          );
        }
        return false;
      }

      // IMPORTANT: Pass first image path for photo hash checking
      final dupMulti = await _duplicateRegistrationBlockedMessageForEmbedding(
        firstEmb,
        instituteId,
        excludeStudentId: studentId,
        photoPath: imagePaths[0], // NEW: check first angle for exact duplicate
      );
      if (dupMulti != null) {
        throw DuplicateFaceRegistrationException(dupMulti);
      }

      // Calculate photo hash from first angle for exact duplicate detection
      final photoHash = await _calculatePhotoHash(imagePaths[0]);

      final now = DateTime.now().toUtc().toIso8601String();
      await appDb.from('students').update({
        'face_embedding': {
          'faceTemplates': templates,
          'embedding': templates[0]['embedding'],
          'photoHash': photoHash, // NEW: store hash for exact duplicate detection
          'version': 2,
          'modelVersion': 'mobilefacenet_tflite_v1',
          'multiAngleEnabled': true,
        },
        'updated_at': now,
      }).eq('id', studentId).eq('institute_id', instituteId);

      if (kDebugMode) {
        debugPrint('✅ Saved ${templates.length} face templates for Roll $rollNumber (multi-angle neural embeddings)');
      }
      return true;
    } on DuplicateFaceRegistrationException {
      rethrow;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error saving multi-angle face templates: $e');
      return false;
    }
  }

  static String _rollKey(dynamic userId, dynamic srNo) {
    final u = userId?.toString().trim() ?? '';
    if (u.isNotEmpty) return u;
    return srNo?.toString().trim() ?? '';
  }

  /// Best cosine similarity between [attendanceEmbedding] and this student's stored template(s).
  static double? _maxSimilarityForStudentRow(
    Map<String, dynamic> studentRow,
    List<double> attendanceEmbedding,
  ) {
    final fe = _faceTemplateMap(studentRow);

    // No template yet (null / non-map) — normal for students who have not registered a face.
    // Duplicate check loops the whole roster; do not log an error per row.
    if (fe == null) {
      return null;
    }

    if (kDebugMode) {
      debugPrint('   ✅ Face template found');
      debugPrint('      Version: ${fe['version']}');
      debugPrint('      Has embedding: ${fe['embedding'] != null}');
      debugPrint('      Has multiAngle: ${fe['multiAngleEnabled']}');
    }

    final multiAngleEnabled = fe['multiAngleEnabled'] as bool? ?? false;
    final faceTemplates = fe['faceTemplates'] as List<dynamic>?;

    if (multiAngleEnabled && faceTemplates != null && faceTemplates.isNotEmpty) {
      if (kDebugMode) debugPrint('   🔄 Using multi-angle templates (${faceTemplates.length} angles)');

      double bestSimilarity = 0.0;
      var any = false;
      for (final templateData in faceTemplates) {
        final templateMap = templateData as Map<String, dynamic>;
        final storedEmbedding = templateMap['embedding'] as List<dynamic>?;
        // ✅ FIX: Don't skip - parent object has version 2, templates are valid
        if (storedEmbedding == null) continue;
        any = true;
        final s = calculateCosineSimilarity(
          attendanceEmbedding,
          storedEmbedding.cast<double>().toList(),
        );
        if (s > bestSimilarity) bestSimilarity = s;
      }
      if (kDebugMode) {
        debugPrint('   📊 Multi-angle best similarity: ${(bestSimilarity * 100).toStringAsFixed(1)}%');
      }
      return any ? bestSimilarity : null;
    }

    final templateVersion = fe['version'] as int? ?? 1;
    if (templateVersion < 2) {
      if (kDebugMode) {
        debugPrint('   ❌ Face template version < 2 (current: $templateVersion) - not neural embedding');
      }
      return null;
    }

    final storedEmbedding = (fe['embedding'] as List<dynamic>?)?.cast<double>().toList();
    if (storedEmbedding == null) {
      if (kDebugMode) {
        debugPrint('   ❌ Embedding array is NULL in version 2 template');
        debugPrint('      Template keys: ${fe.keys.toList()}');
        debugPrint('      embedding value: ${fe['embedding']}');
        debugPrint('      embedding type: ${fe['embedding'].runtimeType}');
      }
      return null;
    }

    if (kDebugMode) {
      debugPrint('   ✅ Neural embedding found (${storedEmbedding.length} dimensions)');
      debugPrint('      Stored embedding type: ${storedEmbedding.runtimeType}');
      debugPrint('      First element type: ${storedEmbedding.isNotEmpty ? storedEmbedding[0].runtimeType : "N/A"}');

      if (storedEmbedding.isNotEmpty) {
        final firstTen = storedEmbedding.take(10).toList();
        debugPrint('      First 10 stored values: ${firstTen.map((v) => v.toStringAsFixed(4)).join(", ")}');

        // Check if stored embedding has non-zero values
        final hasNonZero = storedEmbedding.any((v) => v.abs() > 0.0001);
        if (!hasNonZero) {
          debugPrint('      ⚠️ WARNING: All stored embedding values are near zero!');
        }

        // Calculate L2 norm
        double norm = 0.0;
        for (final val in storedEmbedding) {
          norm += val * val;
        }
        norm = math.sqrt(norm);
        debugPrint('      L2 Norm: ${norm.toStringAsFixed(4)} (should be ~1.0 if L2-normalized)');
      }

      // Also log attendance embedding
      debugPrint('   📋 Attendance embedding:');
      debugPrint('      Type: ${attendanceEmbedding.runtimeType}');
      debugPrint('      Length: ${attendanceEmbedding.length}');
      if (attendanceEmbedding.isNotEmpty) {
        final firstTen = attendanceEmbedding.take(10).toList();
        debugPrint('      First 10 values: ${firstTen.map((v) => v.toStringAsFixed(4)).join(", ")}');

        double norm = 0.0;
        for (final val in attendanceEmbedding) {
          norm += val * val;
        }
        norm = math.sqrt(norm);
        debugPrint('      L2 Norm: ${norm.toStringAsFixed(4)}');
      }
    }

    final similarity = calculateCosineSimilarity(attendanceEmbedding, storedEmbedding);
    if (kDebugMode) {
      debugPrint('   📊 Similarity calculation: ${(similarity * 100).toStringAsFixed(1)}%');
      debugPrint('      Threshold: ${(_verificationThreshold * 100).toStringAsFixed(0)}%');
      if (similarity < _verificationThreshold) {
        debugPrint('      ❌ BELOW THRESHOLD - attendance will be rejected');
      } else {
        debugPrint('      ✅ ABOVE THRESHOLD - attendance will be accepted');
      }
    }
    return similarity;
  }

  /// User-facing error if [embedding] matches another student's template (same institute).
  /// [excludeStudentId]: allow re-saving the same student's face (edit flow).
  static Future<String?> duplicateRegistrationBlockedMessage(
    String imagePath,
    Map<String, dynamic> features,
    String instituteId, {
    String? excludeStudentId,
  }) async {
    if (kIsWeb) return null;
    final embedding = await _extractNeuralEmbeddingInternal(imagePath, features);
    if (embedding == null) return null;
    return _duplicateRegistrationBlockedMessageForEmbedding(
      embedding,
      instituteId,
      excludeStudentId: excludeStudentId,
      photoPath: imagePath, // NEW: pass image path for photo hash checking
    );
  }

  /// User-facing error if a captured embedding already matches another student
  /// in the same institute. Useful when a flow already has the embedding and not
  /// the original image path.
  static Future<String?> duplicateRegistrationBlockedMessageForEmbedding(
    List<double> embedding,
    String instituteId, {
    String? excludeStudentId,
  }) async {
    if (kIsWeb) return null;
    return _duplicateRegistrationBlockedMessageForEmbedding(
      embedding,
      instituteId,
      excludeStudentId: excludeStudentId,
    );
  }

  /// Calculate SHA256 hash of a photo file for duplicate detection
  static Future<String> _calculatePhotoHash(String photoPath) async {
    try {
      final file = File(photoPath);
      final bytes = await file.readAsBytes();
      return sha256.convert(bytes).toString();
    } catch (e) {
      if (kDebugMode) debugPrint('Error calculating photo hash: $e');
      return ''; // Empty hash if calculation fails
    }
  }

  static Future<String?> _duplicateRegistrationBlockedMessageForEmbedding(
    List<double> embedding,
    String instituteId, {
    String? excludeStudentId,
    String? photoPath, // for photo hash checking
  }) async {
    try {
      if (kDebugMode) {
        debugPrint('🔐 Registration Duplicate Check');
        debugPrint('   Institute ID: $instituteId');
        debugPrint('   Checking exact photo hash + same-face embedding match');
      }

      // ONLY CHECK: Exact photo duplicates (same file/image) - WITHIN SAME INSTITUTE ONLY
      // This is the ONLY check during registration - reliable and prevents cheating with same photo
      // NOTE: Same photo in DIFFERENT institutes is OK (each institute is isolated)
      if (photoPath != null && photoPath.isNotEmpty) {
        final photoHash = await _calculatePhotoHash(photoPath);
        if (photoHash.isNotEmpty) {
          // IMPORTANT: Only check within SAME institute (institute_id filtering)
          final hashRows = await appDb
              .from('students')
              .select('id, name, user_id, sr_no, face_embedding')
              .eq('institute_id', instituteId);  // ✅ INSTITUTE ISOLATED

          if (kDebugMode) {
            debugPrint('📷 Photo Hash Check: Checking ${hashRows.length} students in this institute');
          }

          for (final raw in hashRows) {
            final row = Map<String, dynamic>.from(raw as Map);
            final id = row['id']?.toString();
            if (excludeStudentId != null && id == excludeStudentId) continue;

            final faceData = row['face_embedding'];
            // Only check students who have registered a face
            if (faceData is Map && faceData['photoHash'] != null && faceData['photoHash'] == photoHash) {
              final rk = _rollKey(row['user_id'], row['sr_no']);
              final nm = (row['name'] as String?)?.trim() ?? '';
              final who = nm.isNotEmpty ? 'Roll $rk ($nm)' : 'Roll $rk';
              if (kDebugMode) {
                debugPrint('❌ EXACT PHOTO DUPLICATE: Same file registered for $who in THIS INSTITUTE');
              }
              return '⚠️ EXACT PHOTO DUPLICATE!\n\n'
                  'This exact photo is already registered for $who in this institute.\n\n'
                  'Please take a NEW FRESH photo of the student.';
            }
          }
        }
        if (kDebugMode) {
          debugPrint('✅ Photo hash check passed - no duplicate photo found');
        }
      }

      // SECOND CHECK: same person in a different photo (embedding similarity)
      final rows = await appDb
          .from('students')
          .select('id, name, user_id, sr_no, face_embedding')
          .eq('institute_id', instituteId);

      if (kDebugMode) {
        debugPrint('🧠 Embedding duplicate check: checking ${rows.length} students in this institute');
      }

      double bestSimilarity = 0.0;
      Map<String, dynamic>? bestMatch;

      for (final raw in rows) {
        final row = Map<String, dynamic>.from(raw as Map);
        final id = row['id']?.toString();
        if (excludeStudentId != null && id == excludeStudentId) continue;

        final sim = _maxSimilarityForStudentRow(row, embedding);
        if (sim != null && sim > bestSimilarity) {
          bestSimilarity = sim;
          bestMatch = row;
        }
      }

      if (bestMatch != null && bestSimilarity >= _registrationDuplicateThreshold) {
        final rk = _rollKey(bestMatch['user_id'], bestMatch['sr_no']);
        final nm = (bestMatch['name'] as String?)?.trim() ?? '';
        final who = nm.isNotEmpty ? 'Roll $rk ($nm)' : 'Roll $rk';
        if (kDebugMode) {
          debugPrint(
            '❌ SAME FACE DUPLICATE: matched $who at '
            '${(bestSimilarity * 100).toStringAsFixed(1)}%',
          );
        }
        return '⚠️ FACE ALREADY REGISTERED!\n\n'
            'This face already appears to be registered for $who in this institute.\n\n'
            'Please use the correct student record instead of creating a new one.';
      }

      if (bestMatch != null && bestSimilarity >= _registrationReviewThreshold) {
        final rk = _rollKey(bestMatch['user_id'], bestMatch['sr_no']);
        final nm = (bestMatch['name'] as String?)?.trim() ?? '';
        final who = nm.isNotEmpty ? 'Roll $rk ($nm)' : 'Roll $rk';
        if (kDebugMode) {
          debugPrint(
            '⚠️ POSSIBLE DUPLICATE: matched $who at '
            '${(bestSimilarity * 100).toStringAsFixed(1)}%',
          );
        }
        return '⚠️ POSSIBLE DUPLICATE FACE\n\n'
            'This face is quite similar to $who in this institute.\n\n'
            'Please retake all registration photos carefully. If it still matches, ask admin to review before creating a new student.';
      }

      if (kDebugMode) {
        debugPrint(
          '✅ Registration duplicate check complete - no matching registered face '
          '(best similarity ${(bestSimilarity * 100).toStringAsFixed(1)}%)',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ Registration duplicate check error (but allowing registration): $e');
      }
      // Allow registration even if duplicate check fails unexpectedly,
      // rather than blocking genuine students due to a transient error.
    }
    return null;
  }

  /// 1:1 verify selected roll + **reject if another enrolled student matches the photo better**
  /// (reduces using person B's face while roll A is selected).
  static Future<StudentFaceVerifyResult> verifyStudent(
    String attendancePhotoPath,
    String instituteId,
    String rollNumber,
  ) async {
    if (kIsWeb) {
      return StudentFaceVerifyResult.reject('Face verification is not available on web.');
    }

    final selectedKey = rollNumber.trim();
    String? tempPipelinePath;
    try {
      final work = await ensureNormalizedJpegForFacePipeline(attendancePhotoPath);
      if (work != attendancePhotoPath) {
        tempPipelinePath = work;
      }

      final attendanceFeatures = await extractFaceFeatures(work);
      if (attendanceFeatures == null) {
        if (kDebugMode) debugPrint('❌ Could not extract features from attendance photo');
        final reason = await getDiagnosticReasonForInvalidFace(work) ??
            'Face not accepted. Use good lighting, one person in frame, and look at the camera.';
        return StudentFaceVerifyResult.reject(reason);
      }

      final attendanceEmbedding = await _extractNeuralEmbeddingInternal(work, attendanceFeatures);
      if (attendanceEmbedding == null) {
        if (kDebugMode) debugPrint('❌ Could not extract neural embedding from attendance photo');
        return StudentFaceVerifyResult.reject(
          'Could not read face data. Please take a new photo, move closer, and try again.',
        );
      }

      if (kDebugMode) {
        debugPrint('✅ ATTENDANCE VERIFICATION - INSTITUTE ISOLATED');
        debugPrint('   Institute ID: $instituteId');
        debugPrint('   Looking for student: $selectedKey (ONLY in this institute)');
      }

      Map<String, dynamic>? studentData = await appDb
          .from('students')
          .select()
          .eq('institute_id', instituteId)  // ✅ INSTITUTE ISOLATED
          .eq('user_id', selectedKey)
          .maybeSingle();
      studentData ??= await appDb
          .from('students')
          .select()
          .eq('institute_id', instituteId)  // ✅ INSTITUTE ISOLATED
          .eq('sr_no', selectedKey)
          .maybeSingle();

      if (studentData == null) {
        if (kDebugMode) debugPrint('⚠️ Student with roll number $rollNumber not found');
        return StudentFaceVerifyResult.reject('Selected student was not found. Check roll number and try again.');
      }

      final simSelected = _maxSimilarityForStudentRow(studentData, attendanceEmbedding);
      if (simSelected == null) {
        if (kDebugMode) {
          debugPrint('⚠️⚠️⚠️ Student $rollNumber does NOT have a valid face template ⚠️⚠️⚠️');
          debugPrint('   ❌ Face embedding is missing or invalid');
          debugPrint('   📝 Action: Student needs to be registered with face first');
        }
        return StudentFaceVerifyResult.reject(
          'No face registered for this student. Register face first, then try again.',
        );
      }

      if (simSelected < _verificationThreshold) {
        if (kDebugMode) {
          debugPrint(
            '❌❌ FACE MISMATCH: ${(simSelected * 100).toStringAsFixed(1)}% '
            '(need ≥${(_verificationThreshold * 100).toStringAsFixed(0)}%)',
          );
          debugPrint('   This is NOT the registered student');
        }
        return StudentFaceVerifyResult.reject(
          'This photo does not match the selected student. Use the correct person or retake the photo.',
        );
      }

      if (kDebugMode) {
        debugPrint('✅✅✅ FACE MATCH VERIFIED ✅✅✅');
        debugPrint('   Match confidence: ${(simSelected * 100).toStringAsFixed(1)}%');
        debugPrint('   Student: $rollNumber - ${studentData['name']}');
        debugPrint('   ✅ ATTENDANCE WILL BE MARKED');
      }

      // Cross-student guard: another profile must not match this face better than the selected one.
      // INSTITUTE ISOLATED: Only check other students in THIS institute
      if (kDebugMode) {
        debugPrint('🔍 Cross-Student Check: Comparing against OTHER students in SAME institute only');
      }

      final rows = await appDb
          .from('students')
          .select('user_id, sr_no, face_embedding')
          .eq('institute_id', instituteId);  // ✅ INSTITUTE ISOLATED

      if (kDebugMode) {
        debugPrint('   Checking ${rows.length} other students in this institute');
      }

      double bestOtherSim = 0.0;
      String? bestOtherRoll;
      for (final row in rows) {
        final map = Map<String, dynamic>.from(row as Map);
        final otherKey = _rollKey(map['user_id'], map['sr_no']);
        if (otherKey.isEmpty || otherKey == selectedKey) continue;

        final sim = _maxSimilarityForStudentRow(map, attendanceEmbedding);
        if (sim != null && sim > bestOtherSim) {
          bestOtherSim = sim;
          bestOtherRoll = otherKey;
        }
      }

      // Keep this conservative so genuine students are not blocked too easily.
      const crossStudentMargin = 0.04;
      const crossStudentStrongMatch = 0.72;
      const ambiguousDuplicateGap = 0.015;
      final ambiguousCrossMatch =
          simSelected >= crossStudentStrongMatch &&
          bestOtherSim >= crossStudentStrongMatch &&
          (simSelected - bestOtherSim).abs() <= ambiguousDuplicateGap;
      if (bestOtherRoll != null &&
          (bestOtherSim >= _crossStudentHardBlockThreshold ||
              (bestOtherSim >= crossStudentStrongMatch &&
                  bestOtherSim > simSelected + crossStudentMargin) ||
              ambiguousCrossMatch)) {
        if (kDebugMode) {
          debugPrint(
            '❌ SECURITY: Face conflicts with another student '
            '(selected ${(simSelected * 100).toStringAsFixed(1)}% vs roll $bestOtherRoll ${(bestOtherSim * 100).toStringAsFixed(1)}%)',
          );
        }
        return StudentFaceVerifyResult.reject(
          'Wrong or duplicate student: this face also matches Roll $bestOtherRoll '
          'too closely compared with the selected Roll $selectedKey. '
          'Use the correct student record or re-register duplicate faces before marking attendance.',
        );
      }

      if (kDebugMode) {
        debugPrint(
          '✅ Face verified for Roll $selectedKey: ${(simSelected * 100).toStringAsFixed(1)}% '
          '(cross-check: no other student closer)',
        );
      }
      return const StudentFaceVerifyResult.match();
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error verifying student: $e');
      return StudentFaceVerifyResult.reject('Face check failed. Please try again.');
    } finally {
      if (tempPipelinePath != null) {
        try {
          await File(tempPipelinePath!).delete();
        } catch (_) {}
      }
    }
  }

  // Check if student has face template (by roll number)
  static Future<bool> hasFaceTemplate(String instituteId, String rollNumber) async {
    try {
      final key = rollNumber.trim();
      var data = await appDb
          .from('students')
          .select('face_embedding')
          .eq('institute_id', instituteId)
          .eq('user_id', key)
          .maybeSingle();
      data ??= await appDb
          .from('students')
          .select('face_embedding')
          .eq('institute_id', instituteId)
          .eq('sr_no', key)
          .maybeSingle();

      if (data == null) {
        if (kDebugMode) debugPrint('⚠️ Student with roll number $rollNumber not found');
        return false;
      }

      final fe = _faceTemplateMap(data);
      final hasSingleTemplate = fe != null && fe['embedding'] != null;
      final hasMultiAngle = (fe?['multiAngleEnabled'] as bool? ?? false) &&
          ((fe?['faceTemplates'] as List<dynamic>?)?.isNotEmpty ?? false);

      return hasSingleTemplate || hasMultiAngle;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error checking face template: $e');
      return false;
    }
  }
}
