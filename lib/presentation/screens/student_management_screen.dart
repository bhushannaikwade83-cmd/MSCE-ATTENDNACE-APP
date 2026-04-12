import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/app_db.dart';
import '../../core/utils/responsive.dart';

import '../../core/theme/app_theme.dart';
import '../../services/validation_service.dart';
import '../../services/batch_service.dart';
import '../widgets/shimmer_effect.dart';
import '../widgets/enhanced_animations.dart';
import 'add_student_screen.dart';
import 'student_photos_screen.dart';

class StudentManagementScreen extends StatefulWidget {
  static const routeName = '/student-management';
  const StudentManagementScreen({super.key});

  @override
  State<StudentManagementScreen> createState() =>
      _StudentManagementScreenState();
}

class _StudentManagementScreenState extends State<StudentManagementScreen>
    with TickerProviderStateMixin {
  String? _instituteId;
  bool _isLoadingInstitute = true;

  final BatchService _batchService = BatchService();
  List<Map<String, dynamic>> _batches = [];
  String? _selectedBatchId;
  bool _isLoadingBatches = false;

  // Search with debounce (server-side)
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _debounce;

  // Paginated student list state
  static const int _pageSize = 50;
  int _page = 0;
  bool _hasMore = true;
  bool _isLoadingStudents = false;
  bool _isLoadingMore = false;
  List<Map<String, dynamic>> _students = [];
  int _studentCount = 0;
  final ScrollController _scrollController = ScrollController();

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
    _scrollController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      final q = _searchController.text.trim();
      if (q != _searchQuery) {
        setState(() {
          _searchQuery = q;
          _page = 0;
          _students.clear();
          _hasMore = true;
        });
        _loadStudents(reset: true);
      }
    });
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 200 && _hasMore && !_isLoadingMore) {
      _loadStudents();
    }
  }

  Future<void> _loadInstituteId() async {
    try {
      final user = appDb.auth.currentUser;
      if (user == null) {
        setState(() => _isLoadingInstitute = false);
        return;
      }

      if (kDebugMode) debugPrint('Loading institute ID for user: ${user.id}');

      final row = await appDb.from('profiles').select('institute_id').eq('id', user.id).maybeSingle();
      final foundInstituteId = row?['institute_id'] as String?;

      if (foundInstituteId != null && foundInstituteId.isNotEmpty) {
        if (kDebugMode) debugPrint('✅ User found in institute: $foundInstituteId');
        setState(() {
          _instituteId = foundInstituteId;
          _isLoadingInstitute = false;
        });
        await _loadBatches();
        return;
      }

      if (kDebugMode) debugPrint('⚠️ User not found in any institute');
      setState(() => _isLoadingInstitute = false);
    } catch (e) {
      if (kDebugMode) debugPrint('Institute load error: $e');
      setState(() => _isLoadingInstitute = false);
    }
  }

  Future<void> _loadBatches() async {
    if (_instituteId == null) return;
    setState(() => _isLoadingBatches = true);
    try {
      // Load batches and initial student page in parallel
      final results = await Future.wait([
        _batchService.getBatches(_instituteId!),
        _fetchStudentPage(page: 0, query: ''),
      ]);
      if (mounted) {
        setState(() {
          _batches = results[0] as List<Map<String, dynamic>>;
          _isLoadingBatches = false;
        });
        _applyStudentPage(results[1] as _StudentPage, reset: true);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Batch load error: $e');
      if (mounted) setState(() => _isLoadingBatches = false);
    }
  }

  Future<_StudentPage> _fetchStudentPage({
    required int page,
    required String query,
    String? batchId,
  }) async {
    if (_instituteId == null) return const _StudentPage(rows: [], total: 0);

    var q = appDb
        .from('students')
        .select('id,name,user_id,sr_no,year,phone_number,batch_id')
        .eq('institute_id', _instituteId!);

    if (query.isNotEmpty) {
      q = q.or('name.ilike.%$query%,user_id.ilike.%$query%,sr_no.ilike.%$query%');
    }
    if (batchId != null) q = q.eq('batch_id', batchId);

    final from = page * _pageSize;
    final res = await q
        .range(from, from + _pageSize - 1)
        .order('name')
        .count(CountOption.exact);

    final list = (res.data as List?) ?? const [];
    final rows = list.cast<Map<String, dynamic>>();
    return _StudentPage(rows: rows, total: res.count);
  }

  void _applyStudentPage(_StudentPage page, {required bool reset}) {
    if (!mounted) return;
    final mapped = page.rows.map(_mapStudentRow).toList();
    setState(() {
      if (reset) {
        _students = mapped;
      } else {
        _students.addAll(mapped);
      }
      _page = reset ? 1 : _page + 1;
      _hasMore = page.rows.length == _pageSize;
      _studentCount = page.total;
      _isLoadingStudents = false;
      _isLoadingMore = false;
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
    } else {
      if (_isLoadingMore || !_hasMore) return;
      setState(() => _isLoadingMore = true);
    }

    try {
      final page = await _fetchStudentPage(
        page: reset ? 0 : _page,
        query: _searchQuery,
        batchId: _selectedBatchId,
      );
      _applyStudentPage(page, reset: reset);
    } catch (e) {
      if (kDebugMode) debugPrint('Student load error: $e');
      if (mounted) setState(() { _isLoadingStudents = false; _isLoadingMore = false; });
    }
  }

  Map<String, dynamic> _mapStudentRow(Map<String, dynamic> row) {
    String batchName = '';
    String subject = '';
    final bid = row['batch_id']?.toString();
    if (bid != null) {
      for (final b in _batches) {
        if (b['id']?.toString() == bid) {
          batchName = b['name'] as String? ?? '';
          final subs = b['subjects'] as List<dynamic>?;
          if (subs != null && subs.isNotEmpty) {
            subject = subs.first.toString();
          }
          break;
        }
      }
    }
    return {
      'id': row['id'],
      'name': row['name'],
      'userId': row['user_id'] ?? row['sr_no'] ?? '',
      'batchName': batchName,
      'subject': subject,
      'year': row['year'],
      'phoneNumber': row['phone_number'],
      'batchId': row['batch_id'],
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
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
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
        backgroundColor: isDark ? const Color(0xFF0F172A) : AppTheme.backgroundGrey,
        body: SafeArea(
          top: false,
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Column(
              children: [
                _buildStudentToolbar(),
                _buildSearchBar(),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return _buildBody();
                    },
                  ),
                ),
              ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AddStudentScreen()),
          );
          if (result == true) {
            await _loadStudents(reset: true);
          }
        },
        icon: const Icon(Icons.add),
        label: const Text('Add Student', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
      ),
      ),
    );
  }

  Widget _buildStudentToolbar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
      color: AppTheme.backgroundGrey,
      child: Row(
        children: [
          Icon(Icons.school_rounded, color: AppTheme.primaryBlue, size: 22.sp),
          SizedBox(width: 10.w),
          Expanded(
            child: Text(
              'Student directory',
              style: TextStyle(
                color: isDark ? Colors.white : AppTheme.textDark,
                fontSize: 15.sp,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20.r),
              border: Border.all(color: AppTheme.primaryBlue.withValues(alpha: 0.25)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.people_outline, color: AppTheme.primaryBlue, size: 18.sp),
                SizedBox(width: 6.w),
                Text(
                  '$_studentCount',
                  style: TextStyle(
                    color: AppTheme.primaryBlue,
                    fontSize: 15.sp,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // Show loading while checking institute
    if (_isLoadingInstitute) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    // Show error if institute not found
    if (_instituteId == null) {
      return Center(
        child: _buildModernCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline,
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
          isDark: isDark,
        ),
      );
    }

    // Show paginated student list
    if (_isLoadingStudents) {
      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: 5,
        itemBuilder: (context, index) => ShimmerListItem().stagger(index: index),
      );
    }

    if (_students.isEmpty && !_isLoadingStudents) {
      return Center(
        child: _buildModernCard(
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
                    : 'Add your first student using the + button',
                style: TextStyle(
                  color: isDark ? Colors.white70 : AppTheme.textGray,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          isDark: isDark,
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadStudents(reset: true),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        itemCount: _students.length + (_isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _students.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }
          final data = _students[index];
              final name = data['name'] ?? 'Unknown';
              final rollNumber = data['userId'] ?? '';
              final batchName = data['batchName'] ?? '';
              final subject = data['subject'] ?? '';

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildModernCard(
                  isDark: isDark,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryBlue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.person, color: AppTheme.primaryBlue, size: 24),
                    ),
                    title: Text(
                      name,
                      style: TextStyle(
                        color: isDark ? Colors.white : AppTheme.textDark,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text(
                          'Roll: $rollNumber',
                          style: TextStyle(
                            color: isDark ? Colors.white70 : AppTheme.textGray,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (batchName.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Batch: $batchName',
                            style: TextStyle(
                              color: isDark ? Colors.white70 : AppTheme.textGray,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        if (subject.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Subject: $subject',
                            style: TextStyle(
                              color: isDark ? Colors.white : AppTheme.primaryBlue,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(
                            Icons.edit,
                            color: isDark ? Colors.white70 : AppTheme.primaryBlue,
                            size: 22,
                          ),
                          onPressed: () {
                            _showEditStudentDialog(
                              studentId: data['id'] as String,
                              studentData: data,
                            );
                          },
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.photo_library,
                            color: isDark ? Colors.white70 : AppTheme.primaryBlue,
                            size: 22,
                          ),
                          onPressed: () {
                            // Navigate to student photos screen
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => StudentPhotosScreen(
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
                    onTap: () {
                      // Navigate to student photos screen
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => StudentPhotosScreen(
                            studentName: name,
                            rollNumber: rollNumber,
                            instituteId: _instituteId!,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              );
            },
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
        onChanged: (value) {
          setState(() {
            _searchQuery = value;
          });
        },
        decoration: InputDecoration(
          hintText: 'Search by name, roll number, batch, or subject...',
          hintStyle: TextStyle(
            color: isDark ? Colors.white.withOpacity(0.5) : AppTheme.textGray,
            fontSize: 14.sp,
          ),
          prefixIcon: Icon(
            Icons.search,
            color: isDark ? Colors.white.withOpacity(0.7) : AppTheme.primaryBlue,
            size: 24.sp,
          ),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: Icon(
                    Icons.clear,
                    color: isDark ? Colors.white.withOpacity(0.7) : AppTheme.textGray,
                    size: 20.sp,
                  ),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _searchQuery = '';
                    });
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

  void _showEditStudentDialog({
    required String studentId,
    required Map<String, dynamic> studentData,
  }) {
    if (_instituteId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Institute not found'),
          backgroundColor: AppTheme.accentRed,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (context) => _EditStudentDialog(
        instituteId: _instituteId!,
        studentId: studentId,
        studentData: studentData,
        batches: _batches,
        onStudentUpdated: () {
          // Refresh will happen automatically via StreamBuilder
          Navigator.pop(context);
        },
      ),
    );
  }
}

class _EditStudentDialog extends StatefulWidget {
  final String instituteId;
  final String studentId;
  final Map<String, dynamic> studentData;
  final List<Map<String, dynamic>> batches;
  final VoidCallback onStudentUpdated;

  const _EditStudentDialog({
    required this.instituteId,
    required this.studentId,
    required this.studentData,
    required this.batches,
    required this.onStudentUpdated,
  });

  @override
  State<_EditStudentDialog> createState() => _EditStudentDialogState();
}

class _EditStudentDialogState extends State<_EditStudentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _rollController = TextEditingController();
  final _yearController = TextEditingController();
  final _contactController = TextEditingController();
  
  Map<String, dynamic>? _selectedBatch;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Pre-fill with existing student data
    _nameController.text = widget.studentData['name'] ?? '';
    _rollController.text = widget.studentData['userId'] ?? '';
    _yearController.text = widget.studentData['year'] ?? '';
    _contactController.text = widget.studentData['phoneNumber'] ?? '';
    
    // Find selected batch
    final batchId = widget.studentData['batchId'] as String?;
    final batchName = widget.studentData['batchName'] as String?;
    if (batchId != null && widget.batches.isNotEmpty) {
      try {
        _selectedBatch = widget.batches.firstWhere(
          (batch) => batch['id'] == batchId,
        );
      } catch (e) {
        // Try to find by name if ID not found
        if (batchName != null) {
          try {
            _selectedBatch = widget.batches.firstWhere(
              (batch) => batch['name'] == batchName,
            );
          } catch (e) {
            _selectedBatch = null;
          }
        }
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _rollController.dispose();
    _yearController.dispose();
    _contactController.dispose();
    super.dispose();
  }

  Future<void> _updateStudent() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final updateData = <String, dynamic>{
        'name': ValidationService.sanitizeInput(_nameController.text.trim()),
        'user_id': ValidationService.sanitizeInput(_rollController.text.trim()),
        'year': ValidationService.sanitizeInput(_yearController.text.trim()),
        'phone_number': _contactController.text.trim(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

      // Update batch if selected
      if (_selectedBatch != null) {
        updateData['batch_id'] = _selectedBatch!['id'];
        updateData['batch_name'] = _selectedBatch!['name'];
        updateData['batch_timing'] = _selectedBatch!['timing'];
        
        // Update subject if batch has subjects
        final subjects = _selectedBatch!['subjects'] as List<dynamic>?;
        if (subjects != null && subjects.isNotEmpty) {
          updateData['subject'] = subjects.first.toString();
        }
      }

      await appDb.from('students').update(updateData).eq('id', widget.studentId).eq('institute_id', widget.instituteId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Student updated successfully'),
            backgroundColor: AppTheme.accentGreen,
          ),
        );
        widget.onStudentUpdated();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error updating student: ${e.toString()}'),
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        decoration: BoxDecoration(
          color: isDark ? Colors.grey[900] : Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 30,
              spreadRadius: 10,
            ),
          ],
        ),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
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
                        color: AppTheme.primaryBlue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.edit_rounded, color: AppTheme.primaryBlue, size: 24),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Edit Student',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                
                // Name
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Student Name',
                    prefixIcon: Icon(Icons.person),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => ValidationService.validateName(value ?? ''),
                ),
                const SizedBox(height: 16),
                
                // Roll Number
                TextFormField(
                  controller: _rollController,
                  decoration: const InputDecoration(
                    labelText: 'Roll Number',
                    prefixIcon: Icon(Icons.badge),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => ValidationService.validateRollNumber(value ?? ''),
                ),
                const SizedBox(height: 16),
                
                // Year
                TextFormField(
                  controller: _yearController,
                  decoration: const InputDecoration(
                    labelText: 'Year',
                    prefixIcon: Icon(Icons.calendar_today),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Year is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                
                // Contact Number
                TextFormField(
                  controller: _contactController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Contact Number',
                    prefixIcon: Icon(Icons.phone),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                
                // Batch Selection
                DropdownButtonFormField<Map<String, dynamic>>(
                  value: _selectedBatch,
                  decoration: const InputDecoration(
                    labelText: 'Batch',
                    prefixIcon: Icon(Icons.groups),
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<Map<String, dynamic>>(
                      value: null,
                      child: Text('No Batch'),
                    ),
                    ...widget.batches.map((batch) {
                      return DropdownMenuItem<Map<String, dynamic>>(
                        value: batch,
                        child: Text('${batch['name']} (${batch['year']})'),
                      );
                    }),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedBatch = value;
                    });
                  },
                ),
                const SizedBox(height: 24),
                
                // Update Button
                SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _updateStudent,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryBlue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 3,
                            ),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.save_rounded, size: 22),
                              SizedBox(width: 10),
                              Text(
                                'Update Student',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
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
    );
  }
}


/// Lightweight value object returned by server-side paginated student queries.
class _StudentPage {
  final List<Map<String, dynamic>> rows;
  final int total;
  const _StudentPage({required this.rows, required this.total});
}
