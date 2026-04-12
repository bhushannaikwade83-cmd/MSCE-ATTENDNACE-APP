import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/app_db.dart';
import '../../core/time_parse.dart';
import '../../core/utils/responsive.dart';
import '../widgets/secure_network_image.dart';
import '../../services/b2b_storage_service.dart';

class TeacherAttendanceScreen extends StatefulWidget {
  static const routeName = '/teacher-attendance';
  const TeacherAttendanceScreen({super.key});

  @override
  State<TeacherAttendanceScreen> createState() => _TeacherAttendanceScreenState();
}

class _TeacherAttendanceScreenState extends State<TeacherAttendanceScreen> {
  final String _todayDateId = DateTime.now().toString().split(' ')[0];
  Map<String, dynamic> _attendanceMap = {};
  bool _isLoading = true;
  final Map<String, bool> _uploadingStates = {};
  String? _instituteId;

  late FaceDetector _faceDetector;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _faceDetector = FaceDetector(
        options: FaceDetectorOptions(
          enableContours: false,
          enableClassification: false,
          performanceMode: FaceDetectorMode.fast,
        ),
      );
    }
    _loadInstitute();
  }

  Future<void> _loadInstitute() async {
    final u = appDb.auth.currentUser;
    if (u == null) {
      setState(() => _isLoading = false);
      return;
    }
    final p = await appDb.from('profiles').select('institute_id').eq('id', u.id).maybeSingle();
    _instituteId = p?['institute_id'] as String?;
    _fetchTodayAttendance();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _fetchTodayAttendance());
  }

  @override
  void dispose() {
    _poll?.cancel();
    if (!kIsWeb) _faceDetector.close();
    super.dispose();
  }

  Future<void> _fetchTodayAttendance() async {
    try {
      final rows = await appDb.from('teacher_attendance').select().eq('date', _todayDateId);
      final tempMap = <String, dynamic>{};
      for (final r in rows) {
        final m = r as Map<String, dynamic>;
        final sid = m['student_id'] as String?;
        if (sid != null) {
          final payload = (m['payload'] as Map?)?.cast<String, dynamic>() ?? {};
          tempMap[sid] = {
            ...m,
            'status': m['status'],
            'verificationSelfie': m['verification_selfie'],
            'timestamp': parseAnyTimestamp(payload['timestamp'] ?? m['updated_at'] ?? m['created_at']),
          };
        }
      }
      if (mounted) {
        setState(() {
          _attendanceMap = tempMap;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<bool> _isWithinSchoolPremises() async {
    if (kIsWeb) return true;

    try {
      final user = appDb.auth.currentUser;
      if (user == null) {
        if (mounted) _showErrorDialog("Authentication Error", "User not logged in.");
        return false;
      }

      final userDoc = await appDb.from('profiles').select('institute_id').eq('id', user.id).maybeSingle();
      final instituteId = userDoc?['institute_id'] as String?;

      if (instituteId == null || instituteId.isEmpty) {
        if (mounted) _showErrorDialog("Institute Error", "Institute not found. Please contact admin.");
        return false;
      }

      final rows = await appDb.from('gps_settings').select().eq('institute_id', instituteId).limit(1);
      if (rows.isEmpty) {
        if (mounted) {
          _showErrorDialog("GPS Not Configured", "Institute GPS settings not found. Attendance cannot be marked.");
        }
        return false;
      }
      final data = rows.first as Map<String, dynamic>;
      final latitude = (data['latitude'] as num?)?.toDouble();
      final longitude = (data['longitude'] as num?)?.toDouble();
      final radius = (data['radius'] as num?)?.toDouble() ?? 30.0;

      if (latitude == null || longitude == null) {
        if (mounted) _showErrorDialog("GPS Error", "Institute GPS settings incomplete. Contact admin.");
        return false;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) _showErrorDialog("Permission Denied", "Location permission is required.");
          return false;
        }
      }

      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      if (position.isMocked) {
        if (mounted) _showErrorDialog("Fake GPS Detected", "Please turn off Mock Location apps.");
        return false;
      }

      double dist = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        latitude,
        longitude,
      );

      if (dist > radius) {
        if (mounted) {
          _showErrorDialog(
            "Outside Institute",
            "You are ${dist.toStringAsFixed(0)}m away.\nAllowed radius: ${radius.toStringAsFixed(0)}m.\nAttendance can only be marked within the institute premises.",
          );
        }
        return false;
      }
      return true;
    } catch (e) {
      if (mounted) _showErrorDialog("GPS Error", "Location verification failed: ${e.toString()}");
      return false;
    }
  }

  Future<void> _captureAndMarkPresent(String studentId, String studentName) async {
    bool isAllowed = await _isWithinSchoolPremises();
    if (!isAllowed) return;

    final picker = ImagePicker();

    final XFile? photo = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 35,
      maxWidth: 600,
      preferredCameraDevice: CameraDevice.rear,
    );

    if (photo == null) return;

    setState(() => _uploadingStates[studentId] = true);

    try {
      if (!kIsWeb) {
        final inputImage = InputImage.fromFilePath(photo.path);
        final List<Face> faces = await _faceDetector.processImage(inputImage);

        if (faces.isEmpty) {
          if (mounted) _showErrorDialog("No Face Detected", "No person found.\nPlease retake the photo.");
          setState(() => _uploadingStates[studentId] = false);
          return;
        }
      }

      final studRow = await appDb.from('students').select('year,sr_no').eq('id', studentId).maybeSingle();
      final batchYear = (studRow?['year'] as String?)?.isNotEmpty == true ? studRow!['year'] as String : _todayDateId.substring(0, 4);
      final roll = (studRow?['sr_no'] as String?)?.isNotEmpty == true ? studRow!['sr_no'] as String : studentId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').padRight(4, '0').substring(0, 12);

      Uint8List imgBytes = await photo.readAsBytes();

      final up = await B2BStorageService.uploadAttendancePhoto(
        instituteId: _instituteId ?? '',
        batchYear: batchYear,
        rollNumber: roll,
        subject: 'teacher_proof',
        date: _todayDateId,
        photoBytes: imgBytes,
        photoType: 'entry',
      );
      String downloadUrl = up['url'] ?? '';
      if (downloadUrl.isEmpty) throw Exception('Upload failed');

      final docId = '${studentId}_$_todayDateId';
      final ts = DateTime.now().toUtc().toIso8601String();
      await appDb.from('teacher_attendance').upsert({
        'id': docId,
        'institute_id': _instituteId,
        'student_id': studentId,
        'student_name': studentName,
        'date': _todayDateId,
        'status': 'present',
        'verification_selfie': downloadUrl,
        'updated_at': ts,
        'payload': {
          'timestamp': ts,
          'markedBy': 'Teacher',
          'isManual': true,
          'locationVerified': true,
        },
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Verified & Saved!"), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) _showErrorDialog("Error", "Could not verify: $e");
    } finally {
      if (mounted) setState(() => _uploadingStates[studentId] = false);
    }
  }

  Future<void> _markAbsent(String studentId, String studentName) async {
    final docId = '${studentId}_$_todayDateId';
    final ts = DateTime.now().toUtc().toIso8601String();
    await appDb.from('teacher_attendance').upsert({
      'id': docId,
      'institute_id': _instituteId,
      'student_id': studentId,
      'student_name': studentName,
      'date': _todayDateId,
      'status': 'absent',
      'updated_at': ts,
      'payload': {
        'timestamp': ts,
        'markedBy': 'Teacher',
        'isManual': true,
      },
    });
  }

  void _viewProofImage(String url, String name, String time) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.blue,
              child: Row(
                children: [
                  const Icon(Icons.verified_user, color: Colors.white),
                  const SizedBox(width: 10),
                  Expanded(child: Text("$name's Proof", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18))),
                  const CloseButton(color: Colors.white),
                ],
              ),
            ),
            Container(
              height: 400,
              color: Colors.black,
              child: SecureNetworkImage(
                imageUrl: url,
                fit: BoxFit.contain,
                placeholder: const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
                errorWidget: const Center(
                  child: Text(
                    "Image Error",
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text("Marked at: $time", textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      ),
    );
  }

  void _showErrorDialog(String title, String content) {
    showDialog(context: context, builder: (ctx) => AlertDialog(title: Text(title), content: Text(content), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("OK"))]));
  }

  Future<List<Map<String, dynamic>>> _loadApprovedStudents() async {
    if (_instituteId == null) return [];
    final rows = await appDb
        .from('students')
        .select()
        .eq('institute_id', _instituteId!)
        .eq('role', 'student')
        .eq('status', 'approved');
    return rows.cast<Map<String, dynamic>>();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Attendance: ${DateFormat('MMM d').format(DateTime.now())}"),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _loadApprovedStudents(),
        builder: (context, snapshot) {
          if (!snapshot.hasData || _isLoading) return const Center(child: CircularProgressIndicator());
          final students = snapshot.data!;
          if (students.isEmpty) return const Center(child: Text("No students found."));

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: students.length,
            itemBuilder: (context, index) {
              final student = students[index];
              final studentId = student['id'] as String;
              final name = student['name'] ?? 'Unknown';
              final hasDevice = student['has_device'] ?? true;

              final record = _attendanceMap[studentId] as Map<String, dynamic>?;
              final status = record != null ? record['status'] as String? : null;
              final selfieUrl = record != null ? record['verificationSelfie'] as String? : null;
              final isUploading = _uploadingStates[studentId] ?? false;

              String time = "Unknown";
              final ts = record != null ? record['timestamp'] as DateTime? : null;
              if (ts != null) {
                time = DateFormat('h:mm a').format(ts.toLocal());
              }

              return Card(
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: hasDevice ? Colors.blue.shade100 : Colors.orange.shade100,
                        child: Icon(hasDevice ? Icons.phone_android : Icons.person_off, color: hasDevice ? Colors.blue : Colors.orange),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            const SizedBox(height: 4),
                            if (isUploading)
                              const Text("Uploading...", style: TextStyle(color: Colors.blue, fontStyle: FontStyle.italic))
                            else if (status == 'present')
                              Text("Present • $time", style: TextStyle(color: Colors.green[700], fontWeight: FontWeight.bold))
                            else if (status == 'absent')
                              Text("Absent", style: TextStyle(color: Colors.red[700], fontWeight: FontWeight.bold))
                            else
                              const Text("Not Marked", style: TextStyle(color: Colors.grey)),
                          ],
                        ),
                      ),
                      if (hasDevice)
                        if (status == 'present' && selfieUrl != null && selfieUrl.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.image_search, color: Colors.blue),
                            tooltip: "View Student's Selfie",
                            onPressed: () => _viewProofImage(selfieUrl, name, time),
                          )
                        else
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(4)),
                            child: const Text("App User", style: TextStyle(fontSize: 10, color: Colors.grey)),
                          )
                      else
                        _buildManualActions(studentId, name, status, selfieUrl, isUploading, time),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildManualActions(String id, String name, String? status, String? selfieUrl, bool isUploading, String time) {
    if (isUploading) return const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2));

    if (status == 'present' && selfieUrl != null && selfieUrl.isNotEmpty) {
      return InkWell(
        onTap: () => _viewProofImage(selfieUrl, name, time),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            border: Border.all(color: Colors.green),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Row(children: [
            Icon(Icons.check_circle, size: 16, color: Colors.green),
            SizedBox(width: 4),
            Text("Proof", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green))
          ]),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(icon: const Icon(Icons.close, color: Colors.red), onPressed: () => _markAbsent(id, name)),
        ElevatedButton.icon(
          onPressed: () => _captureAndMarkPresent(id, name),
          icon: const Icon(Icons.camera_alt, size: 16),
          label: const Text("Proof"),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
        ),
      ],
    );
  }
}
