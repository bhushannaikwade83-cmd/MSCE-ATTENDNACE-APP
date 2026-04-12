import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:image/image.dart' as img;

/// ArcFace Backend Service
/// 
/// Connects to backend API for fast face recognition
/// Supports 200,000+ students with vector database
class ArcFaceBackendService {
  // Backend API URL - Configure this in your .env file
  static String get _baseUrl {
    // Try to get from .env file first
    final envUrl = dotenv.env['FACE_RECOGNITION_API_URL'];
    if (envUrl != null && envUrl.isNotEmpty) {
      return envUrl;
    }
    // Fallback to actual deployed URL
    return const String.fromEnvironment(
      'FACE_RECOGNITION_API_URL',
      defaultValue: 'https://face-recognition-api-mv5fg3vmlq-uc.a.run.app/api/v1',
    );
  }

  /// Recognize a student from face photo
  /// 
  /// Performance: ~210-450ms (vs 90-180s with current approach)
  /// 
  /// Returns: Student match info or null if no match found
  static Future<Map<String, dynamic>?> recognizeStudent({
    required String imagePath,
    required String instituteId,
    double threshold = 0.85,
  }) async {
    try {
      // Read image file
      final imageFile = File(imagePath);
      if (!await imageFile.exists()) {
        if (kDebugMode) debugPrint('❌ Image file not found: $imagePath');
        return null;
      }

      // Read image bytes
      final imageBytes = await imageFile.readAsBytes();

      if (kDebugMode) {
        debugPrint('🚀 Sending face recognition request to backend (multipart)...');
        debugPrint('   Institute: $instituteId');
        debugPrint('   Image size: ${imageBytes.length} bytes');
      }

      // Create multipart request
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$_baseUrl/recognize'),
      );

      // Add form fields
      request.fields['institute_id'] = instituteId;
      // Only send threshold if provided (it's optional)
      // FastAPI will use default 0.85 if not provided
      // Note: We don't send it at all if not needed, but if we do, send as string

      // Add image file
      request.files.add(
        await http.MultipartFile.fromPath(
          'file',  // Field name must match backend parameter name
          imagePath,
          filename: imagePath.split('/').last,  // Use actual filename
        ),
      );
      
      // Debug: Log all fields being sent
      if (kDebugMode) {
        debugPrint('📤 Multipart Request Details (Recognize):');
        debugPrint('   URL: $_baseUrl/recognize');
        debugPrint('   Fields: ${request.fields}');
        debugPrint('   Files: ${request.files.map((f) => '${f.field}: ${f.filename} (${f.length} bytes)').join(', ')}');
      }

      // Send request to backend API with retry logic for 503 errors
      // Increased timeout to 30 seconds for first request (model loading can take time)
      final startTime = DateTime.now();
      http.StreamedResponse? streamedResponse;
      int retryCount = 0;
      const maxRetries = 2; // Retry up to 2 times for 503 errors
      
      while (retryCount <= maxRetries) {
        try {
          streamedResponse = await request.send().timeout(
            const Duration(seconds: 30), // Increased from 10 to 30 seconds for model loading
            onTimeout: () {
              if (kDebugMode) {
                debugPrint('⏱️ Request timed out after 30 seconds');
                debugPrint('   This may happen on first request when model is loading');
                debugPrint('   Please try again - subsequent requests will be faster');
              }
              throw TimeoutException('Face recognition request timed out after 30 seconds. The backend may be loading the model. Please try again.');
            },
          );
          
          // If we get 503, retry (unless we've exhausted retries)
          if (streamedResponse.statusCode == 503 && retryCount < maxRetries) {
            retryCount++;
            if (kDebugMode) {
              debugPrint('⚠️ 503 Service Unavailable, retrying... (attempt $retryCount/$maxRetries)');
              debugPrint('   Backend may be cold-starting - waiting ${5 * retryCount} seconds');
            }
            // Wait before retry (exponential backoff: 5s, 10s)
            await Future.delayed(Duration(seconds: 5 * retryCount));
            continue; // Retry the request
          }
          
          // If we get a successful response or non-503 error, break
          break;
        } catch (e) {
          // For other errors, don't retry
          if (kDebugMode) {
            debugPrint('❌ Request failed: $e');
          }
          rethrow;
        }
      }
      
      // Ensure we have a response
      if (streamedResponse == null) {
        if (kDebugMode) {
          debugPrint('❌ No response received after ${maxRetries + 1} attempts');
        }
        return null;
      }

      // Read response body
      final responseBody = await streamedResponse.stream.bytesToString();
      final response = http.Response(responseBody, streamedResponse.statusCode);

      final duration = DateTime.now().difference(startTime);

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body) as Map<String, dynamic>;
        
        if (responseData['success'] == true && responseData['match'] != null) {
          final match = responseData['match'] as Map<String, dynamic>;
          
          if (kDebugMode) {
            debugPrint('✅ Student recognized: ${match['name']} (Roll ${match['roll_number']})');
            final similarityPercent = (match['similarity'] as double) * 100;
            debugPrint('   Similarity: ${similarityPercent.toStringAsFixed(1)}%');
            debugPrint('   Processing time: ${responseData['processing_time_ms']}ms');
            debugPrint('   Total time: ${duration.inMilliseconds}ms');
          }
          
          return {
            'studentId': match['student_id'],
            'rollNumber': match['roll_number'],
            'name': match['name'],
            'similarity': match['similarity'],
            'processingTimeMs': responseData['processing_time_ms'],
          };
        } else {
          if (kDebugMode) {
            debugPrint('⚠️ No match found (similarity below threshold)');
          }
          return null;
        }
      } else if (response.statusCode == 503) {
        // Service Unavailable - backend may be cold-starting or crashed
        if (kDebugMode) {
          debugPrint('❌ Backend API error: 503 Service Unavailable');
          debugPrint('   Response: ${response.body}');
          debugPrint('   ⚠️ Backend may be cold-starting or temporarily unavailable');
          debugPrint('   💡 Tip: Wait a few seconds and try again');
        }
        return null;
      } else if (response.statusCode == 500) {
        // Internal Server Error - backend processing error
        String actualError = 'Unknown error';
        String fullResponse = response.body;
        
        // Try to parse the actual error from backend response
        try {
          final errorData = jsonDecode(response.body) as Map<String, dynamic>;
          actualError = errorData['detail'] as String? ?? 
                       errorData['message'] as String? ?? 
                       errorData['error'] as String? ?? 
                       'Unknown error';
          
          // Extract error type and message if available
          if (actualError.contains(':')) {
            final parts = actualError.split(':');
            if (parts.length > 1) {
              actualError = parts.sublist(1).join(':').trim();
            }
          }
        } catch (e) {
          // If JSON parsing fails, use raw response
          actualError = response.body.isNotEmpty ? response.body : 'Unknown error';
        }
        
        if (kDebugMode) {
          debugPrint('═══════════════════════════════════════════════════════');
          debugPrint('❌ BACKEND 500 INTERNAL SERVER ERROR (Recognize)');
          debugPrint('═══════════════════════════════════════════════════════');
          debugPrint('📋 Full Response Body:');
          debugPrint('   $fullResponse');
          debugPrint('');
          debugPrint('🔍 Actual Backend Error:');
          debugPrint('   $actualError');
          debugPrint('');
          debugPrint('💡 This is the REAL error from the backend API');
          debugPrint('   Check backend terminal logs for more details');
          debugPrint('═══════════════════════════════════════════════════════');
        }
        return null;
      } else if (response.statusCode == 422) {
        // Validation Error
        String errorMessage = 'Invalid request data';
        try {
          final errorData = jsonDecode(response.body) as Map<String, dynamic>;
          errorMessage = errorData['detail'] as String? ?? 
                       errorData['help'] as String? ??
                       'Invalid request data. Please check all fields are provided correctly.';
        } catch (_) {
          errorMessage = response.body.isNotEmpty ? response.body : 'Invalid request data';
        }
        
        if (kDebugMode) {
          debugPrint('❌ Backend API error: 422 Validation Error');
          debugPrint('   Response: ${response.body}');
          debugPrint('   Error: $errorMessage');
        }
        return null;
      } else {
        if (kDebugMode) {
          debugPrint('❌ Backend API error: ${response.statusCode}');
          debugPrint('   Response: ${response.body}');
        }
        return null;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error in face recognition: $e');
        if (e is TimeoutException) {
          debugPrint('   ⚠️ Backend may be cold-starting (first request)');
          debugPrint('   💡 Tip: Try again - subsequent requests will be faster');
        } else if (e.toString().contains('SocketException') || e.toString().contains('Failed host lookup')) {
          debugPrint('   ⚠️ Network error - check internet connection');
        } else if (e.toString().contains('503') || e.toString().contains('Service Unavailable')) {
          debugPrint('   ⚠️ Backend service unavailable - may be cold-starting');
          debugPrint('   💡 Tip: Wait 10-20 seconds and try again');
        }
      }
      return null;
    }
  }

  /// Verify face for a specific roll number (direct 1:1 matching)
  /// 
  /// This is faster than searching all students, but also includes
  /// a security check to detect if wrong person's photo is used.
  /// 
  /// Performance: ~210-455ms (faster than full search)
  static Future<Map<String, dynamic>?> verifyStudentFace({
    required String imagePath,
    required String instituteId,
    required String rollNumber,
    double threshold = 0.70,
  }) async {
    try {
      // Read image file
      final imageFile = File(imagePath);
      if (!await imageFile.exists()) {
        if (kDebugMode) debugPrint('❌ Image file not found: $imagePath');
        return null;
      }

      // Read image bytes
      final imageBytes = await imageFile.readAsBytes();

      if (kDebugMode) {
        debugPrint('🔍 Verifying face for roll: $rollNumber (multipart)');
      }

      // Create multipart request
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$_baseUrl/verify'),
      );

      // Add form fields
      request.fields['institute_id'] = instituteId;
      request.fields['roll_number'] = rollNumber;
      // Only send threshold if provided (it's optional)
      // FastAPI will use default 0.70 if not provided

      // Add image file
      request.files.add(
        await http.MultipartFile.fromPath(
          'file',  // Field name must match backend parameter name
          imagePath,
          filename: imagePath.split('/').last,  // Use actual filename
        ),
      );
      
      // Debug: Log all fields being sent
      if (kDebugMode) {
        debugPrint('📤 Multipart Request Details:');
        debugPrint('   URL: $_baseUrl/verify');
        debugPrint('   Fields: ${request.fields}');
        debugPrint('   Files: ${request.files.map((f) => '${f.field}: ${f.filename} (${f.length} bytes)').join(', ')}');
      }

      final startTime = DateTime.now();
      http.StreamedResponse? streamedResponse;
      int retryCount = 0;
      const maxRetries = 2;

      while (retryCount <= maxRetries) {
        try {
          streamedResponse = await request.send().timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              throw TimeoutException('Face verification request timed out after 30 seconds.');
            },
          );
          break;
        } catch (e) {
          if (retryCount < maxRetries && 
              (e.toString().contains('500') || 
               e.toString().contains('503') || 
               e.toString().contains('Service Unavailable'))) {
            retryCount++;
            if (kDebugMode) {
              debugPrint('⚠️ Verification error, retrying... (attempt $retryCount/$maxRetries)');
            }
            await Future.delayed(Duration(seconds: 3 * retryCount));
            continue;
          }
          rethrow;
        }
      }

      if (streamedResponse == null) {
        if (kDebugMode) {
          debugPrint('❌ Failed to get response after $maxRetries retries');
        }
        return null;
      }

      // Read response body
      final responseBody = await streamedResponse.stream.bytesToString();
      final response = http.Response(responseBody, streamedResponse.statusCode);

      final duration = DateTime.now().difference(startTime);

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body) as Map<String, dynamic>;
        
        if (responseData['success'] == true) {
          final match = responseData['match'] as bool;
          final similarity = responseData['similarity'] as double;
          final securityCheckPassed = responseData['security_check_passed'] as bool;
          final topMatchRoll = responseData['top_match_roll'] as String?;
          
          if (kDebugMode) {
            debugPrint('✅ Face verification result:');
            debugPrint('   Match: $match');
            debugPrint('   Similarity: ${(similarity * 100).toStringAsFixed(1)}%');
            debugPrint('   Security check: ${securityCheckPassed ? "PASSED" : "FAILED"}');
            if (topMatchRoll != null) {
              debugPrint('   Top match roll: $topMatchRoll');
            }
            debugPrint('   Processing time: ${responseData['processing_time_ms']}ms');
          }
          
          if (match && securityCheckPassed) {
            return {
              'match': true,
              'similarity': similarity,
              'securityCheckPassed': true,
              'processingTimeMs': responseData['processing_time_ms'],
            };
          } else {
            if (!securityCheckPassed) {
              if (kDebugMode) {
                debugPrint('⚠️ SECURITY ALERT: Face matches different student!');
                debugPrint('   Selected roll: $rollNumber');
                debugPrint('   Matched roll: $topMatchRoll');
              }
            }
            return null;
          }
        }
      }
      
      // Handle 500 errors with detailed logging
      if (response.statusCode == 500) {
        String actualError = 'Unknown error';
        String fullResponse = response.body;
        
        // Try to parse the actual error from backend response
        try {
          final errorData = jsonDecode(response.body) as Map<String, dynamic>;
          actualError = errorData['detail'] as String? ?? 
                       errorData['message'] as String? ?? 
                       errorData['error'] as String? ?? 
                       'Unknown error';
          
          // Extract error type and message if available
          if (actualError.contains(':')) {
            final parts = actualError.split(':');
            if (parts.length > 1) {
              actualError = parts.sublist(1).join(':').trim();
            }
          }
        } catch (e) {
          // If JSON parsing fails, use raw response
          actualError = response.body.isNotEmpty ? response.body : 'Unknown error';
        }
        
        if (kDebugMode) {
          debugPrint('═══════════════════════════════════════════════════════');
          debugPrint('❌ BACKEND 500 INTERNAL SERVER ERROR (Verify)');
          debugPrint('═══════════════════════════════════════════════════════');
          debugPrint('📋 Full Response Body:');
          debugPrint('   $fullResponse');
          debugPrint('');
          debugPrint('🔍 Actual Backend Error:');
          debugPrint('   $actualError');
          debugPrint('');
          debugPrint('💡 This is the REAL error from the backend API');
          debugPrint('   Check backend terminal logs for more details');
          debugPrint('═══════════════════════════════════════════════════════');
        }
        return null;
      } else if (response.statusCode == 422) {
        // Validation Error
        String errorMessage = 'Invalid request data';
        try {
          final errorData = jsonDecode(response.body) as Map<String, dynamic>;
          errorMessage = errorData['detail'] as String? ?? 
                       errorData['help'] as String? ??
                       'Invalid request data. Please check all fields are provided correctly.';
        } catch (_) {
          errorMessage = response.body.isNotEmpty ? response.body : 'Invalid request data';
        }
        
        if (kDebugMode) {
          debugPrint('❌ Backend API error: 422 Validation Error (Verify)');
          debugPrint('   Response: ${response.body}');
          debugPrint('   Error: $errorMessage');
        }
        return null;
      }
      
      if (kDebugMode) {
        debugPrint('❌ Failed to verify face: ${response.statusCode}');
        debugPrint('   Response: ${response.body}');
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error verifying face: $e');
      }
      return null;
    }
  }

  /// Register a new student face
  /// 
  /// Sends single face photo to backend using multipart/form-data (no base64 overhead)
  /// Only the main image is used (additional images are ignored)
  static Future<bool> registerStudentFace({
    required String imagePath,
    List<String>? additionalImagePaths, // Additional images for averaging (ignored)
    required String instituteId,
    required String studentId,
    required String rollNumber,
    required String name,
  }) async {
    try {
      // Read image file
      final imageFile = File(imagePath);
      if (!await imageFile.exists()) {
        if (kDebugMode) debugPrint('❌ Image file not found: $imagePath');
        return false;
      }

      // Read image bytes
      final imageBytes = await imageFile.readAsBytes();
      
      if (imageBytes.isEmpty) {
        if (kDebugMode) debugPrint('❌ Image file is empty: $imagePath');
        return false;
      }
      
      // Decode image for resizing
      final decodedImage = img.decodeImage(imageBytes);
      
      if (decodedImage == null) {
        if (kDebugMode) debugPrint('❌ Failed to decode image: $imagePath');
        return false;
      }
      
      // Resize image to 512px width (maintains aspect ratio, reduces payload size)
      final resizedImage = img.copyResize(
        decodedImage,
        width: 512,
      );
      
      // Encode as JPEG with quality 85 (good balance between size and quality)
      final resizedBytes = img.encodeJpg(resizedImage, quality: 85);
      
      // Debug output
      if (kDebugMode) {
        debugPrint("══════════════════════════════════");
        debugPrint("📸 FACE REGISTRATION REQUEST (Multipart)");
        debugPrint("Image path: $imagePath");
        debugPrint("Original size: ${(imageBytes.length / 1024).toStringAsFixed(2)} KB");
        debugPrint("Resized size: ${(resizedBytes.length / 1024).toStringAsFixed(2)} KB");
        debugPrint("Institute: $instituteId");
        debugPrint("Roll: $rollNumber");
        debugPrint("══════════════════════════════════");
        if (additionalImagePaths != null && additionalImagePaths.isNotEmpty) {
          debugPrint('   ⚠️ Note: ${additionalImagePaths.length} additional images ignored (single image mode)');
        }
      }

      // Create multipart request
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$_baseUrl/register'),
      );

      // Add form fields (all as strings - FastAPI will parse them)
      request.fields['institute_id'] = instituteId;
      request.fields['student_id'] = studentId;
      request.fields['roll_number'] = rollNumber;
      request.fields['name'] = name;

      // Add image file (use resized bytes)
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',  // Field name must match backend parameter name
          resizedBytes,
          filename: 'face.jpg',
          contentType: http.MediaType('image', 'jpeg'),
        ),
      );
      
      // Debug: Log all fields being sent
      if (kDebugMode) {
        debugPrint('📤 Multipart Request Details:');
        debugPrint('   URL: $_baseUrl/register');
        debugPrint('   Fields: ${request.fields}');
        debugPrint('   Files: ${request.files.map((f) => '${f.field}: ${f.filename} (${f.length} bytes)').join(', ')}');
      }

      // Send request with retry logic
      http.StreamedResponse? streamedResponse;
      int retryCount = 0;
      const maxRetries = 2;
      
      while (retryCount <= maxRetries) {
        try {
          streamedResponse = await request.send().timeout(
            const Duration(seconds: 60),
            onTimeout: () {
              throw TimeoutException('Face registration request timed out after 60 seconds. The backend may be loading the model or processing the image. Please try again.');
            },
          );
          
          // If we get a response (even 500/503), break the retry loop
          break;
        } catch (e) {
          if (retryCount < maxRetries && 
              (e.toString().contains('500') || 
               e.toString().contains('503') || 
               e.toString().contains('Service Unavailable') ||
               e.toString().contains('Internal Server Error'))) {
            retryCount++;
            if (kDebugMode) {
              debugPrint('⚠️ Registration error, retrying... (attempt $retryCount/$maxRetries)');
            }
            // Wait before retry (exponential backoff: 3s, 6s)
            await Future.delayed(Duration(seconds: 3 * retryCount));
            continue;
          }
          rethrow;
        }
      }
      
      if (streamedResponse == null) {
        if (kDebugMode) {
          debugPrint('❌ Failed to get response after $maxRetries retries');
        }
        return false;
      }

      // Read response body
      final responseBody = await streamedResponse.stream.bytesToString();
      final response = http.Response(responseBody, streamedResponse.statusCode);

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body) as Map<String, dynamic>;
        
        if (responseData['success'] == true) {
          if (kDebugMode) {
            debugPrint('✅ Face registered successfully for $rollNumber');
          }
          return true;
        }
      } else if (response.statusCode == 500) {
        // Internal Server Error - backend processing error
        String actualError = 'Unknown error';
        String fullResponse = response.body;
        
        // Try to parse the actual error from backend response
        try {
          final errorData = jsonDecode(response.body) as Map<String, dynamic>;
          actualError = errorData['detail'] as String? ?? 
                       errorData['message'] as String? ?? 
                       errorData['error'] as String? ?? 
                       'Unknown error';
          
          // Extract error type and message if available
          if (actualError.contains(':')) {
            final parts = actualError.split(':');
            if (parts.length > 1) {
              actualError = parts.sublist(1).join(':').trim();
            }
          }
        } catch (e) {
          // If JSON parsing fails, use raw response
          actualError = response.body.isNotEmpty ? response.body : 'Unknown error';
        }
        
        if (kDebugMode) {
          debugPrint('═══════════════════════════════════════════════════════');
          debugPrint('❌ BACKEND 500 INTERNAL SERVER ERROR');
          debugPrint('═══════════════════════════════════════════════════════');
          debugPrint('📋 Full Response Body:');
          debugPrint('   $fullResponse');
          debugPrint('');
          debugPrint('🔍 Actual Backend Error:');
          debugPrint('   $actualError');
          debugPrint('');
          debugPrint('💡 This is the REAL error from the backend API');
          debugPrint('   Check backend terminal logs for more details');
          debugPrint('═══════════════════════════════════════════════════════');
        }
        
        // Throw exception with actual error so UI can display it
        throw Exception('Backend Error: $actualError');
      } else if (response.statusCode == 403) {
        // Forbidden - usually spoof detection
        String errorMessage = 'Registration rejected';
        try {
          final errorData = jsonDecode(response.body) as Map<String, dynamic>;
          errorMessage = errorData['detail'] as String? ?? 
                       errorData['message'] as String? ?? 
                       'Registration rejected';
        } catch (_) {
          errorMessage = response.body.isNotEmpty ? response.body : 'Registration rejected';
        }
        
        if (kDebugMode) {
          debugPrint('❌ Backend API error: 403 Forbidden');
          debugPrint('   Response: ${response.body}');
          debugPrint('   Error: $errorMessage');
        }
        
        // Throw exception with actual error message so UI can display it
        throw Exception(errorMessage);
      } else if (response.statusCode == 400) {
        // Bad Request - usually validation errors (no face detected, etc.)
        String errorMessage = 'Registration failed';
        try {
          final errorData = jsonDecode(response.body) as Map<String, dynamic>;
          errorMessage = errorData['detail'] as String? ?? 
                       errorData['message'] as String? ?? 
                       'Registration failed';
        } catch (_) {
          errorMessage = response.body.isNotEmpty ? response.body : 'Registration failed';
        }
        
        if (kDebugMode) {
          debugPrint('❌ Backend API error: 400 Bad Request');
          debugPrint('   Response: ${response.body}');
          debugPrint('   Error: $errorMessage');
        }
        
        // Throw exception with actual error message so UI can display it
        throw Exception(errorMessage);
      } else if (response.statusCode == 503) {
        // Service Unavailable - backend may be cold-starting
        if (kDebugMode) {
          debugPrint('❌ Backend API error: 503 Service Unavailable');
          debugPrint('   Response: ${response.body}');
          debugPrint('   ⚠️ Backend may be cold-starting or temporarily unavailable');
          debugPrint('   💡 Tip: Wait a few seconds and try again');
        }
        throw Exception('Service temporarily unavailable. Please try again in a few seconds.');
      }
      
      // Parse error response to get actual error message for other status codes
      String errorMessage = 'Registration failed';
      try {
        final errorData = jsonDecode(response.body) as Map<String, dynamic>;
        errorMessage = errorData['detail'] as String? ?? 
                     errorData['message'] as String? ?? 
                     'Registration failed';
      } catch (_) {
        errorMessage = response.body.isNotEmpty ? response.body : 'Registration failed';
      }
      
      if (kDebugMode) {
        debugPrint('❌ Failed to register face: ${response.statusCode}');
        debugPrint('   Response: ${response.body}');
        debugPrint('   Error: $errorMessage');
      }
      
      // Throw exception with error message so it can be caught and displayed
      throw Exception(errorMessage);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error registering face: $e');
        if (e is TimeoutException) {
          debugPrint('   ⚠️ Backend may be cold-starting (first request)');
          debugPrint('   💡 Tip: Try again - subsequent requests will be faster');
        } else if (e.toString().contains('SocketException') || e.toString().contains('Failed host lookup')) {
          debugPrint('   ⚠️ Network error - check internet connection');
        }
      }
      return false;
    }
  }

  /// Health check - Test if backend API is available
  static Future<bool> checkHealth() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/health'),
      ).timeout(const Duration(seconds: 5));

      return response.statusCode == 200;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Backend API health check failed: $e');
      }
      return false;
    }
  }
}

class TimeoutException implements Exception {
  final String message;
  TimeoutException(this.message);
  
  @override
  String toString() => message;
}
