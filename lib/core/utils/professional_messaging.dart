import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../../presentation/screens/help_desk_screen.dart';

/// Professional messaging utility for consistent user communication
/// Provides standardized success, error, warning, and info messages
class ProfessionalMessaging {
  /// Show professional success message
  static void showSuccess(
    BuildContext context, {
    required String title,
    required String message,
    String? actionLabel,
    VoidCallback? onAction,
    int durationSeconds = 4,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    message,
                    style: const TextStyle(fontSize: 14, color: Colors.white),
                  ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: AppTheme.accentGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        duration: Duration(seconds: durationSeconds),
        action: actionLabel != null && onAction != null
            ? SnackBarAction(
                label: actionLabel,
                textColor: Colors.white,
                onPressed: onAction,
              )
            : null,
      ),
    );
  }

  /// Show professional error message
  static void showError(
    BuildContext context, {
    required String title,
    required String message,
    bool showHelp = true,
    int durationSeconds = 5,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    message,
                    style: const TextStyle(fontSize: 14, color: Colors.white),
                  ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: AppTheme.accentRed,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        duration: Duration(seconds: durationSeconds),
        action: showHelp
            ? SnackBarAction(
                label: 'Help',
                textColor: Colors.white,
                onPressed: () {
                  Navigator.pushNamed(context, HelpDeskScreen.routeName);
                },
              )
            : null,
      ),
    );
  }

  /// Show professional warning message
  static void showWarning(
    BuildContext context, {
    required String title,
    required String message,
    int durationSeconds = 3,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.white, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    message,
                    style: const TextStyle(fontSize: 14, color: Colors.white),
                  ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: AppTheme.accentOrange,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        duration: Duration(seconds: durationSeconds),
      ),
    );
  }

  /// Show professional info message
  static void showInfo(
    BuildContext context, {
    required String title,
    required String message,
    int durationSeconds = 3,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.white, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    message,
                    style: const TextStyle(fontSize: 14, color: Colors.white),
                  ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: AppTheme.primaryBlue,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        duration: Duration(seconds: durationSeconds),
      ),
    );
  }

  /// Get professional error message based on error type
  static String getProfessionalErrorMessage(String error) {
    final errorLower = error.toLowerCase();

    if (errorLower.contains('permission') || errorLower.contains('denied')) {
      return 'You don\'t have permission to perform this action. Please contact your administrator.';
    } else if (errorLower.contains('network') ||
        errorLower.contains('connection') ||
        errorLower.contains('internet') ||
        errorLower.contains('offline')) {
      return 'Network connection error. Please check your internet connection and try again.';
    } else if (errorLower.contains('timeout')) {
      return 'Request timed out. Please check your connection and try again.';
    } else if (errorLower.contains('index') || errorLower.contains('firestore')) {
      return 'Database configuration required. Please contact technical support for assistance.';
    } else if (errorLower.contains('invalid') || errorLower.contains('validation')) {
      return 'Invalid input detected. Please check your entries and try again.';
    } else if (errorLower.contains('not found') || errorLower.contains('missing')) {
      return 'The requested information was not found. Please verify and try again.';
    } else if (errorLower.contains('already exists') || errorLower.contains('duplicate')) {
      return 'This record already exists. Please check for duplicates.';
    } else if (errorLower.contains('location') || errorLower.contains('gps')) {
      return 'Location services are required. Please enable GPS and location permissions.';
    } else if (errorLower.contains('camera') || errorLower.contains('photo')) {
      return 'Camera access is required. Please enable camera permissions in settings.';
    } else if (errorLower.contains('face') || errorLower.contains('recognition')) {
      return 'Face recognition failed. Please ensure good lighting and clear visibility.';
    } else {
      // Return the actual error message if it doesn't match any pattern
      // This helps with debugging while still being user-friendly
      // But truncate if too long
      if (error.length > 150) {
        return '${error.substring(0, 150)}...';
      }
      return error;
    }
  }

  /// Build instruction card widget
  static Widget buildInstructionCard({
    required String title,
    required List<String> steps,
    IconData icon = Icons.info_outline,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.white.withValues(alpha: 0.9), size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...steps.asMap().entries.map((entry) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${entry.key + 1}. ${entry.value}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  /// Build help tooltip
  static Widget buildHelpTooltip(String message) {
    return Tooltip(
      message: message,
      child: Icon(
        Icons.help_outline,
        color: Colors.white.withValues(alpha: 0.7),
        size: 18,
      ),
    );
  }
}
