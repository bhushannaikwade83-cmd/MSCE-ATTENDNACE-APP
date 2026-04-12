import 'dart:io';
import '../../core/app_db.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'dart:ui';
import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/batch_service.dart';
import '../../services/semester_service.dart';
import '../../services/subject_service.dart';
import '../../services/error_handler.dart';
import '../../core/utils/professional_messaging.dart';
// Face recognition enabled - save face template for attendance verification
import '../../services/face_recognition_service.dart';
import '../../services/arcface_backend_service.dart';
import '../../services/photo_verification_service.dart';
import '../../services/liveness_detection_service.dart';
import '../widgets/face_scanning_widget.dart';
import '../widgets/face_scanner_widget.dart';
import 'help_desk_screen.dart';

class AddStudentScreen extends StatefulWidget {
  static const routeName = '/add-student';
  const AddStudentScreen({super.key});

  @override
  State<AddStudentScreen> createState() => _AddStudentScreenState();
}

class _AddStudentScreenState extends State<AddStudentScreen> with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _rollController = TextEditingController();
  final _yearController = TextEditingController();
  final _contactController = TextEditingController();
  final AuthService _authService = AuthService();
  final BatchService _batchService = BatchService();
  final SemesterService _semesterService = SemesterService();
  final SubjectService _subjectService = SubjectService();
  final ImagePicker _picker = ImagePicker();

  bool _isLoading = false;
  bool _isCapturingFace = false;
  bool _isLoadingBatches = false;
  bool _isLoadingSubjects = false;
  String? _facePhotoPath;
  bool _faceRegistered = false; // Track if face was successfully registered
  String? _instituteId;
  List<Map<String, dynamic>> _batches = [];
  List<String> _selectedBatchIds = []; // Multiple batches
  List<Map<String, dynamic>> _availableSubjects = [];
  List<String> _selectedSubjects = []; // Multiple subjects
  Map<String, dynamic>? _selectedSemester;
  List<Map<String, dynamic>> _availableSemesters = [];

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
    _nameController.dispose();
    _rollController.dispose();
    _yearController.dispose();
    _contactController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _loadInstituteId() async {
    try {
      final user = appDb.auth.currentUser;
      if (user == null) {
        if (kDebugMode) debugPrint('No user logged in');
        return;
      }

      if (kDebugMode) debugPrint('Loading institute ID for user: ${user.id}');

      final profile = await appDb.from('profiles').select('institute_id').eq('id', user.id).maybeSingle();
      final foundInstituteId = profile?['institute_id'] as String?;
      if (foundInstituteId != null && foundInstituteId.isNotEmpty) {
        if (kDebugMode) debugPrint('✅ Institute from profile: $foundInstituteId');
        setState(() {
          _instituteId = foundInstituteId;
        });
        await _loadBatches();
        await _loadSubjects();
        await _loadSemesters();
        return;
      }

      if (kDebugMode) debugPrint('⚠️ User not found in any institute');
    } catch (e) {
      if (kDebugMode) debugPrint('Institute load error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading institute: ${e.toString()}'),
            backgroundColor: AppTheme.accentRed,
          ),
        );
      }
    }
  }


  Future<void> _loadSubjects() async {
    if (_instituteId == null) {
      if (kDebugMode) debugPrint('⚠️ Cannot load subjects: instituteId is null');
      return;
    }

    setState(() => _isLoadingSubjects = true);
    try {
      _availableSubjects = await _subjectService.getSubjects(_instituteId!);
      
      // If no subjects, try to initialize defaults
      if (_availableSubjects.isEmpty) {
        try {
          await _subjectService.initializeDefaultSubjects(_instituteId!);
          _availableSubjects = await _subjectService.getSubjects(_instituteId!);
        } catch (initError) {
          if (kDebugMode) {
            debugPrint('⚠️ Could not initialize subjects (permission issue): $initError');
            debugPrint('   Subjects will need to be added manually in Firestore');
          }
          // Continue without subjects - user can add them manually
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error loading subjects: $e');
        debugPrint('   This might be a Firestore permissions issue.');
        debugPrint('   Please ensure subjects collection has proper read permissions.');
      }
      // Show user-friendly message
      if (mounted) {
        ProfessionalMessaging.showError(
          context,
          title: 'Failed to Load Subjects',
          message: 'Could not load subjects. Please add subjects manually or check Firestore permissions.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingSubjects = false);
      }
    }
  }

  Future<void> _loadSemesters() async {
    _availableSemesters = _semesterService.getSemestersForSelection();
    final currentYear = _semesterService.getCurrentYear();
    final currentSemester = _semesterService.getCurrentSemester();
    
    // Set default to current semester - find by matching semester and year
    if (_availableSemesters.isNotEmpty) {
      try {
        _selectedSemester = _availableSemesters.firstWhere(
          (sem) => sem['semester'] == currentSemester && sem['year'] == currentYear,
        );
      } catch (e) {
        // If not found, use first available
        _selectedSemester = _availableSemesters.first;
      }
    }
  }

  Future<void> _loadBatches() async {
    if (_instituteId == null) {
      if (kDebugMode) debugPrint('⚠️ Cannot load batches: instituteId is null');
      return;
    }

    setState(() => _isLoadingBatches = true);
    try {
      if (kDebugMode) debugPrint('Loading batches for institute: $_instituteId');
      _batches = await _batchService.getBatches(_instituteId!);
      if (kDebugMode) debugPrint('✅ Loaded ${_batches.length} batches');
      
      if (_batches.isEmpty && mounted) {
        ProfessionalMessaging.showWarning(
          context,
          title: 'No Batches Found',
          message: 'Please create batches first before adding students. Go to Batch Management to create batches.',
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Batch load error: $e');
      if (mounted) {
        ProfessionalMessaging.showError(
          context,
          title: 'Failed to Load Batches',
          message: ProfessionalMessaging.getProfessionalErrorMessage(e.toString()),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingBatches = false);
      }
    }
  }

  Future<void> _captureFacePhoto() async {
    setState(() => _isCapturingFace = true);
    
    try {
      // Use simple mobile camera to take single photo
      final photo = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        preferredCameraDevice: CameraDevice.front,
      );
      
      if (photo == null) {
        setState(() => _isCapturingFace = false);
        return;
      }
      
      final capturedPhotoPath = photo.path;
      
      // Store captured image
      setState(() {
        _facePhotoPath = capturedPhotoPath;
        _faceRegistered = false; // Reset registration status
      });
      
      // Show processing overlay
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => FaceScanningOverlay(
            message: 'Processing photo...',
          ),
        );
      }
      
      // Basic validation on photo (quick check)
      final imageFile = File(capturedPhotoPath);
      if (!await imageFile.exists() || await imageFile.length() < 1024) {
        if (mounted) {
          Navigator.of(context).pop();
          ProfessionalMessaging.showError(
            context,
            title: 'Invalid Photo',
            message: 'Photo file is invalid. Please try again.',
          );
        }
        setState(() => _isCapturingFace = false);
        return;
      }

      // Close processing overlay
      if (mounted) {
        Navigator.of(context).pop();
      }

      // Immediately register face with single image
      await _registerFaceImmediately(
        capturedPhotoPath,
        additionalImages: null, // No additional images - single photo only
      );
    } catch (e) {
      final error = ErrorHandler.formatErrorForUI(e, context: 'captureFacePhoto');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error['message']),
            backgroundColor: AppTheme.accentRed,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        );
      }
    }
    setState(() => _isCapturingFace = false);
  }

  /// Register face immediately after capture (before student creation)
  /// Uses single image only - additional images parameter is ignored
  Future<void> _registerFaceImmediately(String photoPath, {List<String>? additionalImages}) async {
    if (_instituteId == null) {
      if (kDebugMode) {
        debugPrint('⚠️ Cannot register face: Institute ID is null');
      }
      return;
    }

    try {
      // Generate a temporary student ID for face registration
      // We'll use a placeholder that will be replaced when student is created
      final tempStudentId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
      final rollNumber = _rollController.text.trim();
      final studentName = _nameController.text.trim();

      if (kDebugMode) {
        debugPrint('📸 Registering face for Roll $rollNumber with single image...');
      }

      // Register face with backend (single image only)
      final faceRegistered = await ArcFaceBackendService.registerStudentFace(
        imagePath: photoPath,
        additionalImagePaths: null, // Single image only - no additional images
        instituteId: _instituteId!,
        studentId: tempStudentId, // Temporary ID
        rollNumber: rollNumber,
        name: studentName,
      );

      if (faceRegistered) {
        setState(() {
          _faceRegistered = true; // Mark as registered
        });
        
        if (kDebugMode) {
          debugPrint('✅ Face registered successfully for Roll $rollNumber');
        }
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Face registered successfully'),
              backgroundColor: AppTheme.accentGreen,
              duration: Duration(seconds: 2),
            ),
          );
        }
      } else {
        setState(() {
          _faceRegistered = false;
          _facePhotoPath = null; // Clear photo path to force re-scan
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ Face registration failed. Please try again.'),
              backgroundColor: AppTheme.accentRed,
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      setState(() {
        _faceRegistered = false;
        _facePhotoPath = null; // Clear photo path to force re-scan
      });
      
      if (kDebugMode) {
        debugPrint('❌ Error registering face: $e');
      }
      
      String errorMessage = 'Face registration failed';
      final errorStr = e.toString();
      
      if (kDebugMode) {
        debugPrint('🔍 Parsing error message: $errorStr');
      }
      
      // First, try to extract the actual error message from Exception(...)
      // This handles cases like: Exception: 🚨 SPOOF DETECTED: ...
      final exceptionMatch = RegExp(r'Exception:\s*(.+)', caseSensitive: false).firstMatch(errorStr);
      if (exceptionMatch != null) {
        final extractedMessage = exceptionMatch.group(1)?.trim() ?? '';
        if (extractedMessage.isNotEmpty && 
            !extractedMessage.contains('500') && 
            !extractedMessage.contains('503') &&
            !extractedMessage.contains('Backend Error:')) {
          errorMessage = extractedMessage;
          if (kDebugMode) {
            debugPrint('✅ Extracted error message: $errorMessage');
          }
        }
      }
      
      // If we still have the default message, try other patterns
      if (errorMessage == 'Face registration failed') {
        // Check for specific error types
        if (errorStr.contains('SPOOF DETECTED') || errorStr.contains('Spoof detected')) {
          // Extract spoof detection message
          final spoofMatch = RegExp(r'(SPOOF DETECTED[^\n]*)', caseSensitive: false).firstMatch(errorStr);
          if (spoofMatch != null) {
            errorMessage = spoofMatch.group(1) ?? '🚨 SPOOF DETECTED: Please use a live photo.';
          } else {
            errorMessage = '🚨 SPOOF DETECTED: Please use a live photo, not a printed photo or phone screen.';
          }
        } else if (errorStr.contains('No face detected') || errorStr.contains('no face detected')) {
          errorMessage = '❌ No face detected. Take a clear photo with face visible.';
        } else if (errorStr.contains('timeout') || errorStr.contains('Timeout')) {
          errorMessage = '❌ Timeout. Please try again.';
        } else if (errorStr.contains('Backend Error:')) {
          // Extract the actual backend error message
          final match = RegExp(r'Backend Error:\s*(.+)', caseSensitive: false).firstMatch(errorStr);
          if (match != null) {
            errorMessage = match.group(1)?.trim() ?? '❌ Backend error occurred.';
          }
        } else if (errorStr.contains('400')) {
          errorMessage = '❌ Invalid photo. Please take a clear photo.';
        } else if (errorStr.contains('500') || errorStr.contains('503')) {
          // Try to extract actual error from exception
          final match = RegExp(r'Exception:\s*(.+)', caseSensitive: false).firstMatch(errorStr);
          if (match != null && 
              !match.group(1)!.contains('500') && 
              !match.group(1)!.contains('503')) {
            errorMessage = match.group(1)?.trim() ?? '❌ Server error occurred.';
          } else {
            errorMessage = '❌ Server error. Please try again.';
          }
        }
      }
      
      // Final fallback - use the full exception string if we still have default
      if (errorMessage == 'Face registration failed') {
        errorMessage = errorStr.replaceAll('Exception: ', '').trim();
        if (errorMessage.isEmpty) {
          errorMessage = '❌ Registration failed. Please try again.';
        }
      }
      
      if (kDebugMode) {
        debugPrint('📱 Final error message to display: $errorMessage');
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: AppTheme.accentRed,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedBatchIds.isEmpty) {
      ProfessionalMessaging.showWarning(
        context,
        title: 'Batch Selection Required',
        message: 'Please select at least one batch for this student. Students can be assigned to multiple batches.',
      );
      return;
    }

    if (_selectedSubjects.isEmpty) {
      ProfessionalMessaging.showWarning(
        context,
        title: 'Subject Selection Required',
        message: 'Please select at least one subject from the predefined list. Students can be enrolled in multiple subjects.',
      );
      return;
    }

    if (_selectedSemester == null) {
      ProfessionalMessaging.showWarning(
        context,
        title: 'Semester Selection Required',
        message: 'Please select a semester for this student. The year will be automatically set based on your selection.',
      );
      return;
    }

    // Require face photo AND successful face registration
    if (_facePhotoPath == null || !_faceRegistered) {
      ProfessionalMessaging.showError(
        context,
        title: 'Face Registration Required',
        message: _facePhotoPath == null
            ? 'Please capture and register the student\'s face first. Face registration is mandatory for student creation.'
            : 'Face registration failed. Please scan the face again and ensure registration succeeds before adding the student.\n\nStudent will NOT be added until face registration is successful.',
        durationSeconds: 5,
      );
      return;
    }

    // Validate institute ID
    if (_instituteId == null || _instituteId!.isEmpty) {
      setState(() => _isLoading = false);
      ProfessionalMessaging.showError(
        context,
        title: 'Institute Not Found',
        message: 'Could not determine your institute. Please ensure you are logged in as an admin.',
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Get batch names and timings
      final selectedBatches = _batches.where((b) => _selectedBatchIds.contains(b['id'])).toList();
      if (selectedBatches.isEmpty) {
        setState(() => _isLoading = false);
        ProfessionalMessaging.showError(
          context,
          title: 'Invalid Batch Selection',
          message: 'Selected batches could not be found. Please select valid batches.',
        );
        return;
      }
      
      final batchNames = selectedBatches.map((b) => b['name'] as String).join(', ');
      final batchTimings = selectedBatches.map((b) => b['timing'] as String).join('; ');

      if (kDebugMode) {
        debugPrint('📝 Adding student:');
        debugPrint('   Name: ${_nameController.text.trim()}');
        debugPrint('   Roll: ${_rollController.text.trim()}');
        debugPrint('   Institute ID: $_instituteId');
        debugPrint('   Batches: $_selectedBatchIds');
        debugPrint('   Subjects: $_selectedSubjects');
      }

      final result = await _authService.addStudentManually(
        name: _nameController.text.trim(),
        rollNumber: _rollController.text.trim(),
        year: _yearController.text.trim(),
        contactNo: _contactController.text.trim(),
        batchId: _selectedBatchIds.first, // Primary batch ID
        batchName: batchNames,
        batchTiming: batchTimings,
        subject: _selectedSubjects.join(', '),
        semester: _selectedSemester!['code'] as String,
        semesterName: _selectedSemester!['name'] as String,
        batchIds: _selectedBatchIds, // All selected batch IDs
        subjects: _selectedSubjects, // Selected subjects
        instituteId: _instituteId,
      );

      // Face is already registered before student creation
      // Update face registration with actual student ID
      if (result['success'] && _faceRegistered && _facePhotoPath != null && _instituteId != null) {
        final studentId = result['studentId'] as String?;
        final rollNumber = _rollController.text.trim();
        final studentName = _nameController.text.trim();
        
        if (studentId != null) {
          // Re-register face with actual student ID (replaces temp registration)
          try {
            final faceReRegistered = await ArcFaceBackendService.registerStudentFace(
              imagePath: _facePhotoPath!,
              instituteId: _instituteId!,
              studentId: studentId,
              rollNumber: rollNumber,
              name: studentName,
            );
            
            if (faceReRegistered) {
              if (kDebugMode) {
                debugPrint('✅ Face registration updated with actual student ID: $studentId');
              }
            } else {
              if (kDebugMode) {
                debugPrint('⚠️ Failed to update face registration with actual student ID');
              }
              // This is not critical - face is already registered with temp ID
              // The roll number and institute ID are the same, so it will work
            }
          } catch (e) {
            if (kDebugMode) {
              debugPrint('❌ Error updating face registration: $e');
            }
            // Not critical - face is already registered
          }
        }
      } else if (result['success'] && !_faceRegistered) {
        // This should not happen as we check _faceRegistered before submit
        // But handle it just in case
        if (kDebugMode) {
          debugPrint('⚠️ WARNING: Student created but face was not registered!');
        }
        
        if (mounted) {
          ProfessionalMessaging.showError(
            context,
            title: 'Registration Error',
            message: 'Student was created but face registration status is invalid. Please contact support.',
          );
        }
      }

      setState(() => _isLoading = false);

      if (!mounted) return;

      if (result['success']) {
        ProfessionalMessaging.showSuccess(
          context,
          title: 'Student Added Successfully',
          message: '${_nameController.text.trim()} has been registered. Face recognition is enabled for attendance marking.',
          actionLabel: 'Done',
          onAction: () => Navigator.pop(context, true),
        );
        // Close screen after short delay
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) Navigator.pop(context, true);
        });
      } else {
        ProfessionalMessaging.showError(
          context,
          title: 'Failed to Add Student',
          message: ProfessionalMessaging.getProfessionalErrorMessage(result['message'] ?? 'Unknown error occurred'),
        );
      }
    } catch (e, stackTrace) {
      setState(() => _isLoading = false);
      
      if (!mounted) return;
      
      if (kDebugMode) {
        debugPrint('❌ Unexpected error adding student: $e');
        debugPrint('   Stack trace: $stackTrace');
      }
      
      // Provide more specific error message
      String errorMessage = 'An unexpected error occurred while adding the student.';
      final errorString = e.toString().toLowerCase();
      
      if (errorString.contains('permission') || errorString.contains('permission-denied')) {
        errorMessage = 'Permission denied. Please check Firestore security rules for students collection.';
      } else if (errorString.contains('network') || errorString.contains('connection')) {
        errorMessage = 'Network error. Please check your internet connection and try again.';
      } else if (errorString.contains('timeout')) {
        errorMessage = 'Request timed out. Please check your connection and try again.';
      } else {
        errorMessage = 'An unexpected error occurred: ${e.toString()}';
      }
      
      ProfessionalMessaging.showError(
        context,
        title: 'Failed to Add Student',
        message: errorMessage,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          // Pop already happened, no action needed
          return;
        }
        // If pop was prevented, manually pop
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
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
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                        padding: EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildHeader(),
                          const SizedBox(height: 24),
                          _buildGlassCard(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildModernTextField(
                                  controller: _nameController,
                                  icon: Icons.person_outline,
                                  label: 'Full Name',
                                  hint: 'Enter student name',
                                  validator: (v) => v!.isEmpty ? 'Required' : null,
                                ),
                                const SizedBox(height: 20),
                                _buildModernTextField(
                                  controller: _rollController,
                                  icon: Icons.badge_outlined,
                                  label: 'Roll Number',
                                  hint: 'Enter roll number',
                                  validator: (v) => v!.isEmpty ? 'Required' : null,
                                ),
                                const SizedBox(height: 20),
                                _buildModernTextField(
                                  controller: _yearController,
                                  icon: Icons.calendar_today_outlined,
                                  label: 'Year',
                                  hint: 'e.g., First Year',
                                  validator: (v) => v!.isEmpty ? 'Required' : null,
                                ),
                                const SizedBox(height: 16),
                                if (_isLoadingBatches)
                                        Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 16),
                                          child: Center(
                                            child: CircularProgressIndicator(
                                              color: Theme.of(context).brightness == Brightness.dark 
                                                  ? Colors.white 
                                                  : AppTheme.primaryBlue,
                                            ),
                                          ),
                                  ),
                                if (!_isLoadingBatches && _batches.isEmpty)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    child: Text(
                                      'No batches available. Please create a batch first.',
                                      style: TextStyle(
                                              color: Theme.of(context).brightness == Brightness.dark
                                                  ? Colors.white.withValues(alpha: 0.8)
                                                  : AppTheme.textDark.withValues(alpha: 0.7),
                                        fontSize: 14,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                // Semester Selection
                                if (_availableSemesters.isNotEmpty) ...[
                                  Builder(
                                    builder: (context) {
                                      final isDark = Theme.of(context).brightness == Brightness.dark;
                                      // Use semester code as unique identifier for dropdown
                                      final selectedCode = _selectedSemester?['code'] as String?;
                                      return _buildModernDropdown<String>(
                                        value: selectedCode,
                                        label: 'Semester',
                                        icon: Icons.calendar_month,
                                        items: _availableSemesters
                                            .map((sem) {
                                              final code = sem['code'] as String;
                                              return DropdownMenuItem<String>(
                                                value: code,
                                              child: Text(
                                                  sem['name'] as String,
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
                                        onChanged: (code) {
                                          if (code != null) {
                                      setState(() {
                                              _selectedSemester = _availableSemesters.firstWhere(
                                                (sem) => sem['code'] == code,
                                              );
                                            });
                                          }
                                        },
                                      );
                                    },
                                  ),
                                  const SizedBox(height: 20),
                                ],
                                
                                // Multiple Batch Selection
                                if (!_isLoadingBatches && _batches.isNotEmpty) ...[
                                  Text(
                                    'Select Batches (Multiple)',
                                        style: TextStyle(
                                      color: Theme.of(context).brightness == Brightness.dark
                                          ? Colors.white.withValues(alpha: 0.9)
                                          : AppTheme.textDark,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Container(
                                    constraints: const BoxConstraints(maxHeight: 200),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).brightness == Brightness.dark
                                          ? Colors.white.withValues(alpha: 0.1)
                                          : Colors.grey.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: Theme.of(context).brightness == Brightness.dark
                                            ? Colors.white.withValues(alpha: 0.3)
                                            : AppTheme.textGray.withValues(alpha: 0.3),
                                      ),
                                    ),
                                    child: ListView.builder(
                                      shrinkWrap: true,
                                      itemCount: _batches.length,
                                      itemBuilder: (context, index) {
                                        final batch = _batches[index];
                                        final batchId = batch['id'] as String;
                                        final isSelected = _selectedBatchIds.contains(batchId);
                                        return CheckboxListTile(
                                          title: Text(
                                            '${batch['name']} (${batch['year']})',
                                            style: TextStyle(
                                              color: Theme.of(context).brightness == Brightness.dark
                                                  ? Colors.white
                                                  : AppTheme.textDark,
                                            ),
                                          ),
                                          subtitle: Text(
                                            batch['timing'] ?? '',
                                            style: TextStyle(
                                              color: Theme.of(context).brightness == Brightness.dark
                                                  ? Colors.white.withValues(alpha: 0.7)
                                                  : AppTheme.textGray,
                                          fontSize: 12,
                                        ),
                                          ),
                                          value: isSelected,
                                          onChanged: (value) {
                                            setState(() {
                                              if (value == true) {
                                                _selectedBatchIds.add(batchId);
                                              } else {
                                                _selectedBatchIds.remove(batchId);
                                              }
                                            });
                                          },
                                          activeColor: AppTheme.primaryBlue,
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                ],
                                
                                // Multiple Subject Selection
                                if (!_isLoadingSubjects && _availableSubjects.isNotEmpty) ...[
                                  Text(
                                    'Select Subjects (Multiple)',
                                    style: TextStyle(
                                      color: Theme.of(context).brightness == Brightness.dark
                                          ? Colors.white.withValues(alpha: 0.9)
                                          : AppTheme.textDark,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Container(
                                    constraints: const BoxConstraints(maxHeight: 200),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).brightness == Brightness.dark
                                          ? Colors.white.withValues(alpha: 0.1)
                                          : Colors.grey.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: Theme.of(context).brightness == Brightness.dark
                                            ? Colors.white.withValues(alpha: 0.3)
                                            : AppTheme.textGray.withValues(alpha: 0.3),
                                      ),
                                    ),
                                    child: ListView.builder(
                                      shrinkWrap: true,
                                      itemCount: _availableSubjects.length,
                                      itemBuilder: (context, index) {
                                        final subject = _availableSubjects[index];
                                        final subjectName = subject['name'] as String;
                                        final isSelected = _selectedSubjects.contains(subjectName);
                                        return CheckboxListTile(
                                          title: Text(
                                            subjectName,
                                            style: TextStyle(
                                              color: Theme.of(context).brightness == Brightness.dark
                                                  ? Colors.white
                                                  : AppTheme.textDark,
                                            ),
                                          ),
                                          value: isSelected,
                                          onChanged: (value) {
                                            setState(() {
                                              if (value == true) {
                                                _selectedSubjects.add(subjectName);
                                              } else {
                                                _selectedSubjects.remove(subjectName);
                                              }
                                            });
                                          },
                                          activeColor: AppTheme.primaryBlue,
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                ],
                                
                                // Contact Number
                                  _buildModernTextField(
                                    controller: _contactController,
                                    icon: Icons.phone_outlined,
                                    label: 'Contact Number',
                                    hint: 'Enter contact number',
                                    keyboardType: TextInputType.phone,
                                    validator: (v) => v!.isEmpty ? 'Required' : null,
                                  ),
                                  const SizedBox(height: 24),
                                  _buildFaceCaptureButton(),
                                  const SizedBox(height: 24),
                                  _buildSubmitButton(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                    },
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
            onPressed: () {
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            },
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.person_add_rounded, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Add New Student',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
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
    return Center(
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.person_add, color: AppTheme.primaryBlue, size: 40),
          ),
          const SizedBox(height: 16),
          Text(
            'Register New Student',
            style: TextStyle(
              color: isDark ? Colors.white : AppTheme.textDark,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Fill in the details below',
            style: TextStyle(
              color: isDark ? Colors.white70 : AppTheme.textGray,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernTextField({
    required TextEditingController controller,
    required IconData icon,
    required String label,
    required String hint,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      style: TextStyle(
        color: isDark ? Colors.white : AppTheme.textDark,
        fontSize: 15,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(
          color: isDark 
              ? Colors.white.withValues(alpha: 0.8) 
              : AppTheme.textDark.withValues(alpha: 0.7),
          fontSize: 14,
        ),
        hintStyle: TextStyle(
          color: isDark 
              ? Colors.white.withValues(alpha: 0.4) 
              : AppTheme.textGray.withValues(alpha: 0.6),
        ),
        prefixIcon: Icon(
          icon, 
          color: isDark 
              ? Colors.white.withValues(alpha: 0.8) 
              : AppTheme.primaryBlue,
          size: 20,
        ),
        filled: true,
        fillColor: isDark 
            ? Colors.white.withValues(alpha: 0.1) 
            : Colors.grey.shade50,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: isDark 
                ? Colors.white.withValues(alpha: 0.3) 
                : AppTheme.primaryBlue.withValues(alpha: 0.3),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: isDark 
                ? Colors.white.withValues(alpha: 0.3) 
                : AppTheme.primaryBlue.withValues(alpha: 0.3),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: isDark ? Colors.white : AppTheme.primaryBlue,
            width: 2,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppTheme.accentRed, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppTheme.accentRed, width: 2),
        ),
        errorStyle: TextStyle(
          color: AppTheme.accentRed,
          fontSize: 12,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      validator: validator,
    );
  }

  Widget _buildModernDropdown<T>({
    required T? value,
    required String label,
    required IconData icon,
    required List<DropdownMenuItem<T>> items,
    required Function(T?) onChanged,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DropdownButtonFormField<T>(
      value: value,
      style: TextStyle(
        color: isDark ? Colors.white : AppTheme.textDark,
        fontSize: 15,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          color: isDark 
              ? Colors.white.withValues(alpha: 0.8) 
              : AppTheme.textDark.withValues(alpha: 0.7),
          fontSize: 14,
        ),
        prefixIcon: Icon(
          icon, 
          color: isDark 
              ? Colors.white.withValues(alpha: 0.8) 
              : AppTheme.primaryBlue,
          size: 20,
        ),
        filled: true,
        fillColor: isDark 
            ? Colors.white.withValues(alpha: 0.1) 
            : Colors.white.withValues(alpha: 0.95),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: isDark 
                ? Colors.white.withValues(alpha: 0.3) 
                : AppTheme.primaryBlue.withValues(alpha: 0.3),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: isDark 
                ? Colors.white.withValues(alpha: 0.3) 
                : AppTheme.primaryBlue.withValues(alpha: 0.3),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: isDark ? Colors.white : AppTheme.primaryBlue,
            width: 2,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      dropdownColor: isDark ? AppTheme.primaryBlueDark : Colors.white,
      items: items,
      onChanged: onChanged,
      icon: Icon(
        Icons.arrow_drop_down,
        color: isDark 
            ? Colors.white.withValues(alpha: 0.8) 
            : AppTheme.primaryBlue,
      ),
      iconSize: 24,
    );
  }

  Widget _buildFaceCaptureButton() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark 
            ? Colors.white.withValues(alpha: 0.1) 
            : AppTheme.primaryBlue.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark 
              ? Colors.white.withValues(alpha: 0.3) 
              : AppTheme.primaryBlue.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            _facePhotoPath != null ? Icons.face_retouching_natural : Icons.face,
            color: _facePhotoPath != null 
                ? (isDark ? Colors.green : Colors.green.shade700)
                : (isDark ? Colors.white : AppTheme.primaryBlue),
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _facePhotoPath == null 
                      ? '📸 Take Photo' 
                      : '✅ Photo Captured',
                  style: TextStyle(
                    color: isDark ? Colors.white : AppTheme.textDark,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                if (_facePhotoPath == null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Take a live photo of the student (not a photo of their photo)',
                    style: TextStyle(
                      color: isDark 
                          ? Colors.white.withValues(alpha: 0.7) 
                          : AppTheme.textDark.withValues(alpha: 0.7),
                      fontSize: 12,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
                ] else ...[
                  const SizedBox(height: 4),
                  Text(
                    'Photo captured. Face recognition will be enabled later.',
                    style: TextStyle(
                      color: isDark 
                          ? Colors.green.withValues(alpha: 0.9) 
                          : Colors.green.shade700,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
                ],
              ],
            ),
          ),
          if (_facePhotoPath == null) ...[
            TextButton(
              onPressed: _isCapturingFace ? null : _captureFacePhoto,
              child: _isCapturingFace
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: isDark ? Colors.white : AppTheme.primaryBlue,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      'Capture Face Photo',
                      style: TextStyle(
                        color: isDark ? Colors.white : AppTheme.primaryBlue,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBatchTimingInfo() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Get timing from first selected batch (if any)
    String timing = 'Not set';
    if (_selectedBatchIds.isNotEmpty) {
      final firstBatch = _batches.firstWhere(
        (b) => b['id'] == _selectedBatchIds.first,
        orElse: () => {},
      );
      timing = firstBatch['timing'] as String? ?? 'Not set';
    }
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark 
              ? Colors.white.withValues(alpha: 0.2) 
              : AppTheme.primaryBlue.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.access_time,
            color: isDark 
                ? Colors.white.withValues(alpha: 0.8) 
                : AppTheme.primaryBlue,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Batch Timing',
                  style: TextStyle(
                    color: isDark 
                        ? Colors.white.withValues(alpha: 0.6) 
                        : AppTheme.textGray,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  timing,
                  style: TextStyle(
                    color: isDark 
                        ? Colors.white.withValues(alpha: 0.9) 
                        : AppTheme.textDark,
                    fontSize: 14,
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

  Widget _buildBatchSubjectsInfo() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Show selected subjects
    final subjects = _selectedSubjects;
    
    if (subjects.isEmpty) {
      return const SizedBox.shrink();
    }
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
        borderRadius: BorderRadius.circular(14),
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
                color: isDark 
                    ? Colors.white.withValues(alpha: 0.8) 
                    : AppTheme.primaryBlue,
              size: 20,
            ),
              const SizedBox(width: 12),
            Text(
                'Batch Subjects',
              style: TextStyle(
                  color: isDark 
                      ? Colors.white.withValues(alpha: 0.8) 
                      : AppTheme.textDark,
                fontSize: 14,
                  fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: subjects.map((subject) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isDark 
                      ? Colors.white.withValues(alpha: 0.1) 
                      : AppTheme.primaryBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark 
                        ? Colors.white.withValues(alpha: 0.3) 
                        : AppTheme.primaryBlue.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                subject,
                style: TextStyle(
                    color: isDark 
                        ? Colors.white.withValues(alpha: 0.9) 
                        : AppTheme.primaryBlue,
                  fontSize: 13,
                    fontWeight: FontWeight.w500,
                ),
              ),
            );
          }).toList(),
        ),
        ],
      ),
    );
  }

  Widget _buildSubmitButton() {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Colors.white, Color(0xFFF3F4F6)]),
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
        onPressed: _isLoading ? null : _submit,
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
                child: CircularProgressIndicator(color: AppTheme.primaryBlue, strokeWidth: 3),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.person_add, color: AppTheme.primaryBlue, size: 22),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                    'Add Student',
                      style: const TextStyle(
                      color: AppTheme.primaryBlue,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildGlassCard({required Widget child}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}
