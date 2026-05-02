# NEW AUTHENTICATION FLOW - IMPLEMENTATION SUMMARY

## Overview
Replacing email-based authentication with **Institute ID (numeric only) + Password** authentication.

---

## Database Changes ✅ COMPLETE

### Migration: `023_admin_password_auth.sql`
```sql
-- Created:
- admin_passwords table (bcrypt hashed passwords)
- admin_login_by_institute(institute_key, password) RPC function
- set_admin_password(profile_id, password) RPC function
```

---

## Flutter App Changes

### 1. Auth Service Updates ✅ COMPLETE
Added to `/lib/services/auth_service.dart`:
```dart
✅ getAdminInvites() → {invites: [...]}
✅ adminLoginByInstitute(instituteKey, password) → {success, userId, profile}
✅ setAdminPassword(profileId, password) → {success}
✅ claimAdminInvite(inviteId, email, password) → {success, userId}
```

### 2. Login Screen Changes 📝 IN PROGRESS
Modify `/lib/presentation/screens/login_screen.dart`:

#### Controller Changes:
```dart
// REMOVE:
- final _emailController
- final _captchaController
- final _emailOtpController

// REPLACE WITH:
final _instituteIdController = TextEditingController();  // Numeric only
final _passwordController = TextEditingController();
final _otpController = TextEditingController();          // OTP for registration
final _newPasswordController = TextEditingController();
final _confirmPasswordController = TextEditingController();
```

#### State Variables:
```dart
// REMOVE:
- _savedEmail
- _prefLastEmail
- All email-based biometric code

// ADD:
int _authStep = 3;  // 0=invites, 1=otp, 2=password, 3=login
List<Map<String, dynamic>> _adminInvites = [];
Map<String, dynamic>? _selectedInvite;
String _savedInstituteId;  // Replace _savedEmail
```

#### New Methods to Add:
```dart
Future<void> _loadAdminInvites() async {
  // Load pending admin invites for registration
  final result = await _authService.getAdminInvites();
  setState(() {
    _adminInvites = result['invites'] ?? [];
    _authStep = 0;  // Show invites screen
  });
}

Future<void> _adminLoginByInstitute() async {
  // NEW LOGIN: Institute ID + Password (NO EMAIL, NO OTP)
  final instituteId = _instituteIdController.text.trim();
  final password = _passwordController.text;
  
  if (instituteId.isEmpty || password.isEmpty) {
    _showModernSnackbar('Institute ID and Password required', isSuccess: false);
    return;
  }
  
  setState(() => _isLoading = true);
  
  final result = await _authService.adminLoginByInstitute(
    instituteKey: instituteId,
    password: password,
  );
  
  if (result['success']) {
    // Save institute ID instead of email
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefLastInstituteId, instituteId);
    
    _currentUserId = result['userId'];
    _navigateToHome();
  } else {
    setState(() => _isLoading = false);
    _showModernSnackbar(result['message'], isSuccess: false);
  }
}

void _startRegistration() async {
  // Load invites and show Step 0: Select Institute
  await _loadAdminInvites();
}

void _verifyOtp() {
  // Step 1: Verify OTP sent to email
  if (_otpController.text.trim() != _demoOtp) {
    _showModernSnackbar('Invalid OTP', isSuccess: false);
    return;
  }
  setState(() => _authStep = 2);  // Move to password creation
}

Future<void> _createPassword() async {
  // Step 2: Create password and complete registration
  final password = _newPasswordController.text;
  final confirmPassword = _confirmPasswordController.text;
  
  if (password != confirmPassword) {
    _showModernSnackbar('Passwords do not match', isSuccess: false);
    return;
  }
  
  if (password.length < 8) {
    _showModernSnackbar('Password must be 8+ characters', isSuccess: false);
    return;
  }
  
  setState(() => _isLoading = true);
  
  final result = await _authService.claimAdminInvite(
    inviteId: _selectedInvite!['id'],
    instituteId: _selectedInvite!['institute_id'],
    email: _selectedInvite!['email'],
    password: password,
  );
  
  if (result['success']) {
    _showModernSnackbar('✅ Registration complete! Logging in...', isSuccess: true);
    await Future.delayed(const Duration(seconds: 2));
    setState(() {
      _authStep = 3;  // Back to login
      _instituteIdController.text = _selectedInvite!['institute_id'];
    });
  } else {
    setState(() => _isLoading = false);
    _showModernSnackbar(result['message'], isSuccess: false);
  }
}
```

#### UI Changes - Build Method:
```dart
// Replace entire build() with logic to show:
// _authStep == 0 → _buildInvitesScreen()   (Select institute)
// _authStep == 1 → _buildOtpScreen()       (Verify OTP)
// _authStep == 2 → _buildPasswordScreen()  (Create password)
// _authStep == 3 → _buildLoginScreen()     (Login with Institute ID + Password)
```

---

## Website Changes 📝 TODO

### Location: `/website/` folder (in project root)

#### 1. Admin Invite Panel
File: `admin/invites.html` (or equivalent)
```html
<!-- Form to create admin invites -->
<form>
  <input type="number" placeholder="Institute ID (numeric)" required>
  <input type="text" placeholder="Admin Full Name" required>
  <input type="email" placeholder="Admin Email" required>
  <input type="tel" placeholder="Admin Mobile" required>
  <button type="submit">Send Invite</button>
</form>

<!-- Displays generated OTP for demo (copy to app manually) -->
<div id="demo-otp">OTP: 123456</div>
```

#### 2. Institute Management
File: `admin/institutes.html` (or equivalent)
```html
<!-- Create institutes with numeric code -->
<form>
  <input type="number" placeholder="Institute ID (numeric)" required>
  <input type="text" placeholder="Institute Name" required>
  <input type="text" placeholder="Address" required>
  <input type="tel" placeholder="Phone" required>
  <button type="submit">Create Institute</button>
</form>
```

#### 3. Backend Endpoints Needed
```
POST /api/admin/invites/create
  → Creates admin_invites record
  → Returns demo OTP (for testing)
  
POST /api/admin/register/verify-otp
  → Verifies OTP matches invite
  
POST /api/admin/register/complete
  → Claims invite + creates profile
  → Saves password hash
```

---

## Testing Checklist

### Registration Flow:
- [ ] Load admin invites from website
- [ ] Select institute invitation
- [ ] Receive OTP (demo shows on mobile)
- [ ] Enter OTP
- [ ] Create password (8+ chars)
- [ ] Save to database
- [ ] Redirect to login

### Login Flow:
- [ ] Enter Institute ID (numeric only)
- [ ] Enter password
- [ ] Successful login
- [ ] Save Institute ID to SharedPreferences
- [ ] Navigate to home with PIN setup

### Returning User:
- [ ] Show PIN screen with saved Institute ID
- [ ] Enter PIN to login
- [ ] Skip registration step

---

## Key Points
1. **Institute ID is numeric only** (e.g., "3001", not "INST_3001")
2. **No email in login** - Only Institute ID + Password
3. **OTP only for registration** - Not used in login
4. **NEW: admin_passwords table** - Stores bcrypt hashes
5. **Website integration** - Provides invites + demo OTP generation

---

## Files Modified/Created

### ✅ Complete:
- `/supabase/migrations/023_admin_password_auth.sql` - Database
- `/lib/services/auth_service.dart` - 4 new auth methods
- `/lib/presentation/screens/institute_admin_registration_screen.dart` - Registration screen

### 📝 Still Need:
- `/lib/presentation/screens/login_screen.dart` - Modify existing
- `/website/*` - Admin panels for invites and institutes

