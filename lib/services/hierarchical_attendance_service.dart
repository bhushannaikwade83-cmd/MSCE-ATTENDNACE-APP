import 'dart:async';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_db.dart';
import 'semester_service.dart';

/// Attendance stored in `attendance_in_out` (Supabase). B2 holds photo files; URLs stored here.
class HierarchicalAttendanceService {
  final SupabaseClient _db = appDb;
  final SemesterService _semesterService = SemesterService();

  Future<String> _instituteCode(String instituteCode) async {
    if (instituteCode.isEmpty) return instituteCode;
    final row = await _db.from('institutes').select('institute_code').eq('id', instituteCode).maybeSingle();
    if (row != null && (row['institute_code'] as String?)?.isNotEmpty == true) {
      return row['institute_code'] as String;
    }
    return instituteCode;
  }

  Future<Map<String, dynamic>> saveAttendance({
    required String instituteCode,
    required String studentId,
    required String studentName,
    required String srNo,
    required String date,
    required String type,
    required String photoUrl,
    String? photoPath,
    Map<String, dynamic>? additionalData,
  }) async {
    try {
      final dateTime = DateTime.parse(date);
      final year = dateTime.year;
      final semester = _semesterService.getCurrentSemester();
      final semesterCode = _semesterService.getSemesterCode(semester, year);
      final code = await _instituteCode(instituteCode);
      final timestamp = DateTime.now();
      final timestampStr = DateFormat('yyyyMMddHHmmss').format(timestamp);
      final uniqueDocId = '${type}_$timestampStr';

      final payload = <String, dynamic>{
        'institute_code': code,
        'student_id': studentId,
        'student_name': studentName,
        'sr_no': srNo,
        'year': year,
        'semester_code': semesterCode,
        'attendance_date': date,
        'type': type,
        'photo_url': photoUrl,
        if (photoPath != null) 'photo_path': photoPath,
        'unique_id': uniqueDocId,
        'additional': additionalData ?? {},
        'created_at': DateTime.now().toUtc().toIso8601String(),
      };

      await _db.from('attendance_in_out').insert(payload);

      return {'success': true, 'message': 'Attendance saved successfully', 'path': uniqueDocId};
    } catch (e) {
      if (kDebugMode) debugPrint('saveAttendance: $e');
      rethrow;
    }
  }

  Map<String, dynamic> _rowToEntry(Map<String, dynamic> row) {
    return {
      'instituteCode': row['institute_code'],
      'studentId': row['student_id'],
      'studentName': row['student_name'],
      'srNo': row['sr_no'],
      'year': row['year'],
      'semesterCode': row['semester_code'],
      'date': row['attendance_date'],
      'type': row['type'],
      'photoUrl': row['photo_url'],
      'photoPath': row['photo_path'],
      'timestamp': row['created_at'],
      'createdAt': row['created_at'],
      ...?((row['additional'] as Map?)?.cast<String, dynamic>()),
    };
  }

  Stream<Map<String, dynamic>?> getAttendanceStream({
    required String instituteCode,
    required String studentId,
    required String date,
  }) {
    final controller = StreamController<Map<String, dynamic>?>.broadcast();
    Timer? timer;
    Future<void> load() async {
      final m = await getAttendance(
        instituteCode: instituteCode,
        studentId: studentId,
        date: date,
      );
      if (!controller.isClosed) controller.add(m);
    }
    load();
    timer = Timer.periodic(const Duration(seconds: 4), (_) => load());
    controller.onCancel = () {
      timer?.cancel();
    };
    return controller.stream;
  }

  Future<Map<String, dynamic>?> getAttendance({
    required String instituteCode,
    required String studentId,
    required String date,
  }) async {
    try {
      final code = await _instituteCode(instituteCode);
      final rows = await _db
          .from('attendance_in_out')
          .select()
          .eq('institute_code', code)
          .eq('student_id', studentId)
          .eq('attendance_date', date);

      if (rows.isEmpty) return null;

      final entries = <Map<String, dynamic>>[];
      final exits = <Map<String, dynamic>>[];
      for (final r in rows) {
        final data = _rowToEntry(r);
        final t = (data['type'] as String?) ?? 'entry';
        if (t == 'entry') {
          entries.add(data);
        } else if (t == 'exit') {
          exits.add(data);
        }
      }

      dynamic parseTs(dynamic a, dynamic b) {
        final x = a ?? b;
        if (x == null) return null;
        if (x is DateTime) return x;
        return DateTime.tryParse(x.toString());
      }

      entries.sort((a, b) {
        final tsA = parseTs(a['timestamp'], a['createdAt']);
        final tsB = parseTs(b['timestamp'], b['createdAt']);
        if (tsA == null && tsB == null) return 0;
        if (tsA == null) return 1;
        if (tsB == null) return -1;
        return tsB.compareTo(tsA);
      });
      exits.sort((a, b) {
        final tsA = parseTs(a['timestamp'], a['createdAt']);
        final tsB = parseTs(b['timestamp'], b['createdAt']);
        if (tsA == null && tsB == null) return 0;
        if (tsA == null) return 1;
        if (tsB == null) return -1;
        return tsB.compareTo(tsA);
      });

      final result = <String, dynamic>{};
      if (entries.isNotEmpty) result['entry'] = entries.first;
      if (exits.isNotEmpty) result['exit'] = exits.first;
      result['allEntries'] = entries;
      result['allExits'] = exits;
      return result;
    } catch (e) {
      if (kDebugMode) debugPrint('getAttendance: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getInstituteAttendance({
    required String instituteCode,
    required int year,
    required String semesterCode,
    String? date,
  }) async {
    try {
      final code = await _instituteCode(instituteCode);
      final rows = await _db
          .from('attendance_in_out')
          .select()
          .eq('institute_code', code)
          .eq('year', year)
          .eq('semester_code', semesterCode);
      final results = <Map<String, dynamic>>[];
      for (final r in rows) {
        final d = r['attendance_date']?.toString() ?? '';
        if (date != null && d != date) continue;
        results.add({
          'studentId': r['student_id'],
          'date': d,
          'type': r['type'],
          ..._rowToEntry(r),
        });
      }
      return results;
    } catch (e) {
      if (kDebugMode) debugPrint('getInstituteAttendance: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> getAttendanceSummary() async {
    try {
      final rows = await _db.from('attendance_in_out').select('year, semester_code, institute_code');
      final triples = <String>{};
      for (final r in rows) {
        final y = r['year']?.toString() ?? '';
        final sem = r['semester_code']?.toString() ?? '';
        final code = r['institute_code']?.toString() ?? '';
        if (y.isEmpty || sem.isEmpty || code.isEmpty) continue;
        triples.add('$y|$sem|$code');
      }
      final summary = <String, dynamic>{};
      for (final t in triples) {
        final parts = t.split('|');
        final y = parts[0];
        final sem = parts[1];
        final code = parts[2];
        summary.putIfAbsent(y, () => <String, dynamic>{});
        final yMap = summary[y] as Map<String, dynamic>;
        yMap.putIfAbsent(sem, () => <String, Map<String, dynamic>>{});
        final semMap = yMap[sem] as Map<String, Map<String, dynamic>>;
        if (semMap.containsKey(code)) continue;

        final instRow = await _db.from('institutes').select('id').eq('institute_code', code).maybeSingle();
        final iid = instRow?['id'] as String?;
        var totalStudents = 0;
        if (iid != null) {
          final studs = await _db.from('students').select('id').eq('institute_id', iid);
          totalStudents = studs.length;
        }
        final yearInt = int.tryParse(y) ?? 0;
        final attRows = await _db
            .from('attendance_in_out')
            .select('id')
            .eq('institute_code', code)
            .eq('semester_code', sem)
            .eq('year', yearInt);
        semMap[code] = {
          'totalStudents': totalStudents,
          'totalAttendance': attRows.length,
        };
      }
      return summary;
    } catch (e) {
      if (kDebugMode) debugPrint('getAttendanceSummary: $e');
      return {};
    }
  }
}
