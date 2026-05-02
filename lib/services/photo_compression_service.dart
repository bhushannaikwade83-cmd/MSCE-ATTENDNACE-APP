import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show compute, kDebugMode, debugPrint;
import 'package:image/image.dart' as img;

/// Tunables shared with the isolate [must be compile-time for worker].
const int _minKb = 50;
const int _maxKb = 100;

/// CPU-heavy work runs in a [compute] isolate so the UI thread keeps scrolling/animating.
Uint8List _compressPhotoBytesWorker(Uint8List photoBytes) {
  try {
    var bytes = photoBytes;
    if (bytes.length >= _minKb * 1024 && bytes.length <= _maxKb * 1024) {
      return bytes;
    }

    final image = img.decodeImage(bytes);
    if (image == null) {
      return photoBytes;
    }

    var quality = 95;
    var compressed = img.encodeJpg(image, quality: quality);

    while (compressed.length > _maxKb * 1024 && quality > 40) {
      quality -= 10;
      compressed = img.encodeJpg(image, quality: quality);
    }

    if (compressed.length > _maxKb * 1024) {
      var scale = 0.7;
      while (compressed.length > _maxKb * 1024 && scale > 0.15) {
        final width = (image.width * scale).toInt();
        final height = (image.height * scale).toInt();
        var resized = img.copyResize(image, width: width, height: height);
        var resizeQuality = 75;
        compressed = img.encodeJpg(resized, quality: resizeQuality);
        while (compressed.length > _maxKb * 1024 && resizeQuality > 40) {
          resizeQuality -= 10;
          compressed = img.encodeJpg(resized, quality: resizeQuality);
        }
        scale -= 0.1;
      }
    }

    return Uint8List.fromList(compressed);
  } catch (_) {
    return photoBytes;
  }
}

/// Photo Compression Service
/// Compresses photos to 50-100KB while maintaining quality for face recognition
class PhotoCompressionService {
  static const int MIN_KB = 50;
  static const int MAX_KB = 100;
  static const int TARGET_KB = 75;

  /// Compress photo bytes directly to target size (50-100KB)
  static Future<Uint8List> compressPhotoBytes(Uint8List photoBytes) async {
    try {
      if (photoBytes.length >= MIN_KB * 1024 && photoBytes.length <= MAX_KB * 1024) {
        if (kDebugMode) {
          debugPrint('🗜️ Photo bytes already in target range, skipping isolate');
        }
        return photoBytes;
      }
      if (kDebugMode) {
        debugPrint('🗜️ Starting photo bytes compression (background isolate)...');
        debugPrint('   Original size: ${(photoBytes.length / 1024).toStringAsFixed(2)} KB');
      }
      final out = await compute(_compressPhotoBytesWorker, photoBytes);
      if (kDebugMode) {
        debugPrint('✅ Compression complete: ${(out.length / 1024).toStringAsFixed(2)} KB');
      }
      return out;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Compression failed: $e');
      return photoBytes;
    }
  }

  /// Compress photo to target size (50-100KB)
  static Future<Uint8List> compressPhoto(String photoPath) async {
    try {
      if (kDebugMode) {
        debugPrint('🗜️ Starting photo compression (background isolate)...');
      }
      final file = File(photoPath);
      final bytes = await file.readAsBytes();
      if (kDebugMode) {
        debugPrint('   Original size: ${(bytes.length / 1024).toStringAsFixed(2)} KB');
      }
      if (bytes.length >= MIN_KB * 1024 && bytes.length <= MAX_KB * 1024) {
        if (kDebugMode) {
          debugPrint('   ✅ Already in target range');
        }
        return bytes;
      }
      final out = await compute(_compressPhotoBytesWorker, bytes);
      if (kDebugMode) {
        debugPrint('✅ Compression complete: ${(out.length / 1024).toStringAsFixed(2)} KB');
      }
      return out;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Compression failed: $e');
      return await File(photoPath).readAsBytes();
    }
  }

  /// Compress and validate photo size
  static Future<CompressedPhotoResult> compressAndValidate(
      String photoPath) async {
    try {
      final compressed = await compressPhoto(photoPath);
      final sizeKB = compressed.length / 1024;

      final isValid =
          compressed.length >= MIN_KB * 1024 &&
          compressed.length <= MAX_KB * 1024;

      if (kDebugMode) {
        debugPrint('📊 Compression Result:');
        debugPrint('   Size: ${sizeKB.toStringAsFixed(2)} KB');
        debugPrint('   Valid: $isValid (Target: $MIN_KB-$MAX_KB KB)');
      }

      return CompressedPhotoResult(
        bytes: compressed,
        sizeKB: sizeKB,
        isValid: isValid,
        reason: isValid
            ? 'Photo compressed successfully ✅'
            : 'Size out of range: ${sizeKB.toStringAsFixed(2)} KB',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Validation failed: $e');
      return CompressedPhotoResult(
        bytes: Uint8List(0),
        sizeKB: 0,
        isValid: false,
        reason: 'Error: $e',
      );
    }
  }
}

/// Compressed photo result
class CompressedPhotoResult {
  final Uint8List bytes;
  final double sizeKB;
  final bool isValid; // true if 50-100KB
  final String reason;

  CompressedPhotoResult({
    required this.bytes,
    required this.sizeKB,
    required this.isValid,
    required this.reason,
  });
}
