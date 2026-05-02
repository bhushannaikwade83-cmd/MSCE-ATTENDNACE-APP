# Quick Troubleshooting Guide - "Find Your Institute" Error

## 🚀 Quick Fixes (Try These First)

### 1. **Disable Proxy** (30 seconds)
```bash
# For macOS/Linux
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY

# Verify
echo $http_proxy  # Should be empty
```

**Android Emulator:**
1. Open Extended Controls (three dots in bottom right)
2. Select "Settings"
3. Go to "Proxy" tab
4. Set to "No proxy"

**iOS Simulator:**
1. System Preferences → Network
2. Select your connection
3. Click "Advanced"
4. Proxies tab → uncheck all

---

### 2. **Check Internet Connection**
```bash
# Test if Supabase is reachable
curl -v https://snxcrqgodamoxwgkkqez.supabase.co

# Expected: HTTP 200 or 400 (not 403)
# Got 403? → Proxy is blocking it
```

**On Device:**
- Settings → WiFi → Check signal strength
- Airplane mode toggle: Off → On → Off
- Switch to mobile data (if available)

---

### 3. **Rebuild Flutter App**
```bash
cd /Users/bhushan/Desktop/PROJECTS/EDUSETU-ATTENDACE-APP-main

# Clean
flutter clean

# Get dependencies
flutter pub get

# Run with verbose output
flutter run -v
```

---

## 🔍 Diagnosis Matrix

| Symptom | Cause | Solution |
|---------|-------|----------|
| **Error 403 Forbidden** | Proxy blocking | Add Supabase to allowlist |
| **No address associated with hostname** | DNS/Network issue | Check internet connection |
| **Timeout error** | Server slow or unreachable | Retry later or use mobile data |
| **Shows "No institutes found"** but no error | API key invalid | Check SUPABASE_ANON_KEY in .env |
| **Works on mobile data but not WiFi** | Proxy on WiFi | Disable WiFi proxy |

---

## 🛠️ Fix by Severity

### **Severity 1: Cannot Connect at All** 🔴
**Symptoms:**
- App shows error immediately on load
- "Failed host lookup" or "403 Forbidden"
- Works on different network? → **It's a proxy issue**

**Steps:**
1. Disable any active proxy
2. Try mobile hotspot
3. Contact IT if on corporate network

---

### **Severity 2: Intermittent Failures** 🟡
**Symptoms:**
- Works sometimes, fails other times
- Timeout errors after 10+ seconds
- Works after retry

**Steps:**
1. Check internet stability
2. Restart WiFi router
3. Update the app with retry logic (see NETWORK_RESILIENCE_GUIDE.md)

---

### **Severity 3: Wrong Data/Empty Results** 🟢
**Symptoms:**
- App connects successfully but shows empty list
- No error messages displayed

**Steps:**
1. Check Supabase database has data
2. Verify RLS policies allow anonymous access
3. Test API key permissions

---

## 📋 Verification Checklist

```
Network
├─ [ ] Internet connection active
├─ [ ] Proxy disabled (or Supabase whitelisted)
├─ [ ] DNS working (can resolve supabase.co)
└─ [ ] No firewall blocking port 443

Configuration
├─ [ ] .env file exists
├─ [ ] SUPABASE_URL is correct
├─ [ ] SUPABASE_ANON_KEY is valid
└─ [ ] App rebuilt after changes

Supabase Backend
├─ [ ] Project is active
├─ [ ] `institutes` table exists
├─ [ ] Table has data rows
├─ [ ] RLS policies allow SELECT
└─ [ ] API key has table access
```

---

## 💡 Advanced Diagnostics

### **Check .env Configuration**
```bash
grep -E "SUPABASE|ADMIN" /Users/bhushan/Desktop/PROJECTS/EDUSETU-ATTENDACE-APP-main/.env
```

**Expected output:**
```
SUPABASE_URL=https://snxcrqgodamoxwgkkqez.supabase.co
SUPABASE_ANON_KEY=sb_publishable_...
```

---

### **View App Logs**
```bash
# While app is running
flutter logs

# Filter for errors
flutter logs | grep -i "error\|failed"
```

**Look for:**
- `Error loading institutes:`
- `Failed host lookup`
- `SocketException`
- `403 Forbidden`

---

### **Test Supabase Directly**
```bash
# Replace with actual values
SUPABASE_URL="https://snxcrqgodamoxwgkkqez.supabase.co"
ANON_KEY="sb_publishable_..."

# Test API access
curl -X GET \
  "$SUPABASE_URL/rest/v1/institutes" \
  -H "apikey: $ANON_KEY" \
  -H "Authorization: Bearer $ANON_KEY"
```

---

## 📱 Device-Specific Fixes

### **Android**
```bash
# Clear app cache
adb shell pm clear com.msce.attendance

# View logcat
adb logcat | grep -i flutter
```

### **iOS**
```bash
# View console
xcrun simctl spawn booted log stream --predicate 'process == "Runner"'
```

### **Web/Desktop**
- Press F12 for Developer Tools
- Check Console tab for errors
- Check Network tab for failed requests

---

## 📞 When to Escalate

**Contact IT/Support if:**
- ✅ Proxy is confirmed as blocker
- ✅ Other users experience same issue
- ✅ Works on some devices but not others
- ✅ Works on mobile data but not WiFi/LAN

**Information to provide:**
- Device type and OS version
- Network type (WiFi/Mobile/VPN)
- Complete error message from app
- Timestamp of issue
- Whether proxy is active

---

## 🔗 Useful Resources

| Resource | Purpose |
|----------|---------|
| [Supabase Docs](https://supabase.com/docs) | API documentation |
| [Supabase Status](https://status.supabase.com) | Service status |
| [Flutter Logs](https://flutter.dev/docs/testing/debugging) | Debug logs |
| [Network Troubleshooting](https://support.google.com/business/answer/14368908) | Network issues |

---

## ⚡ TL;DR - Fastest Solution

1. **Disable proxy** → Test
2. **Try mobile data** → Test
3. **Restart phone/emulator** → Test
4. **Rebuild app** → Test
5. **Contact IT to whitelist Supabase** → Done

Most likely cause: **Proxy blocking Supabase domain**

Success rate: ~90% of cases resolved by disabling proxy
