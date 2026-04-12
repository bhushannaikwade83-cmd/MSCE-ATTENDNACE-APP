import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../core/app_db.dart';
import '../../core/supabase_maps.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/responsive.dart';
import '../../services/error_handler.dart';
import '../../services/pdf_export_service.dart';

class AttendanceReportsScreen extends StatefulWidget {
  static const routeName = '/attendance-reports';
  const AttendanceReportsScreen({super.key});

  @override
  State<AttendanceReportsScreen> createState() => _AttendanceReportsScreenState();
}

class _AttendanceReportsScreenState extends State<AttendanceReportsScreen> {
  String? _instituteId;
  DateTime _selectedStartDate = DateTime.now().subtract(const Duration(days: 7));
  DateTime _selectedEndDate = DateTime.now();
  String? _selectedSubject;
  bool _isLoading = false;
  bool _isLoadingSubjects = false;
  Map<String, dynamic> _reportData = {};
  List<String> _subjects = ['All Subjects'];

  @override
  void initState() {
    super.initState();
    _loadInstituteId();
  }

  Future<void> _loadSubjects() async {
    if (_instituteId == null) return;
    
    setState(() => _isLoadingSubjects = true);
    
    try {
      final batchRows = await appDb.from('batches').select('subjects').eq('institute_id', _instituteId!);

      Set<String> subjectsSet = {'All Subjects'};

      for (final raw in batchRows) {
        final batchData = raw as Map<String, dynamic>;
        final subjects = batchData['subjects'] as List<dynamic>?;
        if (subjects != null) {
          for (var subject in subjects) {
            if (subject is String && subject.isNotEmpty) {
              subjectsSet.add(subject);
            }
          }
        }
      }

      final code = await instituteCodeForId(_instituteId!);
      final attendanceRows = await appDb.from('attendance_in_out').select('additional,semester_code').eq('institute_code', code).limit(100);

      for (final raw in attendanceRows) {
        final data = raw as Map<String, dynamic>;
        final add = data['additional'];
        String? subject;
        if (add is Map && add['subject'] != null) {
          subject = add['subject'].toString();
        } else {
          subject = data['semester_code'] as String?;
        }
        if (subject != null && subject.isNotEmpty) {
          subjectsSet.add(subject);
        }
      }
      
      setState(() {
        _subjects = subjectsSet.toList()..sort();
        _isLoadingSubjects = false;
      });
    } catch (e) {
      setState(() => _isLoadingSubjects = false);
      if (mounted) {
        final errorResult = ErrorHandler.formatErrorForUI(e, context: 'loadSubjects');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorResult['message']),
            backgroundColor: AppTheme.accentRed,
          ),
        );
      }
    }
  }

  Future<void> _loadInstituteId() async {
    try {
      final user = appDb.auth.currentUser;
      if (user == null) return;

      final row = await appDb.from('profiles').select('institute_id').eq('id', user.id).maybeSingle();
      final iid = row?['institute_id'] as String?;
      if (iid != null && iid.isNotEmpty) {
        setState(() {
          _instituteId = iid;
        });
        _loadSubjects();
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

  Future<void> _generateReport() async {
    if (_instituteId == null) return;

    // Validate date range (max 1 month)
    final daysDifference = _selectedEndDate.difference(_selectedStartDate).inDays;
    if (daysDifference > 31) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Date range cannot exceed 1 month (31 days). Please select a shorter range.'),
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

    setState(() => _isLoading = true);

    try {
      final startDateStr = DateFormat('yyyy-MM-dd').format(_selectedStartDate);
      final endDateStr = DateFormat('yyyy-MM-dd').format(_selectedEndDate);

      final code = await instituteCodeForId(_instituteId!);
      List<dynamic> rows = await appDb
          .from('attendance_in_out')
          .select()
          .eq('institute_code', code)
          .gte('attendance_date', startDateStr)
          .lte('attendance_date', endDateStr);

      if (_selectedSubject != null && _selectedSubject != 'All Subjects') {
        rows = rows.where((raw) {
          final data = raw as Map<String, dynamic>;
          final add = data['additional'];
          String sub = '';
          if (add is Map && add['subject'] != null) {
            sub = add['subject'].toString();
          } else {
            sub = data['semester_code']?.toString() ?? '';
          }
          return sub == _selectedSubject;
        }).toList();
      }

      Map<String, int> dailyPresent = {};
      Map<String, int> dailyTotal = {};
      Map<String, Set<String>> studentsByDate = {};
      Map<String, int> studentAttendanceCount = {};
      int totalPresent = 0;
      int totalRecords = 0;

      for (final raw in rows) {
        final data = raw as Map<String, dynamic>;
        final date = data['attendance_date']?.toString() ?? '';
        final add = data['additional'];
        final status = (add is Map ? add['status'] : null) as String? ?? 'present';
        final rollNumber = data['sr_no'] as String? ?? data['student_id'] as String? ?? '';

        if (date.isNotEmpty) {
          dailyTotal[date] = (dailyTotal[date] ?? 0) + 1;

          final isPresent = status == 'present';

          if (isPresent) {
            dailyPresent[date] = (dailyPresent[date] ?? 0) + 1;
            totalPresent++;

            if (!studentsByDate.containsKey(date)) {
              studentsByDate[date] = <String>{};
            }
            studentsByDate[date]!.add(rollNumber);

            studentAttendanceCount[rollNumber] = (studentAttendanceCount[rollNumber] ?? 0) + 1;
          }
          totalRecords++;
        }
      }

      setState(() {
        _reportData = {
          'dailyPresent': dailyPresent,
          'dailyTotal': dailyTotal,
          'studentsByDate': studentsByDate,
          'studentAttendanceCount': studentAttendanceCount,
          'totalPresent': totalPresent,
          'totalRecords': totalRecords,
          'averageAttendance': totalRecords > 0 ? (totalPresent / totalRecords * 100) : 0.0,
        };
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
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
            // Date Range Selection
            _buildDateRangeSelector(),
            const SizedBox(height: 20),

            // Subject Filter
            _buildSubjectFilter(),
            const SizedBox(height: 20),

            // Generate Report Button
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _generateReport,
              icon: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.analytics),
              label: Text(_isLoading ? 'Generating...' : 'Generate Report'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Summary Cards
            if (_reportData.isNotEmpty) ...[
              _buildSummaryCards(),
              const SizedBox(height: 24),

              // Export Buttons
              _buildExportButtons(),
              const SizedBox(height: 24),

              // Daily Attendance Chart
              _buildDailyAttendanceChart(),
              const SizedBox(height: 24),

              // Top Students
              _buildTopStudents(),
            ],

            if (_reportData.isEmpty && !_isLoading)
              Center(
                child: Column(
                  children: [
                    Icon(Icons.analytics_outlined, size: 64, color: AppTheme.textGray),
                    const SizedBox(height: 16),
                    Text(
                      'No data available',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: AppTheme.textGray,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Select date range and generate report',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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
      child: Column(
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
                    'Maximum date range: 1 month (31 days)',
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
                child: InkWell(
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: _selectedStartDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (date != null) {
                      // Validate max 1 month range
                      final daysDifference = _selectedEndDate.difference(date).inDays;
                      if (daysDifference > 31) {
                        // Adjust end date to be max 1 month from start
                        final newEndDate = date.add(const Duration(days: 31));
                        setState(() {
                          _selectedStartDate = date;
                          _selectedEndDate = newEndDate.isAfter(DateTime.now()) 
                              ? DateTime.now() 
                              : newEndDate;
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text('Date range limited to maximum 1 month'),
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
                    // Calculate max end date (1 month from start date or today, whichever is earlier)
                    final maxEndDate = _selectedStartDate.add(const Duration(days: 31));
                    final lastAllowedDate = maxEndDate.isAfter(DateTime.now()) 
                        ? DateTime.now() 
                        : maxEndDate;
                    
                    final date = await showDatePicker(
                      context: context,
                      initialDate: _selectedEndDate.isAfter(lastAllowedDate) 
                          ? lastAllowedDate 
                          : _selectedEndDate,
                      firstDate: _selectedStartDate, // Can't select before start date
                      lastDate: lastAllowedDate, // Max 1 month from start
                    );
                    if (date != null) {
                      // Validate max 1 month range
                      final daysDifference = date.difference(_selectedStartDate).inDays;
                      if (daysDifference > 31) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text('Date range cannot exceed 1 month (31 days)'),
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
    );
  }

  Widget _buildSubjectFilter() {
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
            'Subject Filter',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          _isLoadingSubjects
              ? const Center(child: CircularProgressIndicator())
              : DropdownButtonFormField<String>(
                  value: _selectedSubject,
                  decoration: const InputDecoration(
                    labelText: 'Subject',
                    prefixIcon: Icon(Icons.book_outlined),
                  ),
                  items: _subjects.map((subject) {
                    return DropdownMenuItem(
                      value: subject,
                      child: Text(subject),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() => _selectedSubject = value);
                  },
                ),
        ],
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No students found'),
          backgroundColor: AppTheme.accentOrange,
        ),
      );
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
                  subtitle: Text('Roll: ${student['rollNumber']}'),
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
                Text('Student PDF exported successfully!'),
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

  Widget _buildSummaryCards() {
    final totalPresent = _reportData['totalPresent'] as int? ?? 0;
    final totalRecords = _reportData['totalRecords'] as int? ?? 0;
    final averageAttendance = _reportData['averageAttendance'] as double? ?? 0.0;

    return Row(
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
        const SizedBox(width: 12),
        Expanded(
          child: _SummaryCard(
            title: 'Avg Attendance',
            value: '${averageAttendance.toStringAsFixed(1)}%',
            color: AppTheme.accentOrange,
            icon: Icons.trending_up,
          ),
        ),
      ],
    );
  }

  Widget _buildDailyAttendanceChart() {
    final dailyPresent = _reportData['dailyPresent'] as Map<String, int>? ?? {};
    final dailyTotal = _reportData['dailyTotal'] as Map<String, int>? ?? {};

    if (dailyPresent.isEmpty) {
      return const SizedBox.shrink();
    }

    final sortedDates = dailyPresent.keys.toList()..sort();

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
            final present = dailyPresent[date] ?? 0;
            final total = dailyTotal[date] ?? 1;
            final percentage = (present / total * 100);

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
                    child: Text(
                      'Roll ${student.key}',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
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
