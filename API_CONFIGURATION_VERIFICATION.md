# API Configuration & Verification Guide

## 📋 Current Configuration

### Environment Variables (.env)
```
# Supabase Configuration
SUPABASE_URL=https://snxcrqgodamoxwgkkqez.supabase.co
SUPABASE_ANON_KEY=sb_publishable_qZd_MA-TbJ7CO1pRkp_P9Q_CuC1CdmL
ADMIN_PORTAL_URL=http://localhost:5173
```

### Flutter Package
- **Package:** `supabase_flutter: ^2.12.0`
- **Location:** `/pubspec.yaml`
- **Status:** ✅ Installed and configured

---

## 🔧 Configuration Locations

| Component | File | Status |
|-----------|------|--------|
| **Env Loading** | `main.dart` | ✅ Line 41: `dotenv.load()` |
| **Env Setup** | `config/supabase_env.dart` | ✅ Proper initialization |
| **Supabase Init** | `main.dart` | ✅ Line 46: `SupabaseEnv.initializeRequired()` |
| **Client Access** | `core/app_db.dart` | ✅ Exposes `appDb` getter |
| **API Calls** | `presentation/screens/institute_search_screen.dart` | ✅ Uses correct client |

---

## ✅ Configuration Verification Checklist

### 1. Environment Variables
```bash
# Check .env file exists
ls -la /Users/bhushan/Desktop/PROJECTS/EDUSETU-ATTENDACE-APP-main/.env

# View contents
cat /Users/bhushan/Desktop/PROJECTS/EDUSETU-ATTENDACE-APP-main/.env | grep SUPABASE
```

**Expected Output:**
```
SUPABASE_URL=https://snxcrqgodamoxwgkkqez.supabase.co
SUPABASE_ANON_KEY=sb_publishable_qZd_MA-TbJ7CO1pRkp_P9Q_CuC1CdmL
```

✅ **Status:** Correctly configured

---

### 2. Flutter Configuration
```bash
# Check pubspec.yaml
grep -A 2 "supabase_flutter" /Users/bhushan/Desktop/PROJECTS/EDUSETU-ATTENDACE-APP-main/pubspec.yaml
```

**Expected Output:**
```
supabase_flutter: ^2.12.0
```

✅ **Status:** Correctly versioned

---

### 3. Code Initialization Chain

**File:** `main.dart` (lines 37-46)
```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    await dotenv.load(fileName: '.env');  // ✅ Load .env
  } catch (e) {
    debugPrint('⚠️ Could not load .env: $e');
  }
  
  await SupabaseEnv.initializeRequired();  // ✅ Initialize Supabase
  
  // ... rest of initialization
}
```

✅ **Status:** Proper initialization sequence

---

### 4. Supabase Client Access

**File:** `core/app_db.dart`
```dart
import 'package:supabase_flutter/supabase_flutter.dart';

/// Global Supabase client. Call after [SupabaseEnv.initializeRequired] in main.
SupabaseClient get appDb => Supabase.instance.client;
```

✅ **Status:** Correctly exposes Supabase client

---

### 5. API Call Implementation

**File:** `institute_search_screen.dart` (line 35)
```dart
final rows = await appDb.from('institutes').select().limit(100);
```

✅ **Status:** Correct API usage

---

## 🧪 API Testing

### Test 1: Verify Configuration is Loaded

**Create a test file:** `test_supabase_config.dart`

```dart
import 'package:flutter_dotenv/flutter_dotenv.dart';

void testConfigLoaded() {
  final url = dotenv.env['SUPABASE_URL'];
  final key = dotenv.env['SUPABASE_ANON_KEY'];
  
  print('SUPABASE_URL: ${url?.replaceAll(RegExp(r'.{20}$'), '****')}');
  print('SUPABASE_ANON_KEY loaded: ${key != null ? 'Yes' : 'No'}');
  print('Config loaded: ${url != null && key != null ? 'YES' : 'NO'}');
}
```

---

### Test 2: Verify Supabase Client

**Add to main.dart after initialization:**

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    await dotenv.load(fileName: '.env');
  } catch (e) {
    debugPrint('⚠️ Could not load .env: $e');
  }
  
  await SupabaseEnv.initializeRequired();
  
  // TEST: Verify client is initialized
  try {
    final client = Supabase.instance.client;
    debugPrint('✅ Supabase client initialized');
    debugPrint('📍 URL: ${client.restClient.baseUrl}');
  } catch (e) {
    debugPrint('❌ Supabase client failed: $e');
  }
  
  SessionManager.initialize();
  
  // ... rest of initialization
}
```

---

### Test 3: Test Institute API Call

**Temporary test in institute_search_screen.dart:**

```dart
void _testApiConnection() async {
  debugPrint('🔍 Testing API connection...');
  
  try {
    // Test basic connection
    final testRows = await appDb
        .from('institutes')
        .select('id')
        .limit(1)
        .timeout(const Duration(seconds: 5));
    
    debugPrint('✅ API Connection: SUCCESS');
    debugPrint('📊 Institutes count: ${testRows.length}');
    
  } on SocketException catch (e) {
    debugPrint('❌ Network Error: $e');
  } on TimeoutException catch (e) {
    debugPrint('❌ Timeout Error: $e');
  } catch (e) {
    debugPrint('❌ Unknown Error: $e');
  }
}

// Call from initState for testing
@override
void initState() {
  super.initState();
  _testApiConnection(); // Add this temporarily
  _loadPredefinedInstitutes();
}
```

---

### Test 4: Direct HTTP Test

```bash
#!/bin/bash

SUPABASE_URL="https://snxcrqgodamoxwgkkqez.supabase.co"
ANON_KEY="sb_publishable_qZd_MA-TbJ7CO1pRkp_P9Q_CuC1CdmL"

# Test 1: Basic connectivity
echo "Test 1: Basic Connectivity"
curl -s -o /dev/null -w "%{http_code}\n" "$SUPABASE_URL"

# Test 2: API endpoint with headers
echo "Test 2: API Endpoint"
curl -s -X GET \
  "$SUPABASE_URL/rest/v1/institutes?limit=1" \
  -H "apikey: $ANON_KEY" \
  -H "Authorization: Bearer $ANON_KEY" \
  -w "\nHTTP Status: %{http_code}\n" \
  -o response.json

# Test 3: Check response
echo "Test 3: Response"
cat response.json | head -c 200
echo "..."
```

**Expected Results:**
- HTTP 200: Connected and data retrieved ✅
- HTTP 401: Invalid API key ❌
- HTTP 403: Access denied (check RLS) ❌
- HTTP 500: Server error ❌
- No response: Network/proxy issue ❌

---

## 🔐 API Key Security

### Current Configuration
| Field | Value | Risk |
|-------|-------|------|
| **SUPABASE_ANON_KEY** | `sb_publishable_...` | ⚠️ Public key in .env |
| **Storage Location** | `.env` file | ✅ Gitignored |
| **Access Level** | Read-only tables | ⚠️ Depends on RLS |

### Best Practices
```
✅ DO:
- Use anon key for public data (institutes list)
- Store sensitive keys in .env
- Add .env to .gitignore
- Use RLS to restrict access

❌ DON'T:
- Hardcode keys in code
- Commit .env to git
- Use service role key in client apps
- Trust client-side permissions alone
```

---

## 🛡️ RLS (Row Level Security) Verification

### Check Institutes Table RLS

**Login to Supabase Dashboard:**
1. Go to https://supabase.com
2. Select your project
3. Navigate to: `SQL Editor` → `Policies`
4. Find `institutes` table
5. Check RLS is enabled

**Required Policy:**
```sql
-- Allow anonymous (unauthenticated) users to read institutes
CREATE POLICY "Allow public read institutes" ON institutes
FOR SELECT
TO anon
USING (true);
```

### Verify via SQL
```sql
-- Check if RLS is enabled
SELECT tablename FROM pg_tables 
WHERE schemaname = 'public' AND tablename = 'institutes';

-- Check policies
SELECT * FROM pg_policies 
WHERE tablename = 'institutes' AND policyname LIKE '%public%';
```

---

## 📊 Configuration Test Results

| Component | Status | Evidence |
|-----------|--------|----------|
| **Env File** | ✅ | File exists with correct values |
| **Flutter Package** | ✅ | pubspec.yaml has supabase_flutter |
| **Code Initialization** | ✅ | main.dart loads .env and initializes |
| **Client Exposure** | ✅ | app_db.dart provides client |
| **API Calls** | ✅ | Code structure is correct |
| **Network/Proxy** | ❌ | Blocked by proxy (403) |
| **Supabase Project** | ⚠️ | Assumed healthy (untested) |
| **RLS Policies** | ⚠️ | Assumed correct (untested) |

---

## 🚀 Next Steps

### Immediate (Fix Network Issue)
1. **Disable proxy** and test again
2. **Try mobile data** to isolate proxy issue
3. **Contact IT** to whitelist Supabase domain

### Verification (Once Network Works)
1. Verify institutes data in Supabase
2. Check RLS policies allow anonymous reads
3. Test API directly with curl/Postman
4. Monitor app logs for any other errors

### Enhancement (For Production)
1. Implement retry logic (see NETWORK_RESILIENCE_GUIDE.md)
2. Add offline caching for resilience
3. Monitor network status in real-time
4. Implement more granular error handling

---

## 📚 References

- [Supabase Flutter Docs](https://supabase.com/docs/guides/with-flutter)
- [Supabase RLS Documentation](https://supabase.com/docs/guides/auth/row-level-security)
- [Flutter Dotenv Package](https://pub.dev/packages/flutter_dotenv)
- [Supabase REST API](https://supabase.com/docs/guides/api)

---

## ✨ Summary

**Configuration:** ✅ Correctly Set Up
**Code Quality:** ✅ Properly Implemented  
**Network Connectivity:** ❌ Blocked by Proxy
**API Permissions:** ⚠️ Likely OK (untested)

**Primary Issue:** Network proxy blocking `snxcrqgodamoxwgkkqez.supabase.co`

**Resolution:** Disable proxy or add domain to allowlist
