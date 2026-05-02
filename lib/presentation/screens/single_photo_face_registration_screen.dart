import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/anti_spoof_service.dart';
import '../../services/image_quality_service.dart';
import '../../services/photo_compression_service.dart';
import '../../services/face_embedding_service.dart';
import '../../services/face_recognition_service.dart';
import '../../core/utils/professional_messaging.dart';
import '../widgets/session_monitor.dart';

/// Single Photo Face Registration Screen
/// - Takes 1 photo instead of 3
/// - Applies all validation checks
/// - Extracts face embedding for attendance verification
class SinglePhotoFaceRegistrationScreen extends StatefulWidget {
  final String studentId;
  final String studentName;
  final Function(List<double>, Uint8List) onRegistrationComplete;

  const SinglePhotoFaceRegistrationScreen({
    super.key,
    required this.studentId,
    required this.studentName,
    required this.onRegistrationComplete,
  });

  @override
  State<SinglePhotoFaceRegistrationScreen> createState() =>
      _SinglePhotoFaceRegistrationScreenState();
}

class _SinglePhotoFaceRegistrationScreenState
    extends State<SinglePhotoFaceRegistrationScreen> {
  CameraController? _cameraController;
  bool _isProcessing = false;
  bool _photoTaken = false;
  File? _photoFile;
  List<double>? _faceEmbedding;
  String _statusMessage = 'Ready to register';
  static const double _frontYawMax = 10.0;
  static const double _frontRollMax = 12.0;

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
        cameras.first, // Front camera
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
      if (kDebugMode) debugPrint('✅ Face embedding service initialized');
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

      // Show image preview and start validation
      if (mounted) {
        await _validateAndRegisterPhoto();
      }
    } catch (e) {
      _showError('Capture Error', 'Failed to capture photo: $e');
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
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
        await _validateAndRegisterPhoto();
      }
    } catch (e) {
      _showError('Gallery Error', 'Failed to pick image: $e');
    } finally {
      SessionMonitor.endSuppressResumeLock();
    }
  }

  Future<void> _validateAndRegisterPhoto() async {
    if (_photoFile == null) return;

    setState(() => _isProcessing = true);

    String? tempPipelinePath;

    try {
      // Step 1: Face detection and front-angle validation
      setState(() => _statusMessage = '1️⃣ Detecting face...');
      await Future.delayed(const Duration(milliseconds: 500));

      final workPath = await FaceRecognitionService.ensureNormalizedJpegForFacePipeline(_photoFile!.path);
      if (workPath != _photoFile!.path) {
        tempPipelinePath = workPath;
        _photoFile = File(workPath);
      }

      final faceFeatures = await FaceRecognitionService.extractFaceFeatures(workPath);
      if (faceFeatures == null) {
        final detail = await FaceRecognitionService.getDiagnosticReasonForInvalidFace(workPath) ??
            'Could not use this photo. Try better lighting, one clear face, and look at the camera.';
        _showError('Face not accepted', detail);
        if (tempPipelinePath != null) {
          try {
            await File(tempPipelinePath).delete();
          } catch (_) {}
        }
        _resetPhoto();
        return;
      }

      final yaw = (faceFeatures['headEulerAngleY'] as num?)?.toDouble() ?? 0.0;
      final roll = (faceFeatures['headEulerAngleZ'] as num?)?.toDouble() ?? 0.0;
      if (yaw.abs() > _frontYawMax || roll.abs() > _frontRollMax) {
        if (tempPipelinePath != null) {
          try {
            await File(tempPipelinePath).delete();
          } catch (_) {}
        }
        _showError(
          'Look straight ahead',
          'Registration photo must be front-facing. Please look straight at the camera and keep your head upright.',
        );
        _resetPhoto();
        return;
      }

      // Step 2: Anti-Spoof Check (detect printed photos/deepfakes)
      setState(() => _statusMessage = '2️⃣ Verifying you\'re a real person...');
      if (kDebugMode) debugPrint('🔍 Checking anti-spoof...');
      final antiSpoofResult = await AntiSpoofService.checkSpoof(_photoFile!.path);

      if (!antiSpoofResult.isReal) {
        if (tempPipelinePath != null) {
          try {
            await File(tempPipelinePath).delete();
          } catch (_) {}
        }
        _showError(
          'Fake photo detected',
          '${antiSpoofResult.reason}\n\nPlease use a real person for registration.',
        );
        _resetPhoto();
        return;
      }

      // Step 3: Image Quality Check
      setState(() => _statusMessage = '3️⃣ Checking image quality...');
      if (kDebugMode) debugPrint('📊 Checking image quality...');
      final qualityResult = await ImageQualityService.checkQuality(_photoFile!.path);

      if (!qualityResult.isGood) {
        if (tempPipelinePath != null) {
          try {
            await File(tempPipelinePath).delete();
          } catch (_) {}
        }
        _showError(
          'Poor image quality',
          '${qualityResult.reason}\n\nPlease ensure good lighting and a clear face.',
        );
        _resetPhoto();
        return;
      }

      // Step 4: Photo Compression
      setState(() => _statusMessage = '4️⃣ Optimizing photo size...');
      if (kDebugMode) debugPrint('🗜️ Compressing photo...');
      final compressResult = await PhotoCompressionService.compressAndValidate(_photoFile!.path);

      if (!compressResult.isValid) {
        if (tempPipelinePath != null) {
          try {
            await File(tempPipelinePath).delete();
          } catch (_) {}
        }
        _showError(
          'Compression failed',
          compressResult.reason,
        );
        _resetPhoto();
        return;
      }

      // Step 5: Extract Face Embedding with Face-Region Cropping
      setState(() => _statusMessage = '5️⃣ Extracting face embedding...');
      if (kDebugMode) debugPrint('🧠 Extracting face embedding with face-region cropping...');

      // Extract embedding using the neural embedding method that applies face-region cropping
      _faceEmbedding = await FaceRecognitionService.extractNeuralEmbedding(_photoFile!.path, faceFeatures);

      if (_faceEmbedding == null || _faceEmbedding!.isEmpty) {
        if (tempPipelinePath != null) {
          try {
            await File(tempPipelinePath).delete();
          } catch (_) {}
        }
        _showError(
          'Could not read face data',
          'The face could not be processed. Try a clearer, brighter photo, or re-open the app and try again.',
        );
        _resetPhoto();
        return;
      }

      if (tempPipelinePath != null) {
        try {
          await File(tempPipelinePath).delete();
        } catch (_) {}
      }

      // All checks passed! ✅
      setState(() {
        _photoTaken = true;
        _statusMessage = '✅ Photo registered successfully!';
      });

      // Show success message with file size
      ProfessionalMessaging.showSuccess(
        context,
        title: 'Registration Complete',
        message:
            '${widget.studentName}\'s face registered successfully! ✅\n\nPhoto: ${compressResult.sizeKB.toStringAsFixed(1)} KB\nEmbedding: 192-dim vector',
      );

      // Call the completion callback with embedding and compressed photo bytes
      await Future.delayed(const Duration(seconds: 2));
      widget.onRegistrationComplete(_faceEmbedding!, compressResult.bytes);
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error during registration: $e');
      _showError(
        'Registration issue',
        ProfessionalMessaging.messageForFaceProcessingError(e),
      );
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
      _faceEmbedding = null;
      _statusMessage = 'Ready to register. Please try again.';
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
        title: const Text('Face Registration'),
        elevation: 0,
      ),
      body: _photoTaken ? _buildPhotoPreview() : _buildCameraView(),
    );
  }

  Widget _buildCameraView() {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return Column(
      children: [
        // Camera preview
        Expanded(
          child: CameraPreview(_cameraController!),
        ),
        // Status message
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
              // Camera and gallery buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Take photo button
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
                  // Gallery button
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
                    onPressed: () {}, // Already processing
                    icon: const Icon(Icons.check),
                    label: const Text('Registered'),
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
