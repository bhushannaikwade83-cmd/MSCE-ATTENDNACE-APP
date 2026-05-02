import 'time_parse.dart';

/// Subject buckets in teacher_attendance.payload (`subjectSessions`).
const String kSubjectSessionsPayloadKey = 'subjectSessions';

/// Legacy constant (kept for compatibility).
const double kAttendanceExitDeadlineHours = 24;

/// Legacy helper constant used by some notification codepaths.
///
/// The actual deadline rule is "until the calendar day changes locally"
/// (see [isPastAttendanceExitDeadline]). This duration is kept only to
/// satisfy older callers that add a fixed duration to an entry timestamp.
const Duration kAttendanceExitDeadlineDuration = Duration(hours: 24);

/// Strict rule: Exit must be taken within a fixed window from Entry based on
/// allotted subject count (1 subject=2h, 2=4h, 3=6h, 4+=8h).
bool isPastAttendanceExitDeadline(DateTime entryUtc, DateTime nowUtc, int subjectCount) {
  final allowedHours = attendanceAllowedWindowHoursForSubjectCount(subjectCount);
  final allowed = Duration(minutes: (allowedHours * 60).round());
  return nowUtc.toUtc().isAfter(entryUtc.toUtc().add(allowed));
}

String autoClosedMissingExitNote(double creditedHours) =>
    'No exit within allowed window — credited ${creditedHours}h without exit photo.';

/// Prefer subjects whose name mentions 30, then 40, then 50 (word boundary).
int subjectAutoClosePriority(String subjectName) {
  if (RegExp(r'\b30\b').hasMatch(subjectName)) return 0;
  if (RegExp(r'\b40\b').hasMatch(subjectName)) return 1;
  if (RegExp(r'\b50\b').hasMatch(subjectName)) return 2;
  return 3;
}

bool sessionHasEntryMap(Map<String, dynamic> s) {
  return s['entryPhoto'] != null || s['photoUrl'] != null || s['entryTime'] != null;
}

bool sessionHasExitMap(Map<String, dynamic> s) {
  return s['exitPhoto'] != null || s['exitTime'] != null;
}

Map<String, Map<String, dynamic>> mapSubjectSessions(Map<String, dynamic>? payload) {
  if (payload == null) return {};
  final raw = payload[kSubjectSessionsPayloadKey];
  if (raw is! Map) return {};
  final out = <String, Map<String, dynamic>>{};
  raw.forEach((k, v) {
    if (v is Map) {
      out[k.toString()] = Map<String, dynamic>.from(v.cast<String, dynamic>());
    }
  });
  return out;
}

double sumSubjectCreditedHours(Map<String, Map<String, dynamic>> sessions) {
  double t = 0;
  for (final s in sessions.values) {
    final h = s['hours'];
    if (h is num) t += h.toDouble();
  }
  return double.parse(t.toStringAsFixed(6));
}

bool _legacyHasTopLevelAttendance(Map<String, dynamic> p) {
  return p['entryPhoto'] != null ||
      p['entryTime'] != null ||
      p['photoUrl'] != null ||
      p['exitPhoto'] != null ||
      p['exitTime'] != null;
}

bool _isLegacyAttendanceDoc(Map<String, dynamic> data) {
  final ss = data[kSubjectSessionsPayloadKey];
  if (ss is Map && ss.isNotEmpty) return false;
  return _legacyHasTopLevelAttendance(data);
}

/// Pick enrolled subject for legacy single-row auto-close (30 → 40 → 50 → first).
String? pickEnrollmentSubjectForAutoClose(List<String> enrolledSubjects) {
  if (enrolledSubjects.isEmpty) return null;
  for (final token in ['30', '40', '50']) {
    for (final s in enrolledSubjects) {
      if (RegExp(r'\b' + token + r'\b').hasMatch(s)) return s;
    }
  }
  return enrolledSubjects.first;
}

class AutoCloseSyncHint {
  final String subjectLabel;
  final String sessionEntryUtc;
  final String syntheticExitUtc;

  const AutoCloseSyncHint({
    required this.subjectLabel,
    required this.sessionEntryUtc,
    required this.syntheticExitUtc,
  });
}

class AttendanceAutoCloseApplyResult {
  final Map<String, dynamic> payload;
  final bool changed;
  final List<AutoCloseSyncHint> syncHints;

  const AttendanceAutoCloseApplyResult({
    required this.payload,
    required this.changed,
    required this.syncHints,
  });
}

/// Applies the missing-exit deadline rule to [payload] (mutates a deep copy).
AttendanceAutoCloseApplyResult applyMissingExitAutoClose({
  required Map<String, dynamic> payload,
  required List<String> enrolledSubjects,
  required DateTime nowUtc,
}) {
  final out = Map<String, dynamic>.from(payload);
  final sessions = mapSubjectSessions(out);

  if (sessions.isNotEmpty) {
    return _applySubjectSessions(out, sessions, enrolledSubjects, nowUtc);
  }

  if (_isLegacyAttendanceDoc(out)) {
    return _applyLegacyTopLevel(out, enrolledSubjects, nowUtc);
  }

  return AttendanceAutoCloseApplyResult(payload: out, changed: false, syncHints: const []);
}

AttendanceAutoCloseApplyResult _applySubjectSessions(
  Map<String, dynamic> out,
  Map<String, Map<String, dynamic>> sessions,
  List<String> enrolledSubjects,
  DateTime nowUtc,
) {
  final mutable = <String, Map<String, dynamic>>{};
  for (final e in sessions.entries) {
    mutable[e.key] = Map<String, dynamic>.from(e.value);
  }

  final stale = <String>[];
  for (final sub in enrolledSubjects) {
    final sess = Map<String, dynamic>.from(mutable[sub] ?? {});
    if (sess['autoClosedMissingExit'] == true) continue;
    if (!sessionHasEntryMap(sess)) continue;
    if (sessionHasExitMap(sess)) continue;
    final entry = parseAnyTimestamp(sess['entryTime']) ?? parseAnyTimestamp(sess['timestamp']);
    if (entry == null) continue;
    if (!isPastAttendanceExitDeadline(entry, nowUtc, enrolledSubjects.length)) continue;
    stale.add(sub);
  }

  if (stale.isEmpty) {
    return AttendanceAutoCloseApplyResult(payload: out, changed: false, syncHints: const []);
  }

  stale.sort((a, b) {
    final c = subjectAutoClosePriority(a).compareTo(subjectAutoClosePriority(b));
    if (c != 0) return c;
    return enrolledSubjects.indexOf(a).compareTo(enrolledSubjects.indexOf(b));
  });

  final hints = <AutoCloseSyncHint>[];
  for (final sub in stale) {
    var sess = Map<String, dynamic>.from(mutable[sub] ?? {});
    final entry = parseAnyTimestamp(sess['entryTime']) ?? parseAnyTimestamp(sess['timestamp']);
    if (entry == null) continue;

    final elapsed = nowUtc.difference(entry);
    final rawH = elapsed.inSeconds / 3600.0;

    final entryIso = entry.toUtc().toIso8601String();
    sess.remove('exitTime');
    sess.remove('exitPhoto');
    sess.remove('exitPhotoPath');
    sess.remove('exitPhotoFileId');
    sess['hoursRaw'] = double.parse(rawH.toStringAsFixed(6));
    final creditedHours = attendanceAllocatedHoursForSubjectCount(enrolledSubjects.length);
    sess['hours'] = creditedHours;
    sess['status'] = 'present';
    sess['autoClosedMissingExit'] = true;
    sess['autoClosedNote'] = autoClosedMissingExitNote(creditedHours);
    mutable[sub] = sess;

    hints.add(
      AutoCloseSyncHint(
        subjectLabel: sub,
        sessionEntryUtc: entryIso,
        syntheticExitUtc: nowUtc.toIso8601String(),
      ),
    );
  }

  out[kSubjectSessionsPayloadKey] = mutable;
  out['totalCreditedHoursDay'] = sumSubjectCreditedHours(mutable);

  var allExit = true;
  for (final sub in enrolledSubjects) {
    if (!sessionHasExitMap(Map<String, dynamic>.from(mutable[sub] ?? {}))) {
      allExit = false;
      break;
    }
  }
  out['status'] = allExit ? 'present' : 'pending';

  return AttendanceAutoCloseApplyResult(payload: out, changed: true, syncHints: hints);
}

AttendanceAutoCloseApplyResult _applyLegacyTopLevel(
  Map<String, dynamic> out,
  List<String> enrolledSubjects,
  DateTime nowUtc,
) {
  if (out['autoClosedMissingExit'] == true) {
    return AttendanceAutoCloseApplyResult(payload: out, changed: false, syncHints: const []);
  }

  final hasEntry =
      out['entryPhoto'] != null || out['photoUrl'] != null || out['entryTime'] != null;
  final hasExit = out['exitPhoto'] != null || out['exitTime'] != null;
  if (!hasEntry || hasExit) {
    return AttendanceAutoCloseApplyResult(payload: out, changed: false, syncHints: const []);
  }

  final entry = parseAnyTimestamp(out['entryTime']) ?? parseAnyTimestamp(out['timestamp']);
  if (entry == null) {
    return AttendanceAutoCloseApplyResult(payload: out, changed: false, syncHints: const []);
  }

  if (!isPastAttendanceExitDeadline(entry, nowUtc, enrolledSubjects.length)) {
    return AttendanceAutoCloseApplyResult(payload: out, changed: false, syncHints: const []);
  }

  final chosen = pickEnrollmentSubjectForAutoClose(enrolledSubjects);
  if (chosen == null) {
    return AttendanceAutoCloseApplyResult(payload: out, changed: false, syncHints: const []);
  }

  final elapsed = nowUtc.difference(entry);
  final rawH = elapsed.inSeconds / 3600.0;
  final entryIso = entry.toUtc().toIso8601String();

  out.remove('exitTime');
  out.remove('exitPhoto');
  out.remove('exitPhotoPath');
  out.remove('exitPhotoFileId');
  out['hoursRaw'] = double.parse(rawH.toStringAsFixed(6));
  final creditedHours = attendanceAllocatedHoursForSubjectCount(enrolledSubjects.length);
  out['hours'] = creditedHours;
  out['status'] = 'present';
  out['autoClosedMissingExit'] = true;
  out['autoClosedNote'] = autoClosedMissingExitNote(creditedHours);

  return AttendanceAutoCloseApplyResult(
    payload: out,
    changed: true,
    syncHints: [
      AutoCloseSyncHint(
        subjectLabel: chosen,
        sessionEntryUtc: entryIso,
        syntheticExitUtc: nowUtc.toIso8601String(),
      ),
    ],
  );
}
