import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_db.dart';
import '../core/supabase_maps.dart';

class InstituteSyncEvent {
  final String instituteId;
  final String type;

  const InstituteSyncEvent({
    required this.instituteId,
    required this.type,
  });
}

class InstituteRealtimeSyncService {
  InstituteRealtimeSyncService._();

  static final InstituteRealtimeSyncService instance =
      InstituteRealtimeSyncService._();

  final StreamController<InstituteSyncEvent> _controller =
      StreamController<InstituteSyncEvent>.broadcast();
  final Map<String, int> _refCounts = <String, int>{};
  final Map<String, List<RealtimeChannel>> _channelsByInstitute =
      <String, List<RealtimeChannel>>{};

  Stream<InstituteSyncEvent> watch(String instituteId) =>
      _controller.stream.where((event) => event.instituteId == instituteId);

  Future<void> retain(String instituteId) async {
    final id = instituteId.trim();
    if (id.isEmpty) return;

    final nextCount = (_refCounts[id] ?? 0) + 1;
    _refCounts[id] = nextCount;
    if (nextCount > 1) return;

    final instituteCode = await instituteCodeForId(id);
    final channels = <RealtimeChannel>[];

    RealtimeChannel buildInstituteChannel({
      required String name,
      required String table,
      required String column,
      required String value,
      required String eventType,
    }) {
      return appDb
          .channel(name)
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: table,
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: column,
              value: value,
            ),
            callback: (_) {
              if (kDebugMode) {
                debugPrint('🔄 Realtime sync: $eventType for institute $id');
              }
              _controller.add(
                InstituteSyncEvent(instituteId: id, type: eventType),
              );
            },
          )
          .subscribe();
    }

    channels.add(
      buildInstituteChannel(
        name: 'sync-students-$id',
        table: 'students',
        column: 'institute_id',
        value: id,
        eventType: 'students',
      ),
    );
    channels.add(
      buildInstituteChannel(
        name: 'sync-subjects-$id',
        table: 'institute_subjects',
        column: 'institute_id',
        value: id,
        eventType: 'subjects',
      ),
    );
    channels.add(
      buildInstituteChannel(
        name: 'sync-gps-$id',
        table: 'gps_settings',
        column: 'institute_id',
        value: id,
        eventType: 'gps',
      ),
    );
    channels.add(
      buildInstituteChannel(
        name: 'sync-geofence-$id',
        table: 'institute_geofence',
        column: 'institute_id',
        value: id,
        eventType: 'gps',
      ),
    );
    channels.add(
      buildInstituteChannel(
        name: 'sync-institutes-$id',
        table: 'institutes',
        column: 'id',
        value: id,
        eventType: 'institute',
      ),
    );
    channels.add(
      buildInstituteChannel(
        name: 'sync-teacher-att-$id',
        table: 'teacher_attendance',
        column: 'institute_id',
        value: id,
        eventType: 'attendance',
      ),
    );

    if (instituteCode.isNotEmpty) {
      channels.add(
        buildInstituteChannel(
          name: 'sync-attendance-io-$instituteCode',
          table: 'attendance_in_out',
          column: 'institute_code',
          value: instituteCode,
          eventType: 'attendance',
        ),
      );
    }

    _channelsByInstitute[id] = channels;
  }

  Future<void> release(String instituteId) async {
    final id = instituteId.trim();
    if (id.isEmpty) return;

    final current = _refCounts[id];
    if (current == null) return;

    if (current > 1) {
      _refCounts[id] = current - 1;
      return;
    }

    _refCounts.remove(id);
    final channels = _channelsByInstitute.remove(id) ?? <RealtimeChannel>[];
    for (final channel in channels) {
      await appDb.removeChannel(channel);
    }
  }
}
