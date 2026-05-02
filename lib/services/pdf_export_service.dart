import 'dart:io';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:intl/intl.dart';

import '../core/app_db.dart';
import '../core/supabase_maps.dart';
import '../core/time_parse.dart';
// Institute holiday/open/close system removed.

class PdfExportService {
  static final DateFormat _pdfTimeFmt = DateFormat('HH:mm');
  static final DateFormat _pdfDateFmt = DateFormat('MMM dd, yyyy');

  /// Parse a DB date key (`yyyy-MM-dd`) as local calendar date (no timezone shift).
  static DateTime _parseDateKeyLocal(String dateKey) {
    try {
      return DateFormat('yyyy-MM-dd').parseStrict(dateKey);
    } catch (_) {
      // Fallback for unexpected formats
      return DateTime.tryParse(dateKey)?.toLocal() ?? DateTime.now();
    }
  }

  static String _formatPdfLocalTime(DateTime dt) => _pdfTimeFmt.format(dt.toLocal());
  static String _formatPdfLocalDateFromKey(String dateKey) =>
      _pdfDateFmt.format(_parseDateKeyLocal(dateKey));

  static Future<Map<String, String>> _holidayReasons({
    required String instituteId,
    required String startDate,
    required String endDate,
  }) async {
    // Holiday system removed.
    return <String, String>{};
  }

  static String _rollKey(Map<String, dynamic> s) {
    final u = s['user_id'] as String?;
    final sr = s['sr_no'] as String?;
    return (u != null && u.isNotEmpty) ? u : (sr ?? '');
  }

  static Map<String, dynamic> _additional(dynamic a) {
    if (a is Map<String, dynamic>) return Map<String, dynamic>.from(a);
    if (a is Map) {
      return a.map((k, v) => MapEntry(k.toString(), v));
    }
    return {};
  }

  static String _statusFromRow(Map<String, dynamic> r) {
    final add = _additional(r['additional']);
    final st = add['status']?.toString();
    if (st != null && st.isNotEmpty) return st;
    return 'present';
  }

  static String? _subjectFromRow(Map<String, dynamic> r) {
    final add = _additional(r['additional']);
    return add['subject']?.toString();
  }

  /// Groups rows that share the same calendar day and subject (case-insensitive).
  /// Rows with no subject use a shared `'General'` bucket for that date.
  static String _subjectMergeKey(Map<String, dynamic> r) {
    final s = _subjectFromRow(r)?.trim() ?? '';
    if (s.isEmpty) return '__general__';
    return s.toLowerCase();
  }

  static String _subjectDisplayFromGroup(List<Map<String, dynamic>> list) {
    for (final r in list) {
      final s = _subjectFromRow(r)?.trim() ?? '';
      if (s.isNotEmpty) return s;
    }
    return 'General';
  }

  static Map<String, dynamic> _mergeInOutRowsForDateSubject(
    String date,
    List<Map<String, dynamic>> list,
    String subjectDisplay,
  ) {
    DateTime? entryTime;
    DateTime? exitTime;
    var status = 'absent';
    double? hours;
    var lectures = <String, dynamic>{};
    DateTime? latestTs;
    var autoClosedMissingExit = false;
    String? autoClosedNote;

    for (final data in list) {
      final add = _additional(data['additional']);
      final et = parseAnyTimestamp(add['entryTime']);
      final xt = parseAnyTimestamp(add['exitTime']);
      if (et != null) {
        entryTime = entryTime == null || et.isBefore(entryTime!) ? et : entryTime;
      }
      if (xt != null) {
        exitTime = exitTime == null || xt.isAfter(exitTime!) ? xt : exitTime;
      }
    }

    void pickLectures(Map<String, dynamic> m) {
      if (m.isEmpty) return;
      lectures = Map<String, dynamic>.from(m);
    }

    for (final data in list) {
      final add = _additional(data['additional']);
      final typ = (data['type'] as String?)?.toLowerCase() ?? 'entry';
      final created = parseAnyTimestamp(data['created_at']);
      final st = _statusFromRow(data);
      if (st == 'present') status = 'present';

      if (add['hours'] != null) {
        hours = (add['hours'] as num).toDouble();
      }
      if (add['lectures'] is Map) {
        pickLectures(
          Map<String, dynamic>.from((add['lectures'] as Map).cast<String, dynamic>()),
        );
      }

      if (add['autoClosedMissingExit'] == true) {
        autoClosedMissingExit = true;
        final n = add['autoClosedNote']?.toString().trim();
        if (n != null && n.isNotEmpty) autoClosedNote = n;
      }

      final etAdd = parseAnyTimestamp(add['entryTime']);
      final xtAdd = parseAnyTimestamp(add['exitTime']);

      if (created != null) {
        latestTs = latestTs == null || created.isAfter(latestTs!) ? created : latestTs;
      }

      if (typ == 'exit') {
        if (created != null) {
          exitTime = exitTime == null || created.isAfter(exitTime!) ? created : exitTime;
        }
        if (xtAdd != null) {
          exitTime = exitTime == null || xtAdd.isAfter(exitTime!) ? xtAdd : exitTime;
        }
      } else {
        if (created != null) {
          entryTime = entryTime == null || created.isBefore(entryTime!) ? created : entryTime;
        }
        if (etAdd != null) {
          entryTime = entryTime == null || etAdd.isBefore(entryTime!) ? etAdd : entryTime;
        }
      }
    }

    for (final data in list) {
      final add = _additional(data['additional']);
      final et = parseAnyTimestamp(add['entryTime']);
      final xt = parseAnyTimestamp(add['exitTime']);
      if (et != null) {
        entryTime = entryTime == null || et.isBefore(entryTime!) ? et : entryTime;
      }
      if (xt != null) {
        exitTime = exitTime == null || xt.isAfter(exitTime!) ? xt : exitTime;
      }
    }

    if (entryTime == null) {
      for (final data in list) {
        final typ = (data['type'] as String?)?.toLowerCase() ?? 'entry';
        if (typ != 'entry') continue;
        final c = parseAnyTimestamp(data['created_at']);
        if (c != null) {
          entryTime = entryTime == null || c.isBefore(entryTime!) ? c : entryTime;
        }
      }
    }
    if (exitTime == null) {
      for (final data in list) {
        final typ = (data['type'] as String?)?.toLowerCase() ?? 'entry';
        if (typ != 'exit') continue;
        final c = parseAnyTimestamp(data['created_at']);
        if (c != null) {
          exitTime = exitTime == null || c.isAfter(exitTime!) ? c : exitTime;
        }
      }
    }

    final typeEntry =
        list.any((d) => (d['type']?.toString().toLowerCase().trim() == 'entry'));
    final hasEntrySignal = entryTime != null || typeEntry;
    final credited = hours != null && hours > 0;
    if (hasEntrySignal ||
        autoClosedMissingExit ||
        credited ||
        (exitTime != null && status == 'present')) {
      status = 'present';
    } else {
      status = 'absent';
    }

    return {
      'date': date,
      'status': status,
      'subject': subjectDisplay,
      'timestamp': latestTs,
      'entryTime': entryTime,
      'exitTime': exitTime,
      'hours': hours,
      'lectures': lectures,
      'type': 'session',
      'autoClosedMissingExit': autoClosedMissingExit,
      if (autoClosedNote != null && autoClosedNote.isNotEmpty) 'autoClosedNote': autoClosedNote,
    };
  }

  /// True if [r] should be included when filtering reports/PDF by a single subject name.
  static bool rowMatchesSubjectFilter(Map<String, dynamic> r, String? selectedSubject) {
    if (selectedSubject == null ||
        selectedSubject.isEmpty ||
        selectedSubject == 'All Subjects') {
      return true;
    }
    final subj = _subjectFromRow(r) ?? '';
    if (subj.isEmpty) return false;
    if (subj == selectedSubject) return true;
    for (final part in subj.split(',')) {
      if (part.trim() == selectedSubject) return true;
    }
    return false;
  }

  /// One row per calendar day **per subject**: merges separate `type: entry` / `type: exit`
  /// rows from [attendance_in_out] within the same date and subject bucket.
  static List<Map<String, dynamic>> mergeAttendanceInOutRowsByDate(
    List<Map<String, dynamic>> rows,
  ) {
    if (rows.isEmpty) return [];
    const sep = '|';
    final byComposite = <String, List<Map<String, dynamic>>>{};
    for (final r in rows) {
      final d = r['attendance_date']?.toString() ?? '';
      if (d.isEmpty) continue;
      final mk = _subjectMergeKey(r);
      byComposite.putIfAbsent('$d$sep$mk', () => []).add(r);
    }
    final sortedKeys = byComposite.keys.toList()..sort((a, b) {
      final ia = a.indexOf(sep);
      final ib = b.indexOf(sep);
      final da = a.substring(0, ia);
      final db = b.substring(0, ib);
      final byDate = da.compareTo(db);
      if (byDate != 0) return byDate;
      final ka = a.substring(ia + sep.length);
      final kb = b.substring(ib + sep.length);
      if (ka == '__general__' && kb != '__general__') return 1;
      if (ka != '__general__' && kb == '__general__') return -1;
      return ka.compareTo(kb);
    });

    final out = <Map<String, dynamic>>[];
    for (final key in sortedKeys) {
      final i = key.indexOf(sep);
      final date = key.substring(0, i);
      final list = byComposite[key]!;
      final display = _subjectDisplayFromGroup(list);
      out.add(_mergeInOutRowsForDateSubject(date, list, display));
    }
    return out;
  }

  /// Generate PDF report for all students with daily attendance
  static Future<Uint8List> generateStudentsReport({
    required String instituteId,
    required DateTime startDate,
    required DateTime endDate,
    String? subject,
  }) async {
    final pdf = pw.Document();
    final startDateStr = DateFormat('yyyy-MM-dd').format(startDate);
    final endDateStr = DateFormat('yyyy-MM-dd').format(endDate);
    final holidays = await _holidayReasons(
      instituteId: instituteId,
      startDate: startDateStr,
      endDate: endDateStr,
    );

    final code = await instituteCodeForId(instituteId);
    var attRows = await appDb
        .from('attendance_in_out')
        .select()
        .eq('institute_code', code)
        .gte('attendance_date', startDateStr)
        .lte('attendance_date', endDateStr);

    if (subject != null && subject != 'All Subjects') {
      attRows = attRows.where((raw) {
        final r = raw as Map<String, dynamic>;
        return rowMatchesSubjectFilter(r, subject);
      }).toList();
    }

    final studentsSnap = await appDb.from('students').select().eq('institute_id', instituteId);

    final Map<String, Map<String, dynamic>> studentData = {};
    final Map<String, List<Map<String, dynamic>>> studentAttendance = {};

    for (final s in studentsSnap) {
      final row = s as Map<String, dynamic>;
      final roll = _rollKey(row);
      if (roll.isEmpty) continue;
      studentData[roll] = {
        'name': row['name'] as String? ?? 'Unknown',
        'rollNumber': roll,
        'photoUrl': row['photo_url'] as String? ?? row['face_photo_url'] as String? ?? '',
      };
      studentAttendance[roll] = [];
    }

    final idToRoll = <String, String>{};
    for (final s in studentsSnap) {
      final m = s as Map<String, dynamic>;
      final id = m['id'] as String?;
      if (id == null) continue;
      final rk = _rollKey(m);
      if (rk.isNotEmpty) idToRoll[id] = rk;
    }

    final Map<String, List<Map<String, dynamic>>> rawByRoll = {};
    for (final raw in attRows) {
      final data = raw as Map<String, dynamic>;
      final sid = data['student_id'] as String? ?? '';
      final sr = data['sr_no'] as String? ?? '';
      var roll = idToRoll[sid] ?? '';
      if (roll.isEmpty) {
        for (final s in studentsSnap) {
          final m = s as Map<String, dynamic>;
          if (m['id'] == sid || m['sr_no'] == sr || m['user_id'] == sr) {
            roll = _rollKey(m);
            break;
          }
        }
      }
      if (roll.isEmpty) roll = sr;
      if (roll.isEmpty) continue;
      rawByRoll.putIfAbsent(roll, () => []).add(data);
    }

    for (final e in rawByRoll.entries) {
      final merged = mergeAttendanceInOutRowsByDate(e.value);
      studentAttendance.putIfAbsent(e.key, () => []);
      studentAttendance[e.key]!.addAll(merged);
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Attendance Report',
                      style: pw.TextStyle(
                        fontSize: 24,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      '${_pdfDateFmt.format(startDate)} - ${_pdfDateFmt.format(endDate)}',
                      style: pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
                    ),
                    if (subject != null && subject != 'All Subjects')
                      pw.Text(
                        'Subject: $subject',
                        style: pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
                      ),
                  ],
                ),
                pw.Text(
                  _pdfDateFmt.format(DateTime.now()),
                  style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 20),
          if (holidays.isNotEmpty) ...[
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: PdfColors.orange50,
                border: pw.Border.all(color: PdfColors.orange300),
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Institute Holidays',
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.orange800,
                    ),
                  ),
                  pw.SizedBox(height: 6),
                  ...holidays.entries.map((e) => pw.Padding(
                        padding: const pw.EdgeInsets.only(bottom: 3),
                        child: pw.Text(
                          '${_formatPdfLocalDateFromKey(e.key)}: ${e.value}',
                          style: const pw.TextStyle(fontSize: 10),
                        ),
                      )),
                ],
              ),
            ),
            pw.SizedBox(height: 16),
          ],
          pw.Text(
            'Students Attendance Summary',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 10),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300),
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Text('Roll No', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Text('Name', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Text('Present', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Text('Absent', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Text('Total', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Text('Percentage', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Text(
                      'Total seated',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
                    ),
                  ),
                ],
              ),
              ...studentData.entries.map((entry) {
                final rollNumber = entry.key;
                final student = entry.value;
                final attendance = studentAttendance[rollNumber] ?? [];
                final presentCount = attendance.where((a) => a['status'] == 'present').length;
                final absentCount = attendance.where((a) => a['status'] == 'absent').length;
                final total = attendance.length;
                final percentage = total > 0 ? (presentCount / total * 100) : 0.0;
                var seatedTotal = Duration.zero;
                for (final a in attendance) {
                  final d = seatedDurationFromMergedAttendanceDay(a);
                  if (d != null && !d.isNegative) seatedTotal += d;
                }
                final seatedStr =
                    seatedTotal > Duration.zero ? formatSeatedDurationHuman(seatedTotal) : '—';

                return pw.TableRow(
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text(rollNumber, style: const pw.TextStyle(fontSize: 10)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text(
                        student['name'] as String? ?? 'Unknown',
                        style: const pw.TextStyle(fontSize: 10),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text('$presentCount', style: const pw.TextStyle(fontSize: 10)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text('$absentCount', style: const pw.TextStyle(fontSize: 10)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text('$total', style: const pw.TextStyle(fontSize: 10)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text(
                        '${percentage.toStringAsFixed(1)}%',
                        style: pw.TextStyle(
                          fontSize: 10,
                          color: percentage >= 75 ? PdfColors.green : PdfColors.red,
                        ),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text(seatedStr, style: const pw.TextStyle(fontSize: 9)),
                    ),
                  ],
                );
              }),
            ],
          ),
        ],
      ),
    );

    return pdf.save();
  }

  /// Generate individual student PDF report with photo, percentage, subject-wise attendance
  static Future<Uint8List> generateStudentReport({
    required String instituteId,
    required String rollNumber,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final pdf = pw.Document();
    final startDateStr = DateFormat('yyyy-MM-dd').format(startDate);
    final endDateStr = DateFormat('yyyy-MM-dd').format(endDate);
    final holidays = await _holidayReasons(
      instituteId: instituteId,
      startDate: startDateStr,
      endDate: endDateStr,
    );

    final allStudents = await appDb.from('students').select().eq('institute_id', instituteId);
    Map<String, dynamic>? studentData;
    for (final s in allStudents) {
      final m = s as Map<String, dynamic>;
      if (m['user_id'] == rollNumber || m['sr_no'] == rollNumber) {
        studentData = m;
        break;
      }
    }

    if (studentData == null) {
      if (kDebugMode) debugPrint('Student not found with rollNumber: $rollNumber');
      throw Exception('Student not found with roll number: $rollNumber');
    }
    final studentId = studentData['id'] as String;
    final studentName = studentData['name'] as String? ?? 'Unknown';
    final photoUrl = studentData['photo_url'] as String? ?? studentData['face_photo_url'] as String?;

    final code = await instituteCodeForId(instituteId);
    final rawAtt = await appDb
        .from('attendance_in_out')
        .select()
        .eq('institute_code', code)
        .eq('student_id', studentId)
        .gte('attendance_date', startDateStr)
        .lte('attendance_date', endDateStr)
        .order('attendance_date');

    final attendanceDocs = rawAtt.map((e) => e as Map<String, dynamic>).toList();
    final dailyAttendance = mergeAttendanceInOutRowsByDate(attendanceDocs);
    final dailyDetails = <Map<String, dynamic>>[
      ...dailyAttendance,
      ...holidays.entries.map((e) => {
            'date': e.key,
            'status': 'holiday',
            'reason': e.value,
          }),
    ]..sort((a, b) {
      final da = a['date'] as String;
      final db = b['date'] as String;
      final byDate = da.compareTo(db);
      if (byDate != 0) return byDate;
      final ha = a['status'] == 'holiday';
      final hb = b['status'] == 'holiday';
      if (ha != hb) return ha ? 1 : -1;
      final sa = (a['subject'] as String? ?? '').toLowerCase();
      final sb = (b['subject'] as String? ?? '').toLowerCase();
      return sa.compareTo(sb);
    });

    final totalLectures = dailyAttendance.length;
    final presentCount = dailyAttendance.where((a) => a['status'] == 'present').length;
    final absentCount = dailyAttendance.where((a) => a['status'] == 'absent').length;
    final percentage = totalLectures > 0 ? (presentCount / totalLectures * 100) : 0.0;

    var periodSeatedTotal = Duration.zero;
    for (final m in dailyAttendance) {
      final d = seatedDurationFromMergedAttendanceDay(m);
      if (d != null && !d.isNegative) {
        periodSeatedTotal += d;
      }
    }

    pw.ImageProvider? photoProvider;
    if (photoUrl != null && photoUrl.isNotEmpty) {
      try {
        final response = await http.get(Uri.parse(photoUrl));
        if (response.statusCode == 200) {
          photoProvider = pw.MemoryImage(response.bodyBytes);
        }
      } catch (e) {
        if (kDebugMode) debugPrint('Error loading photo: $e');
      }
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (context) => [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (photoProvider != null)
                pw.Container(
                  width: 80,
                  height: 80,
                  decoration: pw.BoxDecoration(
                    shape: pw.BoxShape.circle,
                    border: pw.Border.all(color: PdfColors.grey400, width: 2),
                  ),
                  child: pw.ClipOval(
                    child: pw.Image(photoProvider, fit: pw.BoxFit.cover),
                  ),
                )
              else
                pw.Container(
                  width: 80,
                  height: 80,
                  decoration: pw.BoxDecoration(
                    shape: pw.BoxShape.circle,
                    color: PdfColors.grey300,
                    border: pw.Border.all(color: PdfColors.grey400, width: 2),
                  ),
                  child: pw.Center(
                    child: pw.Text(
                      'STUDENT',
                      style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
                    ),
                  ),
                ),
              pw.SizedBox(width: 20),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      studentName,
                      style: pw.TextStyle(
                        fontSize: 24,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Roll Number: $rollNumber',
                      style: pw.TextStyle(fontSize: 14, color: PdfColors.grey700),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Text(
                      '${_pdfDateFmt.format(startDate)} - ${_pdfDateFmt.format(endDate)}',
                      style: pw.TextStyle(fontSize: 12, color: PdfColors.grey600),
                    ),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 30),
          pw.Container(
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                pw.Column(
                  children: [
                    pw.Text(
                      '$totalLectures',
                      style: pw.TextStyle(
                        fontSize: 24,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.blue700,
                      ),
                    ),
                    pw.Text(
                      'Total sessions',
                      style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                    ),
                  ],
                ),
                pw.Column(
                  children: [
                    pw.Text(
                      '$presentCount',
                      style: pw.TextStyle(
                        fontSize: 24,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.green700,
                      ),
                    ),
                    pw.Text(
                      'Present',
                      style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                    ),
                  ],
                ),
                pw.Column(
                  children: [
                    pw.Text(
                      '$absentCount',
                      style: pw.TextStyle(
                        fontSize: 24,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.red700,
                      ),
                    ),
                    pw.Text(
                      'Absent',
                      style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                    ),
                  ],
                ),
                pw.Column(
                  children: [
                    pw.Text(
                      '${percentage.toStringAsFixed(1)}%',
                      style: pw.TextStyle(
                        fontSize: 24,
                        fontWeight: pw.FontWeight.bold,
                        color: percentage >= 75 ? PdfColors.green700 : PdfColors.red700,
                      ),
                    ),
                    pw.Text(
                      'Attendance %',
                      style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                    ),
                  ],
                ),
                pw.Column(
                  children: [
                    pw.Text(
                      periodSeatedTotal > Duration.zero
                          ? formatSeatedDurationHuman(periodSeatedTotal)
                          : '—',
                      style: pw.TextStyle(
                        fontSize: 20,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.indigo700,
                      ),
                    ),
                    pw.Text(
                      'Total seated',
                      style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                    ),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 20),
          pw.Text(
            'Daily Attendance Details',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 10),
          if (dailyDetails.isEmpty)
            pw.Container(
              padding: const pw.EdgeInsets.all(16),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Text(
                'No attendance records found for the selected date range.',
                style: pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
                textAlign: pw.TextAlign.center,
              ),
            )
          else
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300),
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text('Date', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text('Subject', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text('Entry Time', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text('Exit Time', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text(
                        'Seated',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text('Status', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    ),
                  ],
                ),
                ...dailyDetails.map((record) {
                  final date = record['date'] as String;
                  final status = record['status'] as String;
                  final reason = record['reason'] as String?;
                  final subjectLabel =
                      status == 'holiday' ? '—' : (record['subject'] as String? ?? 'General');
                  final entryTime = record['entryTime'] as DateTime?;
                  final exitTime = record['exitTime'] as DateTime?;
                  var entryTimeStr = '-';
                  if (entryTime != null) {
                    entryTimeStr = _formatPdfLocalTime(entryTime);
                  }

                  var exitTimeStr = '-';
                  final autoClosed = record['autoClosedMissingExit'] == true;
                  final policyNote = record['autoClosedNote'] as String?;
                  if (exitTime != null) {
                    exitTimeStr = _formatPdfLocalTime(exitTime);
                  } else if (autoClosed) {
                    exitTimeStr = 'No Exit';
                  } else if (status == 'absent') {
                    exitTimeStr = 'No Exit';
                  } else if (status == 'holiday') {
                    exitTimeStr = reason == null || reason.isEmpty ? 'Holiday' : reason;
                  }

                  final seatedDur = seatedDurationFromMergedAttendanceDay(record);
                  final hc = record['hours'];
                  final String seatedStr;
                  if (autoClosed) {
                    final h = record['hours'];
                    final tail =
                        h is num ? ' (${h.toStringAsFixed(2)} h credited)' : '';
                    seatedStr =
                        'Student did not exit$tail${policyNote != null ? '. $policyNote' : ''}';
                  } else if (hc is num && hc > 0) {
                    seatedStr =
                        '${hc.toStringAsFixed(2)} h credited${seatedDur != null && seatedDur > Duration.zero ? ' (${formatSeatedDurationHuman(seatedDur)} seated)' : ''}';
                  } else if (seatedDur != null && seatedDur > Duration.zero) {
                    seatedStr = formatSeatedDurationHuman(seatedDur);
                  } else {
                    seatedStr = '—';
                  }

                  var statusCell = status == 'holiday'
                      ? 'Holiday'
                      : status == 'absent'
                          ? 'Absent'
                          : (status == 'pending' ? 'Pending' : 'Present');
                  if (autoClosed && status == 'present') {
                    statusCell = 'Present (policy)';
                  }

                  return pw.TableRow(
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(
                          _formatPdfLocalDateFromKey(date),
                          style: const pw.TextStyle(fontSize: 9),
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(subjectLabel, style: const pw.TextStyle(fontSize: 9)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(entryTimeStr, style: const pw.TextStyle(fontSize: 9)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(exitTimeStr, style: const pw.TextStyle(fontSize: 9)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(seatedStr, style: const pw.TextStyle(fontSize: 9)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(
                          statusCell,
                          style: pw.TextStyle(
                            fontSize: 9,
                            color: status == 'holiday'
                                ? PdfColors.orange700
                                : status == 'absent'
                                ? PdfColors.red700
                                : (status == 'pending' ? PdfColors.orange700 : PdfColors.green700),
                          ),
                        ),
                      ),
                    ],
                  );
                }),
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text(
                        'Total (period)',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text('—', style: const pw.TextStyle(fontSize: 9)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text('—', style: const pw.TextStyle(fontSize: 9)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text('—', style: const pw.TextStyle(fontSize: 9)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text(
                        periodSeatedTotal > Duration.zero
                            ? formatSeatedDurationHuman(periodSeatedTotal)
                            : '—',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text(
                        '$presentCount / $totalLectures sessions',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
                      ),
                    ),
                  ],
                ),
              ],
            ),
        ],
      ),
    );

    return pdf.save();
  }

  /// Save PDF to device and return file path
  static Future<String> savePdfToDevice(Uint8List pdfBytes, String fileName) async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/$fileName');
    await file.writeAsBytes(pdfBytes);
    return file.path;
  }

  /// Share/Print PDF
  static Future<void> sharePdf(Uint8List pdfBytes, String fileName) async {
    await Printing.layoutPdf(
      onLayout: (format) async => pdfBytes,
    );
  }
}
