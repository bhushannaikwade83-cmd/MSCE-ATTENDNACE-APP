import 'b2b_storage_service.dart';

/// Storage Service for organizing attendance photos
/// Uses B2B Storage (Backblaze B2) for file storage
/// 
/// Folder Structure:
///   institute_id/
///     batch_year/
///       rollNumber/
///         subject/
///           YYYY-MM-DD/
///             photo.jpg
class StorageService {
  /// Generate storage path for attendance photo
  /// 
  /// Structure: institute_id/batch_year/rollNumber/subject/YYYY-MM-DD/photo.jpg
  static String generatePhotoPath({
    required String instituteId,
    required String batchYear,
    required String rollNumber,
    required String subject,
    required String date, // Format: YYYY-MM-DD
  }) {
    return B2BStorageService.generatePhotoPath(
      instituteId: instituteId,
      batchYear: batchYear,
      rollNumber: rollNumber,
      subject: subject,
      date: date,
    );
  }

  /// Upload attendance photo to B2B Storage
  /// 
  /// Returns the file URL and storage path
  /// photoType: 'entry' or 'exit' (optional, defaults to 'entry' for backward compatibility)
  static Future<Map<String, String>> uploadAttendancePhoto({
    required String instituteId,
    required String batchYear,
    required String rollNumber,
    required String subject,
    required String date,
    required List<int> photoBytes,
    String? photoType, // 'entry' or 'exit'
  }) async {
    try {
      final result = await B2BStorageService.uploadAttendancePhoto(
        instituteId: instituteId,
        batchYear: batchYear,
        rollNumber: rollNumber,
        subject: subject,
        date: date,
        photoBytes: photoBytes,
        photoType: photoType,
      );

      return {
        'url': result['url']!,
        'path': result['path']!,
      };
    } catch (e) {
      throw Exception('Failed to upload photo: $e');
    }
  }

  /// Delete attendance photo from B2B Storage
  static Future<void> deleteAttendancePhoto(String objectPath) async {
    try {
      await B2BStorageService.deleteAttendancePhoto(objectPath);
    } catch (e) {
      throw Exception('Failed to delete photo: $e');
    }
  }

  /// Get photo URL from object path
  /// Always returns a signed URL (valid for 5 minutes)
  /// Automatically retries with fresh authorization if needed
  static Future<String> getPhotoUrl(String objectPath) async {
    try {
      return await B2BStorageService.getPhotoUrl(objectPath);
    } catch (e) {
      // Retry once with fresh authorization
      try {
        await Future.delayed(const Duration(milliseconds: 500));
        return await B2BStorageService.getPhotoUrl(objectPath);
      } catch (retryError) {
        rethrow; // Re-throw if retry also fails
      }
    }
  }

  /// Ensure URL is signed (regenerate if needed)
  /// Use this when you have a URL that might be unsigned
  static Future<String> ensureSignedUrl(String url) async {
    // If URL is already signed (has Authorization param), return as-is
    if (url.contains('Authorization=')) {
      return url;
    }

    // If URL is from B2 but unsigned, extract path and regenerate
    if (url.contains('backblazeb2.com')) {
      try {
        final pathMatch = RegExp(r'/file/[^/]+/(.+?)(?:\?|$)').firstMatch(url);
        if (pathMatch != null) {
          final objectPath = Uri.decodeComponent(pathMatch.group(1)!);
          return await getPhotoUrl(objectPath);
        }
      } catch (e) {
        // If regeneration fails, return original (will show error)
        return url;
      }
    }

    // For non-B2 URLs (e.g., Firebase Storage), return as-is
    return url;
  }
  
  /// Get authorization token for private bucket access
  static Future<String> getAuthorizationToken() async {
    return await B2BStorageService.getAuthorizationToken();
  }

  /// Extract metadata from file path/ID
  static Map<String, String>? parsePhotoPath(String pathOrId) {
    try {
      // Handle both path format and file ID format
      final parts = pathOrId.contains('/') 
          ? pathOrId.split('/')
          : pathOrId.split('_');

      if (parts.length >= 5) {
        return {
          'instituteId': parts[0],
          'batchYear': parts[1],
          'rollNumber': parts[2],
          'subject': parts[3].replaceAll('_', ' '),
          'date': parts[4],
        };
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Automatically convert photo data to temporary signed URL
  /// 
  /// This method handles all cases:
  /// - If storagePath is provided, generates URL from it
  /// - If photoUrl is provided but not signed, signs it
  /// - If photoUrl is already signed, returns as-is
  /// - If photoUrl is a storage path (not starting with http), converts it
  /// 
  /// Use this method to automatically get temporary URLs for all student photos
  static Future<String?> getTemporaryPhotoUrl({
    String? photoUrl,
    String? storagePath,
  }) async {
    try {
      // Priority 1: Use storagePath if available (most reliable)
      if (storagePath != null && storagePath.isNotEmpty) {
        return await getPhotoUrl(storagePath);
      }

      // Priority 2: Process photoUrl
      if (photoUrl != null && photoUrl.isNotEmpty) {
        // If it's not a URL (starts with http), treat it as storage path
        if (!photoUrl.startsWith('http')) {
          return await getPhotoUrl(photoUrl);
        }

        // If it's a URL, ensure it's signed
        return await ensureSignedUrl(photoUrl);
      }

      // No valid data
      return null;
    } catch (e) {
      // Return null on error (caller can handle)
      return null;
    }
  }

  /// Batch convert multiple photos to temporary URLs
  /// Useful for displaying multiple student photos at once
  static Future<List<Map<String, dynamic>>> convertPhotosToTemporaryUrls(
    List<Map<String, dynamic>> photos,
  ) async {
    final results = await Future.wait(
      photos.map((photo) async {
        final photoUrl = photo['photoUrl'] as String?;
        final storagePath = photo['storagePath'] as String?;
        
        try {
          final temporaryUrl = await getTemporaryPhotoUrl(
            photoUrl: photoUrl,
            storagePath: storagePath,
          );
          
          return {
            ...photo,
            'photoUrl': temporaryUrl ?? '',
            'hasValidUrl': temporaryUrl != null && temporaryUrl.isNotEmpty,
          };
        } catch (e) {
          return {
            ...photo,
            'photoUrl': '',
            'hasValidUrl': false,
            'error': e.toString(),
          };
        }
      }),
    );
    
    return results;
  }
}
