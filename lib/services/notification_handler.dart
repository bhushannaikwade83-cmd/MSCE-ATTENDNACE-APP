import 'package:flutter/material.dart';
import '../presentation/widgets/institute_status_dialog.dart';
import '../presentation/screens/admin_home_screen.dart';
import 'institute_status_service.dart';

/// Global notification handler for processing notification taps
class NotificationHandler {
  static BuildContext? _context;
  static String? _currentInstituteId;

  /// Set the current context and institute ID
  static void setContext(BuildContext? context, String? instituteId) {
    _context = context;
    _currentInstituteId = instituteId;
  }

  /// Handle notification tap based on payload
  static Future<void> handleNotificationTap(String? payload) async {
    if (payload == null || _context == null) return;

    final parts = payload.split('|');
    if (parts.length < 2) return;

    final action = parts[0];
    final instituteId = parts[1];

    // Navigate to admin home if not already there
    if (_context != null && _context!.mounted) {
      // Navigate to admin home screen
      Navigator.of(_context!).pushNamedAndRemoveUntil(
        AdminHomeScreen.routeName,
        (route) => false,
      );

      // Wait a bit for navigation to complete
      await Future.delayed(const Duration(milliseconds: 500));

      // Show institute status dialog
      if (_context != null && _context!.mounted) {
        final statusService = InstituteStatusService();
        final status = await statusService.getTodayStatus(instituteId);
        final currentStatus = status?['status'] as String?;

        showDialog(
          context: _context!,
          builder: (context) => InstituteStatusDialog(
            instituteId: instituteId,
            currentStatus: currentStatus,
          ),
        );
      }
    }
  }
}
