import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import '../../services/batch_service.dart';
import '../../services/semester_service.dart';
import '../../services/subject_service.dart';
import '../../core/app_db.dart';
import '../../core/theme/app_theme.dart';
import 'help_desk_screen.dart';

class BatchManagementScreen extends StatefulWidget {
  static const routeName = '/batch-management';
  const BatchManagementScreen({super.key});

  @override
  State<BatchManagementScreen> createState() => _BatchManagementScreenState();
}

class _BatchManagementScreenState extends State<BatchManagementScreen> with TickerProviderStateMixin {
  final BatchService _batchService = BatchService();
  String? _instituteId;
  bool _isLoading = true;
  List<Map<String, dynamic>> _batches = [];
  
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
    _loadInstituteId();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _loadInstituteId() async {
    try {
      final user = appDb.auth.currentUser;
      if (user == null) {
        setState(() => _isLoading = false);
        return;
      }

      try {
        final row = await appDb.from('profiles').select('institute_id').eq('id', user.id).maybeSingle();
        final instId = row?['institute_id'] as String?;
        if (instId != null && instId.isNotEmpty) {
          setState(() {
            _instituteId = instId;
            _isLoading = false;
          });
          await _loadBatches();
          return;
        }
      } catch (e) {
        if (kDebugMode) debugPrint('Error getting institute ID: $e');
      }

      setState(() => _isLoading = false);
    } catch (e) {
      if (kDebugMode) debugPrint('Institute load error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadBatches() async {
    if (_instituteId == null) return;

    setState(() => _isLoading = true);
    try {
      _batches = await _batchService.getBatches(_instituteId!);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Error loading batches'),
            backgroundColor: AppTheme.accentRed,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        );
      }
    }
    setState(() => _isLoading = false);
  }


  void _showAddBatchDialog() {
    if (_instituteId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Institute not found'),
          backgroundColor: AppTheme.accentRed,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      );
      return;
    }

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (dialogContext) => _CreateBatchDialog(
        instituteId: _instituteId!,
        onBatchCreated: (result) {
          _loadBatches();
          // Show success message from parent context
          if (result['success'] == true) {
            final batchDuration = result['batchDuration'] ?? 60;
            final isLateAdmission = result['isLateAdmission'] ?? false;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.white, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Batches Created Successfully!',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            '${result['count']} batches created (${batchDuration} minutes each${isLateAdmission ? " - Late Admission" : ""})',
                            style: const TextStyle(fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                backgroundColor: AppTheme.accentGreen,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                duration: const Duration(seconds: 4),
              ),
            );
          }
        },
      ),
    );
  }

  void _showEditBatchDialog(Map<String, dynamic> batch) {
    if (_instituteId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Institute not found'),
          backgroundColor: AppTheme.accentRed,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      );
      return;
    }

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (context) => _EditBatchDialog(
        instituteId: _instituteId!,
        batch: batch,
        onBatchUpdated: () {
          _loadBatches();
          Navigator.pop(context);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: Navigator.of(context).canPop(),
      onPopInvokedWithResult: (didPop, result) {
        // Pop already happened if didPop is true, no action needed
        // If didPop is false, pop was prevented (no previous route), also no action needed
      },
      child: Scaffold(
        backgroundColor: AppTheme.backgroundGrey,
        body: SafeArea(
          top: false,
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Column(
              children: [
                Expanded(
                  child: _isLoading
                      ? const Center(
                          child: CircularProgressIndicator(color: AppTheme.primaryBlue),
                        )
                      : _instituteId == null
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: _buildGlassCard(
                                  child: const Text(
                                    'Institute not found',
                                    style: TextStyle(
                                      color: AppTheme.textDark,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            )
                          : _batches.isEmpty
                              ? Center(
                                  child: SingleChildScrollView(
                                    padding: const EdgeInsets.all(20),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        _buildGlassCard(
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.groups_rounded,
                                                  size: 56, color: AppTheme.primaryBlue.withValues(alpha: 0.85)),
                                              const SizedBox(height: 16),
                                              Text(
                                                'No batches created yet',
                                                style: const TextStyle(
                                                  color: AppTheme.textDark,
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                                textAlign: TextAlign.center,
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                'Create batches with institute timing',
                                                style: TextStyle(
                                                  color: AppTheme.textGray,
                                                  fontSize: 14,
                                                ),
                                                textAlign: TextAlign.center,
                                              ),
                                              const SizedBox(height: 24),
                                              ElevatedButton.icon(
                                                onPressed: _showAddBatchDialog,
                                                icon: const Icon(Icons.add, color: Colors.white),
                                                label: const Text(
                                                  'Create Batches',
                                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                                ),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: AppTheme.primaryBlue,
                                                  foregroundColor: Colors.white,
                                                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius: BorderRadius.circular(12),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              : RefreshIndicator(
                                  onRefresh: _loadBatches,
                                  color: AppTheme.primaryBlue,
                                  child: ListView.builder(
                                    padding: const EdgeInsets.all(20),
                                    itemCount: _batches.length,
                                    itemBuilder: (context, index) {
                                      final batch = _batches[index];
                                      return Padding(
                                        padding: const EdgeInsets.only(bottom: 16),
                                        child: _buildBatchCard(batch),
                                      );
                                    },
                                  ),
                                ),
                ),
              ],
            ),
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          heroTag: 'batch_management_create_fab',
          onPressed: _isLoading ? null : _showAddBatchDialog,
          backgroundColor: AppTheme.primaryBlue,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.add),
          label: const Text('Create Batches', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  Widget _buildBatchCard(Map<String, dynamic> batch) {
    final batchId = batch['id'] as String?;
    return _buildGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  batch['name'] ?? 'Unknown',
                  style: const TextStyle(
                    color: AppTheme.textDark,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit, color: AppTheme.primaryBlue),
                onPressed: () => _showEditBatchDialog(batch),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.calendar_today, size: 16, color: AppTheme.textGray),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Year: ${batch['year'] ?? 'N/A'}',
                  style: const TextStyle(color: AppTheme.textGray, fontSize: 14),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.access_time, size: 16, color: AppTheme.textGray),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Timing: ${batch['timing'] ?? 'N/A'}',
                  style: const TextStyle(color: AppTheme.textGray, fontSize: 14),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Subject count display
          FutureBuilder<int>(
            future: _getBatchSubjectCount(batchId),
            builder: (context, snapshot) {
              final subjectCount = snapshot.data ?? 0;
              return Row(
                children: [
                  Icon(Icons.book, size: 16, color: AppTheme.textGray),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      '$subjectCount subject${subjectCount != 1 ? 's' : ''}',
                      style: TextStyle(
                        color: subjectCount == 0
                            ? AppTheme.accentOrange
                            : AppTheme.textGray,
                        fontSize: 14,
                        fontWeight: subjectCount == 0 ? FontWeight.w600 : FontWeight.normal,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (subjectCount == 0) ...[
                    const SizedBox(width: 8),
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 16,
                      color: AppTheme.accentOrange,
                    ),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          // Students section
          if (batchId != null) ...[
            Text(
              'Students',
              style: TextStyle(
                color: AppTheme.primaryBlue,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _loadStudentsInBatch(batchId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: CircularProgressIndicator(color: AppTheme.primaryBlue),
                    ),
                  );
                }
                
                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      'Error loading students: ${snapshot.error}',
                      style: TextStyle(color: Colors.red.shade300, fontSize: 12),
                    ),
                  );
                }
                
                final students = snapshot.data ?? [];
                
                if (students.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      'No students in this batch',
                      style: TextStyle(color: AppTheme.textLightGray, fontSize: 12),
                    ),
                  );
                }
                
                return Column(
                  children: students.map((student) {
                    final studentName = student['name'] ?? 'Unknown';
                    final studentSubjects = List<String>.from(student['subjects'] ?? []);
                    final studentId = student['id'] ?? '';
                    
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.backgroundGrey,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.dividerColor),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  studentName,
                                  style: const TextStyle(
                                    color: AppTheme.textDark,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.edit, color: AppTheme.primaryBlue, size: 18),
                                onPressed: () => _showEditStudentSubjectsDialog(studentId, studentName, studentSubjects, batchId),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                            ],
                          ),
                          if (studentSubjects.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: studentSubjects.map((subject) {
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryBlue.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: AppTheme.primaryBlue.withValues(alpha: 0.25)),
                                  ),
                                  child: Text(
                                    subject,
                                    style: const TextStyle(color: AppTheme.primaryBlue, fontSize: 11),
                                  ),
                                );
                              }).toList(),
                            ),
                          ] else ...[
                            const SizedBox(height: 4),
                            Text(
                              'No subjects assigned',
                              style: TextStyle(color: AppTheme.textLightGray, fontSize: 11),
                            ),
                          ],
                        ],
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
  
  Future<List<Map<String, dynamic>>> _loadStudentsInBatch(String batchId) async {
    if (_instituteId == null) return [];

    try {
      final rows = await appDb
          .from('students')
          .select('id,name,subjects')
          .eq('institute_id', _instituteId!)
          .eq('batch_id', batchId);

      return rows.map((raw) {
        final data = raw as Map<String, dynamic>;
        return {
          'id': data['id'] as String,
          'name': data['name'] ?? 'Unknown',
          'subjects': List<String>.from(data['subjects'] ?? []),
        };
      }).toList();
    } catch (e) {
      if (kDebugMode) debugPrint('Error loading students: $e');
      return [];
    }
  }

  /// Get total subject count for a batch (counts unique subjects from all students)
  Future<int> _getBatchSubjectCount(String? batchId) async {
    if (batchId == null || _instituteId == null) return 0;

    try {
      final rows = await appDb.from('students').select('subjects').eq('institute_id', _instituteId!).eq('batch_id', batchId);

      final allSubjects = <String>{};
      for (final raw in rows) {
        final data = raw as Map<String, dynamic>;
        final studentSubjects = List<String>.from(data['subjects'] ?? []);
        allSubjects.addAll(studentSubjects);
      }

      return allSubjects.length;
    } catch (e) {
      if (kDebugMode) debugPrint('Error counting batch subjects: $e');
      return 0;
    }
  }
  
  Future<void> _showEditStudentSubjectsDialog(String studentId, String studentName, List<String> currentSubjects, String batchId) async {
    if (_instituteId == null) return;
    
    // Load available subjects
    final SubjectService subjectService = SubjectService();
    List<String> availableSubjects = [];
    try {
      final subjects = await subjectService.getSubjects(_instituteId!);
      availableSubjects = subjects.map((s) => s['name'] as String).toList();
    } catch (e) {
      if (kDebugMode) debugPrint('Error loading subjects: $e');
    }
    
    List<String> selectedSubjects = List.from(currentSubjects);
    
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Edit Subjects for $studentName'),
          content: SizedBox(
            width: double.maxFinite,
            child: availableSubjects.isEmpty
                ? const Text('No subjects available. Please add subjects first.')
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: availableSubjects.length,
                    itemBuilder: (context, index) {
                      final subject = availableSubjects[index];
                      final isSelected = selectedSubjects.contains(subject);
                      
                      return CheckboxListTile(
                        title: Text(subject),
                        value: isSelected,
                        onChanged: (value) {
                          setDialogState(() {
                            if (value == true) {
                              if (!selectedSubjects.contains(subject)) {
                                selectedSubjects.add(subject);
                              }
                            } else {
                              selectedSubjects.remove(subject);
                            }
                          });
                        },
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                try {
                  await appDb.from('students').update({'subjects': selectedSubjects}).eq('id', studentId).eq('institute_id', _instituteId!);
                  
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Subjects updated for $studentName'),
                        backgroundColor: AppTheme.accentGreen,
                      ),
                    );
                    Navigator.pop(context);
                    setState(() {}); // Refresh batch cards
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error updating subjects: $e'),
                        backgroundColor: AppTheme.accentRed,
                      ),
                    );
                  }
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGlassCard({required Widget child}) {
    return GovElevatedCard(
      padding: const EdgeInsets.all(20),
      child: child,
    );
  }
}

class _CreateBatchDialog extends StatefulWidget {
  final String instituteId;
  final Function(Map<String, dynamic>)? onBatchCreated;

  const _CreateBatchDialog({
    required this.instituteId,
    required this.onBatchCreated,
  });

  @override
  State<_CreateBatchDialog> createState() => _CreateBatchDialogState();
}

class _CreateBatchDialogState extends State<_CreateBatchDialog> with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final BatchService _batchService = BatchService();
  final SubjectService _subjectService = SubjectService();
  final SemesterService _semesterService = SemesterService();
  
  List<String> _availableSubjects = [];
  List<Map<String, dynamic>> _availableSemesters = [];
  String? _selectedSemesterCode; // Use semester code (e.g., "1-2026") instead of just semester number
  int? _selectedSemester;
  int? _selectedYear;
  bool _isLoading = false;
  bool _isLoadingSubjects = false;
  bool _isLateAdmission = false; // Toggle for 120-minute batches
  TimeOfDay _openTime = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _closeTime = const TimeOfDay(hour: 20, minute: 0);
  
  // Batch calculation and per-batch subjects
  List<Map<String, dynamic>> _calculatedBatches = []; // List of batches with timing info
  Map<int, List<String>> _batchSubjects = {}; // Map<batchNumber, List<subjects>>
  
  // Batch name prefix controller
  final TextEditingController _batchNamePrefixController = TextEditingController();
  
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOut),
    );
    _fadeController.forward();
    _loadData();
    // Calculate batches after a short delay to ensure times are set
    Future.delayed(const Duration(milliseconds: 100), () {
      _calculateBatches();
    });
  }

  Future<void> _loadData() async {
    // Load semesters and year
    final currentYear = _semesterService.getCurrentYear();
    final semesters = _semesterService.getSemestersForSelection();
    final currentSemester = _semesterService.getCurrentSemester();
    
    setState(() {
      _availableSemesters = semesters;
      
      if (_availableSemesters.isNotEmpty) {
        try {
          // Find current semester and auto-select it with its year
          final matchingSem = _availableSemesters.firstWhere(
            (sem) => (sem['semester'] as int) == currentSemester && 
                     (sem['year'] as int) == currentYear,
          );
          _selectedSemester = matchingSem['semester'] as int;
          _selectedYear = matchingSem['year'] as int;
          _selectedSemesterCode = matchingSem['code'] as String;
        } catch (e) {
          // Fallback: select first available semester
          final firstSem = _availableSemesters.first;
          _selectedSemester = firstSem['semester'] as int;
          _selectedYear = firstSem['year'] as int;
          _selectedSemesterCode = firstSem['code'] as String;
        }
      } else {
        _selectedSemester = currentSemester;
        _selectedYear = currentYear;
        _selectedSemesterCode = _semesterService.getSemesterCode(currentSemester, currentYear);
      }
    });
    
    // Load subjects
    _loadSubjects();
  }

  @override
  void dispose() {
    _batchNamePrefixController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _loadSubjects() async {
    setState(() => _isLoadingSubjects = true);
    try {
      // Get predefined subjects from service and ensure no duplicates
      _availableSubjects = _subjectService.getPredefinedSubjects().toSet().toList();
      
      // Also load from Supabase to ensure they're initialized
      final subjects = await _subjectService.getSubjects(widget.instituteId);
      if (subjects.isEmpty) {
        // Initialize default subjects if they don't exist
        await _subjectService.initializeDefaultSubjects(widget.instituteId);
        _availableSubjects = _subjectService.getPredefinedSubjects().toSet().toList();
      } else {
        // Use predefined subjects only
        _availableSubjects = _subjectService.getPredefinedSubjects().toSet().toList();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error loading subjects: $e');
      // Fallback to predefined list
      _availableSubjects = _subjectService.getPredefinedSubjects().toSet().toList();
    }
    setState(() => _isLoadingSubjects = false);
  }

  /// Calculate batches based on institute timing
  void _calculateBatches() {
    final batchDuration = _isLateAdmission ? 120 : 60;
    final openMinutes = _openTime.hour * 60 + _openTime.minute;
    final closeMinutes = _closeTime.hour * 60 + _closeTime.minute;
    
    if (openMinutes >= closeMinutes) {
      setState(() {
        _calculatedBatches = [];
        _batchSubjects = {};
      });
      return;
    }
    
    final batches = <Map<String, dynamic>>[];
    int currentMinutes = openMinutes;
    int batchNumber = 1;
    
    while (currentMinutes < closeMinutes) {
      final startTime = TimeOfDay(
        hour: currentMinutes ~/ 60,
        minute: currentMinutes % 60,
      );
      
      final endMinutes = currentMinutes + batchDuration;
      final endTime = TimeOfDay(
        hour: endMinutes ~/ 60,
        minute: endMinutes % 60,
      );
      
      // Format timing string (e.g., "08:00 - 09:00")
      final timingString =
          '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')} - '
          '${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}';
      
      batches.add({
        'batchNumber': batchNumber,
        'timing': timingString,
        'startTime': startTime,
        'endTime': endTime,
        'batchDurationMinutes': batchDuration,
      });
      
      currentMinutes += batchDuration;
      batchNumber++;
    }
    
    setState(() {
      _calculatedBatches = batches;
      // Initialize empty subjects list for each batch
      _batchSubjects = {
        for (var batch in batches) batch['batchNumber'] as int: <String>[],
      };
    });
  }
  
  /// Create batches (subject lists on batches are filled when adding students).
  Future<Map<String, dynamic>> _createBatchesWithIndividualSubjects() async {
    try {
      if (_selectedSemester == null || _selectedYear == null) {
        return {'success': false, 'message': 'Semester and year are required'};
      }
      
      final batchDuration = _isLateAdmission ? 120 : 60;
      int createdCount = 0;

      for (var batchData in _calculatedBatches) {
        final batchNumber = batchData['batchNumber'] as int;

        try {
          final existing = await appDb
              .from('batches')
              .select('id')
              .eq('institute_id', widget.instituteId)
              .eq('year', _selectedYear.toString())
              .eq('timing', batchData['timing'] as String);

          if (existing.isEmpty) {
            final startTime = batchData['startTime'] as TimeOfDay;
            final endTime = batchData['endTime'] as TimeOfDay;
            final batchNamePrefix = _batchNamePrefixController.text.trim();
            final batchName = batchNamePrefix.isNotEmpty
                ? '$batchNamePrefix - Batch $batchNumber (${batchData['timing']})${_isLateAdmission ? " - Late Admission" : ""}'
                : 'Batch $batchNumber (${batchData['timing']})${_isLateAdmission ? " - Late Admission" : ""}';

            await appDb.from('batches').insert({
              'institute_id': widget.instituteId,
              'name': batchName,
              'year': _selectedYear.toString(),
              'semester': _selectedSemester.toString(),
              'timing': batchData['timing'] as String,
              'start_time': {'hour': startTime.hour, 'minute': startTime.minute},
              'end_time': {'hour': endTime.hour, 'minute': endTime.minute},
              'batch_duration_minutes': batchDuration,
              'subjects': <String>[],
              'created_by': 'system',
              'student_count': 0,
              'is_auto_generated': true,
              'created_at': DateTime.now().toUtc().toIso8601String(),
            });
            createdCount++;
          }
        } catch (e) {
          if (kDebugMode) debugPrint('Error creating batch $batchNumber: $e');
        }
      }

      if (createdCount > 0) {
        try {
          await appDb.from('institutes').update({
            'batch_open_time': {'hour': _openTime.hour, 'minute': _openTime.minute},
            'batch_close_time': {'hour': _closeTime.hour, 'minute': _closeTime.minute},
            'batch_duration_minutes': batchDuration,
            'batch_timing_updated_at': DateTime.now().toUtc().toIso8601String(),
          }).eq('id', widget.instituteId);
        } catch (e) {
          if (kDebugMode) debugPrint('⚠️ Could not save institute timing: $e');
        }
      }
      
      return {
        'success': true,
        'message': 'Batches created successfully',
        'count': createdCount,
        'totalSlots': _calculatedBatches.length,
      };
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error creating batches: $e');
      return {
        'success': false,
        'message': 'Error creating batches: ${e.toString()}',
      };
    }
  }

  /// Get professional error message based on error type
  String _getProfessionalErrorMessage(String error) {
    final errorLower = error.toLowerCase();
    
    if (errorLower.contains('permission') || errorLower.contains('denied')) {
      return 'You don\'t have permission to create batches. Please contact your administrator.';
    } else if (errorLower.contains('network') || errorLower.contains('connection') || errorLower.contains('internet')) {
      return 'Network connection error. Please check your internet connection and try again.';
    } else if (errorLower.contains('timeout')) {
      return 'Request timed out. Please check your connection and try again.';
    } else if (errorLower.contains('index') || errorLower.contains('firestore')) {
      return 'Database configuration required. Please contact technical support for assistance.';
    } else if (errorLower.contains('invalid') || errorLower.contains('validation')) {
      return 'Invalid input detected. Please check your selections and try again.';
    } else {
      return 'An unexpected error occurred. Please try again or contact support if the problem persists.';
    }
  }

  Future<void> _createBatch() async {
    if (_selectedSemester == null || _selectedYear == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.info_outline, color: Colors.white, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Selection Required',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const Text(
                      'Please select a semester to continue. The year will be automatically set based on your selection.',
                      style: TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ),
            ],
          ),
          backgroundColor: AppTheme.accentOrange,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    if (_calculatedBatches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.info_outline, color: Colors.white, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Invalid Timing',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const Text(
                      'Please set valid institute open and close times to calculate batches.',
                      style: TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ),
            ],
          ),
          backgroundColor: AppTheme.accentOrange,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }
    

    setState(() => _isLoading = true);

    // Create batches with individual subjects
    final result = await _createBatchesWithIndividualSubjects();

    setState(() => _isLoading = false);

    if (!mounted) return;

    if (result['success']) {
      final created = result['count'] as int? ?? 0;
      if (created == 0) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'No new batches were added — these time slots already exist for this semester. '
              'Change open/close times or semester, or edit existing batches.',
            ),
            backgroundColor: AppTheme.accentOrange,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            duration: const Duration(seconds: 5),
          ),
        );
        return;
      }

      Navigator.pop(context);

      if (mounted) {
        Future.delayed(const Duration(milliseconds: 300), () {
          widget.onBatchCreated?.call({
            ...result,
            'batchDuration': _isLateAdmission ? 120 : 60,
            'isLateAdmission': _isLateAdmission,
          });
        });
      }
    } else {
      // Show professional error message
      final errorMessage = _getProfessionalErrorMessage(result['message'] ?? 'Unknown error occurred');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Unable to Create Batches',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      errorMessage,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ),
            ],
          ),
          backgroundColor: AppTheme.accentRed,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'Help',
            textColor: Colors.white,
            onPressed: () {
              Navigator.pushNamed(context, HelpDeskScreen.routeName);
            },
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppTheme.primaryBlue,
                AppTheme.primaryBlueDark,
                AppTheme.primaryBlueLight,
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 30,
                spreadRadius: 10,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Header
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.add_circle_rounded, color: Colors.white, size: 24),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Create Batches',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    _isLateAdmission 
                                      ? 'Auto-generate 120-minute batches (Late Admission)'
                                      : 'Auto-generate 60-minute batches',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.white),
                              onPressed: () => Navigator.pop(context),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        
                        // Instructions Card
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.info_outline, color: Colors.white.withValues(alpha: 0.9), size: 20),
                                  const SizedBox(width: 8),
                                  Text(
                                    'How to Create Batches',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '1. Set your institute open and close times\n'
                                '2. Select semester (year auto-updates)\n'
                                '3. Toggle "Late Admission" for 120-minute batches (optional)\n'
                                '4. Tap "Create Batches" — time slots are saved; you assign subjects when adding students',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.8),
                                  fontSize: 12,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        
                        // Batch Name Prefix (Optional)
                        _buildModernTextField(
                          controller: _batchNamePrefixController,
                          icon: Icons.label_outline,
                          label: 'Batch Name Prefix (Optional)',
                          hint: 'e.g., Computer Science, Engineering, etc.',
                          validator: null, // Optional field
                        ),
                        const SizedBox(height: 16),
                        
                        // Institute Timing
                        Row(
                          children: [
                            Text(
                              'Institute Timing',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.9),
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Tooltip(
                              message: 'Set the hours your institute operates. Batches will be created automatically for these hours.',
                              child: Icon(
                                Icons.help_outline,
                                color: Colors.white.withValues(alpha: 0.7),
                                size: 18,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _buildTimePicker(
                                label: 'Open Time',
                                time: _openTime,
                                onTimeSelected: (time) {
                                  setState(() {
                                    _openTime = time;
                                  });
                                  _calculateBatches();
                                },
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _buildTimePicker(
                                label: 'Close Time',
                                time: _closeTime,
                                onTimeSelected: (time) {
                                  setState(() {
                                    _closeTime = time;
                                  });
                                  _calculateBatches();
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        
                        // Semester Selection
                        Row(
                          children: [
                            Text(
                              'Semester',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.9),
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Tooltip(
                              message: 'Select semester. Year will automatically update based on your selection.',
                              child: Icon(
                                Icons.help_outline,
                                color: Colors.white.withValues(alpha: 0.7),
                                size: 18,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                          ),
                          child: DropdownButtonFormField<String>(
                            value: _selectedSemesterCode != null && 
                                   _availableSemesters.isNotEmpty &&
                                   _availableSemesters.any((sem) => (sem['code'] as String) == _selectedSemesterCode)
                                ? _selectedSemesterCode
                                : null,
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: Colors.white.withValues(alpha: 0.2),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                              ),
                              prefixIcon: const Icon(Icons.calendar_today_rounded, color: Colors.white),
                              hintText: _availableSemesters.isEmpty ? 'Loading semesters...' : 'Select Semester',
                              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                            ),
                            dropdownColor: AppTheme.primaryBlueDark,
                            style: const TextStyle(color: Colors.white),
                            items: _availableSemesters.map((sem) {
                              return DropdownMenuItem<String>(
                                value: sem['code'] as String,
                                child: Text(sem['name'] as String),
                              );
                            }).toList(),
                            onChanged: _availableSemesters.isEmpty 
                                ? null 
                                : (value) {
                                  if (value != null) {
                                    // Find the selected semester to get its year and semester number
                                    final selectedSemData = _availableSemesters.firstWhere(
                                      (sem) => (sem['code'] as String) == value,
                                    );
                                    setState(() {
                                      _selectedSemesterCode = value;
                                      _selectedSemester = selectedSemData['semester'] as int;
                                      _selectedYear = selectedSemData['year'] as int;
                                    });
                                  }
                                },
                          ),
                        ),
                        const SizedBox(height: 24),
                        
                        // Year Display (Auto-selected from semester)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_today_rounded, color: Colors.white, size: 20),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _selectedYear != null 
                                    ? 'Year: $_selectedYear (Auto-selected from semester)'
                                    : 'Year: Loading...',
                                  style: const TextStyle(color: Colors.white, fontSize: 16),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        
                        // Late Admission Toggle
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  Icons.access_time,
                                  color: _isLateAdmission ? AppTheme.accentOrange : Colors.white,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Late Admission Batches',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _isLateAdmission 
                                        ? '120 minutes per batch (for late admission students)'
                                        : '60 minutes per batch (regular batches)',
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.7),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Switch(
                                value: _isLateAdmission,
                                onChanged: (value) {
                                  setState(() {
                                    _isLateAdmission = value;
                                  });
                                  _calculateBatches();
                                },
                                activeColor: AppTheme.accentOrange,
                                activeTrackColor: AppTheme.accentOrange.withValues(alpha: 0.5),
                                inactiveThumbColor: Colors.white,
                                inactiveTrackColor: Colors.white.withValues(alpha: 0.3),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        
                        // Batch Count Display
                        if (_calculatedBatches.isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppTheme.accentGreen.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppTheme.accentGreen.withValues(alpha: 0.5)),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.info_outline, color: AppTheme.accentGreen, size: 24),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    '${_calculatedBatches.length} batches will be created',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          
                          // Preview of batches that will be created
                          Text(
                            'Batch time slots',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 12),
                          
                          // Scrollable batch list
                          Container(
                            constraints: const BoxConstraints(maxHeight: 400),
                            child: ListView.builder(
                              shrinkWrap: true,
                              itemCount: _calculatedBatches.length,
                              itemBuilder: (context, index) {
                                final batchData = _calculatedBatches[index];
                                final batchNumber = batchData['batchNumber'] as int;
                                final timing = batchData['timing'] as String;
                                final batchSubjects = _batchSubjects[batchNumber] ?? [];
                                
                                return Container(
                                  key: ValueKey('batch_$batchNumber'),
                                  margin: const EdgeInsets.only(bottom: 16),
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: batchSubjects.isNotEmpty 
                                          ? AppTheme.accentGreen.withValues(alpha: 0.5)
                                          : Colors.white.withValues(alpha: 0.3),
                                      width: batchSubjects.isNotEmpty ? 2 : 1,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Batch Header
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: AppTheme.primaryBlueLight.withValues(alpha: 0.3),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              'Batch $batchNumber',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Flexible(
                                            flex: 2,
                                            child: Text(
                                              timing,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 14,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (batchSubjects.isNotEmpty) ...[
                                            const SizedBox(width: 8),
                                            Flexible(
                                              flex: 1,
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: AppTheme.accentGreen.withValues(alpha: 0.3),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  '${batchSubjects.length} subject${batchSubjects.length > 1 ? 's' : ''}',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      
                                      // Info message about subjects
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.info_outline,
                                              color: Colors.white.withValues(alpha: 0.8),
                                              size: 18,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                'Subjects will be assigned when adding students to this batch',
                                                style: TextStyle(
                                                  color: Colors.white.withValues(alpha: 0.9),
                                                  fontSize: 12,
                                                ),
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
                        ],
                        const SizedBox(height: 24),
                        
                        // Create Button
                        Container(
                          height: 56,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Colors.white, Color(0xFFF3F4F6)],
                            ),
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 12,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: ElevatedButton(
                            onPressed: (_isLoading ||
                                    _isLoadingSubjects ||
                                    _calculatedBatches.isEmpty)
                                ? null
                                : _createBatch,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    height: 24,
                                    width: 24,
                                    child: CircularProgressIndicator(
                                      color: AppTheme.primaryBlue,
                                      strokeWidth: 3,
                                    ),
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.check_circle_rounded, color: AppTheme.primaryBlue, size: 22),
                                      const SizedBox(width: 10),
                                      Flexible(
                                        child: Text(
                                          'Create Batches',
                                          style: const TextStyle(
                                            color: AppTheme.primaryBlue,
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 0.5,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                        ),
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
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModernTextField({
    required TextEditingController controller,
    required IconData icon,
    required String label,
    required String hint,
    String? Function(String?)? validator,
    void Function(String)? onFieldSubmitted,
  }) {
    return TextFormField(
      controller: controller,
      style: const TextStyle(color: Colors.white, fontSize: 15),
      onFieldSubmitted: onFieldSubmitted,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
        prefixIcon: Icon(icon, color: Colors.white.withValues(alpha: 0.8), size: 20),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.1),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.white, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFEF4444)),
        ),
        errorStyle: const TextStyle(color: Color(0xFFFFE5E5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      validator: validator,
    );
  }

  Widget _buildTimePicker({
    required String label,
    required TimeOfDay time,
    required Function(TimeOfDay) onTimeSelected,
  }) {
    return GestureDetector(
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: time,
          builder: (context, child) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            return Theme(
              data: Theme.of(context).copyWith(
                colorScheme: ColorScheme.light(
                  primary: AppTheme.primaryBlue,
                  onPrimary: Colors.white,
                  onSurface: isDark ? Colors.white : AppTheme.textDark,
                  surface: isDark ? const Color(0xFF1E293B) : Colors.white,
                ),
                dialogBackgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
              ),
              child: child!,
            );
          },
        );
        if (picked != null) {
          onTimeSelected(picked);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  time.format(context),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            Icon(
              Icons.access_time,
              color: Colors.white.withValues(alpha: 0.7),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _EditBatchDialog extends StatefulWidget {
  final String instituteId;
  final Map<String, dynamic> batch;
  final VoidCallback onBatchUpdated;

  const _EditBatchDialog({
    required this.instituteId,
    required this.batch,
    required this.onBatchUpdated,
  });

  @override
  State<_EditBatchDialog> createState() => _EditBatchDialogState();
}

class _EditBatchDialogState extends State<_EditBatchDialog> with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _yearController = TextEditingController();
  final BatchService _batchService = BatchService();
  final SubjectService _subjectService = SubjectService();
  
  List<String> _subjects = [];
  List<String> _availableSubjects = [];
  String? _selectedSubject;
  bool _isLoading = false;
  bool _isLoadingSubjects = false;
  TimeOfDay _startTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 17, minute: 0);
  
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    // Pre-fill with existing batch data
    _nameController.text = widget.batch['name'] ?? '';
    _yearController.text = widget.batch['year'] ?? '';
    _subjects = List<String>.from(widget.batch['subjects'] ?? []);
    
    // Parse timing from batch
    final timing = widget.batch['timing'] as String? ?? '';
    if (timing.isNotEmpty && timing.contains('-')) {
      try {
        final parts = timing.split('-');
        if (parts.length == 2) {
          final startParts = parts[0].trim().split(':');
          final endParts = parts[1].trim().split(':');
          if (startParts.length == 2 && endParts.length == 2) {
            _startTime = TimeOfDay(
              hour: int.parse(startParts[0]),
              minute: int.parse(startParts[1]),
            );
            _endTime = TimeOfDay(
              hour: int.parse(endParts[0]),
              minute: int.parse(endParts[1]),
            );
          }
        }
      } catch (e) {
        // Keep defaults
      }
    }
    
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOut),
    );
    _fadeController.forward();
    _loadSubjects();
  }

  Future<void> _loadSubjects() async {
    setState(() => _isLoadingSubjects = true);
    try {
      // Get predefined subjects from service and ensure no duplicates
      _availableSubjects = _subjectService.getPredefinedSubjects().toSet().toList();
      
      final subjects = await _subjectService.getSubjects(widget.instituteId);
      if (subjects.isEmpty) {
        await _subjectService.initializeDefaultSubjects(widget.instituteId);
        _availableSubjects = _subjectService.getPredefinedSubjects().toSet().toList();
      } else {
        _availableSubjects = _subjectService.getPredefinedSubjects().toSet().toList();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error loading subjects: $e');
      _availableSubjects = _subjectService.getPredefinedSubjects().toSet().toList();
    }
    setState(() => _isLoadingSubjects = false);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _yearController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  void _addSubject() {
    if (_selectedSubject != null && !_subjects.contains(_selectedSubject!)) {
      setState(() {
        _subjects.add(_selectedSubject!);
        _selectedSubject = null;
      });
    }
  }

  void _removeSubject(String subject) {
    setState(() {
      _subjects.remove(subject);
    });
  }

  Future<void> _updateBatch() async {
    if (!_formKey.currentState!.validate()) return;
    if (_subjects.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please add at least one subject'),
          backgroundColor: AppTheme.accentRed,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    // Format timing from time pickers
    final startHour = _startTime.hour.toString().padLeft(2, '0');
    final startMinute = _startTime.minute.toString().padLeft(2, '0');
    final endHour = _endTime.hour.toString().padLeft(2, '0');
    final endMinute = _endTime.minute.toString().padLeft(2, '0');
    final timing = '$startHour:$startMinute - $endHour:$endMinute';

    final result = await _batchService.updateBatch(
      instituteId: widget.instituteId,
      batchId: widget.batch['id'],
      batchName: _nameController.text.trim(),
      year: _yearController.text.trim(),
      timing: timing,
      subjects: _subjects,
    );

    setState(() => _isLoading = false);

    if (!mounted) return;

    if (result['success']) {
      widget.onBatchUpdated();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message']),
          backgroundColor: AppTheme.accentGreen,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message']),
          backgroundColor: AppTheme.accentRed,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppTheme.primaryBlue,
                AppTheme.primaryBlueDark,
                AppTheme.primaryBlueLight,
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 30,
                spreadRadius: 10,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Header
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.edit_rounded, color: Colors.white, size: 24),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'Edit Batch',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.white),
                              onPressed: () => Navigator.pop(context),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        
                        // Batch Name
                        _buildModernTextField(
                          controller: _nameController,
                          icon: Icons.groups_rounded,
                          label: 'Batch Name',
                          hint: 'e.g., Computer Science A',
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Batch name is required';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        
                        // Year
                        _buildModernTextField(
                          controller: _yearController,
                          icon: Icons.calendar_today_rounded,
                          label: 'Year',
                          hint: 'e.g., 2024, First Year, etc.',
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Year is required';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        
                        // Timing
                        Text(
                          'Timing',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _buildTimePicker(
                                label: 'Start Time',
                                time: _startTime,
                                onTimeSelected: (time) {
                                  setState(() {
                                    _startTime = time;
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _buildTimePicker(
                                label: 'End Time',
                                time: _endTime,
                                onTimeSelected: (time) {
                                  setState(() {
                                    _endTime = time;
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        
                        // Subjects Section
                        Text(
                          'Subjects (Predefined Only)',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        
                        // Subject Selection (Dropdown - Only Predefined Subjects)
                        if (_isLoadingSubjects)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.all(16.0),
                              child: CircularProgressIndicator(color: Colors.white),
                            ),
                          )
                        else
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                                  ),
                                  child: DropdownButtonFormField<String>(
                                    value: _selectedSubject != null && 
                                           _availableSubjects
                                               .where((subject) => !_subjects.contains(subject))
                                               .toSet()
                                               .toList()
                                               .contains(_selectedSubject)
                                        ? _selectedSubject
                                        : null,
                                    decoration: InputDecoration(
                                      prefixIcon: const Icon(Icons.book_rounded, color: Colors.white),
                                      labelText: 'Select Subject',
                                      labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                                      hintText: 'Choose a subject',
                                      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                                      border: InputBorder.none,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                                    ),
                                    dropdownColor: AppTheme.primaryBlueDark,
                                    style: const TextStyle(color: Colors.white, fontSize: 16),
                                    icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                                    items: _availableSubjects
                                        .where((subject) => !_subjects.contains(subject))
                                        .toSet() // Remove duplicates
                                        .toList()
                                        .map((subject) {
                                      return DropdownMenuItem<String>(
                                        value: subject,
                                        child: Text(
                                          subject,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      );
                                    }).toList(),
                                    onChanged: (value) {
                                      setState(() {
                                        _selectedSubject = value;
                                      });
                                    },
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                                ),
                                child: IconButton(
                                  icon: const Icon(Icons.add, color: Colors.white),
                                  onPressed: _selectedSubject != null ? _addSubject : null,
                                ),
                              ),
                            ],
                          ),
                        const SizedBox(height: 12),
                        
                        // Subjects List
                        if (_subjects.isNotEmpty) ...[
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _subjects.map((subject) {
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        subject,
                                        style: const TextStyle(color: Colors.white, fontSize: 14),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    GestureDetector(
                                      onTap: () => _removeSubject(subject),
                                      child: Icon(
                                        Icons.close,
                                        color: Colors.white.withValues(alpha: 0.8),
                                        size: 18,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 24),
                        ] else ...[
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                            ),
                            child: Text(
                              'No subjects added yet. Add at least one subject.',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.7),
                                fontSize: 14,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                        
                        // Update Button
                        Container(
                          height: 56,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Colors.white, Color(0xFFF3F4F6)],
                            ),
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 12,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _updateBatch,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    height: 24,
                                    width: 24,
                                    child: CircularProgressIndicator(
                                      color: AppTheme.primaryBlue,
                                      strokeWidth: 3,
                                    ),
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.save_rounded, color: AppTheme.primaryBlue, size: 22),
                                      const SizedBox(width: 10),
                                      Flexible(
                                        child: Text(
                                          'Update Batch',
                                          style: const TextStyle(
                                            color: AppTheme.primaryBlue,
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 0.5,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                        ),
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
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModernTextField({
    required TextEditingController controller,
    required IconData icon,
    required String label,
    required String hint,
    String? Function(String?)? validator,
    void Function(String)? onFieldSubmitted,
  }) {
    return TextFormField(
      controller: controller,
      style: const TextStyle(color: Colors.white, fontSize: 15),
      onFieldSubmitted: onFieldSubmitted,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
        prefixIcon: Icon(icon, color: Colors.white.withValues(alpha: 0.8), size: 20),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.1),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.white, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFEF4444)),
        ),
        errorStyle: const TextStyle(color: Color(0xFFFFE5E5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      validator: validator,
    );
  }

  Widget _buildTimePicker({
    required String label,
    required TimeOfDay time,
    required Function(TimeOfDay) onTimeSelected,
  }) {
    return GestureDetector(
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: time,
          builder: (context, child) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            return Theme(
              data: Theme.of(context).copyWith(
                colorScheme: ColorScheme.light(
                  primary: AppTheme.primaryBlue,
                  onPrimary: Colors.white,
                  onSurface: isDark ? Colors.white : AppTheme.textDark,
                  surface: isDark ? const Color(0xFF1E293B) : Colors.white,
                ),
                dialogBackgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
              ),
              child: child!,
            );
          },
        );
        if (picked != null) {
          onTimeSelected(picked);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  time.format(context),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            Icon(
              Icons.access_time,
              color: Colors.white.withValues(alpha: 0.7),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
