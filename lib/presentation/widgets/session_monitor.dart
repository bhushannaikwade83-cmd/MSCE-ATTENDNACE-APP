import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/session_manager.dart';
import '../../services/biometric_service.dart';
import '../../core/theme/app_theme.dart';
import '../screens/login_screen.dart';
import '../screens/biometric_lock_screen.dart';

/// Session Monitor Widget
/// Monitors user session and shows expiry dialog when session is about to expire
class SessionMonitor extends StatefulWidget {
  final Widget child;

  const SessionMonitor({
    super.key,
    required this.child,
  });

  @override
  State<SessionMonitor> createState() => _SessionMonitorState();
}

class _SessionMonitorState extends State<SessionMonitor> with WidgetsBindingObserver {
  Timer? _sessionCheckTimer;
  Timer? _autoLogoutTimer;
  bool _isDialogShowing = false;
  final ValueNotifier<int> _countdownNotifier = ValueNotifier<int>(5);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startSessionMonitoring();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sessionCheckTimer?.cancel();
    _autoLogoutTimer?.cancel();
    _countdownNotifier.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      // App went to background - track the time
      SessionManager.setBackgroundTime();
    } else if (state == AppLifecycleState.resumed) {
      // App resumed - check if session expired while in background
      SessionManager.clearBackgroundTime();
      
      if (SessionManager.isAuthenticated()) {
        // Check if session expired while in background
        if (!SessionManager.isSessionValid()) {
          // Session expired - auto logout
          _performAutoLogout();
          return;
        }
        
        // Check if biometric is enabled - if yes, show lock screen (IRCTC style)
        BiometricService.isBiometricEnabled().then((isEnabled) {
          if (isEnabled && mounted) {
            // Show biometric lock screen when app resumes
            Navigator.pushNamed(context, BiometricLockScreen.routeName);
          } else {
            // Just update activity if biometric not enabled
            SessionManager.updateActivity();
          }
        });
      }
    }
  }

  void _startSessionMonitoring() {
    // Check session every 30 seconds
    _sessionCheckTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      // Only monitor if user is authenticated
      if (!SessionManager.isAuthenticated()) {
        return;
      }

      // Check if session is expired (don't update activity here - only check)
      if (!SessionManager.isSessionValid() && !_isDialogShowing) {
        _showSessionExpiredDialog();
      }
    });
  }

  void _showSessionExpiredDialog() {
    if (_isDialogShowing || !mounted) return;

    setState(() {
      _isDialogShowing = true;
      _countdownNotifier.value = 5;
    });

    // Start auto logout countdown
    _autoLogoutTimer?.cancel();
    _autoLogoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      _countdownNotifier.value = _countdownNotifier.value - 1;

      if (_countdownNotifier.value <= 0) {
        timer.cancel();
        _performAutoLogout();
      }
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _SessionExpiredDialog(
        countdown: _countdownNotifier.value,
        countdownNotifier: _countdownNotifier,
        onStay: () {
          _extendSession();
        },
        onLogout: () {
          _performAutoLogout();
        },
      ),
    ).then((_) {
      _autoLogoutTimer?.cancel();
      setState(() {
        _isDialogShowing = false;
      });
    });
  }

  void _extendSession() {
    SessionManager.extendSession();
    _autoLogoutTimer?.cancel();
    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 12),
              Text('Session extended successfully'),
            ],
          ),
          backgroundColor: AppTheme.primaryGreen,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _performAutoLogout() async {
    _autoLogoutTimer?.cancel();
    if (mounted) {
      Navigator.of(context).pop(); // Close dialog
      await SessionManager.signOut();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.white),
                SizedBox(width: 12),
                Expanded(
                  child: Text('Session expired. You have been logged out automatically.'),
                ),
              ],
            ),
            backgroundColor: AppTheme.accentOrange,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Wrap child with a listener to track user interactions
    return NotificationListener<ScrollNotification>(
      onNotification: (_) {
        // Update activity on scroll
        if (SessionManager.isAuthenticated()) {
          SessionManager.updateActivity();
        }
        return false;
      },
      child: GestureDetector(
        onTap: () {
          // Update activity on tap
          if (SessionManager.isAuthenticated()) {
            SessionManager.updateActivity();
          }
        },
        child: widget.child,
      ),
    );
  }
}

class _SessionExpiredDialog extends StatefulWidget {
  final int countdown;
  final VoidCallback onStay;
  final VoidCallback onLogout;
  final ValueNotifier<int> countdownNotifier;

  const _SessionExpiredDialog({
    required this.countdown,
    required this.onStay,
    required this.onLogout,
    required this.countdownNotifier,
  });

  @override
  State<_SessionExpiredDialog> createState() => _SessionExpiredDialogState();
}

class _SessionExpiredDialogState extends State<_SessionExpiredDialog> {
  @override
  void initState() {
    super.initState();
    widget.countdownNotifier.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentCountdown = widget.countdownNotifier.value;

    return PopScope(
      canPop: false,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.accentOrange.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.timer_off_rounded,
                color: AppTheme.accentOrange,
                size: 28,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Session Expired',
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
            const Text(
              'Your session has expired due to inactivity.',
              style: TextStyle(
                fontSize: 16,
                color: AppTheme.textDark,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.accentOrange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppTheme.accentOrange.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: AppTheme.accentOrange,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Auto logout in $currentCountdown seconds',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.accentOrange,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Would you like to stay logged in?',
              style: TextStyle(
                fontSize: 14,
                color: AppTheme.textGray,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: widget.onLogout,
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.accentRed,
            ),
            child: const Text('Logout Now'),
          ),
          ElevatedButton(
            onPressed: widget.onStay,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryGreen,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Stay Logged In'),
          ),
        ],
      ),
    );
  }
}
