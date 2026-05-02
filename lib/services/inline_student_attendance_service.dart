import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_db.dart';
import '../core/attendance_auto_close_policy.dart';
import '../core/student_face_embedding_utils.dart';
import '../core/gps_attendance_constants.dart';
import '../core/time_parse.dart';
import 'institute_lecture_timing_service.dart';
import 'device_fingerprint_service.dart';
import 'error_handler.dart';
import 'face_recognition_service.dart';
import 'firestore_retry_service.dart';
import 'geofence_service.dart';
import 'hierarchical_attendance_service.dart';
import 'institute_notification_service.dart';
import 'institute_status_service.dart';
import 'liveness_detection_service.dart';
import 'network_verification_service.dart';
import 'photo_verification_service.dart';
import 'gps_fence_sample.dart';
import 'stale_attendance_reconciliation_service.dart';
import 'storage_service.dart';
import 'suspicious_activity_service.dart';
import '../presentation/widgets/session_monitor.dart';

/// Same document id as [AdminAttendanceScreen] (`instituteId_roll_date`).
String _teacherAttendanceId(String instituteId, String roll, String date) =>
    '${instituteId}_${roll}_$date';

Future<Map<String, dynamic>?> _getTeacherPayload(
  SupabaseClient db,
  String instituteId,
  String roll,
  String date,
) async {
  final row = await db
      .from('teacher_attendance')
      .select()
      .eq('id', _teacherAttendanceId(instituteId, roll, date))
      .maybeSingle();
  if (row == null) return null;
  final p = row['payload'];
  if (p is Map<String, dynamic>) return Map<String, dynamic>.from(p);
  if (p is Map) return p.map((k, v) => MapEntry(k.toString(), v));
  return <String, dynamic>{};
}

Future<void> _upsertTeacherDoc(
  SupabaseClient db,
  String instituteId,
  String roll,
  String date,
  Map<String, dynamic> payload,
) async {
  final now = DateTime.now().toUtc().toIso8601String();
  await db.from('teacher_attendance').upsert(
    {
      'id': _teacherAttendanceId(instituteId, roll, date),
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

Future<void> _syncAttendanceInOut({
  required String instituteId,
  required String roll,
  required String date,
  required String type,
  required String photoUrl,
  String? photoPath,
  String? photoFileId,
  required String recordedAtUtc,
  String? subject,
  String? sessionEntryUtc,
  String? sessionExitUtc,
  double? hours,
  String? status,
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
      if (kDebugMode) debugPrint('⚠️ attendance_in_out sync: no student row for roll $roll');
      return;
    }
    final sid = row['id'] as String;
    final name = row['name'] as String? ?? '';
    final srNo = row['sr_no']?.toString() ?? roll;
    final subj = subject?.trim();
    final additionalData = <String, dynamic>{
      'rollNumber': roll,
      'source': 'student_management_quick',
      if (subj != null && subj.isNotEmpty) 'subject': subj,
      if (sessionEntryUtc != null && sessionEntryUtc.trim().isNotEmpty)
        'entryTime': sessionEntryUtc.trim(),
      if (sessionExitUtc != null && sessionExitUtc.trim().isNotEmpty)
        'exitTime': sessionExitUtc.trim(),
    };
    if (hours != null) additionalData['hours'] = hours;
    if (status != null && status.isNotEmpty) additionalData['status'] = status;

    await HierarchicalAttendanceService().saveAttendance(
      instituteCode: instituteId,
      studentId: sid,
      studentName: name,
      srNo: srNo,
      date: date,
      type: type,
      photoUrl: photoUrl,
      photoPath: photoPath,
      photoFileId: photoFileId,
      recordedAtUtcIso: recordedAtUtc,
      additionalData: additionalData,
    );
  } catch (e) {
    if (kDebugMode) debugPrint('⚠️ attendance_in_out sync failed: $e');
  }
}

dynamic _encodeSv() => DateTime.now().toUtc().toIso8601String();

DateTime? _asDateTime(dynamic v) => parseAnyTimestamp(v);

TimeOfDay? _parseTimeString(String timeStr) {
  try {
    timeStr = timeStr.trim().toUpperCase();
    final hasAmPm = timeStr.contains('AM') || timeStr.contains('PM');
    final isPM = timeStr.contains('PM');
    timeStr = timeStr.replaceAll('AM', '').replaceAll('PM', '').trim();
    final parts = timeStr.split(':');
    if (parts.length != 2) return null;
    var hour = int.parse(parts[0].trim());
    final minute = int.parse(parts[1].trim());
    if (hasAmPm) {
      if (isPM && hour != 12) {
        hour += 12;
      } else if (!isPM && hour == 12) {
        hour = 0;
      }
    }
    return TimeOfDay(hour: hour, minute: minute);
  } catch (e) {
    if (kDebugMode) debugPrint('Error parsing time string: $e');
    return null;
  }
}

List<Map<String, TimeOfDay>> _parseLectureTiming(String timing) {
  if (timing.isEmpty) return [];
  final List<Map<String, TimeOfDay>> lectures = [];
  try {
    final lectureStrings = timing.split(',');
    for (var lectureStr in lectureStrings) {
      lectureStr = lectureStr.trim();
      final parts = lectureStr.split(RegExp(r'[-–—]'));
      if (parts.length == 2) {
        final startTime = _parseTimeString(parts[0].trim());
        final endTime = _parseTimeString(parts[1].trim());
        if (startTime != null && endTime != null) {
          lectures.add({'start': startTime, 'end': endTime});
        }
      }
    }
  } catch (e) {
    if (kDebugMode) debugPrint('Error parsing lecture timing: $e');
  }
  return lectures;
}

/// Next action for today: entry, exit, lecture face scan, or already complete.
class _QuickMarkDecision {
  final String mode; // entry | exit | lecture_scan | complete
  final int? lectureIndex;

  const _QuickMarkDecision(this.mode, [this.lectureIndex]);
}

_QuickMarkDecision _decideNextMark(
  Map<String, dynamic>? data,
  String timing,
) {
  final lectureTimes = _parseLectureTiming(timing);
  if (data == null) {
    return const _QuickMarkDecision('entry');
  }
  final hasEntry = data['entryPhoto'] != null || data['photoUrl'] != null;
  final hasExit = data['exitPhoto'] != null || data['exitTime'] != null;
  final lectures = data['lectures'] as Map<String, dynamic>? ?? {};

  if (!hasEntry) {
    return const _QuickMarkDecision('entry');
  }
  if (hasEntry && !hasExit) {
    if (lectureTimes.isNotEmpty) {
      final currentTime = DateTime.now();
      final currentMinutes = currentTime.hour * 60 + currentTime.minute;
      for (int i = 0; i < lectureTimes.length; i++) {
        final lecture = lectureTimes[i];
        final start = lecture['start'] as TimeOfDay;
        final end = lecture['end'] as TimeOfDay;
        final startMinutes = start.hour * 60 + start.minute;
        final endMinutes = end.hour * 60 + end.minute;
        if (currentMinutes >= startMinutes && currentMinutes <= endMinutes) {
          final lectureKey = 'lecture_${i + 1}';
          final slot = lectures[lectureKey];
          if (slot == null || (slot is Map && slot['faceScanPhoto'] == null)) {
            return _QuickMarkDecision('lecture_scan', i);
          }
        }
      }
    }
    return const _QuickMarkDecision('exit');
  }
  return const _QuickMarkDecision('complete');
}

// ── Per-subject attendance (same shape as AdminAttendanceScreen) ─────────────

const String _kSubjectSessionsKey = 'subjectSessions';

String? _canonicalSubjectFromEnrollment(List<String> enrolled, String? raw) {
  if (raw == null) return null;
  final t = raw.trim();
  if (t.isEmpty) return null;
  for (final e in enrolled) {
    if (e.trim() == t) return e;
  }
  return null;
}

Map<String, Map<String, dynamic>> _mapSubjectSessions(Map<String, dynamic>? payload) {
  if (payload == null) return {};
  final raw = payload[_kSubjectSessionsKey];
  if (raw is! Map) return {};
  final out = <String, Map<String, dynamic>>{};
  raw.forEach((k, v) {
    if (v is Map) {
      out[k.toString()] = Map<String, dynamic>.from(v.cast<String, dynamic>());
    }
  });
  return out;
}

Map<String, dynamic> _sessionForSubject(
  Map<String, Map<String, dynamic>> sessions,
  String subject,
) {
  return Map<String, dynamic>.from(sessions[subject] ?? {});
}

bool _sessionHasEntryMap(Map<String, dynamic> s) {
  return s['entryPhoto'] != null || s['photoUrl'] != null || s['entryTime'] != null;
}

bool _sessionCompleteMap(Map<String, dynamic> s) {
  return s['exitPhoto'] != null || s['exitTime'] != null;
}

String? _pendingSubjectFromPayload(Map<String, dynamic>? payload) {
  if (payload == null) return null;
  final m = _mapSubjectSessions(payload);
  for (final e in m.entries) {
    if (_sessionHasEntryMap(e.value) && !_sessionCompleteMap(e.value)) return e.key;
  }
  return null;
}

/// Earlier subjects in enrollment must each have entry + exit before a later subject may start entry.
String? _sequentialPriorIncompleteSubject(
  List<String> enrolledOrder,
  Map<String, Map<String, dynamic>> sessions,
  String subject,
) {
  final idx = enrolledOrder.indexOf(subject);
  if (idx <= 0) return null;
  for (var j = 0; j < idx; j++) {
    final prev = enrolledOrder[j];
    final sess = _sessionForSubject(sessions, prev);
    if (!_sessionCompleteMap(sess)) return prev;
  }
  return null;
}

/// After [kAttendanceExitDeadlineHours] from entry, manual exit photo is never allowed (reconcile auto-close only).
Future<bool> _inlineAbortManualExitIfDeadlinePassed({
  required ScaffoldMessengerState messenger,
  required SupabaseClient db,
  required String instituteId,
  required String roll,
  required String today,
  required List<String> enrolledSubjects,
  required Map<String, dynamic>? payload,
  required bool useSubjects,
  required String? activeSubject,
  required String timing,
}) async {
  final nowUtc = DateTime.now().toUtc();
  DateTime? entryUtc;
  if (useSubjects && activeSubject != null) {
    final sm = _mapSubjectSessions(payload);
    final s = _sessionForSubject(sm, activeSubject);
    entryUtc = parseAnyTimestamp(s['entryTime']) ?? parseAnyTimestamp(s['timestamp']);
  } else if (payload != null) {
    entryUtc =
        parseAnyTimestamp(payload['entryTime']) ?? parseAnyTimestamp(payload['timestamp']);
  }
  if (entryUtc == null) return false;

  if (!isPastAttendanceExitDeadline(entryUtc, nowUtc)) return false;

  final repaired = await StaleAttendanceReconciliationService.ensureReconciled(
    db: db,
    instituteId: instituteId,
    roll: roll,
    date: today,
    enrolledSubjects: enrolledSubjects,
    existingPayload: payload,
  );

  final red = useSubjects && activeSubject != null
      ? _decideNextMarkSubject(repaired, activeSubject)
      : _decideNextMark(repaired, timing);

  if (red.mode != 'exit') {
    final msg = red.mode == 'complete'
        ? (useSubjects && activeSubject != null
            ? 'Exit window ended (${kAttendanceExitDeadlineHours}h). "$activeSubject" was auto-closed (no exit photo; 1 h credit).'
            : 'Exit window ended (${kAttendanceExitDeadlineHours}h). Session auto-closed (no exit photo; 1 h credit).')
        : 'Attendance was updated — try again.';
    messenger.showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 6),
      ),
    );
    return true;
  }

  messenger.showSnackBar(
    SnackBar(
      content: Text(
        'Exit not allowed: more than ${kAttendanceExitDeadlineHours}h since entry.',
      ),
      backgroundColor: Colors.orange,
      duration: const Duration(seconds: 6),
    ),
  );
  return true;
}

bool _isLegacyAttendanceDoc(Map<String, dynamic>? data) {
  if (data == null || data.isEmpty) return false;
  final ss = data[_kSubjectSessionsKey];
  if (ss is Map && ss.isNotEmpty) return false;
  final hasTop = data['entryPhoto'] != null ||
      data['entryTime'] != null ||
      data['photoUrl'] != null ||
      data['exitPhoto'] != null ||
      data['exitTime'] != null;
  return hasTop;
}

/// Legacy [teacher_attendance] rows store one entry/exit at the top level. When the student has
/// multiple subjects, [InlineStudentAttendanceService] and Admin need `subjectSessions`. Move
/// today's top-level marks into the first enrolled subject so staff can continue from Student Management
/// (they do not have the admin dashboard / Mark Attendance tab).
Map<String, dynamic> _migrateLegacyToFirstSubjectSession(
  Map<String, dynamic> legacy,
  String firstSubject,
) {
  final out = Map<String, dynamic>.from(legacy);
  final sess = <String, dynamic>{};
  const moveKeys = <String>[
    'entryPhoto',
    'entryTime',
    'entryPhotoPath',
    'entryPhotoFileId',
    'exitPhoto',
    'exitTime',
    'exitPhotoPath',
    'exitPhotoFileId',
    'photoUrl',
    'timestamp',
  ];
  for (final k in moveKeys) {
    if (out.containsKey(k)) sess[k] = out.remove(k);
  }
  if (out.containsKey('status')) sess['status'] = out.remove('status');
  if (sess.isNotEmpty) {
    sess['subjectName'] = firstSubject;
    out[_kSubjectSessionsKey] = {firstSubject: sess};
  }
  return out;
}

bool _allSubjectsCompleteInPayload(Map<String, dynamic>? payload, List<String> subjects) {
  if (subjects.isEmpty) return false;
  final m = _mapSubjectSessions(payload);
  for (final s in subjects) {
    if (!_sessionCompleteMap(_sessionForSubject(m, s))) return false;
  }
  return true;
}

_QuickMarkDecision _decideNextMarkSubject(
  Map<String, dynamic>? data,
  String subject,
) {
  final sessions = _mapSubjectSessions(data);
  final sess = _sessionForSubject(sessions, subject);
  final hasEntry = _sessionHasEntryMap(sess);
  final hasExit = _sessionCompleteMap(sess);
  if (!hasEntry) return const _QuickMarkDecision('entry');
  if (hasEntry && !hasExit) return const _QuickMarkDecision('exit');
  return const _QuickMarkDecision('complete');
}

Future<String?> _pickAttendanceSubjectSheet(
  BuildContext context,
  List<String> subjects,
  Map<String, dynamic>? existingPayload,
) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      final bottom = MediaQuery.viewPaddingOf(ctx).bottom;
      return SafeArea(
        child: Padding(
          padding: EdgeInsets.only(bottom: bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Select subject',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'Strict flow: finish exit for any in-progress session first, then subjects in list order '
                  '(full entry + exit each). ✓ = fully done.',
                  style: TextStyle(fontSize: 13, color: Colors.black54),
                ),
              ),
              const SizedBox(height: 8),
              ...subjects.map((sub) {
                final sessions = _mapSubjectSessions(existingPayload);
                final sess = _sessionForSubject(sessions, sub);
                final done = _sessionCompleteMap(sess);
                final started = _sessionHasEntryMap(sess);
                final pending = _pendingSubjectFromPayload(existingPayload);
                final locked = pending != null && pending != sub;
                final seqPrior =
                    _sequentialPriorIncompleteSubject(subjects, sessions, sub);
                final blockedByOrder =
                    seqPrior != null && !started && !done;
                final cannotPick = done || locked || blockedByOrder;
                return ListTile(
                  leading: Icon(
                    done ? Icons.check_circle : Icons.book_outlined,
                    color: done ? Colors.green : Colors.blueGrey,
                  ),
                  title: Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    done
                        ? 'Complete today'
                        : (locked
                            ? 'Finish "$pending" exit first'
                            : (blockedByOrder
                                ? 'Finish "$seqPrior" (entry + exit) first'
                                : (started
                                    ? 'Exit photo needed'
                                    : 'Entry photo first'))),
                  ),
                  enabled: !cannotPick,
                  onTap: cannotPick
                      ? null
                      : () => Navigator.pop(ctx, sub),
                );
              }),
            ],
          ),
        ),
      );
    },
  );
}

Future<Uint8List> _compressImage(Uint8List imageBytes, {required int maxSizeKB}) async {
  try {
    final maxSizeBytes = maxSizeKB * 1024;
    var decodedImage = img.decodeImage(imageBytes);
    if (decodedImage == null) return imageBytes;
    int quality = 85;
    Uint8List compressedBytes = imageBytes;
    if (imageBytes.length > maxSizeBytes * 2) {
      const scale = 0.7;
      final newWidth = (decodedImage.width * scale).round();
      final newHeight = (decodedImage.height * scale).round();
      decodedImage = img.copyResize(decodedImage, width: newWidth, height: newHeight);
    }
    while (compressedBytes.length > maxSizeBytes && quality > 20) {
      compressedBytes = Uint8List.fromList(img.encodeJpg(decodedImage, quality: quality));
      quality -= 10;
    }
    if (compressedBytes.length > maxSizeBytes) {
      const scale = 0.5;
      final newWidth = (decodedImage.width * scale).round();
      final newHeight = (decodedImage.height * scale).round();
      decodedImage = img.copyResize(decodedImage, width: newWidth, height: newHeight);
      compressedBytes = Uint8List.fromList(img.encodeJpg(decodedImage, quality: 60));
    }
    return compressedBytes;
  } catch (e) {
    if (kDebugMode) debugPrint('❌ Error compressing image: $e');
    return imageBytes;
  }
}

/// [gps_settings] rows are keyed by institute admin. Attendance staff uses that same fence.
Future<String?> _gpsFenceAdminIdForInline(SupabaseClient db, String instituteId) async {
  final uid = db.auth.currentUser?.id;
  if (uid == null) return null;
  try {
    final me = await db.from('profiles').select('role').eq('id', uid).maybeSingle();
    if ((me?['role'] as String?) != 'attendance_user') return uid;

    final fenceAdmin = await GeofenceService().lockedFenceAdminIdForInstitute(instituteId);
    if (fenceAdmin != null && fenceAdmin.isNotEmpty) return fenceAdmin;

    final adminRow = await db
        .from('profiles')
        .select('id')
        .eq('institute_id', instituteId)
        .eq('role', 'admin')
        .limit(1)
        .maybeSingle();
    return (adminRow?['id'] as String?) ?? uid;
  } catch (_) {
    return uid;
  }
}

Future<bool> _checkGPSRadius(BuildContext context, String instituteId) async {
  if (kIsWeb) return true;
  final db = appDb;
  final currentUser = db.auth.currentUser;
  if (currentUser == null) return false;
  try {
    final fenceAdminId = await _gpsFenceAdminIdForInline(db, instituteId);
    if (fenceAdminId == null) return false;
    final configRow = await db
        .from('gps_settings')
        .select()
        .eq('institute_id', instituteId)
        .eq('admin_id', fenceAdminId)
        .maybeSingle();

    if (configRow == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Location not verified. Please go to GPS Settings and verify your location first.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
          ),
        );
      }
      return false;
    }

    final latitude = (configRow['latitude'] as num?)?.toDouble();
    final longitude = (configRow['longitude'] as num?)?.toDouble();
    final isLocked = configRow['is_locked'] == true;
    final double radius = kAttendanceFenceRadiusMeters;

    if (latitude == null || longitude == null || latitude == 0.0 || longitude == 0.0) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Location not verified. Please go to GPS Settings and verify your location first.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
          ),
        );
      }
      return false;
    }

    if (!isLocked) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Location not locked. Please verify location in GPS Settings first.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 5),
          ),
        );
      }
      return false;
    }

    final sample = await samplePositionAgainstFence(
      fenceLat: latitude,
      fenceLng: longitude,
      radiusMeters: radius,
    );

    if (sample.mockedDetected) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Fake GPS detected. Please turn off Mock Location apps.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }

    if (sample.errorMessage != null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(sample.errorMessage!),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 8),
          ),
        );
      }
      return false;
    }

    if (!sample.isWithinFence) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '❌ Out of radius: closest ~${sample.bestDistanceMeters.toStringAsFixed(0)}m after several GPS readings. '
              'Try near a window or re-verify the lock in GPS Settings.',
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 10),
          ),
        );
      }
      return false;
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Location check failed: ${ErrorHandler.handleError(e, context: 'gps_radius_inline')}',
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
    return false;
  }
}

/// Mark attendance from Student Management: opens camera only (entry / exit / lecture scan as needed).
class InlineStudentAttendanceService {
  InlineStudentAttendanceService._();

  static Future<void> markForRoll(
    BuildContext context, {
    required String instituteId,
    required String rollNumber,
    String? chosenSubject,
    String? explicitStep,
  }) async {
    final roll = rollNumber.trim();
    if (roll.isEmpty) return;
    if (!context.mounted) return;

    final db = appDb;
    final messenger = ScaffoldMessenger.of(context);

    try {
      final blockMessage =
          await InstituteStatusService().attendanceBlockMessage(instituteId);
      if (blockMessage != null) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(blockMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
        return;
      }

      final gpsOk = await GeofenceService().hasValidPersonalGpsForCurrentAdmin();
      if (!gpsOk) {
        String msg =
            'Lock your attendance zone in GPS Settings before marking attendance.';
        final uid = db.auth.currentUser?.id;
        if (uid != null) {
          try {
            final prof =
                await db.from('profiles').select('role').eq('id', uid).maybeSingle();
            if ((prof?['role'] as String?) == 'attendance_user') {
              msg =
                  'Your institute has not locked a GPS attendance zone yet. Ask your admin to complete GPS Settings.';
            }
          } catch (_) {}
        }
        messenger.showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 4),
          ),
        );
        return;
      }

      // Check if user is within 15m radius for attendance marking
      final locationCheck = await GeofenceService().checkAttendanceLocationForCurrentUser();
      if (locationCheck['allowed'] != true) {
        final msg = locationCheck['message']?.toString() ??
            'You are outside the institute attendance zone (beyond 15m). Cannot mark attendance.';
        messenger.showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
        return;
      }

      var studentRow = await db
          .from('students')
          .select()
          .eq('institute_id', instituteId)
          .eq('user_id', roll)
          .maybeSingle();
      studentRow ??= await db
          .from('students')
          .select()
          .eq('institute_id', instituteId)
          .eq('sr_no', roll)
          .maybeSingle();

      if (studentRow == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Student not found.'), backgroundColor: Colors.red),
        );
        return;
      }

      final studentData = Map<String, dynamic>.from(studentRow);
      final studentSubjects = studentData['subjects'] as List<dynamic>?;
      final studentStoredSlots =
          studentData['lectureTiming'] as String? ??
          studentData['lecture_timing'] as String?;

      List<String> enrolledSubjects = studentSubjects != null && studentSubjects.isNotEmpty
          ? studentSubjects
              .map((s) => s.toString().trim())
              .where((s) => s.isNotEmpty)
              .toList()
          : <String>[];
      if (enrolledSubjects.isEmpty) {
        final single = studentData['subject']?.toString().trim() ?? '';
        if (single.isNotEmpty) enrolledSubjects = [single];
      }

      if (!studentHasNonEmptyFaceEmbedding(studentData['face_embedding'])) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Register this student\'s face before marking attendance (tap the face icon).',
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 5),
          ),
        );
        return;
      }

      String? forcedStep;
      final stepNorm = explicitStep?.trim().toLowerCase();
      if (stepNorm != null && stepNorm.isNotEmpty) {
        if (stepNorm != 'entry' && stepNorm != 'exit') {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Invalid attendance step.'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
        forcedStep = stepNorm;
      }

      if (enrolledSubjects.isEmpty) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Cannot mark attendance: Roll $roll has no subjects. Edit the student and add subjects.',
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 6),
          ),
        );
        return;
      }

      final instituteSlots = await InstituteLectureTimingService().buildLectureTimingString(instituteId);
      final timing = (studentStoredSlots != null && studentStoredSlots.trim().isNotEmpty)
          ? studentStoredSlots.trim()
          : instituteSlots;
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

      var existingPayload = await _getTeacherPayload(db, instituteId, roll, today);

      if (existingPayload != null &&
          enrolledSubjects.length > 1 &&
          _isLegacyAttendanceDoc(existingPayload)) {
        final chosen =
            pickEnrollmentSubjectForAutoClose(enrolledSubjects) ?? enrolledSubjects.first;
        final migrated = _migrateLegacyToFirstSubjectSession(
          Map<String, dynamic>.from(existingPayload),
          chosen,
        );
        if (!_isLegacyAttendanceDoc(migrated)) {
          await _upsertTeacherDoc(db, instituteId, roll, today, migrated);
          existingPayload = migrated;
        }
      }

      existingPayload = await StaleAttendanceReconciliationService.ensureReconciled(
        db: db,
        instituteId: instituteId,
        roll: roll,
        date: today,
        enrolledSubjects: enrolledSubjects,
        existingPayload: existingPayload,
      );

      final bool useSubjects;
      if (enrolledSubjects.isEmpty) {
        useSubjects = false;
      } else if (existingPayload == null || !_isLegacyAttendanceDoc(existingPayload)) {
        useSubjects = true;
      } else {
        useSubjects = false;
      }

      if (!useSubjects &&
          enrolledSubjects.length > 1 &&
          existingPayload != null &&
          _isLegacyAttendanceDoc(existingPayload)) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Roll $roll has multiple subjects and today\'s attendance is in an old format that could not be updated automatically. '
              'Ask your institute admin for help.',
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 8),
          ),
        );
        return;
      }

      if (useSubjects &&
          existingPayload != null &&
          _allSubjectsCompleteInPayload(existingPayload, enrolledSubjects)) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'All subjects are complete today for Roll $roll. After midnight you can mark again.',
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 5),
          ),
        );
        return;
      }

      String? activeSubject;
      if (useSubjects) {
        final chosenRaw = chosenSubject?.trim();
        if (chosenRaw != null && chosenRaw.isNotEmpty) {
          final canon = _canonicalSubjectFromEnrollment(enrolledSubjects, chosenRaw);
          if (canon == null) {
            messenger.showSnackBar(
              SnackBar(
                content: Text('"$chosenRaw" is not assigned to this student.'),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 5),
              ),
            );
            return;
          }
          activeSubject = canon;
        } else {
          final pending = _pendingSubjectFromPayload(existingPayload);
          if (pending != null) {
            activeSubject = pending;
          } else if (enrolledSubjects.length == 1) {
            activeSubject = enrolledSubjects.first;
          } else {
            if (!context.mounted) return;
            activeSubject = await _pickAttendanceSubjectSheet(
              context,
              enrolledSubjects,
              existingPayload,
            );
            if (activeSubject == null || !context.mounted) return;
            if (!enrolledSubjects.contains(activeSubject)) return;
          }
        }
        final pend2 = _pendingSubjectFromPayload(existingPayload);
        if (pend2 != null && pend2 != activeSubject) {
          messenger.showSnackBar(
            SnackBar(
              content: Text('Finish exit for "$pend2" first, then pick another subject.'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 5),
            ),
          );
          return;
        }
      }

      final _QuickMarkDecision decision;
      if (useSubjects && activeSubject != null) {
        decision = _decideNextMarkSubject(existingPayload, activeSubject);
      } else {
        decision = _decideNextMark(existingPayload, timing);
      }

      if (decision.mode == 'complete') {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              (useSubjects && activeSubject != null)
                  ? '"$activeSubject" is already complete today for Roll $roll.'
                  : 'Attendance already complete today for Roll $roll (entry & exit).',
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 4),
          ),
        );
        return;
      }

      if (forcedStep != null) {
        if (decision.mode == 'lecture_scan') {
          messenger.showSnackBar(
            const SnackBar(
              content: Text(
                'This student\'s attendance uses lecture-period scans today — complete those steps in the main attendance flow.',
              ),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 6),
            ),
          );
          return;
        }
        if (forcedStep != decision.mode) {
          if (forcedStep == 'exit' && decision.mode == 'entry') {
            messenger.showSnackBar(
              const SnackBar(
                content: Text('Take entry photo first (green).'),
                backgroundColor: Colors.orange,
              ),
            );
          } else if (forcedStep == 'entry' && decision.mode == 'exit') {
            messenger.showSnackBar(
              const SnackBar(
                content: Text('Entry already recorded — tap Exit (yellow).'),
                backgroundColor: Colors.orange,
              ),
            );
          } else {
            messenger.showSnackBar(
              const SnackBar(
                content: Text('Attendance step does not match current state.'),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        }
      }

      if (decision.mode == 'exit') {
        final abort = await _inlineAbortManualExitIfDeadlinePassed(
          messenger: messenger,
          db: db,
          instituteId: instituteId,
          roll: roll,
          today: today,
          enrolledSubjects: enrolledSubjects,
          payload: existingPayload,
          useSubjects: useSubjects,
          activeSubject: activeSubject,
          timing: timing,
        );
        if (abort) return;
      }

      if (useSubjects &&
          activeSubject != null &&
          decision.mode == 'entry') {
        final sm = _mapSubjectSessions(existingPayload);
        final s = _sessionForSubject(sm, activeSubject);
        if (!_sessionHasEntryMap(s)) {
          final seq = _sequentialPriorIncompleteSubject(
            enrolledSubjects,
            sm,
            activeSubject,
          );
          if (seq != null) {
            messenger.showSnackBar(
              SnackBar(
                content: Text(
                  'Finish entry and exit for "$seq" first, then mark "$activeSubject".',
                ),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 6),
              ),
            );
            return;
          }
        }
      }

      if (!kIsWeb) {
        if (!context.mounted) return;
        final okGps = await _checkGPSRadius(context, instituteId);
        if (!okGps || !context.mounted) return;
      }

      final markingTime = DateTime.now();
      final deviceInfo = await DeviceFingerprintService.getDeviceInfoForLogging();
      final networkInfo = await NetworkVerificationService.getNetworkInfoForLogging();
      SuspiciousActivityService.checkSuspiciousActivity(
        instituteId: instituteId,
        markedBy: db.auth.currentUser?.id ?? 'unknown',
        markingTime: markingTime,
        deviceFingerprint: deviceInfo['fingerprint'],
      ).then((suspiciousCheck) {
        if (suspiciousCheck['isSuspicious'] == true) {
          SuspiciousActivityService.logSuspiciousActivity(
            instituteId: instituteId,
            userId: db.auth.currentUser?.id ?? 'unknown',
            activityData: {
              'warnings': suspiciousCheck['warnings'],
              'deviceInfo': deviceInfo,
              'networkInfo': networkInfo,
            },
          ).catchError((e) {
            if (kDebugMode) debugPrint('⚠️ Failed to log suspicious activity: $e');
          });
        }
      }).catchError((e) {
        if (kDebugMode) debugPrint('⚠️ Suspicious activity check failed: $e');
      });

      final picker = ImagePicker();
      final XFile? photo;
      SessionMonitor.beginSuppressResumeLock();
      try {
        photo = await picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 50,
          maxWidth: 800,
          maxHeight: 800,
          preferredCameraDevice: CameraDevice.front,
        );
      } on PlatformException catch (e) {
        if (e.code == 'already_active') {
          if (context.mounted) {
            messenger.showSnackBar(
              const SnackBar(
                content: Text(
                  'Camera was interrupted (e.g. app went to background). Return here and try marking attendance again.',
                ),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 5),
              ),
            );
          }
          return;
        }
        rethrow;
      } finally {
        SessionMonitor.endSuppressResumeLock();
      }

      if (photo == null || !context.mounted) return;

      // Align verification with actual capture time (not the clock at start of GPS / picker flow).
      final timeAtPhotoCapture = DateTime.now();

      Uint8List bytes = await photo.readAsBytes();
      if (bytes.length > 50 * 1024) {
        bytes = await _compressImage(bytes, maxSizeKB: 50);
      }

      final photoVerification = await PhotoVerificationService.verifyPhoto(
        photoPath: photo.path,
        markingTime: timeAtPhotoCapture,
        expectedLocation: null,
      );
      if (!photoVerification['isValid']) {
        final errors = photoVerification['errors'] as List<String>;
        if (context.mounted) {
          messenger.showSnackBar(
            SnackBar(
              content: Text('❌ Photo verification failed:\n${errors.join('\n')}'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
        }
        return;
      }

      if (await PhotoVerificationService.detectBlur(bytes)) {
        if (context.mounted) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('⚠️ Photo is blurry. Please retake a clear photo.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      if (await PhotoVerificationService.detectPhotoOfPhoto(photo.path)) {
        if (context.mounted) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('❌ Photo of a photo detected. Take a live photo of the student.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 5),
            ),
          );
        }
        return;
      }

      final livenessResult = await LivenessDetectionService.detectLivenessFromPhoto(photoPath: photo.path);
      if (!LivenessDetectionService.passesLivePersonPreCheck(livenessResult)) {
        if (kDebugMode) {
          debugPrint(
            '⚠️ Live-person check failed: ${livenessResult.reason}',
          );
        }
        if (context.mounted) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text(
                'Live face check failed. No printed photos or screens — face the camera, eyes open, good lighting.',
              ),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 5),
            ),
          );
        }
        return;
      }

      final faceDetection = await PhotoVerificationService.detectMultipleFaces(photo.path);
      if (faceDetection['isGroupPhoto'] == true) {
        if (context.mounted) {
          messenger.showSnackBar(
            SnackBar(
              content: Text('⚠️ Multiple faces (${faceDetection['faceCount']}). One student only.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      messenger.clearSnackBars();
      messenger.showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  '🔐 Face verification (on-device)...',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          duration: Duration(seconds: 5),
          backgroundColor: Colors.blue,
        ),
      );

      final faceResult = await FaceRecognitionService.verifyStudent(photo.path, instituteId, roll);
      if (!faceResult.isMatch) {
        if (context.mounted) {
          messenger.clearSnackBars();
          messenger.showSnackBar(
            SnackBar(
              content: Text(faceResult.message),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 10),
            ),
          );
        }
        return;
      }

      messenger.clearSnackBars();

      final maxSizeBytes = 50 * 1024;
      if (bytes.length > maxSizeBytes) {
        if (context.mounted) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Photo too large after processing. Please retake.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final freshPayload = await FirestoreRetryService.executeWithRetry(
        operation: () async => _getTeacherPayload(db, instituteId, roll, today),
        operationName: 'Check existing attendance',
      );

      final currentTime = DateTime.now();
      final serverTs = _encodeSv();
      var mode = decision.mode;
      int? currentLectureIndex = decision.lectureIndex;

      if (freshPayload != null) {
        if (useSubjects && activeSubject != null) {
          if (_allSubjectsCompleteInPayload(freshPayload, enrolledSubjects)) {
            if (context.mounted) {
              messenger.showSnackBar(
                SnackBar(
                  content: Text('All subjects complete today for Roll $roll.'),
                  backgroundColor: Colors.orange,
                ),
              );
            }
            return;
          }
          final d2 = _decideNextMarkSubject(freshPayload, activeSubject);
          mode = d2.mode;
          currentLectureIndex = null;
          if (mode == 'complete') {
            if (context.mounted) {
              messenger.showSnackBar(
                SnackBar(
                  content: Text('"$activeSubject" is already complete for Roll $roll.'),
                  backgroundColor: Colors.orange,
                ),
              );
            }
            return;
          }
        } else {
          final hasEntry =
              freshPayload['entryPhoto'] != null || freshPayload['photoUrl'] != null;
          final hasExit =
              freshPayload['exitPhoto'] != null || freshPayload['exitTime'] != null;
          if (hasEntry && hasExit) {
            if (context.mounted) {
              messenger.showSnackBar(
                SnackBar(
                  content: Text('Attendance already complete today for Roll $roll.'),
                  backgroundColor: Colors.orange,
                ),
              );
            }
            return;
          }
          final d2 = _decideNextMark(freshPayload, timing);
          mode = d2.mode;
          currentLectureIndex = d2.lectureIndex;
          if (mode == 'complete') {
            if (context.mounted) {
              messenger.showSnackBar(
                const SnackBar(
                  content: Text('Already marked complete.'),
                  backgroundColor: Colors.orange,
                ),
              );
            }
            return;
          }
        }
      }

      if (forcedStep != null && forcedStep != mode) {
        if (!context.mounted) return;
        if (forcedStep == 'exit' && mode == 'entry') {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Take entry photo first (green).'),
              backgroundColor: Colors.orange,
            ),
          );
        } else if (forcedStep == 'entry' && mode == 'exit') {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Entry already recorded — tap Exit (yellow).'),
              backgroundColor: Colors.orange,
            ),
          );
        } else if (mode == 'lecture_scan') {
          messenger.showSnackBar(
            const SnackBar(
              content: Text(
                'A lecture scan is required next — complete that step in the main attendance flow.',
              ),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 6),
            ),
          );
        } else {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Attendance was updated — check status and try again.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      if (mode == 'exit') {
        final abort = await _inlineAbortManualExitIfDeadlinePassed(
          messenger: messenger,
          db: db,
          instituteId: instituteId,
          roll: roll,
          today: today,
          enrolledSubjects: enrolledSubjects,
          payload: freshPayload,
          useSubjects: useSubjects,
          activeSubject: activeSubject,
          timing: timing,
        );
        if (abort) return;
      }

      if (useSubjects &&
          activeSubject != null &&
          mode == 'entry') {
        final sm = _mapSubjectSessions(freshPayload);
        final s = _sessionForSubject(sm, activeSubject);
        if (!_sessionHasEntryMap(s)) {
          final seq = _sequentialPriorIncompleteSubject(
            enrolledSubjects,
            sm,
            activeSubject,
          );
          if (seq != null) {
            if (context.mounted) {
              messenger.showSnackBar(
                SnackBar(
                  content: Text(
                    'Finish entry and exit for "$seq" first, then mark "$activeSubject".',
                  ),
                  backgroundColor: Colors.orange,
                  duration: const Duration(seconds: 6),
                ),
              );
            }
            return;
          }
        }
      }

      final isMarkingEntry = mode == 'entry';
      final isMarkingExit = mode == 'exit';
      final isLectureScan = !useSubjects && mode == 'lecture_scan';
      final sy = studentData['year']?.toString().trim();
      final folderYear =
          (sy != null && sy.isNotEmpty) ? sy : DateTime.now().year.toString();
      final lectureTimes = _parseLectureTiming(timing);

      if (isLectureScan &&
          (currentLectureIndex == null ||
              currentLectureIndex < 0 ||
              currentLectureIndex >= lectureTimes.length)) {
        if (context.mounted) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text(
                'Lecture scan not available (check institute hours in settings).',
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      String photoType;
      if (isMarkingEntry) {
        photoType = 'entry';
      } else if (isMarkingExit) {
        photoType = 'exit';
      } else {
        photoType = 'lecture_scan';
      }

      final uploadResult = await StorageService.uploadAttendancePhoto(
        instituteId: instituteId,
        folderYear: folderYear,
        rollNumber: roll,
        subject: (useSubjects && activeSubject != null)
            ? activeSubject.trim()
            : 'all',
        date: today,
        photoBytes: bytes,
        photoType: photoType,
      );

      final url = uploadResult['url']!;
      final storagePath = uploadResult['path']!;
      final fileId = uploadResult['fileId'];

      final existingData = freshPayload != null
          ? Map<String, dynamic>.from(freshPayload)
          : <String, dynamic>{};

      final attendanceData = <String, dynamic>{
        'rollNumber': roll,
        'date': today,
        'markedBy': db.auth.currentUser?.id ?? 'unknown',
        'lectureTiming': timing,
        'instituteId': instituteId,
        'updatedAt': serverTs,
        'subjects': enrolledSubjects,
      };

      if (useSubjects && activeSubject != null) {
        if (!isMarkingEntry && !isMarkingExit) {
          if (context.mounted) {
            messenger.showSnackBar(
              const SnackBar(
                content: Text(
                  'Something went wrong with subject-based marking. Contact your institute admin.',
                ),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        }
        final sub = activeSubject;
        final sessions = <String, Map<String, dynamic>>{};
        for (final e in _mapSubjectSessions(existingData).entries) {
          sessions[e.key] = Map<String, dynamic>.from(e.value);
        }
        var sess = Map<String, dynamic>.from(sessions[sub] ?? {});
        if (isMarkingEntry) {
          sess['entryPhoto'] = url;
          sess['entryTime'] = serverTs;
          sess['entryPhotoPath'] = storagePath;
          if (fileId != null && fileId.isNotEmpty) {
            sess['entryPhotoFileId'] = fileId;
          }
          sess['photoUrl'] = url;
          sess['timestamp'] = serverTs;
          sess['status'] = 'pending';
          sess['subjectName'] = sub;
        } else if (isMarkingExit) {
          sess['exitPhoto'] = url;
          sess['exitTime'] = serverTs;
          sess['exitPhotoPath'] = storagePath;
          if (fileId != null && fileId.isNotEmpty) {
            sess['exitPhotoFileId'] = fileId;
          }
          final entryTime = _asDateTime(sess['entryTime']) ?? _asDateTime(sess['timestamp']);
          if (entryTime != null) {
            final duration = currentTime.difference(entryTime);
            final rawH = duration.inSeconds / 3600.0;
            sess['hoursRaw'] = double.parse(rawH.toStringAsFixed(6));
            sess['hours'] = attendanceCreditedHours(duration);
          }
          sess['status'] = 'present';
        }
        sessions[sub] = sess;
        attendanceData[_kSubjectSessionsKey] = sessions;
      } else if (isMarkingEntry) {
        attendanceData['entryPhoto'] = url;
        attendanceData['entryTime'] = serverTs;
        attendanceData['entryPhotoPath'] = storagePath;
        if (fileId != null && fileId.isNotEmpty) {
          attendanceData['entryPhotoFileId'] = fileId;
        }
        attendanceData['photoUrl'] = url;
        attendanceData['timestamp'] = serverTs;
        attendanceData['status'] = 'pending';
        final lectures = <String, dynamic>{};
        if (lectureTimes.isNotEmpty) {
          for (int i = 0; i < lectureTimes.length; i++) {
            final lecture = lectureTimes[i];
            final start = lecture['start'] as TimeOfDay;
            final end = lecture['end'] as TimeOfDay;
            final lectureKey = 'lecture_${i + 1}';
            lectures[lectureKey] = {
              'startTime': '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}',
              'endTime': '${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}',
              'marked': false,
              'status': 'pending',
            };
          }
        }
        attendanceData['lectures'] = lectures;
      } else if (isLectureScan && currentLectureIndex != null) {
        final lectureIndex = currentLectureIndex;
        final lectureKey = 'lecture_${lectureIndex + 1}';
        final lecture = lectureTimes[lectureIndex];
        final start = lecture['start'] as TimeOfDay;
        final end = lecture['end'] as TimeOfDay;
        attendanceData['entryPhoto'] = existingData['entryPhoto'] ?? existingData['photoUrl'];
        attendanceData['entryTime'] = existingData['entryTime'] ?? existingData['timestamp'];
        attendanceData['entryPhotoPath'] = existingData['entryPhotoPath'] ?? existingData['storagePath'];
        attendanceData['entryPhotoFileId'] = existingData['entryPhotoFileId'];
        attendanceData['photoUrl'] = existingData['photoUrl'] ?? existingData['entryPhoto'];
        attendanceData['timestamp'] = existingData['timestamp'] ?? existingData['entryTime'];
        final lectures = Map<String, dynamic>.from(existingData['lectures'] as Map? ?? {});
        lectures[lectureKey] = {
          'faceScanPhoto': url,
          'faceScanTime': serverTs,
          'faceScanPath': storagePath,
          if (fileId != null && fileId.isNotEmpty) 'faceScanFileId': fileId,
          'startTime': '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}',
          'endTime': '${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}',
          'marked': true,
        };
        attendanceData['lectures'] = lectures;
      } else if (isMarkingExit) {
        attendanceData['entryPhoto'] = existingData['entryPhoto'] ?? existingData['photoUrl'];
        attendanceData['entryTime'] = existingData['entryTime'] ?? existingData['timestamp'];
        attendanceData['entryPhotoPath'] = existingData['entryPhotoPath'] ?? existingData['storagePath'];
        attendanceData['entryPhotoFileId'] = existingData['entryPhotoFileId'];
        attendanceData['photoUrl'] = existingData['photoUrl'] ?? existingData['entryPhoto'];
        attendanceData['timestamp'] = existingData['timestamp'] ?? existingData['entryTime'];
        attendanceData['exitPhoto'] = url;
        attendanceData['exitTime'] = serverTs;
        attendanceData['exitPhotoPath'] = storagePath;
        if (fileId != null && fileId.isNotEmpty) {
          attendanceData['exitPhotoFileId'] = fileId;
        }
        final lectures = Map<String, dynamic>.from(existingData['lectures'] as Map? ?? {});
        final entryTime = _asDateTime(existingData['entryTime']) ?? _asDateTime(existingData['timestamp']);
        if (entryTime != null && lectureTimes.isNotEmpty) {
          final exitDateTime = currentTime;
          for (int i = 0; i < lectureTimes.length; i++) {
            final lec = lectureTimes[i];
            final start = lec['start'] as TimeOfDay;
            final end = lec['end'] as TimeOfDay;
            final lectureStart = DateTime(
              exitDateTime.year,
              exitDateTime.month,
              exitDateTime.day,
              start.hour,
              start.minute,
            );
            final lectureEnd = DateTime(
              exitDateTime.year,
              exitDateTime.month,
              exitDateTime.day,
              end.hour,
              end.minute,
            );
            if (lectureStart.isAfter(entryTime.subtract(const Duration(minutes: 30))) &&
                lectureEnd.isBefore(exitDateTime.add(const Duration(minutes: 30)))) {
              final lk = 'lecture_${i + 1}';
              if (!lectures.containsKey(lk)) {
                lectures[lk] = {
                  'startTime': '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}',
                  'endTime': '${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}',
                  'marked': true,
                  'markedAtExit': true,
                };
              } else {
                final existingLecture = Map<String, dynamic>.from(lectures[lk] as Map);
                existingLecture['marked'] = true;
                lectures[lk] = existingLecture;
              }
            }
          }
        }
        attendanceData['lectures'] = lectures;
        attendanceData['status'] = 'present';
        if (entryTime != null) {
          final duration = currentTime.difference(entryTime);
          final rawH = duration.inSeconds / 3600.0;
          attendanceData['hoursRaw'] = double.parse(rawH.toStringAsFixed(6));
          attendanceData['hours'] = attendanceCreditedHours(duration);
        }
      }

      final mergedPayload = Map<String, dynamic>.from(existingData)..addAll(attendanceData);

      await FirestoreRetryService.executeWithRetry(
        operation: () async => _upsertTeacherDoc(db, instituteId, roll, today, mergedPayload),
        operationName: 'Save attendance record',
      );

      final subjectLabel = (useSubjects && activeSubject != null)
          ? activeSubject
          : (enrolledSubjects.isEmpty
              ? null
              : enrolledSubjects.map((e) => e.toString()).join(', '));

      if (isMarkingEntry) {
        await _syncAttendanceInOut(
          instituteId: instituteId,
          roll: roll,
          date: today,
          type: 'entry',
          photoUrl: url,
          photoPath: storagePath,
          photoFileId: fileId,
          recordedAtUtc: serverTs,
          subject: subjectLabel,
          sessionEntryUtc: serverTs,
          status: 'pending',
        );
        await InstituteNotificationService.scheduleAttendanceExitReminder(
          instituteId: instituteId,
          rollKey: roll,
          dateKey: today,
          subjectTag: !useSubjects || activeSubject == null ? 'all' : activeSubject,
          entryAtUtc: DateTime.parse(serverTs.toString()).toUtc(),
        );
      } else if (isMarkingExit) {
        String? entryUtc;
        double? hrs;
        if (useSubjects && activeSubject != null) {
          final sess =
              _sessionForSubject(_mapSubjectSessions(mergedPayload), activeSubject);
          entryUtc = sess['entryTime']?.toString() ?? sess['timestamp']?.toString();
          hrs = (sess['hours'] as num?)?.toDouble();
        } else {
          entryUtc =
              mergedPayload['entryTime']?.toString() ?? mergedPayload['timestamp']?.toString();
          hrs = (mergedPayload['hours'] as num?)?.toDouble();
        }
        await _syncAttendanceInOut(
          instituteId: instituteId,
          roll: roll,
          date: today,
          type: 'exit',
          photoUrl: url,
          photoPath: storagePath,
          photoFileId: fileId,
          recordedAtUtc: serverTs,
          subject: subjectLabel,
          sessionEntryUtc: entryUtc,
          sessionExitUtc: serverTs,
          hours: hrs,
          status: 'present',
        );
        await InstituteNotificationService.cancelAttendanceExitReminder(
          instituteId: instituteId,
          rollKey: roll,
          dateKey: today,
          subjectTag: !useSubjects || activeSubject == null ? 'all' : activeSubject,
        );
      }

      String successMessage;
      if (isMarkingEntry) {
        successMessage = (useSubjects && activeSubject != null)
            ? '✅ Entry for "$activeSubject" — Roll $roll\nTake exit photo for this subject next.'
            : '✅ Entry recorded for $roll\nTake exit photo later to complete attendance.';
      } else if (isMarkingExit) {
        double credited;
        double rawH;
        if (useSubjects && activeSubject != null) {
          final sessions = _mapSubjectSessions(attendanceData);
          final sess = _sessionForSubject(sessions, activeSubject);
          credited = (sess['hours'] as num?)?.toDouble() ?? 0.0;
          rawH = (sess['hoursRaw'] as num?)?.toDouble() ?? credited;
        } else {
          credited = attendanceData['hours'] as double? ?? 0.0;
          rawH = (attendanceData['hoursRaw'] as num?)?.toDouble() ?? credited;
        }
        final seatedLabel = formatSeatedDurationHuman(
          Duration(seconds: (rawH * 3600).round()),
        );
        if (rawH > credited + 1e-6) {
          successMessage = (useSubjects && activeSubject != null)
              ? '✅ Exit for "$activeSubject" — Roll $roll\n'
                  '⏰ Credited: ${credited.toStringAsFixed(2)} h (max 2.5 h/subject). Seated: $seatedLabel'
              : '✅ Exit marked for $roll\n'
                  '⏰ Credited: ${credited.toStringAsFixed(2)} h (max 2.5 h/day). Seated: $seatedLabel';
        } else {
          successMessage = (useSubjects && activeSubject != null)
              ? '✅ Exit for "$activeSubject" — Roll $roll\n⏰ Credited: ${credited.toStringAsFixed(2)} h ($seatedLabel)'
              : '✅ Exit marked for $roll\n⏰ Credited: ${credited.toStringAsFixed(2)} h ($seatedLabel)';
        }
      } else if (isLectureScan && currentLectureIndex != null) {
        successMessage = '✅ Lecture ${currentLectureIndex + 1} scan done for $roll';
      } else {
        successMessage = '✅ Saved for $roll';
      }

      messenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(child: Text(successMessage)),
            ],
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Inline mark attendance: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to mark attendance: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
