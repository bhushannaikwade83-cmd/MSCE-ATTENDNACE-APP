import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/material.dart';
import '../../core/app_db.dart';
import '../../services/b2b_storage_service.dart';
import 'simplified_attendance_screen.dart';
import '../../core/utils/professional_messaging.dart';

/// Wrapper for Student Attendance Verification
/// Handles fetching registered embedding and saving attendance with verification
class StudentAttendanceVerificationWrapper extends StatefulWidget {
  final String studentId;
  final String studentName;
  final String rollNumber;
  final String instituteId;
  final VoidCallback onAttendanceSuccess;

  const StudentAttendanceVerificationWrapper({
    super.key,
    required this.studentId,
    required this.studentName,
    required this.rollNumber,
    required this.instituteId,
    required this.onAttendanceSuccess,
  });

  @override
  State<StudentAttendanceVerificationWrapper> createState() =>
      _StudentAttendanceVerificationWrapperState();
}

class _StudentAttendanceVerificationWrapperState
    extends State<StudentAttendanceVerificationWrapper> {
  bool _isLoading = true;
  List<double>? _registeredEmbedding;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchRegisteredEmbedding();
  }

  /// Fetch registered face embedding from database
  Future<void> _fetchRegisteredEmbedding() async {
    try {
      if (kDebugMode) {
        debugPrint('🔍 Fetching registered embedding...');
        debugPrint('   Student: ${widget.studentId}');
        debugPrint('   Institute: ${widget.instituteId}');
      }

      final student = await appDb
          .from('students')
          .select('id, face_embedding, face_photo_url')
          .eq('id', widget.studentId)
          .eq('institute_id', widget.instituteId)
          .maybeSingle();

      if (student == null) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'This student has not registered their face yet.';
        });

        if (!mounted) return;
        ProfessionalMessaging.showError(
          context,
          title: 'Not Registered',
          message: 'Please complete face registration first.',
        );
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) Navigator.pop(context);
        return;
      }

      // Extract embedding from database
      final faceEmbedding = student['face_embedding'];
      final faceMap = faceEmbedding is Map ? Map<String, dynamic>.from(faceEmbedding) : null;
      final embeddingData = (faceMap?['embedding'] as List?)?.cast<double>();
      if (embeddingData == null || embeddingData.isEmpty) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'No face embedding found in registration.';
        });

        if (!mounted) return;
        ProfessionalMessaging.showError(
          context,
          title: 'Invalid Registration',
          message: 'Face embedding not found. Please re-register.',
        );
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) Navigator.pop(context);
        return;
      }

      // Convert to List<double>
      final embedding = embeddingData;

      if (kDebugMode) {
        debugPrint('✅ Embedding fetched: ${embedding.length} dimensions');
      }

      setState(() {
        _registeredEmbedding = embedding;
        _isLoading = false;
      });
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error fetching embedding: $e');

      setState(() {
        _isLoading = false;
        _errorMessage = 'Error: $e';
      });

      if (!mounted) return;
      ProfessionalMessaging.showError(
        context,
        title: 'Error',
        message: 'Failed to fetch registration: $e',
      );
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Mark Attendance')),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Fetching registration...'),
            ],
          ),
        ),
      );
    }

    if (_errorMessage != null || _registeredEmbedding == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Mark Attendance')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(_errorMessage ?? 'Unknown error'),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
                label: const Text('Go Back'),
              ),
            ],
          ),
        ),
      );
    }

    return SimplifiedAttendanceScreen(
      studentId: widget.studentId,
      studentName: widget.studentName,
      rollNumber: widget.rollNumber,
      instituteId: widget.instituteId,
      onAttendanceMarked: _handleAttendanceMarked,
    );
  }

  /// Handle attendance marking - save to database with verification photo
  Future<void> _handleAttendanceMarked(
    double cosineSimilarity,
    Uint8List attendancePhotoBytes,
    bool verified,
  ) async {
    try {
      if (kDebugMode) {
        debugPrint('💾 Saving attendance record...');
        debugPrint('   Student: ${widget.studentId}');
        debugPrint('   Similarity: ${cosineSimilarity.toStringAsFixed(3)}');
        debugPrint('   Verified: $verified');
      }

      // Step 1: Upload attendance photo to B2
      if (kDebugMode) debugPrint('📤 Uploading attendance photo...');

      final now = DateTime.now();
      final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final photoPath = 'attendance/${widget.instituteId}/${widget.studentId}_${dateStr}_${now.millisecondsSinceEpoch}.jpg';

      final photoUrl = await B2BStorageService.uploadFile(
        photoPath,
        attendancePhotoBytes,
        contentType: 'image/jpeg',
      );

      if (kDebugMode) debugPrint('✅ Photo uploaded: $photoUrl');

      // Step 2: Save attendance record
      if (kDebugMode) debugPrint('💾 Saving to database...');

      final attendanceRecord = {
        'id': '${widget.studentId}_${now.millisecondsSinceEpoch}',
        'student_id': widget.studentId,
        'institute_id': widget.instituteId,
        'attendance_photo_path': photoUrl,
        'similarity_score': cosineSimilarity,
        'matched': verified,
        'attended_at': now.toIso8601String(),
        'created_at': now.toIso8601String(),
      };

      await appDb.from('attendance_records').insert(attendanceRecord);

      if (kDebugMode) {
        debugPrint('✅ Attendance saved to database');
      }

      // Show success and navigate back
      if (!mounted) return;
      ProfessionalMessaging.showSuccess(
        context,
        title: verified ? 'Attendance Marked' : 'Face Not Verified',
        message: verified
            ? '${widget.studentName}\'s attendance marked successfully! ✅'
            : 'Face did not match registration. Attendance not marked.',
      );

      await Future.delayed(const Duration(seconds: 2));
      if (mounted) {
        widget.onAttendanceSuccess();
        Navigator.pop(context, {'success': verified});
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error saving attendance: $e');

      if (!mounted) return;
      ProfessionalMessaging.showError(
        context,
        title: 'Save Error',
        message: 'Failed to save attendance: $e',
      );
    }
  }
}
