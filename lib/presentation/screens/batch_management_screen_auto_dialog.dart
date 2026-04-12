import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'dart:ui';
import '../../services/batch_service.dart';
import '../../services/semester_service.dart';
import '../../services/subject_service.dart';
import '../../services/firestore_index_service.dart';
import '../../core/theme/app_theme.dart';
import 'package:url_launcher/url_launcher.dart';

class AutoGenerateBatchesDialog extends StatefulWidget {
  final String instituteId;
  final VoidCallback onBatchesGenerated;

  const AutoGenerateBatchesDialog({
    super.key,
    required this.instituteId,
    required this.onBatchesGenerated,
  });

  @override
  State<AutoGenerateBatchesDialog> createState() => _AutoGenerateBatchesDialogState();
}

class _AutoGenerateBatchesDialogState extends State<AutoGenerateBatchesDialog> {
  final BatchService _batchService = BatchService();
  final SemesterService _semesterService = SemesterService();
  final SubjectService _subjectService = SubjectService();
  
  TimeOfDay _openTime = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _closeTime = const TimeOfDay(hour: 22, minute: 0);
  int? _selectedSemester;
  int? _selectedYear;
  List<String> _selectedSubjects = [];
  List<Map<String, dynamic>> _availableSubjects = [];
  List<Map<String, dynamic>> _availableSemesters = [];
  bool _isLateAdmission = false; // Toggle for 120-minute batches (late admission)
  bool _isLoading = false;
  bool _isLoadingSubjects = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoadingSubjects = true);
    
    // Get current year and semesters
    final currentYear = _semesterService.getCurrentYear();
    _availableSemesters = _semesterService.getSemestersForSelection();
    _selectedYear = currentYear;
    
    // Set selected semester only if it exists in available semesters (fix dropdown error)
    final currentSemester = _semesterService.getCurrentSemester();
    if (_availableSemesters.isNotEmpty) {
      // Find matching semester in available list
      try {
        final matchingSem = _availableSemesters.firstWhere(
          (sem) => (sem['semester'] as int) == currentSemester,
        );
        _selectedSemester = matchingSem['semester'] as int;
      } catch (e) {
        // If not found, use first available
        _selectedSemester = _availableSemesters.first['semester'] as int?;
      }
    } else {
      _selectedSemester = currentSemester;
    }
    
    // Load subjects
    try {
      _availableSubjects = await _subjectService.getSubjects(widget.instituteId);
      
      // If no subjects, try to initialize defaults
      if (_availableSubjects.isEmpty) {
        try {
          await _subjectService.initializeDefaultSubjects(widget.instituteId);
          _availableSubjects = await _subjectService.getSubjects(widget.instituteId);
        } catch (initError) {
          // Handle permission errors gracefully
          if (initError.toString().contains('permission-denied')) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text(
                    '⚠️ Cannot access subjects. Please check Firestore permissions.',
                  ),
                  backgroundColor: Colors.orange,
                  duration: const Duration(seconds: 4),
                ),
              );
            }
          }
        }
      }
    } catch (e) {
      // Handle error gracefully - don't block the UI
      if (e.toString().contains('permission-denied')) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                '⚠️ Permission denied: Cannot access subjects. Please contact admin.',
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
      _availableSubjects = []; // Set empty list so UI doesn't break
    }
    
    setState(() => _isLoadingSubjects = false);
  }

  Future<void> _generateBatches() async {
    if (_selectedSemester == null || _selectedYear == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please select semester and year'),
          backgroundColor: AppTheme.accentRed,
        ),
      );
      return;
    }

    if (_selectedSubjects.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please select at least one subject'),
          backgroundColor: AppTheme.accentRed,
        ),
      );
      return;
    }

    // Step 1: Check if Firestore indexes are needed (first time only)
    final hasChecked = await FirestoreIndexService.hasCheckedIndexes();
    if (!hasChecked) {
      setState(() => _isLoading = true);
      
      final indexCheck = await FirestoreIndexService.checkIndexesNeeded(
        instituteId: widget.instituteId,
      );

      setState(() => _isLoading = false);

      if (indexCheck['needed'] == true) {
        // Show dialog to create indexes
        final shouldProceed = await _showIndexCreationDialog(indexCheck['indexUrl']);
        
        if (shouldProceed == false) {
          // User cancelled or needs to create index first
          return;
        }
      }

      // Mark that we've checked
      await FirestoreIndexService.markIndexesChecked();
    }

    // Step 2: Proceed with batch generation
    setState(() => _isLoading = true);

    try {
      // Determine batch duration: 60 minutes (regular) or 120 minutes (late admission)
      final batchDuration = _isLateAdmission ? 120 : 60;

      final result = await _batchService.autoGenerateBatches(
        instituteId: widget.instituteId,
        openTime: _openTime,
        closeTime: _closeTime,
        semester: _selectedSemester.toString(),
        year: _selectedYear!,
        subjects: _selectedSubjects,
        batchDurationMinutes: batchDuration,
      );

      setState(() => _isLoading = false);

      if (!mounted) return;

      if (result['success']) {
        widget.onBatchesGenerated();
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${result['count']} batches generated successfully'),
            backgroundColor: AppTheme.accentGreen,
          ),
        );
      } else {
        // Check if error is index-related
        if (result['indexError'] == true || 
            result['message'].toString().contains('index') || 
            result['message'].toString().contains('failed-precondition')) {
          // Show index creation dialog with URL if available
          await _showIndexCreationDialog(result['indexUrl']);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message']),
              backgroundColor: AppTheme.accentRed,
            ),
          );
        }
      }
    } catch (e) {
      setState(() => _isLoading = false);
      
      if (e.toString().contains('failed-precondition') || 
          e.toString().contains('index')) {
        // Show index creation dialog
        await _showIndexCreationDialog(null);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: ${e.toString()}'),
              backgroundColor: AppTheme.accentRed,
            ),
          );
        }
      }
    }
  }

  Future<bool?> _showIndexCreationDialog(String? indexUrl) async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: AppTheme.primaryBlue),
            SizedBox(width: 12),
            Expanded(child: Text('Firestore Index Required')),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Firestore indexes are required to generate batches. Please create them first.',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 16),
              const Text(
                'Steps to create indexes:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              const Text('1. Click the link below to open Firebase Console'),
              const Text('2. Click "Create Index" button'),
              const Text('3. Wait for index to be created (may take a few minutes)'),
              const Text('4. Return to the app and try again'),
              if (indexUrl != null) ...[
                const SizedBox(height: 16),
                const Text(
                  'Or use Firebase CLI:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'firebase deploy --only firestore:indexes',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    backgroundColor: Colors.grey,
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context, false);
            },
            child: const Text('Cancel'),
          ),
          if (indexUrl != null)
            TextButton(
              onPressed: () async {
                final launched = await FirestoreIndexService.openIndexCreationUrl(indexUrl);
                if (launched) {
                  // Mark that user has opened the link
                  await FirestoreIndexService.markIndexesCreated();
                  if (mounted) {
                    Navigator.pop(context, true);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please create the index and try again'),
                        duration: Duration(seconds: 3),
                      ),
                    );
                  }
                }
              },
              child: const Text('Open Firebase Console'),
            ),
          ElevatedButton(
            onPressed: () async {
              // User says they've created the index
              await FirestoreIndexService.markIndexesCreated();
              Navigator.pop(context, true);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentGreen,
            ),
            child: const Text('I\'ve Created the Index'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
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
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              padding: const EdgeInsets.all(24),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.auto_awesome, color: Colors.white, size: 28),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Generate Batches',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '60 minutes per batch (default)',
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
                    
                    // Institute Timing
                    Text(
                      'Institute Timing',
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
                            label: 'Open Time',
                            time: _openTime,
                            onTimeSelected: (time) => setState(() => _openTime = time),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildTimePicker(
                            label: 'Close Time',
                            time: _closeTime,
                            onTimeSelected: (time) => setState(() => _closeTime = time),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    
                    // Late Admission Toggle (for 120-minute batches)
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                      ),
                      child: SwitchListTile(
                        title: const Text(
                          'Late Admission Batches',
                          style: TextStyle(color: Colors.white, fontSize: 16),
                        ),
                        subtitle: Text(
                          _isLateAdmission 
                              ? '120 minutes per batch (2 hours)'
                              : '60 minutes per batch (1 hour) - Default',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12),
                        ),
                        value: _isLateAdmission,
                        onChanged: (value) => setState(() => _isLateAdmission = value),
                        activeColor: AppTheme.accentGreen,
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    // Semester Selection
                    Text(
                      'Semester',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      // Fix: Only use value if it exists in items to prevent "There should be exactly one item" error
                      value: _selectedSemester != null && 
                             _availableSemesters.any((sem) => (sem['semester'] as int) == _selectedSemester)
                          ? _selectedSemester
                          : null,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.2),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                        ),
                      ),
                      dropdownColor: AppTheme.primaryBlueDark,
                      style: const TextStyle(color: Colors.white),
                      items: _availableSemesters.map((sem) {
                        return DropdownMenuItem<int>(
                          value: sem['semester'] as int,
                          child: Text(sem['name'] as String),
                        );
                      }).toList(),
                      onChanged: (value) => setState(() => _selectedSemester = value),
                    ),
                    const SizedBox(height: 24),
                    
                    // Subjects Selection
                    Text(
                      'Subjects (Select 2-3 for Simultaneous)',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Multiple subjects can run simultaneously in the same batch',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_isLoadingSubjects)
                      const Center(child: CircularProgressIndicator(color: Colors.white))
                    else
                      Container(
                        constraints: const BoxConstraints(maxHeight: 200),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                        ),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: _availableSubjects.length,
                          itemBuilder: (context, index) {
                            final subject = _availableSubjects[index];
                            final isSelected = _selectedSubjects.contains(subject['name']);
                            return CheckboxListTile(
                              title: Text(
                                subject['name'],
                                style: const TextStyle(color: Colors.white),
                              ),
                              value: isSelected,
                              onChanged: (value) {
                                setState(() {
                                  if (value == true) {
                                    _selectedSubjects.add(subject['name']);
                                  } else {
                                    _selectedSubjects.remove(subject['name']);
                                  }
                                });
                              },
                              activeColor: AppTheme.accentGreen,
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 24),
                    
                    // Generate Button
                    ElevatedButton(
                      onPressed: _isLoading ? null : _generateBatches,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.accentGreen,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text(
                              'Generate Batches',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
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
    );
  }

  Widget _buildTimePicker({
    required String label,
    required TimeOfDay time,
    required ValueChanged<TimeOfDay> onTimeSelected,
  }) {
    return GestureDetector(
      onTap: () async {
        final selected = await showTimePicker(
          context: context,
          initialTime: time,
          builder: (context, child) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            return Theme(
              data: Theme.of(context).copyWith(
                colorScheme: ColorScheme.light(
                  primary: AppTheme.primaryBlue,
                  onSurface: isDark ? Colors.white : AppTheme.textDark,
                ),
              ),
              child: child!,
            );
          },
        );
        if (selected != null) {
          onTimeSelected(selected);
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
