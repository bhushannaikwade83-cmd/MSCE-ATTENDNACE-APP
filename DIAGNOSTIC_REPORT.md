# EDUSETU Attendance App - "Find Your Institute" Error Diagnostic Report

**Date:** April 29, 2026  
**Issue:** Failed to load institutes from Supabase API  
**Error Type:** `ClientException with SocketException: Failed host lookup`

---

## 📋 Executive Summary

The app is failing to load institutes from the Supabase backend. The root cause has been identified as a **network/proxy issue** that prevents the device from reaching the Supabase API endpoint. This is NOT a code configuration problem, but rather an environment/network connectivity issue.

---

## 🔍 Diagnostic Findings

### 1. **API Configuration Review** ✅
| Component | Status | Details |
|-----------|--------|---------|
| **SUPABASE_URL** | ✅ Correct | `https://snxcrqgodamoxwgkkqez.supabase.co` |
| **SUPABASE_ANON_KEY** | ✅ Valid | Properly formatted as `sb_publishable_...` |
| **Env Loading** | ✅ Correct | `.env` file loaded via `flutter_dotenv` |
| **Supabase Init** | ✅ Correct | Properly initialized in `SupabaseEnv.initializeRequired()` |

### 2. **Code Analysis** ✅
| File | Issue | Status |
|------|-------|--------|
| `institute_search_screen.dart` | API call logic | ✅ Correct |
| `app_db.dart` | Supabase client setup | ✅ Correct |
| `supabase_env.dart` | Configuration loading | ✅ Correct |
| `main.dart` | Initialization sequence | ✅ Correct |

**Key Code Flow:**
```
main.dart → SupabaseEnv.initializeRequired() 
         → Supabase.initialize(url, anonKey)
         → app_db.dart (returns Supabase.instance.client)
         → institute_search_screen.dart (calls appDb.from('institutes').select())
```

All code is properly structured and follows best practices. No bugs found in the implementation.

### 3. **Network Connectivity Issue** 🚨
| Test | Result | Details |
|------|--------|---------|
| **Host Lookup** | ❌ Failed | `snxcrqgodamoxwgkkqez.supabase.co` unreachable |
| **Proxy Check** | ⚠️ Blocked | HTTP 403 Forbidden - "blocked-by-allowlist" |
| **Proxy Error** | ⚠️ Active | localhost:3128 proxy is active and filtering connections |

**Network Error Details:**
```
Error: ClientException with SocketException: 
       Failed host lookup: 'snxcrqgodamoxwgkkqez.supabase.co'
       (OS Error: No address associated with hostname, errno = 7)
```

**Root Cause:** The device/emulator is running behind a proxy (`localhost:3128`) that has an **allowlist** configured. The Supabase domain is **NOT on the allowlist**, causing all connection attempts to be blocked with a 403 error.

---

## 🔧 Solutions

### **Solution 1: Bypass Proxy (For Development/Testing)**
If you're on a development machine or emulator:

1. **Unset proxy environment variables:**
   ```bash
   unset http_proxy
   unset https_proxy
   unset HTTP_PROXY
   unset HTTPS_PROXY
   ```

2. **For Android Emulator**, open emulator settings and disable proxy.

3. **For iOS Simulator**, System Preferences → Network → Advanced → Proxies (disable).

### **Solution 2: Add Supabase Domain to Proxy Allowlist**
If the proxy is corporate/institutional:

1. **Contact your network administrator** or IT support
2. **Request to add these domains to the proxy allowlist:**
   - `snxcrqgodamoxwgkkqez.supabase.co`
   - `*.supabase.co` (all Supabase domains)
   - `https://` protocol on port 443

3. **Provide this information to IT:**
   ```
   Service: Supabase PostgreSQL Backend-as-a-Service
   Required Domains:
   - snxcrqgodamoxwgkkqez.supabase.co
   - *.supabase.co (wildcard for flexibility)
   Protocol: HTTPS (port 443)
   Purpose: Mobile app backend API calls
   ```

### **Solution 3: Use VPN/Mobile Hotspot (Temporary)**
1. Disable WiFi and use mobile data
2. Or connect to a personal hotspot without proxy restrictions
3. This is temporary but confirms the proxy is the issue

### **Solution 4: Check Supabase Project Health**
Even though proxy is likely the issue, verify Supabase:

1. **Login to Supabase Dashboard:**
   - Go to https://supabase.com
   - Sign in with your account
   - Navigate to project dashboard

2. **Check Database Status:**
   - Verify the `institutes` table exists
   - Check that the table has data
   - Confirm Row Level Security (RLS) policies allow anonymous reads

3. **Check API Status:**
   - Supabase Status Page: https://status.supabase.com
   - Look for any service disruptions

4. **Verify Anon Key Permissions:**
   - In Supabase Dashboard → Settings → API
   - Confirm `SUPABASE_ANON_KEY` has access to `institutes` table
   - Check RLS policies aren't blocking anonymous access

---

## 🛠️ Recommended Implementation Fix (If Needed)

### **Add Network Error Handling & Retry Logic**

Update `institute_search_screen.dart`:

```dart
// Add exponential backoff retry
Future<void> _loadPredefinedInstitutesWithRetry({int retries = 3, Duration delay = const Duration(seconds: 1)}) async {
  setState(() => _isLoading = true);
  
  for (int attempt = 0; attempt < retries; attempt++) {
    try {
      final rows = await appDb.from('institutes').select().limit(100);
      _updateSearchResultsFromRows(rows);
      return; // Success
    } catch (e) {
      if (kDebugMode) debugPrint('Attempt $attempt failed: $e');
      
      if (attempt < retries - 1) {
        await Future.delayed(delay * (attempt + 1)); // Exponential backoff
      } else {
        // Final attempt failed
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Network error: ${e.toString()}\nCheck internet connection.'),
              backgroundColor: AppTheme.accentRed,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    }
  }
  
  setState(() => _isLoading = false);
}
```

### **Add Offline Fallback**

Store institutes locally and show cached data if API fails:

```dart
// In initState or when data loads successfully
void _cacheInstitutes(List<Map<String, dynamic>> institutes) {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
    'cached_institutes',
    jsonEncode(institutes),
  );
}

// Load from cache on failure
Future<void> _loadFromCache() async {
  final prefs = await SharedPreferences.getInstance();
  final cached = prefs.getString('cached_institutes');
  if (cached != null) {
    _updateSearchResultsFromRows(
      List<Map<String, dynamic>>.from(jsonDecode(cached))
    );
  }
}
```

---

## ✅ Testing Checklist

- [ ] **Network Connection:** Verify device has active internet
- [ ] **Proxy Status:** Confirm proxy allowlist includes Supabase domains
- [ ] **Env Variables:** `.env` file contains correct URL and API key
- [ ] **Supabase Project:** Verify project status at https://supabase.com
- [ ] **Database:** Confirm `institutes` table has data
- [ ] **RLS Policies:** Check anonymous access is enabled for `institutes` table
- [ ] **API Key:** Verify `SUPABASE_ANON_KEY` has proper permissions
- [ ] **Test on Different Network:** Try on mobile data to isolate proxy issue
- [ ] **App Rebuild:** Clean and rebuild Flutter app after any configuration changes

---

## 📊 Issue Summary

| Aspect | Finding |
|--------|---------|
| **Code Quality** | ✅ No issues - proper implementation |
| **Supabase Config** | ✅ Correct in .env and initialization |
| **API Design** | ✅ Follows best practices |
| **Root Cause** | 🚨 Network proxy blocking Supabase domain |
| **Severity** | High (blocks app functionality) |
| **Fix Priority** | 1. Network/Proxy (external) → 2. Add retry logic (code enhancement) |

---

## 📝 Next Steps

1. **Immediate:** Try the app on a network without proxy restrictions (mobile data)
2. **Short-term:** Contact IT to add Supabase domain to proxy allowlist
3. **Long-term:** Implement retry logic and offline caching for resilience

---

## 📞 Support Resources

- **Supabase Documentation:** https://supabase.com/docs
- **Flutter Supabase Package:** https://pub.dev/packages/supabase_flutter
- **Network Troubleshooting:** Check device network settings and proxy configuration
