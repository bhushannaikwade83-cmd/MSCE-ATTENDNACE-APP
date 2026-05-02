import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/app_db.dart';
import '../../services/liveness_detection_service.dart';
import '../../services/anti_spoof_service.dart';
import '../../services/image_quality_service.dart';
import '../../services/photo_compression_service.dart';
import '../../services/face_embedding_service.dart';
import '../../services/face_recognition_service.dart';
import '../../utilities/professional_messaging.dart';
import '../widgets/session_monitor.dart';

/// Simplified Attendance Marking Screen
/// - Takes 1 photo
/// - Applies 5-step validation (anti-spoof, liveness, quality, compression)
/// - Extracts embedding with face-region cropping
/// - Compares with registered embedding using verifyStudent()
/// - Marks attendance only if match confirmed
class SimplifiedAttendanceScreen extends StatefulWidget {
  final String studentId;
  final String studentName;
  final String rollNumber; // Student roll number for verification
  final String instituteId; // Institute ID for institute-isolated verification
  final Function(double similarity, Uint8List photoBytes, bool verified) onAttendanceMarked;

  const SimplifiedAttendanceScreen({
    Key? key,
    required this.studentId,
    required this.studentName,
    required this.rollNumber,
    required this.instituteId,
    required this.onAttendanceMarked,
  }) : super(key: key);

  @override
  State<SimplifiedAttendanceScreen> createState() =>
      _SimplifiedAttendanceScreenState();
}

class _SimplifiedAttendanceScreenState
    extends State<SimplifiedAttendanceScreen> {
  CameraController? _cameraController;
  bool _isProcessing = false;
  File? _photoFile;
  String _statusMessage = 'Ready to mark attendance';
  bool _photoTaken = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _initializeEmbeddingService();
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _showError('No Camera', 'No camera found on this device');
        return;
      }

      _cameraController = CameraController(
        cameras.first,
        ResolutionPreset.high,
      );

      await _cameraController!.initialize();
      setState(() {});
    } catch (e) {
      _showError('Camera Error', 'Failed to initialize camera: $e');
    }
  }

  Future<void> _initializeEmbeddingService() async {
    try {
      await FaceEmbeddingService.initialize();
    } catch (e) {
      _showError('Initialization Error', 'Failed to load face model: $e');
    }
  }

  Future<void> _capturePhoto() async {
    if (_isProcessing || _cameraController == null) return;

    setState(() => _isProcessing = true);

    try {
      setState(() => _statusMessage = 'Capturing photo...');

      final image = await _cameraController!.takePicture();
      _photoFile = File(image.path);

      if (mounted) {
        setState(() => _photoTaken = true);
        await _verifyAndMarkAttendance();
      }
    } catch (e) {
      _showError('Capture Error', 'Failed to capture photo: $e');
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _pickPhotoFromGallery() async {
    // Suppress PIN lock while image picker is open
    SessionMonitor.beginSuppressResumeLock();
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);

      if (pickedFile != null) {
        _photoFile = File(pickedFile.path);
        setState(() => _photoTaken = true);
        await _verifyAndMarkAttendance();
      }
    } catch (e) {
      _showError('Gallery Error', 'Failed to pick image: $e');
    } finally {
      SessionMonitor.endSuppressResumeLock();
    }
  }

  Future<void> _verifyAndMarkAttendance() async {
    if (_photoFile == null) return;

    try {
      // Step 1: Image Quality Check (fastest, do first)
      setState(() => _statusMessage = '1️⃣ Checking image quality...');
      if (kDebugMode) debugPrint('📊 Checking attendance photo quality...');
      final qualityResult = await ImageQualityService.checkQuality(_photoFile!.path);

      if (!qualityResult.isGood) {
        _showError(
          'Poor Image Quality',
          '${qualityResult.reason}\n\nPlease ensure good lighting and a clear face view.',
        );
        _resetPhoto();
        return;
      }

      // Step 2: Liveness Detection (check if person is really there)
      setState(() => _statusMessage = '2️⃣ Verifying you\'re present (blink check)...');
      if (kDebugMode) debugPrint('👁️ Checking liveness...');
      final isBlinking = await LivenessDetectionService.isBlinking(_photoFile!.path);

      if (!isBlinking) {
        _showError(
          'Liveness Check Failed',
          'We need to see your eyes blinking.\n\nEnsure your eyes are visible and try again.',
        );
        _resetPhoto();
        return;
      }

      // Step 3: Anti-Spoof Check (detect fake photos)
      setState(() => _statusMessage = '3️⃣ Checking for spoofing...');
      if (kDebugMode) debugPrint('🔍 Checking for spoofing...');
      final antiSpoofResult = await AntiSpoofService.checkSpoof(_photoFile!.path);

      if (!antiSpoofResult.isReal) {
        _showError(
          'Fake Photo Detected',
          '${antiSpoofResult.reason}\n\nAttendance rejected. Please take a real photo.',
        );
        _resetPhoto();
        return;
      }

      // Step 4: Photo Compression
      setState(() => _statusMessage = '4️⃣ Optimizing photo...');
      if (kDebugMode) debugPrint('🗜️ Compressing photo...');
      final compressResult = await PhotoCompressionService.compressAndValidate(_photoFile!.path);

      if (!compressResult.isValid) {
        _showError(
          'Compression Failed',
          compressResult.reason,
        );
        _resetPhoto();
        return;
      }

      // Step 5: Verify Face with Face-Region Cropping
      // Uses neural embeddings with face region cropping for better accuracy
      setState(() => _statusMessage = '5️⃣ Verifying face with neural embedding...');
      if (kDebugMode) debugPrint('🧠 Verifying face using face-region cropping...');

      final verifyResult = await FaceRecognitionService.verifyStudent(
        _photoFile!.path,
        widget.instituteId,
        widget.rollNumber,
      );

      if (!verifyResult.isMatch) {
        _showError(
          'Face Verification Failed',
          verifyResult.message,
        );
        _resetPhoto();
        return;
      }

      // All checks passed! ✅ Mark attendance
      setState(() => _statusMessage = '✅ Attendance marked successfully!');

      // Extract the neural embedding for logging purposes
      // (verifyStudent already did the verification with cropping)
      final attendanceFeatures = await FaceRecognitionService.extractFaceFeatures(_photoFile!.path);
      final attendanceEmbedding = attendanceFeatures != null
          ? await FaceRecognitionService.extractNeuralEmbedding(_photoFile!.path, attendanceFeatures)
          : null;

      // Calculate similarity for display (the actual verification already happened)
      double similarity = 0.6; // Default if we can't calculate
      if (attendanceEmbedding != null) {
        // Get the registered embedding from database
        final studentData = await appDb
            .from('students')
            .select('face_embedding')
            .eq('institute_id', widget.instituteId)
            .eq('user_id', widget.rollNumber)
            .maybeSingle() ??
            await appDb
            .from('students')
            .select('face_embedding')
            .eq('institute_id', widget.instituteId)
            .eq('sr_no', widget.rollNumber)
            .maybeSingle();

        if (studentData != null && studentData['face_embedding'] is Map) {
          final embedMap = Map<String, dynamic>.from(studentData['face_embedding'] as Map);
          final registeredEmbedding = (embedMap['embedding'] as List?)?.cast<double>();
          if (registeredEmbedding != null && registeredEmbedding.isNotEmpty) {
            similarity = FaceRecognitionService.calculateCosineSimilarity(
              registeredEmbedding,
              attendanceEmbedding,
            );
          }
        }
      }

      ProfessionalMessaging.showSuccess(
        context,
        title: 'Attendance Marked',
        message: '${widget.studentName}\'s attendance marked successfully! ✅\n\nPhoto: ${compressResult.sizeKB.toStringAsFixed(1)} KB\nMatch: ${(similarity * 100).toStringAsFixed(1)}%',
      );

      // Notify parent with similarity, photo bytes, and verification status
      await Future.delayed(const Duration(seconds: 2));
      widget.onAttendanceMarked(similarity, compressResult.bytes, true);
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error during attendance: $e');
      _showError('Attendance Error', 'An error occurred: $e');
      _resetPhoto();
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  void _resetPhoto() {
    setState(() {
      _photoTaken = false;
      _photoFile = null;
      _statusMessage = 'Ready to mark attendance. Please try again.';
      _isProcessing = false;
    });
  }

  void _showError(String title, String message) {
    ProfessionalMessaging.showError(
      context,
      title: title,
      message: message,
    );
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    FaceEmbeddingService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mark Attendance'),
        elevation: 0,
      ),
      body: _photoTaken ? _buildPhotoPreview() : _buildCameraView(),
    );
  }

  Widget _buildCameraView() {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        // Camera preview
        Expanded(child: CameraPreview(_cameraController!)),
        // Status and buttons
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.grey[900],
          child: Column(
            children: [
              Text(
                _statusMessage,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  FloatingActionButton(
                    backgroundColor: Colors.blue,
                    heroTag: 'capture',
                    onPressed: _isProcessing ? null : _capturePhoto,
                    child: _isProcessing
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.camera_alt),
                  ),
                  FloatingActionButton(
                    backgroundColor: Colors.green,
                    heroTag: 'gallery',
                    onPressed: _isProcessing ? null : _pickPhotoFromGallery,
                    child: const Icon(Icons.image),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPhotoPreview() {
    return Column(
      children: [
        Expanded(
          child: Image.file(
            _photoFile!,
            fit: BoxFit.cover,
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.grey[900],
          child: Column(
            children: [
              Text(
                _statusMessage,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    onPressed: _resetPhoto,
                    icon: const Icon(Icons.close),
                    label: const Text('Retake'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.check),
                    label: const Text('Processing'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
