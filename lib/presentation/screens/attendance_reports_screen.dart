import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../core/app_db.dart';
import '../../core/attendance_presence_rules.dart';
import '../../core/supabase_maps.dart';
import '../../core/time_parse.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/responsive.dart';
import '../../services/error_handler.dart';
import '../../services/institute_realtime_sync_service.dart';
// Institute open/close/holiday removed.
import '../../services/pdf_export_service.dart';

class AttendanceReportsScreen extends StatefulWidget {
  static const routeName = '/attendance-reports';
  const AttendanceReportsScreen({super.key});

  @override
  State<AttendanceReportsScreen> createState() => _AttendanceReportsScreenState();
}

class _AttendanceReportsScreenState extends State<AttendanceReportsScreen>
    with WidgetsBindingObserver {
  static const int _maxRangeDays = 184; // ~6 months
  static const Duration _autoRefreshInterval = Duration(seconds: 5);
  String? _instituteId;
  List<Map<String, dynamic>> _allInstitutes = [];
  DateTime _selectedStartDate = DateTime.now().subtract(const Duration(days: 7));
  DateTime _selectedEndDate = DateTime.now();
  String? _selectedSubject = 'All Subjects';
  bool _isLoading = false;
  Map<String, dynamic> _reportData = {};
  String _reportMode = 'all'; // all | defaulters
  String _searchQuery = '';
  List<Map<String, dynamic>> _defaultersList = []; // Students with 0 attendance
  Timer? _autoRefreshTimer;
  StreamSubscription<InstituteSyncEvent>? _syncSubscription;
  Timer? _syncDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadInstituteId();
  }

  void _handleAppResumed() {
    if (!mounted || _instituteId == null || _isLoading || _reportData.isEmpty) return;
    _generateReport(showLoader: false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _handleAppResumed();
    }
  }

  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(_autoRefreshInterval, (_) {
      if (!mounted || _instituteId == null || _isLoading || _reportData.isEmpty) return;
      _generateReport(showLoader: false);
    });
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _syncDebounce?.cancel();
    _syncSubscription?.cancel();
    final iid = _instituteId;
    if (iid != null && iid.isNotEmpty) {
      InstituteRealtimeSyncService.instance.release(iid);
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _loadInstituteId() async {
    try {
      final user = appDb.auth.currentUser;
      if (user == null) return;

      final row = await appDb.from('profiles').select('institute_id').eq('id', user.id).maybeSingle();
      if (!mounted) return;
      final iid = row?['institute_id'] as String?;
      if (iid != null && iid.isNotEmpty) {
        // Load current institute
        setState(() {
          _instituteId = iid;
        });
        await InstituteRealtimeSyncService.instance.retain(iid);
        _syncSubscription?.cancel();
        _syncSubscription = InstituteRealtimeSyncService.instance
            .watch(iid)
            .listen((event) {
          if (!mounted) return;
          if (event.type == 'students' || event.type == 'attendance') {
            _syncDebounce?.cancel();
            _syncDebounce = Timer(const Duration(milliseconds: 600), () {
              if (!mounted) return;
              _generateReport(showLoader: false);
            });
          }
        });

        // Load all institutes for multi-institute report
        await _loadAllInstitutes();
        _generateReport();
      }
    } catch (e) {
      if (mounted) {
        final errorResult = ErrorHandler.formatErrorForUI(e, context: 'loadInstituteId');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorResult['message']),
            backgroundColor: AppTheme.accentRed,
          ),
        );
      }
    }
  }

  Future<void> _loadAllInstitutes() async {
    try {
      final institutes = await appDb
          .from('institutes')
          .select('id, name, institute_code')
          .order('name')
          .limit(8000);
      if (mounted) {
        setState(() {
          _allInstitutes = institutes.cast<Map<String, dynamic>>();
        });
      }
    } catch (e) {
      if (mounted) debugPrint('⚠️ Error loading institutes: $e');
    }
  }

  Future<void> _generateReport({bool showLoader = true}) async {
    if (_instituteId == null) return;

    // Validate date range (max 6 months)
    final daysDifference = _selectedEndDate.difference(_selectedStartDate).inDays;
    if (daysDifference > _maxRangeDays) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Date range cannot exceed 6 months. Please select a shorter range.'),
          backgroundColor: AppTheme.accentRed,
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    if (_selectedEndDate.isBefore(_selectedStartDate)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('End date must be after start date'),
          backgroundColor: AppTheme.accentRed,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    if (showLoader) {
      setState(() => _isLoading = true);
    }

    try {
      final startDateStr = DateFormat('yyyy-MM-dd').format(_selectedStartDate);
      final endDateStr = DateFormat('yyyy-MM-dd').format(_selectedEndDate);
      // Holiday system removed.
      final holidayReasons = <String, String>{};

      // Load ALL students from THIS institute ONLY
      List<Map<String, dynamic>> allStudents = (await appDb
          .from('students')
          .select('id,institute_id,user_id,sr_no,name')
          .eq('institute_id', _instituteId!))
          .cast<Map<String, dynamic>>();

      // Get student IDs for filtering attendance
      final studentIds = allStudents.map((s) => s['id']).toList();

      // Load attendance records for ONLY these institute's students
      List<dynamic> rows = [];
      if (studentIds.isNotEmpty) {
        rows = await appDb
            .from('attendance_in_out')
            .select()
            .inFilter('student_id', studentIds)
            .gte('attendance_date', startDateStr)
            .lte('attendance_date', endDateStr);
      }

      print('🔍 REPORT: Fetched ${rows.length} records from $startDateStr to $endDateStr');

      // Count one session per student per day (entry + exit are a single attendance, not two).
      final Map<String, Set<String>> rollsAnyByDate = {};
      final Map<String, Set<String>> rollsPresentByDate = {};
      final Map<String, Set<String>> presentDatesByRoll = {};

      final Map<String, Map<String, List<Map<String, dynamic>>>> rollDateRows = {};

      for (final raw in rows) {
        final data = Map<String, dynamic>.from(raw as Map);
        final date = data['attendance_date']?.toString() ?? '';
        if (date.isEmpty) continue;

        final sid = (data['student_id'] as String?)?.trim() ?? '';
        final sr = (data['sr_no'] as String?)?.trim() ?? '';
        final rollNumber = sid.isNotEmpty ? sid : sr;
        if (rollNumber.isEmpty) continue;

        rollDateRows.putIfAbsent(rollNumber, () => {});
        rollDateRows[rollNumber]!.putIfAbsent(date, () => []).add(data);
      }

      for (final rollEntry in rollDateRows.entries) {
        final rollNumber = rollEntry.key;
        for (final dateEntry in rollEntry.value.entries) {
          final date = dateEntry.key;
          final list = dateEntry.value;
          rollsAnyByDate.putIfAbsent(date, () => <String>{}).add(rollNumber);

          final isPresent = studentDayPresentFromInOutRows(list);

          print('📝 $rollNumber on $date: rows=${list.length}, PRESENT=$isPresent');

          if (isPresent) {
            rollsPresentByDate.putIfAbsent(date, () => <String>{}).add(rollNumber);
            presentDatesByRoll.putIfAbsent(rollNumber, () => <String>{}).add(date);
          }
        }
      }

      print('✅ RESULT: ${rollsPresentByDate.length} students marked present');

      final dailyPresent = <String, int>{};
      final dailyTotal = <String, int>{};
      for (final date in rollsAnyByDate.keys) {
        dailyTotal[date] = rollsAnyByDate[date]!.length;
        dailyPresent[date] = rollsPresentByDate[date]?.length ?? 0;
      }

      final studentsByDate = rollsPresentByDate;

      var totalPresent = 0;
      var totalRecords = 0;
      for (final date in rollsAnyByDate.keys) {
        totalRecords += rollsAnyByDate[date]!.length;
        totalPresent += rollsPresentByDate[date]?.length ?? 0;
      }

      // ✅ Use allStudents loaded above (multi-institute support)
      final rollByStudentId = <String, String>{};
      final nameByRoll = <String, String>{};
      final srNoByRoll = <String, String>{};
      final studentInstituteMap = <String, String>{}; // track which institute each student belongs to

      print('📊 TOTAL allStudents from DB: ${allStudents.length}');

      for (final m in allStudents) {
        final id = m['id'] as String?;
        if (id == null) continue;
        final u = m['user_id'] as String?;
        final sr = m['sr_no'] as String?;
        final iid = m['institute_id'] as String?;
        final rk = (u != null && u.isNotEmpty) ? u : (sr ?? '');
        final nm = m['name']?.toString().trim() ?? '';
        if (rk.isNotEmpty) {
          rollByStudentId[id] = rk;
          if (nm.isNotEmpty) nameByRoll[rk] = nm;
          if (sr != null && sr.trim().isNotEmpty) {
            srNoByRoll[rk] = sr.trim();
          }
          if (iid != null) {
            studentInstituteMap[rk] = iid;
          }
        }
      }

      print('📊 UNIQUE nameByRoll keys: ${nameByRoll.length}');
      print('📊 UNIQUE rollByStudentId keys: ${rollByStudentId.length}');

      // FIX: Remap presentDatesByRoll keys from student_id to roll numbers
      final presentDatesByRollFixed = <String, Set<String>>{};
      for (final entry in presentDatesByRoll.entries) {
        final studentIdOrSrNo = entry.key;
        final roll = rollByStudentId[studentIdOrSrNo] ?? studentIdOrSrNo;
        presentDatesByRollFixed[roll] = entry.value;
        print('✅ REMAP: $studentIdOrSrNo → $roll (${entry.value.length} days present)');
      }
      // Replace with fixed version
      presentDatesByRoll.clear();
      presentDatesByRoll.addAll(presentDatesByRollFixed);

      final studentAttendanceCount = <String, int>{
        for (final e in presentDatesByRoll.entries) e.key: e.value.length,
      };

      // ✅ CALCULATE DEFAULTERS: Students with 0 attendance
      final Set<String> studentsWithAttendance = presentDatesByRoll.keys.toSet();
      final List<Map<String, dynamic>> defaultersList = [];
      for (final student in allStudents) {
        final sr = (student['sr_no'] as String?)?.trim() ?? '';
        final uid = (student['user_id'] as String?)?.trim() ?? '';
        final roll = uid.isNotEmpty ? uid : sr;

        if (roll.isNotEmpty && !studentsWithAttendance.contains(roll)) {
          defaultersList.add({
            'roll': roll,
            'name': student['name']?.toString().trim() ?? 'Unknown',
            'srNo': sr,
            'instituteId': student['institute_id'],
            'attendanceDays': 0,
          });
        }
      }

      final Map<String, List<Map<String, dynamic>>> rawByStudent = {};
      for (final raw in rows) {
        final data = raw as Map<String, dynamic>;
        final sid = (data['student_id'] as String?)?.trim() ?? '';
        final sr = (data['sr_no'] as String?)?.trim() ?? '';
        final key = sid.isNotEmpty ? sid : sr;
        if (key.isEmpty) continue;
        rawByStudent.putIfAbsent(key, () => []).add(Map<String, dynamic>.from(data));
      }

      final dailySeatedSeconds = <String, int>{};
      final studentSeatedSeconds = <String, int>{};
      for (final e in rawByStudent.entries) {
        final merged = PdfExportService.mergeAttendanceInOutRowsByDate(e.value);
        for (final day in merged) {
          final date = day['date'] as String? ?? '';
          if (date.isEmpty) continue;
          final dur = seatedDurationFromMergedAttendanceDay(day);
          if (dur == null || dur <= Duration.zero) continue;
          final sec = dur.inSeconds;
          dailySeatedSeconds[date] = (dailySeatedSeconds[date] ?? 0) + sec;
          studentSeatedSeconds[e.key] = (studentSeatedSeconds[e.key] ?? 0) + sec;
        }
      }

      final totalSeatedSeconds = dailySeatedSeconds.values.fold<int>(0, (a, b) => a + b);

      if (!mounted) return;

      // ✅ Print defaulters summary
      print('📊 DEFAULTERS: ${defaultersList.length} students with 0 attendance');
      if (defaultersList.isNotEmpty) {
        for (final d in defaultersList.take(10)) {
          print('   - ${d['name']} (${d['roll']})');
        }
      }

      setState(() {
        _reportData = {
          'dailyPresent': dailyPresent,
          'dailyTotal': dailyTotal,
          'holidayReasons': holidayReasons,
          'dailySeatedSeconds': dailySeatedSeconds,
          'studentsByDate': studentsByDate,
          'studentAttendanceCount': studentAttendanceCount,
          'studentSeatedSeconds': studentSeatedSeconds,
          'rollByStudentId': rollByStudentId,
          'nameByRoll': nameByRoll,
          'srNoByRoll': srNoByRoll,
          'totalPresent': totalPresent,
          'totalRecords': totalRecords,
          'totalSeatedSeconds': totalSeatedSeconds,
          'averageAttendance': totalRecords > 0 ? (totalPresent / totalRecords * 100) : 0.0,
          'defaultersList': defaultersList,
        };
        _defaultersList = defaultersList;
        _isLoading = false;
      });
      _startAutoRefresh();
    } catch (e) {
      if (!mounted) return;
      if (showLoader || _isLoading) {
        setState(() => _isLoading = false);
      }
      if (mounted) {
        final errorResult = ErrorHandler.formatErrorForUI(e, context: 'generateReport', appType: 'admin');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorResult['message']),
            backgroundColor: AppTheme.accentRed,
          ),
        );
      }
    }
  }

  void _applyQuickRange(int months) {
    final now = DateTime.now();
    final end = DateTime(now.year, now.month, now.day);
    final start = DateTime(end.year, end.month - months, end.day + 1);
    setState(() {
      _selectedStartDate = start;
      _selectedEndDate = end;
    });
    _generateReport();
  }

  Future<Map<String, String>> _loadHolidayReasons(String startDate, String endDate) async {
    // Holiday system removed.
    return <String, String>{};
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : AppTheme.backgroundGrey,
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
            _buildDateRangeSelector(),
            const SizedBox(height: 20),


            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading
                        ? null
                        : () async {
                            setState(() => _reportMode = 'defaulters');
                            await _generateReport();
                          },
                    icon: _isLoading && _reportMode == 'defaulters'
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.warning_amber_rounded),
                    label: const Text('Load Defaulters'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _reportMode == 'defaulters'
                          ? AppTheme.accentRed
                          : AppTheme.accentRed.withValues(alpha: 0.75),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading
                        ? null
                        : () async {
                            setState(() => _reportMode = 'all');
                            await _generateReport();
                          },
                    icon: _isLoading && _reportMode == 'all'
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.groups_rounded),
                    label: const Text('Load All Students'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _reportMode == 'all'
                          ? AppTheme.primaryBlue
                          : AppTheme.primaryBlue.withValues(alpha: 0.75),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Search student by name or SR No',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () => setState(() => _searchQuery = ''),
                        icon: const Icon(Icons.clear),
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Show student list or "no students" message
            if (_reportData.isNotEmpty) ...[
              _buildStudentAttendanceList(),
            ],

            // Show "no students" message when button clicked but no students exist
            if (!_isLoading && _reportMode != null && _reportData.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(40),
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.group_off,
                      size: 48,
                      color: AppTheme.textGray.withOpacity(0.5),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '❌ No students in this institute',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppTheme.accentRed,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Add students to this institute first',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.textGray,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),

            // Only show this message if no button was clicked yet
            if (_reportData.isEmpty && !_isLoading && _reportMode == null)
              Center(
                child: Column(
                  children: [
                    Icon(Icons.analytics_outlined, size: 64, color: AppTheme.textGray),
                    const SizedBox(height: 16),
                    Text(
                      'Select date range and load attendance',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: AppTheme.textGray,
                      ),
                    ),
                  ],
                ),
              ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildDateRangeSelector() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      padding: const EdgeInsets.all(20),
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
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Date Range',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : AppTheme.textDark,
              ),
            ),
          const SizedBox(height: 12),
          // Show date range info
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, 
                  size: 16, 
                  color: isDark ? Colors.white70 : AppTheme.primaryBlue,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Maximum date range: 6 months',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white70 : AppTheme.textGray,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _applyQuickRange(1),
                  child: const Text('1 Month'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _applyQuickRange(3),
                  child: const Text('3 Months'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _applyQuickRange(6),
                  child: const Text('6 Months'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: _selectedStartDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (date != null) {
                      // Validate max 6 months range
                      final daysDifference = _selectedEndDate.difference(date).inDays;
                      if (daysDifference > _maxRangeDays) {
                        // Adjust end date to allowed max range from selected start.
                        final newEndDate = date.add(const Duration(days: _maxRangeDays));
                        setState(() {
                          _selectedStartDate = date;
                          _selectedEndDate = newEndDate.isAfter(DateTime.now()) 
                              ? DateTime.now() 
                              : newEndDate;
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text('Date range limited to maximum 6 months'),
                            backgroundColor: AppTheme.accentOrange,
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      } else {
                        setState(() => _selectedStartDate = date);
                      }
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Start Date',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          DateFormat('MMM dd, yyyy').format(_selectedStartDate),
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InkWell(
                  onTap: () async {
                    // Calculate max end date (6 months from start date or today, whichever is earlier)
                    final maxEndDate = _selectedStartDate.add(const Duration(days: _maxRangeDays));
                    final lastAllowedDate = maxEndDate.isAfter(DateTime.now()) 
                        ? DateTime.now() 
                        : maxEndDate;
                    
                    final date = await showDatePicker(
                      context: context,
                      initialDate: _selectedEndDate.isAfter(lastAllowedDate) 
                          ? lastAllowedDate 
                          : _selectedEndDate,
                      firstDate: _selectedStartDate, // Can't select before start date
                      lastDate: lastAllowedDate, // Max 6 months from start
                    );
                    if (date != null) {
                      // Validate max 6 months range
                      final daysDifference = date.difference(_selectedStartDate).inDays;
                      if (daysDifference > _maxRangeDays) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text('Date range cannot exceed 6 months'),
                            backgroundColor: AppTheme.accentRed,
                            duration: const Duration(seconds: 3),
                          ),
                        );
                        return;
                      }
                      setState(() => _selectedEndDate = date);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'End Date',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          DateFormat('MMM dd, yyyy').format(_selectedEndDate),
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
        ),
      ),
    );
  }

  Widget _buildStudentAttendanceList() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // ✅ Check if institute has NO students at all
    if (_reportData.isEmpty && _defaultersList.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(40),
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
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.group_off,
                size: 48,
                color: AppTheme.textGray.withOpacity(0.5),
              ),
              const SizedBox(height: 16),
              Text(
                '❌ No students added to this institute',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.accentRed,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Add students to this institute first, then their attendance will appear here.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.textGray,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    // ✅ Show defaulters list if in defaulters mode
    if (_reportMode == 'defaulters' && _defaultersList.isNotEmpty) {
      final filteredDefaulters = _defaultersList.where((d) {
        final name = d['name']?.toString() ?? '';
        final roll = d['roll']?.toString() ?? '';
        return _searchQuery.isEmpty
            ? true
            : name.toLowerCase().contains(_searchQuery) || roll.toLowerCase().contains(_searchQuery);
      }).toList();

      return Container(
        padding: const EdgeInsets.all(20),
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
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '⚠️ Defaulters List',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppTheme.accentRed,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Students with 0 attendance (did not mark entry/exit)  |  Total: ${filteredDefaulters.length}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.textGray),
              ),
              const SizedBox(height: 16),
            if (filteredDefaulters.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: Text(
                    'No defaulters found',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              )
            else
              // ✅ Fixed: Use Column instead of ListView to avoid sizing issues
              Column(
                children: [
                  for (int idx = 0; idx < filteredDefaulters.length; idx++) ...[
                    if (idx > 0)
                      Divider(color: AppTheme.textGray.withOpacity(0.2)),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  filteredDefaulters[idx]['name']?.toString() ?? 'Unknown',
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                                Text(
                                  'SR: ${filteredDefaulters[idx]['srNo']?.toString() ?? "N/A"} | Roll: ${filteredDefaulters[idx]['roll']?.toString() ?? "N/A"}',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: AppTheme.textGray,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          Chip(
                            label: const Text('0 days'),
                            backgroundColor: AppTheme.accentRed.withOpacity(0.1),
                            labelStyle: const TextStyle(color: AppTheme.accentRed),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
          ],
            ),
        ),
      );
    }

    // Original student attendance list code
    final studentAttendanceCount = _reportData['studentAttendanceCount'] as Map<String, int>? ?? {};
    final nameByRoll = _reportData['nameByRoll'] as Map<String, String>? ?? {};
    final srNoByRoll = _reportData['srNoByRoll'] as Map<String, String>? ?? {};
    final dailyTotal = _reportData['dailyTotal'] as Map<String, int>? ?? {};
    final totalWorkingDays = dailyTotal.length;

    if (totalWorkingDays == 0 || nameByRoll.isEmpty) {
      return const SizedBox.shrink();
    }

    int? sortableNumber(String value) {
      final match = RegExp(r'\d+').firstMatch(value);
      if (match == null) return null;
      return int.tryParse(match.group(0)!);
    }

    // ✅ DEDUPLICATION: Ensure each roll appears only once
    final seenRolls = <String>{};
    final uniqueNameByRoll = <String, String>{};
    for (final entry in nameByRoll.entries) {
      final roll = entry.key.trim().toLowerCase();
      if (!seenRolls.contains(roll)) {
        seenRolls.add(roll);
        uniqueNameByRoll[entry.key] = entry.value;
      } else if (kDebugMode) {
        debugPrint('⚠️ DUPLICATE ROLL DETECTED: $roll (${entry.value})');
      }
    }
    debugPrint('🔍 nameByRoll count: ${nameByRoll.length} → uniqueNameByRoll count: ${uniqueNameByRoll.length}');

    final allStudents = uniqueNameByRoll.entries.toList()
      ..sort((a, b) {
        final aSr = (srNoByRoll[a.key] ?? a.key).trim();
        final bSr = (srNoByRoll[b.key] ?? b.key).trim();
        final aNum = sortableNumber(aSr);
        final bNum = sortableNumber(bSr);
        if (aNum != null && bNum != null && aNum != bNum) {
          return aNum.compareTo(bNum);
        }
        if (aNum != null && bNum == null) return -1;
        if (aNum == null && bNum != null) return 1;
        final bySrText = aSr.toLowerCase().compareTo(bSr.toLowerCase());
        if (bySrText != 0) return bySrText;
        return a.value.toLowerCase().compareTo(b.value.toLowerCase());
      });

    final filteredStudents = allStudents.where((entry) {
      final roll = entry.key;
      final name = entry.value;
      final presentDays = studentAttendanceCount[roll] ?? 0;
      final absentDays = (totalWorkingDays - presentDays).clamp(0, totalWorkingDays);

      final matchesMode =
          _reportMode == 'defaulters' ? (absentDays > presentDays) : true;
      final matchesSearch = _searchQuery.isEmpty
          ? true
          : name.toLowerCase().contains(_searchQuery) ||
              roll.toLowerCase().contains(_searchQuery);
      return matchesMode && matchesSearch;
    }).toList();

    // isDark already declared at start of method
    return Container(
      padding: const EdgeInsets.all(20),
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
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          Text(
            _reportMode == 'defaulters'
                ? 'Defaulters List'
                : 'Student Attendance List',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            _reportMode == 'defaulters'
                ? 'Showing students where Absent > Present  |  Total attendance days: $totalWorkingDays'
                : 'Showing all students  |  Total attendance days: $totalWorkingDays',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.textGray,
                ),
          ),
          const SizedBox(height: 16),
          if (filteredStudents.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.accentOrange.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.accentOrange.withValues(alpha: 0.2)),
              ),
              child: Text(
                _reportMode == 'defaulters'
                    ? 'No defaulters found for selected range/search.'
                    : 'No students found for selected search.',
                style: const TextStyle(
                  color: AppTheme.textGray,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else
            ...filteredStudents.map((entry) {
              final roll = entry.key;
              final name = entry.value;
              final presentDays = studentAttendanceCount[roll] ?? 0;
              final absentDays = (totalWorkingDays - presentDays).clamp(0, totalWorkingDays);
              final percent = totalWorkingDays == 0 ? 0.0 : (presentDays / totalWorkingDays) * 100;
              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _openStudentReportActions(
                  rollNumber: roll,
                  studentName: name,
                ),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.primaryBlue.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '$name (SR No: $roll)',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textDark,
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.picture_as_pdf_rounded,
                            color: AppTheme.primaryBlue,
                            size: 18,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Total: $totalWorkingDays  |  Present: $presentDays  |  Absent: $absentDays  |  ${percent.toStringAsFixed(1)}%',
                        style: const TextStyle(
                          color: AppTheme.textGray,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
        ),
      ),
    );
  }

  Widget _buildExportButtons() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      padding: const EdgeInsets.all(20),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Export Reports',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _exportAllStudentsPDF,
                  icon: const Icon(Icons.picture_as_pdf, size: 18),
                  label: const Text(
                    'Export All',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _showStudentSelectionDialog,
                  icon: const Icon(Icons.person, size: 18),
                  label: const Text(
                    'Export One',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _exportAllStudentsPDF() async {
    if (_instituteId == null) return;

    setState(() => _isLoading = true);

    try {
      final pdfBytes = await PdfExportService.generateStudentsReport(
        instituteId: _instituteId!,
        startDate: _selectedStartDate,
        endDate: _selectedEndDate,
        subject: _selectedSubject,
      );

      if (mounted) {
        await Printing.layoutPdf(
          onLayout: (format) async => pdfBytes,
        );

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Text('PDF exported successfully!'),
              ],
            ),
            backgroundColor: AppTheme.primaryGreen,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final errorResult = ErrorHandler.formatErrorForUI(e, context: 'exportPDF', appType: 'admin');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorResult['message']),
            backgroundColor: AppTheme.accentRed,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _showStudentSelectionDialog() async {
    if (_instituteId == null) return;

    final studentRows = await appDb.from('students').select('user_id,name,sr_no').eq('institute_id', _instituteId!);

    if (studentRows.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No students found'),
            backgroundColor: AppTheme.accentOrange,
          ),
        );
      }
      return;
    }

    final students = studentRows.map((raw) {
      final data = raw as Map<String, dynamic>;
      return {
        'rollNumber': data['user_id'] as String? ?? data['sr_no'] as String? ?? '',
        'name': data['name'] as String? ?? 'Unknown',
      };
    }).toList();

    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Select Student'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: students.length,
              itemBuilder: (context, index) {
                final student = students[index];
                return ListTile(
                  leading: const Icon(Icons.person),
                  title: Text(student['name'] as String),
                  subtitle: Text('SR No: ${student['rollNumber']}'),
                  onTap: () {
                    Navigator.pop(context);
                    _exportStudentPDF(student['rollNumber'] as String);
                  },
                );
              },
            ),
          ),
        ),
      );
    }
  }

  Future<void> _exportStudentPDF(String rollNumber) async {
    if (_instituteId == null) return;

    setState(() => _isLoading = true);

    try {
      final pdfBytes = await PdfExportService.generateStudentReport(
        instituteId: _instituteId!,
        rollNumber: rollNumber,
        startDate: _selectedStartDate,
        endDate: _selectedEndDate,
      );

      if (mounted) {
        await Printing.layoutPdf(
          onLayout: (format) async => pdfBytes,
        );

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Expanded(
                  child: Text('Student PDF exported successfully!'),
                ),
              ],
            ),
            backgroundColor: AppTheme.primaryGreen,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final errorResult = ErrorHandler.formatErrorForUI(e, context: 'exportStudentPDF', appType: 'admin');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorResult['message']),
            backgroundColor: AppTheme.accentRed,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _openStudentReportActions({
    required String rollNumber,
    required String studentName,
  }) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.picture_as_pdf, color: AppTheme.primaryBlue),
              title: const Text('View PDF Report'),
              subtitle: Text('$studentName (SR No: $rollNumber)'),
              onTap: () async {
                Navigator.of(ctx).pop();
                await _exportStudentPDF(rollNumber);
              },
            ),
            ListTile(
              leading: const Icon(Icons.download_rounded, color: AppTheme.primaryGreen),
              title: const Text('Download / Save to Files'),
              subtitle: const Text('Choose Files in share options'),
              onTap: () async {
                Navigator.of(ctx).pop();
                await _downloadStudentReportPdf(
                  rollNumber: rollNumber,
                  studentName: studentName,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _downloadStudentReportPdf({
    required String rollNumber,
    required String studentName,
  }) async {
    if (_instituteId == null) return;
    setState(() => _isLoading = true);
    try {
      final pdfBytes = await PdfExportService.generateStudentReport(
        instituteId: _instituteId!,
        rollNumber: rollNumber,
        startDate: _selectedStartDate,
        endDate: _selectedEndDate,
      );
      final from = DateFormat('yyyyMMdd').format(_selectedStartDate);
      final to = DateFormat('yyyyMMdd').format(_selectedEndDate);
      final safeName = studentName.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final fileName = 'attendance_${safeName}_${rollNumber}_${from}_$to.pdf';
      await Printing.sharePdf(bytes: pdfBytes, filename: fileName);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('PDF ready. Select Files in share sheet to save.'),
          backgroundColor: AppTheme.primaryGreen,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final errorResult = ErrorHandler.formatErrorForUI(
        e,
        context: 'downloadStudentPDF',
        appType: 'admin',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorResult['message']),
          backgroundColor: AppTheme.accentRed,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildSummaryCards() {
    final totalPresent = _reportData['totalPresent'] as int? ?? 0;
    final totalRecords = _reportData['totalRecords'] as int? ?? 0;
    final averageAttendance = _reportData['averageAttendance'] as double? ?? 0.0;
    final totalSeatedSeconds = _reportData['totalSeatedSeconds'] as int? ?? 0;
    final holidayReasons = _reportData['holidayReasons'] as Map<String, String>? ?? {};
    final totalSeatedLabel = totalSeatedSeconds > 0
        ? formatSeatedDurationHuman(Duration(seconds: totalSeatedSeconds))
        : '—';

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _SummaryCard(
                title: 'Total Present',
                value: '$totalPresent',
                color: AppTheme.accentGreen,
                icon: Icons.check_circle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SummaryCard(
                title: 'Total Records',
                value: '$totalRecords',
                color: AppTheme.primaryGreen,
                icon: Icons.people,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _SummaryCard(
                title: 'Avg Attendance',
                value: '${averageAttendance.toStringAsFixed(1)}%',
                color: AppTheme.accentOrange,
                icon: Icons.trending_up,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SummaryCard(
                title: 'Holidays',
                value: '${holidayReasons.length}',
                color: AppTheme.primaryBlue,
                icon: Icons.beach_access,
              ),
            ),
          ],
        ),
        if (totalSeatedSeconds > 0) ...[
          const SizedBox(height: 12),
          _SummaryCard(
            title: 'Total seated (sum)',
            value: totalSeatedLabel,
            color: AppTheme.primaryBlue,
            icon: Icons.schedule,
          ),
        ],
      ],
    );
  }

  Widget _buildDailyAttendanceChart() {
    final dailyPresent = _reportData['dailyPresent'] as Map<String, int>? ?? {};
    final dailyTotal = _reportData['dailyTotal'] as Map<String, int>? ?? {};
    final dailySeatedSeconds =
        _reportData['dailySeatedSeconds'] as Map<String, int>? ?? {};
    final holidayReasons = _reportData['holidayReasons'] as Map<String, String>? ?? {};

    if (dailyPresent.isEmpty && holidayReasons.isEmpty) {
      return const SizedBox.shrink();
    }

    final sortedDates = {...dailyPresent.keys, ...holidayReasons.keys}.toList()..sort();

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(20),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Daily Attendance',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          ...sortedDates.map((date) {
            final holidayReason = holidayReasons[date];
            if (holidayReason != null) {
              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.accentOrange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.accentOrange.withValues(alpha: 0.35)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.beach_access, color: AppTheme.accentOrange),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            DateFormat('MMM dd, yyyy').format(DateTime.parse(date)),
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Holiday: $holidayReason',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: AppTheme.accentOrange,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }
            final present = dailyPresent[date] ?? 0;
            final total = dailyTotal[date] ?? 1;
            final percentage = (present / total * 100);
            final seatedSec = dailySeatedSeconds[date] ?? 0;
            final seatedLabel = seatedSec > 0
                ? formatSeatedDurationHuman(Duration(seconds: seatedSec))
                : null;

            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        DateFormat('MMM dd, yyyy').format(DateTime.parse(date)),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '$present / $total (${percentage.toStringAsFixed(1)}%)',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.textGray,
                        ),
                      ),
                    ],
                  ),
                  if (seatedLabel != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Total seated that day: $seatedLabel',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.primaryBlue,
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: percentage / 100,
                      minHeight: 8,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        percentage >= 80 ? AppTheme.accentGreen :
                        percentage >= 60 ? AppTheme.accentOrange :
                        AppTheme.accentRed,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildTopStudents() {
    final studentAttendanceCount = _reportData['studentAttendanceCount'] as Map<String, int>? ?? {};
    final studentSeatedSeconds =
        _reportData['studentSeatedSeconds'] as Map<String, int>? ?? {};
    final rollByStudentId = _reportData['rollByStudentId'] as Map<String, String>? ?? {};

    if (studentAttendanceCount.isEmpty) {
      return const SizedBox.shrink();
    }

    final sortedStudents = studentAttendanceCount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final topStudents = sortedStudents.take(10).toList();

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(20),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Top Students by Attendance',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          ...topStudents.asMap().entries.map((entry) {
            final index = entry.key;
            final student = entry.value;
            final seatedSec = studentSeatedSeconds[student.key] ?? 0;
            final seatedLine = seatedSec <= 0
                ? 'Total seated: —'
                : 'Total seated: ${formatSeatedDurationHuman(Duration(seconds: seatedSec))}';
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.backgroundLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: index < 3
                          ? AppTheme.primaryGreen.withValues(alpha: 0.2)
                          : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: index < 3 ? AppTheme.primaryGreen : AppTheme.textGray,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SR No ${rollByStudentId[student.key] ?? student.key}',
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          seatedLine,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppTheme.primaryBlue,
                              ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.accentGreen.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${student.value} days',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.accentGreen,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final Color color;
  final IconData icon;

  const _SummaryCard({
    required this.title,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      padding: const EdgeInsets.all(16),
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
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white70 : AppTheme.textGray,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
