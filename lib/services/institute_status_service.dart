import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_db.dart';
import '../core/attendance_presence_rules.dart';
import 'security_ops_service.dart';

/// Institute daily status in `institute_daily_status` (payload + date_key).
/// Rows with [kInstituteStatusStudentId] hold institute-wide open/close/holiday.
class InstituteStatusService {
  static const String kInstituteStatusStudentId = '__institute__';

  SupabaseClient get _db => appDb;
  final SecurityOpsService _securityOps = SecurityOpsService();

  Future<Map<String, dynamic>?> _rowPayload(String instituteId, String today) async {
    final row = await _db
        .from('institute_daily_status')
        .select()
        .eq('institute_id', instituteId)
        .eq('student_id', kInstituteStatusStudentId)
        .eq('date_key', today)
        .maybeSingle();
    if (row == null) return null;
    final payload = row['payload'];
    if (payload is Map<String, dynamic>) return Map<String, dynamic>.from(payload);
    if (payload is Map) return payload.map((k, v) => MapEntry(k.toString(), v));
    return null;
  }

  /// Get today's institute status (merged with top-level row fields).
  Future<Map<String, dynamic>?> getTodayStatus(String instituteId) async {
    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final payload = await _rowPayload(instituteId, today);
      // New day default: closed until admin explicitly chooses Open or Holiday.
      return payload ??
          <String, dynamic>{
            'status': 'closed',
            'date': today,
            'autoDefaultClosed': true,
            'dayDecisionLocked': false,
          };
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error getting today status: $e');
      return null;
    }
  }

  Future<void> _upsertStatus(String instituteId, String today, Map<String, dynamic> payload) async {
    await _db.from('institute_daily_status').upsert(
      {
        'institute_id': instituteId,
        'student_id': kInstituteStatusStudentId,
        'date_key': today,
        'payload': payload,
      },
      onConflict: 'institute_id,student_id,date_key',
    );
  }

  /// Mark institute as open for today
  Future<Map<String, dynamic>> markOpen(String instituteId) async {
    try {
      final user = _db.auth.currentUser;
      if (user == null) {
        return {'success': false, 'message': 'User not authenticated'};
      }

      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final now = DateTime.now().toUtc().toIso8601String();

      final prev = await _rowPayload(instituteId, today);
      final currentStatus = prev?['status']?.toString();
      final isDecisionLocked = prev?['dayDecisionLocked'] == true;
      if (isDecisionLocked || currentStatus == 'open' || currentStatus == 'holiday') {
        return {
          'success': false,
          'message': 'Today\'s status is already finalized. Open/Holiday cannot be changed now.'
        };
      }
      await _upsertStatus(instituteId, today, {
        ...?prev,
        'status': 'open',
        'dayDecisionLocked': true,
        'dayDecisionType': 'open',
        'dayDecisionAt': now,
        'openedAt': now,
        'openedBy': user.id,
        'date': today,
        'updatedAt': now,
      });

      if (kDebugMode) debugPrint('✅ Institute marked as open for $today');

      return {'success': true, 'message': 'Institute marked as open'};
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error marking institute as open: $e');
      return {'success': false, 'message': 'Error: ${e.toString()}'};
    }
  }

  /// Mark institute as closed for today
  Future<Map<String, dynamic>> markClosed(String instituteId) async {
    try {
      final user = _db.auth.currentUser;
      if (user == null) {
        return {'success': false, 'message': 'User not authenticated'};
      }

      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final now = DateTime.now().toUtc().toIso8601String();

      final currentStatus = await getTodayStatus(instituteId);
      final wasOpen = currentStatus?['status'] == 'open';

      final prev = await _rowPayload(instituteId, today);
      await _upsertStatus(instituteId, today, {
        ...?prev,
        'status': 'closed',
        'closedAt': now,
        'closedBy': user.id,
        'dayFinalized': true,
        'date': today,
        'wasOpen': wasOpen,
        'updatedAt': now,
      });

      if (kDebugMode) debugPrint('✅ Institute marked as closed for $today');

      return {'success': true, 'message': 'Institute marked as closed'};
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error marking institute as closed: $e');
      return {'success': false, 'message': 'Error: ${e.toString()}'};
    }
  }

  /// Mark today as holiday
  Future<Map<String, dynamic>> markHoliday(String instituteId, {String? reason}) async {
    try {
      final user = _db.auth.currentUser;
      if (user == null) {
        return {'success': false, 'message': 'User not authenticated'};
      }

      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final now = DateTime.now().toUtc().toIso8601String();

      final prev = await _rowPayload(instituteId, today);
      final currentStatus = prev?['status']?.toString();
      final isDecisionLocked = prev?['dayDecisionLocked'] == true;
      if (isDecisionLocked || currentStatus == 'open' || currentStatus == 'holiday') {
        return {
          'success': false,
          'message': 'Today\'s status is already finalized. Open/Holiday cannot be changed now.'
        };
      }
      await _upsertStatus(instituteId, today, {
        ...?prev,
        'status': 'holiday',
        'dayDecisionLocked': true,
        'dayDecisionType': 'holiday',
        'dayDecisionAt': now,
        'markedAt': now,
        'markedBy': user.id,
        'date': today,
        'reason': reason ?? 'Holiday',
        'updatedAt': now,
      });

      if (kDebugMode) debugPrint('✅ Institute marked as holiday for $today');

      return {'success': true, 'message': 'Institute marked as holiday'};
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error marking institute as holiday: $e');
      return {'success': false, 'message': 'Error: ${e.toString()}'};
    }
  }

  /// Auto-close institute if not manually closed
  Future<Map<String, dynamic>> autoClose(String instituteId) async {
    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final now = DateTime.now().toUtc().toIso8601String();

      final currentStatus = await getTodayStatus(instituteId);
      if (currentStatus != null) {
        final status = currentStatus['status'] as String?;
        if (status == 'closed' || status == 'holiday') {
          return {'success': true, 'message': 'Already closed or holiday'};
        }
      }

      final prev = await _rowPayload(instituteId, today);
      await _upsertStatus(instituteId, today, {
        ...?prev,
        'status': 'closed',
        'closedAt': now,
        'closedBy': 'system',
        'dayFinalized': true,
        'autoClosed': true,
        'date': today,
        'updatedAt': now,
      });

      if (kDebugMode) debugPrint('✅ Institute auto-closed for $today');

      return {'success': true, 'message': 'Institute auto-closed'};
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error auto-closing institute: $e');
      return {'success': false, 'message': 'Error: ${e.toString()}'};
    }
  }

  Future<bool> isHoliday(String instituteId) async {
    try {
      final status = await getTodayStatus(instituteId);
      return status?['status'] == 'holiday';
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error checking holiday status: $e');
      return false;
    }
  }

  Future<bool> isOpen(String instituteId) async {
    try {
      final status = await getTodayStatus(instituteId);
      return status?['status'] == 'open';
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error checking open status: $e');
      return false;
    }
  }

  Future<String?> attendanceBlockMessage(String instituteId) async {
    return null;
  }

  /// Mark students **absent** only when they have **no entry on any subject** today.
  /// Entry without exit stays hours-based (handled elsewhere); not overwritten here.
  /// Called automatically when the institute is closed for the day.
  /// Returns { 'success', 'updated', 'inserted', 'total' }.
  Future<Map<String, dynamic>> markAbsentAllUnmarkedStudents(
    String instituteId, {
    String? dateKey,
  }) async {
    try {
      final today = dateKey ?? DateFormat('yyyy-MM-dd').format(DateTime.now());
      final now = DateTime.now().toUtc().toIso8601String();

      // All students in the institute
      final students = await _db
          .from('students')
          .select('user_id, sr_no, created_at')
          .eq('institute_id', instituteId);

      // Today's existing attendance rows
      final attendanceRows = await _db
          .from('teacher_attendance')
          .select()
          .eq('institute_id', instituteId)
          .eq('date', today);

      // student_id → {row, payload}
      final attendanceMap = <String, Map<String, dynamic>>{};
      for (final row in attendanceRows) {
        final sid = row['student_id'] as String?;
        if (sid == null) continue;
        final data = row['payload'];
        final Map<String, dynamic> payload;
        if (data is Map<String, dynamic>) {
          payload = Map<String, dynamic>.from(data);
        } else if (data is Map) {
          payload = data.map((k, v) => MapEntry(k.toString(), v));
        } else {
          payload = {};
        }
        attendanceMap[sid] = {'row': row, 'payload': payload};
      }

      int updated = 0;
      int inserted = 0;

      for (final student in students) {
        final roll =
            (student['user_id'] as String?)?.trim() ??
            (student['sr_no'] as String?)?.trim();
        if (roll == null || roll.isEmpty) continue;

        final existing = attendanceMap[roll];

        if (existing != null) {
          final row = Map<String, dynamic>.from(existing['row'] as Map);
          final map = existing['payload'] as Map<String, dynamic>;
          final currentStatus = map['status'] as String?;

          // Already finalised → skip
          if (currentStatus == 'present' || currentStatus == 'absent') {
            continue;
          }

          if (!teacherPayloadHasAnySubjectEntry(map)) {
            map['status'] = 'absent';
            map['absentReason'] =
                'Auto-marked absent: no entry on any subject when institute closed';
            map['markedAbsentAt'] = now;
            map['autoMarkedOnInstituteClose'] = true;

            await _db.from('teacher_attendance').update({
              'payload': map,
              'status': 'absent',
              'updated_at': now,
            }).eq('id', row['id'] as String);
            updated++;
          }
        } else {
          // Do not auto-mark a newly added student absent on day 1.
          // If the student record was created today, skip absent insertion.
          final createdAtRaw = student['created_at']?.toString();
          final createdAt = createdAtRaw == null
              ? null
              : DateTime.tryParse(createdAtRaw)?.toLocal();
          if (createdAt != null) {
            final createdDate =
                DateFormat('yyyy-MM-dd').format(createdAt);
            if (createdDate == today) {
              continue;
            }
          }

          // No record at all for today → insert absent
          final docId = '${instituteId}_${roll}_$today';
          await _db.from('teacher_attendance').upsert(
            {
              'id': docId,
              'institute_id': instituteId,
              'student_id': roll,
              'date': today,
              'status': 'absent',
              'payload': {
                'status': 'absent',
                'absentReason':
                    'Auto-marked absent: no attendance recorded when institute closed',
                'markedAbsentAt': now,
                'autoMarkedOnInstituteClose': true,
                'isManual': false,
              },
              'updated_at': now,
            },
            onConflict: 'id',
          );
          inserted++;
        }
      }

      if (kDebugMode) {
        debugPrint(
            '✅ Auto-absent on close: updated=$updated, inserted=$inserted');
      }
      return {
        'success': true,
        'updated': updated,
        'inserted': inserted,
        'total': updated + inserted,
      };
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error marking absent on institute close: $e');
      }
      return {'success': false, 'message': 'Error: ${e.toString()}'};
    }
  }

  /// Institute daily open/close windows from `institutes.lecture_open_time` /
  /// `lecture_close_time` (jsonb).
  Future<Map<String, dynamic>?> getInstituteTiming(String instituteId) async {
    try {
      final row = await _db
          .from('institutes')
          .select('lecture_open_time, lecture_close_time')
          .eq('id', instituteId)
          .maybeSingle();

      if (row == null) return null;

      final openTime = row['lecture_open_time'];
      final closeTime = row['lecture_close_time'];

      if (openTime == null || closeTime == null) {
        return null;
      }

      Map<String, dynamic> asMap(dynamic v) {
        if (v is Map<String, dynamic>) return v;
        if (v is Map) return v.map((k, e) => MapEntry(k.toString(), e));
        return {};
      }

      final o = asMap(openTime);
      final c = asMap(closeTime);

      return {
        'openTime': {
          'hour': o['hour'] ?? 8,
          'minute': o['minute'] ?? 0,
        },
        'closeTime': {
          'hour': c['hour'] ?? 22,
          'minute': c['minute'] ?? 0,
        },
      };
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error getting institute timing: $e');
      return null;
    }
  }

  /// Poll-based stream of today's status payload (replaces Firestore snapshots).
  Stream<Map<String, dynamic>?> getTodayStatusStream(String instituteId) {
    late StreamController<Map<String, dynamic>?> controller;
    Timer? timer;

    Future<void> emit() async {
      final m = await getTodayStatus(instituteId);
      if (!controller.isClosed) controller.add(m);
    }

    controller = StreamController<Map<String, dynamic>?>(
      onListen: () {
        emit();
        timer = Timer.periodic(const Duration(seconds: 4), (_) => emit());
      },
      onCancel: () => timer?.cancel(),
    );
    return controller.stream;
  }

  /// Create a dual-approval request for sensitive override actions.
  /// Example actions:
  /// - `reopen_finalized_day`
  /// - `attendance_status_override`
  Future<Map<String, dynamic>> requestAdminOverride({
    required String instituteId,
    required String actionType,
    required String targetTable,
    required String targetId,
    required String reason,
  }) async {
    try {
      final result = await _db.rpc('request_admin_override', params: {
        'p_institute_id': instituteId,
        'p_action_type': actionType,
        'p_target_table': targetTable,
        'p_target_id': targetId,
        'p_reason': reason,
      });
      return {
        'success': true,
        'requestId': result?.toString(),
        'message': 'Override request submitted',
      };
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error creating admin override request: $e');
      }
      return {'success': false, 'message': 'Error: ${e.toString()}'};
    }
  }

  /// Approve a dual-approval request (requires MFA AAL2 session on backend).
  Future<Map<String, dynamic>> approveAdminOverride({
    required String requestId,
    String? note,
  }) async {
    try {
      final result = await _db.rpc('approve_admin_override', params: {
        'p_request_id': requestId,
        'p_note': note,
      });
      if (result is Map<String, dynamic>) {
        await _securityOps.reportIncident(
          instituteId: (result['institute_id'] ?? '').toString(),
          category: 'admin_override_approved',
          severity: 'high',
          title: 'Sensitive admin override approved',
          description: 'Dual-approval override has been approved.',
          metadata: result,
        );
        return {'success': true, ...result};
      }
      if (result is Map) {
        final mapped = result.map((k, v) => MapEntry(k.toString(), v));
        await _securityOps.reportIncident(
          instituteId: (mapped['institute_id'] ?? '').toString(),
          category: 'admin_override_approved',
          severity: 'high',
          title: 'Sensitive admin override approved',
          description: 'Dual-approval override has been approved.',
          metadata: mapped,
        );
        return {
          'success': true,
          ...mapped,
        };
      }
      return {'success': true, 'message': 'Approval processed'};
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error approving admin override request: $e');
      }
      return {'success': false, 'message': 'Error: ${e.toString()}'};
    }
  }

  /// List pending override requests for the institute (newest first).
  Future<List<Map<String, dynamic>>> getPendingOverrideRequests(
      String instituteId) async {
    try {
      final rows = await _db
          .from('admin_override_requests')
          .select()
          .eq('institute_id', instituteId)
          .eq('status', 'pending')
          .order('created_at', ascending: false);
      return (rows as List)
          .map((e) => (e as Map).map((k, v) => MapEntry(k.toString(), v)))
          .toList();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error loading pending override requests: $e');
      }
      return [];
    }
  }
}
