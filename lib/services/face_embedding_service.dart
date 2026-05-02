import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

/// Face Embedding Service
/// Extracts 192-dimensional face embeddings from photos using MobileFaceNet
/// Used for face matching during attendance verification
class FaceEmbeddingService {
  static Interpreter? _interpreter;
  static const int EMBEDDING_SIZE = 192; // MobileFaceNet outputs 192-dim vectors
  static const int INPUT_SIZE = 112; // MobileFaceNet expects 112x112 input

  /// Initialize the interpreter (load TFLite model)
  static Future<void> initialize() async {
    if (_interpreter != null) return;

    try {
      if (kDebugMode) debugPrint('📦 Loading MobileFaceNet model...');
      _interpreter = await Interpreter.fromAsset('assets/models/mobilefacenet.tflite');
      if (kDebugMode) debugPrint('✅ MobileFaceNet model loaded successfully');
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Failed to load MobileFaceNet: $e');
      rethrow;
    }
  }

  /// Extract face embedding from a photo
  /// Returns 192-dimensional vector for face matching
  /// [faceFeatures]: Optional face detection features to crop face region and ignore background
  static Future<List<double>> extractEmbedding(String photoPath, {Map<String, dynamic>? faceFeatures}) async {
    try {
      if (_interpreter == null) {
        await initialize();
      }

      // Read and preprocess image
      if (kDebugMode) debugPrint('🖼️ Reading image: $photoPath');
      final imageFile = File(photoPath);
      if (!await imageFile.exists()) {
        throw Exception('Image file not found: $photoPath');
      }

      final imageBytes = await imageFile.readAsBytes();
      var image = img.decodeImage(imageBytes);

      if (image == null) {
        throw Exception('Failed to decode image');
      }

      if (kDebugMode) {
        debugPrint('📐 Original size: ${image.width}x${image.height}');
      }

      // Crop to face region if features provided (ignore background)
      if (faceFeatures != null && faceFeatures['boundingBox'] != null) {
        final bbox = faceFeatures['boundingBox'] as Map<String, dynamic>;
        final left = (bbox['left'] as num?)?.toInt() ?? 0;
        final top = (bbox['top'] as num?)?.toInt() ?? 0;
        final width = (bbox['width'] as num?)?.toInt() ?? image.width;
        final height = (bbox['height'] as num?)?.toInt() ?? image.height;

        // Add 20% padding around face for better context
        final padLeft = (left * 0.2).toInt();
        final padTop = (top * 0.2).toInt();
        final padWidth = (width * 1.4).toInt();
        final padHeight = (height * 1.4).toInt();

        final cropLeft = (left - padLeft).clamp(0, image.width);
        final cropTop = (top - padTop).clamp(0, image.height);
        final cropWidth = (padWidth).clamp(0, image.width - cropLeft);
        final cropHeight = (padHeight).clamp(0, image.height - cropTop);

        image = img.copyCrop(image, x: cropLeft, y: cropTop, width: cropWidth, height: cropHeight);

        if (kDebugMode) {
          debugPrint('🎯 Face region cropped (ignoring background)');
          debugPrint('   Crop area: ${cropLeft}x${cropTop} ${cropWidth}x${cropHeight}');
        }
      }

      // Resize to 112x112 (MobileFaceNet input size)
      image = img.copyResize(image, width: INPUT_SIZE, height: INPUT_SIZE);

      // Convert to RGB if needed
      if (image.numChannels == 4) {
        // RGBA -> RGB
        final rgbImage = img.Image(width: image.width, height: image.height, numChannels: 3);
        for (int y = 0; y < image.height; y++) {
          for (int x = 0; x < image.width; x++) {
            final pixel = image.getPixelSafe(x, y);
            rgbImage.setPixelRgba(x, y, pixel.toInt() >> 16 & 0xff, pixel.toInt() >> 8 & 0xff, pixel.toInt() & 0xff, 255);
          }
        }
        image = rgbImage;
      }

      // Normalize to [0, 1] range and convert to input tensor
      final inputArray = List.filled(INPUT_SIZE * INPUT_SIZE * 3, 0.0);
      var pixelIndex = 0;
      for (int y = 0; y < image.height; y++) {
        for (int x = 0; x < image.width; x++) {
          final pixel = image.getPixelSafe(x, y);
          // Extract RGB components from pixel
          final r = (pixel.toInt() >> 16) & 0xff;
          final g = (pixel.toInt() >> 8) & 0xff;
          final b = pixel.toInt() & 0xff;

          // Normalize RGB values to [0, 1]
          inputArray[pixelIndex++] = r / 255.0;
          inputArray[pixelIndex++] = g / 255.0;
          inputArray[pixelIndex++] = b / 255.0;
        }
      }

      // Reshape for interpreter: [1, 112, 112, 3]
      final input = inputArray.reshape([1, INPUT_SIZE, INPUT_SIZE, 3]);

      // Run inference
      if (kDebugMode) debugPrint('🔄 Running face embedding extraction...');
      final output = List<double>.filled(EMBEDDING_SIZE, 0.0);
      _interpreter!.run(input, output);

      if (kDebugMode) {
        debugPrint('✅ Embedding extracted (192-dim vector)');
        debugPrint('   Vector sample: ${output.take(5).join(", ")}...');
      }

      return output;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Embedding extraction failed: $e');
      rethrow;
    }
  }

  /// Compare two embeddings using cosine similarity
  /// Returns score 0.0 (different) to 1.0 (identical)
  /// Typical thresholds:
  /// - > 0.70 = High confidence match
  /// - 0.60-0.70 = Medium confidence (might be same person)
  /// - < 0.60 = Low confidence (different person)
  static double compareEmbeddings(
    List<double> embedding1,
    List<double> embedding2,
  ) {
    if (embedding1.length != embedding2.length) {
      throw Exception('Embeddings must have same length');
    }

    // Cosine similarity: (A·B) / (||A|| * ||B||)
    double dotProduct = 0.0;
    double norm1 = 0.0;
    double norm2 = 0.0;

    for (int i = 0; i < embedding1.length; i++) {
      dotProduct += embedding1[i] * embedding2[i];
      norm1 += embedding1[i] * embedding1[i];
      norm2 += embedding2[i] * embedding2[i];
    }

    final similarity = dotProduct / (norm1.sqrt() * norm2.sqrt());

    if (kDebugMode) {
      debugPrint('📊 Cosine Similarity: ${similarity.toStringAsFixed(3)}');
    }

    return similarity;
  }

  /// Check if two faces match (using cosine similarity threshold)
  static bool doFacesMatch(
    List<double> registeredEmbedding,
    List<double> attendanceEmbedding, {
    double threshold = 0.70, // Typical threshold for face verification
  }) {
    final similarity = compareEmbeddings(registeredEmbedding, attendanceEmbedding);
    final matches = similarity > threshold;

    if (kDebugMode) {
      debugPrint('🔍 Face Match Check:
   Similarity: ${similarity.toStringAsFixed(3)}');
      debugPrint('   Threshold: ${threshold.toStringAsFixed(2)}');
      debugPrint('   Result: ${matches ? "✅ MATCH" : "❌ NO MATCH"}');
    }

    return matches;
  }

  /// Dispose and cleanup
  static void dispose() {
    _interpreter?.close();
    _interpreter = null;
    if (kDebugMode) debugPrint('🔌 Face embedding service disposed');
  }
}

/// Result of face embedding extraction
class EmbeddingResult {
  final List<double> embedding;
  final bool success;
  final String message;

  EmbeddingResult({
    required this.embedding,
    required this.success,
    required this.message,
  });
}

/// Result of face comparison
class FaceComparisonResult {
  final bool match;
  final double similarity;
  final String message;

  FaceComparisonResult({
    required this.match,
    required this.similarity,
    required this.message,
  });
}
