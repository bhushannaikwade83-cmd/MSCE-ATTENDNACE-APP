import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:intl/intl.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/app_db.dart';
import '../../core/time_parse.dart';
import '../../core/utils/responsive.dart';
import '../widgets/secure_network_image.dart';
import '../../services/b2b_storage_service.dart';

class AttendanceScreen extends StatefulWidget {
  static const routeName = '/student-attendance';
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  User? get user => appDb.auth.currentUser;

  final String _todayDateId = DateTime.now().toString().split(' ')[0];

  bool _isLoading = false;
  bool _isMarked = false;

  String? _proofUrl;
  String? _markTime;
  String? _instituteId;

  late FaceDetector _faceDetector;

  @override
  void initState() {
    super.initState();

    if (!kIsWeb) {
      _faceDetector = FaceDetector(
        options: FaceDetectorOptions(
          performanceMode: FaceDetectorMode.fast,
        ),
      );
    }

    _loadInstituteId();
  }

  @override
  void dispose() {
    if (!kIsWeb) _faceDetector.close();
    super.dispose();
  }

  Future<void> _loadInstituteId() async {
    if (user == null) return;

    setState(() => _isLoading = true);

    final profile = await appDb.from('profiles').select('institute_id,name').eq('id', user!.id).maybeSingle();
    final iid = profile?['institute_id'] as String?;
    if (iid != null && iid.isNotEmpty) {
      _instituteId = iid;
    }

    if (_instituteId == null) {
      _showError("Access Denied", "Institute not linked with this account.");
      setState(() => _isLoading = false);
      return;
    }

    await _checkStatus();
  }

  Future<void> _checkStatus() async {
    if (user == null || _instituteId == null) return;

    final docId = '${user!.id}_$_todayDateId';

    final row = await appDb.from('teacher_attendance').select().eq('id', docId).maybeSingle();

    if (row != null) {
      final payload = (row['payload'] as Map?)?.cast<String, dynamic>() ?? {};
      final ts = parseAnyTimestamp(payload['timestamp'] ?? row['updated_at'] ?? row['created_at']);

      setState(() {
        _isMarked = true;
        _proofUrl = row['verification_selfie'] as String? ?? payload['verificationSelfie'] as String?;
        _markTime = ts != null ? DateFormat('h:mm a').format(ts.toLocal()) : '';
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<bool> _checkLocation() async {
    try {
      final rows = await appDb.from('gps_settings').select().eq('institute_id', _instituteId!).limit(1);
      if (rows.isEmpty) {
        return false;
      }
      final data = rows.first as Map<String, dynamic>;
      final latitude = (data['latitude'] as num?)?.toDouble();
      final longitude = (data['longitude'] as num?)?.toDouble();
      final radius = (data['radius'] as num?)?.toDouble() ?? 30.0;

      if (latitude == null || longitude == null) {
        return false;
      }

      LocationPermission p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) {
        p = await Geolocator.requestPermission();
        if (p == LocationPermission.denied) return false;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      if (pos.isMocked) return false;

      final distance = Geolocator.distanceBetween(
        pos.latitude,
        pos.longitude,
        latitude,
        longitude,
      );

      return distance <= radius;
    } catch (_) {
      return false;
    }
  }

  Future<void> _markAttendance() async {
    if (user == null || _instituteId == null) return;

    setState(() => _isLoading = true);

    if (!kIsWeb) {
      final ok = await _checkLocation();
      if (!ok) {
        _showError("Location Error", "You are outside the 30-meter radius. Attendance can only be marked within the institute premises.");
        setState(() => _isLoading = false);
        return;
      }
    }

    final picker = ImagePicker();
    final XFile? photo = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 40,
      preferredCameraDevice: CameraDevice.front,
    );

    if (photo == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      if (!kIsWeb) {
        final faces = await _faceDetector.processImage(InputImage.fromFilePath(photo.path));
        if (faces.isEmpty) {
          _showError("Face Error", "No face detected.");
          setState(() => _isLoading = false);
          return;
        }
      }

      final bytes = await photo.readAsBytes();

      final profile = await appDb.from('profiles').select('name').eq('id', user!.id).maybeSingle();
      final name = profile?['name'] as String? ?? 'Student';
      final rollKey = user!.id.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').padRight(4, '0').substring(0, 8);

      final up = await B2BStorageService.uploadAttendancePhoto(
        instituteId: _instituteId!,
        batchYear: _todayDateId.substring(0, 4),
        rollNumber: rollKey,
        subject: 'self_attendance',
        date: _todayDateId,
        photoBytes: bytes,
        photoType: 'entry',
      );
      final photoUrl = up['url'] ?? '';

      final docId = '${user!.id}_$_todayDateId';
      final ts = DateTime.now().toUtc().toIso8601String();

      await appDb.from('teacher_attendance').upsert({
        'id': docId,
        'institute_id': _instituteId,
        'student_id': user!.id,
        'student_name': name,
        'date': _todayDateId,
        'status': 'present',
        'verification_selfie': photoUrl,
        'updated_at': ts,
        'payload': {
          'timestamp': ts,
          'markedBy': 'Student',
          'isManual': false,
          'locationVerified': true,
        },
      });

      await _checkStatus();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Attendance Marked Successfully"),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      _showError("Error", e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showError(String title, String msg) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(msg),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Mark Attendance")),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: _isMarked
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(height: 40),
                          const Icon(Icons.check_circle, size: 90, color: Colors.green),
                          const SizedBox(height: 20),
                          Text("Present", style: Theme.of(context).textTheme.headlineMedium),
                          Text("Marked at $_markTime"),
                          const SizedBox(height: 20),
                          if (_proofUrl != null && _proofUrl!.isNotEmpty)
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxHeight: MediaQuery.of(context).size.height * 0.4,
                                maxWidth: MediaQuery.of(context).size.width * 0.8,
                              ),
                              child: SecureNetworkImage(
                                imageUrl: _proofUrl!,
                                height: 200,
                                fit: BoxFit.contain,
                              ),
                            ),
                          const SizedBox(height: 40),
                        ],
                      )
                    : Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: ElevatedButton.icon(
                            onPressed: _markAttendance,
                            icon: const Icon(Icons.camera_alt),
                            label: const Text("Mark Attendance"),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 32,
                                vertical: 16,
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
      ),
    );
  }
}
