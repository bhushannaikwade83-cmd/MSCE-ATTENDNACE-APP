import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_db.dart';

/// Institute daily status in `institute_daily_status` (payload + date_key).
/// Rows with [kInstituteStatusStudentId] hold institute-wide open/close/holiday.
class InstituteStatusService {
  static const String kInstituteStatusStudentId = '__institute__';

  SupabaseClient get _db => appDb;

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
      return await _rowPayload(instituteId, today);
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
      await _upsertStatus(instituteId, today, {
        ...?prev,
        'status': 'open',
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
      await _upsertStatus(instituteId, today, {
        ...?prev,
        'status': 'holiday',
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

  /// Batch / institute timing from `institutes.batch_open_time` / `batch_close_time` (jsonb).
  Future<Map<String, dynamic>?> getInstituteTiming(String instituteId) async {
    try {
      final row = await _db
          .from('institutes')
          .select('batch_open_time, batch_close_time')
          .eq('id', instituteId)
          .maybeSingle();

      if (row == null) return null;

      final openTime = row['batch_open_time'];
      final closeTime = row['batch_close_time'];

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
}
