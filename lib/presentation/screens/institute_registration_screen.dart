import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../core/utils/responsive.dart';
import '../../services/auth_service.dart';
import '../../services/error_handler.dart';
import '../../core/theme/app_theme.dart';
import 'login_screen.dart';

class InstituteRegistrationScreen extends StatefulWidget {
  final String instituteId;
  final String instituteName;
  final String instituteLocation;

  const InstituteRegistrationScreen({
    super.key,
    required this.instituteId,
    required this.instituteName,
    required this.instituteLocation,
  });

  static const routeName = '/institute-registration';

  @override
  State<InstituteRegistrationScreen> createState() => _InstituteRegistrationScreenState();
}

class _InstituteRegistrationScreenState extends State<InstituteRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _mobileController = TextEditingController();
  final _otpController = TextEditingController();
  final AuthService _authService = AuthService();

  bool _isPasswordVisible = false;
  bool _isLoading = false;
  bool _showOtpField = false;
  int _otpTimeLeft = 60;
  Timer? _otpTimer;
  String? _verificationId;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _mobileController.dispose();
    _otpController.dispose();
    _otpTimer?.cancel();
    super.dispose();
  }

  void _startOtpTimer() {
    _otpTimeLeft = 60;
    _otpTimer?.cancel();
    _otpTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _otpTimeLeft--;
        if (_otpTimeLeft <= 0) {
          timer.cancel();
        }
      });
    });
  }

  Future<void> _sendOTP() async {
    if (_mobileController.text.isEmpty) {
      _showError('Please enter mobile number first');
      return;
    }

    if (_mobileController.text.length != 10) {
      _showError('Mobile number must be 10 digits');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await _authService.sendRegistrationOTP(_mobileController.text.trim());
      
      setState(() {
        _isLoading = false;
        _showOtpField = result['success'] ?? false;
        if (result['success'] == true) {
          _verificationId = result['verificationId'];
          _startOtpTimer();
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  result['success'] == true ? Icons.check_circle : Icons.error_outline,
                  color: Colors.white,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    result['success'] == true
                        ? 'OTP sent to ${_mobileController.text.trim()} (Demo OTP: ${result['otp'] ?? 'N/A'})'
                        : result['message'] ?? 'Failed to send OTP',
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ],
            ),
            backgroundColor: result['success'] == true ? AppTheme.primaryGreen : AppTheme.accentRed,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Error sending OTP: $e');
    }
  }

  Future<void> _handleRegistration() async {
    if (!_formKey.currentState!.validate()) return;

    if (!_showOtpField) {
      _showError('Please verify OTP first');
      return;
    }

    setState(() => _isLoading = true);

    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final mobile = _mobileController.text.trim();
    final otp = _otpController.text.trim();

    try {
      // Verify OTP first
      if (_verificationId == null || _verificationId!.isEmpty) {
        setState(() => _isLoading = false);
        _showError('Please verify OTP first');
        return;
      }

      final otpResult = await _authService.verifyRegistrationOTP(
        verificationId: _verificationId!,
        otp: otp,
        mobile: mobile,
      );

      if (otpResult['success'] != true) {
        setState(() => _isLoading = false);
        _showError(otpResult['message'] ?? 'OTP verification failed');
        return;
      }

      // Register user with institute
      final result = await _authService.registerInstituteUser(
        instituteId: widget.instituteId,
        instituteName: widget.instituteName,
        name: name,
        email: email,
        password: password,
        mobile: mobile,
      );

      if (!mounted) return;

      setState(() => _isLoading = false);

      if (result['success'] == true) {
        _showSuccessDialog(
          message: result['message'] as String?,
          needsEmailConfirmation: result['needsEmailConfirmation'] == true,
          pendingApproval: result['pendingApproval'] == true,
        );
      } else {
        _showError(result['message'] ?? 'Registration failed');
      }
    } catch (e) {
      setState(() => _isLoading = false);
      final errorResult = ErrorHandler.formatErrorForUI(e, context: 'instituteRegistration', appType: 'admin');
      _showError(errorResult['message']);
    }
  }

  void _showSuccessDialog({
    String? message,
    bool needsEmailConfirmation = false,
    bool pendingApproval = true,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.primaryGreen.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.check_circle,
                color: AppTheme.primaryGreen,
                size: 28,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Registration Successful!',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message ??
                  'Your account has been created successfully.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.accentMint.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.primaryGreen.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Registered email:',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _emailController.text.trim(),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.primaryGreen,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              needsEmailConfirmation
                  ? 'Supabase still has “Confirm email” on — turn it off under Authentication → Providers → Email (see project docs).'
                  : pendingApproval
                      ? 'You cannot log in until an administrator approves your institute on the web admin portal. After approval, sign in with this email and password.'
                      : 'You can log in with this email and your password.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppTheme.textGray,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            },
            child: const Text('Back to Login'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryGreen,
              foregroundColor: Colors.white,
            ),
            child: const Text('Go to Login'),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: AppTheme.accentRed,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundOffWhite,
      appBar: AppBar(
        title: const Text('Create Account'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Institute Info Card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppTheme.primaryGreen.withValues(alpha: 0.1),
                        AppTheme.accentMint.withValues(alpha: 0.05),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppTheme.primaryGreen.withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryGreen.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.school_rounded,
                          color: AppTheme.primaryGreen,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.instituteName,
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textDark,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  Icons.location_on_outlined,
                                  size: 14,
                                  color: AppTheme.textGray,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  widget.instituteLocation,
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: AppTheme.textGray,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                // Full Name Field
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Full Name',
                    prefixIcon: Icon(Icons.person_outlined),
                    hintText: 'Enter your full name',
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your full name';
                    }
                    if (value.length < 3) {
                      return 'Name must be at least 3 characters';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),

                // Email Field
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textCapitalization: TextCapitalization.none,
                  decoration: const InputDecoration(
                    labelText: 'Email Address',
                    prefixIcon: Icon(Icons.email_outlined),
                    hintText: 'your.email@example.com',
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your email';
                    }
                    if (!value.contains('@') || !value.contains('.')) {
                      return 'Please enter a valid email';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),

                // Password Field
                TextFormField(
                  controller: _passwordController,
                  obscureText: !_isPasswordVisible,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outlined),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _isPasswordVisible
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      onPressed: () {
                        setState(() => _isPasswordVisible = !_isPasswordVisible);
                      },
                    ),
                    helperText: 'Minimum 6 characters',
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter a password';
                    }
                    if (value.length < 6) {
                      return 'Password must be at least 6 characters';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),

                // Mobile Number Field
                TextFormField(
                  controller: _mobileController,
                  keyboardType: TextInputType.phone,
                  maxLength: 10,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: 'Mobile Number',
                    prefixIcon: const Icon(Icons.phone_outlined),
                    hintText: '10 digit mobile number',
                    prefixText: '+91 ',
                    counterText: '',
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter mobile number';
                    }
                    if (value.length != 10) {
                      return 'Mobile number must be 10 digits';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                // Send OTP Button
                if (!_showOtpField)
                  OutlinedButton.icon(
                    onPressed: _isLoading ? null : _sendOTP,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_outlined),
                    label: const Text('Send OTP'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: AppTheme.primaryGreen, width: 2),
                    ),
                  ),

                // OTP Field
                if (_showOtpField) ...[
                  TextFormField(
                    controller: _otpController,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 20, letterSpacing: 8),
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: 'Enter OTP',
                      prefixIcon: const Icon(Icons.verified_user),
                      suffixIcon: _otpTimeLeft > 0
                          ? Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                '${_otpTimeLeft}s',
                                style: const TextStyle(
                                  color: AppTheme.primaryGreen,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            )
                          : TextButton(
                              onPressed: _sendOTP,
                              child: const Text('Resend'),
                            ),
                      counterText: '',
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter OTP';
                      }
                      if (value.length != 6) {
                        return 'OTP must be 6 digits';
                      }
                      return null;
                    },
                  ),
                  if (_otpTimeLeft <= 0)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _sendOTP,
                        child: const Text('Resend OTP'),
                      ),
                    ),
                  const SizedBox(height: 20),
                ],

                const SizedBox(height: 32),

                // Register Button
                Container(
                  height: 58,
                  decoration: AppTheme.primaryGradientDecoration,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleRegistration,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 26,
                            width: 26,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 3,
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.person_add_rounded, size: 22),
                              const SizedBox(width: 10),
                              Text(
                                _showOtpField ? 'Register' : 'Verify OTP First',
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),

                const SizedBox(height: 24),

                // Info Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.accentMint.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppTheme.primaryGreen.withValues(alpha: 0.2),
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        color: AppTheme.primaryGreen,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Your login credentials will be sent to your email after successful registration.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.darkCharcoal,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
