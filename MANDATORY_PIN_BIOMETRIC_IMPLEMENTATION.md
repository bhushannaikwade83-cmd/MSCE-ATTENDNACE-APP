# Mandatory PIN & Biometric Authentication - Implementation Guide

## Overview

**Implemented:** Mandatory PIN and biometric authentication on every app resume and after logout.

---

## What Changed

### 1. **Session Monitor Enhancement** 
**File:** `lib/presentation/widgets/session_monitor.dart`

#### New Feature: Biometric Lock on App Resume
```dart
// ✅ Line 82-84: NEW - Mandatory PIN/Biometric on every app resume
_showBiometricLockOnResume();

void _showBiometricLockOnResume() {
  // Push BiometricLockScreen when app resumes from background
  nav.push(MaterialPageRoute(
    builder: (_) => const BiometricLockScreen(),
    fullscreenDialog: true,
  ));
}
```

#### When This Triggers
- ✅ App closed and reopened
- ✅ App minimized and brought back to foreground
- ✅ After automatic session timeout
- ✅ After manual logout

### 2. **Session Cleanup on Logout**
```dart
// Line 210: Clear background flag on logout
_expectResumeFromBackground = false;
```

---

## User Flow

### Scenario 1: User Closes App and Reopens
```
App Running (Logged In)
    ↓
User presses home / closes app
    ↓
AppLifecycleState.paused triggered
    ↓
User opens app again
    ↓
AppLifecycleState.resumed triggered
    ↓
✅ BiometricLockScreen shown
    ↓
Enter PIN OR use biometric
    ↓
✅ Access granted
```

### Scenario 2: Session Timeout
```
App Running (Logged In)
    ↓
25 minutes of inactivity
    ↓
Session expired dialog shown
    ↓
User clicks "Logout" or countdown reaches 0
    ↓
SessionManager.signOut() called
    ↓
✅ Redirected to LoginScreen
    ↓
Must login again (new PIN/biometric)
```

### Scenario 3: Manual Logout Button
```
User clicks Logout button
    ↓
SessionManager.signOut() called
    ↓
_expectResumeFromBackground = false (reset)
    ↓
✅ Redirected to LoginScreen
```

---

## Security Features

### ✅ Mandatory Authentication Points
1. **Initial Login** - Email + Password + CAPTCHA + OTP + PIN
2. **App Resume** - PIN or Biometric (NEW)
3. **Session Timeout** - Logout + re-login required
4. **After Logout** - Full login flow again

### ✅ Session Management
- Session timeout: **25 minutes** of inactivity
- Background timeout: **1 minute**
- Token refresh: **Every 20 minutes**
- Background detection: **Automatic**

### ✅ Biometric Lock Behavior
- **If biometric enabled:** Tries biometric first, PIN fallback
- **If biometric disabled:** Requires PIN only
- **If biometric fails:** Falls back to PIN input

---

## BiometricLockScreen Details

**File:** `lib/presentation/screens/biometric_lock_screen.dart`

### Features
1. **Automatic Biometric Attempt** (lines 75-80)
   - Automatically tries biometric on load
   - Shows PIN input if biometric fails or disabled

2. **PIN Validation** (lines 125-150)
   - PIN length: 4-6 digits
   - Calls `AuthService.verifyPIN()`
   - Shows error messages on invalid PIN

3. **Unlock Success** (line 147)
   - Calls `_unlockApp()`
   - Pops the BiometricLockScreen
   - Returns to previous screen

---

## Technical Implementation

### Import Changes
```dart
// Added to session_monitor.dart
import '../screens/biometric_lock_screen.dart';
```

### Code Changes Summary
- **Lines added:** ~30
- **Files modified:** 1 (session_monitor.dart)
- **New methods:** `_showBiometricLockOnResume()`
- **Modified methods:** `didChangeAppLifecycleState()`, `_performAutoLogout()`

### No Database Changes Required
- Uses existing BiometricService
- Uses existing AuthService.verifyPIN()
- Uses existing SessionManager

---

## How to Test

### Test 1: App Close/Reopen
1. ✅ Login to app with PIN
2. ✅ Navigate to any screen
3. ✅ Press home button (app minimizes)
4. ✅ Close app completely
5. ✅ Reopen app
6. **Expected:** BiometricLockScreen appears automatically
7. ✅ Enter PIN or use biometric
8. ✅ Access granted, previous screen restored

### Test 2: Session Timeout
1. ✅ Login to app
2. ✅ Wait 25 minutes without activity
3. **Expected:** "Session Expired" dialog appears
4. ✅ Dialog auto-closes after 5 seconds
5. **Expected:** Redirected to LoginScreen
6. ✅ Must login again (email + password + PIN)

### Test 3: Manual Logout
1. ✅ Login to app
2. ✅ Click logout button
3. **Expected:** Immediately redirected to LoginScreen
4. ✅ Must login again

### Test 4: Biometric vs PIN
1. ✅ Setup biometric on device (if available)
2. ✅ Login and enable biometric in security settings
3. ✅ Close and reopen app
4. **Expected:** Biometric dialog appears first
5. **Option A:** Use biometric → Access granted
6. **Option B:** Press PIN button → PIN input field appears
7. ✅ Both paths work

---

## Session States

### Authenticated States
- ✅ Just logged in
- ✅ Active on screen
- ✅ Just unlocked via biometric/PIN
- ✅ Activity ongoing (scrolling, tapping)

### Un-Authenticated States
- ❌ Not logged in (LoginScreen)
- ❌ Session expired (LoginScreen)
- ❌ App closed (BiometricLockScreen on resume)
- ❌ Logged out manually (LoginScreen)

---

## Security Best Practices Implemented

| Feature | Implementation |
|---------|-----------------|
| **Mandatory Auth** | ✅ Every app resume requires PIN/biometric |
| **Session Timeout** | ✅ 25 minutes inactivity auto-logout |
| **Background Detection** | ✅ Automatic app pause/resume detection |
| **Token Refresh** | ✅ Every 20 minutes, automatic |
| **PIN Validation** | ✅ 4-6 digits, server-side verification |
| **Biometric Fallback** | ✅ If biometric fails, PIN input available |
| **Logout Cleanup** | ✅ Session cleared, flags reset |

---

## Configuration Constants

Located in `SessionManager`:
```dart
static const Duration _sessionTimeout = Duration(minutes: 25);
static const Duration _backgroundTimeout = Duration(minutes: 1);
static const Duration _tokenRefreshInterval = Duration(minutes: 20);
```

To change timeouts, modify these constants in `lib/services/session_manager.dart`.

---

## Troubleshooting

### Issue: BiometricLockScreen not appearing
- ✅ Check: Is biometric enabled in device settings?
- ✅ Check: Is user authenticated (`SessionManager.isAuthenticated()`)?
- ✅ Check: Did app actually come from background (`_expectResumeFromBackground`)?

### Issue: Session timeout not working
- ✅ Check: Has 25 minutes passed since last activity?
- ✅ Check: Is `SessionManager.updateActivity()` being called on user interactions?

### Issue: PIN not validating
- ✅ Check: Is PIN 4-6 digits?
- ✅ Check: Is `AuthService.verifyPIN()` returning correct result?

---

## Database/Backend Verification

No backend changes required. The implementation uses:
- ✅ Existing `verifyPin` API endpoint
- ✅ Existing `BiometricService`
- ✅ Existing `SessionManager`
- ✅ Existing Supabase auth session

---

## Summary

**What's Now Compulsory:**
1. ✅ PIN/Biometric required after app close
2. ✅ PIN/Biometric required after logout
3. ✅ Session auto-expires after 25 minutes
4. ✅ Background detection is automatic
5. ✅ Token refresh is automatic every 20 minutes

**Security Level:** 🔒 **High**
- Multiple authentication layers
- Automatic session management
- Biometric + PIN fallback
- Device-level security integration

---

## Build & Deploy

No special build configuration needed. Just rebuild:
```bash
flutter clean
flutter pub get
flutter run
```

The changes are pure Dart/Flutter, no native plugins added.

---

**Status:** ✅ **Ready for Testing**

Test the flow by closing and reopening the app after login!
