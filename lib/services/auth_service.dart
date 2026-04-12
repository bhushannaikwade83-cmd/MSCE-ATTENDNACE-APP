import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'dart:math';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_db.dart';
import '../core/supabase_maps.dart';
import 'error_handler.dart';
import 'validation_service.dart';
import 'batch_service.dart';
import 'database_init_service.dart';

class AuthService {
  SupabaseClient get _db => appDb;

  final Map<String, String> _otpStorage = {};
  final Map<String, String> _registrationOtpStorage = {};
  final Map<String, String> _verificationIdStorage = {};
  /// Login step after password+captcha: OTP keyed by normalized email (in-memory; debug prints code).
  final Map<String, String> _loginEmailOtpStorage = {};
  final Map<String, int> _loginEmailOtpExpiryEpoch = {};

  String _loginEmailOtpKey(String email) => email.trim().toLowerCase();

  /// Send a 6-digit OTP for the secure login step (after password verified, session signed out).
  Future<Map<String, dynamic>> sendLoginEmailOTP(String email) async {
    try {
      final key = _loginEmailOtpKey(email);
      if (key.isEmpty) {
        return {'success': false, 'message': 'Email is required'};
      }
      final otp = _generateOTP();
      _loginEmailOtpStorage[key] = otp;
      _loginEmailOtpExpiryEpoch[key] =
          DateTime.now().add(const Duration(minutes: 10)).millisecondsSinceEpoch ~/ 1000;
      if (kDebugMode) {
        debugPrint('📧 LOGIN OTP for $email: $otp (valid 10 min, in-memory demo)');
      }
      return {'success': true, 'message': 'OTP sent', 'otp': otp};
    } catch (e) {
      return {'success': false, 'message': 'Failed to send OTP'};
    }
  }

  /// Verify login OTP; on success clears stored OTP for that email.
  Future<Map<String, dynamic>> verifyLoginEmailOTP(String email, String otp) async {
    final key = _loginEmailOtpKey(email);
    final exp = _loginEmailOtpExpiryEpoch[key];
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (exp != null && now > exp) {
      _loginEmailOtpStorage.remove(key);
      _loginEmailOtpExpiryEpoch.remove(key);
      return {'success': false, 'message': 'OTP expired. Tap Resend OTP.'};
    }
    final stored = _loginEmailOtpStorage[key];
    if (stored == null || stored != otp.trim()) {
      return {'success': false, 'message': 'Invalid OTP'};
    }
    _loginEmailOtpStorage.remove(key);
    _loginEmailOtpExpiryEpoch.remove(key);
    return {'success': true, 'message': 'OTP verified'};
  }

  Future<void> _incrementInstituteField(String instituteId, String column) async {
    final row = await _db.from('institutes').select(column).eq('id', instituteId).maybeSingle();
    final n = (row?[column] as int?) ?? 0;
    await _db.from('institutes').update({column: n + 1}).eq('id', instituteId);
  }

  Map<String, dynamic> _profileBundle(Map<String, dynamic> row) {
    return {
      'profileId': row['id'].toString(),
      'userData': profileRowToUserData(row),
      'instituteId': row['institute_id'],
      'instituteName': row['institute_name'],
    };
  }

  Future<Map<String, dynamic>?> _findUserProfile({
    String? uid,
    String? email,
  }) async {
    try {
      if (uid != null && uid.isNotEmpty) {
        final row = await _db.from('profiles').select().eq('id', uid).maybeSingle();
        if (row != null) return _profileBundle(row);
      }
      if (email != null && email.isNotEmpty) {
        final row = await _db.from('profiles').select().eq('email', email).maybeSingle();
        if (row != null) return _profileBundle(row);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error in _findUserProfile: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>> registerAdmin({
    required String email,
    required String password,
    required String name,
    required String adminId,
  }) async {
    String? uid;
    try {
      await DatabaseInitService.ensureInitialized();

      final emailError = ValidationService.validateEmail(email);
      if (emailError != null) {
        return {'success': false, 'message': emailError};
      }

      final passwordError = ValidationService.validatePassword(password, isRegistration: true);
      if (passwordError != null) {
        return {'success': false, 'message': passwordError};
      }

      final nameError = ValidationService.validateName(name);
      if (nameError != null) {
        return {'success': false, 'message': nameError};
      }

      email = ValidationService.sanitizeInput(email);
      name = ValidationService.sanitizeInput(name);

      if (ValidationService.containsDangerousContent(email) ||
          ValidationService.containsDangerousContent(name)) {
        return {'success': false, 'message': 'Invalid characters detected in input'};
      }

      final adminIdError = ValidationService.validateRollNumber(adminId);
      if (adminIdError != null) {
        return {'success': false, 'message': adminIdError};
      }

      if (kDebugMode) debugPrint('🔐 Creating Supabase user for: $email');

      final res = await _db.auth.signUp(
        email: email,
        password: password,
        data: {'name': name},
      );
      final user = res.user;
      if (user == null) {
        return {'success': false, 'message': 'Could not create account'};
      }
      uid = user.id;

      await _db.from('profiles').upsert(
        {
          'id': uid,
          'email': email,
          'user_id': ValidationService.sanitizeInput(adminId),
          'name': name,
          'role': 'admin',
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'last_login': null,
        },
        onConflict: 'id',
      );

      await _db.auth.signOut();
      return {'success': true, 'message': 'Admin created successfully'};
    } on AuthException catch (e) {
      if (uid != null) {
        try {
          await _db.auth.signOut();
        } catch (_) {}
      }
      return {'success': false, 'message': ErrorHandler.handleAuthException(e)};
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Unexpected error: $e');
      return {'success': false, 'message': 'Error: ${e.toString()}'};
    }
  }

  Future<Map<String, dynamic>> addStudentManually({
    required String name,
    required String rollNumber,
    required String year,
    required String contactNo,
    String? batchId,
    String? batchName,
    String? batchTiming,
    String? subject,
    String? instituteId,
    String? semester,
    String? semesterName,
    List<String>? batchIds,
    List<String>? subjects,
  }) async {
    await DatabaseInitService.ensureInitialized();

    final nameError = ValidationService.validateName(name);
    if (nameError != null) {
      return {'success': false, 'message': nameError};
    }

    final rollNumberError = ValidationService.validateRollNumber(rollNumber);
    if (rollNumberError != null) {
      return {'success': false, 'message': rollNumberError};
    }

    name = ValidationService.sanitizeInput(name);
    rollNumber = ValidationService.sanitizeInput(rollNumber);
    year = ValidationService.sanitizeInput(year);
    contactNo = ValidationService.sanitizeInput(contactNo);
    if (batchName != null) batchName = ValidationService.sanitizeInput(batchName);
    if (batchTiming != null) batchTiming = ValidationService.sanitizeInput(batchTiming);

    if (ValidationService.containsDangerousContent(name) ||
        ValidationService.containsDangerousContent(rollNumber) ||
        ValidationService.containsDangerousContent(year) ||
        ValidationService.containsDangerousContent(contactNo)) {
      return {'success': false, 'message': 'Invalid characters detected in input'};
    }

    try {
      String? currentInstituteId = instituteId;

      if (currentInstituteId == null) {
        final u = _db.auth.currentUser;
        if (u != null) {
          final prof = await _findUserProfile(uid: u.id);
          currentInstituteId = prof?['instituteId'] as String?;
        }
      }

      if (currentInstituteId == null || currentInstituteId.isEmpty) {
        return {
          'success': false,
          'message':
              'Cannot add student: Institute ID not found. Please ensure you are logged in as an admin of an institute.',
        };
      }

      try {
        final existing = await _db
            .from('students')
            .select('id, batch_id, batch_ids, batch_name')
            .eq('institute_id', currentInstituteId)
            .eq('user_id', rollNumber);

        if (batchId != null) {
          for (final row in existing) {
            if (row['batch_id'] == batchId) {
              return {'success': false, 'message': 'Roll Number already exists in this batch'};
            }
            final arr = row['batch_ids'];
            if (arr is List && arr.contains(batchId)) {
              return {'success': false, 'message': 'Roll Number already exists in one of the selected batches'};
            }
          }
        } else if (batchName != null) {
          final normalizedNew = ValidationService.normalizeBatchName(batchName);
          for (final row in existing) {
            final bn = row['batch_name'] as String? ?? '';
            if (ValidationService.normalizeBatchName(bn) == normalizedNew) {
              return {
                'success': false,
                'message': 'Roll Number already exists in this batch. Existing batch: "$bn"',
              };
            }
          }
        } else {
          if (existing.isNotEmpty) {
            return {'success': false, 'message': 'Roll Number already exists in this institute'};
          }
        }
      } catch (e) {
        if (kDebugMode) debugPrint('⚠️ Duplicate check: $e');
      }

      final docId = 'MANUAL_${DateTime.now().millisecondsSinceEpoch}';

      final studentData = <String, dynamic>{
        'id': docId,
        'institute_id': currentInstituteId,
        'uid': docId,
        'user_id': rollNumber,
        'name': name,
        'email': '',
        'phone_number': contactNo,
        'year': year,
        if (batchId != null) 'batch_id': batchId,
        if (batchIds != null && batchIds.isNotEmpty) 'batch_ids': batchIds,
        'batch_name': batchName ?? '',
        'batch_timing': batchTiming ?? '',
        if (subject != null && subject.isNotEmpty) 'subject': subject,
        if (subjects != null && subjects.isNotEmpty) 'subjects': subjects,
        if (semester != null) 'semester': semester,
        if (semesterName != null) 'semester_name': semesterName,
        'role': 'student',
        'status': 'approved',
        'has_device': false,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      };

      await _db.from('students').insert(studentData);

      if (batchIds != null && batchIds.isNotEmpty) {
        final batchService = BatchService();
        for (final bid in batchIds) {
          try {
            await batchService.incrementStudentCount(currentInstituteId, bid);
          } catch (e) {
            if (kDebugMode) debugPrint('⚠️ increment batch $bid: $e');
          }
        }
      } else if (batchId != null) {
        try {
          final batchService = BatchService();
          await batchService.incrementStudentCount(currentInstituteId, batchId);
        } catch (e) {
          if (kDebugMode) debugPrint('⚠️ increment batch: $e');
        }
      }

      try {
        await _incrementInstituteField(currentInstituteId, 'student_count');
      } catch (e) {
        if (kDebugMode) debugPrint('⚠️ student_count: $e');
      }

      return {
        'success': true,
        'message': 'Student added successfully to batch',
        'instituteId': currentInstituteId,
        'studentId': docId,
      };
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('❌ addStudentManually: $e');
        debugPrint('$stackTrace');
      }
      return {'success': false, 'message': 'Failed to save student: ${e.toString()}'};
    }
  }

  Future<Map<String, dynamic>> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      await _db.auth.signInWithPassword(email: email, password: password);
      final uid = _db.auth.currentUser!.id;

      if (kDebugMode) debugPrint('Login attempt - Email: $email, UID: $uid');

      final profile = await _findUserProfile(uid: uid, email: email);
      if (profile == null) {
        await _db.auth.signOut();
        return {
          'success': false,
          'message':
              'User profile not found. Please ensure you are registered as an admin user.\n\nTroubleshooting:\n1. Verify your email: $email\n2. Ensure a profile row exists in Supabase `profiles` for your user id.',
        };
      }

      final userData = profile['userData'] as Map<String, dynamic>;
      final instituteId = profile['instituteId'] as String?;
      final instituteName = profile['instituteName'] as String?;

      if (userData.isEmpty) {
        await _db.auth.signOut();
        return {'success': false, 'message': 'User profile data is empty. Please register again.'};
      }

      String role = (userData['role'] ?? '').toString();
      final isAllowedRole = role == 'admin' || role == 'super_admin';
      if (!isAllowedRole) {
        await _db.auth.signOut();
        return {
          'success': false,
          'message':
              'Access denied. Only Admin or Super Admin can login.\n\nYour role: $role',
        };
      }

      final status = (userData['status'] ?? '').toString().toLowerCase();
      if (status.isNotEmpty && status != 'approved' && status != 'active') {
        await _db.auth.signOut();
        final pendingMsg = status == 'pending'
            ? 'Your institute admin registration is waiting for approval. An administrator must approve you on the MSCE web admin portal before you can log in.'
            : 'Your admin account is not approved yet. Current status: $status.\n\nAsk your organization to approve you on the admin web portal (same Supabase project).';
        return {
          'success': false,
          'message': pendingMsg,
          'openAdminPortal': true,
        };
      }

      if (instituteId != null && instituteId.isNotEmpty) {
        if (kDebugMode) debugPrint('✅ User is admin of institute: $instituteId ($instituteName)');
      }

      try {
        await _db.from('profiles').update({
          'last_login': DateTime.now().toUtc().toIso8601String(),
          'last_login_ip': '192.168.1.1',
        }).eq('id', uid);
      } catch (e) {
        if (kDebugMode) debugPrint('Warning: Could not update lastLogin: $e');
      }

      return {
        'success': true,
        'userId': uid,
        'role': userData['role'],
        'instituteId': instituteId,
        'instituteName': instituteName,
        'userData': userData,
      };
    } on AuthException catch (e) {
      return ErrorHandler.formatErrorForUI(e, context: 'signInWithEmail', appType: 'admin');
    } catch (e) {
      return {'success': false, 'message': 'Login failed: ${e.toString()}'};
    }
  }

  Future<Map<String, dynamic>> signInWithId({
    required String userId,
    required String password,
    required String role,
  }) async {
    try {
      final rows = await _db.from('profiles').select().eq('user_id', userId).eq('role', role).limit(1);

      if (rows.isEmpty) {
        return {'success': false, 'message': 'User ID not found'};
      }

      final row = rows.first;
      final email = row['email'] as String?;
      if (email == null || email.isEmpty) {
        return {'success': false, 'message': 'User has no email on file'};
      }

      await _db.auth.signInWithPassword(email: email, password: password);

      String userRole = (row['role'] ?? '').toString();
      if (userRole != 'admin' && userRole != 'super_admin') {
        await _db.auth.signOut();
        return {'success': false, 'message': 'Access denied. Only Admin or Super Admin can login.'};
      }

      final pid = row['id'].toString();
      await _db.from('profiles').update({
        'last_login': DateTime.now().toUtc().toIso8601String(),
        'last_login_ip': '192.168.1.1',
      }).eq('id', pid);

      return {
        'success': true,
        'userId': pid,
        'role': row['role'],
        'userData': profileRowToUserData(row),
      };
    } on AuthException catch (e) {
      return ErrorHandler.formatErrorForUI(e, context: 'signInWithEmail', appType: 'admin');
    } catch (e) {
      return {'success': false, 'message': 'Login failed: ${e.toString()}'};
    }
  }

  Future<Map<String, dynamic>> setPIN({
    required String userId,
    required String pin,
  }) async {
    try {
      if (pin.length < 4 || pin.length > 6) {
        return {'success': false, 'message': 'PIN must be 4-6 digits'};
      }
      if (!RegExp(r'^\d+$').hasMatch(pin)) {
        return {'success': false, 'message': 'PIN must contain only digits'};
      }

      final pinHash = sha256.convert(utf8.encode(pin)).toString();

      await _db.from('profiles').update({
        'pin_hash': pinHash,
        'pin_set_at': DateTime.now().toUtc().toIso8601String(),
        'has_pin': true,
      }).eq('id', userId);

      return {'success': true, 'message': 'PIN set successfully'};
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error setting PIN: $e');
      return {'success': false, 'message': 'Failed to set PIN: ${e.toString()}'};
    }
  }

  Future<bool> hasPIN(String userId) async {
    try {
      final profile = await _findUserProfile(uid: userId);
      if (profile == null) return false;
      final userData = profile['userData'] as Map<String, dynamic>;
      return userData['hasPIN'] == true;
    } catch (e) {
      return false;
    }
  }

  /// Whether the profile for [email] has a PIN (for IRCTC-style returning-user flow).
  Future<bool> hasPINForEmail(String email) async {
    try {
      final profile = await _findUserProfile(email: email.trim());
      if (profile == null) return false;
      final userData = profile['userData'] as Map<String, dynamic>;
      return userData['hasPIN'] == true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> verifyPIN(String userId, String pin) async {
    try {
      final profile = await _findUserProfile(uid: userId);
      if (profile == null) return false;
      final userData = profile['userData'] as Map<String, dynamic>;
      final storedPinHash = userData['pinHash'] as String?;
      if (storedPinHash == null) return false;
      final providedPinHash = sha256.convert(utf8.encode(pin)).toString();
      return providedPinHash == storedPinHash;
    } catch (e) {
      return false;
    }
  }

  Future<Map<String, dynamic>> signInWithPIN({
    required String email,
    required String pin,
  }) async {
    try {
      final profile = await _findUserProfile(email: email);
      if (profile == null) {
        return {'success': false, 'message': 'User not found'};
      }

      final userData = profile['userData'] as Map<String, dynamic>;
      final uid = userData['uid'] as String? ?? profile['profileId'] as String;

      if (userData['hasPIN'] != true) {
        return {'success': false, 'message': 'PIN not set. Please login with password first to set PIN.'};
      }

      final storedPinHash = userData['pinHash'] as String?;
      if (storedPinHash == null) {
        return {'success': false, 'message': 'PIN not configured'};
      }

      final providedPinHash = sha256.convert(utf8.encode(pin)).toString();
      if (providedPinHash != storedPinHash) {
        return {'success': false, 'message': 'Invalid PIN'};
      }

      final encryptedPassword = userData['encryptedPassword'] as String?;
      if (encryptedPassword == null) {
        return {'success': false, 'message': 'Please login with password first to enable PIN login'};
      }

      final password = _decryptPassword(encryptedPassword, pin);

      try {
        await _db.auth.signInWithPassword(email: email, password: password);
      } on AuthException catch (e) {
        return {'success': false, 'message': ErrorHandler.handleAuthException(e)};
      }

      final instituteId = profile['instituteId'] as String? ?? userData['instituteId'] as String?;
      final instituteName = profile['instituteName'] as String? ?? userData['instituteName'] as String?;

      final role = (userData['role'] ?? '').toString();
      if (role != 'admin' && role != 'super_admin') {
        await _db.auth.signOut();
        return {'success': false, 'message': 'Access denied. Only Admin or Super Admin can login.'};
      }
      final status = (userData['status'] ?? '').toString().toLowerCase();
      if (status.isNotEmpty && status != 'approved' && status != 'active') {
        await _db.auth.signOut();
        final pendingMsg = status == 'pending'
            ? 'Your institute admin registration is waiting for approval. An administrator must approve you on the MSCE web admin portal before you can log in.'
            : 'Your admin account is not approved yet. Current status: $status.\n\nAsk your organization to approve you on the admin web portal (same Supabase project).';
        return {
          'success': false,
          'message': pendingMsg,
          'openAdminPortal': true,
        };
      }

      await _db.from('profiles').update({
        'last_login': DateTime.now().toUtc().toIso8601String(),
        'last_login_ip': '192.168.1.1',
      }).eq('id', uid);

      return {
        'success': true,
        'userId': uid,
        'role': userData['role'],
        'instituteId': instituteId,
        'instituteName': instituteName,
        'userData': userData,
      };
    } catch (e) {
      if (kDebugMode) debugPrint('❌ PIN login error: $e');
      return {'success': false, 'message': 'PIN login failed: ${e.toString()}'};
    }
  }

  Future<Map<String, dynamic>> setPINWithPassword({
    required String userId,
    required String pin,
    required String password,
  }) async {
    try {
      if (pin.length < 4 || pin.length > 6) {
        return {'success': false, 'message': 'PIN must be 4-6 digits'};
      }
      if (!RegExp(r'^\d+$').hasMatch(pin)) {
        return {'success': false, 'message': 'PIN must contain only digits'};
      }

      final pinHash = sha256.convert(utf8.encode(pin)).toString();
      final encryptedPassword = _encryptPassword(password, pin);

      final profile = await _findUserProfile(uid: userId);
      if (profile == null) {
        return {'success': false, 'message': 'User profile not found for PIN setup'};
      }
      final profileId = profile['profileId'] as String;
      await _db.from('profiles').update({
        'pin_hash': pinHash,
        'encrypted_password': encryptedPassword,
        'pin_set_at': DateTime.now().toUtc().toIso8601String(),
        'has_pin': true,
      }).eq('id', profileId);

      return {'success': true, 'message': 'PIN set successfully'};
    } catch (e) {
      return {'success': false, 'message': 'Failed to set PIN: ${e.toString()}'};
    }
  }

  Future<Map<String, dynamic>> resetPIN({
    required String email,
    required String password,
    required String newPin,
  }) async {
    try {
      final authResult = await signInWithEmail(email: email, password: password);
      if (authResult['success'] != true) {
        return authResult;
      }

      final userId = authResult['userId'] as String;

      return await setPINWithPassword(
        userId: userId,
        pin: newPin,
        password: password,
      );
    } catch (e) {
      return {'success': false, 'message': 'Failed to reset PIN: ${e.toString()}'};
    }
  }

  String _encryptPassword(String password, String pin) {
    final passwordBytes = utf8.encode(password);
    final pinBytes = utf8.encode(pin);
    final encrypted = <int>[];
    for (int i = 0; i < passwordBytes.length; i++) {
      encrypted.add(passwordBytes[i] ^ pinBytes[i % pinBytes.length]);
    }
    return base64Encode(encrypted);
  }

  String _decryptPassword(String encryptedPassword, String pin) {
    final encrypted = base64Decode(encryptedPassword);
    final pinBytes = utf8.encode(pin);
    final decrypted = <int>[];
    for (int i = 0; i < encrypted.length; i++) {
      decrypted.add(encrypted[i] ^ pinBytes[i % pinBytes.length]);
    }
    return utf8.decode(decrypted);
  }

  Future<Map<String, dynamic>> sendOTP(String userId) async {
    try {
      String otp = _generateOTP();
      _otpStorage[userId] = otp;
      if (kDebugMode) debugPrint('🔐 SECURITY OTP for $userId: $otp');
      return {'success': true, 'message': 'OTP sent', 'otp': otp};
    } catch (e) {
      return {'success': false, 'message': 'Failed to send OTP'};
    }
  }

  Future<Map<String, dynamic>> verifyOTP({
    required String userId,
    required String otp,
  }) async {
    String? storedOtp = _otpStorage[userId];
    if (storedOtp == null || storedOtp != otp) {
      return {'success': false, 'message': 'Invalid or expired OTP'};
    }
    _otpStorage.remove(userId);
    return {'success': true, 'message': 'OTP verified'};
  }

  Future<void> signOut() async {
    try {
      await _db.auth.signOut();
    } catch (e) {
      if (kDebugMode) debugPrint('Error signing out: $e');
    }
  }

  Future<Map<String, dynamic>> sendRegistrationOTP(String mobile) async {
    try {
      if (mobile.isEmpty || mobile.length != 10) {
        return {'success': false, 'message': 'Invalid mobile number. Must be 10 digits'};
      }

      String otp = _generateOTP();
      String verificationId = 'VER_${DateTime.now().millisecondsSinceEpoch}_$mobile';

      _registrationOtpStorage[verificationId] = otp;
      _verificationIdStorage[mobile] = verificationId;

      if (kDebugMode) debugPrint('📱 REGISTRATION OTP for $mobile: $otp');

      return {
        'success': true,
        'message': 'OTP sent successfully',
        'otp': otp,
        'verificationId': verificationId,
      };
    } catch (e) {
      return {'success': false, 'message': 'Failed to send OTP: ${e.toString()}'};
    }
  }

  Future<Map<String, dynamic>> verifyRegistrationOTP({
    required String verificationId,
    required String otp,
    required String mobile,
  }) async {
    String? storedOtp = _registrationOtpStorage[verificationId];

    if (storedOtp == null) {
      return {'success': false, 'message': 'Invalid verification ID or OTP expired'};
    }

    if (storedOtp != otp) {
      return {'success': false, 'message': 'Invalid OTP'};
    }

    _registrationOtpStorage.remove(verificationId);
    _verificationIdStorage.remove(mobile);

    return {'success': true, 'message': 'OTP verified successfully'};
  }

  Future<Map<String, dynamic>> registerInstituteUser({
    required String instituteId,
    required String instituteName,
    required String name,
    required String email,
    required String password,
    required String mobile,
  }) async {
    try {
      await DatabaseInitService.ensureInitialized();

      // RLS often blocks pre-signup duplicate checks for anonymous users; Auth enforces unique email.

      final res = await _db.auth.signUp(
        email: email,
        password: password,
        data: {
          'name': name,
          'institute_id': instituteId,
          'institute_name': instituteName,
          'phone_number': mobile,
        },
      );
      final user = res.user;
      if (user == null) {
        return {'success': false, 'message': 'Could not create account'};
      }
      final uid = user.id;

      // profiles + user_credentials + user_count are created by trigger
      // public.handle_institute_admin_signup (migration 012) so this works even when
      // email confirmation is ON and signUp returns no session (RLS would block client inserts).

      if (kDebugMode) {
        debugPrint(
          '📧 Institute admin signup $email / $instituteName — session: ${res.session != null}',
        );
      }

      await _db.auth.signOut();

      final needsEmailConfirm = res.session == null;
      return {
        'success': true,
        'message': needsEmailConfirm
            ? 'Account created. Disable “Confirm email” in Supabase Auth if login is blocked. Your admin access is pending approval on the web portal — you cannot log in until an administrator approves you.'
            : 'Registration submitted. Your institute admin access is pending approval on the web portal. You cannot log in until an administrator approves your account.',
        'userId': uid,
        'needsEmailConfirmation': needsEmailConfirm,
        'pendingApproval': true,
      };
    } on AuthException catch (e) {
      final lower = e.toString().toLowerCase();

      if (lower.contains('over_email_send_rate_limit') ||
          lower.contains('email rate limit exceeded') ||
          lower.contains('statuscode: 429')) {
        return {
          'success': false,
          'message':
              'Too many signup email requests were sent. Please wait a few minutes and try again, or use a different test email.',
        };
      }

      if (lower.contains('user_already_exists') || lower.contains('already registered')) {
        return {
          'success': false,
          'message':
              'This email is already registered in Authentication. Use login/reset password, or create the institute admin with a different email.',
        };
      }

      return ErrorHandler.formatErrorForUI(e, context: 'registerInstituteUser', appType: 'admin');
    } catch (e) {
      return ErrorHandler.formatErrorForUI(e, context: 'registerInstituteUser', appType: 'admin');
    }
  }

  Future<Map<String, dynamic>> initializeDefaultInstitutes() async {
    try {
      await DatabaseInitService.ensureInitialized();

      if (kDebugMode) debugPrint('📚 Initializing default institutes...');
      List<String> created = [];
      List<String> skipped = [];

      Future<void> upsert(String id, Map<String, dynamic> row) async {
        final ex = await _db.from('institutes').select('id').eq('id', id).maybeSingle();
        if (ex != null) {
          skipped.add(id);
          return;
        }
        await _db.from('institutes').insert(row);
        created.add(id);
      }

      await upsert('3333', {
        'id': '3333',
        'institute_code': '3333',
        'name': 'MSCE Pune',
        'location': 'Pune',
        'address': 'Pune',
        'city': 'Pune',
        'district': 'Pune',
        'taluka': 'Haveli',
        'state': 'Maharashtra',
        'country': 'India',
        'mobile_no': '8329012808',
        'is_active': true,
        'user_count': 0,
        'student_count': 0,
      });

      await upsert('dummy01', {
        'id': 'dummy01',
        'institute_code': '',
        'name': 'Lakshya Institute',
        'location': 'Dombivali West',
        'address': 'Dombivali West',
        'city': 'Mumbai',
        'district': '',
        'taluka': '',
        'state': 'Maharashtra',
        'country': 'India',
        'mobile_no': '',
        'is_active': true,
        'user_count': 0,
        'student_count': 0,
      });

      return {
        'success': true,
        'message': 'Institutes initialized successfully',
        'created': created,
        'skipped': skipped,
      };
    } catch (e) {
      return {'success': false, 'message': 'Error initializing institutes: ${e.toString()}'};
    }
  }

  Future<Map<String, dynamic>> createInstitute({
    required String instituteId,
    required String name,
    String? instituteCode,
    String? location,
    String? address,
    String? city,
    String? district,
    String? taluka,
    String? state,
    String? country,
    String? mobileNo,
  }) async {
    try {
      await DatabaseInitService.ensureInitialized();

      final existingById = await _db.from('institutes').select('id').eq('id', instituteId).maybeSingle();
      if (existingById != null) {
        return {'success': false, 'message': 'Institute with this ID already exists'};
      }

      if (instituteCode != null && instituteCode.isNotEmpty) {
        final existingByCode = await _db
            .from('institutes')
            .select('id')
            .eq('institute_code', instituteCode)
            .maybeSingle();
        if (existingByCode != null) {
          return {'success': false, 'message': 'Institute with this code already exists'};
        }
      }

      await _db.from('institutes').insert({
        'id': instituteId,
        'institute_code': instituteCode ?? '',
        'name': name,
        'location': location ?? '',
        'address': address ?? '',
        'city': city ?? '',
        'district': district ?? '',
        'taluka': taluka ?? '',
        'state': state ?? '',
        'country': country ?? 'India',
        'mobile_no': mobileNo ?? '',
        'is_active': true,
        'user_count': 0,
        'student_count': 0,
      });

      return {
        'success': true,
        'message': 'Institute created successfully',
        'instituteId': instituteId,
      };
    } catch (e) {
      return {'success': false, 'message': 'Error creating institute: ${e.toString()}'};
    }
  }

  Future<Map<String, dynamic>> signInWithEmailAndInstitute({
    required String email,
    required String password,
    String? instituteId,
  }) async {
    try {
      await _db.auth.signInWithPassword(email: email, password: password);
      final uid = _db.auth.currentUser!.id;

      final row = await _db.from('profiles').select().eq('id', uid).maybeSingle();
      if (row == null) {
        await _db.auth.signOut();
        return {'success': false, 'message': 'User not found'};
      }

      final userData = profileRowToUserData(row);
      final userInstituteId = row['institute_id'] as String?;

      if (instituteId != null && userInstituteId != instituteId) {
        await _db.auth.signOut();
        return {'success': false, 'message': 'User does not belong to this institute'};
      }

      String role = (userData['role'] ?? '').toString();
      if (role != 'admin' && role != 'super_admin') {
        await _db.auth.signOut();
        return {'success': false, 'message': 'Access denied. Only Admin or Super Admin can login.'};
      }

      await _db.from('profiles').update({
        'last_login': DateTime.now().toUtc().toIso8601String(),
        'last_login_ip': '192.168.1.1',
      }).eq('id', uid);

      return {
        'success': true,
        'userId': uid,
        'role': userData['role'],
        'instituteId': userInstituteId,
        'instituteName': row['institute_name'],
        'userData': userData,
      };
    } on AuthException catch (e) {
      return ErrorHandler.formatErrorForUI(e, context: 'signInWithEmail', appType: 'admin');
    } catch (e) {
      return {'success': false, 'message': 'Login failed: ${e.toString()}'};
    }
  }

  String _generateOTP() {
    return (100000 + Random().nextInt(900000)).toString();
  }
}
