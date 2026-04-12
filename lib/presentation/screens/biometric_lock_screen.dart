import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/app_db.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../services/biometric_service.dart';
import '../../services/auth_service.dart';
import '../../services/session_manager.dart';
import '../../core/theme/app_theme.dart';
import 'main_navigation_screen.dart';
import 'login_screen.dart';
import 'dart:ui';

class BiometricLockScreen extends StatefulWidget {
  static const routeName = '/biometric-lock';
  const BiometricLockScreen({super.key});

  @override
  State<BiometricLockScreen> createState() => _BiometricLockScreenState();
}

class _BiometricLockScreenState extends State<BiometricLockScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _pinController = TextEditingController();
  final AuthService _authService = AuthService();
  
  bool _isLoading = false;
  bool _biometricSupported = false;
  bool _biometricEnabled = false;
  bool _showPinInput = false;
  String? _userEmail;
  String? _userId;
  String _errorMessage = '';
  
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    
    _initialize();
  }

  @override
  void dispose() {
    _pinController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    // Get current user
    final user = appDb.auth.currentUser;
    if (user == null) {
      // No user logged in, go to login
      if (mounted) {
        Navigator.pushReplacementNamed(context, LoginScreen.routeName);
      }
      return;
    }

    _userId = user.id;
    _userEmail = user.email;

    // Check biometric support
    final isSupported = await BiometricService.isDeviceSupported();
    final isEnabled = await BiometricService.isBiometricEnabled();
    
    if (mounted) {
      setState(() {
        _biometricSupported = isSupported;
        _biometricEnabled = isEnabled;
      });

      // IRCTC Style: Auto-trigger biometric immediately, but always show PIN option
      // Show PIN input immediately (IRCTC shows both options)
      setState(() {
        _showPinInput = true;
      });

      // Auto-trigger biometric if enabled (IRCTC style - immediate prompt)
      if (_biometricEnabled && _biometricSupported) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            // Shorter delay for faster response (IRCTC style)
            Future.delayed(const Duration(milliseconds: 300), () {
              if (mounted) {
                _tryBiometricUnlock();
              }
            });
          }
        });
      }
    }
  }

  Future<void> _tryBiometricUnlock() async {
    if (!_biometricEnabled || !_biometricSupported || !mounted) {
      setState(() {
        _showPinInput = true;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      // Show biometric prompt
      final authenticated = await BiometricService.authenticate(
        reason: 'Unlock app with biometric',
        useErrorDialogs: true,
      );

      if (!mounted) return;

      if (authenticated) {
        // Biometric successful - unlock app
        await _unlockApp();
      } else {
        // Biometric failed or cancelled - show PIN input
        setState(() {
          _isLoading = false;
          _showPinInput = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _showPinInput = true;
          _errorMessage = 'Biometric authentication failed. Please use PIN.';
        });
      }
    }
  }

  Future<void> _unlockWithPin() async {
    if (_pinController.text.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter PIN';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      // Verify PIN
      final isValid = await _authService.verifyPIN(_userId!, _pinController.text);
      
      if (!mounted) return;

      if (isValid) {
        await _unlockApp();
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Incorrect PIN. Please try again.';
          _pinController.clear();
        });
        // Haptic feedback for error
        HapticFeedback.vibrate();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'PIN verification failed. Please try again.';
          _pinController.clear();
        });
      }
    }
  }

  Future<void> _unlockApp() async {
    if (!mounted) return;
    
    setState(() {
      _isLoading = true;
    });

    // Update session activity
    SessionManager.updateActivity();
    
    // Navigate to home
    Navigator.pushReplacementNamed(context, MainNavigationScreen.routeName);
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false, // Prevent back button
      child: Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppTheme.primaryBlue,
                AppTheme.primaryBlueDark,
                AppTheme.primaryBlueLight,
              ],
            ),
          ),
          child: SafeArea(
            child: Center(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final viewportH = MediaQuery.sizeOf(context).height;
                    final logoW = AppUI.bodyLogoMaxWidth(
                      constraints.maxWidth,
                      viewportH,
                    );
                    return SingleChildScrollView(
                      padding: EdgeInsets.all(24.w),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.hasBoundedHeight
                              ? constraints.maxHeight
                              : viewportH,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ScaleTransition(
                              scale: _pulseAnimation,
                              child: Container(
                                constraints: BoxConstraints(maxWidth: logoW),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(20.r),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.45),
                                    width: 2.5,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.25,
                                      ),
                                      blurRadius: 28,
                                      spreadRadius: 2,
                                      offset: const Offset(0, 10),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(18.r),
                                  child: ColoredBox(
                                    color: Colors.white,
                                    child: AspectRatio(
                                      aspectRatio: AppUI.appLogoAspectRatio,
                                      child: Image.asset(
                                        AppUI.appLogoAsset,
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                    SizedBox(height: 40.h),
                    
                    // Title
                    Text(
                      'App Locked',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28.sp,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                    SizedBox(height: 12.h),
                    
                    // Subtitle
                    Text(
                      _biometricEnabled && _biometricSupported
                          ? 'Use biometric or PIN to unlock'
                          : 'Enter PIN to unlock',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 16.sp,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    
                    if (_userEmail != null) ...[
                      SizedBox(height: 8.h),
                      Text(
                        _userEmail!,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 14.sp,
                        ),
                      ),
                    ],
                    
                    SizedBox(height: 40.h),
                    
                    // PIN Input (IRCTC Style: Always visible as fallback)
                    if (_showPinInput) ...[
                      Container(
                        padding: EdgeInsets.all(24.w),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.3),
                            width: 2,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                            child: Column(
                              children: [
                                // PIN Input Field (IRCTC Style: Auto-submit on 6 digits)
                                TextField(
                                  controller: _pinController,
                                  keyboardType: TextInputType.number,
                                  obscureText: true,
                                  maxLength: 6,
                                  textAlign: TextAlign.center,
                                  autofocus: !_biometricEnabled, // Auto-focus if biometric not enabled
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 32.sp,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 8,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: 'Enter 6-digit PIN',
                                    hintStyle: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.5),
                                      fontSize: 18.sp,
                                    ),
                                    filled: true,
                                    fillColor: Colors.transparent,
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    disabledBorder: InputBorder.none,
                                    errorBorder: InputBorder.none,
                                    focusedErrorBorder: InputBorder.none,
                                    counterText: '',
                                    contentPadding: EdgeInsets.symmetric(vertical: 16.h),
                                  ),
                                  onChanged: (value) {
                                    // IRCTC Style: Auto-submit when 6 digits entered
                                    if (value.length == 6 && !_isLoading) {
                                      _unlockWithPin();
                                    }
                                  },
                                  onSubmitted: (_) => _unlockWithPin(),
                                ),
                                
                                if (_errorMessage.isNotEmpty) ...[
                                  SizedBox(height: 16.h),
                                  Text(
                                    _errorMessage,
                                    style: TextStyle(
                                      color: Colors.red.shade300,
                                      fontSize: 14.sp,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                                
                                SizedBox(height: 24.h),
                                
                                // Unlock Button
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed: _isLoading ? null : _unlockWithPin,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.white,
                                      foregroundColor: AppTheme.primaryBlue,
                                      padding: EdgeInsets.symmetric(vertical: 16.h),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      elevation: 4,
                                    ),
                                    child: _isLoading
                                        ? SizedBox(
                                            width: 24.w,
                                            height: 24.w,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              valueColor: AlwaysStoppedAnimation<Color>(
                                                AppTheme.primaryBlue,
                                              ),
                                            ),
                                          )
                                        : Text(
                                            'Unlock',
                                            style: TextStyle(
                                              fontSize: 18.sp,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                    
                    // Biometric Button (IRCTC Style: Always show if enabled, even when PIN is visible)
                    if (_biometricEnabled && _biometricSupported) ...[
                      SizedBox(height: 24.h),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.h),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.3),
                            width: 1.5,
                          ),
                        ),
                        child: TextButton.icon(
                          onPressed: _isLoading ? null : _tryBiometricUnlock,
                          icon: Icon(
                            Icons.fingerprint_rounded,
                            color: Colors.white,
                            size: 32.sp,
                          ),
                          label: Text(
                            'Use Biometric / Face ID',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16.sp,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                          ),
                        ),
                      ),
                    ],
                    
                    SizedBox(height: 40.h),
                    
                    // Logout Option
                    TextButton(
                      onPressed: _isLoading
                          ? null
                          : () async {
                              await appDb.auth.signOut();
                              if (mounted) {
                                Navigator.pushReplacementNamed(
                                  context,
                                  LoginScreen.routeName,
                                );
                              }
                            },
                      child: Text(
                        'Logout',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 14.sp,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
                  },
                ),
              ),
            ),
          ),
        ),
    );
  }
}
