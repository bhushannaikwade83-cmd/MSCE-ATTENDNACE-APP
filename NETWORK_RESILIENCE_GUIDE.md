# Network Resilience Implementation Guide

## Overview

This guide provides code implementations to make the app more resilient to network issues while the Supabase connectivity problem is being resolved.

---

## 1. Enhanced Institute Search Screen with Retry Logic

**File:** `lib/presentation/screens/institute_search_screen.dart`

Add this helper function to the `_InstituteSearchScreenState` class:

```dart
// Add these constants at the top of the state class
static const int MAX_RETRIES = 3;
static const Duration INITIAL_RETRY_DELAY = Duration(seconds: 1);

// Replace _loadPredefinedInstitutes with this version
Future<void> _loadPredefinedInstitutes({int attempt = 0}) async {
  setState(() => _isLoading = true);
  
  try {
    if (kDebugMode) debugPrint('Loading institutes (attempt ${attempt + 1}/$MAX_RETRIES)');
    
    final rows = await appDb
        .from('institutes')
        .select()
        .limit(100)
        .timeout(
          const Duration(seconds: 10),
          onTimeout: () => throw TimeoutException('Institute load timeout'),
        );
    
    _updateSearchResultsFromRows(rows);
    
    if (kDebugMode) debugPrint('✅ Institutes loaded successfully');
  } catch (e) {
    if (kDebugMode) debugPrint('❌ Error loading institutes (attempt ${attempt + 1}): $e');
    
    // Retry with exponential backoff
    if (attempt < MAX_RETRIES - 1) {
      final delayMs = INITIAL_RETRY_DELAY.inMilliseconds * (2 ^ attempt);
      if (kDebugMode) debugPrint('⏳ Retrying in ${delayMs}ms...');
      
      await Future.delayed(Duration(milliseconds: delayMs));
      return _loadPredefinedInstitutes(attempt: attempt + 1);
    }
    
    // All retries exhausted
    setState(() => _isLoading = false);
    
    if (mounted) {
      _showErrorDialog(
        title: 'Unable to Load Institutes',
        message: 'Network error: ${_extractErrorMessage(e)}\n\n'
            'Check your internet connection and try again.',
        onRetry: () => _loadPredefinedInstitutes(),
      );
    }
    
    // Try to load from cache as fallback
    await _loadFromCache();
  }
}

// Add this helper to extract user-friendly error messages
String _extractErrorMessage(dynamic error) {
  final errorStr = error.toString();
  
  if (errorStr.contains('SocketException')) {
    return 'No internet connection';
  } else if (errorStr.contains('TimeoutException')) {
    return 'Request timed out';
  } else if (errorStr.contains('Failed host lookup')) {
    return 'Unable to reach server';
  } else if (errorStr.contains('403')) {
    return 'Access denied (check proxy/firewall)';
  } else if (errorStr.contains('500') || errorStr.contains('502')) {
    return 'Server error';
  }
  
  return errorStr.split(':').first; // First part of error
}

// Add error dialog
void _showErrorDialog({
  required String title,
  required String message,
  VoidCallback? onRetry,
}) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        if (onRetry != null)
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              onRetry();
            },
            child: const Text('Retry'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Dismiss'),
        ),
      ],
    ),
  );
}
```

---

## 2. Offline Caching with SharedPreferences

**File:** `lib/services/institute_cache_service.dart` (new file)

Create a new service for caching institutes locally:

```dart
import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

class InstituteCacheService {
  static const String _cacheKey = 'cached_institutes';
  static const String _cacheTimestampKey = 'cached_institutes_timestamp';
  static const Duration _cacheValidDuration = Duration(hours: 24);

  /// Save institutes to local cache
  static Future<void> cacheInstitutes(
    List<Map<String, dynamic>> institutes,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      await prefs.setString(
        _cacheKey,
        jsonEncode(institutes),
      );
      
      await prefs.setInt(
        _cacheTimestampKey,
        DateTime.now().millisecondsSinceEpoch,
      );
      
      if (kDebugMode) {
        debugPrint('✅ Cached ${institutes.length} institutes');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Cache error: $e');
    }
  }

  /// Retrieve institutes from local cache
  static Future<List<Map<String, dynamic>>?> getCachedInstitutes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_cacheKey);
      
      if (cached == null) {
        if (kDebugMode) debugPrint('⚠️ No cached institutes found');
        return null;
      }

      // Check if cache is still valid
      final timestamp = prefs.getInt(_cacheTimestampKey) ?? 0;
      final cacheAge = DateTime.now().millisecondsSinceEpoch - timestamp;
      
      if (cacheAge > _cacheValidDuration.inMilliseconds) {
        if (kDebugMode) debugPrint('⚠️ Cache expired');
        return null;
      }

      final List<dynamic> decoded = jsonDecode(cached);
      final institutes = decoded
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      
      if (kDebugMode) {
        debugPrint('✅ Loaded ${institutes.length} institutes from cache');
      }
      
      return institutes;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error loading cache: $e');
      return null;
    }
  }

  /// Clear the cache
  static Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);
      await prefs.remove(_cacheTimestampKey);
      if (kDebugMode) debugPrint('✅ Cache cleared');
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error clearing cache: $e');
    }
  }

  /// Check if cache exists and is valid
  static Future<bool> hasCachedInstitutes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_cacheKey);
      final timestamp = prefs.getInt(_cacheTimestampKey) ?? 0;
      
      if (cached == null) return false;
      
      final cacheAge = DateTime.now().millisecondsSinceEpoch - timestamp;
      return cacheAge <= _cacheValidDuration.inMilliseconds;
    } catch (e) {
      return false;
    }
  }
}
```

---

## 3. Updated Institute Search Screen with Caching

Add these imports to `institute_search_screen.dart`:

```dart
import '../../services/institute_cache_service.dart';
```

Update the `_loadPredefinedInstitutes` method:

```dart
Future<void> _loadPredefinedInstitutes({int attempt = 0}) async {
  setState(() => _isLoading = true);
  
  try {
    if (kDebugMode) debugPrint('Loading institutes (attempt ${attempt + 1}/$MAX_RETRIES)');
    
    final rows = await appDb
        .from('institutes')
        .select()
        .limit(100)
        .timeout(
          const Duration(seconds: 10),
          onTimeout: () => throw TimeoutException('Institute load timeout'),
        );
    
    _updateSearchResultsFromRows(rows);
    
    // Cache successful results
    await InstituteCacheService.cacheInstitutes(rows);
    
    if (kDebugMode) debugPrint('✅ Institutes loaded and cached');
  } catch (e) {
    if (kDebugMode) debugPrint('❌ Error loading institutes (attempt ${attempt + 1}): $e');
    
    // Retry with exponential backoff
    if (attempt < MAX_RETRIES - 1) {
      final delayMs = INITIAL_RETRY_DELAY.inMilliseconds * (2 ^ attempt);
      if (kDebugMode) debugPrint('⏳ Retrying in ${delayMs}ms...');
      
      await Future.delayed(Duration(milliseconds: delayMs));
      return _loadPredefinedInstitutes(attempt: attempt + 1);
    }
    
    // All retries exhausted - try cache
    setState(() => _isLoading = false);
    
    final cachedInstitutes = await InstituteCacheService.getCachedInstitutes();
    
    if (cachedInstitutes != null && cachedInstitutes.isNotEmpty) {
      // Show cached data with warning
      _updateSearchResultsFromRows(cachedInstitutes);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Showing cached institutes (offline)'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } else {
      // No cache available
      if (mounted) {
        _showErrorDialog(
          title: 'Unable to Load Institutes',
          message: 'Network error: ${_extractErrorMessage(e)}\n\n'
              'No cached data available. Please check your connection.',
          onRetry: () => _loadPredefinedInstitutes(),
        );
      }
    }
  }
}
```

---

## 4. Network Status Monitoring

**File:** `lib/services/network_status_service.dart` (new file)

Create a service to monitor network status:

```dart
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show ChangeNotifier, debugPrint;

class NetworkStatusService extends ChangeNotifier {
  static final NetworkStatusService _instance = NetworkStatusService._internal();
  
  factory NetworkStatusService() {
    return _instance;
  }
  
  NetworkStatusService._internal() {
    _initializeConnectivity();
  }

  bool _isConnected = true;
  bool get isConnected => _isConnected;

  final Connectivity _connectivity = Connectivity();

  void _initializeConnectivity() {
    _connectivity.onConnectivityChanged.listen(
      (List<ConnectivityResult> results) {
        _handleConnectivityChange(results);
      },
    );
  }

  void _handleConnectivityChange(List<ConnectivityResult> results) {
    final wasConnected = _isConnected;
    final isNowConnected = results.isNotEmpty && 
        !results.contains(ConnectivityResult.none);
    
    if (wasConnected != isNowConnected) {
      _isConnected = isNowConnected;
      
      if (kDebugMode) {
        debugPrint(_isConnected ? '📡 Connected' : '❌ Disconnected');
      }
      
      notifyListeners();
    }
  }
}
```

---

## 5. Integration in Main App

Update `main.dart` to initialize services:

```dart
import 'services/network_status_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await dotenv.load(fileName: '.env');
  } catch (e) {
    debugPrint('⚠️ Could not load .env: $e');
  }

  await SupabaseEnv.initializeRequired();

  SessionManager.initialize();
  
  // Initialize network status monitoring
  NetworkStatusService();

  try {
    await FaceRecognitionService.initialize();
  } catch (e, st) {
    debugPrint('⚠️ Face model failed to load: $e');
  }

  runApp(const SmartAttendanceApp());
}
```

---

## 6. Dependency Updates

Update `pubspec.yaml` to ensure all required packages are included:

```yaml
dependencies:
  # ... existing dependencies ...
  shared_preferences: ^2.3.3  # For local caching
  connectivity_plus: ^7.1.1    # For network monitoring
```

---

## Testing the Implementation

### Test 1: Network Available
1. Run the app on a device with internet
2. Institutes should load normally
3. Data should be cached automatically

### Test 2: Network Unavailable
1. Toggle airplane mode after first successful load
2. App should show cached institutes
3. Should indicate they are from cache

### Test 3: Retry Logic
1. Turn off WiFi (but keep some connectivity issue)
2. App should retry 3 times
3. After retries, fall back to cache
4. Show user-friendly error message

### Test 4: Cache Expiration
1. Clear cache manually
2. Turn off internet
3. App should show no data
4. Display appropriate error message

---

## Performance Considerations

- **Caching:** 24-hour cache validity (configurable)
- **Timeout:** 10-second API timeout to fail fast
- **Retries:** 3 attempts with exponential backoff
- **Memory:** Efficient JSON encoding/decoding
- **Disk:** ~50-100KB for typical institute data

---

## Summary

This implementation provides:
- ✅ Automatic retry with exponential backoff
- ✅ Offline caching with 24-hour validity
- ✅ Network status monitoring
- ✅ User-friendly error messages
- ✅ Graceful fallbacks
- ✅ Detailed debugging logs
