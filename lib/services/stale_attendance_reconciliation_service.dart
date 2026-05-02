import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_db.dart';
import '../core/attendance_auto_close_policy.dart';
import '../core/supabase_maps.dart';
import 'hierarchical_attendance_service.dart';

/// Closes teacher_attendance sessions that passed [kAttendanceExitDeadlineHours] without exit,
/// credits [kMissingExitCreditedHours], writes `attendance_in_out` exit rows for reporting,
/// and flags rows with `autoClosedMissingExit` (subject labels are display-only).
class StaleAttendanceReconciliationService {
  StaleAttendanceReconciliationService._();

  static String teacherDocId(String instituteId, String roll, String date) =>
      '${instituteId}_${roll}_$date';

  static Future<Map<String, dynamic>?> _fetchPayload(
    SupabaseClient db,
    String instituteId,
    String roll,
    String date,
  ) async {
    final row = await db
        .from('teacher_attendance')
        .select()
        .eq('id', teacherDocId(instituteId, roll, date))
        .maybeSingle();
    if (row == null) return null;
    final p = row['payload'];
    if (p is Map<String, dynamic>) return Map<String, dynamic>.from(p);
    if (p is Map) return p.map((k, v) => MapEntry(k.toString(), v));
    return <String, dynamic>{};
  }

  static Future<void> _upsertTeacherPayload(
    SupabaseClient db,
    String instituteId,
    String roll,
    String date,
    Map<String, dynamic> payload,
  ) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await db.from('teacher_attendance').upsert(
      {
        'id': teacherDocId(instituteId, roll, date),
        'institute_id': instituteId,
        'student_id': roll,
        'date': date,
        'status': payload['status']?.toString(),
        'payload': payload,
        'updated_at': now,
      },
      onConflict: 'id',
    );
  }

  static Future<void> _syncAutoClosedExit({
    required String instituteId,
    required String roll,
    required String date,
    required AutoCloseSyncHint hint,
  }) async {
    try {
      final key = roll.trim();
      var row = await appDb
          .from('students')
          .select('id,name,user_id,sr_no')
          .eq('institute_id', instituteId)
          .eq('user_id', key)
          .maybeSingle();
      row ??= await appDb
          .from('students')
          .select('id,name,user_id,sr_no')
          .eq('institute_id', instituteId)
          .eq('sr_no', key)
          .maybeSingle();
      if (row == null) {
        if (kDebugMode) {
          debugPrint('⚠️ auto-close sync: no student row for roll $roll');
        }
        return;
      }
      final sid = row['id'] as String;
      final name = row['name'] as String? ?? '';
      final srNo = row['sr_no']?.toString() ?? roll;

      final code = await instituteCodeForId(instituteId);

      final existing = await appDb
          .from('attendance_in_out')
          .select('additional,type')
          .eq('institute_code', code)
          .eq('student_id', sid)
          .eq('attendance_date', date)
          .eq('type', 'exit');

      for (final raw in existing) {
        final add = raw['additional'];
        if (add is! Map) continue;
        final am = Map<String, dynamic>.from(add.cast<String, dynamic>());
        if (am['autoClosedMissingExit'] == true &&
            (am['subject']?.toString() ?? '') == hint.subjectLabel) {
          return;
        }
      }

      await HierarchicalAttendanceService().saveAttendance(
        instituteCode: instituteId,
        studentId: sid,
        studentName: name,
        srNo: srNo,
        date: date,
        type: 'exit',
        photoUrl: '',
        recordedAtUtcIso: hint.syntheticExitUtc,
        additionalData: {
          'rollNumber': roll,
          'source': 'auto_close_missing_exit',
          'subject': hint.subjectLabel,
          'entryTime': hint.sessionEntryUtc,
          'exitTime': hint.syntheticExitUtc,
          'hours': kMissingExitCreditedHours,
          'status': 'present',
          'autoClosedMissingExit': true,
          'autoClosedNote': autoClosedMissingExitNote(),
        },
      );
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ auto-close attendance_in_out sync failed: $e');
    }
  }

  /// Returns the payload to use (possibly updated after reconciliation).
  static Future<Map<String, dynamic>?> ensureReconciled({
    required SupabaseClient db,
    required String instituteId,
    required String roll,
    required String date,
    required List<String> enrolledSubjects,
    Map<String, dynamic>? existingPayload,
  }) async {
    if (enrolledSubjects.isEmpty) return existingPayload;

    var payload = existingPayload ?? await _fetchPayload(db, instituteId, roll, date);
    if (payload == null || payload.isEmpty) return existingPayload ?? payload;

    final applied = applyMissingExitAutoClose(
      payload: payload,
      enrolledSubjects: enrolledSubjects,
      nowUtc: DateTime.now().toUtc(),
    );

    if (!applied.changed) {
      return payload;
    }

    await _upsertTeacherPayload(db, instituteId, roll, date, applied.payload);

    for (final h in applied.syncHints) {
      await _syncAutoClosedExit(instituteId: instituteId, roll: roll, date: date, hint: h);
    }

    return applied.payload;
  }
}
