import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint, kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_db.dart';
import '../../core/time_parse.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:image/image.dart' as img;
import '../../services/batch_service.dart';
import '../../services/storage_service.dart';
import '../../services/device_fingerprint_service.dart';
import '../../services/photo_verification_service.dart';
import '../../services/network_verification_service.dart';
import '../../services/suspicious_activity_service.dart';
import '../../services/firestore_retry_service.dart';
import '../../services/geofence_service.dart';
// Face recognition enabled - mandatory security
import '../../services/face_recognition_service.dart';
import '../../services/arcface_backend_service.dart';
import '../../services/liveness_detection_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/professional_messaging.dart';
import 'help_desk_screen.dart';
import '../widgets/secure_network_image.dart';
// import '../widgets/face_scanner_widget.dart';

class AdminAttendanceScreen extends StatefulWidget {
  static const routeName = '/admin-attendance';
  const AdminAttendanceScreen({super.key});

  @override
  State<AdminAttendanceScreen> createState() => _AdminAttendanceScreenState();
}

class _AdminAttendanceScreenState extends State<AdminAttendanceScreen> with TickerProviderStateMixin {
  SupabaseClient get _db => appDb;

  String _teacherAttendanceId(String roll, String date) => '${instituteId}_${roll}_$date';

  Future<Map<String, dynamic>?> _getTeacherAttendanceDoc(String roll, String date) async {
    if (instituteId == null) return null;
    final row = await _db.from('teacher_attendance').select().eq('id', _teacherAttendanceId(roll, date)).maybeSingle();
    if (row == null) return null;
    final p = row['payload'];
    if (p is Map<String, dynamic>) return Map<String, dynamic>.from(p);
    if (p is Map) return p.map((k, v) => MapEntry(k.toString(), v));
    return <String, dynamic>{};
  }

  Future<void> _upsertTeacherAttendanceDoc({
    required String roll,
    required String date,
    required Map<String, dynamic> payload,
    String? status,
  }) async {
    if (instituteId == null) return;
    final now = DateTime.now().toUtc().toIso8601String();
    final id = _teacherAttendanceId(roll, date);
    await _db.from('teacher_attendance').upsert(
      {
        'id': id,
        'institute_id': instituteId,
        'student_id': roll,
        'date': date,
        'status': status ?? payload['status']?.toString(),
        'payload': payload,
        'updated_at': now,
      },
      onConflict: 'id',
    );
  }

  dynamic _encodeSv() => DateTime.now().toUtc().toIso8601String();

  DateTime? _asDateTime(dynamic v) => parseAnyTimestamp(v);
  final picker = ImagePicker();
  final BatchService _batchService = BatchService();
  final GeofenceService _geofenceService = GeofenceService();

  String? instituteId;
  Map<String, dynamic>? selectedBatch;
  String? selectedSubject;
  String? selectedTiming;
  String? selectedRollNumber;
  List<String> studentEnrolledSubjects = []; // Store student's enrolled subjects
  String? selectedLectureNumber; // For multiple lectures (e.g., "Lecture 1", "Lecture 2", "Lecture 3")
  bool isEntryPhoto = true; // true = entry photo, false = exit photo
  String? attendanceMode; // 'entry', 'exit', or 'lecture_scan'
  int? currentLectureIndex; // Index of current lecture being scanned

  bool isLoading = false;
  bool isLocationValid = false;
  bool? isAlreadyMarked; // null = not checked, true = already marked, false = not marked
  String? existingMarkTime;
  Map<String, dynamic>? existingAttendanceData; // Store existing attendance to check entry/exit

  List<Map<String, dynamic>> batches = [];
  List<String> students = [];
  List<String> filteredStudents = []; // For search
  bool isLoadingBatches = false;
  final TextEditingController _searchController = TextEditingController();
  
  Timer? _autoMarkAbsentTimer; // Timer for periodic auto-mark absent check

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOut),
    );
    _fadeController.forward();
    _init();
  }

  @override
  void dispose() {
    _autoMarkAbsentTimer?.cancel();
    _fadeController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    await _loadInstitute();
    await _loadBatches();
    await _loadStudentsForBatch(); // Load all students (flexible attendance)
    await _checkLocation();
    // Check for missing exit photos and mark as absent
    _checkAndMarkMissingExits();
    // Schedule periodic check every 15 minutes
    _startAutoMarkAbsentTimer();
  }
  
  /// Start periodic timer to check and mark absent students after institute hours
  void _startAutoMarkAbsentTimer() {
    // Cancel existing timer if any
    _autoMarkAbsentTimer?.cancel();
    
    // Check immediately, then every 15 minutes
    _autoMarkAbsentTimer = Timer.periodic(const Duration(minutes: 15), (timer) {
      _checkAndMarkMissingExits();
    });
  }

  /// Check for students who took entry photo but didn't take exit photo
  /// Mark them as absent automatically after institute hours complete
  Future<void> _checkAndMarkMissingExits() async {
    if (instituteId == null) return;

    try {
      final instituteRow = await _db.from('institutes').select('batch_close_time').eq('id', instituteId!).maybeSingle();
      if (instituteRow == null) return;

      final closeTimeRaw = instituteRow['batch_close_time'];
      Map<String, dynamic>? closeTimeData;
      if (closeTimeRaw is Map<String, dynamic>) {
        closeTimeData = closeTimeRaw;
      } else if (closeTimeRaw is Map) {
        closeTimeData = closeTimeRaw.map((k, v) => MapEntry(k.toString(), v));
      }
      
      if (closeTimeData == null) {
        if (kDebugMode) debugPrint('⚠️ Institute close time not set');
        return;
      }
      
      final closeHour = closeTimeData['hour'] as int? ?? 22;
      final closeMinute = closeTimeData['minute'] as int? ?? 0;
      final closeTime = TimeOfDay(hour: closeHour, minute: closeMinute);
      
      // Calculate close time in minutes (add 30 minutes buffer after close time)
      final closeMinutes = closeTime.hour * 60 + closeTime.minute;
      final bufferMinutes = 30; // 30 minutes buffer after institute closes
      final finalCloseTime = closeMinutes + bufferMinutes;
      
      final currentTime = DateTime.now();
      final currentMinutes = currentTime.hour * 60 + currentTime.minute;
      
      // Only check if institute hours have passed (current time > close time + buffer)
      if (currentMinutes <= finalCloseTime) {
        if (kDebugMode) {
          debugPrint('⏰ Institute hours not complete yet. Close time: ${closeTime.hour}:${closeTime.minute.toString().padLeft(2, '0')} (+30 min buffer)');
        }
        return;
      }
      
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      
      final rows = await _db.from('teacher_attendance').select().eq('institute_id', instituteId!).eq('date', today);

      int markedCount = 0;

      for (final row in rows) {
        final data = row['payload'];
        Map<String, dynamic> map;
        if (data is Map<String, dynamic>) {
          map = Map<String, dynamic>.from(data);
        } else if (data is Map) {
          map = data.map((k, v) => MapEntry(k.toString(), v));
        } else {
          continue;
        }
        final hasEntry = map['entryPhoto'] != null || map['entryTime'] != null || map['photoUrl'] != null;
        final hasExit = map['exitPhoto'] != null || map['exitTime'] != null;
        final status = map['status'] as String?;

        if (hasEntry && !hasExit && status != 'absent') {
          map['status'] = 'absent';
          map['absentReason'] = 'No exit photo - automatically marked absent after institute hours completed';
          map['markedAbsentAt'] = _encodeSv();
          map['autoMarkedAfterCloseTime'] = true;
          map['instituteCloseTime'] =
              '${closeTime.hour.toString().padLeft(2, '0')}:${closeTime.minute.toString().padLeft(2, '0')}';

          await _db.from('teacher_attendance').update({
            'payload': map,
            'status': 'absent',
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          }).eq('id', row['id'] as String);

          markedCount++;

          if (kDebugMode) {
            final rollNumber = map['rollNumber'] ?? 'unknown';
            debugPrint('⚠️ Auto-marked absent: Roll $rollNumber (no exit photo after institute hours)');
          }
        }
      }
      
      if (markedCount > 0 && kDebugMode) {
        debugPrint('✅ Auto-marked $markedCount students as absent after institute hours completed');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error checking missing exits: $e');
    }
  }

  Future<void> _loadBatches() async {
    if (instituteId == null) return;

    setState(() => isLoadingBatches = true);
    try {
      final loadedBatches = await _batchService.getBatches(instituteId!);
      setState(() {
        batches = loadedBatches;
        isLoadingBatches = false;
      });
    } catch (e) {
      setState(() => isLoadingBatches = false);
      if (kDebugMode) debugPrint('Error loading batches: $e');
    }
  }

  /// Fetch student data and auto-populate batch, subject, and timing
  Future<void> _fetchStudentDataAndSetBatch(String rollNumber) async {
    if (instituteId == null) return;

    try {
      final studentRow = await _db
          .from('students')
          .select()
          .eq('institute_id', instituteId!)
          .eq('user_id', rollNumber)
          .maybeSingle();

      if (studentRow == null) {
        if (kDebugMode) debugPrint('⚠️ Student not found: $rollNumber');
        return;
      }

      final studentData = Map<String, dynamic>.from(studentRow);
      final studentBatchId = studentData['batchId'] as String? ?? studentData['batch_id'] as String?;
      final studentBatchIds = studentData['batchIds'] as List<dynamic>? ?? studentData['batch_ids'] as List<dynamic>?;
      final studentSubjects = studentData['subjects'] as List<dynamic>?;
      final studentBatchTiming = studentData['batchTiming'] as String? ?? studentData['batch_timing'] as String?;

      // Get the first batch ID (primary batch or first from batchIds)
      final primaryBatchId = studentBatchId ?? (studentBatchIds?.isNotEmpty == true ? studentBatchIds!.first.toString() : null);
      
      if (primaryBatchId != null) {
        // Find the batch in the loaded batches
        final batch = batches.firstWhere(
          (b) => b['id'] == primaryBatchId,
          orElse: () => <String, dynamic>{},
        );

        if (batch.isNotEmpty) {
          setState(() {
            selectedBatch = batch;
            selectedTiming = studentBatchTiming ?? batch['timing']?.toString();
            
            // Store student's enrolled subjects (all subjects selected for reference)
            if (studentSubjects != null && studentSubjects.isNotEmpty) {
              studentEnrolledSubjects = studentSubjects.map((s) => s.toString()).toList();
              // Select all subjects (for display/reference only, not used for attendance marking)
              selectedSubject = studentEnrolledSubjects.join(', '); // All subjects as comma-separated string
            } else {
              studentEnrolledSubjects = [];
              selectedSubject = null;
              // CRITICAL: Student has 0 subjects - cannot mark attendance
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, color: Colors.white),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '⚠️ Cannot Mark Attendance',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Student with roll number $rollNumber has 0 subjects assigned.\n\n'
                          'Attendance can only be marked for students with at least 1 subject.\n\n'
                          'Please assign subjects to this student first in Batch Management.',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ],
                    ),
                    backgroundColor: Colors.orange,
                    duration: const Duration(seconds: 8),
                  ),
                );
              }
            }
          });
          
          if (kDebugMode) {
            debugPrint('✅ Auto-populated batch for roll $rollNumber: ${batch['name']}');
            debugPrint('   Subject: $selectedSubject');
            debugPrint('   Timing: $selectedTiming');
          }
        } else {
          if (kDebugMode) debugPrint('⚠️ Batch not found in loaded batches: $primaryBatchId');
        }
      } else {
        if (kDebugMode) debugPrint('⚠️ Student has no batch assigned: $rollNumber');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error fetching student data: $e');
    }
  }

  Future<void> _loadStudentsForBatch() async {
    // Flexible attendance: Load ALL students from institute, not just from selected batch
    if (instituteId == null) return;

    setState(() => isLoadingBatches = true);
    try {
      final rows = await _db.from('students').select('user_id').eq('institute_id', instituteId!);

      setState(() {
        students = rows
            .map((r) => r['user_id'] as String? ?? '')
            .where((roll) => roll.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
        filteredStudents = students; // Initialize filtered list
        isLoadingBatches = false;
        isLoading = false;
      });
      
      // Initialize search
      _searchController.addListener(_filterStudents);
    } catch (e) {
      setState(() => isLoading = false);
      if (kDebugMode) debugPrint('Error loading students: $e');
    }
  }

  /* ---------------- INSTITUTE ---------------- */

  Future<void> _loadInstitute() async {
    try {
      final user = _db.auth.currentUser;
      if (user == null) return;

      try {
        final profile = await _db.from('profiles').select('institute_id').eq('id', user.id).maybeSingle();
        final instId = profile?['institute_id'] as String?;
        if (instId != null && instId.isNotEmpty) {
          setState(() {
            instituteId = instId;
          });
          return;
        }
      } catch (e) {
        if (kDebugMode) debugPrint('Error fetching institute from profile: $e');
      }
      try {
        final institutes = await _db.from('institutes').select('id').limit(1);
        if (institutes.isNotEmpty) {
          setState(() {
            instituteId = institutes.first['id'] as String?;
          });
          return;
        }
      } catch (e) {
        if (kDebugMode) debugPrint('Error listing institutes: $e');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error loading institute: $e');
    }
  }

  /* ---------------- LOCATION ---------------- */

  Future<void> _checkLocation() async {
    try {
      LocationPermission p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) {
        p = await Geolocator.requestPermission();
      }
      if (p == LocationPermission.denied ||
          p == LocationPermission.deniedForever) {
        isLocationValid = false;
      } else {
        // First check location lock status
        await _checkLocationLockStatus();
        // Then check if within GPS radius (strict 30m check)
        final withinRadius = await _checkGPSRadius();
        isLocationValid = withinRadius;
      }
    } catch (_) {
      isLocationValid = false;
    }
    setState(() {});
  }

  /// Check location lock status and show appropriate messages
  Future<void> _checkLocationLockStatus() async {
    if (instituteId == null || instituteId!.isEmpty) return;
    final currentUser = _db.auth.currentUser;
    if (currentUser == null) return;

    try {
      final locationStatus = await _geofenceService.checkAdminLocationStatus(
        instituteId: instituteId!,
        adminId: currentUser.id,
      );

      final isLocked = locationStatus['isLocked'] as bool;
      final hasLocation = locationStatus['hasLocation'] as bool;
      final isWithinRadius = locationStatus['isWithinRadius'] as bool?;
      final distance = locationStatus['distance'] as double?;

      // Check radius status (30m is ALWAYS enforced, regardless of lock status)
      if (hasLocation && isWithinRadius != null) {
        if (isWithinRadius == false && distance != null) {
          // Admin is OUT OF RADIUS (more than 30m away) - cannot mark attendance
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '❌ Out of radius: You are ${distance.toStringAsFixed(0)}m away. Attendance can only be marked within 30m of the institute.',
                ),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 6),
              ),
            );
          }
        } else if (isWithinRadius == true) {
          // Admin is WITHIN 30m radius - can mark attendance
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  isLocked 
                      ? '✅ Location is locked - You are within 30m radius. You can mark attendance.'
                      : '✅ Location is unlocked - You are within 30m radius. You can mark attendance.',
                ),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
      } else if (!isLocked && hasLocation && isWithinRadius == null) {
        // Location is unlocked but unable to verify radius
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🔓 Location is unlocked. Unable to verify your distance from institute.'),
              backgroundColor: Colors.blue,
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error checking location lock status: $e');
      // Don't block if check fails
    }
  }

  /// STRICT GPS RADIUS CHECK - Must be within 30m, no buffer
  /// Uses admin's own GPS settings (cross-device locking)
  Future<bool> _checkGPSRadius() async {
    if (kIsWeb) return true; // Web bypass for testing
    
    if (instituteId == null || instituteId!.isEmpty) {
      return false;
    }

    final currentUser = _db.auth.currentUser;
    if (currentUser == null) {
      return false;
    }

    try {
      final configRow = await _db
          .from('gps_settings')
          .select()
          .eq('institute_id', instituteId!)
          .eq('admin_id', currentUser.id)
          .maybeSingle();

      if (configRow == null) {
        if (mounted) {
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

      final data = configRow;
      final latitude = (data['latitude'] as num?)?.toDouble();
      final longitude = (data['longitude'] as num?)?.toDouble();
      final isLocked = data['is_locked'] == true;
      
      // RADIUS IS ALWAYS FIXED AT 30M - NEVER CHANGES, EVEN IF UNLOCKED
      // This is a system-wide constant, not stored in database
      const double radius = 30.0; // Fixed 30m for all admins, always

      // Validate locked location exists
      if (latitude == null || longitude == null || latitude == 0.0 || longitude == 0.0) {
        if (mounted) {
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

      // If location is not locked yet, it means it hasn't been verified
      // Location should be locked after first verification
      if (!isLocked) {
        if (mounted) {
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

      // Get current position with best accuracy
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best, // Use best accuracy for precise location
          timeLimit: Duration(seconds: 10), // Timeout after 10 seconds
        ),
      );

      // Block fake GPS
      if (position.isMocked) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ Fake GPS detected. Please turn off Mock Location apps.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return false;
      }

      // Calculate distance from locked location
      final distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        latitude,
        longitude,
      );

      // Account for GPS accuracy - add buffer if GPS accuracy is poor
      // If GPS accuracy is 20m, allow 30m + 20m = 50m total
      final gpsAccuracy = position.accuracy;
      final effectiveRadius = radius + (gpsAccuracy > 0 ? gpsAccuracy : 0);
      
      // Debug: Log location check
      if (kDebugMode) {
        debugPrint('📍 Location Check (Admin: ${currentUser.id}):');
        debugPrint('   Locked Location: Lat=$latitude, Lng=$longitude');
        debugPrint('   Current Location: Lat=${position.latitude}, Lng=${position.longitude}');
        debugPrint('   Distance: ${distance.toStringAsFixed(2)}m');
        debugPrint('   Required: Within ${radius.toStringAsFixed(0)}m (base)');
        debugPrint('   GPS Accuracy: ${gpsAccuracy.toStringAsFixed(1)}m');
        debugPrint('   Effective Radius: ${effectiveRadius.toStringAsFixed(1)}m (${radius.toStringAsFixed(0)}m + ${gpsAccuracy.toStringAsFixed(1)}m accuracy buffer)');
        debugPrint('   Status: ${distance <= effectiveRadius ? "✅ WITHIN RADIUS" : "❌ OUT OF RADIUS"}');
      }

      // CHECK: Must be within effective radius (30m + GPS accuracy buffer)
      // This accounts for GPS inaccuracy - if GPS says you're 35m away but accuracy is 10m,
      // you might actually be within 30m
      if (distance > effectiveRadius) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '❌ Out of radius: You are ${distance.toStringAsFixed(0)}m away',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Required: Within ${radius.toStringAsFixed(0)}m of the locked location.\n'
                    'GPS Accuracy: ${gpsAccuracy.toStringAsFixed(1)}m\n'
                    'Effective Radius: ${effectiveRadius.toStringAsFixed(1)}m\n\n'
                    'Locked Location: ${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}\n'
                    'Your Location: ${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}\n\n'
                    '💡 If you are at the correct location:\n'
                    '• The stored coordinates may be incorrect\n'
                    '• GPS accuracy may be poor (try moving to open area)\n'
                    '• Please update location in GPS Settings',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 12),
            ),
          );
        }
        return false;
      }
      
      // If within base radius (30m), allow immediately
      if (distance <= radius) {
        if (kDebugMode) {
          debugPrint('✅ Within base radius (${radius.toStringAsFixed(0)}m) - Attendance allowed');
        }
        return true;
      }
      
      // If between base radius and effective radius, warn but allow
      // (This accounts for GPS inaccuracy)
      if (kDebugMode) {
        debugPrint('⚠️ Within effective radius (${effectiveRadius.toStringAsFixed(1)}m) but outside base radius (${radius.toStringAsFixed(0)}m)');
        debugPrint('   Allowing due to GPS accuracy buffer');
      }
      return true;

      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ GPS check failed: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false; // BLOCK on any error
    }
  }

  bool canMark() {
    // Flexible attendance: Allow any student to mark attendance regardless of batch
    return !isLoading &&
        isLocationValid &&
        instituteId != null &&
        selectedRollNumber != null &&
        isAlreadyMarked != true; // Can't mark if already marked
  }

  // Filter students based on search query
  void _filterStudents() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        filteredStudents = students;
      } else {
        filteredStudents = students
            .where((roll) => roll.toLowerCase().contains(query))
            .toList();
      }
    });
  }

  /// Parse lecture timing string to extract start and end times
  /// Format: "08:30 - 13:30" or "08:30-13:30" or multiple lectures "08:30-10:30, 11:00-13:30"
  List<Map<String, TimeOfDay>> _parseLectureTiming(String timing) {
    if (timing.isEmpty) return [];
    
    final List<Map<String, TimeOfDay>> lectures = [];
    
    try {
      // Split by comma if multiple lectures
      final lectureStrings = timing.split(',');
      
      for (var lectureStr in lectureStrings) {
        lectureStr = lectureStr.trim();
        // Split by dash or hyphen
        final parts = lectureStr.split(RegExp(r'[-–—]'));
        
        if (parts.length == 2) {
          final startStr = parts[0].trim();
          final endStr = parts[1].trim();
          
          // Parse time strings (format: HH:MM or HH:MM AM/PM)
          final startTime = _parseTimeString(startStr);
          final endTime = _parseTimeString(endStr);
          
          if (startTime != null && endTime != null) {
            lectures.add({
              'start': startTime,
              'end': endTime,
            });
          }
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error parsing lecture timing: $e');
    }
    
    return lectures;
  }

  /// Parse time string to TimeOfDay
  /// Supports formats: "08:30", "8:30 AM", "13:30", "1:30 PM"
  TimeOfDay? _parseTimeString(String timeStr) {
    try {
      timeStr = timeStr.trim().toUpperCase();
      
      // Check if it has AM/PM
      final hasAmPm = timeStr.contains('AM') || timeStr.contains('PM');
      final isPM = timeStr.contains('PM');
      
      // Remove AM/PM
      timeStr = timeStr.replaceAll('AM', '').replaceAll('PM', '').trim();
      
      // Split by colon
      final parts = timeStr.split(':');
      if (parts.length != 2) return null;
      
      var hour = int.parse(parts[0].trim());
      final minute = int.parse(parts[1].trim());
      
      // Convert 12-hour to 24-hour if needed
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

  /// Validate if current time is within lecture hours with entry/exit windows
  /// Entry window: 20 minutes after lecture start (e.g., 8:30-8:50)
  /// Exit window: 25 minutes after lecture end (e.g., 11:25-11:50)
  /// Returns map with 'valid' (bool) and 'message' (String?)
  Map<String, dynamic> _validateLectureTime(DateTime currentTime, List<Map<String, TimeOfDay>> lectures, bool isEntry) {
    if (lectures.isEmpty) {
      return {'valid': true, 'message': null};
    }
    
    final currentHour = currentTime.hour;
    final currentMinute = currentTime.minute;
    final currentTimeOfDay = TimeOfDay(hour: currentHour, minute: currentMinute);
    final currentMinutes = currentTimeOfDay.hour * 60 + currentTimeOfDay.minute;
    
    if (isEntry) {
      // ENTRY WINDOW: 20 minutes after first lecture start
      final firstLecture = lectures.first;
      final start = firstLecture['start'] as TimeOfDay;
      final startMinutes = start.hour * 60 + start.minute;
      final entryWindowEnd = startMinutes + 20; // 20 minutes after lecture start
      
      // Entry allowed from lecture start to 20 minutes after
      if (currentMinutes >= startMinutes && currentMinutes <= entryWindowEnd) {
        return {'valid': true, 'message': null};
      } else if (currentMinutes < startMinutes) {
        final startStr = '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}';
        return {
          'valid': false,
          'message': 'Entry window not open yet. Entry allowed from $startStr to ${_formatMinutes(entryWindowEnd)}',
        };
      } else {
        final endStr = _formatMinutes(entryWindowEnd);
        return {
          'valid': false,
          'message': 'Entry window closed. Entry was allowed until $endStr (20 minutes after lecture start)',
        };
      }
    } else {
      // EXIT WINDOW: 25 minutes after last lecture end
      final lastLecture = lectures.last;
      final end = lastLecture['end'] as TimeOfDay;
      final endMinutes = end.hour * 60 + end.minute;
      final exitWindowStart = endMinutes - 5; // 5 minutes before lecture end (11:25 for 11:30 end)
      final exitWindowEnd = endMinutes + 25; // 25 minutes after lecture end
      
      // Exit allowed from 5 minutes before lecture end to 25 minutes after
      if (currentMinutes >= exitWindowStart && currentMinutes <= exitWindowEnd) {
        return {'valid': true, 'message': null};
      } else if (currentMinutes < exitWindowStart) {
        final startStr = _formatMinutes(exitWindowStart);
        final endStr = '${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}';
        return {
          'valid': false,
          'message': 'Exit window not open yet. Exit allowed from $startStr (5 mins before $endStr) to ${_formatMinutes(exitWindowEnd)}',
        };
      } else {
        final endStr = _formatMinutes(exitWindowEnd);
        return {
          'valid': false,
          'message': 'Exit window closed. Exit was allowed until $endStr (25 minutes after lecture end)',
        };
      }
    }
  }

  /// Format minutes (since midnight) to HH:MM string
  String _formatMinutes(int minutes) {
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    return '${hours.toString().padLeft(2, '0')}:${mins.toString().padLeft(2, '0')}';
  }

  // Mark student as absent (one-tap, no photo required)
  Future<void> _markAbsent() async {
    if (selectedRollNumber == null || instituteId == null) {
      if (selectedBatch == null) {
        ProfessionalMessaging.showWarning(
          context,
          title: 'Student Batch Not Found',
          message: 'This student does not have a batch assigned. Please assign a batch to the student first.',
        );
        return;
      }
      ProfessionalMessaging.showWarning(
        context,
        title: 'Roll Number Required',
        message: 'Please select a roll number first.',
      );
      return;
    }
    
    // No subject requirement - attendance is based on entry/exit times only

    // Show reason dialog
    final reason = await _showAbsentReasonDialog();
    if (reason == null) return; // User cancelled

    setState(() => isLoading = true);

    try {
      final markingTime = DateTime.now();
      final absentDate = DateFormat('yyyy-MM-dd').format(markingTime);
      // Per-day attendance (not per-subject)
      final docId = '${selectedRollNumber}_$absentDate';

      final existingData = await _getTeacherAttendanceDoc(selectedRollNumber!, absentDate);

      if (existingData != null) {
        if (existingData['status'] == 'absent') {
          setState(() => isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠️ Student already marked as absent today'),
              backgroundColor: Colors.orange,
            ),
          );
          return;
        }
      }

      // Get device and network info
      final deviceInfo = await DeviceFingerprintService.getDeviceInfoForLogging();
      final networkInfo = await NetworkVerificationService.getNetworkInfoForLogging();

      final merged = Map<String, dynamic>.from(existingData ?? {});
      merged.addAll({
        'rollNumber': selectedRollNumber,
        'date': absentDate,
        'status': 'absent',
        'reason': reason,
        'timestamp': _encodeSv(),
        'markedBy': _db.auth.currentUser?.id ?? 'unknown',
        'batchId': selectedBatch?['id'],
        'batchName': selectedBatch?['name'],
        'instituteId': instituteId,
        'deviceInfo': deviceInfo,
        'networkInfo': networkInfo,
        'createdAt': merged['createdAt'] ?? _encodeSv(),
        'lastModified': _encodeSv(),
      });

      await _upsertTeacherAttendanceDoc(
        roll: selectedRollNumber!,
        date: absentDate,
        payload: merged,
        status: 'absent',
      );

      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Marked absent: $reason'),
          backgroundColor: Colors.orange,
        ),
      );

      // Reset selections
      selectedRollNumber = null;
      isAlreadyMarked = null;
      existingMarkTime = null;
    } catch (e) {
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Show absent reason dialog
  Future<String?> _showAbsentReasonDialog() async {
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark Absent'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Select reason for absence:'),
            const SizedBox(height: 16),
            ...['Sick', 'Leave', 'Late', 'Other'].map((reason) => 
              ListTile(
                title: Text(reason),
                onTap: () => Navigator.pop(context, reason),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Future<void> _checkAttendanceStatus() async {
    if (selectedRollNumber == null || instituteId == null) {
      setState(() {
        isAlreadyMarked = null;
        existingMarkTime = null;
        existingAttendanceData = null;
      });
      return;
    }

    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      // Changed: Per-day attendance, not per-subject
      final docId = '${selectedRollNumber}_$today';

      final data = await _getTeacherAttendanceDoc(selectedRollNumber!, today);

      if (data != null) {
        final ts = _asDateTime(data['entryTime']) ?? _asDateTime(data['timestamp']);
        String? timeStr;
        if (ts != null) {
          timeStr = DateFormat('hh:mm a').format(ts);
        }

        // Check if entry and exit are both marked
        final hasEntry = data['entryPhoto'] != null || data['photoUrl'] != null;
        final hasExit = data['exitPhoto'] != null;
        
        // Get lecture scans
        final lectures = data['lectures'] as Map<String, dynamic>? ?? {};
        final timing = selectedTiming ?? selectedBatch?['timing']?.toString() ?? '';
        final lectureTimes = _parseLectureTiming(timing);
        
        // Determine which lecture needs scanning
        int? nextLectureIndex;
        if (hasEntry && !hasExit && lectureTimes.isNotEmpty) {
          final currentTime = DateTime.now();
          final currentHour = currentTime.hour;
          final currentMinute = currentTime.minute;
          final currentMinutes = currentHour * 60 + currentMinute;
          
          for (int i = 0; i < lectureTimes.length; i++) {
            final lecture = lectureTimes[i];
            final start = lecture['start'] as TimeOfDay;
            final end = lecture['end'] as TimeOfDay;
            final startMinutes = start.hour * 60 + start.minute;
            final endMinutes = end.hour * 60 + end.minute;
            
            // Check if we're within this lecture time
            if (currentMinutes >= startMinutes && currentMinutes <= endMinutes) {
              final lectureKey = 'lecture_${i + 1}';
              if (!lectures.containsKey(lectureKey) || lectures[lectureKey]['faceScanPhoto'] == null) {
                nextLectureIndex = i;
                break;
              }
            }
          }
        }

        setState(() {
          isAlreadyMarked = hasEntry && hasExit; // Fully marked if both entry and exit exist
          existingMarkTime = timeStr;
          existingAttendanceData = data;
          currentLectureIndex = nextLectureIndex;
          
          // Determine mode: entry, exit, or lecture scan
          if (!hasEntry) {
            attendanceMode = 'entry';
            isEntryPhoto = true;
          } else if (hasEntry && !hasExit) {
            if (nextLectureIndex != null) {
              attendanceMode = 'lecture_scan';
              isEntryPhoto = false;
            } else {
              attendanceMode = 'exit';
              isEntryPhoto = false;
            }
          } else {
            attendanceMode = 'entry'; // Both marked, start new day
            isEntryPhoto = true;
          }
        });
      } else {
        setState(() {
          isAlreadyMarked = false;
          existingMarkTime = null;
          existingAttendanceData = null;
          attendanceMode = 'entry';
          isEntryPhoto = true; // Start with entry photo
          currentLectureIndex = null;
        });
      }
    } catch (e) {
      setState(() {
        isAlreadyMarked = null;
        existingMarkTime = null;
        existingAttendanceData = null;
        attendanceMode = null;
        currentLectureIndex = null;
      });
    }
  }

  /* ---------------- MARK ATTENDANCE ---------------- */

  Future<void> _markAttendance() async {
    setState(() => isLoading = true);

    try {
      final markingTime = DateTime.now();
      
      // 🛡️ SECURITY CHECK 1: Prevent backdating and future dating
      final today = DateFormat('yyyy-MM-dd').format(markingTime);
      
      // Block future dates
      if (markingTime.isAfter(DateTime.now().add(const Duration(minutes: 5)))) {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Cannot mark attendance for future dates'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // 🛡️ SECURITY CHECK 2: Device fingerprinting
      final deviceInfo = await DeviceFingerprintService.getDeviceInfoForLogging();
      final deviceChanged = await DeviceFingerprintService.hasDeviceChanged();
      
      if (deviceChanged) {
        if (kDebugMode) debugPrint('⚠️ Device change detected - logging for review');
      }

      // 🛡️ SECURITY CHECK 3: Network verification
      final networkInfo = await NetworkVerificationService.getNetworkInfoForLogging();

      // 🛡️ SECURITY CHECK 4: Suspicious activity check (non-blocking, optimized)
      // Run in background to not delay attendance marking
      SuspiciousActivityService.checkSuspiciousActivity(
        instituteId: instituteId!,
        markedBy: _db.auth.currentUser?.id ?? 'unknown',
        markingTime: markingTime,
        deviceFingerprint: deviceInfo['fingerprint'],
      ).then((suspiciousCheck) {
        if (suspiciousCheck['isSuspicious'] == true) {
          // Log suspicious activity asynchronously (non-blocking)
          SuspiciousActivityService.logSuspiciousActivity(
            instituteId: instituteId!,
            userId: _db.auth.currentUser?.id ?? 'unknown',
            activityData: {
              'warnings': suspiciousCheck['warnings'],
              'deviceInfo': deviceInfo,
              'networkInfo': networkInfo,
            },
          ).catchError((e) {
            // Don't block if logging fails
            if (kDebugMode) debugPrint('⚠️ Failed to log suspicious activity: $e');
          });
        }
      }).catchError((e) {
        // Don't block attendance marking if check fails
        if (kDebugMode) debugPrint('⚠️ Suspicious activity check failed: $e');
      });

      // 🛡️ SECURITY CHECK 5: STRICT GPS RADIUS CHECK (30m, no buffer)
      if (!kIsWeb) {
        final withinRadius = await _checkGPSRadius();
        if (!withinRadius) {
          setState(() => isLoading = false);
          return; // BLOCK attendance if outside 30m radius
        }
      }

      // Use simple ImagePicker for testing (face recognition disabled for now)
      final photo = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 50, // Lower quality for smaller file size (was 85)
        maxWidth: 800, // Limit width to reduce size
        maxHeight: 800, // Limit height to reduce size
        preferredCameraDevice: CameraDevice.front,
      );

      if (photo == null) {
        setState(() => isLoading = false);
        return;
      }

      // Read and compress photo
      Uint8List bytes = await photo.readAsBytes();
      
      // Compress image if still too large (target: under 50KB)
      if (bytes.length > 50 * 1024) {
        bytes = await _compressImage(bytes, maxSizeKB: 50);
        if (kDebugMode) {
          debugPrint('📸 Photo compressed: ${(bytes.length / 1024).toStringAsFixed(2)} KB');
        }
      }
      
      // 🛡️ SECURITY CHECK 5: Photo verification (EXIF, timestamp, screenshot detection)
      final photoVerification = await PhotoVerificationService.verifyPhoto(
        photoPath: photo.path,
        markingTime: markingTime,
        expectedLocation: null, // Can add location check if needed
      );

      if (!photoVerification['isValid']) {
        setState(() => isLoading = false);
        final errors = photoVerification['errors'] as List<String>;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Photo verification failed:\n${errors.join('\n')}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
        return;
      }

      // 🛡️ SECURITY CHECK 6: Blur detection
      final isBlurry = await PhotoVerificationService.detectBlur(bytes);
      if (isBlurry) {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Photo is blurry. Please retake a clear photo.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // 🛡️ SECURITY CHECK 7: Photo-of-photo detection
      final isPhotoOfPhoto = await PhotoVerificationService.detectPhotoOfPhoto(photo.path);
      if (isPhotoOfPhoto) {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '❌ Invalid: Photo of a photo detected.\n'
              'Please take a live photo of the student, not a photo of their photo.',
            ),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
          ),
        );
        return;
      }

      // 🛡️ SECURITY CHECK 7B: Liveness detection (eyes open, looking at camera)
      final livenessResult = await LivenessDetectionService.detectLivenessFromPhoto(
        photoPath: photo.path,
      );
      if (!livenessResult['isLive'] || (livenessResult['confidence'] as double) < 0.5) {
        setState(() => isLoading = false);
        final details = livenessResult['details'] as Map<String, dynamic>;
        final errorMsg = details['error'] as String?;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              errorMsg != null
                  ? '❌ Liveness check failed: $errorMsg\n'
                      'Please ensure:\n'
                      '• Student is looking at the camera\n'
                      '• Eyes are open\n'
                      '• Face is clearly visible'
                  : '❌ Liveness check failed.\n'
                      'Please ensure the student is:\n'
                      '• Looking directly at the camera\n'
                      '• Eyes are open\n'
                      '• Face is clearly visible and well-lit',
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 6),
          ),
        );
        return;
      }

      // 🛡️ SECURITY CHECK 8: Multiple face detection (group photo)
      final faceDetection = await PhotoVerificationService.detectMultipleFaces(photo.path);
      if (faceDetection['isGroupPhoto'] == true) {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠️ Multiple faces detected (${faceDetection['faceCount']}). Please take a photo of a single student.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      
      // 🛡️ SECURITY CHECK 9A: Subject validation - must have at least 1 subject
      if (studentEnrolledSubjects.isEmpty) {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.white),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '❌ Cannot Mark Attendance',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Student with roll number $selectedRollNumber has 0 subjects assigned.\n\n'
                  'Attendance can only be marked for students with at least 1 subject.\n\n'
                  'Please assign subjects to this student first in Batch Management.',
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 8),
          ),
        );
        return;
      }
      
      // 🛡️ SECURITY CHECK 9: Face Recognition Verification (Face ID-like) - MANDATORY
      // CRITICAL: This check CANNOT be bypassed - it prevents wrong person from marking attendance
      if (selectedRollNumber == null || instituteId == null) {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '❌ CRITICAL: Face recognition is required for attendance.\n'
              'Please ensure roll number is selected and student face is registered.',
            ),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
          ),
        );
        return;
      }

      // Note: Old face template check and quality checks removed
      // Backend API (DeepFace) handles face detection and quality automatically
      
      setState(() => isLoading = true); // Show loading during verification
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  '🔐 Face Recognition: Processing with DeepFace API...',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          duration: Duration(seconds: 10),
          backgroundColor: Colors.blue,
        ),
      );
      
      // CRITICAL: Verify face match using DIRECT 1:1 matching (faster)
      // Uses new /verify endpoint: Direct match + Security check
      // Threshold: 0.70 (70%) - more lenient for same photo matching while still secure
      final verifyResult = await ArcFaceBackendService.verifyStudentFace(
        imagePath: photo.path,
        instituteId: instituteId!,
        rollNumber: selectedRollNumber!,
        threshold: 0.70, // 70% - more lenient for same photo, still prevents wrong matches
      );
      
      // Check verification result
      if (verifyResult == null || verifyResult['match'] != true) {
        // Verification failed - could be no face registered, face doesn't match, or security check failed
        setState(() => isLoading = false);
        
        String errorMessage = 'Face verification failed.\n\n';
        if (verifyResult != null && verifyResult['securityCheckPassed'] == false) {
          errorMessage = '❌ SECURITY ALERT: Wrong Student Detected!\n\n'
              'The face in the photo matches a DIFFERENT student.\n'
              'Selected: Roll $selectedRollNumber\n\n'
              'SECURITY BLOCKED: Wrong person detected!';
        } else {
          errorMessage = '❌ Face Recognition Failed\n\n'
              'Possible reasons:\n'
              '• Face not registered for this student\n'
              '• Face does not match registered face\n'
              '• No face detected in photo\n\n'
              'Please ensure:\n'
              '• Student face is registered first\n'
              '• The CORRECT student is present\n'
              '• Good lighting and clear face view\n'
              '• Looking directly at camera';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      verifyResult != null && verifyResult['securityCheckPassed'] == false
                          ? Icons.security
                          : Icons.error_outline,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        verifyResult != null && verifyResult['securityCheckPassed'] == false
                            ? '❌ SECURITY: Wrong Student Detected'
                            : '❌ Face Recognition Failed',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  errorMessage,
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 10),
          ),
        );
        return;
      }
      
      // Face verified successfully (like Face ID unlock)
      if (kDebugMode) {
        final similarity = verifyResult['similarity'] as double? ?? 0.0;
        final processingTime = verifyResult['processingTimeMs'] as double? ?? 0.0;
        debugPrint('✅ Face ID verification passed for Roll $selectedRollNumber');
        debugPrint('   Similarity: ${(similarity * 100).toStringAsFixed(1)}%');
        debugPrint('   Processing time: ${processingTime.toStringAsFixed(0)}ms');
        debugPrint('   Security check: PASSED');
      }
      
      // Check file size - must be under 50KB
      final maxSizeBytes = 50 * 1024; // 50KB
      if (bytes.length > maxSizeBytes) {
        throw Exception(
          'Photo is too large (${(bytes.length / 1024).toStringAsFixed(1)} KB).\n\n'
          'Maximum allowed: 50 KB\n\n'
          'Please take a new photo. The app will automatically compress it.'
        );
      }

      // Changed: Per-day attendance document (not per-subject)
      final docId = '${selectedRollNumber}_$today';

      final existingPayload = await FirestoreRetryService.executeWithRetry(
        operation: () async => await _getTeacherAttendanceDoc(selectedRollNumber!, today),
        operationName: 'Check existing attendance',
      );

      final currentTime = DateTime.now();
      final serverTs = _encodeSv();
      
      // Determine mode: entry, exit, or lecture scan
      String mode = attendanceMode ?? 'entry';
      if (existingPayload != null) {
        final existingData = existingPayload;
        final hasEntry = existingData['entryPhoto'] != null || existingData['photoUrl'] != null;
        final hasExit = existingData['exitPhoto'] != null;
        
        if (hasEntry && hasExit) {
          // Both entry and exit already marked
          setState(() => isLoading = false);
          final entryTime = _asDateTime(existingData['entryTime']) ?? _asDateTime(existingData['timestamp']);
          final exitTime = _asDateTime(existingData['exitTime']);
        String timeInfo = '';
          if (entryTime != null && exitTime != null) {
            final entry = DateFormat('hh:mm a').format(entryTime);
            final exit = DateFormat('hh:mm a').format(exitTime);
            timeInfo = ' (Entry: $entry, Exit: $exit)';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '⚠️ Attendance fully marked for this student$timeInfo.\n\n'
                'Both entry and exit photos are already recorded.',
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 5),
          ),
        );
        return;
        } else if (!hasEntry) {
          mode = 'entry';
        } else if (hasEntry && !hasExit) {
          // Check if we need lecture scan or exit
          if (currentLectureIndex != null && attendanceMode == 'lecture_scan') {
            mode = 'lecture_scan';
          } else {
            mode = 'exit';
          }
        }
      }
      
      bool isMarkingEntry = (mode == 'entry');
      bool isMarkingExit = (mode == 'exit');
      bool isLectureScan = (mode == 'lecture_scan');

      // Get batch year for folder structure
      final batchYear = selectedBatch?['year']?.toString() ?? DateTime.now().year.toString();
      // Parse batch timing to get lecture start/end times (for display only, no validation)
      final timing = selectedTiming ?? selectedBatch?['timing']?.toString() ?? '';
      final lectureTimes = _parseLectureTiming(timing);
      
      // NO TIME RESTRICTIONS - Students can mark entry/exit at any time
      // Hours are calculated based on actual entry/exit times, not batch timings

      // Upload photo - different path for entry/exit/lecture_scan
      String photoType;
      if (isMarkingEntry) {
        photoType = 'entry';
      } else if (isMarkingExit) {
        photoType = 'exit';
      } else {
        photoType = 'lecture_scan';
      }
      
      final uploadResult = await StorageService.uploadAttendancePhoto(
        instituteId: instituteId!,
        batchYear: batchYear,
        rollNumber: selectedRollNumber!,
        subject: 'all', // Not subject-based - use 'all' for per-day attendance
        date: today,
        photoBytes: bytes,
        photoType: photoType,
      );

      final url = uploadResult['url']!;
      final storagePath = uploadResult['path']!;
      final fileSizeBytes = bytes.length;

      debugPrint('📁 Storage Path: $storagePath');
      debugPrint('🔗 Photo URL: $url');
      debugPrint('📏 Photo Size: ${(fileSizeBytes / 1024).toStringAsFixed(2)} KB');
      debugPrint('📸 Photo Type: $photoType');

      final existingData = existingPayload != null
          ? Map<String, dynamic>.from(existingPayload!)
          : <String, dynamic>{};
      
      // Save attendance record with entry/exit/lecture scan support
      // Note: Attendance is per-day, not per-subject. Subjects stored for reference only.
      final attendanceData = <String, dynamic>{
        'rollNumber': selectedRollNumber,
        'date': today,
        'markedBy': _db.auth.currentUser?.id ?? 'unknown',
        'batchId': selectedBatch?['id'],
        'batchName': selectedBatch?['name'],
        'batchTiming': timing,
        'instituteId': instituteId,
        'updatedAt': serverTs,
        // Store student's enrolled subjects for reference (not used for attendance marking)
        'subjects': studentEnrolledSubjects,
      };

      if (isMarkingEntry) {
        // Marking entry - start of day
        // DO NOT mark as present until exit photo is taken
        attendanceData['entryPhoto'] = url;
        attendanceData['entryTime'] = serverTs;
        attendanceData['entryPhotoPath'] = storagePath;
        attendanceData['photoUrl'] = url; // For backward compatibility
        attendanceData['timestamp'] = serverTs;
        attendanceData['status'] = 'pending'; // Pending until exit photo is taken
        
        // Do NOT mark lectures as present at entry - only mark at exit
        // Just store lecture structure for reference
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
              'marked': false, // Not marked until exit photo
              'status': 'pending',
            };
          }
        }
        attendanceData['lectures'] = lectures;
      } else if (isLectureScan && currentLectureIndex != null) {
        // Marking lecture face scan
        final lectureIndex = currentLectureIndex!;
        final lectureKey = 'lecture_${lectureIndex + 1}';
        final lecture = lectureTimes[lectureIndex];
        final start = lecture['start'] as TimeOfDay;
        final end = lecture['end'] as TimeOfDay;
        
        // Preserve existing data
        attendanceData['entryPhoto'] = existingData['entryPhoto'] ?? existingData['photoUrl'];
        attendanceData['entryTime'] = existingData['entryTime'] ?? existingData['timestamp'];
        attendanceData['entryPhotoPath'] = existingData['entryPhotoPath'] ?? existingData['storagePath'];
        attendanceData['photoUrl'] = existingData['photoUrl'] ?? existingData['entryPhoto'];
        attendanceData['timestamp'] = existingData['timestamp'] ?? existingData['entryTime'];
        
        // Get existing lectures or create new
        final lectures = Map<String, dynamic>.from(existingData['lectures'] as Map? ?? {});
        lectures[lectureKey] = {
          'faceScanPhoto': url,
          'faceScanTime': serverTs,
          'faceScanPath': storagePath,
          'startTime': '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}',
          'endTime': '${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}',
          'marked': true,
        };
        attendanceData['lectures'] = lectures;
      } else if (isMarkingExit) {
        // Marking exit - end of day
        // Preserve entry data
        attendanceData['entryPhoto'] = existingData['entryPhoto'] ?? existingData['photoUrl'];
        attendanceData['entryTime'] = existingData['entryTime'] ?? existingData['timestamp'];
        attendanceData['entryPhotoPath'] = existingData['entryPhotoPath'] ?? existingData['storagePath'];
        attendanceData['photoUrl'] = existingData['photoUrl'] ?? existingData['entryPhoto'];
        attendanceData['timestamp'] = existingData['timestamp'] ?? existingData['entryTime'];
        
        // Mark exit
        attendanceData['exitPhoto'] = url;
        attendanceData['exitTime'] = serverTs;
        attendanceData['exitPhotoPath'] = storagePath;
        
        // Get existing lectures
        final lectures = Map<String, dynamic>.from(existingData['lectures'] as Map? ?? {});
        final entryTime = _asDateTime(existingData['entryTime']) ?? _asDateTime(existingData['timestamp']);
        
        // Automatically mark attendance for all lectures between entry and exit
        if (entryTime != null && lectureTimes.isNotEmpty) {
          final entryDateTime = entryTime;
          final exitDateTime = currentTime;
          
          for (int i = 0; i < lectureTimes.length; i++) {
            final lecture = lectureTimes[i];
            final start = lecture['start'] as TimeOfDay;
            final end = lecture['end'] as TimeOfDay;
            
            // Create lecture start/end DateTime for today
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
            
            // If lecture is between entry and exit, mark it
            if (lectureStart.isAfter(entryDateTime.subtract(const Duration(minutes: 30))) &&
                lectureEnd.isBefore(exitDateTime.add(const Duration(minutes: 30)))) {
              final lectureKey = 'lecture_${i + 1}';
              if (!lectures.containsKey(lectureKey)) {
                // Mark lecture as attended (even without face scan if exit is marked)
                lectures[lectureKey] = {
                  'startTime': '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}',
                  'endTime': '${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}',
                  'marked': true,
                  'markedAtExit': true, // Flag to indicate marked at exit time
                };
              } else {
                // Update existing lecture to ensure it's marked
                final existingLecture = Map<String, dynamic>.from(lectures[lectureKey] as Map);
                existingLecture['marked'] = true;
                lectures[lectureKey] = existingLecture;
              }
            }
          }
        }
        
        attendanceData['lectures'] = lectures;
        attendanceData['status'] = 'present'; // Mark as present when exit photo taken
        
        // Calculate hours from entry and exit times
        if (entryTime != null) {
          final entryDateTime = entryTime;
          final exitDateTime = currentTime;
          final duration = exitDateTime.difference(entryDateTime);
          final hours = duration.inMinutes / 60.0; // Convert to hours with decimal
          attendanceData['hours'] = double.parse(hours.toStringAsFixed(2)); // Store hours with 2 decimal places
        }
      }

      final mergedPayload = Map<String, dynamic>.from(existingData)..addAll(attendanceData);

      await FirestoreRetryService.executeWithRetry(
        operation: () async {
          await _upsertTeacherAttendanceDoc(
            roll: selectedRollNumber!,
            date: today,
            payload: mergedPayload,
            status: mergedPayload['status']?.toString(),
          );
        },
        operationName: 'Save attendance record',
      );

      final rollNumberForMessage = selectedRollNumber; // Store before clearing
      
      String successMessage;
      if (isMarkingEntry) {
        successMessage = '✅ Entry photo recorded for $rollNumberForMessage\n'
            '⚠️ Attendance will be marked as present only after exit photo is taken!\n'
            '⚠️ Remember to take exit photo before leaving!';
      } else if (isMarkingExit) {
        final hours = attendanceData['hours'] as double? ?? 0.0;
        successMessage = '✅ Exit attendance marked for $rollNumberForMessage\n'
            '⏰ Total hours: ${hours.toStringAsFixed(2)} hours';
      } else if (isLectureScan && currentLectureIndex != null) {
        successMessage = '✅ Lecture ${currentLectureIndex! + 1} face scan marked for $rollNumberForMessage';
      } else {
        successMessage = '✅ Attendance marked for $rollNumberForMessage';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text(successMessage),
              ),
            ],
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );

      // QUEUE MODE: Keep batch/subject/timing selected, only clear roll number
      // This allows continuous marking for students in line
      setState(() {
        selectedRollNumber = null; // Only clear roll number for next student
      isAlreadyMarked = null;
      existingMarkTime = null;
        existingAttendanceData = null;
        isEntryPhoto = true; // Reset to entry photo for next student (will be updated by _checkAttendanceStatus)
      });
      
      // Refresh student list to show updated status
      if (selectedBatch != null) {
        _loadStudentsForBatch();
      }
    } catch (e) {
      String errorMessage = 'Failed to mark attendance';
      
      // Extract user-friendly error message
      final errorString = e.toString();
      
      // Log full error for debugging
      if (kDebugMode) {
        debugPrint('🔴 Attendance Upload Error:');
        debugPrint('   Full error: $errorString');
      }
      
      // User-friendly error messages
      if (errorString.contains('Photo is too large') || errorString.contains('File size validation failed')) {
        errorMessage = 'Photo file is too large. The app will automatically compress it. Please try taking the photo again.';
      } else if (errorString.contains('Storage Authentication Error') || 
                 errorString.contains('Authentication Failed') ||
                 errorString.contains('InvalidAccessKeyId') ||
                 errorString.contains('403') ||
                 errorString.contains('SignatureDoesNotMatch')) {
        errorMessage = 'Storage service configuration error. Please contact technical support.';
      } else if (errorString.contains('B2B upload failed')) {
        errorMessage = 'Failed to upload photo. Please check your internet connection and try again.';
      } else if (errorString.contains('timeout') && errorString.contains('30 seconds')) {
        errorMessage = 'Face recognition request timed out. The backend may be loading the AI model (first request). Please try again - subsequent requests will be faster.';
      } else if (errorString.contains('500') || errorString.contains('Internal Server Error')) {
        errorMessage = 'Backend processing error. This may happen if:\n• Face detection failed\n• Student face not registered\n• Backend memory issue\n\nPlease try again or ensure student face is registered first.';
      } else if (errorString.contains('503') || errorString.contains('Service Unavailable')) {
        errorMessage = 'Backend service is temporarily unavailable. The AI model may be loading (first request). Please wait 10-20 seconds and try again.';
      } else if (errorString.contains('network') || errorString.contains('connection') || errorString.contains('timeout')) {
        errorMessage = 'Network connection issue. Please check your internet connection and try again.';
      } else if (errorString.contains('face') || errorString.contains('recognition') || errorString.contains('match')) {
        errorMessage = 'Face verification failed. Please ensure good lighting, face is clearly visible, and try again.';
      } else if (errorString.contains('location') || errorString.contains('GPS') || errorString.contains('geofence')) {
        errorMessage = 'Location verification failed. Please enable location services and ensure you are within 30 meters of the institute.';
      } else if (errorString.contains('time') || errorString.contains('window') || errorString.contains('entry') || errorString.contains('exit')) {
        errorMessage = 'Attendance can only be marked during the allowed time window. Please check the batch timing and try again.';
      } else if (errorString.contains('blur') || errorString.contains('quality')) {
        errorMessage = 'Photo quality is too low. Please ensure good lighting, keep the camera steady, and take a clear photo.';
      } else if (errorString.contains('photo') && errorString.contains('photo')) {
        errorMessage = 'Invalid photo detected. Please take a live photo of the student, not a photo of a photo.';
      } else if (errorString.contains('dotenv') || errorString.contains('not initialized')) {
        errorMessage = 'System configuration error. Please contact technical support.';
      } else {
        errorMessage = 'An error occurred while marking attendance. Please try again. If the problem persists, contact support.';
      }
      
      if (mounted) {
        ProfessionalMessaging.showError(
          context,
          title: 'Attendance Marking Failed',
          message: errorMessage,
          showHelp: true,
          durationSeconds: 6,
        );
      }
    } finally {
      setState(() => isLoading = false);
    }
  }

  /* ---------------- UI ---------------- */

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return PopScope(
      canPop: Navigator.of(context).canPop(),
      onPopInvokedWithResult: (didPop, result) {
        // Pop already happened if didPop is true, no action needed
        // If didPop is false, pop was prevented (no previous route), also no action needed
      },
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF0F172A) : AppTheme.backgroundGrey,
        body: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Column(
              children: [
                _buildModernAppBar(),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildHeader(),
                        const SizedBox(height: 24),
                        
                        // Queue Mode Instructions
                        if (selectedBatch != null && selectedSubject != null)
                          _buildQueueModeBanner(),
                        if (selectedBatch != null)
                          const SizedBox(height: 16),

            // Step 1: Select Roll Number with Search (Batch auto-fetched)
            _buildStepCard(
              stepNumber: 1,
              title: 'Select Roll Number',
              icon: Icons.badge_outlined,
              iconColor: AppTheme.accentYellow,
                child: isLoadingBatches
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24.0),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    : Column(
                        children: [
                          // Search Bar
                          Builder(
                            builder: (context) {
                              final isDark = Theme.of(context).brightness == Brightness.dark;
                              return Container(
                                decoration: BoxDecoration(
                                  color: isDark 
                                      ? Colors.white.withValues(alpha: 0.1) 
                                      : AppTheme.backgroundGrey,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isDark 
                                        ? Colors.white.withValues(alpha: 0.3) 
                                        : AppTheme.primaryBlue.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: TextField(
                                  controller: _searchController,
                                  style: TextStyle(
                                    color: isDark ? Colors.white : AppTheme.textDark,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: 'Search by roll number...',
                                    hintStyle: TextStyle(
                                      color: isDark 
                                          ? Colors.white.withValues(alpha: 0.7) 
                                          : AppTheme.textGray,
                                      fontSize: 15,
                                    ),
                                    prefixIcon: Icon(
                                      Icons.search, 
                                      color: isDark ? Colors.white : AppTheme.primaryBlue, 
                                      size: 22,
                                    ),
                                    suffixIcon: _searchController.text.isNotEmpty
                                        ? IconButton(
                                            icon: Icon(
                                              Icons.clear, 
                                              color: isDark ? Colors.white : AppTheme.primaryBlue, 
                                              size: 22,
                                            ),
                                            onPressed: () {
                                              _searchController.clear();
                                              _filterStudents();
                                            },
                                          )
                                        : null,
                                    border: InputBorder.none,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                  ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                          // Dropdown with filtered students
                          _buildModernDropdown(
                        value: selectedRollNumber,
                        label: 'Select Roll Number *',
                        icon: Icons.badge_outlined,
                            items: filteredStudents
                            .map((roll) {
                              final isDark = Theme.of(context).brightness == Brightness.dark;
                              return DropdownMenuItem(
                                  value: roll,
                                      child: Text(
                                        'Roll $roll',
                                  style: TextStyle(
                                    color: isDark ? Colors.white : AppTheme.textDark,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                ),
                              );
                            })
                            .toList(),
                        onChanged: (roll) async {
                          if (roll != null) {
                            setState(() {
                              selectedRollNumber = roll;
                              isAlreadyMarked = null;
                              existingMarkTime = null;
                              attendanceMode = null;
                              currentLectureIndex = null;
                              selectedBatch = null;
                              selectedSubject = null;
                              selectedTiming = null;
                              studentEnrolledSubjects = [];
                            });
                            // Fetch student data and auto-populate batch/subject/timing
                            await _fetchStudentDataAndSetBatch(roll);
                            _checkAttendanceStatus();
                          }
                        },
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 16),
              
              // Display Batch/Subject/Timing Info (auto-populated)
              if (selectedRollNumber != null && selectedBatch != null) ...[
                _buildStepCard(
                  stepNumber: 2,
                  title: 'Batch Information',
                  icon: Icons.info_outline,
                  iconColor: AppTheme.primaryBlue,
                  child: Builder(
                    builder: (context) {
                      final isDark = Theme.of(context).brightness == Brightness.dark;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Batch Name
                          Row(
                            children: [
                              Icon(Icons.groups_outlined, size: 20, color: isDark ? Colors.white70 : AppTheme.textGray),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Batch: ${selectedBatch!['name'] ?? 'N/A'}',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: isDark ? Colors.white : AppTheme.textDark,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // Timing
                          if (selectedTiming != null && selectedTiming!.isNotEmpty)
                            Row(
                              children: [
                                Icon(Icons.access_time_outlined, size: 20, color: isDark ? Colors.white70 : AppTheme.textGray),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Timing: $selectedTiming',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: isDark ? Colors.white : AppTheme.textDark,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          const SizedBox(height: 12),
                          // Display Student's Enrolled Subjects (Read-only)
                          if (studentEnrolledSubjects.isNotEmpty) ...[
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: isDark 
                                    ? Colors.white.withValues(alpha: 0.1)
                                    : AppTheme.primaryBlueLight.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isDark 
                                      ? Colors.white.withValues(alpha: 0.2)
                                      : AppTheme.primaryBlue.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.book_outlined,
                                        size: 20,
                                        color: isDark ? Colors.white70 : AppTheme.primaryBlue,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Enrolled Subjects',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: isDark ? Colors.white : AppTheme.textDark,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: studentEnrolledSubjects.map((subject) {
                                      // All subjects are selected (shown for reference only)
                                      return Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: isDark 
                                              ? AppTheme.primaryBlue.withValues(alpha: 0.2)
                                              : AppTheme.primaryBlue.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(
                                            color: AppTheme.primaryBlue.withValues(alpha: 0.5),
                                            width: 1,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.check_circle,
                                              size: 16,
                                              color: AppTheme.primaryBlue,
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              subject,
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w500,
                                                color: isDark ? Colors.white : AppTheme.textDark,
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Note: All enrolled subjects shown for reference. Attendance is per-day, not per-subject. Hours are calculated based on entry/exit time.',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isDark 
                                          ? Colors.white.withValues(alpha: 0.6)
                                          : AppTheme.textGray,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ] else if (selectedSubject != null) ...[
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: isDark 
                                    ? Colors.white.withValues(alpha: 0.1)
                                    : AppTheme.primaryBlueLight.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isDark 
                                      ? Colors.white.withValues(alpha: 0.2)
                                      : AppTheme.primaryBlue.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.book_outlined, size: 20, color: isDark ? Colors.white70 : AppTheme.primaryBlue),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Subject: $selectedSubject',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: isDark ? Colors.white : AppTheme.textDark,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ] else ...[
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.orange.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.warning_amber_rounded, size: 20, color: Colors.orange),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'No subjects assigned to this student',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.orange.shade700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
              ],
              
              // Attendance Status Indicator
              if (selectedRollNumber != null) ...[
                _buildAttendanceStatusIndicator(),
                const SizedBox(height: 12),
                // Entry/Exit Status Card
                _buildEntryExitStatusCard(),
              ],
              
              const SizedBox(height: 16),

              // Action Buttons Row
              Row(
                children: [
                  // Mark Absent Button (Quick)
                  Expanded(
                    child: Container(
                      height: 60.h,
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(16.r),
                        border: Border.all(color: Colors.orange, width: 2.w),
                      ),
                      child: ElevatedButton.icon(
                        icon: Icon(Icons.close, color: Colors.orange, size: 18.sp),
                        label: Flexible(
                          child: Text(
                            'Mark Absent',
                            style: TextStyle(
                              fontSize: 13.sp,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          padding: EdgeInsets.symmetric(vertical: 16.h),
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16.r),
                          ),
                        ),
                        onPressed: (selectedRollNumber != null && isAlreadyMarked != true) 
                            ? _markAbsent 
                            : null,
                      ),
                    ),
                  ),
                  SizedBox(width: 12.w),
                  // Mark Present Button (Photo Required) - Entry/Exit/Lecture Scan
                  Expanded(
                    flex: 2,
                    child: Builder(
                      builder: (context) {
                        final isLectureScanMode = attendanceMode == 'lecture_scan';
                        final buttonColor = isEntryPhoto 
                            ? AppTheme.primaryGreen
                            : isLectureScanMode
                                ? AppTheme.primaryBlue
                                : AppTheme.accentOrange;
                        final buttonIcon = isEntryPhoto 
                            ? Icons.login
                            : isLectureScanMode
                                ? Icons.face
                                : Icons.logout;
                        String buttonText;
                        if (isEntryPhoto) {
                          buttonText = 'Take Entry Photo';
                        } else if (isLectureScanMode && currentLectureIndex != null) {
                          buttonText = 'Scan Lecture ${currentLectureIndex! + 1}';
                        } else {
                          buttonText = 'Take Exit Photo';
                        }
                        
                        return Container(
                          height: 60.h,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                buttonColor,
                                buttonColor.withValues(alpha: 0.8),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(16.r),
                            boxShadow: [
                              BoxShadow(
                                color: buttonColor.withValues(alpha: 0.3),
                                blurRadius: 10.r,
                                spreadRadius: 1.w,
                              ),
                            ],
                          ),
                          child: ElevatedButton.icon(
                            icon: Icon(
                              buttonIcon,
                              size: 18.sp,
                              color: Colors.white,
                            ),
                            label: Flexible(
                              child: Text(
                                buttonText,
                                style: TextStyle(
                                  fontSize: 13.sp,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              disabledBackgroundColor: Colors.grey.shade300,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            onPressed: (canMark() && isAlreadyMarked != true) ? _markAttendance : null,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (!isLocationValid)
                _buildGlassInfoCard(
                  icon: Icons.location_off,
                  iconColor: AppTheme.accentRed,
                  title: 'Location Not Verified',
                  message: 'Please enable location services to mark attendance',
                ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }

  Widget _buildModernAppBar() {
    return Container(
      width: double.infinity,
      color: AppTheme.primaryBlue,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Mark Attendance',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.help_outline, color: Colors.white, size: 24),
            onPressed: () {
              Navigator.pushNamed(context, HelpDeskScreen.routeName);
            },
            tooltip: 'Help & Instructions',
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
              color: AppTheme.primaryBlue.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
            child: const Icon(Icons.camera_alt, size: 40, color: AppTheme.primaryBlue),
              ),
              const SizedBox(height: 16),
          Text(
                'Mark Student Attendance',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : AppTheme.textDark,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Follow the steps below to mark attendance',
                style: TextStyle(
                  fontSize: 14,
              color: isDark ? Colors.white70 : AppTheme.textGray,
                ),
              ),
            ],
      ),
    );
  }

  Widget _buildGlassInfoCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String message,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
            child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                  style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : AppTheme.textDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      message,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
            ],
      ),
    );
  }

  Widget _buildStepCard({
    required int stepNumber,
    required String title,
    required IconData icon,
    required Color iconColor,
    required Widget child,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: iconColor.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '$stepNumber',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: iconColor,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(icon, color: iconColor, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                    title,
                      style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : AppTheme.textDark,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              child,
            ],
      ),
    );
  }

  Widget _buildAttendanceStatusIndicator() {
    if (isAlreadyMarked == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Checking attendance status...',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    if (isAlreadyMarked == true) {
      final hasEntry = existingAttendanceData?['entryPhoto'] != null || 
                       existingAttendanceData?['photoUrl'] != null;
      final hasExit = existingAttendanceData?['exitPhoto'] != null;
      
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: (hasEntry && hasExit) 
              ? Colors.orange.withValues(alpha: 0.2)
              : Colors.blue.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: (hasEntry && hasExit) 
                ? Colors.orange.withValues(alpha: 0.5)
                : Colors.blue.withValues(alpha: 0.5),
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Icon(
              (hasEntry && hasExit) 
                  ? Icons.warning_amber_rounded
                  : Icons.info_outline,
              color: (hasEntry && hasExit) ? Colors.orange : Colors.blue,
              size: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (hasEntry && hasExit)
                        ? 'Attendance Fully Marked'
                        : hasEntry
                            ? 'Entry Marked - Exit Pending'
                            : 'Exit Marked - Entry Pending',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (existingMarkTime != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Entry: $existingMarkTime',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 13,
                      ),
                    ),
                  ],
                  if (hasExit && existingAttendanceData != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Exit: ${_formatTime(existingAttendanceData!['exitTime'])}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 13,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    (hasEntry && hasExit)
                        ? 'Both entry and exit photos are recorded. Attendance complete.'
                        : hasEntry
                            ? 'Entry photo recorded. Mark exit when student leaves.'
                            : 'Exit photo recorded. Mark entry when student arrives.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // isAlreadyMarked == false - attendance not marked yet
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.withValues(alpha: 0.5), width: 2),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline, color: Colors.green, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Attendance not marked yet. You can proceed to mark attendance.',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEntryExitStatusCard() {
    if (selectedRollNumber == null || selectedSubject == null) {
      return const SizedBox.shrink();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasEntry = existingAttendanceData?['entryPhoto'] != null || 
                     existingAttendanceData?['photoUrl'] != null;
    final hasExit = existingAttendanceData?['exitPhoto'] != null;

    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.white,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
          color: isDark 
              ? Colors.white.withValues(alpha: 0.3) 
              : AppTheme.primaryBlue.withValues(alpha: 0.3),
          width: 2.w,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12.r,
            offset: Offset(0, 4.h),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.access_time,
                color: isDark ? Colors.white : AppTheme.primaryBlue,
                size: 18.sp,
              ),
              SizedBox(width: 8.w),
              Flexible(
                child: Text(
                  'Entry/Exit Status',
                  style: TextStyle(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : AppTheme.textDark,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
          SizedBox(height: 12.h),
          Row(
            children: [
              // Entry Photo with Timestamp
              Expanded(
                child: _buildPhotoCard(
                  photoUrl: hasEntry 
                      ? (existingAttendanceData?['entryPhoto'] as String? ?? existingAttendanceData?['photoUrl'] as String? ?? '')
                      : null,
                  storagePath: existingAttendanceData?['entryPhotoPath'] as String?,
                  timestamp: _asDateTime(existingAttendanceData?['entryTime']) ?? _asDateTime(existingAttendanceData?['timestamp']),
                  label: 'Entry',
                  isMarked: hasEntry,
                  color: AppTheme.primaryGreen,
                ),
              ),
              SizedBox(width: 12.w),
              // Exit Photo with Timestamp
              Expanded(
                child: _buildPhotoCard(
                  photoUrl: hasExit 
                      ? (existingAttendanceData?['exitPhoto'] as String? ?? '')
                      : null,
                  storagePath: existingAttendanceData?['exitPhotoPath'] as String?,
                  timestamp: _asDateTime(existingAttendanceData?['exitTime']),
                  label: 'Exit',
                  isMarked: hasExit,
                  color: AppTheme.accentOrange,
                ),
              ),
            ],
          ),
          if (!hasEntry || !hasExit) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isEntryPhoto 
                    ? AppTheme.primaryGreen.withValues(alpha: 0.1)
                    : AppTheme.accentOrange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    isEntryPhoto ? Icons.info_outline : Icons.info_outline,
                    color: isEntryPhoto ? AppTheme.primaryGreen : AppTheme.accentOrange,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isEntryPhoto
                          ? 'Ready to mark entry attendance'
                          : 'Ready to mark exit attendance',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white : AppTheme.textDark,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatTime(dynamic timestamp) {
    if (timestamp == null) return '-';
    try {
      final dt = parseAnyTimestamp(timestamp);
      if (dt == null) return '-';
      return DateFormat('hh:mm a').format(dt);
    } catch (e) {
      return '-';
    }
  }

  Widget _buildQueueModeBanner() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primaryBlue.withValues(alpha: 0.1),
            AppTheme.primaryGreen.withValues(alpha: 0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.primaryBlue.withValues(alpha: 0.3),
          width: 2,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.queue,
              color: AppTheme.primaryBlue,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Queue Mode Active',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : AppTheme.textDark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Batch & Subject selected. Students can queue: Select Roll → Take Photo → Done. Next student ready!',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white70 : AppTheme.textGray,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoCard({
    String? photoUrl,
    String? storagePath,
    DateTime? timestamp,
    required String label,
    required bool isMarked,
    required Color color,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return GestureDetector(
      onTap: photoUrl != null && photoUrl.isNotEmpty
          ? () => _showPhotoDialog(photoUrl, storagePath, label, timestamp)
          : null,
      child: Container(
        padding: EdgeInsets.all(12.w),
        decoration: BoxDecoration(
          color: isMarked 
              ? color.withValues(alpha: 0.1)
              : Colors.grey.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(
            color: isMarked ? color : Colors.grey,
            width: 2.w,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Photo or Icon
            if (isMarked && photoUrl != null && photoUrl.isNotEmpty) ...[
              Flexible(
                child: Container(
                  constraints: BoxConstraints(
                    maxHeight: 70.h,
                    minHeight: 50.h,
                  ),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8.r),
                    border: Border.all(
                      color: color.withValues(alpha: 0.3),
                      width: 1.w,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8.r),
                    child: SecureNetworkImage(
                      imageUrl: photoUrl,
                      storagePath: storagePath,
                      fit: BoxFit.cover,
                      placeholder: Container(
                        color: color.withValues(alpha: 0.1),
                        child: Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: color,
                          ),
                        ),
                      ),
                      errorWidget: Container(
                        color: color.withValues(alpha: 0.1),
                        child: Icon(
                          Icons.broken_image,
                          color: color,
                          size: 20.sp,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 6.h),
            ] else ...[
              Icon(
                isMarked ? Icons.check_circle : Icons.radio_button_unchecked,
                color: isMarked ? color : Colors.grey,
                size: 28.sp,
              ),
              SizedBox(height: 4.h),
            ],
            // Label
            Text(
              label,
              style: TextStyle(
                fontSize: 11.sp,
                fontWeight: FontWeight.w600,
                color: isMarked ? color : Colors.grey,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
            // Timestamp
            if (isMarked && timestamp != null) ...[
              SizedBox(height: 2.h),
              Text(
                _formatTime(timestamp),
                style: TextStyle(
                  fontSize: 9.sp,
                  color: isDark ? Colors.white70 : AppTheme.textGray,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showPhotoDialog(String photoUrl, String? storagePath, String label, DateTime? timestamp) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            // Full screen photo
            Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: SecureNetworkImage(
                  imageUrl: photoUrl,
                  storagePath: storagePath,
                  fit: BoxFit.contain,
                  placeholder: const Center(
                    child: CircularProgressIndicator(),
                  ),
                  errorWidget: const Center(
                    child: Icon(
                      Icons.broken_image,
                      size: 80,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
            // Info card at bottom
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.8),
                    ],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (timestamp != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        DateFormat('MMM dd, yyyy • hh:mm a').format(timestamp),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // Close button
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => Navigator.pop(context),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black.withValues(alpha: 0.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModernDropdown({
    required String? value,
    required String label,
    required IconData icon,
    required List<DropdownMenuItem<String>> items,
    required Function(String?) onChanged,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.2) : AppTheme.primaryBlue.withOpacity(0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: DropdownButtonFormField<String>(
        value: value,
        style: TextStyle(
          color: isDark ? Colors.white : AppTheme.textDark,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
            color: isDark ? Colors.white70 : AppTheme.textGray,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          prefixIcon: Icon(
            icon,
            color: isDark ? Colors.white70 : AppTheme.primaryBlue,
            size: 20,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          filled: true,
          fillColor: Colors.transparent,
        ),
        dropdownColor: isDark ? AppTheme.primaryBlueDark : Colors.white,
        icon: Icon(
          Icons.arrow_drop_down,
          color: isDark ? Colors.white70 : AppTheme.primaryBlue,
        ),
        iconSize: 28,
        menuMaxHeight: 300,
        items: items,
        selectedItemBuilder: (BuildContext context) {
          return items.map<Widget>((DropdownMenuItem<String> item) {
            String displayText = item.value ?? '';
            // Try to extract text from child if it's a Text widget
            if (item.child is Text) {
              final textWidget = item.child as Text;
              displayText = textWidget.data ?? item.value ?? '';
            }
            return Align(
              alignment: Alignment.centerLeft,
              child: Text(
                displayText,
                style: TextStyle(
                  color: isDark ? Colors.white : AppTheme.textDark,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            );
          }).toList();
        },
        onChanged: onChanged,
      ),
    );
  }

  /// Compress image to target size (max 50KB)
  Future<Uint8List> _compressImage(Uint8List imageBytes, {required int maxSizeKB}) async {
    try {
      final maxSizeBytes = maxSizeKB * 1024;
      var decodedImage = img.decodeImage(imageBytes);
      if (decodedImage == null) return imageBytes;

      // Start with quality 85 and reduce if needed
      int quality = 85;
      Uint8List compressedBytes = imageBytes;

      // If image is still too large, resize it
      if (imageBytes.length > maxSizeBytes * 2) {
        final scale = 0.7; // Reduce to 70% of original size
        final newWidth = (decodedImage.width * scale).round();
        final newHeight = (decodedImage.height * scale).round();
        decodedImage = img.copyResize(decodedImage, width: newWidth, height: newHeight);
      }

      // Try different quality levels until we get under the limit
      while (compressedBytes.length > maxSizeBytes && quality > 20) {
        compressedBytes = Uint8List.fromList(
          img.encodeJpg(decodedImage, quality: quality),
        );
        quality -= 10;
      }

      // If still too large, resize more aggressively
      if (compressedBytes.length > maxSizeBytes) {
        final scale = 0.5; // Reduce to 50% of original size
        final newWidth = (decodedImage.width * scale).round();
        final newHeight = (decodedImage.height * scale).round();
        decodedImage = img.copyResize(decodedImage, width: newWidth, height: newHeight);
        compressedBytes = Uint8List.fromList(
          img.encodeJpg(decodedImage, quality: 60),
        );
      }

      if (kDebugMode) {
        debugPrint('📸 Image compression: ${(imageBytes.length / 1024).toStringAsFixed(2)} KB -> ${(compressedBytes.length / 1024).toStringAsFixed(2)} KB');
      }

      return compressedBytes;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error compressing image: $e');
      return imageBytes; // Return original if compression fails
    }
  }
}
