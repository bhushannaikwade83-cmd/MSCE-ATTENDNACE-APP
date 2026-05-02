import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

/// Anti-Spoof Detection Service
/// Detects printed photos, deepfakes, and other 2D spoofing attempts
class AntiSpoofService {
  static Interpreter? _interpreter;
  static bool _isInitialized = false;

  /// Initialize the TensorFlow Lite model
  static Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      if (kDebugMode) debugPrint('🔄 Loading anti-spoof TensorFlow Lite model...');

      _interpreter = await Interpreter.fromAsset(
        'assets/models/anti_spoof_model.tflite',
      );

      _isInitialized = true;
      if (kDebugMode) debugPrint('✅ Anti-spoof model loaded');
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to load anti-spoof model: $e');
        debugPrint('⚠️ Continuing without anti-spoof detection');
      }
      _isInitialized = false;
    }
  }

  /// Check if photo is real (3D face) or fake (2D/printed)
  /// Returns confidence score: 0.0 (definitely fake) to 1.0 (definitely real)
  static Future<AntiSpoofResult> checkSpoof(String photoPath) async {
    try {
      // If model not loaded, skip anti-spoof check
      if (!_isInitialized || _interpreter == null) {
        if (kDebugMode) {
          debugPrint('⚠️ Anti-spoof model not available, skipping check');
        }
        return AntiSpoofResult(
          isReal: true,
          confidence: 0.5,
          reason: 'Anti-spoof model not available',
        );
      }

      if (kDebugMode) debugPrint('🔍 Performing anti-spoof check...');

      // Read and preprocess image
      final file = File(photoPath);
      final bytes = await file.readAsBytes();
      final image = img.decodeImage(bytes);

      if (image == null) {
        return AntiSpoofResult(
          isReal: false,
          confidence: 0.0,
          reason: 'Failed to decode image',
        );
      }

      // Resize to model input size (usually 224x224 or 320x320)
      final resized = img.copyResize(image, width: 224, height: 224);

      // Normalize image
      final input = _normalizeImage(resized);

      // Run inference
      var output = List.filled(2, 0.0).reshape([1, 2]);
      _interpreter!.run(input, output);

      // Extract confidence scores
      final fakeScore = output[0][0] as double;
      final realScore = output[0][1] as double;

      // Normalize to 0-1 range
      final total = fakeScore + realScore;
      final realConfidence = realScore / total;

      // Threshold: > 0.5 = real, < 0.5 = fake
      final isReal = realConfidence > 0.5;

      if (kDebugMode) {
        debugPrint('📊 Anti-spoof Results:');
        debugPrint('   Real Confidence: ${(realConfidence * 100).toStringAsFixed(1)}%');
        debugPrint('   Fake Confidence: ${(fakeScore / total * 100).toStringAsFixed(1)}%');
        debugPrint('   Is Real: $isReal');
      }

      final reason = isReal
          ? 'Detected real 3D face ✅'
          : 'Detected printed/fake photo ❌';

      return AntiSpoofResult(
        isReal: isReal,
        confidence: realConfidence,
        reason: reason,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Anti-spoof check failed: $e');
      return AntiSpoofResult(
        isReal: false,
        confidence: 0.0,
        reason: 'Error: $e',
      );
    }
  }

  /// Normalize image for TensorFlow Lite model
  static List<List<List<List<double>>>> _normalizeImage(img.Image image) {
    final height = image.height;
    final width = image.width;

    final input = List<List<List<List<double>>>>.generate(
      1,
      (i) => List<List<List<double>>>.generate(
        height,
        (j) => List<List<double>>.generate(
          width,
          (k) {
            final pixel = image.getPixelSafe(k, j);
            // Extract RGB from pixel (image v4.8.0 API)
            final r = pixel.r as int;
            final g = pixel.g as int;
            final b = pixel.b as int;

            // Normalize to 0-1
            return <double>[
              r / 255.0,
              g / 255.0,
              b / 255.0,
            ];
          },
        ),
      ),
    );

    return input;
  }

  static void dispose() {
    _interpreter?.close();
    _isInitialized = false;
  }
}

/// Anti-spoof detection result
class AntiSpoofResult {
  final bool isReal; // true = real 3D face, false = fake/printed
  final double confidence; // 0.0 to 1.0
  final String reason;

  AntiSpoofResult({
    required this.isReal,
    required this.confidence,
    required this.reason,
  });
}
