import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Biometric Authentication Service (IRCTC Style)
/// 
/// Provides fingerprint and face unlock functionality
/// Similar to IRCTC's biometric authentication
class BiometricService {
  static final LocalAuthentication _localAuth = LocalAuthentication();
  static const String _biometricEnabledKey = 'biometric_enabled';
  static const String _biometricEmailKey = 'biometric_email';
  /// Cleared on uninstall; when true we already showed "enable biometric?" this install.
  static const String _biometricSetupPromptShownKey = 'biometric_setup_prompt_shown';

  static Future<bool> wasBiometricSetupPromptShown() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_biometricSetupPromptShownKey) ?? false;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error reading biometric prompt flag: $e');
      return false;
    }
  }

  static Future<void> markBiometricSetupPromptShown() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_biometricSetupPromptShownKey, true);
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error saving biometric prompt flag: $e');
    }
  }

  /// True when the device can use biometric auth (hardware + at least one enrolled biometric).
  static Future<bool> isDeviceSupported() async {
    try {
      if (!await _localAuth.isDeviceSupported()) return false;
      final enrolled = await _localAuth.getAvailableBiometrics();
      return enrolled.isNotEmpty;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error checking biometric support: $e');
      return false;
    }
  }

  /// Get available biometric types (fingerprint, face, etc.)
  static Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _localAuth.getAvailableBiometrics();
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error getting available biometrics: $e');
      return [];
    }
  }

  /// Check if biometric authentication is enabled for user
  static Future<bool> isBiometricEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_biometricEnabledKey) ?? false;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error checking biometric enabled: $e');
      return false;
    }
  }

  /// Enable biometric authentication for user
  static Future<bool> enableBiometric(String email) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_biometricEnabledKey, true);
      await prefs.setString(_biometricEmailKey, email);
      if (kDebugMode) debugPrint('✅ Biometric authentication enabled for: $email');
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error enabling biometric: $e');
      return false;
    }
  }

  /// Disable biometric authentication
  static Future<bool> disableBiometric() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_biometricEnabledKey, false);
      await prefs.remove(_biometricEmailKey);
      if (kDebugMode) debugPrint('✅ Biometric authentication disabled');
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error disabling biometric: $e');
      return false;
    }
  }

  /// Get stored email for biometric login
  static Future<String?> getBiometricEmail() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_biometricEmailKey);
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error getting biometric email: $e');
      return null;
    }
  }

  /// Authenticate using the device biometric (Face ID, fingerprint, etc.).
  ///
  /// [requirePreferenceEnabled]: when false, used for first-time setup so the OS
  /// can show Face ID / fingerprint permission and the user can confirm before
  /// we save [enableBiometric].
  static Future<bool> authenticate({
    String reason = 'Authenticate to continue',
    bool useErrorDialogs = true,
    bool stickyAuth = true,
    bool requirePreferenceEnabled = true,
  }) async {
    try {
      final isSupported = await isDeviceSupported();
      if (!isSupported) {
        if (kDebugMode) debugPrint('⚠️ No enrolled biometrics on this device');
        return false;
      }

      if (requirePreferenceEnabled) {
        final isEnabled = await isBiometricEnabled();
        if (!isEnabled) {
          if (kDebugMode) debugPrint('⚠️ Biometric login not enabled in app settings');
          return false;
        }
      }

      final didAuthenticate = await _localAuth.authenticate(
        localizedReason: reason,
        options: AuthenticationOptions(
          useErrorDialogs: useErrorDialogs,
          stickyAuth: stickyAuth,
          sensitiveTransaction: false,
          biometricOnly: true,
        ),
      );

      if (didAuthenticate) {
        if (kDebugMode) debugPrint('✅ Biometric authentication successful');
      } else {
        if (kDebugMode) debugPrint('❌ Biometric authentication failed or cancelled');
      }

      return didAuthenticate;
    } on PlatformException catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Biometric authentication error: ${e.code} - ${e.message}');
      }
      return false;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error during biometric authentication: $e');
      return false;
    }
  }

  /// Stop authentication (if in progress)
  static Future<void> stopAuthentication() async {
    try {
      await _localAuth.stopAuthentication();
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error stopping authentication: $e');
    }
  }

  /// Get biometric type name for display
  static String getBiometricTypeName(BiometricType type) {
    switch (type) {
      case BiometricType.face:
        return 'Face ID';
      case BiometricType.fingerprint:
        return 'Fingerprint';
      case BiometricType.strong:
        return 'Strong Biometric';
      case BiometricType.weak:
        return 'Biometric';
      case BiometricType.iris:
        return 'Iris';
      default:
        return 'Biometric';
    }
  }

  /// Get all available biometric types as string list
  static Future<List<String>> getAvailableBiometricNames() async {
    final types = await getAvailableBiometrics();
    return types.map((type) => getBiometricTypeName(type)).toList();
  }
}
