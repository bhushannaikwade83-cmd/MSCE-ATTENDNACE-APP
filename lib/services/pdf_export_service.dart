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

class PdfExportService {
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
    return add['subject']?.toString() ?? r['semester_code']?.toString();
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
        final subj = _subjectFromRow(r);
        return subj == subject;
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
        'batchName': row['batch_name'] as String? ?? '',
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

      final date = data['attendance_date']?.toString() ?? '';
      final status = _statusFromRow(data);
      final subjectName = _subjectFromRow(data) ?? '';
      final add = _additional(data['additional']);
      final entryTime = parseAnyTimestamp(add['entryTime'] ?? data['created_at']);
      final exitTime = parseAnyTimestamp(add['exitTime']);
      final lectures = add['lectures'] is Map ? Map<String, dynamic>.from((add['lectures'] as Map).cast<String, dynamic>()) : <String, dynamic>{};

      if (date.isEmpty) continue;
      studentAttendance.putIfAbsent(roll, () => []);
      studentAttendance[roll]!.add({
        'date': date,
        'status': status,
        'subject': subjectName,
        'timestamp': parseAnyTimestamp(data['created_at']),
        'entryTime': entryTime,
        'exitTime': exitTime,
        'hours': (add['hours'] as num?)?.toDouble(),
        'lectures': lectures,
      });
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
                      '${DateFormat('MMM dd, yyyy').format(startDate)} - ${DateFormat('MMM dd, yyyy').format(endDate)}',
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
                  DateFormat('MMM dd, yyyy').format(DateTime.now()),
                  style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 20),
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
                    child: pw.Text('Batch', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
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
                      child: pw.Text(
                        student['batchName'] as String? ?? '',
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
    final batchName = studentData['batch_name'] as String? ?? '';
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

    final Map<String, List<Map<String, dynamic>>> subjectAttendance = {};
    final List<Map<String, dynamic>> dailyAttendance = [];

    for (final data in attendanceDocs) {
      final date = data['attendance_date']?.toString() ?? '';
      final status = _statusFromRow(data);
      final subj = _subjectFromRow(data) ?? 'Unknown';
      final add = _additional(data['additional']);
      final created = parseAnyTimestamp(data['created_at']);
      final typ = data['type'] as String? ?? 'entry';
      DateTime? entryTime;
      DateTime? exitTime;
      if (typ == 'entry') {
        entryTime = created;
      } else {
        exitTime = created;
      }

      dailyAttendance.add({
        'date': date,
        'status': status,
        'subject': subj,
        'timestamp': created,
        'entryTime': entryTime,
        'exitTime': exitTime,
        'hours': (add['hours'] as num?)?.toDouble(),
        'lectures': add['lectures'] is Map ? Map<String, dynamic>.from((add['lectures'] as Map).cast<String, dynamic>()) : <String, dynamic>{},
        'type': typ,
      });

      subjectAttendance.putIfAbsent(subj, () => []);
      subjectAttendance[subj]!.add({
        'date': date,
        'status': status,
        'timestamp': created,
      });
    }

    dailyAttendance.sort((a, b) {
      final da = a['date'] as String? ?? '';
      final db = b['date'] as String? ?? '';
      return da.compareTo(db);
    });

    final totalLectures = dailyAttendance.length;
    final presentCount = dailyAttendance.where((a) => a['status'] == 'present').length;
    final absentCount = dailyAttendance.where((a) => a['status'] == 'absent').length;
    final percentage = totalLectures > 0 ? (presentCount / totalLectures * 100) : 0.0;

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
                    if (batchName.isNotEmpty)
                      pw.Text(
                        'Batch: $batchName',
                        style: pw.TextStyle(fontSize: 14, color: PdfColors.grey700),
                      ),
                    pw.SizedBox(height: 8),
                    pw.Text(
                      '${DateFormat('MMM dd, yyyy').format(startDate)} - ${DateFormat('MMM dd, yyyy').format(endDate)}',
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
                      'Total Lectures',
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
              ],
            ),
          ),
          pw.SizedBox(height: 30),
          pw.Text(
            'Subject-wise Attendance',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 10),
          ...subjectAttendance.entries.map((entry) {
            final subject = entry.key;
            final records = entry.value;
            final subjectTotal = records.length;
            final subjectPresent = records.where((r) => r['status'] == 'present').length;
            final subjectPercentage = subjectTotal > 0 ? (subjectPresent / subjectTotal * 100) : 0.0;

            return pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 12),
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300),
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        subject,
                        style: pw.TextStyle(
                          fontSize: 14,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text(
                        '$subjectPresent/$subjectTotal (${subjectPercentage.toStringAsFixed(1)}%)',
                        style: pw.TextStyle(
                          fontSize: 12,
                          color: subjectPercentage >= 75 ? PdfColors.green700 : PdfColors.red700,
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 8),
                  pw.Text(
                    'Attended: $subjectPresent | Total: $subjectTotal',
                    style: pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
                  ),
                ],
              ),
            );
          }),
          pw.SizedBox(height: 20),
          pw.Text(
            'Daily Attendance Details',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 10),
          if (dailyAttendance.isEmpty)
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
                      child: pw.Text('Entry Time', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text('Exit Time', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text('Hours', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text('Lectures', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text('Status', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    ),
                  ],
                ),
                ...dailyAttendance.map((record) {
                  final date = record['date'] as String;
                  final status = record['status'] as String;
                  final entryTime = record['entryTime'] as DateTime?;
                  final exitTime = record['exitTime'] as DateTime?;
                  final lectures = record['lectures'] as Map<String, dynamic>? ?? {};

                  var entryTimeStr = '-';
                  if (entryTime != null) {
                    entryTimeStr = DateFormat('hh:mm a').format(entryTime);
                  }

                  var exitTimeStr = '-';
                  if (exitTime != null) {
                    exitTimeStr = DateFormat('hh:mm a').format(exitTime);
                  } else if (status == 'absent') {
                    exitTimeStr = 'No Exit';
                  }

                  var hoursStr = '-';
                  if (entryTime != null && exitTime != null) {
                    final duration = exitTime.difference(entryTime);
                    final hours = duration.inMinutes / 60.0;
                    hoursStr = '${hours.toStringAsFixed(2)} hrs';
                  } else if (record['hours'] != null) {
                    final hours = record['hours'] as double? ?? 0.0;
                    hoursStr = '${hours.toStringAsFixed(2)} hrs';
                  }

                  final markedLectures = lectures.entries.where((e) {
                    final lecture = e.value as Map<String, dynamic>?;
                    return lecture?['marked'] == true;
                  }).length;
                  final totalLec = lectures.length;
                  final lecturesStr = totalLec > 0 ? '$markedLectures/$totalLec' : '-';

                  return pw.TableRow(
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(
                          DateFormat('MMM dd, yyyy').format(DateTime.parse(date)),
                          style: const pw.TextStyle(fontSize: 9),
                        ),
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
                        child: pw.Text(hoursStr, style: const pw.TextStyle(fontSize: 9)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(lecturesStr, style: const pw.TextStyle(fontSize: 9)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(
                          status == 'absent' ? 'Absent' : (status == 'pending' ? 'Pending' : 'Present'),
                          style: pw.TextStyle(
                            fontSize: 9,
                            color: status == 'absent'
                                ? PdfColors.red700
                                : (status == 'pending' ? PdfColors.orange700 : PdfColors.green700),
                          ),
                        ),
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
