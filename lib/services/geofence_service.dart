import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_db.dart';

/// Geofence / GPS settings (Supabase `gps_settings` + `institute_geofence`).
class GeofenceService {
  SupabaseClient get _db => appDb;

  Stream<List<Map<String, dynamic>>> getLockedGeofences() {
    late StreamController<List<Map<String, dynamic>>> controller;
    Timer? timer;

    Future<List<Map<String, dynamic>>> load() async {
      final rows = await _db.from('gps_settings').select().eq('is_locked', true);
      return rows
          .map(
            (r) => {
              'instituteId': r['institute_id'],
              'adminId': r['admin_id'],
              'latitude': r['latitude'],
              'longitude': r['longitude'],
              'radius': r['radius'],
            },
          )
          .toList();
    }

    controller = StreamController<List<Map<String, dynamic>>>(
      onListen: () async {
        controller.add(await load());
        timer = Timer.periodic(const Duration(seconds: 4), (_) async {
          if (!controller.isClosed) {
            controller.add(await load());
          }
        });
      },
      onCancel: () => timer?.cancel(),
    );

    return controller.stream;
  }

  Stream<List<Map<String, dynamic>>> getLockedGeofencesByInstitute(String instituteId) {
    return getLockedGeofences().map(
      (list) => list.where((e) => e['instituteId'] == instituteId).toList(),
    );
  }

  Future<Map<String, dynamic>> unlockGeofence({
    required String instituteId,
    required String adminId,
  }) async {
    try {
      final currentUser = _db.auth.currentUser;
      if (currentUser == null) {
        return {'success': false, 'message': 'User not authenticated'};
      }

      final row = await _db
          .from('gps_settings')
          .select()
          .eq('institute_id', instituteId)
          .eq('admin_id', adminId)
          .maybeSingle();

      if (row == null) {
        return {'success': false, 'message': 'Geofence not found'};
      }

      if (row['is_locked'] != true) {
        return {'success': false, 'message': 'Geofence is not locked'};
      }

      const double radius = 30.0;
      final latitude = (row['latitude'] as num?)?.toDouble();
      final longitude = (row['longitude'] as num?)?.toDouble();

      if (latitude != null && longitude != null) {
        try {
          final position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
            ),
          );

          if (position.isMocked) {
            return {
              'success': false,
              'message': 'Cannot unlock: Fake GPS detected. Please turn off Mock Location apps.',
            };
          }

          final distance = Geolocator.distanceBetween(
            position.latitude,
            position.longitude,
            latitude,
            longitude,
          );

          if (distance <= radius) {
            return {
              'success': false,
              'message':
                  'Cannot unlock: Admin is within ${radius.toStringAsFixed(0)}m of the locked location.',
            };
          }
        } catch (e) {
          if (kDebugMode) debugPrint('⚠️ Error checking location for unlock: $e');
        }
      }

      await _db.from('gps_settings').update({
        'is_locked': false,
        'unlocked_at': DateTime.now().toUtc().toIso8601String(),
        'unlocked_by': currentUser.id,
        'unlocked_by_email': currentUser.email ?? 'Unknown',
      }).eq('institute_id', instituteId).eq('admin_id', adminId);

      return {'success': true, 'message': 'Geofence unlocked successfully'};
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error unlocking geofence: $e');
      return {'success': false, 'message': 'Error unlocking geofence: ${e.toString()}'};
    }
  }

  Future<Map<String, dynamic>> lockGeofence({
    required String instituteId,
    required String adminId,
  }) async {
    try {
      final currentUser = _db.auth.currentUser;
      if (currentUser == null) {
        return {'success': false, 'message': 'User not authenticated'};
      }

      await _db.from('gps_settings').update({
        'is_locked': true,
        'locked_at': DateTime.now().toUtc().toIso8601String(),
        'locked_by': currentUser.id,
      }).eq('institute_id', instituteId).eq('admin_id', adminId);

      return {'success': true, 'message': 'Geofence locked successfully'};
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error locking geofence: $e');
      return {'success': false, 'message': 'Error locking geofence: ${e.toString()}'};
    }
  }

  Future<Map<String, dynamic>?> getGeofenceDetails({
    required String instituteId,
    required String adminId,
  }) async {
    try {
      final row = await _db
          .from('gps_settings')
          .select()
          .eq('institute_id', instituteId)
          .eq('admin_id', adminId)
          .maybeSingle();
      if (row == null) return null;
      return {
        'isLocked': row['is_locked'],
        'latitude': row['latitude'],
        'longitude': row['longitude'],
        'radius': row['radius'],
      };
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error getting geofence details: $e');
      return null;
    }
  }

  Future<bool> isGeofenceLocked({
    required String instituteId,
    required String adminId,
  }) async {
    try {
      final details = await getGeofenceDetails(
        instituteId: instituteId,
        adminId: adminId,
      );
      return details?['isLocked'] == true;
    } catch (e) {
      return false;
    }
  }

  Future<Map<String, dynamic>> checkAdminLocationStatus({
    required String instituteId,
    required String adminId,
  }) async {
    try {
      final details = await getGeofenceDetails(
        instituteId: instituteId,
        adminId: adminId,
      );

      if (details == null) {
        return {
          'isLocked': false,
          'hasLocation': false,
          'isWithinRadius': null,
          'distance': null,
          'message': 'Location not configured',
        };
      }

      final isLocked = details['isLocked'] == true;
      final latitude = (details['latitude'] as num?)?.toDouble();
      final longitude = (details['longitude'] as num?)?.toDouble();

      const double radius = 30.0;

      final hasLocation = latitude != null &&
          longitude != null &&
          latitude != 0.0 &&
          longitude != 0.0;

      if (!hasLocation) {
        return {
          'isLocked': false,
          'hasLocation': false,
          'isWithinRadius': null,
          'distance': null,
          'message': 'Location not set',
        };
      }

      try {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
          ),
        );

        if (position.isMocked) {
          return {
            'isLocked': isLocked,
            'hasLocation': true,
            'isWithinRadius': false,
            'distance': null,
            'message': isLocked ? 'Location locked - Fake GPS detected' : 'Location unlocked - Fake GPS detected',
          };
        }

        final distance = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          latitude!,
          longitude!,
        );

        final gpsAccuracy = position.accuracy;
        final effectiveRadius = radius + (gpsAccuracy > 0 ? gpsAccuracy : 0);
        final isWithinRadius = distance <= effectiveRadius;

        return {
          'isLocked': isLocked,
          'hasLocation': true,
          'isWithinRadius': isWithinRadius,
          'distance': distance,
          'message': isWithinRadius ? 'Within radius' : 'Outside radius',
        };
      } catch (e) {
        if (kDebugMode) debugPrint('⚠️ Error checking current location: $e');
        return {
          'isLocked': isLocked,
          'hasLocation': true,
          'isWithinRadius': null,
          'distance': null,
          'message': 'Unable to verify current location',
        };
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error checking admin location status: $e');
      return {
        'isLocked': false,
        'hasLocation': false,
        'isWithinRadius': null,
        'distance': null,
        'message': 'Error checking location status',
      };
    }
  }

  Future<Map<String, dynamic>> migrateRadiusTo30Meters() async {
    try {
      int updatedCount = 0;
      final institutes = await _db.from('institutes').select('id');
      for (final inst in institutes) {
        final iid = inst['id'] as String;
        final gpsRows = await _db.from('gps_settings').select().eq('institute_id', iid);
        for (final g in gpsRows) {
          final r = (g['radius'] as num?)?.toDouble() ?? 0.0;
          if (r >= 24.9 && r <= 25.1) {
            await _db
                .from('gps_settings')
                .update({'radius': 30.0, 'extra': {'radiusMigratedFrom': 25.0}})
                .eq('institute_id', iid)
                .eq('admin_id', g['admin_id']);
            updatedCount++;
          }
        }
        final gf = await _db.from('institute_geofence').select().eq('institute_id', iid).maybeSingle();
        if (gf != null) {
          final data = gf['data'];
          final r = data is Map && data['radius'] != null ? (data['radius'] as num).toDouble() : (gf['radius'] as num?)?.toDouble() ?? 0;
          if (r >= 24.9 && r <= 25.1) {
            await _db.from('institute_geofence').update({'radius': 30.0}).eq('institute_id', iid);
            updatedCount++;
          }
        }
      }

      final global = await _db.from('system_settings').select().eq('key', 'gps_config').maybeSingle();
      if (global != null) {
        final val = global['value'];
        if (val is Map && val['radius'] != null) {
          final r = (val['radius'] as num).toDouble();
          if (r >= 24.9 && r <= 25.1) {
            await _db.from('system_settings').upsert({
              'key': 'gps_config',
              'value': {...val, 'radius': 30.0},
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            });
            updatedCount++;
          }
        }
      }

      return {
        'success': true,
        'updatedCount': updatedCount,
        'errorCount': 0,
        'message': 'Migration completed: Updated $updatedCount settings to 30 meters.',
        'errors': <String>[],
      };
    } catch (e) {
      return {
        'success': false,
        'updatedCount': 0,
        'errorCount': 0,
        'message': 'Error during migration: ${e.toString()}',
        'errors': [e.toString()],
      };
    }
  }
}
