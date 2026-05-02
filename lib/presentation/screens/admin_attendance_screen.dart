import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint, kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_db.dart';
import '../../core/attendance_auto_close_policy.dart';
import '../../core/time_parse.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:image/image.dart' as img;
import '../../services/institute_lecture_timing_service.dart';
import '../../services/storage_service.dart';
import '../../services/device_fingerprint_service.dart';
import '../../services/photo_verification_service.dart';
import '../../services/network_verification_service.dart';
import '../../services/suspicious_activity_service.dart';
import '../../services/firestore_retry_service.dart';
import '../../services/geofence_service.dart';
import '../../services/gps_fence_sample.dart';
import '../../services/hierarchical_attendance_service.dart';
import '../../services/stale_attendance_reconciliation_service.dart';
import '../../services/institute_notification_service.dart';
// Face recognition enabled - mandatory security (on-device MobileFaceNet)
import '../../services/face_recognition_service.dart';
import '../../services/liveness_detection_service.dart';
import '../../services/institute_status_service.dart';
import '../../services/student_validation_service.dart';
import '../../services/session_manager.dart';
import '../../core/theme/app_theme.dart';
import '../../core/gps_attendance_constants.dart';
import '../../core/utils/responsive_page.dart';
import '../../core/utils/professional_messaging.dart';
import '../../utils/performance_utils.dart';
import 'help_desk_screen.dart';
import 'login_screen.dart';
import '../widgets/secure_network_image.dart';
import '../widgets/session_monitor.dart';
// import '../widgets/face_scanner_widget.dart';

class AdminAttendanceScreen extends StatefulWidget {
  static const routeName = '/admin-attendance';

  /// When set (e.g. from Student Management), opens attendance with this roll pre-selected.
  final String? initialRollNumber;

  /// When true, user is `attendance_user`: back button becomes sign-out; GPS uses institute admin fence.
  final bool restrictToAttendanceOnly;

  const AdminAttendanceScreen({
    super.key,
    this.initialRollNumber,
    this.restrictToAttendanceOnly = false,
  });

  @override
  State<AdminAttendanceScreen> createState() => _AdminAttendanceScreenState();
}

class _AdminAttendanceScreenState extends State<AdminAttendanceScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
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

  /// Mirror entry/exit into `attendance_in_out` (student_id = students.id) for reports & Student Photos.
  Future<void> _syncAttendanceInOut({
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
    if (instituteId == null) return;
    try {
      final key = roll.trim();
      var row = await _db
          .from('students')
          .select('id,name,user_id,sr_no')
          .eq('institute_id', instituteId!)
          .eq('user_id', key)
          .maybeSingle();
      row ??= await _db
          .from('students')
          .select('id,name,user_id,sr_no')
          .eq('institute_id', instituteId!)
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
      await HierarchicalAttendanceService().saveAttendance(
        instituteCode: instituteId!,
        studentId: sid,
        studentName: name,
        srNo: srNo,
        date: date,
        type: type,
        photoUrl: photoUrl,
        photoPath: photoPath,
        photoFileId: photoFileId,
        recordedAtUtcIso: recordedAtUtc,
        additionalData: {
          'rollNumber': roll,
          'source': 'admin_attendance',
          if (subj != null && subj.isNotEmpty) 'subject': subj,
          if (sessionEntryUtc != null && sessionEntryUtc.trim().isNotEmpty)
            'entryTime': sessionEntryUtc.trim(),
          if (sessionExitUtc != null && sessionExitUtc.trim().isNotEmpty)
            'exitTime': sessionExitUtc.trim(),
          if (hours != null) 'hours': hours,
          if (status != null && status.isNotEmpty) 'status': status,
        },
      );
      if (kDebugMode) debugPrint('✅ attendance_in_out: $type for roll $roll (student id $sid)');
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ attendance_in_out sync failed: $e');
    }
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
  final InstituteLectureTimingService _lectureTimingService = InstituteLectureTimingService();
  final GeofenceService _geofenceService = GeofenceService();

  String? instituteId;
  String? selectedSubject;
  String? selectedTiming;
  String? selectedRollNumber;
  String? _selectedStudentYear;
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

  /// One enrolled subject selected for the current entry/exit pair (non-legacy days).
  String? activeAttendanceSubject;
  /// True when today's payload uses top-level entry/exit only (older rows until exit completes).
  bool _legacyDayAttendance = false;

  static const String _kSubjectSessionsKey = 'subjectSessions';

  /// Server-side search; avoids downloading full institute rosters.
  static const int _kAttendanceRosterLimit = 400;

  List<String> filteredStudents = []; // Roster rows from `institute_attendance_roll_search`
  bool isLoadingRoster = false;
  final TextEditingController _searchController = TextEditingController();
  late Debouncer _searchDebouncer; // Debounce search input to prevent rapid rebuilds

  Timer? _autoMarkAbsentTimer; // Timer for periodic auto-mark absent check
  Timer? _gpsServerSyncTimer; // Re-read gps_settings (e.g. web unlock / re-lock)
  /// Ticks every second while entry is done and exit pending (session duration UI).
  Timer? _entrySessionTicker;
  RealtimeChannel? _studentsRealtimeChannel;
  RealtimeChannel? _attendanceRealtimeChannel;
  Timer? _realtimeRefreshDebounce;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Initialize debouncer for search with 500ms delay to prevent widget tree corruption
    _searchDebouncer = Debouncer(delay: const Duration(milliseconds: 500));

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOut),
    );
    _fadeController.forward();
    _searchController.addListener(_onRosterSearchChanged);
    _init();
  }

  @override
  void dispose() {
    _autoMarkAbsentTimer?.cancel();
    _gpsServerSyncTimer?.cancel();
    _entrySessionTicker?.cancel();
    _realtimeRefreshDebounce?.cancel();
    if (_studentsRealtimeChannel != null) _db.removeChannel(_studentsRealtimeChannel!);
    if (_attendanceRealtimeChannel != null) _db.removeChannel(_attendanceRealtimeChannel!);
    _searchController.removeListener(_onRosterSearchChanged);
    _searchDebouncer.dispose(); // Dispose debouncer to cleanup timer
    WidgetsBinding.instance.removeObserver(this);
    _fadeController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _checkLocation(showUserMessages: false);
    }
  }

  void _startGpsServerSyncTimer() {
    _gpsServerSyncTimer?.cancel();
    _gpsServerSyncTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      if (!mounted) return;
      _checkLocation(showUserMessages: false);
    });
  }

  Future<void> _init() async {
    await _loadInstitute();
    await _loadAttendanceRoster();
    await _checkLocation();
    final pre = widget.initialRollNumber?.trim();
    if (pre != null && pre.isNotEmpty) {
      await _applyPreselectedRoll(pre);
    }
    // Check for missing exit photos and mark as absent
    _checkAndMarkMissingExits();
    // Schedule periodic check every 15 minutes
    _startAutoMarkAbsentTimer();
    // Pick up GPS lock changes from web / other devices
    _startGpsServerSyncTimer();
    await _subscribeRealtime();
  }

  /// Same as choosing a roll from the dropdown: subject + today's entry/exit state.
  Future<void> _applyPreselectedRoll(String roll) async {
    if (!mounted) return;
    setState(() {
      selectedRollNumber = roll;
      isAlreadyMarked = null;
      existingMarkTime = null;
      attendanceMode = null;
      currentLectureIndex = null;
      selectedSubject = null;
      selectedTiming = null;
      _selectedStudentYear = null;
      studentEnrolledSubjects = [];
      activeAttendanceSubject = null;
      _legacyDayAttendance = false;
      _searchController.text = roll;
    });
    await _loadAttendanceRoster();
    await _fetchStudentDataForRoll(roll);
    await _checkAttendanceStatus();
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

  /// After institute hours we **do not** mark absent for missing exits — presence is hours-based;
  /// stale sessions are reconciled separately when attendance is loaded/marked.
  Future<void> _checkAndMarkMissingExits() async {
    if (instituteId == null) return;

    try {
      final blockMessage =
          await InstituteStatusService().attendanceBlockMessage(instituteId!);
      if (blockMessage != null) {
        if (kDebugMode) debugPrint('Skipping post-close attendance sweep: $blockMessage');
        return;
      }

      final instituteRow = await _db.from('institutes').select('lecture_close_time').eq('id', instituteId!).maybeSingle();
      if (instituteRow == null) return;

      final closeTimeRaw = instituteRow['lecture_close_time'];
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

      final closeMinutes = closeTime.hour * 60 + closeTime.minute;
      const bufferMinutes = 30;
      final finalCloseTime = closeMinutes + bufferMinutes;

      final currentTime = DateTime.now();
      final currentMinutes = currentTime.hour * 60 + currentTime.minute;

      if (currentMinutes <= finalCloseTime) {
        if (kDebugMode) {
          debugPrint('⏰ Institute hours not complete yet. Close time: ${closeTime.hour}:${closeTime.minute.toString().padLeft(2, '0')} (+30 min buffer)');
        }
        return;
      }

      if (kDebugMode) {
        debugPrint('✅ Post-close sweep: skip absent-for-missing-exit (hours-based policy).');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error checking missing exits: $e');
    }
  }

  /// Load subjects and schedule timing for the selected roll (institute hours / legacy row timing).
  Future<void> _fetchStudentDataForRoll(String rollNumber) async {
    if (instituteId == null) return;

    try {
      final key = rollNumber.trim();
      var studentRow = await _db
          .from('students')
          .select()
          .eq('institute_id', instituteId!)
          .eq('user_id', key)
          .maybeSingle();
      studentRow ??= await _db
          .from('students')
          .select()
          .eq('institute_id', instituteId!)
          .eq('sr_no', key)
          .maybeSingle();
      if (!mounted) return;

      if (studentRow == null) {
        if (kDebugMode) debugPrint('⚠️ Student not found: $rollNumber');
        return;
      }

      final studentData = Map<String, dynamic>.from(studentRow);
      final studentSubjects = studentData['subjects'] as List<dynamic>?;
      final studentStoredSlots =
          studentData['lectureTiming'] as String? ??
          studentData['lecture_timing'] as String?;
      final y = studentData['year']?.toString().trim();

      final instituteSlots = await _lectureTimingService.buildLectureTimingString(instituteId!);
      final timing = (studentStoredSlots != null && studentStoredSlots.trim().isNotEmpty)
          ? studentStoredSlots.trim()
          : instituteSlots;

      if (studentSubjects != null && studentSubjects.isNotEmpty) {
        final subs = studentSubjects.map((s) => s.toString()).toList();
        setState(() {
          studentEnrolledSubjects = subs;
          selectedSubject = subs.join(', ');
          selectedTiming = timing;
          _selectedStudentYear = (y != null && y.isNotEmpty) ? y : null;
        });
        if (kDebugMode) {
          debugPrint('✅ Loaded student $rollNumber: subjects=$selectedSubject timing=$timing');
        }
      } else {
        final singleSubject = studentData['subject']?.toString().trim();
        if (singleSubject != null && singleSubject.isNotEmpty) {
          setState(() {
            studentEnrolledSubjects = [singleSubject];
            selectedSubject = singleSubject;
            selectedTiming = timing;
            _selectedStudentYear = (y != null && y.isNotEmpty) ? y : null;
          });
          if (kDebugMode) {
            debugPrint('✅ Loaded student $rollNumber: subject column=$singleSubject timing=$timing');
          }
        } else {
          setState(() {
            studentEnrolledSubjects = [];
            selectedSubject = null;
            selectedTiming = timing;
            _selectedStudentYear = (y != null && y.isNotEmpty) ? y : null;
          });
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
                      'Student with roll number $rollNumber has no subjects assigned.\n\n'
                      'Add subjects for this student in Student Management → Edit.',
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
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error fetching student data: $e');
    }
  }

  void _onRosterSearchChanged() {
    if (!mounted) return;
    setState(() {});
    _searchDebouncer(() {
      if (mounted) _loadAttendanceRoster();
    });
  }

  int _compareRollIds(String a, String b) {
    final na = int.tryParse(a);
    final nb = int.tryParse(b);
    if (na != null && nb != null) return na.compareTo(nb);
    if (na != null) return -1;
    if (nb != null) return 1;
    return a.compareTo(b);
  }

  Future<void> _loadAttendanceRoster() async {
    if (instituteId == null) return;

    setState(() => isLoadingRoster = true);
    try {
      final q = _searchController.text.trim();
      final raw = await _db.rpc(
        'institute_attendance_roll_search',
        params: {
          'p_institute_id': instituteId!,
          'p_search': q,
          'p_limit': _kAttendanceRosterLimit,
        },
      );
      if (!mounted) return;

      final rolls = <String>[];
      if (raw is List) {
        for (final e in raw) {
          if (e is Map) {
            final r = e['roll']?.toString().trim() ?? '';
            if (r.isNotEmpty) rolls.add(r);
          }
        }
      }

      final sel = selectedRollNumber?.trim();
      if (sel != null && sel.isNotEmpty && !rolls.contains(sel)) {
        rolls.add(sel);
      }
      rolls.sort(_compareRollIds);

      setState(() {
        filteredStudents = rolls;
        isLoadingRoster = false;
        isLoading = false;
      });
    } catch (e) {
      if (kDebugMode) debugPrint('institute_attendance_roll_search failed, legacy roster load: $e');
      await _loadAttendanceRosterLegacy();
    }
  }

  /// If RPC is missing (migration not applied), cap rows transferred to the client.
  Future<void> _loadAttendanceRosterLegacy() async {
    if (instituteId == null) return;
    try {
      final rows = await _db
          .from('students')
          .select('user_id,sr_no')
          .eq('institute_id', instituteId!)
          .limit(8000);
      if (!mounted) return;

      final rollSet = <String>{};
      for (final r in rows) {
        final u = (r['user_id'] as String?)?.trim() ?? '';
        final s = (r['sr_no'] as String?)?.trim() ?? '';
        if (u.isNotEmpty) rollSet.add(u);
        if (s.isNotEmpty) rollSet.add(s);
      }

      final q = _searchController.text.trim().toLowerCase();
      var list = rollSet.toList();
      if (q.isNotEmpty) {
        list = list.where((roll) => roll.toLowerCase().contains(q)).toList();
      }
      list.sort(_compareRollIds);
      if (list.length > _kAttendanceRosterLimit) {
        list = list.sublist(0, _kAttendanceRosterLimit);
      }

      final sel = selectedRollNumber?.trim();
      if (sel != null && sel.isNotEmpty && !list.contains(sel)) {
        list = [sel, ...list];
        if (list.length > _kAttendanceRosterLimit) {
          list = list.sublist(0, _kAttendanceRosterLimit);
        }
      }

      setState(() {
        filteredStudents = list;
        isLoadingRoster = false;
        isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoadingRoster = false;
          isLoading = false;
        });
      }
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
        if (!mounted) return;
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
        if (!mounted) return;
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

  /// Fence in [gps_settings] — staff uses the institute’s locked attendance row (same as admin’s configured point).
  Future<String?> _gpsSettingsAdminId() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null || instituteId == null || instituteId!.isEmpty) return uid;
    try {
      final me = await _db.from('profiles').select('role').eq('id', uid).maybeSingle();
      if ((me?['role'] as String?) != 'attendance_user') return uid;

      final fenceAdmin = await _geofenceService.lockedFenceAdminIdForInstitute(instituteId!);
      if (fenceAdmin != null && fenceAdmin.isNotEmpty) return fenceAdmin;

      final adminRow = await _db
          .from('profiles')
          .select('id')
          .eq('institute_id', instituteId!)
          .eq('role', 'admin')
          .limit(1)
          .maybeSingle();
      return (adminRow?['id'] as String?) ?? uid;
    } catch (_) {
      return uid;
    }
  }

  Future<void> _subscribeRealtime() async {
    if (instituteId == null || instituteId!.isEmpty) return;

    if (_studentsRealtimeChannel != null) {
      await _db.removeChannel(_studentsRealtimeChannel!);
      _studentsRealtimeChannel = null;
    }
    if (_attendanceRealtimeChannel != null) {
      await _db.removeChannel(_attendanceRealtimeChannel!);
      _attendanceRealtimeChannel = null;
    }

    void scheduleRefresh({bool attendanceOnly = false}) {
      _realtimeRefreshDebounce?.cancel();
      _realtimeRefreshDebounce = Timer(const Duration(milliseconds: 600), () async {
        if (!mounted || instituteId == null) return;
        if (!attendanceOnly) {
          await _loadAttendanceRoster();
        }
        if (selectedRollNumber != null && selectedRollNumber!.trim().isNotEmpty) {
          await _fetchStudentDataForRoll(selectedRollNumber!);
          await _checkAttendanceStatus();
        }
      });
    }

    _studentsRealtimeChannel = _db
        .channel('admin-attendance-students-$instituteId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'students',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'institute_id',
            value: instituteId!,
          ),
          callback: (_) {
            if (kDebugMode) {
              debugPrint('🔄 Admin attendance realtime student update for institute $instituteId');
            }
            scheduleRefresh();
          },
        )
        .subscribe();

    _attendanceRealtimeChannel = _db
        .channel('admin-attendance-marks-$instituteId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'teacher_attendance',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'institute_id',
            value: instituteId!,
          ),
          callback: (_) {
            if (kDebugMode) {
              debugPrint('🔄 Admin attendance realtime mark update for institute $instituteId');
            }
            scheduleRefresh(attendanceOnly: true);
          },
        )
        .subscribe();
  }

  /* ---------------- LOCATION ---------------- */

  Future<void> _checkLocation({bool showUserMessages = true}) async {
    try {
      LocationPermission p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) {
        p = await Geolocator.requestPermission();
      }
      if (p == LocationPermission.denied ||
          p == LocationPermission.deniedForever) {
        isLocationValid = false;
      } else {
        await _checkLocationLockStatus(showUserMessages: showUserMessages);
        final withinRadius = await _checkGPSRadius(showUserMessages: showUserMessages);
        isLocationValid = withinRadius;
      }
    } catch (_) {
      isLocationValid = false;
    }
    if (mounted) setState(() {});
  }

  /// Check location lock status and show appropriate messages
  Future<void> _checkLocationLockStatus({bool showUserMessages = true}) async {
    if (instituteId == null || instituteId!.isEmpty) return;
    final currentUser = _db.auth.currentUser;
    if (currentUser == null) return;

    try {
      final gpsUid = await _gpsSettingsAdminId();
      final locationStatus = await _geofenceService.checkAdminLocationStatus(
        instituteId: instituteId!,
        adminId: gpsUid ?? currentUser.id,
      );

      final isLocked = locationStatus['isLocked'] as bool;
      final hasLocation = locationStatus['hasLocation'] as bool;
      final isWithinRadius = locationStatus['isWithinRadius'] as bool?;
      final distance = locationStatus['distance'] as double?;

      // Check radius status (15 m is enforced from the locked point, regardless of lock label in messages)
      if (hasLocation && isWithinRadius != null) {
        final rLabel = kAttendanceFenceRadiusMeters.toStringAsFixed(0);
        if (isWithinRadius == false && distance != null) {
          // Admin is OUT OF RADIUS — cannot mark attendance
          if (showUserMessages && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '❌ Out of radius: You are ${distance.toStringAsFixed(0)}m away. Attendance can only be marked within ${rLabel}m of the locked point.',
                ),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 6),
              ),
            );
          }
        } else if (isWithinRadius == true) {
          if (showUserMessages && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  isLocked
                      ? '✅ Location is locked — you are within ${rLabel}m. You can mark attendance.'
                      : '⚠️ Save and lock your location in GPS Settings before marking attendance (you are within ${rLabel}m).',
                ),
                backgroundColor: isLocked ? Colors.green : Colors.orange,
                duration: const Duration(seconds: 4),
              ),
            );
          }
        }
      } else if (!isLocked && hasLocation && isWithinRadius == null) {
        // Location is unlocked but unable to verify radius
        if (showUserMessages && mounted) {
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

  /// GPS radius check: fixed fence + accuracy buffer, with multiple samples (indoor drift).
  /// Uses admin's own GPS settings (cross-device locking)
  Future<bool> _checkGPSRadius({bool showUserMessages = true}) async {
    if (kIsWeb) return true; // Web bypass for testing

    // ✅ DEBUG MODE BYPASS: Allow testing from any location in debug mode
    if (kDebugMode) {
      if (showUserMessages && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🔧 DEBUG MODE: GPS check bypassed. You can test from any location.'),
            backgroundColor: Colors.blue,
            duration: Duration(seconds: 3),
          ),
        );
      }
      return true;
    }

    if (instituteId == null || instituteId!.isEmpty) {
      return false;
    }

    final currentUser = _db.auth.currentUser;
    if (currentUser == null) {
      return false;
    }

    final gpsAdminId = await _gpsSettingsAdminId();
    if (gpsAdminId == null) {
      return false;
    }

    try {
      final configRow = await _db
          .from('gps_settings')
          .select()
          .eq('institute_id', instituteId!)
          .eq('admin_id', gpsAdminId)
          .maybeSingle();

      if (configRow == null) {
        if (showUserMessages && mounted) {
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

      final double radius = kAttendanceFenceRadiusMeters;

      if (latitude == null || longitude == null || latitude == 0.0 || longitude == 0.0) {
        if (showUserMessages && mounted) {
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
        if (showUserMessages && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ Lock your location in GPS Settings before marking attendance.'),
              backgroundColor: Colors.red,
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
        if (showUserMessages && mounted) {
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
        if (showUserMessages && mounted) {
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

      final distance = sample.bestDistanceMeters;
      final gpsAccuracy = sample.accuracyUsedForMessage;
      final effectiveRadius = radius + (gpsAccuracy > 0 ? gpsAccuracy.clamp(12.0, 100.0) : 12.0);

      if (kDebugMode) {
        debugPrint('📍 Location Check (Admin: ${currentUser.id}, multi-sample):');
        debugPrint('   Locked: Lat=$latitude, Lng=$longitude');
        debugPrint('   Best distance: ${distance.toStringAsFixed(1)}m');
        debugPrint('   Within fence: ${sample.isWithinFence}');
      }

      if (!sample.isWithinFence) {
        if (showUserMessages && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '❌ Out of radius: closest reading ~${distance.toStringAsFixed(0)}m (several GPS samples)',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Indoor GPS often jumps; we already tried multiple readings.\n'
                    'Target: about ${radius.toStringAsFixed(0)}m + accuracy (up to ~${(radius + 100).toStringAsFixed(0)}m when signal is weak).\n\n'
                    '💡 Try: window/open area, wait a few seconds, or re-save the lock point in GPS Settings if it was set incorrectly.\n'
                    'Locked: ${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 14),
            ),
          );
        }
        return false;
      }

      if (distance <= radius) {
        if (kDebugMode) {
          debugPrint('✅ Within base radius (${radius.toStringAsFixed(0)}m) - Attendance allowed');
        }
        return true;
      }

      if (kDebugMode) {
        debugPrint(
          '⚠️ Allowed within effective radius (~${effectiveRadius.toStringAsFixed(0)}m) using accuracy buffer',
        );
      }
      return true;
    } catch (e) {
      if (showUserMessages && mounted) {
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

  /// Checks if student has a profile photo in database (registration completion check)
  /// Prevents marking attendance for students who haven't finished registration
  Future<bool> _checkStudentProfilePhoto(String rollNumber) async {
    if (instituteId == null) return false;

    try {
      final roll = rollNumber.trim();

      // First try matching by user_id (roll number)
      var studentRow = await _db
          .from('students')
          .select('id,face_photo_url,face_embedding')
          .eq('institute_id', instituteId!)
          .eq('user_id', roll)
          .maybeSingle();

      // If not found, try matching by sr_no (serial number)
      if (studentRow == null) {
        studentRow = await _db
            .from('students')
            .select('id,face_photo_url,face_embedding')
            .eq('institute_id', instituteId!)
            .eq('sr_no', roll)
            .maybeSingle();
      }

      if (studentRow == null) {
        return false;  // Student not found
      }

      final photoUrl = studentRow['face_photo_url'] as String?;
      final faceEmbedding = studentRow['face_embedding'];

      // Check if BOTH photo AND face embedding exist (indicates completed registration)
      if ((photoUrl != null && photoUrl.isNotEmpty) && faceEmbedding != null) {
        if (kDebugMode) {
          debugPrint('✅ Student has profile photo and face embedding - registration complete');
        }
        return true;  // Has both photo and embedding = registration complete
      }

      if (kDebugMode) {
        debugPrint('❌ Student profile incomplete - missing photo: ${photoUrl?.isEmpty ?? true}, missing embedding: ${faceEmbedding == null}');
      }
      return false;  // Missing photo or embedding = registration incomplete
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error checking student profile photo: $e');
      }
      return false;
    }
  }

  /// Validates that the selected student exists in the database
  /// Prevents marking attendance for non-existent or invalid students
  Future<bool> _validateStudentExists(String rollNumber) async {
    if (instituteId == null) return false;

    try {
      final roll = rollNumber.trim();

      // First try matching by user_id (roll number)
      var studentRow = await _db
          .from('students')
          .select('id,user_id,sr_no,name')
          .eq('institute_id', instituteId!)
          .eq('user_id', roll)
          .maybeSingle();

      // If not found, try matching by sr_no (serial number)
      if (studentRow == null) {
        studentRow = await _db
            .from('students')
            .select('id,user_id,sr_no,name')
            .eq('institute_id', instituteId!)
            .eq('sr_no', roll)
            .maybeSingle();
      }

      if (studentRow != null) {
        if (kDebugMode) {
          debugPrint('✅ Student validated: ${studentRow['name']} (${studentRow['user_id'] ?? studentRow['sr_no']})');
        }
        return true;
      }

      if (kDebugMode) {
        debugPrint('❌ Student not found in database: $roll');
      }
      return false;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Student validation error: $e');
      }
      return false;
    }
  }

  /// Compares the captured attendance photo with the student's face embedding
  /// Uses SAME face verification logic as student registration
  /// Returns {isMatch: bool, reason: String?, confidence: double?}
  Future<Map<String, dynamic>> _compareStudentPhoto(String rollNumber, String capturedPhotoPath) async {
    if (instituteId == null) {
      return {'isMatch': false, 'reason': 'Institute ID not found'};
    }

    try {
      final roll = rollNumber.trim();

      final workPath = await FaceRecognitionService.ensureNormalizedJpegForFacePipeline(capturedPhotoPath);
      String? tempToDelete;
      if (workPath != capturedPhotoPath) {
        tempToDelete = workPath;
      }

      // Step 1: Extract face features from captured photo (same as registration)
      final capturedFeatures = await FaceRecognitionService.extractFaceFeatures(workPath);
      if (!mounted) {
        if (tempToDelete != null) {
          try {
            await File(tempToDelete).delete();
          } catch (_) {}
        }
        return {'isMatch': false, 'reason': 'Could not extract face features'};
      }
      if (capturedFeatures == null) {
        final reason = await FaceRecognitionService.getDiagnosticReasonForInvalidFace(workPath) ??
            'Face not accepted. Check lighting, one clear face, and look at the camera.';
        if (tempToDelete != null) {
          try {
            await File(tempToDelete).delete();
          } catch (_) {}
        }
        return {'isMatch': false, 'reason': reason};
      }

      // Step 2: Extract neural embedding from captured photo
      final capturedEmbedding = await FaceRecognitionService.extractNeuralEmbedding(
        workPath,
        capturedFeatures,
      );
      if (tempToDelete != null) {
        try {
          await File(tempToDelete).delete();
        } catch (_) {}
        tempToDelete = null;
      }
      if (!mounted) return {'isMatch': false, 'reason': 'Could not extract face embedding'};
      if (capturedEmbedding == null) {
        return {
          'isMatch': false,
          'reason': 'Neural face read failed. Try a clearer, closer photo with the face well lit.',
        };
      }

      // Step 3: Get student's stored face embedding from database
      var studentRow = await _db
          .from('students')
          .select('id,user_id,sr_no,name,face_embedding')
          .eq('institute_id', instituteId!)
          .eq('user_id', roll)
          .maybeSingle();

      if (studentRow == null) {
        studentRow = await _db
            .from('students')
            .select('id,user_id,sr_no,name,face_embedding')
            .eq('institute_id', instituteId!)
            .eq('sr_no', roll)
            .maybeSingle();
      }

      if (studentRow == null) {
        return {'isMatch': false, 'reason': 'Student profile not found'};
      }

      final studentName = studentRow['name'] as String? ?? 'Unknown';
      final faceTemplate = studentRow['face_embedding'];

      if (kDebugMode) {
        debugPrint('🔍 Verifying attendance for $studentName (Roll: $roll)');
      }

      // If student has no face embedding from registration, can't verify
      if (faceTemplate == null) {
        if (kDebugMode) {
          debugPrint('⚠️ Student $studentName has no face embedding. Student may not have completed registration.');
        }
        return {
          'isMatch': false,
          'reason': 'Student registration incomplete (missing face data). Please contact administrator.'
        };
      }

      // Step 4: Extract stored embedding from face template map
      final storedEmbedding = (faceTemplate is Map ? faceTemplate['embedding'] : faceTemplate) as List<dynamic>?;
      if (storedEmbedding == null) {
        return {
          'isMatch': false,
          'reason': 'Stored face embedding is invalid. Please contact administrator.'
        };
      }

      // Convert to List<double>
      final storedEmbeddingList = List<double>.from(storedEmbedding.map((x) => (x as num).toDouble()));

      // Step 5: Compare embeddings using cosine similarity
      final similarity = FaceRecognitionService.calculateCosineSimilarity(
        capturedEmbedding,
        storedEmbeddingList,
      );

      if (kDebugMode) {
        debugPrint('🔍 Face match for $studentName:');
        debugPrint('   Similarity score: ${(similarity * 100).toStringAsFixed(1)}%');
      }

      // Use same thresholds as student registration
      if (similarity >= 0.70) {
        // High confidence match (70%+)
        return {
          'isMatch': true,
          'confidence': similarity,
          'reason': 'Face verified successfully'
        };
      } else if (similarity >= 0.60) {
        // Medium-high confidence - allow but log
        if (kDebugMode) {
          debugPrint('⚠️ Medium confidence face match (${(similarity * 100).toStringAsFixed(1)}%)');
        }
        return {
          'isMatch': true,
          'confidence': similarity,
          'reason': 'Face match (${(similarity * 100).toStringAsFixed(0)}% similarity)'
        };
      } else {
        // Low confidence - reject
        return {
          'isMatch': false,
          'confidence': similarity,
          'reason': 'Face does not match student profile (${(similarity * 100).toStringAsFixed(0)}% similarity)'
        };
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Student photo comparison error: $e');
      }
      return {'isMatch': false, 'reason': 'Photo verification failed: ${e.toString()}'};
    }
  }

  Map<String, Map<String, dynamic>> _mapSubjectSessions(Map<String, dynamic>? payload) {
    final out = <String, Map<String, dynamic>>{};
    if (payload == null) return out;
    final raw = payload[_kSubjectSessionsKey];
    if (raw is! Map) return out;
    for (final e in raw.entries) {
      final v = e.value;
      if (v is Map) {
        out[e.key.toString()] =
            Map<String, dynamic>.from(v.map((k, val) => MapEntry(k.toString(), val)));
      }
    }
    return out;
  }

  Map<String, dynamic> _sessionForSubject(Map<String, Map<String, dynamic>> sessions, String subject) {
    return Map<String, dynamic>.from(sessions[subject] ?? {});
  }

  /// [subjectSessions] keys may differ from enrollment by whitespace-only mismatch.
  String? _subjectSessionsMapKey(Map<String, Map<String, dynamic>> sessions, String label) {
    if (sessions.containsKey(label)) return label;
    final t = label.trim();
    for (final k in sessions.keys) {
      if (k.toString().trim() == t) return k.toString();
    }
    return null;
  }

  /// Which subject slice to show for thumbnails, timers (non-legacy).
  String? _displaySubjectSliceForSessions() {
    if (_legacyDayAttendance || studentEnrolledSubjects.isEmpty) return null;
    final payload = existingAttendanceData;
    if (payload == null) return null;
    final sessions = _mapSubjectSessions(payload);
    if (sessions.isEmpty) return null;

    final active = activeAttendanceSubject?.trim();
    if (active != null && active.isNotEmpty) {
      final k = _subjectSessionsMapKey(sessions, active);
      if (k != null) return k;
    }

    final pending = _pendingSubjectFromPayload(payload);
    if (pending != null && pending.trim().isNotEmpty) {
      final k = _subjectSessionsMapKey(sessions, pending);
      if (k != null) return k;
    }

    for (final sub in studentEnrolledSubjects) {
      final k = _subjectSessionsMapKey(sessions, sub);
      if (k == null) continue;
      final sess = sessions[k]!;
      if (_sessionHasEntryMap(sess) || _sessionCompleteMap(sess)) return k;
    }

    return studentEnrolledSubjects.length == 1
        ? _subjectSessionsMapKey(sessions, studentEnrolledSubjects.first)
        : null;
  }

  bool _sessionHasEntryMap(Map<String, dynamic> s) {
    return s['entryPhoto'] != null ||
        s['photoUrl'] != null ||
        s['entry_photo'] != null ||
        s['entryTime'] != null ||
        s['entry_time'] != null ||
        s['timestamp'] != null;
  }

  bool _sessionCompleteMap(Map<String, dynamic> s) {
    return s['exitPhoto'] != null ||
        s['exit_photo'] != null ||
        s['exitTime'] != null ||
        s['exit_time'] != null;
  }

  /// First non-empty string among keys (camelCase / legacy snake_case in JSON).
  String? _stringField(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }

  String? _sessionEntryPhotoUrl(Map<String, dynamic> s) =>
      _stringField(s, ['entryPhoto', 'photoUrl', 'entry_photo']);

  String? _sessionEntryPhotoPath(Map<String, dynamic> s) =>
      _stringField(s, ['entryPhotoPath', 'storagePath', 'entry_photo_path']);

  String? _sessionExitPhotoUrl(Map<String, dynamic> s) =>
      _stringField(s, ['exitPhoto', 'exit_photo']);

  String? _sessionExitPhotoPath(Map<String, dynamic> s) =>
      _stringField(s, ['exitPhotoPath', 'exit_photo_path']);

  String? _pendingSubjectFromPayload(Map<String, dynamic>? payload) {
    if (payload == null) return null;
    final m = _mapSubjectSessions(payload);
    for (final e in m.entries) {
      if (_sessionHasEntryMap(e.value) && !_sessionCompleteMap(e.value)) return e.key;
    }
    return null;
  }

  String? _nextUnlockedSubjectFromPayload(Map<String, dynamic>? payload) {
    if (_legacyDayAttendance || studentEnrolledSubjects.isEmpty) return null;
    final sessions = _mapSubjectSessions(payload);

    final pending = _pendingSubjectFromPayload(payload);
    if (pending != null && pending.trim().isNotEmpty) {
      return pending;
    }

    final active = activeAttendanceSubject?.trim();
    if (active != null &&
        active.isNotEmpty &&
        studentEnrolledSubjects.contains(active) &&
        !_sessionCompleteMap(_sessionForSubject(sessions, active))) {
      return active;
    }

    for (final subject in studentEnrolledSubjects) {
      final sess = _sessionForSubject(sessions, subject);
      if (!_sessionHasEntryMap(sess) || !_sessionCompleteMap(sess)) {
        return subject;
      }
    }

    return studentEnrolledSubjects.isNotEmpty ? studentEnrolledSubjects.first : null;
  }

  /// Subjects must be finished in list order: no [entry] on a later subject until all prior have entry+exit.
  String? _sequentialPriorIncomplete(
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

  Map<String, dynamic> _flattenSubjectSessionsToDailyPayload(
    Map<String, dynamic> payload,
  ) {
    final sessions = _mapSubjectSessions(payload);
    if (sessions.isEmpty) return Map<String, dynamic>.from(payload);

    final out = Map<String, dynamic>.from(payload)..remove(_kSubjectSessionsKey);
    DateTime? earliestEntry;
    DateTime? latestExit;
    Map<String, dynamic>? entrySource;
    Map<String, dynamic>? exitSource;
    double totalHours = 0;
    bool hasHours = false;

    for (final subject in studentEnrolledSubjects.isEmpty
        ? sessions.keys
        : studentEnrolledSubjects) {
      final sess = _sessionForSubject(sessions, subject);
      if (sess.isEmpty) continue;

      final entryAt = _asDateTime(sess['entryTime']) ??
          _asDateTime(sess['timestamp']) ??
          _asDateTime(sess['entry_time']);
      if (entryAt != null &&
          (earliestEntry == null || entryAt.isBefore(earliestEntry))) {
        earliestEntry = entryAt;
        entrySource = sess;
      }

      final exitAt = _asDateTime(sess['exitTime']) ?? _asDateTime(sess['exit_time']);
      if (exitAt != null && (latestExit == null || exitAt.isAfter(latestExit))) {
        latestExit = exitAt;
        exitSource = sess;
      }

      final h = (sess['hours'] as num?)?.toDouble();
      if (h != null) {
        totalHours += h;
        hasHours = true;
      }
    }

    if (entrySource != null) {
      out['entryPhoto'] = _sessionEntryPhotoUrl(entrySource!);
      out['entryPhotoPath'] = _sessionEntryPhotoPath(entrySource!);
      out['entryPhotoFileId'] = entrySource!['entryPhotoFileId'];
      out['photoUrl'] = _sessionEntryPhotoUrl(entrySource!);
      out['storagePath'] = _sessionEntryPhotoPath(entrySource!);
      if (earliestEntry != null) {
        final iso = earliestEntry.toUtc().toIso8601String();
        out['entryTime'] = iso;
        out['timestamp'] = iso;
      }
    }

    if (exitSource != null) {
      out['exitPhoto'] = _sessionExitPhotoUrl(exitSource!);
      out['exitPhotoPath'] = _sessionExitPhotoPath(exitSource!);
      out['exitPhotoFileId'] = exitSource!['exitPhotoFileId'];
      if (latestExit != null) {
        out['exitTime'] = latestExit.toUtc().toIso8601String();
      }
    }

    if (hasHours) out['hours'] = double.parse(totalHours.toStringAsFixed(6));
    if (out['entryPhoto'] != null && out['exitPhoto'] != null) {
      out['status'] = 'present';
    } else if (out['entryPhoto'] != null) {
      out['status'] = 'pending';
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

  double _sumSubjectCreditedHours(Map<String, Map<String, dynamic>> sessions) {
    double t = 0;
    for (final s in sessions.values) {
      final h = s['hours'];
      if (h is num) t += h.toDouble();
    }
    return double.parse(t.toStringAsFixed(6));
  }

  bool canMark() {
    return !isLoading &&
        isLocationValid &&
        instituteId != null &&
        selectedRollNumber != null &&
        isAlreadyMarked != true;
  }

  bool _hasEntryPhoto() {
    final d = existingAttendanceData;
    if (d == null) return false;
    if (_legacyDayAttendance) {
      return d['entryPhoto'] != null || d['photoUrl'] != null;
    }
    if (studentEnrolledSubjects.isEmpty) return false;
    final subKey = _displaySubjectSliceForSessions();
    if (subKey == null) return false;
    final sessions = _mapSubjectSessions(d);
    final sess = sessions[subKey] ?? {};
    return _sessionHasEntryMap(sess);
  }

  bool _hasExitPhoto() {
    final d = existingAttendanceData;
    if (d == null) return false;
    if (_legacyDayAttendance) return d['exitPhoto'] != null;
    if (studentEnrolledSubjects.isEmpty) return false;
    final subKey = _displaySubjectSliceForSessions();
    if (subKey == null) return false;
    final sess = _mapSubjectSessions(d)[subKey] ?? {};
    return _sessionCompleteMap(sess);
  }

  /// Lecture face-scan must be completed (when the institute schedule requires it) before exit.
  bool _lectureScanBlocksExit() =>
      _legacyDayAttendance &&
      attendanceMode == 'lecture_scan' &&
      currentLectureIndex != null;

  void _syncEntrySessionTicker() {
    _entrySessionTicker?.cancel();
    _entrySessionTicker = null;
    if (!mounted) return;

    DateTime? entryUtc;
    final d = existingAttendanceData;
    if (_legacyDayAttendance) {
      entryUtc = _asDateTime(d?['entryTime']) ??
          _asDateTime(d?['timestamp']) ??
          _asDateTime(d?['entry_time']);
    } else if (studentEnrolledSubjects.isNotEmpty && d != null) {
      final subKey = _displaySubjectSliceForSessions();
      if (subKey != null) {
        final sess = _mapSubjectSessions(d)[subKey] ?? {};
        entryUtc = _asDateTime(sess['entryTime']) ??
            _asDateTime(sess['timestamp']) ??
            _asDateTime(sess['entry_time']);
      }
    }

    if (entryUtc == null || _hasExitPhoto()) return;
    _entrySessionTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  String _elapsedSinceEntryLabel() {
    final d = existingAttendanceData;

    DateTime? entryUtc;
    if (_legacyDayAttendance) {
      entryUtc = _asDateTime(d?['entryTime']) ??
          _asDateTime(d?['timestamp']) ??
          _asDateTime(d?['entry_time']);
    } else if (studentEnrolledSubjects.isNotEmpty && d != null) {
      final subKey = _displaySubjectSliceForSessions();
      if (subKey != null) {
        final sess = _mapSubjectSessions(d)[subKey] ?? {};
        entryUtc = _asDateTime(sess['entryTime']) ??
            _asDateTime(sess['timestamp']) ??
            _asDateTime(sess['entry_time']);
      }
    }

    if (entryUtc == null || _hasExitPhoto()) return '';
    final diff = DateTime.now().difference(entryUtc);
    if (diff.isNegative) return '0:00:00';
    final h = diff.inHours;
    final m = diff.inMinutes.remainder(60);
    final s = diff.inSeconds.remainder(60);
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
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
    // Daily policy: entry/exit is allowed any time during the day; midnight finalizes.
    return {'valid': true, 'message': null};
    
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
      ProfessionalMessaging.showWarning(
        context,
        title: 'Roll Number Required',
        message: 'Please select a roll number first.',
      );
      return;
    }
    
    // No subject requirement - attendance is based on entry/exit times only

    // Block absent marking when attendance is disabled for the day.
    if (instituteId != null) {
      final blockMessage =
          await InstituteStatusService().attendanceBlockMessage(instituteId!);
      if (!mounted) return;
      if (blockMessage != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(blockMessage),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 4),
          ));
        }
        return;
      }
    }

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
      if (!mounted) return;

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
      if (!mounted) return;

      final merged = Map<String, dynamic>.from(existingData ?? {});
      merged.addAll({
        'rollNumber': selectedRollNumber,
        'date': absentDate,
        'status': 'absent',
        'reason': reason,
        'timestamp': _encodeSv(),
        'markedBy': _db.auth.currentUser?.id ?? 'unknown',
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

      if (!mounted) return;
      _entrySessionTicker?.cancel();
      _entrySessionTicker = null;
      setState(() {
        isLoading = false;
        selectedRollNumber = null;
        isAlreadyMarked = null;
        existingMarkTime = null;
        existingAttendanceData = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Marked absent: $reason'),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (e) {
      if (!mounted) return;
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
      _entrySessionTicker?.cancel();
      _entrySessionTicker = null;
      setState(() {
        isAlreadyMarked = null;
        existingMarkTime = null;
        existingAttendanceData = null;
        activeAttendanceSubject = null;
        _legacyDayAttendance = false;
      });
      return;
    }

    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      var data = await _getTeacherAttendanceDoc(selectedRollNumber!, today);
      if (!mounted) return;

      if (data != null && !_isLegacyAttendanceDoc(data)) {
        data = _flattenSubjectSessionsToDailyPayload(data);
        await _upsertTeacherAttendanceDoc(
          roll: selectedRollNumber!,
          date: today,
          payload: data,
          status: data['status']?.toString(),
        );
      }

      if (data != null) {
        final currentStatus = data['status']?.toString();
        if (currentStatus == 'absent') {
          setState(() {
            _legacyDayAttendance = false;
            activeAttendanceSubject = null;
            isAlreadyMarked = true;
            existingMarkTime = null;
            existingAttendanceData = data;
            attendanceMode = null;
            isEntryPhoto = true;
            currentLectureIndex = null;
          });
          return;
        }

        if (_isLegacyAttendanceDoc(data)) {
          final ts = _asDateTime(data['entryTime']) ?? _asDateTime(data['timestamp']);
          String? timeStr;
          if (ts != null) timeStr = DateFormat('HH:mm').format(ts);

          final hasEntry = data['entryPhoto'] != null || data['photoUrl'] != null;
          final hasExit = data['exitPhoto'] != null;

          final lectures = data['lectures'] as Map<String, dynamic>? ?? {};
          final timing = selectedTiming ?? '';
          final lectureTimes = _parseLectureTiming(timing);

          int? nextLectureIndex;
          if (hasEntry && !hasExit && lectureTimes.isNotEmpty) {
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
                if (!lectures.containsKey(lectureKey) || lectures[lectureKey]['faceScanPhoto'] == null) {
                  nextLectureIndex = i;
                  break;
                }
              }
            }
          }

          setState(() {
            _legacyDayAttendance = true;
            activeAttendanceSubject = null;
            isAlreadyMarked = hasEntry && hasExit;
            existingMarkTime = timeStr;
            existingAttendanceData = data;
            currentLectureIndex = nextLectureIndex;

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
              attendanceMode = 'entry';
              isEntryPhoto = true;
            }
          });
          return;
        }
      } else {
        setState(() {
          _legacyDayAttendance = true;
          activeAttendanceSubject = null;
          isAlreadyMarked = false;
          existingMarkTime = null;
          existingAttendanceData = null;
          attendanceMode = 'entry';
          isEntryPhoto = true;
          currentLectureIndex = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isAlreadyMarked = null;
          existingMarkTime = null;
          existingAttendanceData = null;
          attendanceMode = null;
          currentLectureIndex = null;
          activeAttendanceSubject = null;
          _legacyDayAttendance = false;
        });
      }
    } finally {
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _syncEntrySessionTicker();
        });
      }
    }
  }

  /* ---------------- MARK ATTENDANCE ---------------- */

  /// [photoIntent]: `'entry'` | `'exit'` for explicit buttons; `null` for lecture scan / legacy auto mode.
  Future<void> _markAttendance({String? photoIntent}) async {
    setState(() => isLoading = true);

    // Attendance is available every day; do not block on institute open/holiday/close status.

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
      if (!mounted) return;

      if (deviceChanged) {
        if (kDebugMode) debugPrint('⚠️ Device change detected - logging for review');
      }

      // 🛡️ SECURITY CHECK 3: Network verification
      final networkInfo = await NetworkVerificationService.getNetworkInfoForLogging();
      if (!mounted) return;

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

      // 🛡️ SECURITY CHECK 5: STRICT GPS RADIUS CHECK
      if (!kIsWeb) {
        final withinRadius = await _checkGPSRadius();
        if (!mounted) return;
        if (!withinRadius) {
          setState(() => isLoading = false);
          return;
        }
      }

      // 🛡️ SECURITY CHECK 6: STUDENT VALIDATION - Verify student exists in database
      if (selectedRollNumber == null || selectedRollNumber!.isEmpty) {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ No student selected. Please select a student first.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4),
          ),
        );
        return;
      }

      final studentExists = await _validateStudentExists(selectedRollNumber!);
      if (!mounted) return;
      if (studentExists != true) {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Student "$selectedRollNumber" not found in database.\n'
                'Cannot mark attendance for unknown students.\n'
                'Please verify the roll number and try again.'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
        return;
      }

      // 🛡️ SECURITY CHECK 6A: Verify student has profile photo (completed registration)
      final hasProfilePhoto = await _checkStudentProfilePhoto(selectedRollNumber!);
      if (!mounted) return;
      if (hasProfilePhoto != true) {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Student "$selectedRollNumber" registration incomplete.\n'
                'Student must complete registration with profile photo first.\n'
                'Contact the student to finish registration.'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 6),
          ),
        );
        return;
      }

      // Use simple ImagePicker for testing (face recognition disabled for now)
      XFile? photo;
      // Suppress PIN lock while camera is open
      SessionMonitor.beginSuppressResumeLock();
      try {
        photo = await picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 50, // Lower quality for smaller file size (was 85)
          maxWidth: 800, // Limit width to reduce size
          maxHeight: 800, // Limit height to reduce size
          preferredCameraDevice: CameraDevice.front,
        ).timeout(
          const Duration(seconds: 60),
          onTimeout: () {
            if (kDebugMode) debugPrint('⏱️ Camera timeout - user took too long');
            return null;
          },
        );
      } catch (e) {
        if (kDebugMode) {
          debugPrint('❌ Camera error (interrupted or permission denied): $e');
        }
        if (!mounted) return;
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Camera error: ${e.toString()}\nPlease try again or check camera permissions.'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
        return;
      }

      if (!mounted) return;
      if (photo == null) {
        setState(() => isLoading = false);
        return;
      }

      // Clock at capture — must match EXIF / file time (not [markingTime] from start of flow).
      final timeAtPhotoCapture = DateTime.now();

      // Read and compress photo
      Uint8List bytes = await photo.readAsBytes();
      if (!mounted) return;

      // Compress image if still too large (target: under 50KB)
      if (bytes.length > 50 * 1024) {
        bytes = await _compressImage(bytes, maxSizeKB: 50);
        if (!mounted) return;
        if (kDebugMode) {
          debugPrint('📸 Photo compressed: ${(bytes.length / 1024).toStringAsFixed(2)} KB');
        }
      }
      
      // 🛡️ SECURITY CHECK 5: Photo verification (EXIF, timestamp, screenshot detection)
      final photoVerification = await PhotoVerificationService.verifyPhoto(
        photoPath: photo.path,
        markingTime: timeAtPhotoCapture,
        expectedLocation: null, // Can add location check if needed
      );

      if (!mounted) return;
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

      // 🛡️ SECURITY CHECK 7: Same face verification as student registration
      // Step 1: Detect photo-of-photo (printed photo / screen)
      if (!kIsWeb) {
        final isPhotoOfPhoto = await PhotoVerificationService.detectPhotoOfPhoto(photo.path);
        if (!mounted) return;
        if (isPhotoOfPhoto) {
          setState(() => isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ This looks like a photo of a photo or screen.\n'
                  'Point the camera at the student in person only.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 5),
            ),
          );
          return;
        }
      }

      // Step 2: Detect liveness (live person vs recording/mask)
      if (!kIsWeb) {
        final liveness = await LivenessDetectionService.detectLivenessFromPhoto(
          photoPath: photo.path,
        );
        if (!mounted) return;
        if (!LivenessDetectionService.passesLivePersonPreCheck(liveness)) {
          setState(() => isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ Liveness check failed.\n'
                  'Student must face camera directly with eyes open — no masks, recordings, or fake faces.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 5),
            ),
          );
          return;
        }
      }

      // Step 3: Extract face features and compare with student profile
      final photoMatchResult = await _compareStudentPhoto(selectedRollNumber!, photo.path);
      if (!mounted) return;
      if (!photoMatchResult['isMatch']) {
        setState(() => isLoading = false);
        final reason = photoMatchResult['reason'] ?? 'Photo does not match student profile';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Student verification failed!\n'
                '$reason\n\n'
                'Please verify you are marking attendance for the correct student.'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 6),
          ),
        );
        return;
      }

      if (photoMatchResult['confidence'] != null) {
        if (kDebugMode) {
          final confidence = (photoMatchResult['confidence'] as double) * 100;
          debugPrint('✅ Face match confidence: ${confidence.toStringAsFixed(1)}%');
        }
      }

      // 🛡️ SECURITY CHECK 8: Blur detection
      final isBlurry = await PhotoVerificationService.detectBlur(bytes);
      if (!mounted) return;
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

      // 🛡️ SECURITY CHECK 9: Photo-of-photo detection
      final isPhotoOfPhoto = await PhotoVerificationService.detectPhotoOfPhoto(photo.path);
      if (!mounted) return;
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
      if (!mounted) return;
      if (!LivenessDetectionService.passesLivePersonPreCheck(livenessResult)) {
        setState(() => isLoading = false);
        if (kDebugMode) {
          debugPrint(
            '⚠️ Live-person check failed: ${livenessResult.reason}',
          );
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Live face check failed. Do not use a printed photo or another phone screen. '
              'The student must face the camera directly, eyes open, good lighting — then try again.',
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 6),
          ),
        );
        return;
      }

      // 🛡️ SECURITY CHECK 8: Multiple face detection (group photo)
      final faceDetection = await PhotoVerificationService.detectMultipleFaces(photo.path);
      if (!mounted) return;
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
                  'Please add subjects for this student in Student Management → Edit.',
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

      setState(() => isLoading = true); // Show loading during verification
      ScaffoldMessenger.of(context).clearSnackBars();
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

      // 🔒 STRICT CHECK: Verify student hasn't already marked attendance today
      if (selectedRollNumber != null && instituteId != null) {
        final attendanceError = await StudentValidationService.validateAttendanceMarking(
          studentId: selectedRollNumber!,
          instituteCode: instituteId ?? '',
          instituteId: instituteId ?? '',
          attendanceDate: DateTime.now(),
          skipDuplicateTodayCheck: true,
        );

        if (attendanceError != null) {
          setState(() => isLoading = false);
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(attendanceError),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 6),
            ),
          );
          return;
        }
      }

      // Location was already enforced at mark start via [_checkGPSRadius] (locked GPS point).
      // Avoid a second "Verifying location..." pass against institutes.latitude/longitude — it
      // confused users and could stay visible if the lookup or GPS call stalled.

      final faceResult = await FaceRecognitionService.verifyStudent(
        photo.path,
        instituteId!,
        selectedRollNumber!,
      );
      if (!mounted) return;

      if (!faceResult.isMatch) {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).clearSnackBars();
        final isWrongStudent = faceResult.message.contains('Wrong student:');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isWrongStudent ? Icons.security : Icons.error_outline,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isWrongStudent ? 'Wrong student — blocked' : 'Face check failed',
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
                  faceResult.message,
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 12),
          ),
        );
        return;
      }

      if (kDebugMode) {
        debugPrint('✅ On-device face verification passed for Roll $selectedRollNumber');
      }

      ScaffoldMessenger.of(context).clearSnackBars();

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

      var existingPayload = await FirestoreRetryService.executeWithRetry(
        operation: () async => await _getTeacherAttendanceDoc(selectedRollNumber!, today),
        operationName: 'Check existing attendance',
      );
      if (!mounted) return;

      if (instituteId != null && studentEnrolledSubjects.isNotEmpty) {
        existingPayload = await StaleAttendanceReconciliationService.ensureReconciled(
          db: _db,
          instituteId: instituteId!,
          roll: selectedRollNumber!,
          date: today,
          enrolledSubjects: studentEnrolledSubjects,
          existingPayload: existingPayload,
        );
      }

      if (!mounted) return;

      if (existingPayload != null && !_isLegacyAttendanceDoc(existingPayload)) {
        existingPayload = _flattenSubjectSessionsToDailyPayload(existingPayload);
        await FirestoreRetryService.executeWithRetry(
          operation: () async {
            await _upsertTeacherAttendanceDoc(
              roll: selectedRollNumber!,
              date: today,
              payload: existingPayload!,
              status: existingPayload!['status']?.toString(),
            );
          },
          operationName: 'Migrate daily attendance payload',
        );
      }

      final photoCapturedAt = timeAtPhotoCapture.toUtc();
      final currentTime = photoCapturedAt.toLocal();
      final serverTs = photoCapturedAt.toIso8601String();

      final ex = existingPayload;
      final existingStatus = ex?['status']?.toString();
      if (existingStatus == 'absent') {
        setState(() => isLoading = false);
        final reason = ex?['absentReason']?.toString() ??
            ex?['reason']?.toString() ??
            'Already absent for today';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠️ Student already absent for today.\n$reason'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 6),
          ),
        );
        return;
      }
      const useSubjects = false;
      activeAttendanceSubject = null;

      late final bool hasEntry;
      late final bool hasExit;
      if (useSubjects) {
        final sub = activeAttendanceSubject!;
        final subjectEx = _sessionForSubject(_mapSubjectSessions(ex), sub);
        hasEntry = _sessionHasEntryMap(subjectEx);
        hasExit = _sessionCompleteMap(subjectEx);
      } else {
        hasEntry = ex != null && (ex['entryPhoto'] != null || ex['photoUrl'] != null);
        hasExit = ex != null && (ex['exitPhoto'] != null || ex['exitTime'] != null);
      }

      // Determine mode: entry, exit, or lecture scan
      String mode = attendanceMode ?? 'entry';

      if (photoIntent == 'entry') {
        if (useSubjects) {
          if (_allSubjectsCompleteInPayload(ex, studentEnrolledSubjects)) {
            setState(() => isLoading = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'All enrolled subjects are complete for today. After midnight (new calendar day) you can mark again.',
                ),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 6),
              ),
            );
            return;
          }
          if (hasEntry && hasExit) {
            setState(() => isLoading = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '⚠️ "${activeAttendanceSubject!}" is already complete for today. Choose another subject or return after midnight.',
                ),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 6),
              ),
            );
            return;
          }
        } else if (hasEntry && hasExit) {
          setState(() => isLoading = false);
          final doc = ex;
          final entryTime = _asDateTime(doc!['entryTime']) ?? _asDateTime(doc['timestamp']);
          final exitTime = _asDateTime(doc['exitTime']);
          var timeInfo = '';
          if (entryTime != null && exitTime != null) {
            timeInfo =
                ' (Entry: ${DateFormat('HH:mm').format(entryTime)}, Exit: ${DateFormat('HH:mm').format(exitTime)})';
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '⚠️ Today is already complete for this student$timeInfo.\n'
                'A new entry starts after midnight (next calendar day).',
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 6),
            ),
          );
          return;
        }
        mode = 'entry';
      } else if (photoIntent == 'exit') {
        if (!hasEntry) {
          setState(() => isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ Take entry photo first for this subject, then exit photo.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 4),
            ),
          );
          return;
        }
        // Strict window: Exit must be within allowed hours from Entry.
        if (!useSubjects && ex != null) {
          final entryTime = _asDateTime(ex['entryTime']) ?? _asDateTime(ex['timestamp']);
          if (entryTime != null) {
            final allowedH = attendanceAllowedWindowHoursForSubjectCount(studentEnrolledSubjects.length);
            final deadline = entryTime.toUtc().add(Duration(minutes: (allowedH * 60).round()));
            if (DateTime.now().toUtc().isAfter(deadline)) {
              setState(() => isLoading = false);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    '⛔ Exit time window passed (${allowedH.toStringAsFixed(0)}h from entry). Attendance will be auto-credited without exit photo.',
                  ),
                  backgroundColor: Colors.orange,
                  duration: const Duration(seconds: 6),
                ),
              );
              return;
            }
          }
        }
        if (hasExit) {
          setState(() => isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                useSubjects
                    ? '⚠️ Exit is already recorded for "${activeAttendanceSubject!}" today. After midnight, this subject unlocks again.'
                    : '⚠️ Exit is already recorded for today. After midnight, a new day begins.',
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 5),
            ),
          );
          return;
        }
        if (_lectureScanBlocksExit()) {
          setState(() => isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '❌ Complete lecture ${currentLectureIndex! + 1} face scan first, then use exit photo.',
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 5),
            ),
          );
          return;
        }
        mode = 'exit';
      } else if (ex != null) {
        if (useSubjects) {
          if (_allSubjectsCompleteInPayload(ex, studentEnrolledSubjects)) {
            setState(() => isLoading = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('All subjects complete for today.'),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 5),
              ),
            );
            return;
          }
          if (!hasEntry) {
            mode = 'entry';
          } else if (!hasExit) {
            mode = 'exit';
          } else {
            mode = 'entry';
          }
        } else {
          final existingData = ex;
          if (hasEntry && hasExit) {
            setState(() => isLoading = false);
            final entryTime =
                _asDateTime(existingData['entryTime']) ?? _asDateTime(existingData['timestamp']);
            final exitTime = _asDateTime(existingData['exitTime']);
            var timeInfo = '';
            if (entryTime != null && exitTime != null) {
              final entry = DateFormat('HH:mm').format(entryTime);
              final exit = DateFormat('HH:mm').format(exitTime);
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
            if (currentLectureIndex != null && attendanceMode == 'lecture_scan') {
              mode = 'lecture_scan';
            } else {
              mode = 'exit';
            }
          }
        }
      }

      if (mode == 'exit' && instituteId != null && selectedRollNumber != null) {
        DateTime? entryUtc;
        if (useSubjects && activeAttendanceSubject != null) {
          final subjectEx = _sessionForSubject(_mapSubjectSessions(ex), activeAttendanceSubject!);
          entryUtc = _asDateTime(subjectEx['entryTime']) ?? _asDateTime(subjectEx['timestamp']);
        } else if (ex != null) {
          entryUtc = _asDateTime(ex['entryTime']) ?? _asDateTime(ex['timestamp']);
        }
        if (entryUtc != null &&
            isPastAttendanceExitDeadline(
              entryUtc.toUtc(),
              DateTime.now().toUtc(),
              studentEnrolledSubjects.length,
            )) {
          Map<String, dynamic>? repaired = ex;
          if (studentEnrolledSubjects.isNotEmpty) {
            repaired = await StaleAttendanceReconciliationService.ensureReconciled(
              db: _db,
              instituteId: instituteId!,
              roll: selectedRollNumber!,
              date: today,
              enrolledSubjects: studentEnrolledSubjects,
              existingPayload: ex,
            );
          }
          if (!mounted) return;

          var stillNeedsManualExit = false;
          if (useSubjects && activeAttendanceSubject != null) {
            final subjectEx =
                _sessionForSubject(_mapSubjectSessions(repaired), activeAttendanceSubject!);
            stillNeedsManualExit =
                _sessionHasEntryMap(subjectEx) && !_sessionCompleteMap(subjectEx);
          } else if (repaired != null) {
            final hasEn = repaired['entryPhoto'] != null || repaired['photoUrl'] != null;
            final hasEx = repaired['exitPhoto'] != null || repaired['exitTime'] != null;
            stillNeedsManualExit = hasEn && !hasEx;
          }

          if (!stillNeedsManualExit) {
            setState(() {
              isLoading = false;
              if (repaired != null) {
                existingAttendanceData = Map<String, dynamic>.from(repaired);
              }
            });
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _syncEntrySessionTicker();
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  useSubjects && activeAttendanceSubject != null
                      ? 'Session auto-closed after midnight: "${activeAttendanceSubject!}". No exit photo — 1 h credit.'
                      : 'Session auto-closed after midnight. No exit photo — 1 h credit.',
                ),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 6),
              ),
            );
          } else {
            setState(() => isLoading = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(
                  'Exit is no longer available because the day has already rolled over.',
                ),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 6),
              ),
            );
          }
          return;
        }
      }

      bool isMarkingEntry = (mode == 'entry');
      bool isMarkingExit = (mode == 'exit');
      bool isLectureScan = (mode == 'lecture_scan');

      if (useSubjects &&
          isMarkingEntry &&
          activeAttendanceSubject != null) {
        final sessionsMap = _mapSubjectSessions(ex);
        final subj = activeAttendanceSubject!;
        final subjectEx = _sessionForSubject(sessionsMap, subj);
        if (!_sessionHasEntryMap(subjectEx)) {
          final seq = _sequentialPriorIncomplete(
            studentEnrolledSubjects,
            sessionsMap,
            subj,
          );
          if (seq != null) {
            setState(() => isLoading = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Finish entry and exit for "$seq" first. '
                  'The next subject unlocks only after the previous one is fully done.',
                ),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 6),
              ),
            );
            return;
          }
        }
      }

      // Calendar year segment in B2 object path (unchanged for existing keys)
      final folderYear = _selectedStudentYear ?? DateTime.now().year.toString();
      final timing = selectedTiming ?? '';
      final lectureTimes = _parseLectureTiming(timing);
      
      // Hours are calculated from actual entry/exit times, not scheduled slots.

      // Upload photo - different path for entry/exit/lecture_scan
      String photoType;
      if (isMarkingEntry) {
        photoType = 'entry';
      } else if (isMarkingExit) {
        photoType = 'exit';
      } else {
        photoType = 'lecture_scan';
      }
      
      // Raw subject for validation; [B2BStorageService.generatePhotoPath] sanitizes for the object key.
      final uploadSubject = useSubjects && activeAttendanceSubject != null
          ? activeAttendanceSubject!.trim()
          : 'all';

      final uploadResult = await StorageService.uploadAttendancePhoto(
        instituteId: instituteId!,
        folderYear: folderYear,
        rollNumber: selectedRollNumber!,
        subject: uploadSubject,
        date: today,
        photoBytes: bytes,
        photoType: photoType,
      );

      if (!mounted) return;
      final url = uploadResult['url']!;
      final storagePath = uploadResult['path']!;
      final fileId = uploadResult['fileId'];
      final fileSizeBytes = bytes.length;

      debugPrint('📁 Storage Path: $storagePath');
      debugPrint('🔗 Photo URL: $url');
      debugPrint('📏 Photo Size: ${(fileSizeBytes / 1024).toStringAsFixed(2)} KB');
      debugPrint('📸 Photo Type: $photoType');

      final existingData = existingPayload != null
          ? Map<String, dynamic>.from(existingPayload!)
          : <String, dynamic>{};
      
      // Save attendance: either per-subject sessions (same doc / calendar day) or legacy top-level row.
      final attendanceData = <String, dynamic>{
        'rollNumber': selectedRollNumber,
        'date': today,
        'markedBy': _db.auth.currentUser?.id ?? 'unknown',
        'lectureTiming': timing,
        'instituteId': instituteId,
        'updatedAt': serverTs,
        'subjects': studentEnrolledSubjects,
      };

      if (useSubjects) {
        final sub = activeAttendanceSubject!;
        final sessions = _mapSubjectSessions(existingData);
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

        final mergedStub = Map<String, dynamic>.from(existingData);
        mergedStub[_kSubjectSessionsKey] = sessions;
        final allDone = _allSubjectsCompleteInPayload(mergedStub, studentEnrolledSubjects);

        attendanceData[_kSubjectSessionsKey] = sessions;
        attendanceData['totalCreditedHoursDay'] = _sumSubjectCreditedHours(sessions);
        attendanceData['status'] = allDone ? 'present' : 'pending';
      } else if (isMarkingEntry) {
        // Marking entry - start of day
        // DO NOT mark as present until exit photo is taken
        attendanceData['entryPhoto'] = url;
        attendanceData['entryTime'] = serverTs;
        attendanceData['entryPhotoPath'] = storagePath;
        if (fileId != null && fileId.isNotEmpty) {
          attendanceData['entryPhotoFileId'] = fileId;
        }
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
        attendanceData['entryPhotoFileId'] = existingData['entryPhotoFileId'];
        attendanceData['photoUrl'] = existingData['photoUrl'] ?? existingData['entryPhoto'];
        attendanceData['timestamp'] = existingData['timestamp'] ?? existingData['entryTime'];

        // Get existing lectures or create new
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
        // Marking exit - end of day
        // Preserve entry data
        attendanceData['entryPhoto'] = existingData['entryPhoto'] ?? existingData['photoUrl'];
        attendanceData['entryTime'] = existingData['entryTime'] ?? existingData['timestamp'];
        attendanceData['entryPhotoPath'] = existingData['entryPhotoPath'] ?? existingData['storagePath'];
        attendanceData['entryPhotoFileId'] = existingData['entryPhotoFileId'];
        attendanceData['photoUrl'] = existingData['photoUrl'] ?? existingData['entryPhoto'];
        attendanceData['timestamp'] = existingData['timestamp'] ?? existingData['entryTime'];

        // Mark exit
        attendanceData['exitPhoto'] = url;
        attendanceData['exitTime'] = serverTs;
        attendanceData['exitPhotoPath'] = storagePath;
        if (fileId != null && fileId.isNotEmpty) {
          attendanceData['exitPhotoFileId'] = fileId;
        }

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

        // Calculate hours from entry and exit times.
        // Strict rule: credit actual duration if within allowed window (capped to the window).
        if (entryTime != null) {
          final entryDateTime = entryTime;
          final exitDateTime = currentTime;
          final duration = exitDateTime.difference(entryDateTime);
          final rawH = duration.inSeconds / 3600.0;
          attendanceData['hoursRaw'] = double.parse(rawH.toStringAsFixed(6));
          final maxH = attendanceAllowedWindowHoursForSubjectCount(studentEnrolledSubjects.length);
          final credited = rawH > maxH ? maxH : rawH;
          attendanceData['hours'] = double.parse(credited.toStringAsFixed(6));
          attendanceData['attendanceReason'] = attendanceCompletedWithinWindowNote(
            creditedHours: double.parse(credited.toStringAsFixed(6)),
            allowedHours: maxH,
          );
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

      // New policy: one Entry + one Exit per calendar day (not per subject).
      // We still display allotted subjects, and credit hours based on their count.
      final syncSubject = useSubjects ? activeAttendanceSubject : 'all';

      if (isMarkingEntry) {
        await _syncAttendanceInOut(
          roll: selectedRollNumber!,
          date: today,
          type: 'entry',
          photoUrl: url,
          photoPath: storagePath,
          photoFileId: fileId,
          recordedAtUtc: serverTs,
          subject: syncSubject,
          sessionEntryUtc: serverTs,
          status: 'pending',
        );
        if (instituteId != null) {
          await InstituteNotificationService.scheduleAttendanceExitReminder(
            instituteId: instituteId!,
            rollKey: selectedRollNumber!,
            dateKey: today,
            subjectTag:
                (useSubjects && activeAttendanceSubject != null) ? activeAttendanceSubject! : 'all',
            entryAtUtc: DateTime.parse(serverTs.toString()).toUtc(),
          );
        }
      } else if (isMarkingExit) {
        if (useSubjects && activeAttendanceSubject != null) {
          final sessions = _mapSubjectSessions(mergedPayload);
          final sess = _sessionForSubject(sessions, activeAttendanceSubject!);
          final entryUtc = sess['entryTime']?.toString() ?? sess['timestamp']?.toString();
          final hrs = (sess['hours'] as num?)?.toDouble();
          await _syncAttendanceInOut(
            roll: selectedRollNumber!,
            date: today,
            type: 'exit',
            photoUrl: url,
            photoPath: storagePath,
            photoFileId: fileId,
            recordedAtUtc: serverTs,
            subject: activeAttendanceSubject,
            sessionEntryUtc: entryUtc,
            sessionExitUtc: serverTs,
            hours: hrs,
            status: 'present',
          );
        } else {
          final entryUtc =
              mergedPayload['entryTime']?.toString() ?? mergedPayload['timestamp']?.toString();
          final hrs = (mergedPayload['hours'] as num?)?.toDouble();
          await _syncAttendanceInOut(
            roll: selectedRollNumber!,
            date: today,
            type: 'exit',
            photoUrl: url,
            photoPath: storagePath,
            photoFileId: fileId,
            recordedAtUtc: serverTs,
            subject: syncSubject,
            sessionEntryUtc: entryUtc,
            sessionExitUtc: serverTs,
            hours: hrs,
            status: 'present',
          );
        }
        if (instituteId != null) {
          await InstituteNotificationService.cancelAttendanceExitReminder(
            instituteId: instituteId!,
            rollKey: selectedRollNumber!,
            dateKey: today,
            subjectTag:
                (useSubjects && activeAttendanceSubject != null) ? activeAttendanceSubject! : 'all',
          );
        }
      }

      if (!mounted) return;
      final rollNumberForMessage = selectedRollNumber; // Store before clearing

      String successMessage;
      if (isMarkingEntry && useSubjects && activeAttendanceSubject != null) {
        successMessage = '✅ Entry for "${activeAttendanceSubject!}" recorded ($rollNumberForMessage)\n'
            '⚠️ Take exit photo for this subject to complete the session.\n'
            'You can mark other subjects after this one is fully complete.';
      } else if (isMarkingEntry) {
        successMessage = '✅ Entry photo recorded for $rollNumberForMessage\n'
            '⚠️ Attendance will be marked as present only after exit photo is taken!\n'
            '⚠️ Remember to take exit photo before leaving!';
      } else if (isMarkingExit) {
        if (useSubjects && activeAttendanceSubject != null) {
          final sessions = _mapSubjectSessions(mergedPayload);
          final sess = _sessionForSubject(sessions, activeAttendanceSubject!);
          final credited = (sess['hours'] as num?)?.toDouble() ?? 0.0;
          final sub = activeAttendanceSubject!;
          final isAutoClosed = sess['autoClosedMissingExit'] == true;
          final autoClosedNote = sess['autoClosedNote'] as String?;

          if (isAutoClosed && autoClosedNote != null) {
            successMessage = '✅ $sub — Auto-closed for $rollNumberForMessage\n'
                '⚠️ ${autoClosedNote}\n'
                '⏰ Credit: 1.0 h (no exit photo)';
          } else {
            successMessage = '✅ $sub — exit recorded for $rollNumberForMessage\n'
                '⏰ Credit: ${credited.toStringAsFixed(2)} h';
          }
        } else {
          final credited = attendanceData['hours'] as double? ?? 0.0;
          final isAutoClosed = attendanceData['autoClosedMissingExit'] == true;
          final autoClosedNote = attendanceData['autoClosedNote'] as String?;

          if (isAutoClosed && autoClosedNote != null) {
            successMessage = '✅ Auto-closed for $rollNumberForMessage\n'
                '⚠️ ${autoClosedNote}\n'
                '⏰ Credit: 1.0 h (no exit photo)';
          } else {
            successMessage = '✅ Exit attendance marked for $rollNumberForMessage\n'
                '⏰ Credit: ${credited.toStringAsFixed(2)} h';
          }
        }
      } else if (isLectureScan && currentLectureIndex != null) {
        successMessage = '✅ Lecture ${currentLectureIndex! + 1} face scan marked for $rollNumberForMessage';
      } else {
        successMessage = '✅ Attendance marked for $rollNumberForMessage';
      }

      ScaffoldMessenger.of(context).clearSnackBars();
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

      // After legacy exit: clear roll. Per-subject: keep roll so more subjects can be marked today.
      if (isMarkingExit) {
        _entrySessionTicker?.cancel();
        _entrySessionTicker = null;
        if (useSubjects) {
          await _checkAttendanceStatus();
          if (mounted) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _syncEntrySessionTicker();
            });
          }
        } else {
          setState(() {
            selectedRollNumber = null;
            isAlreadyMarked = null;
            existingMarkTime = null;
            existingAttendanceData = null;
            isEntryPhoto = true;
            attendanceMode = 'entry';
            currentLectureIndex = null;
            activeAttendanceSubject = null;
            _legacyDayAttendance = false;
          });
        }
      } else {
        await _checkAttendanceStatus();
        if (mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _syncEntrySessionTicker();
          });
        }
      }

      // Refresh student list to show updated status
      if (selectedRollNumber != null) {
        _loadAttendanceRoster();
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
        errorMessage = 'Photos could not be saved. Please try again. If this continues, contact your institute administrator.';
      } else if (errorString.contains('B2B upload failed')) {
        errorMessage = 'Failed to upload photo. Please check your internet connection and try again.';
      } else if (errorString.contains('timeout') && errorString.contains('30 seconds')) {
        errorMessage =
            'Verification took too long. Please try again. The first attempt after opening the app may take a little longer.';
      } else if (errorString.contains('500') || errorString.contains('Internal Server Error')) {
        errorMessage =
            'Attendance could not be saved right now. Check the photo is clear, the student is registered with a profile photo, then try again.';
      } else if (errorString.contains('503') || errorString.contains('Service Unavailable')) {
        errorMessage =
            'Service is busy. Please wait a few seconds and try again.';
      } else if (errorString.contains('network') || errorString.contains('connection') || errorString.contains('timeout')) {
        errorMessage = 'Network connection issue. Please check your internet connection and try again.';
      } else if (errorString.contains('face') || errorString.contains('recognition') || errorString.contains('match')) {
        errorMessage = 'Face verification failed. Please ensure good lighting, face is clearly visible, and try again.';
      } else if (errorString.contains('location') || errorString.contains('GPS') || errorString.contains('geofence')) {
        errorMessage = 'Location verification failed. Please enable location services and ensure you are within 15 meters of the institute.';
      } else if (errorString.contains('time') || errorString.contains('window') || errorString.contains('entry') || errorString.contains('exit')) {
        errorMessage = 'Attendance can only be marked during the allowed time window. Please check institute hours and try again.';
      } else if (errorString.contains('blur') || errorString.contains('quality')) {
        errorMessage = 'Photo quality is too low. Please ensure good lighting, keep the camera steady, and take a clear photo.';
      } else if (errorString.contains('photo') && errorString.contains('photo')) {
        errorMessage = 'Invalid photo detected. Please take a live photo of the student, not a photo of a photo.';
      } else if (errorString.contains('dotenv') || errorString.contains('not initialized')) {
        errorMessage = 'Something is misconfigured on this device. Please contact your institute administrator.';
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
      SessionMonitor.endSuppressResumeLock();
      if (mounted) setState(() => isLoading = false);
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
                  child: ResponsiveScrollBody(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildHeader(),
                        const SizedBox(height: 24),

                        // Queue Mode Instructions
                        Visibility(
                          visible: selectedRollNumber != null &&
                              (selectedSubject != null ||
                                  studentEnrolledSubjects.isNotEmpty),
                          maintainSize: true,
                          maintainAnimation: true,
                          maintainState: true,
                          child: _buildQueueModeBanner(),
                        ),
                        Visibility(
                          visible: selectedRollNumber != null,
                          maintainSize: true,
                          maintainAnimation: true,
                          maintainState: true,
                          child: const SizedBox(height: 16),
                        ),

            // Step 1: Select Roll Number with Search
            _buildStepCard(
              stepNumber: 1,
              title: 'Select Roll Number',
              icon: Icons.badge_outlined,
              iconColor: AppTheme.accentYellow,
                child: isLoadingRoster
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
                                    suffixIcon: Visibility(
                                      visible: _searchController.text.isNotEmpty,
                                      maintainSize: true,
                                      maintainAnimation: true,
                                      maintainState: true,
                                      child: IconButton(
                                        icon: Icon(
                                          Icons.clear,
                                          color: isDark ? Colors.white : AppTheme.primaryBlue,
                                          size: 22,
                                        ),
                                        onPressed: () {
                                          _searchController.clear();
                                        },
                                      ),
                                    ),
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
                              selectedSubject = null;
                              selectedTiming = null;
                              _selectedStudentYear = null;
                              studentEnrolledSubjects = [];
                              activeAttendanceSubject = null;
                              _legacyDayAttendance = false;
                            });
                            await _fetchStudentDataForRoll(roll);
                            _checkAttendanceStatus();
                          }
                        },
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 16),
              
              // Subject / schedule (auto-populated)
              if (selectedRollNumber != null &&
                  (studentEnrolledSubjects.isNotEmpty ||
                      (selectedTiming != null && selectedTiming!.isNotEmpty))) ...[
                _buildStepCard(
                  stepNumber: 2,
                  title: 'Allotted subjects → then photos (strict)',
                  icon: Icons.book_outlined,
                  iconColor: AppTheme.primaryBlue,
                  child: Builder(
                    builder: (context) {
                      final isDark = Theme.of(context).brightness == Brightness.dark;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (selectedTiming != null && selectedTiming!.isNotEmpty) ...[
                            Row(
                              children: [
                                Icon(Icons.access_time_outlined, size: 20, color: isDark ? Colors.white70 : AppTheme.textGray),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Schedule: $selectedTiming',
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
                          ] else
                            const SizedBox(height: 0),

                          // Subjects allotted — shown directly; attendance uses the next valid subject automatically.
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
                                        'Allotted subjects',
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
                                      return Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 9,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isDark
                                              ? Colors.white.withValues(alpha: 0.08)
                                              : Colors.white,
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: isDark
                                                ? Colors.white.withValues(alpha: 0.18)
                                                : AppTheme.primaryBlue.withValues(alpha: 0.18),
                                          ),
                                        ),
                                        child: Text(
                                          subject,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: isDark ? Colors.white : AppTheme.textDark,
                                          ),
                                        ),
                                      );
                                    }).toList(),
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
              
              if (selectedRollNumber != null &&
                  studentEnrolledSubjects.length > 1 &&
                  !_legacyDayAttendance &&
                  isAlreadyMarked != true) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.orange.shade800, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Attendance is daily: take 1 Entry photo + 1 Exit photo. Credited hours are based on allotted subject count.',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.orange.shade900,
                          ),
                        ),
                      ),
                    ],
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

              // Mark absent (full width), then explicit Entry photo / Exit photo (+ lecture scan when required).
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 56.h,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(16.r),
                        border: Border.all(color: Colors.orange, width: 2.w),
                      ),
                      child: ElevatedButton.icon(
                        icon: Icon(Icons.close, color: Colors.orange, size: 18.sp),
                        label: Text(
                          'Mark Absent',
                          style: TextStyle(
                            fontSize: 13.sp,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          padding: EdgeInsets.symmetric(vertical: 14.h),
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16.r),
                          ),
                        ),
                        onPressed: (selectedRollNumber != null && isAlreadyMarked != true) ? _markAbsent : null,
                      ),
                    ),
                  ),
                  if (selectedRollNumber != null) ...[
                    SizedBox(height: 10.h),
                    if (attendanceMode == 'lecture_scan' && currentLectureIndex != null) ...[
                      SizedBox(
                        height: 52.h,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                AppTheme.primaryBlue,
                                AppTheme.primaryBlue.withValues(alpha: 0.8),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(16.r),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.primaryBlue.withValues(alpha: 0.3),
                                blurRadius: 10.r,
                                spreadRadius: 1.w,
                              ),
                            ],
                          ),
                          child: ElevatedButton.icon(
                            icon: Icon(Icons.face, size: 18.sp, color: Colors.white),
                            label: Text(
                              'Lecture ${currentLectureIndex! + 1} face scan',
                              style: TextStyle(
                                fontSize: 13.sp,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              padding: EdgeInsets.symmetric(vertical: 12.h),
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              disabledBackgroundColor: Colors.grey.shade300,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16.r),
                              ),
                            ),
                            onPressed: (canMark() && isAlreadyMarked != true) ? () => _markAttendance() : null,
                          ),
                        ),
                      ),
                      SizedBox(height: 10.h),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 56.h,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    AppTheme.primaryGreen,
                                    AppTheme.primaryGreen.withValues(alpha: 0.8),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(16.r),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppTheme.primaryGreen.withValues(alpha: 0.3),
                                    blurRadius: 10.r,
                                    spreadRadius: 1.w,
                                  ),
                                ],
                              ),
                              child: ElevatedButton.icon(
                                icon: Icon(Icons.photo_camera_rounded, size: 18.sp, color: Colors.white),
                                label: Text(
                                  'Entry (camera)',
                                  style: TextStyle(
                                    fontSize: 12.sp,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 4.w),
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  disabledBackgroundColor: Colors.grey.shade400,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16.r),
                                  ),
                                ),
                                onPressed: (canMark() && isAlreadyMarked != true && !_hasEntryPhoto())
                                    ? () => _markAttendance(photoIntent: 'entry')
                                    : null,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: 10.w),
                        Expanded(
                          child: SizedBox(
                            height: 56.h,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    AppTheme.accentOrange,
                                    AppTheme.accentOrange.withValues(alpha: 0.8),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(16.r),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppTheme.accentOrange.withValues(alpha: 0.3),
                                    blurRadius: 10.r,
                                    spreadRadius: 1.w,
                                  ),
                                ],
                              ),
                              child: ElevatedButton.icon(
                                icon: Icon(Icons.photo_camera_rounded, size: 18.sp, color: Colors.white),
                                label: Text(
                                  'Exit (camera)',
                                  style: TextStyle(
                                    fontSize: 12.sp,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 4.w),
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  disabledBackgroundColor: Colors.grey.shade400,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16.r),
                                  ),
                                ),
                                onPressed: (canMark() &&
                                        isAlreadyMarked != true &&
                                        _hasEntryPhoto() &&
                                        !_hasExitPhoto() &&
                                        !_lectureScanBlocksExit())
                                    ? () => _markAttendance(photoIntent: 'exit')
                                    : null,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
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
          if (widget.restrictToAttendanceOnly)
            IconButton(
              icon: const Icon(Icons.logout, color: Colors.white),
              tooltip: 'Sign out',
              onPressed: () async {
                await SessionManager.signOut();
                if (context.mounted) {
                  Navigator.of(context).pushNamedAndRemoveUntil(
                    LoginScreen.routeName,
                    (route) => false,
                  );
                }
              },
            )
          else
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
                'Entry photo when they arrive, exit photo when they leave — both show for the day; next calendar day starts fresh.',
                textAlign: TextAlign.center,
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
      final isAbsent = existingAttendanceData?['status'] == 'absent';
      if (isAbsent) {
        final reason = existingAttendanceData?['absentReason']?.toString() ??
            existingAttendanceData?['reason']?.toString() ??
            'Already marked absent for today';
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.orange.withValues(alpha: 0.5),
              width: 2,
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.block_rounded, color: Colors.orange, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Student Already Absent',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      reason,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
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

      if (!_legacyDayAttendance && studentEnrolledSubjects.isNotEmpty) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.orange.withValues(alpha: 0.5),
              width: 2,
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.check_circle_outline, color: Colors.orange, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'All subjects complete for today',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'After midnight (new calendar day) you can mark entry/exit for each subject again.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
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

    if (!_legacyDayAttendance &&
        studentEnrolledSubjects.isNotEmpty &&
        existingAttendanceData != null &&
        isAlreadyMarked == false) {
      final key = _displaySubjectSliceForSessions();
      if (key != null) {
        final sess = Map<String, dynamic>.from(
          _mapSubjectSessions(existingAttendanceData)[key] ?? {},
        );
        if (_sessionHasEntryMap(sess) && !_sessionCompleteMap(sess)) {
          final entryAt =
              _asDateTime(sess['entryTime']) ?? _asDateTime(sess['timestamp']);
          final tf =
              entryAt != null ? DateFormat('HH:mm').format(entryAt.toLocal()) : '—';
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.blue.withValues(alpha: 0.55),
                width: 2,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.photo_camera_outlined, color: Colors.lightBlueAccent, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Entry done for "$key" — exit pending',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Entry time: $tf · Take exit photo to complete this subject.',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.88),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }
      }
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
              (!_legacyDayAttendance && studentEnrolledSubjects.isNotEmpty)
                  ? 'The app uses the current allotted subject automatically. Take entry and exit photos in order, and the next subject unlocks after the current one is finished. Everything resets after midnight.'
                  : 'Attendance not marked yet. You can proceed to mark attendance.',
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
    if (selectedRollNumber == null) {
      return const SizedBox.shrink();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    late final bool hasEntry;
    late final bool hasExit;
    late final String? entryPhoto;
    late final String? entryPath;
    late final DateTime? entryTs;
    late final String? exitPhoto;
    late final String? exitPath;
    late final DateTime? exitTs;
    var titleSuffix = '';

    if (!_legacyDayAttendance && studentEnrolledSubjects.isNotEmpty) {
      final key = _displaySubjectSliceForSessions();
      if (key != null && existingAttendanceData != null) {
        final sess = Map<String, dynamic>.from(
          _mapSubjectSessions(existingAttendanceData)[key] ?? {},
        );
        titleSuffix = ' — $key';
        hasEntry = _sessionHasEntryMap(sess);
        hasExit = _sessionCompleteMap(sess);
        entryPhoto = _sessionEntryPhotoUrl(sess);
        entryPath = _sessionEntryPhotoPath(sess);
        entryTs = _asDateTime(sess['entryTime']) ??
            _asDateTime(sess['timestamp']) ??
            _asDateTime(sess['entry_time']);
        exitPhoto = _sessionExitPhotoUrl(sess);
        exitPath = _sessionExitPhotoPath(sess);
        exitTs = _asDateTime(sess['exitTime']) ?? _asDateTime(sess['exit_time']);
      } else {
        titleSuffix = '';
        hasEntry = false;
        hasExit = false;
        entryPhoto = null;
        entryPath = null;
        entryTs = null;
        exitPhoto = null;
        exitPath = null;
        exitTs = null;
      }
    } else {
      final d = existingAttendanceData;
      if (d == null) {
        hasEntry = false;
        hasExit = false;
        entryPhoto = null;
        entryPath = null;
        entryTs = null;
        exitPhoto = null;
        exitPath = null;
        exitTs = null;
      } else {
        final m = Map<String, dynamic>.from(d);
        hasEntry = _sessionHasEntryMap(m);
        hasExit = _sessionCompleteMap(m);
        entryPhoto = _sessionEntryPhotoUrl(m);
        entryPath = _sessionEntryPhotoPath(m);
        entryTs = _asDateTime(m['entryTime']) ??
            _asDateTime(m['timestamp']) ??
            _asDateTime(m['entry_time']);
        exitPhoto = _sessionExitPhotoUrl(m);
        exitPath = _sessionExitPhotoPath(m);
        exitTs = _asDateTime(m['exitTime']) ?? _asDateTime(m['exit_time']);
      }
    }

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
                  'Entry/Exit Status$titleSuffix',
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
              Expanded(
                child: _buildPhotoCard(
                  photoUrl: hasEntry ? entryPhoto : null,
                  storagePath: entryPath,
                  timestamp: entryTs,
                  label: 'Entry',
                  isMarked: hasEntry,
                  color: AppTheme.primaryGreen,
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: _buildPhotoCard(
                  photoUrl: hasExit ? exitPhoto : null,
                  storagePath: exitPath,
                  timestamp: exitTs,
                  label: 'Exit',
                  isMarked: hasExit,
                  color: AppTheme.accentOrange,
                ),
              ),
            ],
          ),
          if (hasEntry && !hasExit) ...[
            SizedBox(height: 12.h),
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
              decoration: BoxDecoration(
                color: AppTheme.primaryBlue.withValues(alpha: isDark ? 0.2 : 0.1),
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(color: AppTheme.primaryBlue.withValues(alpha: 0.35)),
              ),
              child: Row(
                children: [
                  Icon(Icons.timer_outlined, color: AppTheme.primaryBlue, size: 22.sp),
                  SizedBox(width: 10.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Time since entry',
                          style: TextStyle(
                            fontSize: 11.sp,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white70 : AppTheme.textGray,
                          ),
                        ),
                        Text(
                          _elapsedSinceEntryLabel().isEmpty ? '—' : _elapsedSinceEntryLabel(),
                          style: TextStyle(
                            fontSize: 18.sp,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : AppTheme.primaryBlue,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        Text(
                          !_legacyDayAttendance
                              ? 'Complete exit for this subject, then you can pick the next one.'
                              : 'Attendance completes after exit photo. Same roll stays selected.',
                          style: TextStyle(
                            fontSize: 10.sp,
                            color: isDark ? Colors.white60 : AppTheme.textGray,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (hasEntry && hasExit) ...[
            SizedBox(height: 12.h),
            _buildEntryExitDurationBanner(isDark),
          ],
          if (!hasEntry && !hasExit) ...[
            SizedBox(height: 12.h),
            Container(
              padding: EdgeInsets.all(12.w),
              decoration: BoxDecoration(
                color: AppTheme.primaryGreen.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: AppTheme.primaryGreen, size: 18.sp),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: Text(
                      !_legacyDayAttendance
                          ? 'Use Entry photo for the current allotted subject, then Exit the same day. The next subject unlocks after this pair is done.'
                          : 'Start with “Entry photo”, then “Exit photo” the same day. After midnight, records belong to the new calendar day.',
                      style: TextStyle(
                        fontSize: 11.sp,
                        color: isDark ? Colors.white : AppTheme.textDark,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          SizedBox(height: 8.h),
          Text(
            DateFormat('yyyy-MM-dd').format(DateTime.now()),
            style: TextStyle(
              fontSize: 10.sp,
              fontStyle: FontStyle.italic,
              color: isDark ? Colors.white54 : AppTheme.textGray,
            ),
          ),
        ],
      ),
    );
  }

  /// Time between entry and exit for today (and stored hours if present).
  Widget _buildEntryExitDurationBanner(bool isDark) {
    Map<String, dynamic>? slice = existingAttendanceData;
    if (!_legacyDayAttendance && existingAttendanceData != null) {
      final key = _displaySubjectSliceForSessions();
      if (key != null) {
        slice = Map<String, dynamic>.from(
          _mapSubjectSessions(existingAttendanceData)[key] ?? {},
        );
      }
    }
    final entry =
        _asDateTime(slice?['entryTime']) ?? _asDateTime(slice?['timestamp']);
    final exit = _asDateTime(slice?['exitTime']);
    final storedHours = slice?['hours'];
    final storedRaw = slice?['hoursRaw'];
    String line1;
    if (entry != null && exit != null) {
      final d = exit.difference(entry);
      if (!d.isNegative) {
        final totalMin = d.inMinutes;
        final h = totalMin ~/ 60;
        final m = totalMin % 60;
        line1 = 'Time between entry & exit: ${h}h ${m}m';
      } else {
        line1 = 'Time between entry & exit: —';
      }
    } else {
      line1 = 'Time between entry & exit: —';
    }
    String? line2;
    String? line3;
    if (storedHours is num) {
      line2 = 'Credited: ${storedHours.toStringAsFixed(2)} hours';
    }
    if (storedRaw is num) {
      final r = storedRaw.toDouble();
      final c = storedHours is num ? storedHours.toDouble() : null;
      if (c == null || (r - c).abs() > 1e-6) {
        line3 = 'Actual seated: ${r.toStringAsFixed(2)} hours';
      }
    }

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: AppTheme.primaryBlue.withValues(alpha: isDark ? 0.15 : 0.08),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(
          color: AppTheme.primaryBlue.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.timelapse, size: 20.sp, color: AppTheme.primaryBlue),
              SizedBox(width: 8.w),
              Expanded(
                child: Text(
                  line1,
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : AppTheme.textDark,
                  ),
                ),
              ),
            ],
          ),
          if (line2 != null) ...[
            SizedBox(height: 6.h),
            Text(
              line2,
              style: TextStyle(
                fontSize: 12.sp,
                color: isDark ? Colors.white70 : AppTheme.textGray,
              ),
            ),
          ],
          if (line3 != null) ...[
            SizedBox(height: 4.h),
            Text(
              line3,
              style: TextStyle(
                fontSize: 12.sp,
                color: isDark ? Colors.white60 : AppTheme.textGray,
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
      return DateFormat('HH:mm').format(dt.toLocal());
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
                  'Subject selected. Students can queue: Select Roll → Take Photo → Done. Next student ready!',
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
    final thumb = (photoUrl != null && photoUrl.trim().isNotEmpty) ? photoUrl.trim() : null;

    return GestureDetector(
      onTap: thumb != null ? () => _showPhotoDialog(thumb, storagePath, label, timestamp) : null,
      child: Container(
        padding: EdgeInsets.all(12.w),
        decoration: BoxDecoration(
          color: isMarked ? color.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.1),
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
            // Show captured photo when we have a URL; otherwise placeholder icon when not marked /
            // or check + camera hint when marked but URL still resolving.
            if (thumb != null) ...[
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
                      imageUrl: thumb,
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
                isMarked ? Icons.check_circle : Icons.photo_camera_outlined,
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
            if ((thumb != null || isMarked) && timestamp != null) ...[
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
                        DateFormat('MMM dd, yyyy • hh:mm a').format(timestamp.toLocal()),
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
        isExpanded: true,
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
                maxLines: 1,
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
