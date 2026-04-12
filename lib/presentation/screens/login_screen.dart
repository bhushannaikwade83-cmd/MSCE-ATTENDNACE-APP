import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_attendance_app/l10n/app_localizations.dart';
import '../../services/locale_service.dart';
import '../../services/auth_service.dart';
import '../../services/error_handler.dart';
import '../../services/biometric_service.dart';
import '../../services/geofence_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/responsive.dart';
import 'main_navigation_screen.dart';
import 'institute_search_screen.dart';
import 'biometric_lock_screen.dart';
import '../../core/app_db.dart';
import '../../config/admin_portal_url.dart';

// ─── CAPTCHA PAINTER ──────────────────────────────────────────────────────────

class _CaptchaPainter extends CustomPainter {
  final String text;
  final List<Color> charColors;
  final List<double> charRotations;

  const _CaptchaPainter({
    required this.text,
    required this.charColors,
    required this.charRotations,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          const Color(0xFFEEF4FF),
          const Color(0xFFE8F0FE),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, size.width, size.height),
          const Radius.circular(8)),
      bgPaint,
    );

    // Border
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, size.width, size.height),
          const Radius.circular(8)),
      Paint()
        ..style = PaintingStyle.stroke
        ..color = AppTheme.primaryBlue.withValues(alpha: 0.25)
        ..strokeWidth = 1.5,
    );

    // Noise lines
    final noisePaint = Paint()
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    final rand = math.Random(text.hashCode);
    for (int i = 0; i < 6; i++) {
      noisePaint.color = [
        AppTheme.primaryBlue,
        AppTheme.accentSaffron,
        AppTheme.primaryGreen,
      ][i % 3]
          .withValues(alpha: 0.15 + rand.nextDouble() * 0.15);
      canvas.drawLine(
        Offset(rand.nextDouble() * size.width,
            rand.nextDouble() * size.height),
        Offset(rand.nextDouble() * size.width,
            rand.nextDouble() * size.height),
        noisePaint,
      );
    }
    // Noise dots
    final dotPaint = Paint()..style = PaintingStyle.fill;
    for (int i = 0; i < 20; i++) {
      dotPaint.color =
          AppTheme.primaryBlue.withValues(alpha: 0.08 + rand.nextDouble() * 0.1);
      canvas.drawCircle(
        Offset(rand.nextDouble() * size.width,
            rand.nextDouble() * size.height),
        1.2 + rand.nextDouble() * 1.5,
        dotPaint,
      );
    }

    // Draw each character
    final charW = size.width / (text.length + 1);
    for (int i = 0; i < text.length; i++) {
      final x = charW * (i + 0.6) + charW * 0.2;
      final y = size.height / 2 + (rand.nextDouble() - 0.5) * 8;
      final fontSize = 20.0 + rand.nextDouble() * 6;

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(charRotations[i]);

      final tp = TextPainter(
        text: TextSpan(
          text: text[i],
          style: TextStyle(
            color: charColors[i],
            fontSize: fontSize,
            fontWeight: FontWeight.w800,
            fontFamily: 'monospace',
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_CaptchaPainter oldDelegate) =>
      oldDelegate.text != text;
}

// ─── LOGIN SCREEN ─────────────────────────────────────────────────────────────

class LoginScreen extends StatefulWidget {
  static const routeName = '/login';
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  // ── Form controllers ─────────────────────────────────────────────────────────
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _pinController = TextEditingController();
  final _captchaController = TextEditingController();
  final _emailOtpController = TextEditingController();

  // ── Services ─────────────────────────────────────────────────────────────────
  final AuthService _authService = AuthService();
  final GeofenceService _geofenceService = GeofenceService();

  // ── State ────────────────────────────────────────────────────────────────────
  bool _isPasswordVisible = false;
  bool _isLoading = false;
  bool _biometricSupported = false;
  bool _biometricEnabled = false;
  String? _currentUserId;

  // ── IRCTC-style flow state ────────────────────────────────────────────────────
  /// true  → show IRCTC PIN screen (returning user)
  /// false → show full login form (first-time or Change User)
  bool _isReturningUser = false;
  String? _savedEmail;           // last successfully logged-in email
  bool _hasPIN = false;          // does the last user have a PIN set?

  /// After password + CAPTCHA pass: user must enter email OTP before session is restored.
  bool _waitingForEmailOtp = false;
  /// True after [verifyLoginEmailOTP] succeeds; stay on OTP UI until sign-in + PIN/home complete.
  bool _loginOtpVerified = false;
  Timer? _loginOtpCooldownTimer;
  int _loginOtpCooldownSec = 0;

  static const String _prefLastEmail = 'msce_last_login_email';
  /// Remember that this device last logged in with a PIN (works after logout when profile read may fail).
  static const String _prefLastUserHasPin = 'msce_last_user_has_pin';

  // ── CAPTCHA state ─────────────────────────────────────────────────────────────
  String _captchaText = '';
  List<Color> _captchaColors = [];
  List<double> _captchaRotations = [];
  bool _captchaVerified = false;
  static const String _captchaChars =
      'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  // ── Animation Controllers ─────────────────────────────────────────────────────
  late AnimationController _masterController;
  late AnimationController _badgeWobbleController;
  late AnimationController _buttonPulseController;

  late Animation<double> _logoFlip;
  late Animation<double> _screenFade;
  late Animation<double> _cardTiltX;
  late Animation<double> _cardSlideY;
  late Animation<double> _cardFade;
  late Animation<double> _badgeSpin;
  late Animation<double> _buttonPulse;

  bool _buttonPressed = false;

  @override
  void initState() {
    super.initState();
    _generateCaptcha();
    _setupAnimations();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final args = ModalRoute.of(context)?.settings.arguments;
      // forceFullLogin: show email/password/CAPTCHA (same as "Change user"), clear saved email.
      if (args is Map && args['forceFullLogin'] == true) {
        await _switchToChangeUser();
      } else {
        await _loadSavedUser();
      }
      if (!mounted) return;
      _checkBiometricStatus();
    });
  }

  // ─── CAPTCHA ──────────────────────────────────────────────────────────────────

  void _generateCaptcha() {
    final rand = math.Random();
    final sb = StringBuffer();
    for (int i = 0; i < 6; i++) {
      sb.write(_captchaChars[rand.nextInt(_captchaChars.length)]);
    }
    final colors = [
      AppTheme.primaryBlue,
      AppTheme.accentRed,
      AppTheme.primaryGreen,
      const Color(0xFF6B21A8), // purple
      AppTheme.accentSaffron,
      AppTheme.primaryBlueDark,
    ]..shuffle(rand);
    setState(() {
      _captchaText = sb.toString();
      _captchaColors = List.generate(6, (i) => colors[i % colors.length]);
      _captchaRotations = List.generate(
          6, (_) => (rand.nextDouble() - 0.5) * 0.45);
      _captchaVerified = false;
      _captchaController.clear();
    });
  }

  bool _verifyCaptcha() {
    return _captchaController.text.trim().toUpperCase() == _captchaText;
  }

  // ─── SAVED USER ───────────────────────────────────────────────────────────────

  Future<void> _loadSavedUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString(_prefLastEmail);
      if (email != null && email.isNotEmpty) {
        final localHadPin = prefs.getBool(_prefLastUserHasPin) ?? false;
        bool serverHasPin = false;
        try {
          serverHasPin = await _authService.hasPINForEmail(email);
        } catch (_) {}
        final hasPIN = serverHasPin || localHadPin;
        if (mounted) {
          setState(() {
            _savedEmail = email;
            _hasPIN = hasPIN;
            _isReturningUser = hasPIN;
            if (hasPIN) {
              _emailController.text = email;
            }
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _saveLastUser(String email) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefLastEmail, email);
    } catch (_) {}
  }

  Future<void> _persistLastUserHasPin(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (value) {
        await prefs.setBool(_prefLastUserHasPin, true);
      } else {
        await prefs.remove(_prefLastUserHasPin);
      }
    } catch (_) {}
  }

  Future<void> _switchToChangeUser() async {
    _loginOtpCooldownTimer?.cancel();
    _loginOtpCooldownTimer = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefLastEmail);
      await prefs.remove(_prefLastUserHasPin);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _isReturningUser = false;
      _waitingForEmailOtp = false;
      _loginOtpVerified = false;
      _loginOtpCooldownSec = 0;
      _emailController.clear();
      _passwordController.clear();
      _pinController.clear();
      _emailOtpController.clear();
    });
    _generateCaptcha();
  }

  void _cancelEmailOtpStep() {
    _loginOtpCooldownTimer?.cancel();
    _loginOtpCooldownTimer = null;
    setState(() {
      _waitingForEmailOtp = false;
      _loginOtpVerified = false;
      _emailOtpController.clear();
      _loginOtpCooldownSec = 0;
    });
    _generateCaptcha();
  }

  void _startLoginOtpCooldown(int seconds) {
    _loginOtpCooldownTimer?.cancel();
    setState(() => _loginOtpCooldownSec = seconds);
    _loginOtpCooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_loginOtpCooldownSec <= 1) {
        t.cancel();
        setState(() => _loginOtpCooldownSec = 0);
      } else {
        setState(() => _loginOtpCooldownSec--);
      }
    });
  }

  Future<void> _resendLoginOtp() async {
    if (_loginOtpCooldownSec > 0 || _isLoading) return;
    final email = _emailController.text.trim();
    setState(() => _isLoading = true);
    final r = await _authService.sendLoginEmailOTP(email);
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (r['success'] == true) {
      _startLoginOtpCooldown(60);
      if (kDebugMode) {
        _showModernSnackbar(
            'Demo OTP: ${r['otp'] ?? ''}', isSuccess: true);
      } else {
        _showModernSnackbar('OTP resent.', isSuccess: true);
      }
    } else {
      _showModernSnackbar(r['message'] ?? 'Could not resend OTP', isSuccess: false);
    }
  }

  // ─── ANIMATIONS ───────────────────────────────────────────────────────────────

  void _setupAnimations() {
    _masterController = AnimationController(
        duration: const Duration(milliseconds: 2000), vsync: this);
    _badgeWobbleController = AnimationController(
        duration: const Duration(seconds: 5), vsync: this)
      ..repeat();
    _buttonPulseController = AnimationController(
        duration: const Duration(milliseconds: 1600), vsync: this)
      ..repeat(reverse: true);

    _screenFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _masterController,
          curve: const Interval(0.0, 0.15, curve: Curves.easeIn)),
    );
    _logoFlip = Tween<double>(begin: -math.pi / 2, end: 0.0).animate(
      CurvedAnimation(parent: _masterController,
          curve: const Interval(0.05, 0.35, curve: Curves.elasticOut)),
    );
    _cardFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _masterController,
          curve: const Interval(0.35, 0.55, curve: Curves.easeIn)),
    );
    _cardTiltX = Tween<double>(begin: -0.18, end: 0.0).animate(
      CurvedAnimation(parent: _masterController,
          curve: const Interval(0.35, 0.65, curve: Curves.easeOutCubic)),
    );
    _cardSlideY = Tween<double>(begin: 45.0, end: 0.0).animate(
      CurvedAnimation(parent: _masterController,
          curve: const Interval(0.35, 0.65, curve: Curves.easeOutCubic)),
    );
    _badgeSpin = Tween<double>(begin: 0, end: 2 * math.pi).animate(
      CurvedAnimation(parent: _badgeWobbleController, curve: Curves.linear),
    );
    _buttonPulse = Tween<double>(begin: 1.0, end: 1.028).animate(
      CurvedAnimation(parent: _buttonPulseController, curve: Curves.easeInOut),
    );

    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) _masterController.forward();
    });
  }

  // ─── BIOMETRIC ────────────────────────────────────────────────────────────────

  Future<void> _checkBiometricStatus() async {
    final isSupported = await BiometricService.isDeviceSupported();
    final isEnabled = await BiometricService.isBiometricEnabled();
    if (mounted) {
      setState(() {
        _biometricSupported = isSupported;
        _biometricEnabled = isEnabled;
      });
      // Auto-trigger biometric if returning user with biometric enabled
      if (_biometricEnabled && _isReturningUser) {
        Future.delayed(const Duration(milliseconds: 700), () {
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
      reason: 'Use biometric to login to MSCE Attendance',
      useErrorDialogs: true,
    );
    if (!mounted) return;
    if (authenticated) _showBiometricPasswordDialog(email);
  }

  void _showBiometricPasswordDialog(String email) {
    final passwordController = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(children: [
          Icon(Icons.fingerprint, color: AppTheme.primaryGreen, size: 26),
          SizedBox(width: 10),
          Expanded(
              child: Text('Biometric Verified',
                  style: TextStyle(
                      fontSize: 17, fontWeight: FontWeight.bold))),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Enter your password to complete login',
              style: TextStyle(fontSize: 13)),
          const SizedBox(height: 14),
          TextField(
            controller: passwordController,
            obscureText: true,
            decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock_outline)),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              _passwordController.text = passwordController.text;
              _handleFullLogin(
                email: email,
                password: passwordController.text,
                isBiometric: true,
              );
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8))),
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
    _captchaController.dispose();
    _emailOtpController.dispose();
    _loginOtpCooldownTimer?.cancel();
    _masterController.dispose();
    _badgeWobbleController.dispose();
    _buttonPulseController.dispose();
    super.dispose();
  }

  // ─── AUTH LOGIC ───────────────────────────────────────────────────────────────

  /// Called when user taps LOGIN in the PIN screen (IRCTC mode)
  void _handlePINLogin() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    final email = _savedEmail ?? _emailController.text.trim();
    final pin = _pinController.text.trim();

    try {
      final result =
          await _authService.signInWithPIN(email: email, pin: pin);
      if (!mounted) return;

      if (result['success']) {
        _currentUserId = result['userId'];
        final String role = result['role'];
        if (role != 'admin') {
          setState(() => _isLoading = false);
          _showModernSnackbar('Access denied. Admin only.', isSuccess: false);
          return;
        }
        await _persistLastUserHasPin(true);
        setState(() => _isLoading = false);
        if (mounted) {
          await _checkLocationLockStatus();
          _navigateToHome();
        }
      } else {
        setState(() => _isLoading = false);
        _showLoginFailure(result);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      final err = ErrorHandler.formatErrorForUI(e,
          context: 'login', appType: 'admin');
      _showModernSnackbar(err['message'], isSuccess: false);
    }
  }

  /// Step 1: password + CAPTCHA → verify credentials, sign out, send OTP.
  Future<void> _handleFullFormLogin() async {
    if (!_formKey.currentState!.validate()) return;

    if (!_verifyCaptcha()) {
      _showModernSnackbar(
          'Verification code is incorrect. Please try again.',
          isSuccess: false);
      _generateCaptcha();
      return;
    }

    setState(() => _isLoading = true);
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    try {
      final result = await _authService.signInWithEmail(
          email: email, password: password);

      if (!mounted) return;

      if (result['success'] != true) {
        setState(() => _isLoading = false);
        _showLoginFailure(result);
        _generateCaptcha();
        return;
      }

      await _authService.signOut();

      final otpResult = await _authService.sendLoginEmailOTP(email);
      if (!mounted) return;

      if (otpResult['success'] != true) {
        setState(() => _isLoading = false);
        _showModernSnackbar(
            otpResult['message'] ?? 'Could not send OTP', isSuccess: false);
        _generateCaptcha();
        return;
      }

      setState(() {
        _isLoading = false;
        _waitingForEmailOtp = true;
        _emailOtpController.clear();
      });
      _startLoginOtpCooldown(60);

      if (kDebugMode) {
        _showModernSnackbar(
            'Enter OTP below. Debug build shows code: ${otpResult['otp'] ?? ''}',
            isSuccess: true);
      } else {
        _showModernSnackbar(
            'OTP sent. Enter the 6-digit code to finish login. '
            '(Production: connect SMS/email provider; demo uses in-app verification.)',
            isSuccess: true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      final err = ErrorHandler.formatErrorForUI(e,
          context: 'login', appType: 'admin');
      _showModernSnackbar(err['message'], isSuccess: false);
      _generateCaptcha();
    }
  }

  /// Step 2: OTP OK → sign in again and continue PIN/biometric flow.
  Future<void> _handleEmailOtpVerify() async {
    if (_loginOtpVerified) return;
    final otp = _emailOtpController.text.trim();
    if (otp.length != 6 || !RegExp(r'^\d{6}$').hasMatch(otp)) {
      _showModernSnackbar('Enter the 6-digit OTP', isSuccess: false);
      return;
    }

    setState(() => _isLoading = true);
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    try {
      final v = await _authService.verifyLoginEmailOTP(email, otp);
      if (!mounted) return;

      if (v['success'] != true) {
        setState(() => _isLoading = false);
        _showModernSnackbar(v['message'] ?? 'Invalid OTP', isSuccess: false);
        return;
      }

      _loginOtpCooldownTimer?.cancel();
      // Stay on OTP step; show verified state while we sign in and open PIN / home.
      setState(() {
        _loginOtpVerified = true;
        _loginOtpCooldownSec = 0;
      });

      await _handleFullLogin(
        email: email,
        password: password,
        fromEmailOtpStep: true,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      final err = ErrorHandler.formatErrorForUI(e,
          context: 'login', appType: 'admin');
      _showModernSnackbar(err['message'], isSuccess: false);
    }
  }

  Future<void> _handleFullLogin({
    required String email,
    required String password,
    bool isBiometric = false,
    bool fromEmailOtpStep = false,
  }) async {
    void resetOtpStepAfterFailure() {
      if (!fromEmailOtpStep) return;
      setState(() {
        _waitingForEmailOtp = false;
        _loginOtpVerified = false;
        _emailOtpController.clear();
      });
    }

    try {
      final result = await _authService.signInWithEmail(
          email: email, password: password);

      if (!mounted) return;

      if (result['success']) {
        _currentUserId = result['userId'];
        final String role = result['role'];
        if (role != 'admin') {
          setState(() => _isLoading = false);
          resetOtpStepAfterFailure();
          if (fromEmailOtpStep) _generateCaptcha();
          _showModernSnackbar('Access denied. Admin only.', isSuccess: false);
          return;
        }

        // Save email for future PIN-only logins
        await _saveLastUser(email);

        // Check PIN
        final hasPin = await _authService.hasPIN(_currentUserId!);
        await _persistLastUserHasPin(hasPin);
        if (!hasPin) {
          setState(() => _isLoading = false);
          _showPinSetupDialog(email);
          return;
        }

        // Offer biometric setup once per install
        if (_biometricSupported &&
            !_biometricEnabled &&
            !isBiometric &&
            !await BiometricService.wasBiometricSetupPromptShown()) {
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
        resetOtpStepAfterFailure();
        _showLoginFailure(result);
        if (!isBiometric) _generateCaptcha();
      }
    } catch (e) {
      setState(() => _isLoading = false);
      resetOtpStepAfterFailure();
      final err = ErrorHandler.formatErrorForUI(e,
          context: 'login', appType: 'admin');
      _showModernSnackbar(err['message'], isSuccess: false);
      if (!isBiometric) _generateCaptcha();
    }
  }

  Future<void> _maybeOfferBiometricAfterPin(String email) async {
    if (!mounted) return;
    final supported = await BiometricService.isDeviceSupported();
    final enabled = await BiometricService.isBiometricEnabled();
    final prompted = await BiometricService.wasBiometricSetupPromptShown();
    if (supported && !enabled && !prompted) {
      setState(() {
        _biometricSupported = supported;
        _biometricEnabled = enabled;
      });
      _showBiometricSetupDialog(email);
      return;
    }
    await _checkLocationLockStatus();
    _navigateToHome();
  }

  void _showPinSetupDialog(String email) {
    final pinCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        titlePadding:
            const EdgeInsets.fromLTRB(20, 20, 20, 0),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.pin_rounded,
                    color: AppTheme.primaryBlue, size: 22),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Set Login PIN',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ]),
            const SizedBox(height: 8),
            const Text(
              'Set a 4–6 digit PIN for quick login on your next visit — just like IRCTC.',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: AppTheme.textGray),
            ),
          ],
        ),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          TextField(
            controller: pinCtrl,
            keyboardType: TextInputType.number,
            maxLength: 6,
            obscureText: true,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 22, letterSpacing: 8, fontWeight: FontWeight.bold),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: 'Enter PIN (4–6 digits)',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    const BorderSide(color: AppTheme.primaryBlue, width: 2),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: confirmCtrl,
            keyboardType: TextInputType.number,
            maxLength: 6,
            obscureText: true,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 22, letterSpacing: 8, fontWeight: FontWeight.bold),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: 'Confirm PIN',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    const BorderSide(color: AppTheme.primaryBlue, width: 2),
              ),
            ),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _navigateToHome();
            },
            child: const Text('Skip for now'),
          ),
          ElevatedButton(
            onPressed: () async {
              final pin = pinCtrl.text;
              final confirmPin = confirmCtrl.text;
              if (pin.length < 4 || pin.length > 6) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('PIN must be 4–6 digits')));
                return;
              }
              if (pin != confirmPin) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('PINs do not match')));
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
                  await _persistLastUserHasPin(true);
                  setState(() {
                    _savedEmail = email;
                    _hasPIN = true;
                    _isReturningUser = true;
                    _emailController.text = email;
                    _pinController.clear();
                    _waitingForEmailOtp = false;
                    _loginOtpVerified = false;
                  });
                  _showModernSnackbar(
                      'PIN set! Use PIN for next login.',
                      isSuccess: true);
                  await _maybeOfferBiometricAfterPin(email);
                } else {
                  _showModernSnackbar(result['message'], isSuccess: false);
                }
              }
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8))),
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
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(children: [
          Icon(Icons.fingerprint, color: AppTheme.primaryBlue, size: 26),
          SizedBox(width: 10),
          Expanded(
              child: Text('Enable Biometric Login',
                  style: TextStyle(
                      fontSize: 17, fontWeight: FontWeight.bold))),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
                'Enable fingerprint / face ID for one-tap login on future visits.',
                style: TextStyle(fontSize: 13)),
            const SizedBox(height: 14),
            FutureBuilder<List<String>>(
              future: BiometricService.getAvailableBiometricNames(),
              builder: (context, snapshot) {
                if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Available on this device:',
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 12)),
                      const SizedBox(height: 6),
                      ...snapshot.data!.map((type) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(children: [
                              const Icon(Icons.check_circle,
                                  color: AppTheme.primaryGreen, size: 14),
                              const SizedBox(width: 6),
                              Text(type,
                                  style: const TextStyle(fontSize: 12)),
                            ]),
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
            onPressed: () async {
              Navigator.pop(context);
              await BiometricService.markBiometricSetupPromptShown();
              if (!mounted) return;
              await _checkLocationLockStatus();
              _navigateToHome();
            },
            child: const Text('Skip'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              final names =
                  await BiometricService.getAvailableBiometricNames();
              final label =
                  names.isNotEmpty ? names.join(' / ') : 'biometric';
              final verified = await BiometricService.authenticate(
                reason: 'Use $label to enable quick login.',
                useErrorDialogs: true,
                stickyAuth: true,
                requirePreferenceEnabled: false,
              );
              if (!mounted) return;
              await BiometricService.markBiometricSetupPromptShown();
              if (!mounted) return;
              if (!verified) {
                _showModernSnackbar(
                    'Biometric setup cancelled. Enable later in settings.',
                    isSuccess: false);
                await _checkLocationLockStatus();
                _navigateToHome();
                return;
              }
              final enabled =
                  await BiometricService.enableBiometric(email);
              if (!mounted) return;
              if (enabled) {
                setState(() => _biometricEnabled = true);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Row(children: [
                    Icon(Icons.check_circle, color: Colors.white),
                    SizedBox(width: 8),
                    Text('Biometric login enabled'),
                  ]),
                  backgroundColor: AppTheme.primaryGreen,
                ));
              }
              await _checkLocationLockStatus();
              _navigateToHome();
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8))),
            child: const Text('Enable'),
          ),
        ],
      ),
    );
  }

  void _navigateToHome() async {
    if (!mounted) return;
    setState(() {
      _waitingForEmailOtp = false;
      _loginOtpVerified = false;
    });
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
          pageBuilder: (_, animation, __) => const MainNavigationScreen(),
          transitionDuration: const Duration(milliseconds: 600),
          transitionsBuilder: (_, animation, __, child) => FadeTransition(
            opacity: CurvedAnimation(
                parent: animation, curve: Curves.easeIn),
            child: child,
          ),
        ),
      );
    }
  }

  Future<void> _checkLocationLockStatus() async {
    if (_currentUserId == null) return;
    try {
      final profile = await appDb
          .from('profiles')
          .select('institute_id')
          .eq('id', _currentUserId!)
          .maybeSingle();
      if (profile == null) return;
      final instituteId = profile['institute_id'] as String?;
      if (instituteId == null || instituteId.isEmpty) return;
      final locationStatus =
          await _geofenceService.checkAdminLocationStatus(
        instituteId: instituteId,
        adminId: _currentUserId!,
      );
      if (locationStatus['isLocked'] == true) {
        final isWithinRadius = locationStatus['isWithinRadius'] as bool?;
        final distance = locationStatus['distance'] as double?;
        if (isWithinRadius == false && distance != null && mounted) {
          _showModernSnackbar(
              '⚠️ Location locked – ${distance.toStringAsFixed(0)}m away.',
              isSuccess: false);
        } else if (isWithinRadius == true && mounted) {
          _showModernSnackbar('✅ Within verified location area.',
              isSuccess: true);
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error checking location lock: $e');
    }
  }

  void _showLoginFailure(Map<String, dynamic> result) {
    final message = result['message'] as String? ?? 'Login failed';
    final openPortal = result['openAdminPortal'] == true;
    final portalReady = AdminPortalUrl.isConfigured;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.error_outline, color: Colors.white, size: 20),
        const SizedBox(width: 10),
        Expanded(
            child: Text(
          openPortal && !portalReady
              ? '$message\n\nSet ADMIN_PORTAL_URL in .env.'
              : message,
          style: const TextStyle(fontSize: 13),
        )),
      ]),
      action: openPortal && portalReady
          ? SnackBarAction(
              label: 'Open Portal',
              textColor: Colors.white,
              onPressed: () async {
                final ok = await AdminPortalUrl.launch();
                if (!ok && mounted) {
                  _showModernSnackbar('Could not open admin portal',
                      isSuccess: false);
                }
              })
          : null,
      backgroundColor: AppTheme.accentRed,
      behavior: SnackBarBehavior.floating,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(16),
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      duration: Duration(seconds: openPortal ? 8 : 4),
    ));
  }

  void _showModernSnackbar(String message, {required bool isSuccess}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(
            isSuccess
                ? Icons.check_circle_outline
                : Icons.error_outline,
            color: Colors.white,
            size: 20),
        const SizedBox(width: 10),
        Expanded(
            child: Text(message,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500))),
      ]),
      backgroundColor:
          isSuccess ? AppTheme.primaryGreen : AppTheme.accentRed,
      behavior: SnackBarBehavior.floating,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(16),
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      duration: const Duration(seconds: 4),
    ));
  }

  void _showForgotPinDialog() {
    // Forgot PIN → clear saved user → go to full login form
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Forgot PIN?',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text(
          'You will be redirected to the full login form where you can login with your password and set a new PIN.',
          style: TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _switchToChangeUser();
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8))),
            child: const Text('Login with Password'),
          ),
        ],
      ),
    );
  }

  // ─── BUILD ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundGrey,
      body: AnimatedBuilder(
        animation: _masterController,
        builder: (context, _) {
          return Opacity(
            opacity: _screenFade.value.clamp(0.0, 1.0),
            child: Column(
              children: [
                const GovPortalHeader(),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: EdgeInsets.symmetric(
                      horizontal: Responsive.padding(context).horizontal,
                      vertical: 20.h,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildLogoSection(context),
                        SizedBox(height: 20.h),
                        // Switch between IRCTC PIN screen and Full Login form
                        _isReturningUser
                            ? _buildIRCTCPinCard()
                            : _buildFullLoginCard(),
                        SizedBox(height: 24.h),
                        _buildFooter(context),
                        SizedBox(height: 16.h),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ─── LOGO SECTION ─────────────────────────────────────────────────────────────

  Widget _buildLogoSection(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final viewportH = MediaQuery.sizeOf(context).height;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Drive by height (18% of viewport) so the landscape logo is never squat/compressed.
        final logoH = viewportH * 0.18;
        final logoW = (logoH * AppUI.appLogoAspectRatio)
            .clamp(0.0, constraints.maxWidth * 0.88);
        return Column(
          children: [
            SizedBox(height: 8.h),
            Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.002)..rotateY(_logoFlip.value),
              child: Center(
                child: Container(
                  width: logoW,
                  height: logoH,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16.r),
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryBlue.withValues(alpha: 0.35),
                        blurRadius: 22,
                        offset: const Offset(0, 7),
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16.r),
                    child: Padding(
                      padding: EdgeInsets.all(logoH * 0.06),
                      child: Image.asset(
                        AppUI.appLogoAsset,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(height: 14.h),
            Text(
              l10n.loginAppTitle,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppTheme.primaryBlue,
                fontSize: 25.sp,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
            SizedBox(height: 4.h),
            Text(
              l10n.loginSubtitle,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppTheme.textGray,
                fontSize: 11.sp,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: 14.h),
            Wrap(
              spacing: 8.w,
              runSpacing: 6.h,
              alignment: WrapAlignment.center,
              children: [
                _build3DBadge(Icons.verified_rounded, l10n.badgeGovtCertified,
                    AppTheme.primaryBlue, 0.0),
                _build3DBadge(Icons.security_rounded, l10n.badgeSslSecured,
                    AppTheme.primaryGreen, 0.5),
                _build3DBadge(Icons.lock_rounded, l10n.badgeCertInCompliant,
                    AppTheme.accentSaffron, 1.0),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _build3DBadge(IconData icon, String label, Color color, double phase) {
    final sinVal = math.sin(_badgeSpin.value + phase * math.pi) * 0.05;
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.002)..rotateX(sinVal * 0.5)..rotateY(sinVal),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.25), width: 1),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.1), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 12.sp, color: color),
          SizedBox(width: 4.w),
          Text(label, style: TextStyle(fontSize: 10.5.sp, color: color, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  // ─── CARD WRAPPER ─────────────────────────────────────────────────────────────

  Widget _wrapCard(Widget child) {
    return Opacity(
      opacity: _cardFade.value.clamp(0.0, 1.0),
      child: Transform(
        alignment: Alignment.topCenter,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.001)
          ..rotateX(_cardTiltX.value)
          ..translate(0.0, _cardSlideY.value),
        child: GovElevatedCard(
          padding: EdgeInsets.zero,
          child: child,
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // ──  IRCTC PIN SCREEN  (returning user)  ─────────────────────────────────────
  // ══════════════════════════════════════════════════════════════════════════════

  Widget _buildIRCTCPinCard() {
    final initials = (_savedEmail ?? 'U')
        .split('@')
        .first
        .substring(0, 1)
        .toUpperCase();

    return _wrapCard(
      Padding(
        padding: EdgeInsets.all(20.w),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Card header
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 4.w,
                    height: 22.h,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          AppTheme.primaryBlueLight,
                          AppTheme.primaryBlueDark,
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  SizedBox(width: 10.w),
                  Expanded(
                    child: Text(
                      'Quick Login  |  द्रुत लॉगिन',
                      style: TextStyle(
                        color: AppTheme.primaryBlue,
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 6.h),
              const Divider(color: AppTheme.dividerColor, thickness: 1),
              SizedBox(height: 20.h),

              // ── User Avatar + Email ──────────────────────────────────────────
              Center(
                child: Column(
                  children: [
                    // Avatar circle with initial
                    Container(
                      width: 64.w, height: 64.h,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppTheme.primaryBlueLight, AppTheme.primaryBlueDark],
                          begin: Alignment.topLeft, end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(
                            color: AppTheme.primaryBlue.withValues(alpha: 0.3),
                            blurRadius: 14, offset: const Offset(0, 5))],
                      ),
                      child: Center(
                        child: Text(initials, style: TextStyle(
                            color: Colors.white, fontSize: 26.sp,
                            fontWeight: FontWeight.w800)),
                      ),
                    ),
                    SizedBox(height: 10.h),
                    // Email display
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
                      decoration: BoxDecoration(
                        color: AppTheme.backgroundGrey,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppTheme.dividerColor, width: 1),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.account_circle_outlined,
                              color: AppTheme.textGray, size: 16),
                          SizedBox(width: 6.w),
                          Expanded(
                            child: Text(
                              _savedEmail ?? '',
                              style: TextStyle(
                                color: AppTheme.textDark,
                                fontSize: 13.sp,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text('Logged in as Admin',
                        style: TextStyle(color: AppTheme.textLightGray,
                            fontSize: 10.5.sp, fontWeight: FontWeight.w400)),
                  ],
                ),
              ),

              SizedBox(height: 24.h),

              // ── PIN Field ────────────────────────────────────────────────────
              _buildGovPINField(),

              SizedBox(height: 24.h),

              // ── PIN Login Button ─────────────────────────────────────────────
              _build3DLoginButton(
                label: 'LOGIN WITH PIN  |  लॉगिन करा',
                onTap: _handlePINLogin,
              ),

              SizedBox(height: 14.h),

              // ── Biometric Button ─────────────────────────────────────────────
              if (_biometricEnabled && _biometricSupported) ...[
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _isLoading ? null : _tryBiometricLogin,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.primaryBlue,
                      side: const BorderSide(color: AppTheme.primaryBlue, width: 1.5),
                      padding: EdgeInsets.symmetric(vertical: 14.h, horizontal: 10.w),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: FutureBuilder<List<String>>(
                      future: BiometricService.getAvailableBiometricNames(),
                      builder: (context, snapshot) {
                        final label = snapshot.hasData && snapshot.data!.isNotEmpty
                            ? 'Login with ${snapshot.data!.first}'
                            : 'Login with Biometric';
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.fingerprint, size: 22),
                            SizedBox(width: 8.w),
                            Expanded(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.center,
                                child: Text(
                                  label,
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  style: TextStyle(
                                    fontSize: 14.sp,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.primaryBlue,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
                SizedBox(height: 14.h),
              ],

              // ── Bottom links: Forgot PIN | Change User ───────────────────────
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8.w,
                runSpacing: 8.h,
                children: [
                  TextButton.icon(
                    onPressed: _showForgotPinDialog,
                    icon: const Icon(Icons.lock_reset_rounded,
                        size: 15, color: AppTheme.textGray),
                    label: Text('Forgot PIN?',
                        style: TextStyle(
                            color: AppTheme.textGray, fontSize: 12.sp,
                            fontWeight: FontWeight.w600)),
                    style: TextButton.styleFrom(padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  ),
                  GestureDetector(
                    onTap: _switchToChangeUser,
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 7.h),
                      decoration: BoxDecoration(
                        color: AppTheme.accentSaffron.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.accentSaffron.withValues(alpha: 0.4), width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.swap_horiz_rounded, size: 15.sp,
                              color: AppTheme.accentSaffron),
                          SizedBox(width: 5.w),
                          Text('Change User',
                              style: TextStyle(color: AppTheme.accentSaffron,
                                  fontSize: 12.sp, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 8.h),
              Text(
                'Change User: full login with password, CAPTCHA & OTP — same as first install.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10.sp,
                  color: AppTheme.textLightGray,
                  fontWeight: FontWeight.w500,
                ),
              ),

              SizedBox(height: 10.h),
              _buildSecurityInfoRow(context),
            ],
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // ──  FULL LOGIN FORM  (first-time / change user)  ────────────────────────────
  // ══════════════════════════════════════════════════════════════════════════════

  String _maskEmail(String email) {
    if (email.isEmpty) return '—';
    final at = email.indexOf('@');
    if (at <= 0) return '***';
    if (at <= 2) return '${email[0]}***${email.substring(at)}';
    return '${email.substring(0, 2)}***${email.substring(at)}';
  }

  Widget _buildFullLoginCard() {
    return _wrapCard(
      Padding(
        padding: EdgeInsets.all(20.w),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Card header
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 4.w,
                    height: 22.h,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          AppTheme.primaryBlueLight,
                          AppTheme.primaryBlueDark,
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  SizedBox(width: 10.w),
                  Expanded(
                    child: Text(
                      'Secure Login  |  सुरक्षित लॉगिन',
                      style: TextStyle(
                        color: AppTheme.primaryBlue,
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w800,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 6.h),
              const Divider(color: AppTheme.dividerColor, thickness: 1),

              if (!_waitingForEmailOtp) ...[
                SizedBox(height: 12.h),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.primaryBlue.withValues(alpha: 0.2)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.info_outline, color: AppTheme.primaryBlue, size: 16),
                    SizedBox(width: 8.w),
                    Expanded(
                      child: Text(
                        'IRCTC-style: enter User ID, Password and CAPTCHA, then a one-time OTP. Next visits: PIN or biometric. Use Change User on PIN screen for full login again.',
                        style: TextStyle(color: AppTheme.primaryBlue,
                            fontSize: 11.sp, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ]),
                ),
                SizedBox(height: 18.h),
                _buildGovTextField(
                  controller: _emailController,
                  icon: Icons.email_outlined,
                  label: 'User ID / Email  |  ईमेल पत्ता',
                  hint: 'example@gov.in',
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Email is required';
                    if (!value.contains('@')) return 'Enter a valid email';
                    return null;
                  },
                ),
                SizedBox(height: 14.h),
                _buildGovTextField(
                  controller: _passwordController,
                  icon: Icons.lock_outline_rounded,
                  label: 'Password  |  पासवर्ड',
                  hint: '••••••••',
                  isPassword: true,
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Password is required';
                    return null;
                  },
                ),
                SizedBox(height: 18.h),
                _buildCaptchaSection(),
                SizedBox(height: 24.h),
                _build3DLoginButton(
                  label: 'VERIFY & SEND OTP  |  ओटीपी पाठवा',
                  onTap: _handleFullFormLogin,
                ),
                SizedBox(height: 16.h),
                Center(
                  child: GestureDetector(
                    onTap: () {
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const InstituteSearchScreen()));
                    },
                    child: RichText(
                      text: TextSpan(
                        text: 'New institute? ',
                        style: TextStyle(
                            color: AppTheme.textGray, fontSize: 12.sp),
                        children: [
                          TextSpan(
                            text: 'Register here',
                            style: TextStyle(
                                color: AppTheme.primaryBlue,
                                fontSize: 12.sp,
                                fontWeight: FontWeight.w700,
                                decoration: TextDecoration.underline),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ] else ...[
                SizedBox(height: 12.h),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryGreen.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.primaryGreen.withValues(alpha: 0.25)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.sms_outlined, color: AppTheme.primaryGreen, size: 18),
                    SizedBox(width: 8.w),
                    Expanded(
                      child: Text(
                        'OTP sent for ${_maskEmail(_emailController.text.trim())}. Enter the 6-digit code. (Debug: see console/snackbar for demo code.)',
                        style: TextStyle(color: AppTheme.textDark,
                            fontSize: 11.sp, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ]),
                ),
                SizedBox(height: 20.h),
                TextFormField(
                  controller: _emailOtpController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: TextStyle(
                    fontSize: 22.sp,
                    letterSpacing: 8.w,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryBlue,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Enter OTP  |  ओटीपी टाका',
                    hintText: '• • • • • •',
                    counterText: '',
                    prefixIcon: Icon(Icons.pin_rounded, color: AppTheme.textGray, size: 19.sp),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppTheme.primaryBlue, width: 2),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'OTP required';
                    if (value.length != 6) return 'OTP must be 6 digits';
                    return null;
                  },
                  readOnly: _loginOtpVerified,
                ),
                if (_loginOtpVerified) ...[
                  SizedBox(height: 12.h),
                  Container(
                    padding:
                        EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryGreen.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppTheme.primaryGreen.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle,
                            color: AppTheme.primaryGreen, size: 20.sp),
                        SizedBox(width: 10.w),
                        Expanded(
                          child: Text(
                            _isLoading
                                ? 'OTP verified — signing you in securely…'
                                : 'OTP verified.',
                            style: TextStyle(
                              color: AppTheme.primaryGreen,
                              fontSize: 12.sp,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                SizedBox(height: 20.h),
                _build3DLoginButton(
                  label: 'VERIFY OTP & LOGIN  |  सत्यापन व लॉगिन',
                  onTap: () {
                    if (_formKey.currentState?.validate() ?? false) {
                      _handleEmailOtpVerify();
                    }
                  },
                ),
                SizedBox(height: 12.h),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8.w,
                  runSpacing: 6.h,
                  children: [
                    TextButton.icon(
                      onPressed: _isLoading ? null : _cancelEmailOtpStep,
                      icon: Icon(Icons.arrow_back, size: 18.sp, color: AppTheme.textGray),
                      label: Text(
                        'Back to login',
                        style: TextStyle(color: AppTheme.textGray, fontSize: 12.sp, fontWeight: FontWeight.w600),
                      ),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.symmetric(horizontal: 4.w),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    TextButton(
                      onPressed: (_loginOtpCooldownSec > 0 || _isLoading) ? null : _resendLoginOtp,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.symmetric(horizontal: 4.w),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                      child: Text(
                        _loginOtpCooldownSec > 0
                            ? 'Resend in ${_loginOtpCooldownSec}s'
                            : 'Resend OTP',
                        style: TextStyle(
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primaryBlue,
                        ),
                      ),
                    ),
                  ],
                ),
              ],

              SizedBox(height: 14.h),
              _buildSecurityInfoRow(context),
            ],
          ),
        ),
      ),
    );
  }

  // ─── CAPTCHA WIDGET ───────────────────────────────────────────────────────────

  Widget _buildCaptchaSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label: title on its own row so "Verified" never steals width (avoids tiny overflows)
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Icon(Icons.verified_user_outlined,
                    size: 14, color: AppTheme.primaryBlue),
                SizedBox(width: 6.w),
                Expanded(
                  child: Text(
                    'Verification Code  |  सत्यापन कोड',
                    style: TextStyle(
                      color: AppTheme.textGray,
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (_captchaVerified) ...[
              SizedBox(height: 4.h),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle,
                      color: AppTheme.primaryGreen, size: 14),
                  SizedBox(width: 4.w),
                  Text(
                    'Verified',
                    style: TextStyle(
                      color: AppTheme.primaryGreen,
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        SizedBox(height: 8.h),

        // CAPTCHA image + refresh
        Row(children: [
          Expanded(
            child: SizedBox(
              height: 52.h,
              child: CustomPaint(
                painter: _CaptchaPainter(
                  text: _captchaText,
                  charColors: _captchaColors,
                  charRotations: _captchaRotations,
                ),
              ),
            ),
          ),
          SizedBox(width: 8.w),
          // Refresh button
          InkWell(
            onTap: _generateCaptcha,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: EdgeInsets.all(10.w),
              decoration: BoxDecoration(
                color: AppTheme.primaryBlue.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.primaryBlue.withValues(alpha: 0.2)),
              ),
              child: Icon(Icons.refresh_rounded,
                  color: AppTheme.primaryBlue, size: 22.sp),
            ),
          ),
        ]),
        SizedBox(height: 10.h),

        // Captcha input
        TextFormField(
          controller: _captchaController,
          textCapitalization: TextCapitalization.characters,
          maxLength: 6,
          onChanged: (val) {
            if (val.toUpperCase() == _captchaText && !_captchaVerified) {
              setState(() => _captchaVerified = true);
            } else if (val.toUpperCase() != _captchaText && _captchaVerified) {
              setState(() => _captchaVerified = false);
            }
          },
          style: TextStyle(color: AppTheme.textDark, fontSize: 14.sp,
              fontWeight: FontWeight.w600, letterSpacing: 2),
          decoration: InputDecoration(
            labelText: 'Type the code shown above',
            hintText: 'e.g. A7K9MX',
            hintStyle: TextStyle(fontSize: 13.sp, color: AppTheme.textLightGray,
                letterSpacing: 1),
            prefixIcon: Icon(Icons.keyboard_outlined, size: 19.sp, color: AppTheme.textGray),
            suffixIcon: _captchaVerified
                ? const Icon(Icons.check_circle, color: AppTheme.primaryGreen)
                : null,
            counterText: '',
            filled: true, fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppTheme.dividerColor, width: 1.5)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppTheme.dividerColor, width: 1.5)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppTheme.primaryBlue, width: 2)),
            errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppTheme.accentRed, width: 1.5)),
            contentPadding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 14.h),
          ),
          validator: (value) {
            if (value == null || value.isEmpty) return 'Please enter the verification code';
            if (value.toUpperCase() != _captchaText) return 'Incorrect code — please try again';
            return null;
          },
        ),
      ],
    );
  }

  // ─── SHARED UI WIDGETS ────────────────────────────────────────────────────────

  Widget _build3DLoginButton({
    required String label,
    required VoidCallback onTap,
  }) {
    return AnimatedBuilder(
      animation: _buttonPulseController,
      builder: (_, child) {
        return GestureDetector(
          onTapDown: (_) => setState(() => _buttonPressed = true),
          onTapUp: (_) {
            setState(() => _buttonPressed = false);
            if (!_isLoading) onTap();
          },
          onTapCancel: () => setState(() => _buttonPressed = false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: double.infinity,
            height: 52.h,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001)
              ..translate(0.0, _buttonPressed ? 3.0 : 0.0)
              ..scale(_buttonPressed ? 0.97 : (_isLoading ? 1.0 : _buttonPulse.value)),
            transformAlignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: _buttonPressed || _isLoading
                  ? const LinearGradient(
                      colors: [AppTheme.primaryBlueDark, AppTheme.primaryBlue],
                      begin: Alignment.topLeft, end: Alignment.bottomRight)
                  : const LinearGradient(
                      colors: [AppTheme.primaryBlueLight, AppTheme.primaryBlueDark],
                      begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(10),
              boxShadow: _buttonPressed
                  ? [BoxShadow(color: AppTheme.primaryBlue.withValues(alpha: 0.2),
                      blurRadius: 4, offset: const Offset(0, 1))]
                  : [
                      BoxShadow(color: AppTheme.primaryBlue.withValues(alpha: 0.45),
                          blurRadius: 16, offset: const Offset(0, 6), spreadRadius: 1),
                      BoxShadow(color: AppTheme.primaryBlueDark.withValues(alpha: 0.3),
                          blurRadius: 4, offset: const Offset(0, 2)),
                    ],
            ),
            child: child,
          ),
        );
      },
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 10.w),
        child: _isLoading
            ? Center(
                child: SizedBox(
                  width: 24.w,
                  height: 24.w,
                  child: const CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.5,
                  ),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.login_rounded, color: Colors.white, size: 20.sp),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.center,
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13.sp,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildGovTextField({
    required TextEditingController controller,
    required IconData icon,
    required String label,
    required String hint,
    TextInputType? keyboardType,
    bool isPassword = false,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: keyboardType == TextInputType.emailAddress
          ? TextCapitalization.none : TextCapitalization.sentences,
      obscureText: isPassword && !_isPasswordVisible,
      style: TextStyle(color: AppTheme.textDark, fontSize: 14.sp, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 19.sp, color: AppTheme.textGray),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                    _isPasswordVisible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    color: AppTheme.textGray, size: 19.sp),
                onPressed: () => setState(() => _isPasswordVisible = !_isPasswordVisible))
            : null,
        filled: true, fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppTheme.dividerColor, width: 1.5)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppTheme.dividerColor, width: 1.5)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppTheme.primaryBlue, width: 2)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppTheme.accentRed, width: 1.5)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppTheme.accentRed, width: 2)),
        contentPadding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 14.h),
        labelStyle: TextStyle(fontSize: 12.5.sp, color: AppTheme.textGray),
        hintStyle: TextStyle(fontSize: 13.sp, color: AppTheme.textLightGray),
      ),
      validator: validator,
    );
  }

  Widget _buildGovPINField() {
    return TextFormField(
      controller: _pinController,
      keyboardType: TextInputType.number,
      maxLength: 6,
      obscureText: true,
      textAlign: TextAlign.center,
      style: TextStyle(color: AppTheme.primaryBlue, fontSize: 22.sp,
          letterSpacing: 10, fontWeight: FontWeight.bold),
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: 'Enter PIN  |  पिन टाका',
        hintText: '• • • •',
        hintStyle: TextStyle(color: AppTheme.textLightGray, fontSize: 18.sp, letterSpacing: 8),
        prefixIcon: Icon(Icons.pin_rounded, color: AppTheme.textGray, size: 19.sp),
        filled: true, fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppTheme.dividerColor, width: 1.5)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppTheme.dividerColor, width: 1.5)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppTheme.primaryBlue, width: 2)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppTheme.accentRed, width: 1.5)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppTheme.accentRed, width: 2)),
        counterText: '',
        labelStyle: TextStyle(fontSize: 12.5.sp, color: AppTheme.textGray),
        contentPadding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 16.h),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) return 'PIN is required';
        if (value.length < 4 || value.length > 6) return 'PIN must be 4–6 digits';
        return null;
      },
    );
  }

  Widget _buildSecurityInfoRow(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 10.w,
      runSpacing: 8.h,
      children: [
        _buildSecurityChip(Icons.lock_rounded, l10n.chipEncrypted, AppTheme.primaryGreen),
        _buildSecurityChip(Icons.shield_rounded, l10n.chipGovtPortal, AppTheme.primaryBlue),
        _buildSecurityChip(Icons.verified_user_rounded, l10n.chipSecure, AppTheme.accentSaffron),
      ],
    );
  }

  Widget _buildSecurityChip(IconData icon, String label, Color color) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 12.sp, color: color),
      SizedBox(width: 3.w),
      Text(label, style: TextStyle(fontSize: 10.5.sp, color: AppTheme.textGray,
          fontWeight: FontWeight.w500)),
    ]);
  }

  // ─── FOOTER ───────────────────────────────────────────────────────────────────

  Widget _buildFooter(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final localeSvc = context.watch<LocaleService>();
    return Column(
      children: [
        Row(children: [
          const Expanded(child: Divider(color: AppTheme.dividerColor)),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 12.w),
            child: Text(l10n.footerOfficialUse,
                style: TextStyle(fontSize: 10.sp, color: AppTheme.textLightGray,
                    fontWeight: FontWeight.w600, letterSpacing: 1.2)),
          ),
          const Expanded(child: Divider(color: AppTheme.dividerColor)),
        ]),
        SizedBox(height: 10.h),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4.w,
          runSpacing: 4.h,
          children: [
            Text(
              l10n.languageToggleHint,
              style: TextStyle(fontSize: 10.sp, color: AppTheme.textGray, fontWeight: FontWeight.w600),
            ),
            TextButton(
              onPressed: () => localeSvc.setLocale(const Locale('en')),
              style: TextButton.styleFrom(
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                l10n.languageEnglish,
                style: TextStyle(
                  fontSize: 11.sp,
                  fontWeight: FontWeight.w800,
                  color: localeSvc.locale.languageCode == 'en' ? AppTheme.primaryBlue : AppTheme.textGray,
                  decoration: localeSvc.locale.languageCode == 'en' ? TextDecoration.underline : null,
                ),
              ),
            ),
            Text('|', style: TextStyle(fontSize: 11.sp, color: AppTheme.textLightGray)),
            TextButton(
              onPressed: () => localeSvc.setLocale(const Locale('mr')),
              style: TextButton.styleFrom(
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                l10n.languageMarathi,
                style: TextStyle(
                  fontSize: 11.sp,
                  fontWeight: FontWeight.w800,
                  color: localeSvc.locale.languageCode == 'mr' ? AppTheme.primaryBlue : AppTheme.textGray,
                  decoration: localeSvc.locale.languageCode == 'mr' ? TextDecoration.underline : null,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 12.h),
        Text(l10n.footerCredit,
            style: TextStyle(fontSize: 11.sp, color: AppTheme.textLightGray,
                fontWeight: FontWeight.w500),
            textAlign: TextAlign.center),
        SizedBox(height: 4.h),
        Text(l10n.loginCopyright('${DateTime.now().year}'),
            style: TextStyle(fontSize: 10.sp, color: AppTheme.textLightGray,
                fontWeight: FontWeight.w400),
            textAlign: TextAlign.center),
        SizedBox(height: 10.h),
        Row(children: [
          Expanded(child: Container(height: 3, decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFFFF6600), Color(0xFFFF9933)])))),
          Expanded(child: Container(height: 3, color: Colors.white70)),
          Expanded(child: Container(height: 3, decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFF006600), Color(0xFF138808)])))),
        ]),
      ],
    );
  }
}
