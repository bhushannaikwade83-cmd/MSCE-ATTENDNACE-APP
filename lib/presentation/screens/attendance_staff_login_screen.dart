import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/attendance_staff_auth.dart';
import '../../core/root_navigator.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/responsive_page.dart';
import '../../services/auth_service.dart';
import '../../services/geofence_service.dart';
import '../../services/session_manager.dart';
import 'login_screen.dart';
import 'staff_attendance_portal_screen.dart';
import 'institute_location_gate_screen.dart';

/// Login for institute instructors: Institute ID + PIN (access scoped by institute).
class AttendanceStaffLoginScreen extends StatefulWidget {
  static const routeName = '/attendance-staff-login';

  const AttendanceStaffLoginScreen({super.key});

  @override
  State<AttendanceStaffLoginScreen> createState() =>
      _AttendanceStaffLoginScreenState();
}

class _AttendanceStaffLoginScreenState extends State<AttendanceStaffLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _instituteCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  final _auth = AuthService();
  bool _busy = false;
  bool _isReturningUser = false;
  bool _instituteFieldDisabled = true;  // Start disabled, unlock only to change

  // Preferences key for saved institute code
  static const String _prefLastStaffInstituteCode = 'msce_last_staff_institute_code';

  @override
  void initState() {
    super.initState();
    _loadSavedInstitute();
  }

  @override
  void dispose() {
    _instituteCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  /// Load saved institute code for returning users
  Future<void> _loadSavedInstitute() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedInstituteCode = prefs.getString(_prefLastStaffInstituteCode);
      if (mounted) {
        if (savedInstituteCode != null && savedInstituteCode.isNotEmpty) {
          // Returning user: pre-fill and keep disabled
          setState(() {
            _instituteCtrl.text = savedInstituteCode;
            _isReturningUser = true;
            _instituteFieldDisabled = true;  // Locked permanently
          });
        }
        // First-time user: field stays disabled (auto-fetches during registration)
      }
    } catch (_) {}
  }

  /// Save institute code after successful login
  Future<void> _saveStaffInstituteCode(String instituteCode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final code = instituteCode.trim();
      if (code.isNotEmpty) {
        await prefs.setString(_prefLastStaffInstituteCode, code);
      }
    } catch (_) {}
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final res = await _auth.signInAttendanceStaff(
        instituteKey: _instituteCtrl.text.trim(),
        pin: _pinCtrl.text.trim(),
      );
      if (!mounted) return;
      if (res['success'] != true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res['message']?.toString() ?? 'Login failed'),
            backgroundColor: AppTheme.accentRed,
          ),
        );
        return;
      }

      final email = res['email']?.toString() ?? '';
      final canonId = res['canonicalInstituteId']?.toString() ?? '';
      final pin = _pinCtrl.text.trim();
      final pwd = email.isNotEmpty && canonId.isNotEmpty
          ? AttendanceStaffAuth.authPasswordFor(
              canonicalInstituteId: canonId,
              pin: pin,
            )
          : null;

      // Save institute code for next login
      await _saveStaffInstituteCode(_instituteCtrl.text);

      SessionManager.updateActivity();
      if (!mounted) return;

      final gateFuture = GeofenceService().attendanceLocationGateForCurrentUser(
        fastFenceSampleForLogin: true,
      );
      final cacheFuture = (email.isNotEmpty && canonId.isNotEmpty && pwd != null)
          ? Future.wait<void>([
              _auth.cachePinForAttendanceStaffLogin(
                email: email,
                pin: pin,
                canonicalInstituteId: canonId,
              ),
              _auth.cacheBiometricLogin(
                email: email,
                password: pwd,
              ),
            ])
          : Future<void>.value();

      final done = await Future.wait<dynamic>([cacheFuture, gateFuture]);
      final gate = done[1] as Map<String, dynamic>;
      if (!mounted) return;
      if (gate['allowed'] != true) {
        final nav = rootNavigatorKey.currentState;
        if (nav != null && nav.mounted) {
          nav.pushNamedAndRemoveUntil(
            InstituteLocationGateScreen.routeName,
            (_) => false,
            arguments: {'resumeRoute': StaffAttendancePortalScreen.routeName},
          );
        } else {
          Navigator.of(context, rootNavigator: true).pushNamedAndRemoveUntil(
            InstituteLocationGateScreen.routeName,
            (_) => false,
            arguments: {'resumeRoute': StaffAttendancePortalScreen.routeName},
          );
        }
        return;
      }

      // Use root navigator so staff portal replaces splash/lock, not a nested route.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final nav = rootNavigatorKey.currentState;
        if (nav != null && nav.mounted) {
          nav.pushNamedAndRemoveUntil(
            StaffAttendancePortalScreen.routeName,
            (_) => false,
          );
        } else {
          Navigator.of(context, rootNavigator: true).pushNamedAndRemoveUntil(
            StaffAttendancePortalScreen.routeName,
            (_) => false,
          );
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundGrey,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const GovTricolorStrip(),
          Expanded(
            child: ResponsiveScrollBody(
              padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 20.h),
              child: Form(
                key: _formKey,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Institute instructor login',
                        style: TextStyle(
                          fontSize: 22.sp,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.primaryBlue,
                        ),
                      ),
                      SizedBox(height: 8.h),
                      Text(
                        'Enter your institute\'s 5-digit Institute ID (e.g. 00000) and the PIN your admin set for your account. '
                        'Each instructor has their own PIN. Access is limited to that institute only.',
                        style: TextStyle(fontSize: 13.sp, color: AppTheme.textGray),
                      ),
                      SizedBox(height: 24.h),
                      TextFormField(
                        controller: _instituteCtrl,
                        keyboardType: TextInputType.number,
                        enabled: !_instituteFieldDisabled,
                        decoration: InputDecoration(
                          labelText: 'Institute ID',
                          helperText: _instituteFieldDisabled
                            ? 'Your registered institute (locked)'
                            : '5-digit code (leading zeros), e.g. 00000',
                          border: const OutlineInputBorder(),
                        ),
                        validator: (v) {
                          final t = v?.trim() ?? '';
                          if (t.isEmpty) return 'Required';
                          if (!RegExp(r'^\d+$').hasMatch(t)) {
                            return 'Use numeric Institute ID';
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: 16.h),
                      TextFormField(
                        controller: _pinCtrl,
                        obscureText: true,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        maxLength: 4,
                        decoration: const InputDecoration(
                          labelText: 'PIN (4 digits)',
                          border: OutlineInputBorder(),
                          counterText: '',
                        ),
                        validator: (v) {
                          final p = v?.trim() ?? '';
                          if (!AuthService.isValidLoginPinLength(p)) {
                            return AuthService.loginPinLengthMessage;
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: 28.h),
                      FilledButton(
                        onPressed: _busy ? null : _submit,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primaryBlue,
                          padding: EdgeInsets.symmetric(vertical: 14.h),
                        ),
                        child: _busy
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('LOG IN  |  लॉगिन'),
                      ),
                      SizedBox(height: 16.h),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => Navigator.pushReplacementNamed(
                                  context,
                                  LoginScreen.routeName,
                                ),
                        child: const Text('Back to admin login'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
