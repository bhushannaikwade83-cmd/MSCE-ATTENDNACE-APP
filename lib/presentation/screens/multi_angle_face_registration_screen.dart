import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/material.dart';

import '../widgets/face_scanner_widget.dart';
import '../../services/anti_spoof_service.dart';
import '../../services/face_recognition_service.dart';
import '../../services/image_quality_service.dart';
import '../../services/photo_compression_service.dart';

/// Guided multi-angle registration flow.
/// Student captures FRONT, LEFT, RIGHT from stable camera preview,
/// then the app validates and duplicate-checks those frames before returning.
class MultiAngleFaceRegistrationScreen extends StatefulWidget {
  static const routeName = '/multi-angle-face-registration';

  final String studentName;
  final String rollNumber;
  final String instituteId;

  const MultiAngleFaceRegistrationScreen({
    super.key,
    required this.studentName,
    required this.rollNumber,
    required this.instituteId,
  });

  @override
  State<MultiAngleFaceRegistrationScreen> createState() =>
      _MultiAngleFaceRegistrationScreenState();
}

class _MultiAngleFaceRegistrationScreenState
    extends State<MultiAngleFaceRegistrationScreen> {
  bool _isProcessing = false;
  String? _processingMessage;
  int _scannerSession = 0;

  static const double _frontYawMax = 10.0;
  static const double _sideYawMin = 40.0;
  static const double _sideYawMax = 72.0;
  static const double _rollMax = 12.0;

  @override
  void initState() {
    super.initState();
    if (kDebugMode) {
      debugPrint(
        '📸 Guided multi-angle registration started for: ${widget.studentName}',
      );
    }
  }

  String? _angleErrorMessage(String angle, Map<String, dynamic> features) {
    final rawYaw = (features['headEulerAngleY'] as num?)?.toDouble() ?? 0.0;
    final yaw = -rawYaw;
    final roll = (features['headEulerAngleZ'] as num?)?.toDouble() ?? 0.0;

    if (kDebugMode) {
      debugPrint(
        '📐 Registration angle check [$angle] rawYaw=$rawYaw effectiveYaw=$yaw roll=$roll',
      );
    }

    if (roll.abs() > _rollMax) {
      return 'Keep your head upright. Do not tilt sideways during $angle capture.';
    }

    switch (angle) {
      case 'left':
        if (yaw > -_sideYawMin) {
          return 'Turn your head more to the LEFT. A strong side pose is needed here.';
        }
        if (yaw < -_sideYawMax) {
          return 'You turned too far LEFT. Keep one eye and the nose slightly visible.';
        }
        return null;
      case 'front':
        if (yaw.abs() > _frontYawMax) {
          return 'Look straight at the camera for the FRONT photo.';
        }
        return null;
      case 'right':
        if (yaw < _sideYawMin) {
          return 'Turn your head more to the RIGHT. A strong side pose is needed here.';
        }
        if (yaw > _sideYawMax) {
          return 'You turned too far RIGHT. Keep one eye and the nose slightly visible.';
        }
        return null;
      default:
        return null;
    }
  }

  Future<File> _processCapturedPhoto(String photoPath, String angle) async {
    var photoFile = File(photoPath);
    String? tempNormalized;
    final workPath = await FaceRecognitionService.ensureNormalizedJpegForFacePipeline(photoFile.path);
    if (workPath != photoFile.path) {
      tempNormalized = workPath;
      photoFile = File(workPath);
    }

    try {
    if (mounted) {
      setState(() {
        _processingMessage = '🔍 Validating ${angle.toUpperCase()} photo...';
      });
    }

    var faceFeatures =
        await FaceRecognitionService.extractFaceFeaturesForRegistrationAngle(
      photoFile.path,
      angle,
    );
    if (faceFeatures == null || faceFeatures.isEmpty) {
      final why = await FaceRecognitionService.getDiagnosticReasonForRegistrationAngle(
            photoFile.path,
            angle,
          ) ??
          (angle == 'front'
              ? 'Front face was not clear enough. Use good lighting, one person, eyes visible.'
              : 'Side face was not clear enough. Keep one eye and the nose in view for this angle.');
      throw Exception(why);
    }

    final angleError = _angleErrorMessage(angle, faceFeatures);
    if (angleError != null) {
      throw Exception(angleError);
    }

    if (mounted) {
      setState(() {
        _processingMessage = '🛡️ Checking ${angle.toUpperCase()} photo for spoofing...';
      });
    }
    final antiSpoofResult = await AntiSpoofService.checkSpoof(photoFile.path);
    if (!antiSpoofResult.isReal) {
      throw Exception(
        '${antiSpoofResult.reason}\n\nPlease register with a real person, not a printed photo or screen.',
      );
    }

    if (mounted) {
      setState(() {
        _processingMessage = '📊 Checking ${angle.toUpperCase()} photo quality...';
      });
    }
    final qualityResult = await ImageQualityService.checkQuality(photoFile.path);
    if (!qualityResult.isGood) {
      throw Exception(
        '${qualityResult.reason}\n\nUse good lighting, clear focus, and avoid blur or shadows.',
      );
    }

    if (mounted) {
      setState(() {
        _processingMessage = '🗜️ Optimizing ${angle.toUpperCase()} photo...';
      });
    }
    final compressResult =
        await PhotoCompressionService.compressAndValidate(photoFile.path);
    if (!compressResult.isValid) {
      throw Exception('${compressResult.reason}\n\nPlease retake the photo.');
    }

    final extIndex = photoFile.path.lastIndexOf('.');
    final compressedPath = extIndex == -1
        ? '${photoFile.path}_compressed.jpg'
        : '${photoFile.path.substring(0, extIndex)}_compressed${photoFile.path.substring(extIndex)}';
    final compressedFile = File(compressedPath);
    await compressedFile.writeAsBytes(compressResult.bytes);
    return compressedFile;
    } finally {
      if (tempNormalized != null) {
        try {
          await File(tempNormalized).delete();
        } catch (_) {}
      }
    }
  }

  Future<Map<String, dynamic>> _extractFaceFeatures(
    File photoFile,
    String angle,
  ) async {
    try {
      final features =
          await FaceRecognitionService.extractFaceFeaturesForRegistrationAngle(
        photoFile.path,
        angle,
      );
      return features ?? {};
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Feature extraction error ($angle): $e');
      return {};
    }
  }

  Future<void> _restartScannerWithError(String title, String message) async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Try Again'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    setState(() {
      _isProcessing = false;
      _processingMessage = null;
      _scannerSession++;
    });
  }

  Future<void> _handleScannedImages(List<String> imagePaths) async {
    if (_isProcessing) return;
    if (imagePaths.length < 3) {
      await _restartScannerWithError(
        '❌ Capture incomplete',
        'Front, left, and right photos are required. Please try again.',
      );
      return;
    }

    setState(() {
      _isProcessing = true;
      _processingMessage = '🧠 Preparing captured photos...';
    });

    try {
      // FaceScannerWidget returns images in FRONT, LEFT, RIGHT order.
      final frontPhoto = await _processCapturedPhoto(imagePaths[0], 'front');
      final leftPhoto = await _processCapturedPhoto(imagePaths[1], 'left');
      final rightPhoto = await _processCapturedPhoto(imagePaths[2], 'right');

      if (kDebugMode) {
        debugPrint('🔐 Starting duplicate check for guided registration');
        debugPrint('   Institute: ${widget.instituteId}');
        debugPrint('   Student: ${widget.studentName} (${widget.rollNumber})');
      }

      setState(() => _processingMessage = '🧠 Extracting LEFT face data...');
      final leftFeatures = await _extractFaceFeatures(leftPhoto, 'left');
      if (leftFeatures.isEmpty) {
        final msg = await FaceRecognitionService.getDiagnosticReasonForRegistrationAngle(
              leftPhoto.path,
              'left',
            ) ??
            'Could not extract face from LEFT photo. Check lighting and turn further left as guided.';
        throw Exception(msg);
      }

      setState(() => _processingMessage = '🧠 Extracting FRONT face data...');
      final frontFeatures = await _extractFaceFeatures(frontPhoto, 'front');
      if (frontFeatures.isEmpty) {
        final msg = await FaceRecognitionService.getDiagnosticReasonForRegistrationAngle(
              frontPhoto.path,
              'front',
            ) ??
            'Could not extract face from FRONT photo. Look straight at the camera with eyes open.';
        throw Exception(msg);
      }

      setState(() => _processingMessage = '🧠 Extracting RIGHT face data...');
      final rightFeatures = await _extractFaceFeatures(rightPhoto, 'right');
      if (rightFeatures.isEmpty) {
        final msg = await FaceRecognitionService.getDiagnosticReasonForRegistrationAngle(
              rightPhoto.path,
              'right',
            ) ??
            'Could not extract face from RIGHT photo. Check lighting and turn further right as guided.';
        throw Exception(msg);
      }

      setState(() => _processingMessage = '📊 Checking LEFT face for duplicates...');
      final leftDupMsg =
          await FaceRecognitionService.duplicateRegistrationBlockedMessage(
        leftPhoto.path,
        leftFeatures,
        widget.instituteId,
      );

      setState(
        () => _processingMessage = '📊 Checking FRONT face for duplicates...',
      );
      final frontDupMsg =
          await FaceRecognitionService.duplicateRegistrationBlockedMessage(
        frontPhoto.path,
        frontFeatures,
        widget.instituteId,
      );

      setState(
        () => _processingMessage = '📊 Checking RIGHT face for duplicates...',
      );
      final rightDupMsg =
          await FaceRecognitionService.duplicateRegistrationBlockedMessage(
        rightPhoto.path,
        rightFeatures,
        widget.instituteId,
      );

      final errorMessages = <String>[];
      if (leftDupMsg != null) errorMessages.add('LEFT: $leftDupMsg');
      if (frontDupMsg != null) errorMessages.add('FRONT: $frontDupMsg');
      if (rightDupMsg != null) errorMessages.add('RIGHT: $rightDupMsg');

      if (errorMessages.isNotEmpty) {
        await _restartScannerWithError(
          '❌ Registration Blocked',
          errorMessages.join('\n\n'),
        );
        return;
      }

      if (!mounted) return;
      setState(() => _processingMessage = '✅ All checks passed!');
      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;

      Navigator.of(context).pop({
        'success': true,
        'leftPhoto': leftPhoto.path,
        'frontPhoto': frontPhoto.path,
        'rightPhoto': rightPhoto.path,
        'leftFeatures': leftFeatures,
        'frontFeatures': frontFeatures,
        'rightFeatures': rightFeatures,
      });
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Registration processing error: $e');
      await _restartScannerWithError('❌ Registration capture failed', '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isProcessing,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_isProcessing) return;
        Navigator.of(context).pop({'success': false});
      },
      child: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: FaceScannerWidget(
                key: ValueKey('registration-scanner-$_scannerSession'),
                title: 'Guided Face Registration',
                subtitle:
                    'Use preview to capture Front, Left, and Right. The app will verify them after capture.',
                autoCapture: false,
                multiAngleMode: false,
                simpleMode: true,
                onFaceScanned: (_) {},
                onMultiAngleScanned: _handleScannedImages,
              ),
            ),
            if (_isProcessing)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.72),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(color: Colors.white),
                          const SizedBox(height: 18),
                          Text(
                            _processingMessage ?? 'Processing captured photos...',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
