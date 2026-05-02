import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/app_db.dart';
import '../../core/root_navigator.dart';
import '../../core/supabase_maps.dart';
import '../../core/time_parse.dart';
import '../../core/utils/responsive.dart';
import '../../config/supabase_env.dart';

import '../../core/student_face_embedding_utils.dart';
import '../../core/attendance_presence_rules.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/shimmer_effect.dart';
import '../widgets/enhanced_animations.dart';
import 'login_screen.dart';
import 'student_photos_screen.dart';
import '../../services/inline_student_attendance_service.dart';
import '../../services/stale_attendance_reconciliation_service.dart';
import '../../services/session_manager.dart';
import '../widgets/secure_network_image.dart';
import 'student_face_registration_wrapper.dart';

class StudentManagementScreen extends StatefulWidget {
  static const routeName = '/student-management';

  /// When true, shows the same UI as in admin main nav, but for `attendance_user`:
  /// sign-out control, no system back to leave the portal (use Sign out).
  final bool forAttendanceStaffPortal;

  const StudentManagementScreen({
    super.key,
    this.forAttendanceStaffPortal = false,
  });

  @override
  State<StudentManagementScreen> createState() =>
      _StudentManagementScreenState();
}

class _StudentManagementScreenState extends State<StudentManagementScreen>
    with TickerProviderStateMixin {
  String? _instituteId;
  bool _isLoadingInstitute = true;

  // Search with debounce (server-side)
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _debounce;

  // Paginated student list state (server-side range; scroll loads next page)
  static const int _pageSize = 20;
  int _page = 0;
  bool _hasMore = true;
  bool _isLoadingStudents = false;
  bool _isLoadingMore = false;
  List<Map<String, dynamic>> _students = [];
  int _studentCount = 0;
  final ScrollController _scrollController = ScrollController();

  static const String _studentSelectCols =
      'id,name,user_id,sr_no,year,subject,subjects,face_photo_url,face_embedding';

  Map<String, Map<String, dynamic>> _todayPayloadByRoll = {};

  /// Selected subject on each row for per-subject entry / exit.

  static const Color _exitAttendanceMarkColor = Color(0xFFFFC107);

  int _statsTotal = 0;
  int _statsPresentToday = 0;
  int _statsAbsentToday = 0;
  RealtimeChannel? _studentsChannel;
  RealtimeChannel? _attendanceChannel;
  Timer? _realtimeRefreshDebounce;

  String _supabaseHostForLogs() {
    try {
      return Uri.parse(SupabaseEnv.url).host;
    } catch (_) {
      return 'unknown-host';
    }
  }

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _fadeAnimation =
        CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _fadeController.forward();
    _loadInstituteId();
    _scrollController.addListener(_onScroll);
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _debounce?.cancel();
    _realtimeRefreshDebounce?.cancel();
    if (_studentsChannel != null) appDb.removeChannel(_studentsChannel!);
    if (_attendanceChannel != null) appDb.removeChannel(_attendanceChannel!);
    _scrollController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      final q = _sanitizeStudentSearchToken(_searchController.text);
      if (q == _searchQuery) return;
      setState(() {
        _searchQuery = q;
        _page = 0;
        _students.clear();
        _hasMore = true;
      });
      _loadStudents(reset: true);
    });
  }

  void _onScroll() {
    // Auto-scroll pagination disabled - use manual "Load More" button instead
    // This prevents loading multiple pages automatically when list fits on screen
    // User must explicitly click "Load More" to load next batch
  }

  static String _formatSrDisplay(String? sr) {
    final s = (sr ?? '').trim();
    if (s.isEmpty) return '—';
    final n = int.tryParse(s);
    if (n != null) return n.toString().padLeft(3, '0');
    return s;
  }

  /// PostgREST `.or()` splits on commas; user `%` / `_` widen ilike patterns.
  static String _sanitizeStudentSearchToken(String raw) {
    var s = raw.trim().replaceAll(',', ' ');
    s = s.replaceAll(RegExp(r'[%_]'), '');
    return s.trim();
  }

  /// Server-side match across common student columns (institute already scoped).
  static String? _studentSearchOrFilter(String rawQuery) {
    final q = _sanitizeStudentSearchToken(rawQuery);
    if (q.isEmpty) return null;
    const cols = [
      'name',
      'user_id',
      'sr_no',
      'year',
      'subject',
    ];
    return cols.map((c) => '$c.ilike.%$q%').join(',');
  }

  /// Collapse duplicate DB rows (same roll / auth id) in the visible list.
  static String _studentRowDedupeKey(Map<String, dynamic> mapped) {
    final id = mapped['id']?.toString().trim() ?? '';
    final uid = mapped['userId']?.toString().trim() ?? '';
    final sr = mapped['srNo']?.toString().trim() ?? '';
    if (uid.isNotEmpty) return 'u:$uid';
    if (sr.isNotEmpty) return 's:$sr';
    return 'id:$id';
  }

  static List<Map<String, dynamic>> _dedupeMergedStudents(
    List<Map<String, dynamic>> list,
  ) {
    final keys = <String>{};
    final out = <Map<String, dynamic>>[];
    for (final s in list) {
      final k = _studentRowDedupeKey(s);
      if (keys.contains(k)) continue;
      keys.add(k);
      out.add(s);
    }
    return out;
  }

  /// Stats for header (total students, present/absent today).
  Future<void> _loadHeaderStats() async {
    if (_instituteId == null) return;
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    try {
      final totalRes = await appDb
          .from('students')
          .select('id')
          .eq('institute_id', _instituteId!)
          .count(CountOption.exact);
      final total = totalRes.count;

      final code = await instituteCodeForId(_instituteId!);
      final instituteCodes = <String>{code, _instituteId!.trim()}
        ..removeWhere((s) => s.isEmpty);
      final rows = await appDb
          .from('attendance_in_out')
          .select('student_id,sr_no,type,additional')
          .inFilter('institute_code', instituteCodes.toList())
          .eq('attendance_date', today);

      final Map<String, List<Map<String, dynamic>>> byStudentKey = {};
      for (final raw in rows) {
        final row = Map<String, dynamic>.from(raw as Map);
        final sid = row['student_id']?.toString().trim() ?? '';
        final sr = row['sr_no']?.toString().trim() ?? '';
        final key = sid.isNotEmpty ? sid : sr;
        if (key.isEmpty) continue;
        byStudentKey.putIfAbsent(key, () => []).add(row);
      }

      final presentRolls = <String>{};
      for (final e in byStudentKey.entries) {
        if (studentDayPresentFromInOutRows(e.value)) {
          presentRolls.add(e.key);
        }
      }

      final present = presentRolls.length;
      final absent = (total - present).clamp(0, total);
      if (mounted) {
        setState(() {
          _statsTotal = total;
          _statsPresentToday = present;
          _statsAbsentToday = absent;
        });
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Header stats: $e');
    }
  }

  Future<void> _refreshTodayPayloadsForVisibleStudents() async {
    if (!mounted || _instituteId == null) return;
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    if (_students.isEmpty) {
      if (mounted) setState(() => _todayPayloadByRoll = {});
      return;
    }
    try {
      final code = await instituteCodeForId(_instituteId!);

      final ids = <String>[];
      final idToRollKey = <String, String>{};
      for (final student in _students) {
        final studentId = student['id']?.toString().trim() ?? '';
        final userId = student['userId']?.toString().trim() ?? '';
        final srNo = student['srNo']?.toString().trim() ?? '';
        final rollKey = userId.isNotEmpty ? userId : srNo;

        if (studentId.isEmpty || rollKey.isEmpty) {
          if (kDebugMode) debugPrint('   ⏭️ SKIPPED: studentId or rollKey is empty');
          continue;
        }
        ids.add(studentId);
        idToRollKey[studentId] = rollKey;
      }

      // Map roll → students.id (first wins) for merging legacy rows keyed by sr_no/user_id only.
      final rollToStudentId = <String, String>{};
      for (final e in idToRollKey.entries) {
        rollToStudentId.putIfAbsent(e.value, () => e.key);
      }

      if (ids.isEmpty) {
        if (mounted) setState(() => _todayPayloadByRoll = {});
        return;
      }

      if (kDebugMode) {
        debugPrint(
          '🔍 Today thumbnails: ${_students.length} listed, ${ids.length} with id+roll — institute_code=$code',
        );
      }

      final instituteKey = _instituteId!;
      for (final student in _students) {
        final userId = student['userId']?.toString().trim() ?? '';
        final srNo = student['srNo']?.toString().trim() ?? '';
        final rk = userId.isNotEmpty ? userId : srNo;
        final rawSubs = student['subjectsList'];
        final subjectsList = rawSubs is List
            ? rawSubs.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList()
            : <String>[];
        if (rk.isEmpty || subjectsList.isEmpty) continue;
        await StaleAttendanceReconciliationService.ensureReconciled(
          db: appDb,
          instituteId: instituteKey,
          roll: rk,
          date: today,
          enrolledSubjects: subjectsList,
        );
      }

      void mergeAttendanceRow(Map<String, dynamic> payload, Map<String, dynamic> row) {
        final type = (row['type']?.toString() ?? '').toLowerCase();
        final photoUrl = (row['photo_url'] ?? '').toString().trim();
        final createdAt = row['created_at'];
        final add = row['additional'] is Map
            ? Map<String, dynamic>.from((row['additional'] as Map).cast<String, dynamic>())
            : <String, dynamic>{};

        if (type == 'exit') {
          if (payload['exitPhoto'] == null && photoUrl.isNotEmpty) {
            payload['exitPhoto'] = photoUrl;
          }
          if (payload['exitTime'] == null) {
            payload['exitTime'] = add['exitTime'] ?? createdAt;
          }
          payload['status'] = add['status'];
        } else {
          if (payload['entryPhoto'] == null && photoUrl.isNotEmpty) {
            payload['entryPhoto'] = photoUrl;
          }
          if (payload['photoUrl'] == null && photoUrl.isNotEmpty) {
            payload['photoUrl'] = photoUrl;
          }
          if (payload['entryTime'] == null) {
            payload['entryTime'] = add['entryTime'] ?? createdAt;
          }
          payload['status'] = add['status'];
        }
      }

      final map = <String, Map<String, dynamic>>{};
      const chunk = 100;
      for (var offset = 0; offset < ids.length; offset += chunk) {
        final end = (offset + chunk) > ids.length ? ids.length : offset + chunk;
        final slice = ids.sublist(offset, end);

        final instituteCodes = <String>{
          code,
          (_instituteId ?? '').trim(),
        }..removeWhere((s) => s.isEmpty);

        final rows = await appDb
            .from('attendance_in_out')
            .select('id,student_id,sr_no,type,photo_url,created_at,additional')
            .inFilter('institute_code', instituteCodes.toList())
            .eq('attendance_date', today)
            .inFilter('student_id', slice)
            .order('created_at', ascending: false);

        final seenRowIds = <String>{};
        final byStudent = <String, List<Map<String, dynamic>>>{};
        void absorbRow(Map<String, dynamic> row, String attributedStudentId) {
          final rid = row['id']?.toString().trim() ?? '';
          if (rid.isNotEmpty && seenRowIds.contains(rid)) return;
          if (rid.isNotEmpty) seenRowIds.add(rid);
          if (attributedStudentId.isEmpty) return;
          byStudent.putIfAbsent(attributedStudentId, () => []).add(row);
        }

        for (final raw in rows) {
          final row = Map<String, dynamic>.from(raw as Map);
          final sid = row['student_id']?.toString().trim() ?? '';
          if (sid.isEmpty) continue;
          absorbRow(row, sid);
        }

        final fallbackRolls = <String>{};
        for (final sid in slice) {
          final rollKey = idToRollKey[sid];
          if (rollKey == null || rollKey.isEmpty) continue;
          final have = byStudent[sid];
          if (have == null || have.isEmpty) fallbackRolls.add(rollKey);
        }
        if (fallbackRolls.isNotEmpty) {
          final rowsBySr = await appDb
              .from('attendance_in_out')
              .select('id,student_id,sr_no,type,photo_url,created_at,additional')
              .inFilter('institute_code', instituteCodes.toList())
              .eq('attendance_date', today)
              .inFilter('sr_no', fallbackRolls.toList())
              .order('created_at', ascending: false);
          for (final raw in rowsBySr) {
            final row = Map<String, dynamic>.from(raw as Map);
            final sr = row['sr_no']?.toString().trim() ?? '';
            final sid = rollToStudentId[sr];
            if (sid == null) continue;
            absorbRow(row, sid);
          }
        }

        // Legacy: some rows store roll/user_id in student_id (not students.id) and omit sr_no.
        final stillMissingRolls = <String>{};
        for (final sid in slice) {
          final rk = idToRollKey[sid];
          if (rk == null || rk.isEmpty) continue;
          final have = byStudent[sid];
          if (have == null || have.isEmpty) stillMissingRolls.add(rk);
        }
        var rollAsStudentIdRowCount = 0;
        if (stillMissingRolls.isNotEmpty) {
          final rowsByRollInStudentId = await appDb
              .from('attendance_in_out')
              .select('id,student_id,sr_no,type,photo_url,created_at,additional')
              .inFilter('institute_code', instituteCodes.toList())
              .eq('attendance_date', today)
              .inFilter('student_id', stillMissingRolls.toList())
              .order('created_at', ascending: false);
          rollAsStudentIdRowCount = rowsByRollInStudentId.length;
          for (final raw in rowsByRollInStudentId) {
            final row = Map<String, dynamic>.from(raw as Map);
            final key = row['student_id']?.toString().trim() ?? '';
            final sid = rollToStudentId[key];
            if (sid == null) continue;
            absorbRow(row, sid);
          }
        }

        if (kDebugMode) {
          var n = 0;
          for (final sid in slice) {
            final list = byStudent[sid];
            if (list != null) n += list.length;
          }
          debugPrint(
            '📸 Bulk attendance thumbnails chunk: ${slice.length} student(s), ${rows.length} by students.id'
            '${fallbackRolls.isEmpty ? '' : ', sr_no fallback for ${fallbackRolls.length} key(s)'}'
            '${stillMissingRolls.isEmpty ? '' : ', student_id=roll fetched $rollAsStudentIdRowCount row(s)'}, merged $n for slice',
          );
        }

        for (final sid in slice) {
          final rollKey = idToRollKey[sid];
          final list = byStudent[sid];
          if (rollKey == null || list == null || list.isEmpty) continue;

          final payload = <String, dynamic>{};
          for (final row in list) {
            mergeAttendanceRow(payload, row);
          }
          if (payload.isNotEmpty) {
            map[rollKey] = payload;
          }
        }
      }

      if (mounted) setState(() => _todayPayloadByRoll = map);
    } catch (e) {
      if (kDebugMode) debugPrint('Today payloads: $e');
    }
  }

  Future<void> _loadInstituteId() async {
    try {
      final user = appDb.auth.currentUser;
      if (user == null) {
        setState(() => _isLoadingInstitute = false);
        return;
      }

      if (kDebugMode) {
        debugPrint('🔐 Loading institute ID for user: ${user.id}');
        debugPrint('   📱 Device/Phone Info for debugging cross-device sync');
      }

      final row = await appDb.from('profiles').select('institute_id').eq('id', user.id).maybeSingle();
      if (!mounted) return;
      final foundInstituteId = row?['institute_id'] as String?;

      if (foundInstituteId != null && foundInstituteId.isNotEmpty) {
        if (kDebugMode) {
          debugPrint('✅ User found in institute: $foundInstituteId');
          debugPrint('   📊 Profile institute_id: $foundInstituteId');

          // DIAGNOSTIC: Check if students table has entries for this institute
          try {
            final studentCount = await appDb
                .from('students')
                .select('id')
                .eq('institute_id', foundInstituteId)
                .count(CountOption.exact);
            debugPrint('   📚 Total students in institute: ${studentCount.count}');
          } catch (e) {
            debugPrint('   ⚠️ Could not count students: $e');
          }
        }
        setState(() {
          _instituteId = foundInstituteId;
          _isLoadingInstitute = false;
        });
        await _subscribeRealtime();
        await _bootstrapStudentList();
        return;
      }

      if (kDebugMode) {
        debugPrint('❌ CRITICAL: User not found in any institute!');
        debugPrint('   User ID: ${user.id}');
        debugPrint('   Profile row: $row');
        debugPrint('   This means the profile institute_id is NULL or EMPTY');
      }
      if (mounted) setState(() => _isLoadingInstitute = false);
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Institute load error: $e');
      if (mounted) setState(() => _isLoadingInstitute = false);
    }
  }

  Future<void> _bootstrapStudentList() async {
    if (_instituteId == null) return;
    final instituteId = _instituteId!;
    var page = const _StudentPage(rows: [], total: 0, hasMore: false);

    try {
      page = await _fetchStudentPage(pageIndex: 0, query: '', previousTotal: null);
      if (kDebugMode) {
        debugPrint(
          '📚 Student list bootstrap for institute $instituteId: ${page.total} total, ${page.rows.length} first-page rows',
        );
        debugPrint('   Supabase host: ${_supabaseHostForLogs()}');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Student bootstrap load error for institute $instituteId: $e');
    }

    if (!mounted) return;
    _applyStudentPage(page, reset: true);
  }

  Future<void> _subscribeRealtime() async {
    if (_instituteId == null || _instituteId!.isEmpty) return;

    if (_studentsChannel != null) {
      await appDb.removeChannel(_studentsChannel!);
      _studentsChannel = null;
    }
    if (_attendanceChannel != null) {
      await appDb.removeChannel(_attendanceChannel!);
      _attendanceChannel = null;
    }

    void scheduleRefresh({bool attendanceOnly = false}) {
      _realtimeRefreshDebounce?.cancel();
      _realtimeRefreshDebounce = Timer(const Duration(milliseconds: 600), () async {
        if (!mounted) return;
        if (attendanceOnly) {
          await _refreshTodayPayloadsForVisibleStudents();
          await _loadHeaderStats();
        } else {
          await _loadStudents(reset: true);
          await _loadHeaderStats();
        }
      });
    }

    _studentsChannel = appDb
        .channel('student-management-students-${_instituteId!}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'students',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'institute_id',
            value: _instituteId!,
          ),
          callback: (_) {
            if (kDebugMode) {
              debugPrint('🔄 Realtime students update received for institute $_instituteId');
            }
            scheduleRefresh();
          },
        )
        .subscribe();

    final code = await instituteCodeForId(_instituteId!);
    _attendanceChannel = appDb
        .channel('student-management-attendance-$code')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'attendance_in_out',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'institute_code',
            value: code,
          ),
          callback: (_) {
            if (kDebugMode) {
              debugPrint('🔄 Realtime attendance update received for institute code $code');
            }
            scheduleRefresh(attendanceOnly: true);
          },
        )
        .subscribe();
  }

  Future<_StudentPage> _fetchStudentPage({
    required int pageIndex,
    required String query,
    required int? previousTotal,
  }) async {
    if (_instituteId == null) {
      return const _StudentPage(rows: [], total: 0, hasMore: false);
    }
    final instituteId = _instituteId!;

    dynamic dataQ = appDb.from('students').select(_studentSelectCols).eq('institute_id', instituteId);
    dynamic countQ = appDb.from('students').select('id').eq('institute_id', instituteId);
    final searchFilter = _studentSearchOrFilter(query);
    if (searchFilter != null) {
      dataQ = dataQ.or(searchFilter);
      countQ = countQ.or(searchFilter);
    }

    final total = (pageIndex > 0 && previousTotal != null)
        ? previousTotal
        : (await countQ.count(CountOption.exact)).count;

    final from = pageIndex * _pageSize;
    if (from >= total) {
      return _StudentPage(rows: [], total: total, hasMore: false);
    }

    final rows = await dataQ
        .order('created_at', ascending: true)
        .order('id', ascending: true)
        .range(from, from + _pageSize - 1);

    final list =
        (rows as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

    final seen = <String>{};
    final deduped = <Map<String, dynamic>>[];
    for (final row in list) {
      final id = row['id']?.toString().trim() ?? '';
      if (id.isNotEmpty && !seen.contains(id)) {
        seen.add(id);
        deduped.add(row);
      }
    }

    final hasMore = from + deduped.length < total;

    if (kDebugMode) {
      debugPrint(
        '📋 Students page $pageIndex: ${deduped.length} row(s), total=$total, hasMore=$hasMore',
      );
    }

    return _StudentPage(rows: deduped, total: total, hasMore: hasMore);
  }

  void _applyStudentPage(_StudentPage page, {required bool reset}) {
    if (!mounted) return;
    final mapped = page.rows.map(_mapStudentRow).toList();
    setState(() {
      if (reset) {
        _students = _dedupeMergedStudents(mapped);
      } else {
        _students = _dedupeMergedStudents([..._students, ...mapped]);
      }
      _page = reset ? 1 : _page + 1;
      _hasMore = page.hasMore;
      _studentCount = page.total;
      _isLoadingStudents = false;
      _isLoadingMore = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _refreshTodayPayloadsForVisibleStudents();
        if (reset) _loadHeaderStats();
      }
    });
  }

  Future<void> _loadStudents({bool reset = false}) async {
    if (_instituteId == null) return;
    if (reset) {
      if (!mounted) return;
      setState(() {
        _isLoadingStudents = true;
        _page = 0;
        _students.clear();
        _hasMore = true;
      });
      debugPrint('🔄 Loading students from RESET...');
    } else {
      if (_isLoadingMore || !_hasMore) return;
      setState(() => _isLoadingMore = true);
      debugPrint('🔄 Loading students page: ${_page + 1}...');
    }

    try {
      final pageData = await _fetchStudentPage(
        pageIndex: reset ? 0 : _page,
        query: _searchQuery,
        previousTotal: reset ? null : _studentCount,
      );
      debugPrint('✅ Loaded ${pageData.rows.length} students for page ${reset ? 0 : _page}, total: ${pageData.total}, hasMore: ${pageData.hasMore}');
      _applyStudentPage(pageData, reset: reset);
    } catch (e) {
      if (kDebugMode) debugPrint('Student load error: $e');
      if (mounted) setState(() { _isLoadingStudents = false; _isLoadingMore = false; });
    }
  }

  Map<String, dynamic> _mapStudentRow(Map<String, dynamic> row) {
    String subject = row['subject']?.toString().trim() ?? '';
    final subs = row['subjects'];
    if (subject.isEmpty && subs is List && subs.isNotEmpty) {
      subject = subs.map((e) => e.toString()).join(', ');
    }

    final srRaw = row['sr_no']?.toString().trim() ?? '';
    final regUrl = (row['face_photo_url'] as String?)?.trim();
    final url = regUrl ?? '';

    final parsedSubs = _parseSubjectsList(row);
    final hasFaceEmb = studentHasNonEmptyFaceEmbedding(row['face_embedding']);

    if (kDebugMode && url.isEmpty) {
      debugPrint('⚠️ Student has no photo URL:');
      debugPrint('   Name: ${row['name']}');
      debugPrint('   face_photo_url: EMPTY');
    } else if (kDebugMode && url.isNotEmpty) {
      debugPrint('✅ Student photo found:');
      debugPrint('   Name: ${row['name']}');
      debugPrint('   Photo URL: $url');
    }

    if (kDebugMode) {
      debugPrint('✅ Mapped student: ${row['name']}');
      debugPrint('   hasFaceEmbedding: $hasFaceEmb');
      debugPrint('   subjectsList count: ${parsedSubs.length}');
      debugPrint('   subjectsList: $parsedSubs');
    }

    return {
      'id': row['id'],
      'name': row['name'],
      'userId': row['user_id'] ?? row['sr_no'] ?? '',
      'srNo': srRaw.isNotEmpty ? srRaw : (row['user_id']?.toString() ?? ''),
      'subject': subject,
      'subjectsList': parsedSubs,
      'year': row['year'],
      'photoUrl': url,
      'hasFaceEmbedding': hasFaceEmb,
    };
  }

  // Polling removed — data is loaded on demand with server-side pagination.

  @override
  Widget build(BuildContext context) {
    if (_isLoadingInstitute) {
      return const Scaffold(
        backgroundColor: AppTheme.backgroundGrey,
        body: Center(child: CircularProgressIndicator(color: AppTheme.primaryBlue)),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: !widget.forAttendanceStaffPortal,
      onPopInvokedWithResult: (didPop, result) {
        if (widget.forAttendanceStaffPortal) return;
        if (didPop) return;
        // Check if we're in a PageView (main navigation) or as a separate route
        // If we can pop, do it normally
        if (Navigator.of(context).canPop()) {
          Navigator.pop(context);
        }
        // If we can't pop (likely in PageView), do nothing - let user use bottom nav
        // Don't force navigation to home
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: isDark ? const Color(0xFF0F172A) : AppTheme.backgroundGrey,
        body: SafeArea(
          top: false,
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: RefreshIndicator(
              onRefresh: () async {
                await _loadStudents(reset: true);
                await _loadHeaderStats();
              },
              child: CustomScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                slivers: [
                  SliverToBoxAdapter(child: _buildBlueStudentsHeader()),
                  SliverToBoxAdapter(child: _buildSearchBar()),
                  if (_instituteId != null)
                    SliverToBoxAdapter(child: _buildSummaryStatCards()),
                  if (_instituteId != null &&
                      (_studentCount > 0 || _students.isNotEmpty))
                    SliverToBoxAdapter(child: _buildListProgressHint()),
                  ..._buildStudentContentSlivers(context, isDark),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBlueStudentsHeader() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(14.w, 10.h, 10.w, 12.h),
      color: AppTheme.primaryBlue,
      child: Row(
        children: [
          if (widget.forAttendanceStaffPortal) ...[
            IconButton(
              icon: Icon(Icons.logout, color: Colors.white, size: 22.sp),
              tooltip: 'Sign out',
              padding: EdgeInsets.zero,
              constraints: BoxConstraints(minWidth: 36.w, minHeight: 36.h),
              onPressed: () async {
                await SessionManager.signOut();
                if (!context.mounted) return;
                rootNavigatorKey.currentState?.pushNamedAndRemoveUntil(
                  LoginScreen.routeName,
                  (_) => false,
                );
              },
            ),
            SizedBox(width: 4.w),
          ],
          Icon(Icons.school_rounded, color: Colors.white.withValues(alpha: 0.95), size: 22.sp),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(
              'Students',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17.sp,
                fontWeight: FontWeight.w800,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _headerStatChip('Total', _statsTotal),
                  SizedBox(width: 6.w),
                  _headerStatChip('Present', _statsPresentToday),
                  SizedBox(width: 6.w),
                  _headerStatChip('Absent', _statsAbsentToday),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerStatChip(String label, int value) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(14.r),
      ),
      child: Text(
        '$label $value',
        style: TextStyle(
          color: Colors.white,
          fontSize: 10.sp,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildSummaryStatCards() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 0),
      child: Row(
        children: [
          Expanded(
            child: _bigStatCard(
              label: 'Total',
              value: _statsTotal,
              icon: Icons.people_alt_rounded,
              color: AppTheme.primaryBlue,
              isDark: isDark,
            ),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: _bigStatCard(
              label: 'Present',
              value: _statsPresentToday,
              icon: Icons.check_circle_rounded,
              color: AppTheme.primaryGreen,
              isDark: isDark,
            ),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: _bigStatCard(
              label: 'Absent',
              value: _statsAbsentToday,
              icon: Icons.cancel_rounded,
              color: AppTheme.accentRed,
              isDark: isDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _bigStatCard({
    required String label,
    required int value,
    required IconData icon,
    required Color color,
    required bool isDark,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 14.h, horizontal: 8.w),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white,
        borderRadius: BorderRadius.circular(14.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 26.sp),
          SizedBox(height: 6.h),
          Text(
            '$value',
            style: TextStyle(
              fontSize: 20.sp,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : AppTheme.textDark,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.sp,
              color: isDark ? Colors.white70 : AppTheme.textGray,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String? _entryPhotoUrl(Map<String, dynamic> p) {
    final e = p['entryPhoto'] ?? p['photoUrl'];
    if (e is String && e.trim().isNotEmpty) return e.trim();
    return null;
  }

  String? _exitPhotoUrl(Map<String, dynamic> p) {
    final e = p['exitPhoto'];
    if (e is String && e.trim().isNotEmpty) return e.trim();
    return null;
  }

  String _formatPayloadTime(Map<String, dynamic>? p, bool isEntry) {
    if (p == null) return '—';
    final t = isEntry ? parseAnyTimestamp(p['entryTime']) : parseAnyTimestamp(p['exitTime']);
    if (t == null) return '—';
    final loc = t.toLocal();
    return DateFormat('HH:mm:ss').format(loc);
  }

  List<String> _parseSubjectsList(Map<String, dynamic> row) {
    final subs = row['subjects'];
    final out = <String>[];

    if (kDebugMode) {
      debugPrint('🔍 Raw subjects for ${row['name']}: $subs (type: ${subs.runtimeType})');
    }

    if (subs is List) {
      // Handle native List format
      for (final e in subs) {
        final s = e.toString().trim();
        if (s.isNotEmpty && !out.contains(s)) {
          out.add(s);
          if (kDebugMode) debugPrint('  ✓ Added from List: "$s"');
        }
      }
    } else if (subs is String && subs.isNotEmpty) {
      // Handle JSON string format: '["GCC TBC ENG 40","GCC TBC ENG 30"]'
      String cleaned = subs.trim();

      // Remove outer brackets and quotes
      if (cleaned.startsWith('[') && cleaned.endsWith(']')) {
        cleaned = cleaned.substring(1, cleaned.length - 1);
      } else if (cleaned.startsWith('{') && cleaned.endsWith('}')) {
        cleaned = cleaned.substring(1, cleaned.length - 1);
      }

      // Split by comma and clean each item
      if (cleaned.isNotEmpty) {
        final parts = cleaned.split(',');
        for (final p in parts) {
          var trimmed = p.trim();
          // Remove quotes from JSON strings
          if (trimmed.startsWith('"') && trimmed.endsWith('"')) {
            trimmed = trimmed.substring(1, trimmed.length - 1);
          }
          if (trimmed.isNotEmpty && !out.contains(trimmed)) {
            out.add(trimmed);
            if (kDebugMode) debugPrint('  ✓ Added from String: "$trimmed"');
          }
        }
      }
    }

    // Remove duplicates (case-insensitive comparison)
    final deduplicated = <String>[];
    for (final s in out) {
      if (!deduplicated.any((existing) => existing.toLowerCase() == s.toLowerCase())) {
        deduplicated.add(s);
      }
    }

    // Fallback to subject column if no subjects array found
    if (deduplicated.isEmpty) {
      final single = row['subject']?.toString().trim() ?? '';
      if (single.isNotEmpty) {
        deduplicated.add(single);
        if (kDebugMode) debugPrint('  ⚠️  Fallback to subject column: "$single"');
      }
    }

    if (kDebugMode && deduplicated.isNotEmpty) {
      debugPrint('✅ Final ${deduplicated.length} subjects for ${row['name']}: $deduplicated');
    }

    return deduplicated;
  }

  bool _sliceHasEntry(Map<String, dynamic>? slice) {
    if (slice == null) return false;
    return slice['entryPhoto'] != null ||
        slice['photoUrl'] != null ||
        slice['entryTime'] != null;
  }

  bool _sliceComplete(Map<String, dynamic>? slice) {
    if (slice == null) return false;
    return slice['exitPhoto'] != null || slice['exitTime'] != null;
  }

  Future<void> _markAttendanceForSubject(
    BuildContext context, {
    required String rollKey,
    required String step,
  }) async {
    if (_instituteId == null || rollKey.isEmpty) return;
    await InlineStudentAttendanceService.markForRoll(
      context,
      instituteId: _instituteId!,
      rollNumber: rollKey,
      explicitStep: step,
    );
    if (!mounted) return;
    await _refreshTodayPayloadsForVisibleStudents();
  }

  String? _durationChipText(Map<String, dynamic>? p) {
    if (p == null) return null;
    Duration? dur;
    final h = p['hours'];
    if (h is num) {
      dur = Duration(seconds: (h.toDouble() * 3600).round());
    } else {
      final et = parseAnyTimestamp(p['entryTime']);
      final xt = parseAnyTimestamp(p['exitTime']);
      if (et != null && xt != null && !xt.isBefore(et)) {
        dur = xt.difference(et);
      }
    }
    if (dur == null) return null;
    return 'Duration: ${formatSeatedDurationHuman(dur)}';
  }

  Widget _buildAttendanceThumb({
    required String label,
    required Color borderColor,
    required String? imageUrl,
    required String time,
    required bool isDark,
    VoidCallback? onTap,
    bool dimmed = false,
  }) {
    final box = Container(
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: imageUrl != null && imageUrl.isNotEmpty
          ? SecureNetworkImage(
              imageUrl: imageUrl,
              storagePath: null,
              width: double.infinity,
              height: 48,
              fit: BoxFit.cover,
              placeholder: ColoredBox(color: borderColor.withValues(alpha: 0.08)),
              errorWidget: ColoredBox(
                color: borderColor.withValues(alpha: 0.08),
                child: Icon(Icons.broken_image_outlined, color: borderColor, size: 22),
              ),
            )
          : ColoredBox(
              color: isDark ? Colors.white.withValues(alpha: 0.06) : AppTheme.backgroundGrey,
              child: Icon(Icons.photo_camera_outlined, color: borderColor.withValues(alpha: 0.65), size: 22),
            ),
    );

    Widget thumb = onTap != null
        ? Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(8),
              child: box,
            ),
          )
        : box;

    if (dimmed) {
      thumb = Opacity(opacity: 0.42, child: thumb);
    }

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: borderColor,
            ),
          ),
          const SizedBox(height: 4),
          thumb,
          const SizedBox(height: 2),
          Text(
            time,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white70 : AppTheme.textGray,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  /// Bottom inset for scroll content above the bottom nav / gesture bar.
  EdgeInsets _studentListOuterPadding(BuildContext context) {
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final horizontal = context.vw(4).clamp(12.0, 24.0);
    final top = context.vh(1.5).clamp(10.0, 20.0);
    final bottomBase = context.vh(2).clamp(12.0, 24.0);
    return EdgeInsets.fromLTRB(
      horizontal,
      top,
      horizontal,
      bottomBase + safeBottom,
    );
  }

  List<Widget> _buildStudentContentSlivers(BuildContext context, bool isDark) {
    if (_instituteId == null) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: _buildModernCard(
                isDark: isDark,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline,
                        size: 60, color: AppTheme.accentRed),
                    const SizedBox(height: 16),
                    Text(
                      'Institute not found',
                      style: TextStyle(
                        color: isDark ? Colors.white : AppTheme.textDark,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Please login again or contact support',
                      style: TextStyle(
                        color: isDark ? Colors.white70 : AppTheme.textGray,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ];
    }

    if (_isLoadingStudents) {
      return [
        SliverPadding(
          padding: _studentListOuterPadding(context),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (ctx, index) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ShimmerListItem().stagger(index: index),
              ),
              childCount: 5,
            ),
          ),
        ),
      ];
    }

    if (_students.isEmpty && !_isLoadingStudents) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: _buildModernCard(
                isDark: isDark,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_searchQuery.isNotEmpty ? Icons.search_off : Icons.school,
                        size: 60, color: AppTheme.primaryBlue),
                    const SizedBox(height: 16),
                    Text(
                      _searchQuery.isNotEmpty ? 'No students found' : 'No students yet',
                      style: TextStyle(
                        color: isDark ? Colors.white : AppTheme.textDark,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _searchQuery.isNotEmpty
                          ? 'Try a different search term'
                          : 'Student records from your institute appear here.',
                      style: TextStyle(
                        color: isDark ? Colors.white70 : AppTheme.textGray,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ];
    }

    return [
      // Pagination info bar
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.2)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Showing ${_students.length} of $_studentCount students',
                  style: TextStyle(
                    color: AppTheme.primaryBlue,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                if (_hasMore || _isLoadingMore)
                  Text(
                    'Scroll down to load more ↓',
                    style: TextStyle(
                      color: AppTheme.textGray,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  )
                else
                  const Icon(Icons.check_circle, size: 16, color: Colors.green),
              ],
            ),
          ),
        ),
      ),
      SliverPadding(
        padding: _studentListOuterPadding(context),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (ctx, index) {
              if (index == _students.length) {
                // Show pagination control instead of just spinner
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Column(
                    children: [
                      if (_isLoadingMore)
                        const Center(child: CircularProgressIndicator(strokeWidth: 2))
                      else if (_hasMore)
                        Center(
                          child: ElevatedButton.icon(
                            onPressed: _loadStudents,
                            icon: const Icon(Icons.arrow_downward),
                            label: Text(
                              'Load More Students (${_students.length}/${_studentCount})',
                              style: const TextStyle(fontSize: 14),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryBlue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            ),
                          ),
                        )
                      else
                        Center(
                          child: Text(
                            '✅ Showing all ${_students.length} students',
                            style: TextStyle(
                              color: AppTheme.textGray,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              }
              return _buildStudentListItem(context, index, isDark);
            },
            childCount: _students.length + 1, // Always show pagination control at bottom
          ),
        ),
      ),
    ];
  }

  Widget _buildStudentListItem(BuildContext context, int index, bool isDark) {
    final data = _students[index];
    final name = data['name'] ?? 'Unknown';
    final rollNumber = data['userId'] ?? '';
    final srNo = data['srNo']?.toString() ?? rollNumber.toString();
    final subject = data['subject'] ?? '';
    final profileUrl = (data['photoUrl'] as String?) ?? '';
    final hasPhoto = profileUrl.isNotEmpty;
    final rollKey = rollNumber.toString().trim();
    final payload = rollKey.isNotEmpty ? _todayPayloadByRoll[rollKey] : null;
    final hasFaceEmbedding = data['hasFaceEmbedding'] == true;
    final studentId = data['id']?.toString() ?? '';
    final rawSubs = data['subjectsList'];
    final subjectsList = rawSubs is List
        ? rawSubs.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList()
        : <String>[];
    final slice = payload;
    final hasEntryForSubject = _sliceHasEntry(slice);
    final subjectComplete = _sliceComplete(slice);
    final canMark = hasFaceEmbedding;
    final entryEnabled = canMark && !subjectComplete;
    final exitEnabled = canMark && hasEntryForSubject && !subjectComplete;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _buildModernCard(
        isDark: isDark,
        child: IntrinsicHeight(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 72,
                    height: 72,
                    child: hasPhoto
                        ? SecureNetworkImage(
                            imageUrl: profileUrl.isNotEmpty ? profileUrl : null,
                            width: 72,
                            height: 72,
                            fit: BoxFit.cover,
                            placeholder: Container(
                              color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                              child: const Center(
                                child: SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              ),
                            ),
                            errorWidget: Container(
                              color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                              child: const Icon(Icons.person, color: AppTheme.primaryBlue, size: 32),
                            ),
                          )
                        : Container(
                            color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                            child: const Icon(Icons.person, color: AppTheme.primaryBlue, size: 32),
                          ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          color: isDark ? Colors.white : AppTheme.textDark,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'SR NO: ${_formatSrDisplay(srNo)}',
                        style: TextStyle(
                          color: isDark ? Colors.white70 : AppTheme.textGray,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (subjectsList.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Subjects',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white70 : AppTheme.textGray,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: subjectsList
                              .map(
                                (s) => Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.08)
                                        : AppTheme.primaryBlueLight.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: isDark
                                          ? Colors.white.withValues(alpha: 0.16)
                                          : AppTheme.primaryBlue.withValues(alpha: 0.16),
                                    ),
                                  ),
                                  child: Text(
                                    s,
                                    style: TextStyle(
                                      color: isDark ? Colors.white : AppTheme.textDark,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ] else if (subject.toString().trim().isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Subject',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white70 : AppTheme.textGray,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.08)
                                : AppTheme.primaryBlueLight.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.16)
                                  : AppTheme.primaryBlue.withValues(alpha: 0.16),
                            ),
                          ),
                          child: Text(
                            subject.toString().trim(),
                            style: TextStyle(
                              color: isDark ? Colors.white : AppTheme.textDark,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ] else ...[
                        const SizedBox(height: 4),
                        Text(
                          'No subjects — edit student to assign subjects.',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.orange.shade700,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildAttendanceThumb(
                            label: 'Entry',
                            borderColor: AppTheme.primaryGreen,
                            imageUrl: slice != null ? _entryPhotoUrl(slice) : null,
                            time: _formatPayloadTime(slice, true),
                            isDark: isDark,
                            onTap: entryEnabled
                                ? () => _markAttendanceForSubject(
                                      context,
                                      rollKey: rollKey,
                                      step: 'entry',
                                    )
                                : null,
                            dimmed: !entryEnabled,
                          ),
                          const SizedBox(width: 6),
                          _buildAttendanceThumb(
                            label: 'Exit',
                            borderColor: _exitAttendanceMarkColor,
                            imageUrl: slice != null ? _exitPhotoUrl(slice) : null,
                            time: _formatPayloadTime(slice, false),
                            isDark: isDark,
                            onTap: exitEnabled
                                ? () => _markAttendanceForSubject(
                                      context,
                                      rollKey: rollKey,
                                      step: 'exit',
                                    )
                                : null,
                            dimmed: !exitEnabled,
                          ),
                        ],
                      ),
                      if (_durationChipText(slice ?? payload) != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryBlue.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.schedule, size: 14, color: AppTheme.primaryBlue),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  _durationChipText(slice ?? payload)!,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.primaryBlue,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      icon: Icon(
                        hasFaceEmbedding ? Icons.check_circle : Icons.face_retouching_natural,
                        color: hasFaceEmbedding
                            ? (isDark ? Colors.white38 : AppTheme.textLightGray)
                            : AppTheme.primaryGreen,
                        size: 22,
                      ),
                      tooltip: hasFaceEmbedding
                          ? 'Face registered'
                          : 'Register face (duplicate-checked for this institute)',
                      onPressed: hasFaceEmbedding ||
                              rollKey.isEmpty ||
                              studentId.isEmpty ||
                              _instituteId == null
                          ? null
                          : () async {
                              await Navigator.push<void>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => StudentFaceRegistrationWrapper(
                                    studentId: studentId,
                                    studentName: name.toString(),
                                    rollNumber: rollKey,
                                    instituteId: _instituteId!,
                                    onRegistrationSuccess: () {},
                                  ),
                                ),
                              );
                              if (mounted) {
                                await _loadStudents(reset: true);
                                await _loadHeaderStats();
                                _refreshTodayPayloadsForVisibleStudents();
                              }
                            },
                    ),
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      tooltip: 'Photos',
                      icon: Icon(Icons.photo_library, color: isDark ? Colors.white70 : AppTheme.primaryBlue, size: 20),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (ctx) => StudentPhotosScreen(
                              studentName: name,
                              rollNumber: rollNumber,
                              instituteId: _instituteId!,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (_) {
          if (mounted) setState(() {});
        },
        decoration: InputDecoration(
          hintText: 'Search by name, SR no., year, subject…',
          hintStyle: TextStyle(
            color: isDark ? Colors.white.withOpacity(0.5) : AppTheme.textGray,
            fontSize: 14.sp,
          ),
          prefixIcon: Icon(
            Icons.search,
            color: isDark ? Colors.white.withOpacity(0.7) : AppTheme.primaryBlue,
            size: 24.sp,
          ),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: Icon(
                    Icons.clear,
                    color: isDark ? Colors.white.withOpacity(0.7) : AppTheme.textGray,
                    size: 20.sp,
                  ),
                  onPressed: () {
                    _debounce?.cancel();
                    _searchController.clear();
                    setState(() {
                      _searchQuery = '';
                      _page = 0;
                      _students.clear();
                      _hasMore = true;
                    });
                    _loadStudents(reset: true);
                  },
                )
              : null,
          filled: true,
          fillColor: isDark 
              ? Colors.white.withOpacity(0.1) 
              : AppTheme.backgroundGrey,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12.r),
            borderSide: BorderSide(
              color: isDark 
                  ? Colors.white.withOpacity(0.2) 
                  : AppTheme.primaryBlue.withOpacity(0.3),
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12.r),
            borderSide: BorderSide(
              color: isDark 
                  ? Colors.white.withOpacity(0.2) 
                  : AppTheme.primaryBlue.withOpacity(0.3),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12.r),
            borderSide: BorderSide(
              color: isDark ? Colors.white : AppTheme.primaryBlue,
              width: 2,
            ),
          ),
          contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
        ),
        style: TextStyle(
          color: isDark ? Colors.white : AppTheme.textDark,
          fontSize: 14.sp,
        ),
      ),
    );
  }

  Widget _buildListProgressHint() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tail = _hasMore ? ' · Scroll for more' : '';
    final searching = _searchQuery.trim().isNotEmpty;
    final noun = searching ? 'matches' : 'students';
    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 6.h),
      child: Text(
        'Showing ${_students.length} of $_studentCount $noun$tail',
        style: TextStyle(
          fontSize: 12.sp,
          color: isDark ? Colors.white54 : AppTheme.textGray,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildModernCard({required Widget child, required bool isDark}) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
          child: child,
    );
  }
}
/// Lightweight value object returned by server-side paginated student queries.
class _StudentPage {
  final List<Map<String, dynamic>> rows;
  final int total;
  final bool hasMore;

  const _StudentPage({
    required this.rows,
    required this.total,
    required this.hasMore,
  });
}
