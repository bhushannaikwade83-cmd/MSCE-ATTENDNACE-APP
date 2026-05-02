import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_theme.dart';
import '../../services/app_permissions_service.dart';
import 'biometric_lock_screen.dart';
import 'login_screen.dart';
import 'onboarding_screen.dart';

/// Shown once at first launch (before onboarding / login / biometric) to request
/// camera, location, and notification permissions in a consistent order on all devices.
class AppPermissionsScreen extends StatefulWidget {
  static const routeName = '/app-permissions';

  const AppPermissionsScreen({super.key});

  @override
  State<AppPermissionsScreen> createState() => _AppPermissionsScreenState();
}

class _AppPermissionsScreenState extends State<AppPermissionsScreen> {
  bool _busy = false;
  Map<Permission, PermissionStatus>? _lastStatuses;
  bool _askedOnce = false;

  Future<void> _finishAndNavigate() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppPermissionsService.prefKeySetupDone, true);
    if (!mounted) return;

    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      Navigator.pushReplacementNamed(context, BiometricLockScreen.routeName);
    } else {
      final onboardingCompleted = prefs.getBool('onboarding_completed') ?? false;
      if (onboardingCompleted) {
        Navigator.pushReplacementNamed(context, LoginScreen.routeName);
      } else {
        Navigator.pushReplacementNamed(context, OnboardingScreen.routeName);
      }
    }
  }

  Future<void> _requestPermissions() async {
    setState(() => _busy = true);
    try {
      final locOn = await AppPermissionsService.isLocationServiceEnabled();
      if (!locOn && mounted) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Location services'),
            content: const Text(
              'GPS is turned off. Turn it on so attendance can verify you are at the institute. '
              'You can enable it in system settings, then return here.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Not now'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  AppPermissionsService.openLocationSettings();
                },
                child: const Text('Open location settings'),
              ),
            ],
          ),
        );
      }

      final statuses = await AppPermissionsService.requestCorePermissions();
      if (!mounted) return;
      setState(() {
        _lastStatuses = statuses;
        _askedOnce = true;
        _busy = false;
      });

      if (AppPermissionsService.criticalDenied(statuses) && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Camera and location are needed for attendance. You can allow them later in system settings.',
            ),
            duration: Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not request permissions: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final permanentlyDenied = _lastStatuses != null &&
        AppPermissionsService.hasPermanentDenial(_lastStatuses!);

    return Scaffold(
      backgroundColor: AppTheme.backgroundOffWhite,
      appBar: AppBar(
        title: const Text('Permissions'),
        centerTitle: true,
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Allow access for MSCE Attendance',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textDark,
                    ),
              ),
              const SizedBox(height: 12),
              Text(
                'These permissions let the app work the same way on all supported phones: '
                'face-based attendance, GPS check at the institute, and reminders when available.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppTheme.textGray,
                      height: 1.4,
                    ),
              ),
              const SizedBox(height: 24),
              _tile(
                icon: Icons.camera_alt_rounded,
                title: 'Camera',
                subtitle: 'Take photos for attendance and student enrollment.',
              ),
              const SizedBox(height: 12),
              _tile(
                icon: Icons.location_on_outlined,
                title: 'Location',
                subtitle: 'Confirm you are within the institute area when marking attendance.',
              ),
              const SizedBox(height: 12),
              _tile(
                icon: Icons.notifications_active_outlined,
                title: 'Notifications',
                subtitle: 'Optional alerts for institute schedules and reminders.',
              ),
              const Spacer(),
              if (permanentlyDenied)
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => AppPermissionsService.openDeviceAppSettings(),
                  icon: const Icon(Icons.settings),
                  label: const Text('Open app settings'),
                ),
              if (permanentlyDenied) const SizedBox(height: 12),
              FilledButton(
                onPressed: _busy
                    ? null
                    : () async {
                        if (!_askedOnce) {
                          await _requestPermissions();
                        } else {
                          await _finishAndNavigate();
                        }
                      },
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primaryBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _busy
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(_askedOnce ? 'Continue to app' : 'Allow access'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tile({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppTheme.primaryBlue, size: 28),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: AppTheme.textDark,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade700,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
