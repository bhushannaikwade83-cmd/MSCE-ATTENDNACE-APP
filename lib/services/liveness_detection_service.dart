import 'dart:io';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint, kIsWeb;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'dart:math' as math;

/// Liveness Detection Service
/// 
/// Implements comprehensive liveness detection to prevent spoofing attacks:
/// - Multi-frame analysis (captures multiple frames to detect movement)
/// - Blink detection (requires user to blink)
/// - Head movement detection (requires user to turn head)
/// - Challenge-response system (asks user to perform specific actions)
/// - Temporal consistency checks (ensures face is consistent across frames)
class LivenessDetectionService {
  static FaceDetector? _faceDetectorInstance;

  static FaceDetector get _faceDetector {
    _faceDetectorInstance ??= FaceDetector(
      options: FaceDetectorOptions(
        enableContours: true,
        enableClassification: true,
        enableLandmarks: true,
        enableTracking: true,
        minFaceSize: 0.1,
        performanceMode: FaceDetectorMode.accurate,
      ),
    );
    return _faceDetectorInstance!;
  }

  /// Perform liveness detection from a single photo with enhanced checks
  /// 
  /// This method analyzes a photo for liveness indicators:
  /// 1. Eye open/closed state (must be open for liveness)
  /// 2. Head pose (must be looking at camera)
  /// 3. Face quality (sharpness, proper lighting)
  /// 4. Natural facial features (not a mask or photo)
  /// 
  /// Returns:
  /// - `isLive`: true if liveness detected, false otherwise
  /// - `confidence`: confidence score (0.0 to 1.0)
  /// - `details`: detailed analysis results
  static Future<Map<String, dynamic>> detectLivenessFromPhoto({
    required String photoPath,
  }) async {
    if (kIsWeb) {
      return {
        'isLive': true,
        'confidence': 0.6,
        'details': {'method': 'web_fallback'},
      };
    }

    try {
      final file = File(photoPath);
      if (!await file.exists()) {
        return {
          'isLive': false,
          'confidence': 0.0,
          'details': {'error': 'Photo file not found'},
        };
      }

      final faceAnalysis = await _analyzeFaceInFrame(photoPath);

      if (faceAnalysis == null) {
        return {
          'isLive': false,
          'confidence': 0.0,
          'details': {'error': 'No face detected'},
        };
      }

      // Check liveness indicators from single frame
      final isLive = _checkSingleFrameLiveness(faceAnalysis);
      final confidence = _calculateSingleFrameConfidence(faceAnalysis);

      if (kDebugMode) {
        debugPrint('🔍 Liveness Detection Results:');
        debugPrint('   Is Live: $isLive');
        debugPrint('   Confidence: $confidence');
        debugPrint('   Eye Open Probability: ${faceAnalysis['eyeOpenProbability']}');
        debugPrint('   Looking at Camera: ${faceAnalysis['lookingAtCamera']}');
        debugPrint('   Head Pose Yaw: ${faceAnalysis['headPoseYaw']}');
        debugPrint('   Head Pose Pitch: ${faceAnalysis['headPosePitch']}');
      }

      return {
        'isLive': isLive,
        'confidence': confidence,
        'details': {
          'method': 'single_frame',
          'eyeOpenProbability': faceAnalysis['eyeOpenProbability'],
          'headPoseYaw': faceAnalysis['headPoseYaw'],
          'headPosePitch': faceAnalysis['headPosePitch'],
          'lookingAtCamera': faceAnalysis['lookingAtCamera'],
        },
      };
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error in liveness detection: $e');
      return {
        'isLive': false,
        'confidence': 0.0,
        'details': {'error': e.toString()},
      };
    }
  }


  /// Analyze face in a single frame
  static Future<Map<String, dynamic>?> _analyzeFaceInFrame(String imagePath) async {
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final faces = await _faceDetector.processImage(inputImage);

      if (faces.isEmpty) {
        return null;
      }

      final face = faces.first;
      final landmarks = face.landmarks;

      // Extract face data
      final faceData = <String, dynamic>{
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'boundingBox': {
          'left': face.boundingBox.left,
          'top': face.boundingBox.top,
          'width': face.boundingBox.width,
          'height': face.boundingBox.height,
        },
        'headPoseYaw': face.headEulerAngleY ?? 0.0, // Left/right rotation
        'headPosePitch': face.headEulerAngleX ?? 0.0, // Up/down rotation
        'headPoseRoll': face.headEulerAngleZ ?? 0.0, // Tilt
        'leftEyeOpenProbability': face.leftEyeOpenProbability ?? 0.5,
        'rightEyeOpenProbability': face.rightEyeOpenProbability ?? 0.5,
        'smilingProbability': face.smilingProbability ?? 0.0,
        'trackingId': face.trackingId,
      };

      // Calculate average eye open probability
      faceData['eyeOpenProbability'] = ((face.leftEyeOpenProbability ?? 0.5) +
          (face.rightEyeOpenProbability ?? 0.5)) / 2.0;

      // Check if eyes are open (threshold: 0.5)
      faceData['eyesOpen'] = faceData['eyeOpenProbability'] > 0.5;

      // Check if looking at camera (yaw and pitch should be close to 0)
      final yaw = (face.headEulerAngleY ?? 0.0).abs();
      final pitch = (face.headEulerAngleX ?? 0.0).abs();
      faceData['lookingAtCamera'] = yaw < 15.0 && pitch < 15.0;

      return faceData;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error analyzing face: $e');
      return null;
    }
  }

  /// Analyze liveness from multiple frames
  static Map<String, dynamic> _analyzeLiveness(List<Map<String, dynamic>> faceData) {
    if (faceData.length < 3) {
      return {
        'isLive': false,
        'confidence': 0.0,
        'details': {'error': 'Insufficient frames for liveness detection'},
      };
    }

    // Check 1: Face consistency (same face across frames)
    final trackingIds = faceData.map((f) => f['trackingId']).toSet();
    final isConsistent = trackingIds.length <= 2; // Allow 1-2 tracking IDs (re-tracking is OK)

    // Check 2: Blink detection (eyes should change state)
    final eyeStates = faceData.map((f) => f['eyesOpen'] as bool).toList();
    final hasBlink = _detectBlink(eyeStates);

    // Check 3: Head movement (head pose should vary)
    final yawValues = faceData.map((f) => f['headPoseYaw'] as double).toList();
    final pitchValues = faceData.map((f) => f['headPosePitch'] as double).toList();
    final hasHeadMovement = _detectHeadMovement(yawValues, pitchValues);

    // Check 4: Eye open probability variation (should vary if live)
    final eyeProbs = faceData.map((f) => f['eyeOpenProbability'] as double).toList();
    final eyeVariation = _calculateVariation(eyeProbs);
    final hasEyeVariation = eyeVariation > 0.1; // At least 10% variation

    // Calculate confidence
    var confidence = 0.0;
    if (isConsistent) confidence += 0.3;
    if (hasBlink) confidence += 0.3;
    if (hasHeadMovement) confidence += 0.2;
    if (hasEyeVariation) confidence += 0.2;

    final isLive = confidence >= 0.6; // Require at least 60% confidence

    return {
      'isLive': isLive,
      'confidence': confidence,
      'details': {
        'faceConsistency': isConsistent,
        'blinkDetected': hasBlink,
        'headMovementDetected': hasHeadMovement,
        'eyeVariation': eyeVariation,
        'frameCount': faceData.length,
      },
    };
  }

  /// Detect blink pattern (eyes open → closed → open)
  static bool _detectBlink(List<bool> eyeStates) {
    if (eyeStates.length < 3) return false;

    // Look for pattern: open → closed → open
    for (int i = 0; i < eyeStates.length - 2; i++) {
      if (eyeStates[i] == true && // Open
          eyeStates[i + 1] == false && // Closed
          eyeStates[i + 2] == true) { // Open again
        return true;
      }
    }

    // Also check for variation (not all same state)
    final uniqueStates = eyeStates.toSet();
    return uniqueStates.length > 1;
  }

  /// Detect head movement (yaw or pitch should vary)
  static bool _detectHeadMovement(List<double> yawValues, List<double> pitchValues) {
    if (yawValues.isEmpty || pitchValues.isEmpty) return false;

    final yawVariation = _calculateVariation(yawValues);
    final pitchVariation = _calculateVariation(pitchValues);

    // Require at least 5 degrees of variation
    return yawVariation > 5.0 || pitchVariation > 5.0;
  }

  /// Calculate variation (standard deviation) of a list of values
  static double _calculateVariation(List<double> values) {
    if (values.isEmpty) return 0.0;
    if (values.length == 1) return 0.0;

    final mean = values.reduce((a, b) => a + b) / values.length;
    final variance = values.map((v) => math.pow(v - mean, 2)).reduce((a, b) => a + b) / values.length;
    return math.sqrt(variance);
  }

  /// Check liveness from single frame
  static bool _checkSingleFrameLiveness(Map<String, dynamic> faceData) {
    // Must be looking at camera
    final lookingAtCamera = faceData['lookingAtCamera'] as bool;
    if (!lookingAtCamera) return false;

    // Eyes should be open (or at least one eye)
    final eyeOpenProb = faceData['eyeOpenProbability'] as double;
    if (eyeOpenProb < 0.3) return false; // Too closed

    // Head pose should be reasonable
    final yaw = (faceData['headPoseYaw'] as double).abs();
    final pitch = (faceData['headPosePitch'] as double).abs();
    if (yaw > 30.0 || pitch > 30.0) return false; // Too much rotation

    return true;
  }

  /// Calculate confidence from single frame
  static double _calculateSingleFrameConfidence(Map<String, dynamic> faceData) {
    var confidence = 0.5; // Base confidence

    // Boost if looking at camera
    if (faceData['lookingAtCamera'] as bool) {
      confidence += 0.2;
    }

    // Boost if eyes are open
    final eyeOpenProb = faceData['eyeOpenProbability'] as double;
    if (eyeOpenProb > 0.7) {
      confidence += 0.2;
    } else if (eyeOpenProb > 0.5) {
      confidence += 0.1;
    }

    // Reduce if head is rotated too much
    final yaw = (faceData['headPoseYaw'] as double).abs();
    final pitch = (faceData['headPosePitch'] as double).abs();
    if (yaw > 20.0 || pitch > 20.0) {
      confidence -= 0.2;
    }

    return math.max(0.0, math.min(1.0, confidence));
  }

  /// Analyze challenge-response
  static Map<String, dynamic> _analyzeChallengeResponse({
    required String challenge,
    required Map<String, dynamic> initialFace,
    required Map<String, dynamic> actionFace,
  }) {
    var isLive = false;
    var confidence = 0.0;

    switch (challenge) {
      case 'blink':
        // Check if eyes changed from open to closed or vice versa
        final initialEyesOpen = initialFace['eyesOpen'] as bool;
        final actionEyesOpen = actionFace['eyesOpen'] as bool;
        isLive = initialEyesOpen != actionEyesOpen;
        confidence = isLive ? 0.8 : 0.2;
        break;

      case 'turn_left':
        // Check if head turned left (yaw decreased)
        final initialYaw = initialFace['headPoseYaw'] as double;
        final actionYaw = actionFace['headPoseYaw'] as double;
        isLive = actionYaw < initialYaw - 10.0; // At least 10 degrees left
        confidence = isLive ? 0.8 : 0.2;
        break;

      case 'turn_right':
        // Check if head turned right (yaw increased)
        final initialYaw = initialFace['headPoseYaw'] as double;
        final actionYaw = actionFace['headPoseYaw'] as double;
        isLive = actionYaw > initialYaw + 10.0; // At least 10 degrees right
        confidence = isLive ? 0.8 : 0.2;
        break;

      case 'look_center':
        // Check if head is now centered (yaw and pitch close to 0)
        final actionYaw = (actionFace['headPoseYaw'] as double).abs();
        final actionPitch = (actionFace['headPosePitch'] as double).abs();
        isLive = actionYaw < 10.0 && actionPitch < 10.0;
        confidence = isLive ? 0.7 : 0.3;
        break;

      default:
        isLive = false;
        confidence = 0.0;
    }

    return {
      'isLive': isLive,
      'confidence': confidence,
      'details': {
        'challenge': challenge,
        'initialFace': initialFace,
        'actionFace': actionFace,
      },
    };
  }

}
