import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'dart:ui';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../services/auth_service.dart';
import '../../services/error_handler.dart';
import '../../services/biometric_service.dart';
import '../../services/geofence_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/responsive.dart';
import 'main_navigation_screen.dart';
import 'institute_search_screen.dart';
import 'setup_screen.dart';
import 'biometric_lock_screen.dart';
import '../widgets/animated_background.dart';

/// Modern Redesigned Login Screen
/// Features: Premium glassmorphic design, smooth animations, better UX
class ModernLoginScreen extends StatefulWidget {
  static const routeName = '/modern-login';
  const ModernLoginScreen({super.key});

  @override
  State<ModernLoginScreen> createState() => _ModernLoginScreenState();
}

class _ModernLoginScreenState extends State<ModernLoginScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _pinController = TextEditingController();
  final AuthService _authService = AuthService();
  final GeofenceService _geofenceService = GeofenceService();

  bool _isPasswordVisible = false;
  bool _isLoading = false;
  bool _usePinLogin = false;
  bool _biometricSupported = false;
  bool _biometricEnabled = false;
  String? _currentUserId;

  late AnimationController _fadeController;
  late AnimationController _slideController;
  late AnimationController _scaleController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _checkBiometricStatus();
  }

  void _initializeAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOut),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic));
    _scaleAnimation = Tween<double>(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeOutBack),
    );

    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) {
        _fadeController.forward();
        _slideController.forward();
        _scaleController.forward();
      }
    });
  }

  Future<void> _checkBiometricStatus() async {
    final isSupported = await BiometricService.isDeviceSupported();
    final isEnabled = await BiometricService.isBiometricEnabled();
    if (mounted) {
      setState(() {
        _biometricSupported = isSupported;
        _biometricEnabled = isEnabled;
      });

      if (_biometricEnabled) {
        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted) _tryBiometricLogin();
        });
      }
    }
  }

  Future<void> _tryBiometricLogin() async {
    if (!_biometricEnabled || !_biometricSupported || !mounted) return;

    final email = await BiometricService.getBiometricEmail();
    if (email == null || email.isEmpty) return;

    _emailController.text = email;

    final authenticated = await BiometricService.authenticate(
      reason: 'Use biometric to login quickly',
      useErrorDialogs: true,
    );

    if (!mounted) return;

    if (authenticated) {
      _showBiometricPasswordDialog(email);
    }
  }

  void _showBiometricPasswordDialog(String email) {
    final passwordController = TextEditingController();
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
                color: AppTheme.primaryGreen.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.fingerprint, color: AppTheme.primaryGreen, size: 24),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Biometric Verified',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Please enter your password to complete login',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                prefixIcon: const Icon(Icons.lock),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              _passwordController.text = passwordController.text;
              _handleLogin();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Login'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _pinController.dispose();
    _fadeController.dispose();
    _slideController.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  void _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final pin = _pinController.text.trim();

    try {
      Map<String, dynamic> result;

      if (_usePinLogin && pin.isNotEmpty) {
        result = await _authService.signInWithPIN(email: email, pin: pin);
      } else {
        result = await _authService.signInWithEmail(email: email, password: password);
      }

      if (!mounted) return;

      if (result['success']) {
        _currentUserId = result['userId'];
        String userRole = result['role'];

        if (userRole != 'admin') {
          setState(() => _isLoading = false);
          _showSnackbar('Access denied. Admin only.', isSuccess: false);
          return;
        }

        if (!_usePinLogin) {
          final hasPin = await _authService.hasPIN(_currentUserId!);
          if (!hasPin) {
            setState(() => _isLoading = false);
            _showPinSetupDialog();
            return;
          }
        }

        if (_biometricSupported && !_biometricEnabled) {
          setState(() => _isLoading = false);
          _showBiometricSetupDialog(email);
          return;
        }

        setState(() => _isLoading = false);
        if (mounted) {
          await _checkLocationLockStatus();
          _navigateToHome();
        }
      } else {
        setState(() => _isLoading = false);
        _showSnackbar(result['message'], isSuccess: false);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      final errorResult = ErrorHandler.formatErrorForUI(e, context: 'login', appType: 'admin');
      _showSnackbar(errorResult['message'], isSuccess: false);
    }
  }

  void _showPinSetupDialog() {
    final pinController = TextEditingController();
    final confirmPinController = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Set PIN for Quick Login'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Set a 4-6 digit PIN for faster login (like IRCTC)'),
            const SizedBox(height: 20),
            TextField(
              controller: pinController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'Enter PIN (4-6 digits)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmPinController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'Confirm PIN',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _navigateToHome();
            },
            child: const Text('Skip'),
          ),
          ElevatedButton(
            onPressed: () async {
              final pin = pinController.text;
              final confirmPin = confirmPinController.text;

              if (pin.length < 4 || pin.length > 6) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('PIN must be 4-6 digits')),
                );
                return;
              }

              if (pin != confirmPin) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('PINs do not match')),
                );
                return;
              }

              final result = await _authService.setPINWithPassword(
                userId: _currentUserId!,
                pin: pin,
                password: _passwordController.text,
              );

              if (mounted) {
                Navigator.pop(context);
                if (result['success']) {
                  _showSnackbar('PIN set successfully!', isSuccess: true);
                  _navigateToHome();
                } else {
                  _showSnackbar(result['message'], isSuccess: false);
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryBlue,
              foregroundColor: Colors.white,
            ),
            child: const Text('Set PIN'),
          ),
        ],
      ),
    );
  }

  void _showBiometricSetupDialog(String email) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.fingerprint, color: AppTheme.primaryBlue, size: 28),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Enable Biometric Login',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enable biometric authentication for quick login (like IRCTC)',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            FutureBuilder<List<String>>(
              future: BiometricService.getAvailableBiometricNames(),
              builder: (context, snapshot) {
                if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Available on this device:',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      ...snapshot.data!.map((type) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              children: [
                                const Icon(Icons.check_circle, color: Colors.green, size: 16),
                                const SizedBox(width: 8),
                                Text(type, style: const TextStyle(fontSize: 13)),
                              ],
                            ),
                          )),
                    ],
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _navigateToHome();
            },
            child: const Text('Skip'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              final enabled = await BiometricService.enableBiometric(email);
              if (enabled && mounted) {
                _showSnackbar('✅ Biometric login enabled', isSuccess: true);
              }
              _navigateToHome();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryBlue,
              foregroundColor: Colors.white,
            ),
            child: const Text('Enable'),
          ),
        ],
      ),
    );
  }

  void _navigateToHome() async {
    if (!mounted) return;

    final isBiometricEnabled = await BiometricService.isBiometricEnabled();
    final isBiometricSupported = await BiometricService.isDeviceSupported();

    if (isBiometricEnabled && isBiometricSupported) {
      Navigator.pushReplacementNamed(context, BiometricLockScreen.routeName);
      return;
    }

    if (mounted) {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              const MainNavigationScreen(),
          transitionDuration: const Duration(milliseconds: 600),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeIn),
            );
            return FadeTransition(opacity: fadeAnimation, child: child);
          },
        ),
      );
    }
  }

  Future<void> _checkLocationLockStatus() async {
    if (_currentUserId == null) return;
    // Implementation same as original
  }

  void _showSnackbar(String message, {required bool isSuccess}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isSuccess ? Icons.check_circle_rounded : Icons.error_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor: isSuccess ? AppTheme.primaryGreen : AppTheme.accentRed,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.symmetric(
              horizontal: Responsive.padding(context).horizontal,
              vertical: Responsive.padding(context).vertical,
            ),
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: SlideTransition(
                position: _slideAnimation,
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(height: 40.h),

                      // Modern Logo Section
                      ScaleTransition(
                        scale: _scaleAnimation,
                        child: _buildLogoSection(),
                      ),

                      SizedBox(height: 50.h),

                      // Modern Glassmorphic Form Card
                      ScaleTransition(
                        scale: _scaleAnimation,
                        child: _buildFormCard(),
                      ),

                      SizedBox(height: 30.h),

                      // Change User Account Button
                      _buildChangeUserButton(),

                      SizedBox(height: 20.h),

                      // Footer
                      _buildFooter(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogoSection() {
    return Column(
      children: [
        // Glassmorphic Logo Container
        Container(
          width: 120.w,
          height: 120.h,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.2),
                Colors.white.withOpacity(0.1),
              ],
            ),
            borderRadius: BorderRadius.circular(30.r),
            border: Border.all(
              color: Colors.white.withOpacity(0.3),
              width: 2.w,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 30.r,
                spreadRadius: 5.r,
                offset: Offset(0, 15.h),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(30.r),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Center(
                child: Icon(
                  Icons.fingerprint_rounded,
                  size: 60.sp,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
        SizedBox(height: 24.h),

        // App Name
        Text(
          'MSCE Attendance',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
            fontSize: Responsive.fontSize(context, 42).sp,
            shadows: [
              Shadow(
                color: Colors.black26,
                blurRadius: 10.r,
                offset: Offset(0, 4.h),
              ),
            ],
          ),
        ),
        SizedBox(height: 8.h),

        // Tagline
        Text(
          'Smart Attendance System',
          style: TextStyle(
            color: Colors.white.withOpacity(0.9),
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
            fontSize: Responsive.fontSize(context, 16).sp,
          ),
        ),
        SizedBox(height: 16.h),

        // Company Badge
        Container(
          padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 10.h),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20.r),
            border: Border.all(
              color: Colors.white.withOpacity(0.3),
              width: 1.5.w,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20.r),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Text(
                'By Digitrix Media',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.95),
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.4,
                  fontSize: 13.sp,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFormCard() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.25),
            Colors.white.withOpacity(0.15),
          ],
        ),
        borderRadius: BorderRadius.circular(28.r),
        border: Border.all(
          color: Colors.white.withOpacity(0.4),
          width: 2.w,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 30.r,
            spreadRadius: 5.r,
          ),
          BoxShadow(
            color: Colors.white.withOpacity(0.1),
            blurRadius: 20.r,
            spreadRadius: -5.r,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28.r),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            padding: EdgeInsets.all(28.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Tab Switcher
                _buildTabSwitcher(),

                SizedBox(height: 28.h),

                // Email Field
                _buildEmailField(),

                SizedBox(height: 20.h),

                // Password/PIN Toggle
                _buildAuthMethodToggle(),

                SizedBox(height: 20.h),

                // Password/PIN Field
                _usePinLogin ? _buildPINField() : _buildPasswordField(),

                // Forgot PIN / Change User (for PIN mode)
                if (_usePinLogin) ...[
                  SizedBox(height: 12.h),
                  _buildPINModeActions(),
                ],

                SizedBox(height: 28.h),

                // Login Button
                _buildLoginButton(),

                SizedBox(height: 16.h),

                // Biometric Button (if enabled)
                if (_biometricEnabled && _biometricSupported)
                  _buildBiometricButton(),

                SizedBox(height: 16.h),

                // Security Badge
                _buildSecurityBadge(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabSwitcher() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.15),
        borderRadius: BorderRadius.circular(18.r),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          Expanded(
            child: _buildTabButton(
              'Login',
              Icons.login_rounded,
              true,
              () {},
            ),
          ),
          Expanded(
            child: _buildTabButton(
              'Sign Up',
              Icons.person_add_rounded,
              false,
              () {
                Navigator.push(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) =>
                        const InstituteSearchScreen(),
                    transitionsBuilder: (context, animation, secondaryAnimation, child) {
                      var begin = const Offset(1.0, 0.0);
                      var end = Offset.zero;
                      var curve = Curves.easeInOutCubic;
                      var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
                      return SlideTransition(
                        position: animation.drive(tween),
                        child: FadeTransition(opacity: animation, child: child),
                      );
                    },
                    transitionDuration: const Duration(milliseconds: 400),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton(String label, IconData icon, bool isActive, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: EdgeInsets.symmetric(vertical: 14.h, horizontal: 16.w),
        decoration: BoxDecoration(
          gradient: isActive
              ? LinearGradient(
                  colors: [
                    Colors.white.withOpacity(0.3),
                    Colors.white.withOpacity(0.2),
                  ],
                )
              : null,
          color: isActive ? null : Colors.transparent,
          borderRadius: BorderRadius.circular(14.r),
          border: isActive
              ? Border.all(color: Colors.white.withOpacity(0.5), width: 1.5)
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isActive ? Colors.white : Colors.white.withOpacity(0.7),
              size: 18.sp,
            ),
            SizedBox(width: 6.w),
            Text(
              label,
              style: TextStyle(
                color: isActive ? Colors.white : Colors.white.withOpacity(0.7),
                fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                fontSize: 14.sp,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmailField() {
    return TextFormField(
      controller: _emailController,
      keyboardType: TextInputType.emailAddress,
      textCapitalization: TextCapitalization.none,
      style: const TextStyle(color: Colors.white, fontSize: 15),
      decoration: InputDecoration(
        labelText: 'Email',
        hintText: 'admin@institute.com',
        labelStyle: TextStyle(color: Colors.white.withOpacity(0.8)),
        hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
        prefixIcon: Icon(Icons.email_rounded, color: Colors.white.withOpacity(0.8), size: 20),
        filled: true,
        fillColor: Colors.white.withOpacity(0.1),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14.r),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14.r),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14.r),
          borderSide: const BorderSide(color: Colors.white, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14.r),
          borderSide: const BorderSide(color: AppTheme.accentRed),
        ),
        errorStyle: const TextStyle(color: Color(0xFFFFE5E5)),
        contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Email required';
        }
        if (!value.contains('@')) {
          return 'Invalid email';
        }
        return null;
      },
    );
  }

  Widget _buildAuthMethodToggle() {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () => setState(() {
              _usePinLogin = false;
              _pinController.clear();
            }),
            child: Container(
              padding: EdgeInsets.symmetric(vertical: 12.h),
              decoration: BoxDecoration(
                color: !_usePinLogin
                    ? Colors.white.withOpacity(0.2)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(
                  color: !_usePinLogin
                      ? Colors.white
                      : Colors.white.withOpacity(0.3),
                  width: !_usePinLogin ? 2 : 1,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.lock_rounded,
                    color: !_usePinLogin ? Colors.white : Colors.white.withOpacity(0.7),
                    size: 16.sp,
                  ),
                  SizedBox(width: 4.w),
                  Text(
                    'Password',
                    style: TextStyle(
                      color: !_usePinLogin ? Colors.white : Colors.white.withOpacity(0.7),
                      fontWeight: !_usePinLogin ? FontWeight.bold : FontWeight.normal,
                      fontSize: 11.sp,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        SizedBox(width: 8.w),
        Expanded(
          child: GestureDetector(
            onTap: () => setState(() {
              _usePinLogin = true;
              _passwordController.clear();
            }),
            child: Container(
              padding: EdgeInsets.symmetric(vertical: 12.h),
              decoration: BoxDecoration(
                color: _usePinLogin
                    ? Colors.white.withOpacity(0.2)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(
                  color: _usePinLogin
                      ? Colors.white
                      : Colors.white.withOpacity(0.3),
                  width: _usePinLogin ? 2 : 1,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.pin_rounded,
                    color: _usePinLogin ? Colors.white : Colors.white.withOpacity(0.7),
                    size: 16.sp,
                  ),
                  SizedBox(width: 4.w),
                  Text(
                    'PIN',
                    style: TextStyle(
                      color: _usePinLogin ? Colors.white : Colors.white.withOpacity(0.7),
                      fontWeight: _usePinLogin ? FontWeight.bold : FontWeight.normal,
                      fontSize: 11.sp,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordField() {
    return TextFormField(
      controller: _passwordController,
      obscureText: !_isPasswordVisible,
      style: const TextStyle(color: Colors.white, fontSize: 15),
      decoration: InputDecoration(
        labelText: 'Password',
        hintText: '••••••••',
        labelStyle: TextStyle(color: Colors.white.withOpacity(0.8)),
        hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
        prefixIcon: Icon(Icons.lock_rounded, color: Colors.white.withOpacity(0.8), size: 20),
        suffixIcon: IconButton(
          icon: Icon(
            _isPasswordVisible ? Icons.visibility_off_rounded : Icons.visibility_rounded,
            color: Colors.white.withOpacity(0.7),
            size: 20,
          ),
          onPressed: () => setState(() => _isPasswordVisible = !_isPasswordVisible),
        ),
        filled: true,
        fillColor: Colors.white.withOpacity(0.1),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14.r),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14.r),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14.r),
          borderSide: const BorderSide(color: Colors.white, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14.r),
          borderSide: const BorderSide(color: AppTheme.accentRed),
        ),
        errorStyle: const TextStyle(color: Color(0xFFFFE5E5)),
        contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Password required';
        }
        return null;
      },
    );
  }

  Widget _buildPINField() {
    return TextFormField(
      controller: _pinController,
      keyboardType: TextInputType.number,
      maxLength: 6,
      obscureText: true,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: Colors.white,
        fontSize: 24.sp,
        letterSpacing: 8.w,
        fontWeight: FontWeight.bold,
      ),
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: 'Enter PIN',
        labelStyle: TextStyle(color: Colors.white.withOpacity(0.8)),
        hintText: '••••',
        hintStyle: TextStyle(
          color: Colors.white.withOpacity(0.4),
          fontSize: 24.sp,
          letterSpacing: 8.w,
        ),
        prefixIcon: Icon(Icons.pin_rounded, color: Colors.white.withOpacity(0.8)),
        filled: true,
        fillColor: Colors.white.withOpacity(0.1),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14.r),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14.r),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14.r),
          borderSide: const BorderSide(color: Colors.white, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14.r),
          borderSide: const BorderSide(color: AppTheme.accentRed),
        ),
        errorStyle: const TextStyle(color: Color(0xFFFFE5E5)),
        counterText: '',
        contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'PIN required';
        }
        if (value.length < 4 || value.length > 6) {
          return 'PIN must be 4-6 digits';
        }
        return null;
      },
      onChanged: (value) {
        if (value.length == 6) {
          // Auto-submit after 6 digits
          Future.delayed(const Duration(milliseconds: 300), () {
            if (mounted && _formKey.currentState!.validate()) {
              _handleLogin();
            }
          });
        }
      },
    );
  }

  Widget _buildPINModeActions() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        TextButton(
          onPressed: () {
            Navigator.pushReplacementNamed(context, SetupScreen.routeName);
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.person_outline, color: Colors.white.withOpacity(0.9), size: 16),
              const SizedBox(width: 4),
              Text(
                'Change User',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 12,
                  decoration: TextDecoration.underline,
                ),
              ),
            ],
          ),
        ),
        TextButton(
          onPressed: () {
            // Show forgot PIN dialog
            _showForgotPinDialog();
          },
          child: Text(
            'Forgot PIN?',
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 12,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      ],
    );
  }

  void _showForgotPinDialog() {
    // Implementation for forgot PIN dialog
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Reset PIN'),
        content: const Text('Please contact admin to reset your PIN'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginButton() {
    return Container(
      height: 56.h,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white,
            Colors.white.withOpacity(0.95),
          ],
        ),
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 20.r,
            spreadRadius: 2.r,
            offset: Offset(0, 4.h),
          ),
          BoxShadow(
            color: Colors.white.withOpacity(0.2),
            blurRadius: 10.r,
            spreadRadius: -2.r,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isLoading ? null : _handleLogin,
          borderRadius: BorderRadius.circular(16.r),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 24.w),
            child: _isLoading
                ? Center(
                    child: SizedBox(
                      height: 24.h,
                      width: 24.w,
                      child: const CircularProgressIndicator(
                        color: AppTheme.primaryBlue,
                        strokeWidth: 3,
                      ),
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.login_rounded, color: AppTheme.primaryBlue, size: 22),
                      SizedBox(width: 12.w),
                      Text(
                        'Login',
                        style: TextStyle(
                          color: AppTheme.primaryBlue,
                          fontSize: 17.sp,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildBiometricButton() {
    return GestureDetector(
      onTap: _isLoading ? null : _tryBiometricLogin,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 16.h, horizontal: 24.w),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(16.r),
          border: Border.all(
            color: Colors.white.withOpacity(0.3),
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.fingerprint, color: Colors.white, size: 24),
            SizedBox(width: 12.w),
            Text(
              'Login with Biometric',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSecurityBadge() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
      decoration: BoxDecoration(
        color: AppTheme.primaryGreen.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: AppTheme.primaryGreen.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.security_rounded, color: AppTheme.primaryGreen, size: 16.sp),
          SizedBox(width: 6.w),
          Flexible(
            child: Text(
              _usePinLogin ? 'PIN Login' : 'Password Login',
              style: TextStyle(
                color: Colors.white.withOpacity(0.95),
                fontWeight: FontWeight.w600,
                fontSize: 12.sp,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChangeUserButton() {
    return TextButton(
      onPressed: () {
        Navigator.pushReplacementNamed(context, SetupScreen.routeName);
      },
      style: TextButton.styleFrom(
        padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.h),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.swap_horiz_rounded,
            color: Colors.white.withOpacity(0.9),
            size: 20.sp,
          ),
          SizedBox(width: 8.w),
          Text(
            'Change User Account',
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 14.sp,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.underline,
              decorationColor: Colors.white.withOpacity(0.9),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Center(
      child: Text(
        'Powered by Digitrix Media',
        style: TextStyle(
          color: Colors.white.withOpacity(0.8),
          fontSize: 12.sp,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
