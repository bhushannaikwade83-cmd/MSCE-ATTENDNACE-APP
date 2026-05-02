# 🔐 Complete OTP Usage Map - All Locations

## 📋 OTP is Used in These 4 Screens:

### **1. Login Screen** 
📄 `lib/presentation/screens/login_screen.dart`

**When OTP is used:**
- User enters email/student ID
- Clicks "Send OTP" button
- OTP verification step happens
- Then PIN/Password entry

**Code locations:**
```dart
sendOTP(userId)              // Line: Sends OTP
verifyOTP(userId, otp)       // Line: Verifies OTP
_otpController               // Line: OTP input field
```

---

### **2. Institute Registration Screen** ⭐ (MAIN SIGNUP)
📄 `lib/presentation/screens/institute_registration_screen.dart`

**Complete OTP Flow:**

```
Step 1: Send OTP Email
├─ User selects institute
├─ Shows email (prefilled from invite)
└─ Click "Send OTP" button
   └─ Calls: sendInviteSignupEmailOTP(email)

Step 2: Enter OTP
├─ User sees 6-digit OTP field
├─ Enter OTP received in email
└─ Click "Verify OTP" button
   └─ Calls: verifyInviteSignupOTP(email, otp)

Step 3: After OTP Verified ✅
├─ OTP field is disabled/hidden
├─ Password setup shown
├─ Confirm password shown
└─ User continues to final registration

Step 4: Complete Registration
├─ Sets password (8+ characters)
├─ Confirms password
└─ Submits form to create account
```

**Code locations:**
```dart
_otpController               // Line 47: OTP input controller
_inviteEmailOtpSent         // Line 52: Track if OTP sent
_inviteEmailOtpVerified     // Line 56: Track if OTP verified

_sendInviteEmailOtp()       // Line 72: Send OTP button action
_verifyInviteEmailOtp()     // Line 105: Verify OTP button action

sendInviteSignupEmailOTP()  // AuthService: Calls Brevo
verifyInviteSignupOTP()     // AuthService: Verifies OTP
```

**UI Fields:**
- Line 334: OTP input field (shown if OTP sent, not verified)
- Line 336: _otpController (6-digit number input)
- Line 340: Center aligned, big font

---

### **3. Institute Admin Registration Screen**
📄 `lib/presentation/screens/institute_admin_registration_screen.dart`

**When OTP is used:**
- New admin registration flow
- Email OTP verification before account creation
- Similar to institute registration

---

### **4. Biometric Lock Screen**
📄 `lib/presentation/screens/biometric_lock_screen.dart`

**When OTP is used:**
- Fallback if biometric fails
- OTP as secondary authentication
- Emergency access method

---

## 🔄 Complete User Journey

```
Login/Register Flow:
┌─────────────────────────────────────────────────────┐
│  User Opens App                                     │
└────────────┬────────────────────────────────────────┘
             │
    ┌────────▼─────────┐
    │  Select Institute │
    └────────┬─────────┘
             │
    ┌────────▼──────────────────────┐
    │  Email shown (prefilled)       │
    │  [Send OTP] Button             │  ← OTP Sent
    └────────┬──────────────────────┘
             │
    ┌────────▼──────────────────────┐
    │  📧 OTP arrives in email       │
    │  [6-digit OTP input field]     │  ← User enters OTP
    │  [Verify OTP] Button           │
    └────────┬──────────────────────┘
             │
    ┌────────▼──────────────────────┐
    │  ✅ OTP Verified              │
    │  [Password setup]              │  ← Next step
    │  [Confirm password]            │
    │  [Submit]                      │
    └────────┬──────────────────────┘
             │
    ┌────────▼──────────────────────┐
    │  ✅ Account Created            │
    │  Ready to Login                │
    └─────────────────────────────────┘
```

---

## 📍 Exact Code Locations in institute_registration_screen.dart

| Step | Code Line | Function | What Happens |
|------|-----------|----------|--------------|
| **Send OTP** | 72 | `_sendInviteEmailOtp()` | Gets email, calls `sendInviteSignupEmailOTP()` |
| **Store OTP sent** | 79 | `_inviteEmailOtpSent = true` | Shows OTP input field |
| **Show OTP Field** | 334-360 | UI Build | Displays 6-digit number input |
| **Verify OTP** | 105 | `_verifyInviteEmailOtp()` | Reads _otpController, calls `verifyInviteSignupOTP()` |
| **Success** | 120 | `_inviteEmailOtpVerified = true` | Enables password fields, hides OTP field |
| **Continue** | 380+ | Build widgets | Shows password setup (only after OTP verified) |

---

## 🔑 Key Variables Tracking OTP State

```dart
// In _InstituteRegistrationScreenState

bool _inviteEmailOtpSent = false;           // Has OTP been sent?
bool _inviteEmailOtpVerified = false;       // Has OTP been verified?
TextEditingController _otpController = ...  // OTP input field

// Usage:
if (!_inviteEmailOtpSent) {
  // Show "Send OTP" button
}
if (_inviteEmailOtpSent && !_inviteEmailOtpVerified) {
  // Show OTP input field and "Verify" button
}
if (_inviteEmailOtpVerified) {
  // Show password fields (only after OTP verified)
}
```

---

## 🎯 Where to Display Demo OTP

To show the OTP on-screen during signup, modify:

**File:** `lib/services/auth_service.dart`

**Function:** `sendInviteSignupEmailOTP()`

```dart
Future<Map<String, dynamic>> sendInviteSignupEmailOTP(String email) async {
  String otp = _generateOTP();  // Generate 6-digit OTP
  _otpStorage[email] = otp;
  
  // 🟢 DEMO MODE: Return OTP to show on screen
  return {
    'success': true,
    'message': 'Demo OTP: $otp',  // ← Shows in snackbar
    'otp': otp,
  };
}
```

---

## 📊 OTP Flow Summary

| Screen | OTP Send | OTP Verify | Next Step |
|--------|----------|-----------|-----------|
| **Login Screen** | Yes | Yes | PIN/Password entry |
| **Institute Registration** | Yes | Yes | Password setup |
| **Admin Registration** | Yes | Yes | Account creation |
| **Biometric Lock** | No | Yes (fallback) | Unlock app |

---

## ✅ Testing Checklist

- [ ] Try registration flow in institute_registration_screen
- [ ] See OTP sent message
- [ ] **With DEMO_MODE=true:** OTP shows on screen
- [ ] Enter OTP and verify
- [ ] Password fields appear
- [ ] Set password and complete registration
- [ ] Check students appear in database
- [ ] Try logging in with new account

---

**Current Status:** DEMO_MODE enabled - OTP shows on screen instead of using Brevo

To disable DEMO_MODE when ready for production:
```dart
const bool DEMO_MODE = false;  // Change back to true when production ready
```
