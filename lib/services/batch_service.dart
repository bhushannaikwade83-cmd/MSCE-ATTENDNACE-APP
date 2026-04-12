import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_db.dart';
import 'database_init_service.dart';
import 'validation_service.dart';

class BatchService {
  SupabaseClient get _db => appDb;

  Future<Map<String, dynamic>> createBatch({
    required String instituteId,
    required String batchName,
    required String year,
    required String timing,
    required List<String> subjects,
  }) async {
    try {
      await DatabaseInitService.ensureInitialized();

      if (batchName.isEmpty) {
        return {'success': false, 'message': 'Batch name is required'};
      }
      if (year.isEmpty) {
        return {'success': false, 'message': 'Year is required'};
      }
      if (timing.isEmpty) {
        return {'success': false, 'message': 'Timing is required'};
      }
      if (subjects.isEmpty) {
        return {'success': false, 'message': 'At least one subject is required'};
      }

      batchName = ValidationService.sanitizeInput(batchName);
      year = ValidationService.sanitizeInput(year);
      timing = ValidationService.sanitizeInput(timing);

      final normalizedBatchName = ValidationService.normalizeBatchName(batchName);
      final existingBatches = await _db
          .from('batches')
          .select('name, year')
          .eq('institute_id', instituteId)
          .eq('year', year);

      for (final row in existingBatches) {
        final existingName = row['name'] as String? ?? '';
        final existingYear = row['year'] as String? ?? '';
        if (existingYear.toLowerCase() == year.toLowerCase() &&
            ValidationService.normalizeBatchName(existingName) == normalizedBatchName) {
          return {
            'success': false,
            'message': 'Batch "$existingName" already exists for year $year',
          };
        }
      }

      const createdBy = 'admin';

      await _db.from('batches').insert({
        'institute_id': instituteId,
        'name': batchName,
        'year': year,
        'timing': timing,
        'subjects': subjects,
        'created_by': createdBy,
        'student_count': 0,
      });

      return {'success': true, 'message': 'Batch created successfully'};
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error creating batch: $e');
      return {'success': false, 'message': 'Error creating batch: ${e.toString()}'};
    }
  }

  Future<Map<String, dynamic>?> getInstituteTiming(String instituteId) async {
    try {
      final row = await _db.from('institutes').select('batch_open_time, batch_close_time, batch_duration_minutes').eq('id', instituteId).maybeSingle();

      if (row == null) return null;

      final openTime = row['batch_open_time'];
      final closeTime = row['batch_close_time'];
      final duration = row['batch_duration_minutes'] ?? 60;

      if (openTime == null || closeTime == null) {
        return null;
      }

      Map<String, dynamic> asMap(dynamic v) => Map<String, dynamic>.from(v as Map);

      final o = asMap(openTime);
      final c = asMap(closeTime);

      return {
        'openTime': TimeOfDay(
          hour: (o['hour'] as num?)?.toInt() ?? 8,
          minute: (o['minute'] as num?)?.toInt() ?? 0,
        ),
        'closeTime': TimeOfDay(
          hour: (c['hour'] as num?)?.toInt() ?? 22,
          minute: (c['minute'] as num?)?.toInt() ?? 0,
        ),
        'durationMinutes': duration,
      };
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error getting institute timing: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getBatches(String instituteId) async {
    try {
      final rows = await _db.from('batches').select().eq('institute_id', instituteId).order('name');

      return rows.map((data) {
        return {
          'id': data['id'].toString(),
          'name': data['name'] ?? '',
          'year': data['year'] ?? '',
          'timing': data['timing'] ?? '',
          'subjects': List<String>.from(data['subjects'] ?? []),
          'studentCount': data['student_count'] ?? 0,
        };
      }).toList();
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error getting batches: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getBatchesByYear(String instituteId, String year) async {
    try {
      final rows =
          await _db.from('batches').select().eq('institute_id', instituteId).eq('year', year).order('name');

      return rows.map((data) {
        return {
          'id': data['id'].toString(),
          'name': data['name'] ?? '',
          'year': data['year'] ?? '',
          'timing': data['timing'] ?? '',
          'subjects': List<String>.from(data['subjects'] ?? []),
          'studentCount': data['student_count'] ?? 0,
        };
      }).toList();
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error getting batches by year: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> updateBatch({
    required String instituteId,
    required String batchId,
    String? batchName,
    String? year,
    String? timing,
    List<String>? subjects,
  }) async {
    try {
      final updateData = <String, dynamic>{};

      if (batchName != null) {
        updateData['name'] = ValidationService.sanitizeInput(batchName);
      }
      if (year != null) {
        updateData['year'] = ValidationService.sanitizeInput(year);
      }
      if (timing != null) {
        updateData['timing'] = ValidationService.sanitizeInput(timing);
      }
      if (subjects != null) {
        updateData['subjects'] = subjects;
      }

      if (updateData.isEmpty) {
        return {'success': false, 'message': 'No fields to update'};
      }

      updateData['updated_at'] = DateTime.now().toUtc().toIso8601String();

      await _db.from('batches').update(updateData).eq('institute_id', instituteId).eq('id', batchId);

      return {'success': true, 'message': 'Batch updated successfully'};
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error updating batch: $e');
      return {'success': false, 'message': 'Error updating batch: ${e.toString()}'};
    }
  }

  Future<Map<String, dynamic>> deleteBatch(String instituteId, String batchId) async {
    try {
      try {
        final batchRow =
            await _db.from('batches').select('student_count').eq('institute_id', instituteId).eq('id', batchId).maybeSingle();

        if (batchRow != null) {
          final studentCount = batchRow['student_count'] ?? 0;
          if (studentCount > 0) {
            return {
              'success': false,
              'message': 'Cannot delete batch with $studentCount students. Please remove students first.',
            };
          }
        }
      } catch (e) {
        if (kDebugMode) debugPrint('Warning: Could not check batch student count: $e');
      }

      await _db.from('batches').delete().eq('institute_id', instituteId).eq('id', batchId);

      return {'success': true, 'message': 'Batch deleted successfully'};
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error deleting batch: $e');
      return {'success': false, 'message': 'Error deleting batch: ${e.toString()}'};
    }
  }

  Future<void> incrementStudentCount(String instituteId, String batchId) async {
    try {
      final row = await _db.from('batches').select('student_count').eq('institute_id', instituteId).eq('id', batchId).maybeSingle();
      final n = (row?['student_count'] as int?) ?? 0;
      await _db.from('batches').update({'student_count': n + 1}).eq('institute_id', instituteId).eq('id', batchId);
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error incrementing student count: $e');
    }
  }

  Future<void> decrementStudentCount(String instituteId, String batchId) async {
    try {
      final row = await _db.from('batches').select('student_count').eq('institute_id', instituteId).eq('id', batchId).maybeSingle();
      final n = (row?['student_count'] as int?) ?? 0;
      await _db.from('batches').update({'student_count': (n - 1).clamp(0, 1 << 30)}).eq('institute_id', instituteId).eq('id', batchId);
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error decrementing student count: $e');
    }
  }

  Future<String> _instituteCode(String instituteId) async {
    final row = await _db.from('institutes').select('institute_code, id').eq('id', instituteId).maybeSingle();
    if (row == null) return instituteId;
    final code = row['institute_code'] as String?;
    if (code != null && code.isNotEmpty) return code;
    return instituteId;
  }

  Future<Map<String, dynamic>> getBatchStatistics(String instituteId, String batchId) async {
    try {
      final batchRow =
          await _db.from('batches').select('student_count').eq('institute_id', instituteId).eq('id', batchId).maybeSingle();

      if (batchRow == null) {
        return {'success': false, 'message': 'Batch not found'};
      }

      final studentCount = batchRow['student_count'] ?? 0;

      final studentsRows = await _db
          .from('students')
          .select('user_id')
          .eq('institute_id', instituteId)
          .eq('batch_id', batchId);

      final studentIds = studentsRows
          .map((e) => e['user_id'] as String? ?? '')
          .where((id) => id.isNotEmpty)
          .toList();

      if (studentIds.isEmpty) {
        return {
          'success': true,
          'studentCount': studentCount,
          'attendanceRate': 0.0,
          'totalAttendance': 0,
          'expectedAttendance': 0,
        };
      }

      final now = DateTime.now();
      final startOfMonth = DateTime(now.year, now.month, 1);
      final endOfMonth = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
      final code = await _instituteCode(instituteId);

      final attRows = await _db
          .from('attendance_in_out')
          .select('student_id, attendance_date')
          .eq('institute_code', code)
          .gte('attendance_date', startOfMonth.toIso8601String().split('T').first)
          .lte('attendance_date', endOfMonth.toIso8601String().split('T').first);

      final filtered = attRows.where((doc) {
        final roll = doc['student_id'] as String? ?? '';
        return studentIds.contains(roll);
      }).toList();

      final totalAttendance = filtered.length;
      final daysInMonth = endOfMonth.day;
      final expectedAttendance = studentCount * daysInMonth;
      final attendanceRate = expectedAttendance > 0 ? (totalAttendance / expectedAttendance * 100) : 0.0;

      return {
        'success': true,
        'studentCount': studentCount,
        'attendanceRate': attendanceRate.clamp(0.0, 100.0),
        'totalAttendance': totalAttendance,
        'expectedAttendance': expectedAttendance,
      };
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error getting batch statistics: $e');
      return {'success': false, 'message': 'Error calculating statistics: ${e.toString()}'};
    }
  }

  Future<Map<String, dynamic>> autoGenerateBatches({
    required String instituteId,
    required TimeOfDay openTime,
    required TimeOfDay closeTime,
    required String semester,
    required int year,
    required List<String> subjects,
    int batchDurationMinutes = 60,
  }) async {
    try {
      await DatabaseInitService.ensureInitialized();

      if (subjects.isEmpty) {
        return {'success': false, 'message': 'At least one subject is required'};
      }

      if (batchDurationMinutes != 60 && batchDurationMinutes != 120) {
        return {
          'success': false,
          'message': 'Batch duration must be either 60 or 120 minutes',
        };
      }

      final openMinutes = openTime.hour * 60 + openTime.minute;
      final closeMinutes = closeTime.hour * 60 + closeTime.minute;

      if (openMinutes >= closeMinutes) {
        return {
          'success': false,
          'message': 'Close time must be after open time',
        };
      }

      final batches = <Map<String, dynamic>>[];
      int currentMinutes = openMinutes;
      int batchNumber = 1;

      while (currentMinutes < closeMinutes) {
        final startTime = TimeOfDay(
          hour: currentMinutes ~/ 60,
          minute: currentMinutes % 60,
        );

        final endMinutes = currentMinutes + batchDurationMinutes;
        final endTime = TimeOfDay(
          hour: endMinutes ~/ 60,
          minute: endMinutes % 60,
        );

        final timingString =
            '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')} - '
            '${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}';

        final batchName = batchDurationMinutes == 120
            ? 'Batch $batchNumber ($timingString) - Late Admission'
            : 'Batch $batchNumber ($timingString)';

        batches.add({
          'name': batchName,
          'timing': timingString,
          'startTime': {'hour': startTime.hour, 'minute': startTime.minute},
          'endTime': {'hour': endTime.hour, 'minute': endTime.minute},
          'batchDurationMinutes': batchDurationMinutes,
        });

        currentMinutes += batchDurationMinutes;
        batchNumber++;
      }

      int createdCount = 0;
      for (final batchData in batches) {
        final timing = batchData['timing'] as String;
        final existing = await _db
            .from('batches')
            .select('id')
            .eq('institute_id', instituteId)
            .eq('year', year.toString())
            .eq('timing', timing)
            .maybeSingle();

        if (existing == null) {
          await _db.from('batches').insert({
            'institute_id': instituteId,
            'name': batchData['name'],
            'year': year.toString(),
            'semester': semester,
            'timing': timing,
            'start_time': batchData['startTime'],
            'end_time': batchData['endTime'],
            'batch_duration_minutes': batchData['batchDurationMinutes'] ?? 60,
            'subjects': subjects,
            'created_by': 'system',
            'student_count': 0,
            'is_auto_generated': true,
          });
          createdCount++;
        }
      }

      if (createdCount > 0) {
        await _db.from('institutes').update({
          'batch_open_time': {'hour': openTime.hour, 'minute': openTime.minute},
          'batch_close_time': {'hour': closeTime.hour, 'minute': closeTime.minute},
          'batch_duration_minutes': batchDurationMinutes,
          'batch_timing_updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', instituteId);
      }

      return {
        'success': true,
        'message': 'Batches auto-generated successfully',
        'count': createdCount,
        'totalSlots': batches.length,
      };
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error auto-generating batches: $e');
      return {
        'success': false,
        'message': 'Error auto-generating batches: ${e.toString()}',
      };
    }
  }

  Future<Map<String, dynamic>> duplicateBatch({
    required String instituteId,
    required String batchId,
    String? newBatchName,
    String? newYear,
  }) async {
    try {
      final batchRow = await _db.from('batches').select().eq('institute_id', instituteId).eq('id', batchId).maybeSingle();

      if (batchRow == null) {
        return {'success': false, 'message': 'Batch not found'};
      }

      final originalName = batchRow['name'] as String? ?? '';
      final originalYear = batchRow['year'] as String? ?? '';
      final timing = batchRow['timing'] as String? ?? '';
      final subjects = List<String>.from(batchRow['subjects'] ?? []);

      final finalBatchName = newBatchName ?? '$originalName (Copy)';
      final finalYear = newYear ?? originalYear;

      final normalizedBatchName = ValidationService.normalizeBatchName(finalBatchName);
      final existingBatches =
          await _db.from('batches').select('name, year').eq('institute_id', instituteId).eq('year', finalYear);

      for (final doc in existingBatches) {
        final existingName = doc['name'] as String? ?? '';
        final existingYear = doc['year'] as String? ?? '';
        if (existingYear.toLowerCase() == finalYear.toLowerCase() &&
            ValidationService.normalizeBatchName(existingName) == normalizedBatchName) {
          return {
            'success': false,
            'message': 'Batch "$finalBatchName" already exists for year $finalYear',
          };
        }
      }

      return await createBatch(
        instituteId: instituteId,
        batchName: finalBatchName,
        year: finalYear,
        timing: timing,
        subjects: subjects,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error duplicating batch: $e');
      return {'success': false, 'message': 'Error duplicating batch: ${e.toString()}'};
    }
  }
}
