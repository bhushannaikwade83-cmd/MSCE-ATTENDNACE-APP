import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_db.dart';
import '../../core/student_face_embedding_utils.dart';
import '../../core/utils/professional_messaging.dart';
import '../../services/b2b_storage_service.dart';
import '../../services/face_recognition_service.dart';
import '../../services/photo_compression_service.dart';
import '../widgets/session_monitor.dart';

/// Postgres `uuid` column compatible (RFC 4122 variant 4).
String _randomUuidV4() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex =
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-${hex.substring(20, 32)}';
}

/// Re-register or add face embedding using **one** front-camera photo (device camera app).
/// No guided multi-angle flow.
class StudentFaceRegistrationWrapper extends StatefulWidget {
  final String studentId;
  final String studentName;
  final String rollNumber;
  final String instituteId;
  final VoidCallback onRegistrationSuccess;

  const StudentFaceRegistrationWrapper({
    super.key,
    required this.studentId,
    required this.studentName,
    required this.rollNumber,
    required this.instituteId,
    required this.onRegistrationSuccess,
  });

  @override
  State<StudentFaceRegistrationWrapper> createState() =>
      _StudentFaceRegistrationWrapperState();
}

class _StudentFaceRegistrationWrapperState
    extends State<StudentFaceRegistrationWrapper> {
  bool _isCheckingRegistration = true;
  bool _isSaving = false;
  bool _hasExistingRegistration = false;
  bool _allowReregister = false;

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _checkExistingRegistration();
  }

  Future<void> _checkExistingRegistration() async {
    try {
      final student = await appDb
          .from('students')
          .select('face_embedding, face_photo_url')
          .eq('id', widget.studentId)
          .eq('institute_id', widget.instituteId)
          .maybeSingle();

      final hasEmbedding = studentHasNonEmptyFaceEmbedding(
        student?['face_embedding'],
      );

      if (!mounted) return;
      setState(() {
        _hasExistingRegistration = hasEmbedding;
        _isCheckingRegistration = false;
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error checking existing face registration: $e');
      }
      if (!mounted) return;
      setState(() => _isCheckingRegistration = false);
    }
  }

  Future<void> _captureOnePhotoAndSave() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      SessionMonitor.beginSuppressResumeLock();
      XFile? picked;
      try {
        picked = await _picker.pickImage(
          source: ImageSource.camera,
          preferredCameraDevice: CameraDevice.front,
        );
      } finally {
        await Future<void>.delayed(const Duration(milliseconds: 400));
        SessionMonitor.endSuppressResumeLock();
      }

      if (picked == null) {
        if (mounted) setState(() => _isSaving = false);
        return;
      }

      final workPath =
          await FaceRecognitionService.ensureNormalizedJpegForFacePipeline(
            picked.path,
          );

      final prepared = await FaceRecognitionService.prepareFaceRegistrationOnePhoto(
        workPath,
        widget.instituteId,
        widget.rollNumber,
        widget.studentId,
      );

      if (prepared == null) {
        throw Exception(
          'Could not prepare face registration. Try a clearer photo with one face and good light.',
        );
      }

      var photoBytes = await File(workPath).readAsBytes();
      photoBytes = await PhotoCompressionService.compressPhotoBytes(photoBytes);

      final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final photoPath =
          'registrations/${widget.instituteId}/${widget.studentId}_$timestamp.jpg';
      final photoUrl = await B2BStorageService.uploadFile(
        photoPath,
        photoBytes,
        contentType: 'image/jpeg',
      );

      final committed = await FaceRecognitionService.commitFaceRegistrationOnePhoto(
        studentId: widget.studentId,
        instituteId: widget.instituteId,
        embeddingPayload: prepared.embeddingPayload,
        facePhotoUrl: photoUrl,
      );

      if (!committed) {
        throw Exception(
          'Face data could not be saved. Check network or Supabase access, then try again.',
        );
      }

      final existingRegistration = await appDb
          .from('student_registrations')
          .select('id')
          .eq('student_id', widget.studentId)
          .maybeSingle();

      final embeddingField = prepared.embeddingPayload['embedding'];
      if (embeddingField is! List) {
        throw Exception('Invalid embedding payload — cannot sync student_registrations');
      }
      final List<double> cleanEmbedding = List<double>.from(
        embeddingField.map((e) => (e as num).toDouble()),
      );

      // Canonical JSON array of JSON numbers — avoids Dart/Supabase serializers sending a non-array shape.
      final faceEmbeddingPgArray =
          jsonDecode(jsonEncode(cleanEmbedding)) as List<dynamic>;

      late final String registrationId;
      // Optional mirror row: canonical face data lives on `students` (already committed above).
      try {
        if (existingRegistration != null) {
          registrationId = existingRegistration['id']!.toString();
          await appDb
              .from('student_registrations')
              .update(<String, dynamic>{
                'student_id': widget.studentId,
                'registration_photo_path': photoUrl,
                'face_embedding': faceEmbeddingPgArray,
              })
              .eq('id', registrationId);
        } else {
          registrationId = _randomUuidV4();
          await appDb.from('student_registrations').insert(<String, dynamic>{
            'id': registrationId,
            'student_id': widget.studentId,
            'registration_photo_path': photoUrl,
            'face_embedding': faceEmbeddingPgArray,
            'created_at': DateTime.now().toUtc().toIso8601String(),
          });
        }
      } on PostgrestException catch (e) {
        if (kDebugMode) {
          debugPrint(
            '⚠️ student_registrations optional sync failed (${e.code}): ${e.message}\n'
            '   Hint: Face template is stored on students; align column type (jsonb vs float[]) or migrate.',
          );
        }
      }

      if (!mounted) return;
      ProfessionalMessaging.showSuccess(
        context,
        title: 'Registration complete',
        message:
            '${widget.studentName}\'s face was saved from one photo.\n\nReady for attendance.',
      );

      await Future<void>.delayed(const Duration(seconds: 2));
      if (mounted) {
        widget.onRegistrationSuccess();
        Navigator.pop(context, {
          'success': true,
          'registrationId': registrationId,
        });
      }
    } on DuplicateFaceRegistrationException catch (e) {
      if (!mounted) return;
      ProfessionalMessaging.showError(
        context,
        title: 'Duplicate face',
        message: e.message,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Face registration error: $e');
      if (!mounted) return;
      ProfessionalMessaging.showError(
        context,
        title: 'Registration failed',
        message: ProfessionalMessaging.messageForFaceProcessingError(e),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingRegistration) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Checking existing face registration...'),
            ],
          ),
        ),
      );
    }

    if (_hasExistingRegistration && !_allowReregister) {
      return Scaffold(
        appBar: AppBar(title: const Text('Face registration')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.verified_user, size: 56, color: Colors.green),
                const SizedBox(height: 16),
                Text(
                  '${widget.studentName} already has a saved face embedding.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Attendance uses this template. Use “Register again” only to replace it with a new photo.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Go back'),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => setState(() => _allowReregister = true),
                    child: const Text('Register again'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Face registration')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isSaving) ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                const Text('Saving face template…'),
              ] else ...[
                const Icon(
                  Icons.camera_alt_outlined,
                  size: 56,
                  color: Colors.blue,
                ),
                const SizedBox(height: 16),
                Text(
                  'One photo for ${widget.studentName}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Opens your camera once. Use the front camera, good light, one clear face.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _captureOnePhotoAndSave,
                    icon: const Icon(Icons.photo_camera),
                    label: const Text('Take registration photo'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
