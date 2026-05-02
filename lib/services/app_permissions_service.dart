import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

/// First-launch permission gate so camera, location, and notifications are
/// requested consistently on all supported phones (Android / iOS).
class AppPermissionsService {
  AppPermissionsService._();

  static const String prefKeySetupDone = 'permissions_setup_done';

  static bool get shouldRunPermissionGate => !kIsWeb;

  static Future<bool> isLocationServiceEnabled() async {
    if (kIsWeb) return true;
    return Geolocator.isLocationServiceEnabled();
  }

  static Future<void> openLocationSettings() => Geolocator.openLocationSettings();

  static Future<bool> openDeviceAppSettings() => openAppSettings();

  /// Request core runtime permissions in a stable order (camera → location → notifications).
  /// Returns map of permission → final status after request.
  static Future<Map<Permission, PermissionStatus>> requestCorePermissions() async {
    if (kIsWeb) return {};

    final out = <Permission, PermissionStatus>{};

    out[Permission.camera] = await Permission.camera.request();

    out[Permission.locationWhenInUse] = await Permission.locationWhenInUse.request();

    // Android 13+ / iOS: local reminders and institute notifications
    final notif = await Permission.notification.request();
    out[Permission.notification] = notif;

    return out;
  }

  static bool criticalDenied(Map<Permission, PermissionStatus> statuses) {
    final cam = statuses[Permission.camera] ?? PermissionStatus.denied;
    final loc = statuses[Permission.locationWhenInUse] ?? PermissionStatus.denied;
    return !cam.isGranted || !loc.isGranted;
  }

  static bool hasPermanentDenial(Map<Permission, PermissionStatus> statuses) {
    for (final s in statuses.values) {
      if (s.isPermanentlyDenied) return true;
    }
    return false;
  }
}

