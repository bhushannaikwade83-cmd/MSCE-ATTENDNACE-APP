import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode, debugPrint;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:intl/intl.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/app_db.dart';
import '../../core/gps_attendance_constants.dart';
import '../../core/time_parse.dart';
import '../../core/utils/responsive.dart';
import '../widgets/secure_network_image.dart';
import '../../services/b2b_storage_service.dart';
import '../../services/liveness_detection_service.dart';
import '../../services/anti_spoof_service.dart';
import '../../services/image_quality_service.dart';
import '../../services/photo_compression_service.dart';
import '../../services/gps_fence_sample.dart';
import '../../services/photo_verification_service.dart';
import '../../services/liveness_detection_service.dart';
import '../../services/institute_status_service.dart';
import '../widgets/session_monitor.dart';

class AttendanceScreen extends StatefulWidget {
  static const routeName = '/student-attendance';
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  User? get user => appDb.auth.currentUser;

  String _todayDateId = DateTime.now().toString().split(' ')[0];
  Timer? _dayRefreshTimer;

  bool _isLoading = false;
  bool _isMarked = false;

  String? _proofUrl;
  String? _markTime;
  String? _instituteId;
  String _instituteStatus = ''; // 'open', 'closed', 'holiday', or ''
  String? _studentRecordId;  // ✅ Cache student record ID to avoid repeated DB queries

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
    _startDailyRefreshWatcher();
  }

  @override
  void dispose() {
    _dayRefreshTimer?.cancel();
    if (!kIsWeb) _faceDetector.close();
    super.dispose();
  }

  String _currentDateId() => DateTime.now().toString().split(' ')[0];

  void _startDailyRefreshWatcher() {
    _dayRefreshTimer?.cancel();
    _dayRefreshTimer = Timer.periodic(const Duration(minutes: 1), (_) async {
      if (!mounted) return;
      final nextDateId = _currentDateId();
      if (nextDateId == _todayDateId) return;

      setState(() {
        _todayDateId = nextDateId;
        _isMarked = false;
        _proofUrl = null;
        _markTime = null;
      });

      await _checkStatus();
      await _loadInstituteStatus();
    });
  }

  Future<void> _loadInstituteId() async {
    if (user == null) return;

    setState(() => _isLoading = true);

    final profile = await appDb.from('profiles').select('institute_id,name').eq('id', user!.id).maybeSingle();
    if (!mounted) return;
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
    await _loadInstituteStatus();
  }

  Future<void> _loadInstituteStatus() async {
    if (_instituteId == null) return;
    try {
      final status = await InstituteStatusService().getTodayStatus(_instituteId!);
      if (mounted) setState(() => _instituteStatus = status?['status'] as String? ?? '');
    } catch (_) {}
  }

  Future<void> _checkStatus() async {
    if (user == null || _instituteId == null) return;

    final docId = '${user!.id}_$_todayDateId';

    final row = await appDb.from('teacher_attendance').select().eq('id', docId).maybeSingle();
    if (!mounted) return;

    if (row != null) {
      final payload = (row['payload'] as Map?)?.cast<String, dynamic>() ?? {};
      final ts = parseAnyTimestamp(payload['timestamp'] ?? row['updated_at'] ?? row['created_at']);

      setState(() {
        _isMarked = true;
        _proofUrl = row['verification_selfie'] as String? ?? payload['verificationSelfie'] as String?;
        _markTime = ts != null ? DateFormat('HH:mm').format(ts.toLocal()) : '';
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
      final radius = (data['radius'] as num?)?.toDouble() ?? kAttendanceFenceRadiusMeters;

      if (latitude == null || longitude == null) {
        return false;
      }

      LocationPermission p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) {
        p = await Geolocator.requestPermission();
        if (p == LocationPermission.denied) return false;
      }

      final sample = await samplePositionAgainstFence(
        fenceLat: latitude,
        fenceLng: longitude,
        radiusMeters: radius,
      );

      if (sample.mockedDetected) return false;
      if (sample.errorMessage != null) return false;
      return sample.isWithinFence;
    } catch (_) {
      return false;
    }
  }

  Future<void> _markAttendance() async {
    if (user == null || _instituteId == null) return;

    setState(() => _isLoading = true);

    // Check institute is open before allowing attendance
    final todayStatus = await InstituteStatusService().getTodayStatus(_instituteId!);
    if (!mounted) return;
    final instStatus = todayStatus?['status'] as String? ?? '';
    if (instStatus == 'holiday') {
      _showError("Holiday", "Today is a holiday. Attendance is not counted on holidays.");
      setState(() => _isLoading = false);
      return;
    }
    if (instStatus != 'open') {
      _showError("Institute Not Open",
          instStatus == 'closed'
              ? "The institute is closed for today. Attendance cannot be marked."
              : "The institute has not been opened yet. Please wait for the admin to open it.");
      setState(() => _isLoading = false);
      return;
    }

    if (!kIsWeb) {
      final ok = await _checkLocation();
      if (!mounted) return;
      if (!ok) {
        _showError("Location Error", "You are outside the allowed radius (15 m). Attendance can only be marked within the institute zone.");
        setState(() => _isLoading = false);
        return;
      }
    }

    // Suppress PIN lock while camera is open
    SessionMonitor.beginSuppressResumeLock();
    try {
      final picker = ImagePicker();
      final XFile? photo = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 40,
        preferredCameraDevice: CameraDevice.front,
      );

      if (!mounted) return;
      if (photo == null) {
        setState(() => _isLoading = false);
        return;
      }

      if (!kIsWeb) {
        // Phase 2: Real-time Advanced Verification

        // Step 1: Check face detection
        if (kDebugMode) debugPrint('🔍 Step 1: Detecting face...');
        setState(() => _isLoading = true);
        final faces = await _faceDetector.processImage(InputImage.fromFilePath(photo.path));
        if (!mounted) return;
        if (faces.isEmpty) {
          _showError("Face Error", "No face detected. Make sure your face is visible in the camera.");
          setState(() => _isLoading = false);
          return;
        }

        // Step 2: Check image quality
        if (kDebugMode) debugPrint('📊 Step 2: Checking image quality...');
        setState(() => _isLoading = true);
        final qualityResult = await ImageQualityService.checkQuality(photo.path);
        if (!qualityResult.isGood) {
          _showError(
            "📸 Image Quality Issues",
            '${qualityResult.reason}\n\nEnsure:\n• Good lighting\n• Face is clear\n• No blur',
          );
          setState(() => _isLoading = false);
          return;
        }
        if (kDebugMode) {
          debugPrint('✅ Quality check passed (Brightness: ${qualityResult.brightness}, Sharpness: ${qualityResult.sharpness})');
        }

        // Step 3: Check liveness (blink detection)
        if (kDebugMode) debugPrint('👁️ Step 3: Checking liveness (blink)...');
        setState(() => _isLoading = true);
        final isBlinking = await LivenessDetectionService.isBlinking(photo.path);
        if (!isBlinking) {
          _showError(
            "👁️ Blink Not Detected",
            "You must blink naturally for attendance. This prevents using printed photos or videos.",
          );
          setState(() => _isLoading = false);
          return;
        }
        if (kDebugMode) debugPrint('✅ Liveness check passed');

        // Step 4: Check anti-spoof (real face vs printed/screen)
        if (kDebugMode) debugPrint('🔍 Step 4: Checking anti-spoof...');
        setState(() => _isLoading = true);
        final antiSpoofResult = await AntiSpoofService.checkSpoof(photo.path);
        if (!antiSpoofResult.isReal) {
          _showError(
            "❌ Spoofing Detected",
            '${antiSpoofResult.reason}\n\nPlease use your real face, not a photo or screen.',
          );
          setState(() => _isLoading = false);
          return;
        }
        if (kDebugMode) {
          debugPrint('✅ Anti-spoof check passed (${(antiSpoofResult.confidence * 100).toStringAsFixed(1)}%)');
        }

        // Step 5: Compress photo to 50-100KB
        if (kDebugMode) debugPrint('🗜️ Step 5: Compressing photo...');
        setState(() => _isLoading = true);
        final compressResult = await PhotoCompressionService.compressAndValidate(photo.path);
        if (!compressResult.isValid) {
          _showError(
            "🗜️ Compression Failed",
            '${compressResult.reason}\n\nPlease retake the photo.',
          );
          setState(() => _isLoading = false);
          return;
        }
        if (kDebugMode) {
          debugPrint('✅ Photo compressed: ${compressResult.sizeKB.toStringAsFixed(1)} KB');
        }
      }

      // ✅ Detect photo angle (LEFT, FRONT, RIGHT)
      setState(() => _isLoading = true);
      final detectedAngle = await _detectPhotoAngle(photo.path);
      if (!mounted) return;
      setState(() => _isLoading = false);

      // ✅ Show angle confirmation dialog with success/retake options
      final shouldConfirm = await _showAngleConfirmationDialog(detectedAngle, photo.path);
      if (!mounted) return;

      if (!shouldConfirm) {
        // User clicked "Retake" - restart attendance marking
        setState(() => _isLoading = false);
        return _markAttendance();  // Recursively call to retake
      }

      // ✅ User confirmed - proceed with attendance marking
      setState(() => _isLoading = true);

      final bytes = await photo.readAsBytes();

      final profile = await appDb.from('profiles').select('name').eq('id', user!.id).maybeSingle();
      final name = profile?['name'] as String? ?? 'Student';
      final rollKey = user!.id.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').padRight(4, '0').substring(0, 8);

      final up = await B2BStorageService.uploadAttendancePhoto(
        instituteId: _instituteId!,
        folderYear: _todayDateId.substring(0, 4),
        rollNumber: rollKey,
        subject: 'self_attendance',
        date: _todayDateId,
        photoBytes: bytes,
        photoType: 'entry',
      );
      final photoUrl = up['url'] ?? '';

      final docId = '${user!.id}_$_todayDateId';
      final ts = DateTime.now().toUtc().toIso8601String();

      // ✅ Store in teacher_attendance (main attendance record)
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
          'detectedAngle': detectedAngle,  // ✅ Store detected angle
        },
      });

      // ✅ Also store in attendance_in_out table (for entry/exit photo display)
      try {
        if (kDebugMode) {
          debugPrint('📸 Starting attendance_in_out storage...');
        }

        // ✅ Use cached student record ID (avoid repeated DB queries)
        String studentRecordId = _studentRecordId ?? '';

        if (kDebugMode) {
          debugPrint('   Cached student record ID: ${studentRecordId.isEmpty ? "EMPTY" : studentRecordId}');
          debugPrint('   User: ${user != null ? user!.id : "NULL"}');
        }

        if (studentRecordId.isEmpty && user != null) {
          // Only query if not cached yet
          if (kDebugMode) {
            debugPrint('   Querying students table for user_id: ${user!.id}');
          }

          final studentRecord = await appDb
              .from('students')
              .select('id')
              .eq('user_id', user!.id)
              .maybeSingle();

          if (studentRecord != null) {
            studentRecordId = studentRecord['id']?.toString() ?? '';
            _studentRecordId = studentRecordId;  // ✅ Cache for future use
            if (kDebugMode) {
              debugPrint('   ✅ Found student record with ID: $studentRecordId');
            }
          } else {
            if (kDebugMode) {
              debugPrint('   ❌ NO student record found for user_id: ${user!.id}');
            }
          }
        }

        if (studentRecordId.isNotEmpty) {
            final timestamp = DateTime.now();
            final timestampStr = timestamp.toString().replaceAll(RegExp(r'[^0-9]'), '').substring(0, 14);
            final uniqueId = 'entry_$timestampStr';

            final attendanceDateObj = DateTime.parse(_todayDateId);
            final year = attendanceDateObj.year;

            final inOutRecord = {
              'student_id': studentRecordId,  // ✅ FIX: Use student record ID, not auth ID
              'student_name': name,
              'sr_no': rollKey,
              'institute_code': _instituteId,
              'attendance_date': _todayDateId,
              'type': 'entry',
              'photo_url': photoUrl,
              'year': year,
              'unique_id': uniqueId,
              'photo_path': null,
              'photo_file_id': null,
              'created_at': ts,
              'additional': {
                'entryTime': ts,
                'detectedAngle': detectedAngle,
                'markedBy': 'Student',
                'status': 'present',
              },
            };

            if (kDebugMode) {
              debugPrint('   📝 Inserting record: student_id=$studentRecordId, sr_no=$rollKey, type=entry');
            }

            await appDb.from('attendance_in_out').insert(inOutRecord);

            if (kDebugMode) {
              debugPrint('✅ Attendance photo stored in attendance_in_out table');
              debugPrint('   Student Record ID: $studentRecordId');
              debugPrint('   Student Name: $name');
              debugPrint('   Date: $_todayDateId');
              debugPrint('   Photo URL: $photoUrl');
            }
          } else {
            if (kDebugMode) {
              debugPrint('⚠️ SKIPPED: Student record ID is empty!');
              debugPrint('   User: ${user != null ? user!.id : "NULL"}');
              debugPrint('   Cached ID: $_studentRecordId');
            }
          }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⚠️ Warning: Could not store in attendance_in_out: $e');
          debugPrint('   Student Record ID: $_studentRecordId');
          debugPrint('   Error details: ${e.toString()}');
        }
        // Don't fail attendance marking if in_out storage fails
      }

      await _checkStatus();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("✅ Attendance Marked Successfully ($detectedAngle)"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      _showError("Error", e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
      SessionMonitor.endSuppressResumeLock();
    }
  }

  /// Detect the angle of the face in the photo (LEFT, FRONT, RIGHT)
  Future<String> _detectPhotoAngle(String photoPath) async {
    try {
      if (kIsWeb) return 'FRONT';  // Default to front on web

      final faces = await _faceDetector.processImage(
        InputImage.fromFilePath(photoPath),
      );

      if (faces.isEmpty) return 'UNKNOWN';

      final face = faces.first;

      // Try to get head euler angles for rotation detection
      double? yaw = face.headEulerAngleY;
      yaw ??= face.headEulerAngleZ;  // Fallback to Z if Y not available

      if (kDebugMode) {
        debugPrint('📐 Face angle detection:');
        debugPrint('   headEulerAngleY: ${face.headEulerAngleY}');
        debugPrint('   headEulerAngleZ: ${face.headEulerAngleZ}');
        debugPrint('   headEulerAngleX: ${face.headEulerAngleX}');
        debugPrint('   Using angle value: $yaw');
      }

      // If we have a valid yaw angle, classify based on rotation
      if (yaw != null) {
        // LEFT 45°: yaw > 20
        // FRONT: -20 <= yaw <= 20
        // RIGHT 45°: yaw < -20

        if (yaw > 20) {
          return 'LEFT 45°';
        } else if (yaw < -20) {
          return 'RIGHT 45°';
        } else {
          return 'FRONT';
        }
      }

      // Fallback: Analyze face position and landmark distribution
      // If left side of face has more space, it's a right profile
      // If right side of face has more space, it's a left profile
      try {
        final bounds = face.boundingBox;
        final landmarks = face.landmarks;

        if (landmarks.isNotEmpty) {
          final leftEye = landmarks[FaceLandmarkType.leftEye];
          final rightEye = landmarks[FaceLandmarkType.rightEye];

          if (leftEye != null && rightEye != null) {
            final eyeDistance = (rightEye.position.x - leftEye.position.x).abs();
            final faceWidth = bounds.width;

            // If eyes are significantly asymmetric, it's a profile
            if (eyeDistance < faceWidth * 0.3) {
              // Eyes are close together - profile view
              if (leftEye.position.x < rightEye.position.x) {
                return 'RIGHT 45°';  // Right eye more visible = looking left
              } else {
                return 'LEFT 45°';   // Left eye more visible = looking right
              }
            }
          }
        }
      } catch (e) {
        if (kDebugMode) debugPrint('⚠️ Landmark analysis failed: $e');
      }

      // Default to FRONT if we can't determine angle
      return 'FRONT';

    } catch (e) {
      if (kDebugMode) debugPrint('❌ Angle detection error: $e');
      return 'UNKNOWN';
    }
  }

  /// Show dialog with detected angle and allow confirm/retake
  Future<bool> _showAngleConfirmationDialog(String detectedAngle, String photoPath) async {
    if (!mounted) return false;

    final isUnknown = detectedAngle == 'UNKNOWN';
    final iconColor = isUnknown ? Colors.orange : Colors.blue;

    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(
          isUnknown ? '⚠️ Angle Not Detected' : '📸 Photo Angle Detected',
          style: TextStyle(
            color: isUnknown ? Colors.orange : Colors.blue,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isUnknown ? Colors.orange.shade50 : Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isUnknown ? Colors.orange.shade200 : Colors.blue.shade200,
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    isUnknown
                        ? Icons.help_outline_rounded
                        : detectedAngle == 'LEFT 45°'
                            ? Icons.rotate_right_rounded
                            : detectedAngle == 'RIGHT 45°'
                                ? Icons.rotate_left_rounded
                                : Icons.face_rounded,
                    size: 48,
                    color: isUnknown ? Colors.orange.shade700 : Colors.blue.shade700,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    detectedAngle,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isUnknown ? Colors.orange.shade700 : Colors.blue.shade700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (isUnknown)
              const Text(
                'Could not clearly detect face angle.\n\n'
                'Tips:\n'
                '• Ensure face is clearly visible\n'
                '• Use good lighting\n'
                '• Face the camera directly or turn head 45°\n'
                '• You can still confirm and mark attendance',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 13),
              )
            else
              Text(
                'Your photo shows $detectedAngle.\n\n'
                'Click "Confirm" to mark attendance\nor "Retake" for a different angle.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('🔄 Retake'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: isUnknown ? Colors.orange : Colors.blue,
            ),
            child: Text(
              isUnknown ? '✅ Mark Anyway' : '✅ Confirm & Mark',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    ) ?? false;
  }

  void _showError(String title, String msg) {
    if (!mounted) return;
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
  Widget _buildInstituteStatusBanner() {
    Color bgColor;
    Color textColor = Colors.white;
    IconData icon;
    String message;

    switch (_instituteStatus) {
      case 'open':
        bgColor = Colors.green.shade600;
        icon = Icons.domain_verification_rounded;
        message = '✅ Institute is Open — Attendance is being tracked today.';
        break;
      case 'holiday':
        bgColor = Colors.orange.shade600;
        icon = Icons.beach_access_rounded;
        message = '🏖️ Today is a Holiday — Attendance is not counted.';
        break;
      case 'closed':
        bgColor = Colors.red.shade600;
        icon = Icons.domain_disabled_rounded;
        message = '🔴 Institute is Closed — Attendance cannot be marked.';
        break;
      default:
        bgColor = Colors.grey.shade600;
        icon = Icons.info_outline_rounded;
        message = '⚠️ Institute status not set. Contact your admin.';
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: textColor, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
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
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(height: 20),
                          // Institute status banner
                          if (_instituteStatus.isNotEmpty)
                            _buildInstituteStatusBanner(),
                          const SizedBox(height: 30),
                          ElevatedButton.icon(
                            onPressed: _instituteStatus == 'open' ? _markAttendance : null,
                            icon: const Icon(Icons.camera_alt),
                            label: Text(_instituteStatus == 'holiday'
                                ? 'Holiday — No Attendance'
                                : _instituteStatus == 'closed'
                                    ? 'Institute Closed'
                                    : _instituteStatus == 'open'
                                        ? 'Mark Attendance'
                                        : 'Waiting for Institute to Open'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 32,
                                vertical: 16,
                              ),
                            ),
                          ),
                          const SizedBox(height: 40),
                        ],
                      ),
              ),
      ),
    );
  }
}
