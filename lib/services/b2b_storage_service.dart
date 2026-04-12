import 'dart:convert';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import '../config/b2b_storage_config.dart';
import 'validation_service.dart';

/// Backblaze B2 Storage Service
/// 
/// Backblaze B2 is a cost-effective object storage solution
/// 
/// Folder Structure:
///   institute_id/
///     batch_year/
///       rollNumber/
///         subject/
///           YYYY-MM-DD/
///             photo.jpg
class B2BStorageService {
  // B2B Storage configuration - loaded from secure config file (B2 Native API)
  static String get bucketName => B2BStorageConfig.bucketName;
  static String get bucketId => B2BStorageConfig.bucketId;
  static String get keyId => B2BStorageConfig.keyId;
  static String get applicationKey => B2BStorageConfig.applicationKey;
  
  // B2 Native API base URL
  static const String _b2ApiBaseUrl = 'https://api.backblazeb2.com/b2api/v2';
  
  // Cache for authorization (to avoid re-authorizing on every request)
  static String? _cachedAuthToken;
  static String? _cachedApiUrl;
  static String? _cachedDownloadUrl;
  
  /// Generate storage path for attendance photo
  /// 
  /// Structure: institute_id/batch_year/rollNumber/subject/YYYY-MM-DD/photo.jpg
  /// For entry/exit: institute_id/batch_year/rollNumber/subject/YYYY-MM-DD/entry.jpg or exit.jpg
  static String generatePhotoPath({
    required String instituteId,
    required String batchYear,
    required String rollNumber,
    required String subject,
    required String date, // Format: YYYY-MM-DD
    String? photoType, // 'entry' or 'exit'
  }) {
    // Clean subject name (remove spaces, special chars)
    final cleanSubject = subject
        .replaceAll(' ', '_')
        .replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '')
        .toLowerCase();
    
    // Clean roll number
    final cleanRollNumber = rollNumber.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    
    // Determine filename based on photo type
    final fileName = photoType != null && (photoType == 'entry' || photoType == 'exit')
        ? '$photoType.jpg'
        : 'photo.jpg'; // Default for backward compatibility
    
    // Path: institute_id/batch_year/rollNumber/subject/YYYY-MM-DD/entry.jpg or exit.jpg
    return '$instituteId/$batchYear/$cleanRollNumber/$cleanSubject/$date/$fileName';
  }

  /// Upload attendance photo to B2B Storage
  /// 
  /// Returns the file URL and storage path
  /// 
  /// SECURITY: Validates all inputs and file size before upload
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
      // SECURITY: Validate inputs
      final instituteIdError = ValidationService.validateInstituteId(instituteId);
      if (instituteIdError != null) {
        throw Exception('Invalid institute ID: $instituteIdError');
      }

      final rollNumberError = ValidationService.validateRollNumber(rollNumber);
      if (rollNumberError != null) {
        throw Exception('Invalid roll number: $rollNumberError');
      }

      final subjectError = ValidationService.validateSubject(subject);
      if (subjectError != null) {
        throw Exception('Invalid subject: $subjectError');
      }

      // SECURITY: Validate file size (max 50KB)
      final fileSizeError = ValidationService.validateFileSize(photoBytes.length, maxSizeKB: 50);
      if (fileSizeError != null) {
        throw Exception('File size validation failed: $fileSizeError');
      }

      // SECURITY: Validate date format (YYYY-MM-DD)
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date)) {
        throw Exception('Invalid date format. Expected YYYY-MM-DD');
      }

      // SECURITY: Validate batch year format
      if (batchYear.isEmpty || batchYear.length > 50) {
        throw Exception('Invalid batch year');
      }

      // Generate storage path with entry/exit support
      final storagePath = generatePhotoPath(
        instituteId: instituteId,
        batchYear: batchYear,
        rollNumber: rollNumber,
        subject: subject,
        date: date,
        photoType: photoType,
      );

      // Upload to B2B Storage (S3-compatible)
      final url = await _uploadToB2BStorage(
        objectKey: storagePath,
        data: photoBytes,
        contentType: 'image/jpeg',
      );

      return {
        'url': url,
        'path': storagePath,
        'bucket': bucketName,
      };
    } catch (e) {
      // Provide user-friendly error messages
      final errorString = e.toString();
      
      if (errorString.contains('File size validation failed')) {
        throw Exception(
          'Photo is too large!\n\n'
          'Maximum size: 50 KB\n'
          'Please reduce image quality or take a new photo.\n\n'
          'Tip: Use lower quality settings or crop the image.'
        );
      }
      
      if (errorString.contains('401') || 
          errorString.contains('unauthorized') ||
          errorString.contains('Authentication Failed') ||
          errorString.contains('Authentication')) {
        throw Exception(
          'Storage Authentication Error\n\n'
          'Please verify B2B Storage credentials in .env file:\n'
          '1. B2B_KEY_ID is correct (12 chars)\n'
          '2. B2B_APPLICATION_KEY is correct (42 chars)\n'
          '3. Application Key has "Read and Write" permissions\n'
          '4. B2B_BUCKET_NAME is correct\n'
          '5. B2B_BUCKET_ID is correct\n\n'
          'Check: .env file in project root\n'
          'Make sure app was restarted after updating .env'
        );
      }
      
      if (errorString.contains('Invalid institute ID') || 
          errorString.contains('Invalid roll number') ||
          errorString.contains('Invalid subject')) {
        throw Exception('Invalid data: $errorString');
      }
      
      // Generic error with more context
      throw Exception('Failed to upload photo: ${e.toString().replaceAll("Exception: ", "")}');
    }
  }

  /// Authorize B2 account and get authorization token (B2 Native API)
  static Future<Map<String, String>> _authorizeAccount() async {
    try {
      // Verify credentials are not empty
      if (keyId.isEmpty || applicationKey.isEmpty) {
        throw Exception('B2B Storage credentials are missing. Please check your configuration.');
      }
      
      // Trim whitespace from credentials
      final cleanKeyId = keyId.trim();
      final cleanAppKey = applicationKey.trim();
      
      // Validate credential format
      if (cleanKeyId.length != 12) {
        throw Exception(
          'Invalid Key ID format!\n\n'
          'Key ID should be exactly 12 characters.\n'
          'Current length: ${cleanKeyId.length} characters\n'
          'Key ID: "$cleanKeyId"\n\n'
          'Please check your .env file\n'
          'Make sure B2B_KEY_ID is set correctly with no extra spaces.'
        );
      }
      
      // Validate Key ID contains only hex characters
      if (!RegExp(r'^[0-9a-fA-F]{12}$').hasMatch(cleanKeyId)) {
        throw Exception(
          'Invalid Key ID format!\n\n'
          'Key ID should contain only hexadecimal characters (0-9, a-f, A-F).\n'
          'Current Key ID: "$cleanKeyId"\n\n'
          'Please check your .env file\n'
          'Make sure B2B_KEY_ID contains only valid hex characters.'
        );
      }
      
      // Validate Application Key length (42 characters)
      if (cleanAppKey.length != 42) {
        throw Exception(
          'Invalid Application Key format!\n\n'
          'Application Key should be exactly 42 characters.\n'
          'Current length: ${cleanAppKey.length} characters\n'
          'First 10 chars: "${cleanAppKey.substring(0, cleanAppKey.length > 10 ? 10 : cleanAppKey.length)}"\n'
          'Last 10 chars: "${cleanAppKey.length > 10 ? cleanAppKey.substring(cleanAppKey.length - 10) : cleanAppKey}"\n\n'
          'Common issues:\n'
          '1. Extra spaces before/after the key\n'
          '2. Extra quotes or characters\n'
          '3. Wrong Application Key copied\n\n'
          'Please check your .env file\n'
          'Make sure B2B_APPLICATION_KEY is set correctly (42 chars, no spaces, no quotes).\n'
          'Restart the app after updating .env file.'
        );
      }
      
      // Create Basic Auth header: base64(keyId:applicationKey)
      final credentials = '$cleanKeyId:$cleanAppKey';
      final credentialsBase64 = base64Encode(utf8.encode(credentials));
      
      // Authorize account
      final authResponse = await http.get(
        Uri.parse('$_b2ApiBaseUrl/b2_authorize_account'),
        headers: {
          'Authorization': 'Basic $credentialsBase64',
        },
      );
      
      if (authResponse.statusCode != 200) {
        throw Exception(
          'B2B Authorization Failed: ${authResponse.statusCode}\n'
          'Response: ${authResponse.body}\n\n'
          'Please verify your B2B_KEY_ID and B2B_APPLICATION_KEY in .env file.'
        );
      }
      
      final authData = jsonDecode(authResponse.body) as Map<String, dynamic>;
      final authToken = authData['authorizationToken'] as String;
      final apiUrl = authData['apiUrl'] as String;
      final downloadUrl = authData['downloadUrl'] as String;
      
      // Cache the authorization
      _cachedAuthToken = authToken;
      _cachedApiUrl = apiUrl;
      _cachedDownloadUrl = downloadUrl;
      
      return {
        'authorizationToken': authToken,
        'apiUrl': apiUrl,
        'downloadUrl': downloadUrl,
      };
    } catch (e) {
      throw Exception('Failed to authorize B2B account: $e');
    }
  }
  
  /// Get upload URL for bucket (B2 Native API)
  static Future<Map<String, String>> _getUploadUrl() async {
    try {
      // Use cached auth or authorize
      String authToken;
      String apiUrl;
      
      if (_cachedAuthToken != null && _cachedApiUrl != null) {
        authToken = _cachedAuthToken!;
        apiUrl = _cachedApiUrl!;
      } else {
        final auth = await _authorizeAccount();
        authToken = auth['authorizationToken']!;
        apiUrl = auth['apiUrl']!;
      }
      
      // Get upload URL
      final uploadUrlResponse = await http.post(
        Uri.parse('$apiUrl/b2api/v2/b2_get_upload_url'),
        headers: {
          'Authorization': authToken,
        },
        body: jsonEncode({'bucketId': bucketId}),
      );
      
      if (uploadUrlResponse.statusCode != 200) {
        // If auth failed, try re-authorizing
        if (uploadUrlResponse.statusCode == 401) {
          final auth = await _authorizeAccount();
          authToken = auth['authorizationToken']!;
          apiUrl = auth['apiUrl']!;
          
          // Retry with new auth
          final retryResponse = await http.post(
            Uri.parse('$apiUrl/b2api/v2/b2_get_upload_url'),
            headers: {
              'Authorization': authToken,
            },
            body: jsonEncode({'bucketId': bucketId}),
          );
          
          if (retryResponse.statusCode != 200) {
            throw Exception('Failed to get upload URL: ${retryResponse.statusCode} - ${retryResponse.body}');
          }
          
          final uploadData = jsonDecode(retryResponse.body) as Map<String, dynamic>;
          return {
            'uploadUrl': uploadData['uploadUrl'] as String,
            'authorizationToken': uploadData['authorizationToken'] as String,
          };
        }
        
        throw Exception('Failed to get upload URL: ${uploadUrlResponse.statusCode} - ${uploadUrlResponse.body}');
      }
      
      final uploadData = jsonDecode(uploadUrlResponse.body) as Map<String, dynamic>;
      return {
        'uploadUrl': uploadData['uploadUrl'] as String,
        'authorizationToken': uploadData['authorizationToken'] as String,
      };
    } catch (e) {
      throw Exception('Failed to get upload URL: $e');
    }
  }
  
  /// Upload file to B2B Storage (B2 Native API)
  static Future<String> _uploadToB2BStorage({
    required String objectKey,
    required List<int> data,
    required String contentType,
  }) async {
    try {
      // Debug: Log credential info
      print('🔐 ========== B2B STORAGE AUTH DEBUG ==========');
      print('Bucket: $bucketName');
      print('Bucket ID: $bucketId');
      final keyIdStatus = keyId.trim().length == 12 ? "✅" : "❌";
      final appKeyStatus = applicationKey.trim().length == 42 ? "✅" : "❌";
      print('Key ID: ${keyId.trim()} (${keyId.trim().length} chars) $keyIdStatus');
      print('Application Key: ${applicationKey.trim().length > 8 ? applicationKey.trim().substring(0, 8) : applicationKey.trim()}... (${applicationKey.trim().length} chars) $appKeyStatus');
      print('API: B2 Native API');
      print('===============================================');
      
      // Get upload URL
      final uploadInfo = await _getUploadUrl();
      final uploadUrl = uploadInfo['uploadUrl']!;
      final uploadAuthToken = uploadInfo['authorizationToken']!;
      
      // Calculate SHA1 hash of file content (B2 requires this)
      final sha1Hash = sha1.convert(data).toString();
      
      // URL encode the file name
      final encodedFileName = Uri.encodeComponent(objectKey);
      
      // Upload file to B2
      // B2 requires both Content-Type and X-Bz-Content-Type headers
      final uploadResponse = await http.post(
        Uri.parse(uploadUrl),
        headers: {
          'Authorization': uploadAuthToken,
          'Content-Type': contentType, // Standard HTTP header (required by B2)
          'X-Bz-File-Name': encodedFileName,
          'X-Bz-Content-Type': contentType, // B2-specific header
          'X-Bz-Content-Sha1': sha1Hash,
        },
        body: data,
      );
      
      if (uploadResponse.statusCode == 200) {
        final uploadResult = jsonDecode(uploadResponse.body) as Map<String, dynamic>;
        final fileId = uploadResult['fileId'] as String;
        final fileName = uploadResult['fileName'] as String;
        
        // Get download URL (use cached or get from auth)
        String downloadUrl;
        if (_cachedDownloadUrl != null) {
          downloadUrl = _cachedDownloadUrl!;
        } else {
          final auth = await _authorizeAccount();
          downloadUrl = auth['downloadUrl']!;
        }
        
        // Construct file URL
        final fileUrl = '$downloadUrl/file/$bucketName/$encodedFileName';
        
        print('✅ Upload successful!');
        print('File ID: $fileId');
        print('File URL: $fileUrl');
        
        return fileUrl;
      } else {
        // Parse error response
        String errorMessage = 'B2B upload failed: ${uploadResponse.statusCode}';
        final errorBody = uploadResponse.body;
        
        print('🔴 ========== B2B HTTP ERROR RESPONSE ==========');
        print('Status Code: ${uploadResponse.statusCode}');
        print('Response Body: $errorBody');
        
        try {
          final errorData = jsonDecode(errorBody) as Map<String, dynamic>;
          if (errorData.containsKey('code')) {
            errorMessage += '\nError Code: ${errorData['code']}';
          }
          if (errorData.containsKey('message')) {
            errorMessage += '\nError Message: ${errorData['message']}';
          }
        } catch (_) {
          errorMessage += '\nResponse: $errorBody';
        }
        print('================================================');
        
        throw Exception(errorMessage);
      }
    } catch (e) {
      final errorString = e.toString();
      
      // Log detailed error for debugging
      print('🔴 ========== B2B STORAGE ERROR ==========');
      print('Error: $errorString');
      print('Bucket: $bucketName');
      print('Bucket ID: $bucketId');
      print('Key ID: ${keyId.trim()} (${keyId.trim().length} chars)');
      print('Application Key Length: ${applicationKey.trim().length} chars');
      print('==========================================');
      
      if (kDebugMode) {
        debugPrint('🔴 B2B Storage Error Details:');
        debugPrint('   Full error: $errorString');
      }
      
      // Check for authentication errors
      if (errorString.contains('401') || 
          errorString.contains('unauthorized') ||
          errorString.contains('Authentication') ||
          errorString.contains('authorization')) {
        throw Exception(
          'B2B Storage Authentication Failed\n\n'
          'Please verify your credentials in .env file:\n\n'
          'Check:\n'
          '1. B2B_KEY_ID is correct (12 chars)\n'
          '2. B2B_APPLICATION_KEY is correct (42 chars)\n'
          '3. Application Key has "Read and Write" permissions\n'
          '4. Bucket ID: $bucketId\n'
          '5. Bucket Name: $bucketName\n\n'
          'Make sure your .env file has:\n'
          'B2B_KEY_ID=379cd0b52bbf\n'
          'B2B_APPLICATION_KEY=your_42_char_key\n'
          'B2B_BUCKET_NAME=attendance-students-photos\n'
          'B2B_BUCKET_ID=2357799c9d705bc592cb0b1f'
        );
      }
      
      // Check for bucket errors
      if (errorString.contains('404') || errorString.contains('not found')) {
        throw Exception(
          'B2B Storage Bucket Not Found\n\n'
          'Bucket Name: $bucketName\n'
          'Bucket ID: $bucketId\n'
          'Please verify the bucket exists and IDs are correct.'
        );
      }
      
      // Generic error
      rethrow;
    }
  }

  /// Delete attendance photo from B2B Storage (B2 Native API)
  static Future<void> deleteAttendancePhoto(String objectPath) async {
    try {
      // Get authorization token
      String authToken;
      String apiUrl;
      
      if (_cachedAuthToken != null && _cachedApiUrl != null) {
        authToken = _cachedAuthToken!;
        apiUrl = _cachedApiUrl!;
      } else {
        final auth = await _authorizeAccount();
        authToken = auth['authorizationToken']!;
        apiUrl = auth['apiUrl']!;
      }
      
      // Get file ID first (B2 requires fileId to delete)
      // For simplicity, we'll use b2_delete_file_version with fileName and fileId
      // Note: In production, you might want to store fileId when uploading
      
      // Delete file using fileName (B2 Native API)
      final deleteResponse = await http.post(
        Uri.parse('$apiUrl/b2api/v2/b2_delete_file_version'),
        headers: {
          'Authorization': authToken,
        },
        body: jsonEncode({
          'fileName': objectPath,
          'bucketId': bucketId,
        }),
      );
      
      if (deleteResponse.statusCode != 200 && deleteResponse.statusCode != 404) {
        // If auth failed, try re-authorizing
        if (deleteResponse.statusCode == 401) {
          final auth = await _authorizeAccount();
          authToken = auth['authorizationToken']!;
          apiUrl = auth['apiUrl']!;
          
          // Retry delete
          final retryResponse = await http.post(
            Uri.parse('$apiUrl/b2api/v2/b2_delete_file_version'),
            headers: {
              'Authorization': authToken,
            },
            body: jsonEncode({
              'fileName': objectPath,
              'bucketId': bucketId,
            }),
          );
          
          if (retryResponse.statusCode != 200 && retryResponse.statusCode != 404) {
            throw Exception('B2B delete failed: ${retryResponse.statusCode} - ${retryResponse.body}');
          }
        } else {
          throw Exception('B2B delete failed: ${deleteResponse.statusCode} - ${deleteResponse.body}');
        }
      }
    } catch (e) {
      throw Exception('Failed to delete photo from B2B Storage: $e');
    }
  }

  /// Get temporary signed photo URL (valid for 5 minutes)
  /// This generates a temporary URL that can be used to download the file without authentication
  /// Perfect for displaying images in Flutter apps with private B2 buckets
  static Future<String> getPhotoUrl(String objectPath) async {
    try {
      // Ensure we have authorization
      String authToken;
      String apiUrl;
      String downloadUrl;
      
      if (_cachedAuthToken != null && _cachedApiUrl != null && _cachedDownloadUrl != null) {
        authToken = _cachedAuthToken!;
        apiUrl = _cachedApiUrl!;
        downloadUrl = _cachedDownloadUrl!;
      } else {
        final auth = await _authorizeAccount();
        authToken = auth['authorizationToken']!;
        apiUrl = auth['apiUrl']!;
        downloadUrl = auth['downloadUrl']!;
      }
      
      // Generate temporary download authorization (valid for 5 minutes = 300 seconds)
      final downloadAuthResponse = await http.post(
        Uri.parse('$apiUrl/b2api/v2/b2_get_download_authorization'),
        headers: {
          'Authorization': authToken,
        },
        body: jsonEncode({
          'bucketId': bucketId,
          'fileNamePrefix': objectPath,
          'validDurationInSeconds': 300, // 5 minutes
        }),
      );
      
      if (downloadAuthResponse.statusCode != 200) {
        throw Exception('Failed to get download authorization: ${downloadAuthResponse.statusCode} - ${downloadAuthResponse.body}');
      }
      
      final downloadAuthData = jsonDecode(downloadAuthResponse.body) as Map<String, dynamic>;
      final downloadAuthToken = downloadAuthData['authorizationToken'] as String;
      
      // URL encode the path properly
      final encodedPath = Uri.encodeComponent(objectPath);
      
      // Construct temporary signed URL
      // Format: {downloadUrl}/file/{bucketName}/{encodedPath}?Authorization={downloadAuthToken}
      final temporaryUrl = '$downloadUrl/file/$bucketName/$encodedPath?Authorization=$downloadAuthToken';
      
      if (kDebugMode) {
        debugPrint('📷 Generated temporary photo URL (5 min validity): $temporaryUrl');
        debugPrint('   Object path: $objectPath');
        debugPrint('   Encoded path: $encodedPath');
        debugPrint('   Download URL: $downloadUrl');
      }
      
      return temporaryUrl;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error generating temporary photo URL: $e');
        debugPrint('   Attempting retry with fresh authorization...');
      }
      
      // Retry with fresh authorization
      try {
        // Clear cache and retry
        _cachedAuthToken = null;
        _cachedApiUrl = null;
        _cachedDownloadUrl = null;
        
        final auth = await _authorizeAccount();
        final authToken = auth['authorizationToken']!;
        final apiUrl = auth['apiUrl']!;
        final downloadUrl = auth['downloadUrl']!;
        
        // Generate temporary download authorization
        final downloadAuthResponse = await http.post(
          Uri.parse('$apiUrl/b2api/v2/b2_get_download_authorization'),
          headers: {
            'Authorization': authToken,
          },
          body: jsonEncode({
            'bucketId': bucketId,
            'fileNamePrefix': objectPath,
            'validDurationInSeconds': 300,
          }),
        );
        
        if (downloadAuthResponse.statusCode == 200) {
          final downloadAuthData = jsonDecode(downloadAuthResponse.body) as Map<String, dynamic>;
          final downloadAuthToken = downloadAuthData['authorizationToken'] as String;
          final encodedPath = Uri.encodeComponent(objectPath);
          final temporaryUrl = '$downloadUrl/file/$bucketName/$encodedPath?Authorization=$downloadAuthToken';
          
          if (kDebugMode) {
            debugPrint('✅ Retry successful: Generated signed URL');
          }
          
          return temporaryUrl;
        }
      } catch (retryError) {
        if (kDebugMode) {
          debugPrint('❌ Retry also failed: $retryError');
        }
      }
      
      // Final fallback: throw error instead of returning unsigned URL
      // This will be caught by the UI and show proper error message
      throw Exception('Failed to generate signed photo URL after retry. Please check your B2B Storage credentials and network connection.');
    }
  }
  
  /// Get authorization token for private bucket access (legacy method)
  /// Note: Use getPhotoUrl() instead for temporary signed URLs
  @Deprecated('Use getPhotoUrl() which generates temporary signed URLs')
  static Future<String> getAuthorizationToken() async {
    if (_cachedAuthToken != null) {
      return _cachedAuthToken!;
    }
    
    final auth = await _authorizeAccount();
    return auth['authorizationToken']!;
  }
}
