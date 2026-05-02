import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'session_monitor.dart';

/// Face ID-like scanner widget with live camera preview and scanning animation
class FaceScannerWidget extends StatefulWidget {
  final Function(String imagePath) onFaceScanned;
  final Function(List<String> imagePaths)? onMultiAngleScanned; // For multi-angle capture
  final String? title;
  final String? subtitle;
  final bool autoCapture;
  final bool multiAngleMode; // iPhone-style multi-angle capture
  final bool simpleMode; // Simple camera with manual buttons

  const FaceScannerWidget({
    super.key,
    required this.onFaceScanned,
    this.onMultiAngleScanned,
    this.title,
    this.subtitle,
    this.autoCapture = true,
    this.multiAngleMode = false, // Default to single capture
    this.simpleMode = false, // Simple manual capture mode
  });

  @override
  State<FaceScannerWidget> createState() => _FaceScannerWidgetState();
}

class _FaceScannerWidgetState extends State<FaceScannerWidget>
    with TickerProviderStateMixin {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  CameraDescription? _activeCamera;
  bool _isInitialized = false;
  bool _isScanning = false;
  String? _statusMessage;
  Face? _detectedFace;
  bool _isFaceValid = false;
  int _scanAttempts = 0;

  // Multi-angle capture state - 3 angles: front, left, right
  int _currentAngleIndex = 0;
  final List<String> _capturedAngles = [];
  final List<bool> _angleCompleted = [false, false, false]; // 3 angles: front, left, right
  final List<String> _angleInstructions = [
    'Look straight ahead',
    'Turn your head strongly to the left',
    'Turn your head strongly to the right',
  ];
  final List<Map<String, double>> _angleRequirements = [
    {'y': 0.0, 'z': 0.0, 'tolerance': 12.0}, // Front - straight ahead
    {'y': -50.0, 'z': 0.0, 'tolerance': 15.0}, // Left - strong left turn
    {'y': 50.0, 'z': 0.0, 'tolerance': 15.0}, // Right - strong right turn
  ];
  
  // Simple mode: Manual photo capture
  final List<String?> _simpleModePhotos = [null, null, null]; // Front, Left, Right
  final List<String> _simpleModeLabels = ['Front', 'Left', 'Right'];

  late AnimationController _scanAnimationController;
  late Animation<double> _scanAnimation;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Google ML Kit Face Detector - Optimized for face detection
  // Configuration:
  // - enableContours: false - Disabled for faster detection
  // - enableClassification: true - Classifies eyes open/closed, smiling
  // - enableLandmarks: true - Detects facial landmarks (eyes, nose, mouth)
  // - enableTracking: true - Tracks face across frames (better for live camera)
  // - minFaceSize: 0.05 - Minimum 5% of image size (very lenient for easier detection)
  // - performanceMode: fast - Prioritizes speed and detection rate over accuracy
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableContours: false, // Disabled for faster detection
      enableClassification: true, // Eye open/closed, smiling probability
      enableLandmarks: true, // Facial landmarks (eyes, nose, mouth, cheeks)
      enableTracking: true, // Track face across frames (better for live scanning)
      minFaceSize: 0.05, // Minimum 5% of image size (very lenient - allows smaller faces)
      performanceMode: FaceDetectorMode.fast, // Fast mode for better detection rate
    ),
  );

  Timer? _faceDetectionTimer;
  bool _isProcessingFrame = false; // Prevent overlapping captures
  DateTime? _lastFrameProcessed; // Throttle frame processing
  static const int _requiredStableFrames = 4;
  int _noFaceFrameCount = 0;
  /// Pauses app-resume PIN lock while in-app camera is active.
  bool _cameraResumeSuppressActive = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _setupAnimations();
  }

  void _setupAnimations() {
    // Scanning line animation (like Face ID)
    _scanAnimationController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat();

    _scanAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _scanAnimationController,
        curve: Curves.easeInOut,
      ),
    );

    // Pulse animation for face detection
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOut,
      ),
    );
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        setState(() {
          _statusMessage = 'No camera available';
        });
        return;
      }

      // Use front camera for face scanning
      final frontCamera = _cameras!.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras!.first,
      );
      _activeCamera = frontCamera;

      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isIOS
            ? ImageFormatGroup.bgra8888
            : ImageFormatGroup.yuv420,
      );

      await _cameraController!.initialize();
      
      if (kDebugMode) {
        debugPrint('✅ Camera initialized: ${_cameraController!.value.previewSize}');
        debugPrint('📹 Camera description: ${frontCamera.name}');
      }
      
      setState(() {
        _isInitialized = true;
        _isScanning = !widget.simpleMode;
        if (widget.simpleMode) {
          _statusMessage = 'Use the preview and capture Front, Left, and Right manually.';
        } else if (widget.multiAngleMode) {
          _statusMessage = _angleInstructions[0]; // First instruction
        } else {
          _statusMessage = 'Position your face in the frame';
        }
      });
      SessionMonitor.beginSuppressResumeLock();
      _cameraResumeSuppressActive = true;

      if (!widget.simpleMode) {
        // Start face detection with small delay to ensure camera is ready
        await Future.delayed(const Duration(milliseconds: 500));
        _startFaceDetection();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error initializing camera: $e');
      setState(() {
        _statusMessage = 'Camera error: $e';
      });
    }
  }

  void _startFaceDetection() {
    if (kDebugMode) debugPrint('🎬 Starting face detection...');
    
    // Ensure animations are running
    if (!_scanAnimationController.isAnimating) {
      _scanAnimationController.repeat();
    }
    if (!_pulseController.isAnimating) {
      _pulseController.repeat();
    }
    
    // Use camera image stream for better performance
    _cameraController!.startImageStream((CameraImage image) async {
      if (!_isScanning || _isProcessingFrame) {
        return;
      }

      // Throttle: Process max 3 frames per second (every 333ms)
      final now = DateTime.now();
      if (_lastFrameProcessed != null) {
        final timeSinceLastFrame = now.difference(_lastFrameProcessed!);
        if (timeSinceLastFrame.inMilliseconds < 333) {
          return; // Skip this frame
        }
      }
      _lastFrameProcessed = now;

      _isProcessingFrame = true;

      try {
        if (kDebugMode) debugPrint('📷 Processing frame: ${image.width}x${image.height}');
        
        // Convert CameraImage to InputImage for ML Kit
        InputImage? inputImage;
        try {
          inputImage = _cameraImageToInputImage(image);
        } catch (conversionError) {
          if (kDebugMode) {
            debugPrint('❌ Image conversion error: $conversionError');
          }
          // Skip this frame if conversion fails
          _isProcessingFrame = false;
          return;
        }
        
        if (inputImage == null) {
          _isProcessingFrame = false;
          return;
        }
        
        if (kDebugMode) debugPrint('🔍 Detecting faces...');
        
        List<Face> faces;
        try {
          faces = await _faceDetector.processImage(inputImage).timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              if (kDebugMode) debugPrint('⏱️ Face detection timeout');
              return <Face>[];
            },
          );
        } catch (detectionError) {
          if (kDebugMode) {
            debugPrint('❌ Face detector error: $detectionError');
          }
          // Don't show error to user, just skip this frame
          _isProcessingFrame = false;
          return;
        }

        if (!mounted) {
          _isProcessingFrame = false;
          return;
        }

        if (kDebugMode) debugPrint('👤 Faces detected: ${faces.length}');

        if (faces.isEmpty) {
          _noFaceFrameCount++;
          if (_noFaceFrameCount >= 3) {
            setState(() {
              _detectedFace = null;
              _isFaceValid = false;
              _statusMessage = 'No face detected. Position your face in the frame.';
              _scanAttempts = 0;
            });
          }
          _isProcessingFrame = false;
          return;
        }

        _noFaceFrameCount = 0;
        final face = faces.first;
        final qualityCheck = _checkFaceQuality(face);

        if (kDebugMode) {
          debugPrint('✅ Face quality check: ${qualityCheck['isValid']} - ${qualityCheck['message']}');
        }

        setState(() {
          _detectedFace = face;
          _isFaceValid = qualityCheck['isValid'] as bool;
          _statusMessage = qualityCheck['message'] as String;
        });

        // Auto-capture if face is valid and autoCapture is enabled
        if (_isFaceValid && widget.autoCapture) {
          if (widget.simpleMode) {
            // Simple mode: Auto-capture 3 photos (Front, Left, Right)
            await _handleSimpleModeAutoCapture();
          } else if (widget.multiAngleMode) {
            // Multi-angle mode: capture when angle matches
            if (!_angleCompleted[_currentAngleIndex]) {
              _scanAttempts++;
              if (kDebugMode) debugPrint('📊 Scan attempts: $_scanAttempts/2 for angle ${_currentAngleIndex + 1}');
              if (_scanAttempts >= _requiredStableFrames) {
                if (kDebugMode) debugPrint('🎯 Ready to capture angle ${_currentAngleIndex + 1}');
                // Mark as processing to prevent multiple captures
                _isProcessingFrame = true;
                await Future.delayed(const Duration(milliseconds: 750));
                if (_isScanning && !_angleCompleted[_currentAngleIndex]) {
                  await _captureAngle();
                }
                _scanAttempts = 0; // Reset after capture
              }
            }
          } else {
            // Single capture mode
            _scanAttempts++;
            if (kDebugMode) debugPrint('📊 Scan attempts: $_scanAttempts/2');
            if (_scanAttempts >= _requiredStableFrames) {
              if (kDebugMode) debugPrint('🎯 Ready to capture face');
              // Mark as processing to prevent multiple captures
              _isProcessingFrame = true;
              await Future.delayed(const Duration(milliseconds: 600));
              if (_isScanning) {
                await _captureFace();
              }
            }
          }
        } else {
          // Reset attempts if face becomes invalid
          if (!_isFaceValid) {
            _scanAttempts = 0;
            // Also reset simple mode attempts
            if (widget.simpleMode) {
              for (int i = 0; i < 3; i++) {
                if (_simpleModePhotos[i] == null) {
                  _simpleModeAttempts[i] = 0;
                }
              }
            }
          }
        }
      } catch (e, stackTrace) {
        if (kDebugMode) {
          debugPrint('❌ Unexpected face detection error: $e');
          debugPrint('Stack trace: $stackTrace');
        }
        // Don't show error message on every frame - only log it
        // The user will see "No face detected" if detection fails
      } finally {
        if (_isScanning) {
          _isProcessingFrame = false;
        }
      }
    });
    
    if (kDebugMode) debugPrint('✅ Face detection stream started');
  }

  /// Convert CameraImage to InputImage for ML Kit
  InputImage? _cameraImageToInputImage(CameraImage cameraImage) {
    try {
      final sensorOrientation = _activeCamera?.sensorOrientation ?? 0;
      final rotation =
          InputImageRotationValue.fromRawValue(sensorOrientation) ??
              InputImageRotation.rotation0deg;
      
      // Get image size
      final size = Size(
        cameraImage.width.toDouble(),
        cameraImage.height.toDouble(),
      );
      
      if (kDebugMode && _lastFrameProcessed == null) {
        debugPrint('📐 Image size: ${cameraImage.width}x${cameraImage.height}');
        debugPrint('📐 Planes: ${cameraImage.planes.length}');
        for (int i = 0; i < cameraImage.planes.length; i++) {
          debugPrint('  Plane $i: ${cameraImage.planes[i].bytesPerRow}x${cameraImage.planes[i].height}');
        }
      }
      
      // Most cameras use YUV420 format - convert to NV21 for ML Kit
      if (cameraImage.planes.length >= 3) {
        try {
          // YUV420 format: Convert to NV21
          final yPlane = cameraImage.planes[0];
          final uPlane = cameraImage.planes[1];
          final vPlane = cameraImage.planes[2];
          
          // Calculate NV21 bytes
          final yBytes = yPlane.bytes;
          final uBytes = uPlane.bytes;
          final vBytes = vPlane.bytes;
          
          // Validate plane sizes
          if (yBytes.isEmpty || uBytes.isEmpty || vBytes.isEmpty) {
            if (kDebugMode) debugPrint('⚠️ Empty plane data');
            return null;
          }
          
          // NV21 format: Y plane + interleaved VU plane
          // For YUV420, U and V planes are each 1/4 the size of Y plane
          // So total UV data = (Y size / 4) * 2 = Y size / 2
          // Total NV21 size = Y size + (Y size / 2) = Y size * 1.5
          final uvSize = uBytes.length; // U and V should be same size in YUV420
          final totalNv21Size = yBytes.length + (uvSize * 2);
          
          // Validate buffer size
          if (totalNv21Size <= 0 || totalNv21Size > 10 * 1024 * 1024) { // Max 10MB sanity check
            if (kDebugMode) debugPrint('⚠️ Invalid buffer size: $totalNv21Size');
            return null;
          }
          
          final nv21Bytes = Uint8List(totalNv21Size);
          
          // Copy Y plane
          if (yBytes.length > nv21Bytes.length) {
            if (kDebugMode) debugPrint('⚠️ Y plane too large: ${yBytes.length} > ${nv21Bytes.length}');
            return null;
          }
          nv21Bytes.setRange(0, yBytes.length, yBytes);
          
          // Interleave U and V planes for NV21 (VU order)
          final uvOffset = yBytes.length;
          final minLength = uBytes.length < vBytes.length ? uBytes.length : vBytes.length;
          
          // Calculate how many pairs we can fit
          final availableSpace = totalNv21Size - uvOffset;
          final maxPairs = availableSpace ~/ 2;
          final interleaveLength = minLength < maxPairs ? minLength : maxPairs;
          
          // Safety check: ensure we don't write beyond buffer
          if (uvOffset + (interleaveLength * 2) > totalNv21Size) {
            if (kDebugMode) debugPrint('⚠️ Buffer overflow risk: offset=$uvOffset, pairs=$interleaveLength, total=$totalNv21Size');
            return null;
          }
          
          for (int i = 0; i < interleaveLength; i++) {
            final vIndex = uvOffset + (i * 2);
            final uIndex = uvOffset + (i * 2) + 1;
            
            // Double-check bounds before writing
            if (vIndex < totalNv21Size && uIndex < totalNv21Size && i < vBytes.length && i < uBytes.length) {
              nv21Bytes[vIndex] = vBytes[i];     // V first
              nv21Bytes[uIndex] = uBytes[i];      // U second
            } else {
              if (kDebugMode) debugPrint('⚠️ Index out of bounds at i=$i, vIndex=$vIndex, uIndex=$uIndex');
              break;
            }
          }
          
          return InputImage.fromBytes(
            bytes: nv21Bytes,
            metadata: InputImageMetadata(
              size: size,
              rotation: rotation,
              format: InputImageFormat.nv21,
              bytesPerRow: yPlane.bytesPerRow,
            ),
          );
        } catch (nv21Error) {
          if (kDebugMode) debugPrint('❌ NV21 conversion error: $nv21Error');
          // Fallback to single plane if NV21 conversion fails
        }
      }
      
      // Fallback: Try single plane format
      if (cameraImage.planes.isNotEmpty) {
        try {
          final plane = cameraImage.planes[0];
          if (plane.bytes.isEmpty) {
            if (kDebugMode) debugPrint('⚠️ Empty plane bytes');
            return null;
          }
          
          // Try BGRA format first (common for some devices)
          return InputImage.fromBytes(
            bytes: plane.bytes,
            metadata: InputImageMetadata(
              size: size,
              rotation: rotation,
              format: InputImageFormat.bgra8888,
              bytesPerRow: plane.bytesPerRow,
            ),
          );
        } catch (bgraError) {
          if (kDebugMode) debugPrint('❌ BGRA conversion error: $bgraError');
        }
      }
      
      if (kDebugMode) debugPrint('❌ All image conversion methods failed');
      return null;
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('❌ Error converting camera image: $e');
        debugPrint('Stack trace: $stackTrace');
      }
      return null;
    }
  }

  Map<String, dynamic> _checkFaceQuality(Face face) {
    // Check face size - very lenient threshold for easier detection
    final faceSize = face.boundingBox.width * face.boundingBox.height;
    // Very lenient: reduced from 5000 to 2000 to make it much easier to detect faces
    if (faceSize < 2000) {
      if (kDebugMode) {
        debugPrint('📏 Face too small: ${faceSize.toInt()} (need 2000+)');
      }
      return {
        'isValid': false,
        'message': 'Move closer to camera',
      };
    }
    
    if (kDebugMode) {
      debugPrint('📏 Face size OK: ${face.boundingBox.width.toInt()}x${face.boundingBox.height.toInt()} = ${faceSize.toInt()}');
    }

    // Check eyes - make it more lenient (allow partially closed eyes)
    final leftEyeOpen = face.leftEyeOpenProbability ?? 0.0;
    final rightEyeOpen = face.rightEyeOpenProbability ?? 0.0;
    final avgEyeOpen = (leftEyeOpen + rightEyeOpen) / 2.0;

    if (avgEyeOpen < 0.3) { // Reduced from 0.5 to 0.3 for more lenient detection
      if (kDebugMode) {
        debugPrint('👁️ Eyes: L=${leftEyeOpen.toStringAsFixed(2)}, R=${rightEyeOpen.toStringAsFixed(2)}, Avg=${avgEyeOpen.toStringAsFixed(2)}');
      }
      return {
        'isValid': false,
        'message': 'Keep your eyes open',
      };
    }

    // For multi-angle mode, check if current angle matches requirement
    if (widget.multiAngleMode && _currentAngleIndex < _angleRequirements.length) {
      final rawAngleY = face.headEulerAngleY ?? 0.0;
      final angleY = -rawAngleY;
      final angleZ = face.headEulerAngleZ ?? 0.0;
      final requirement = _angleRequirements[_currentAngleIndex];
      final targetY = requirement['y']!;
      final targetZ = requirement['z']!;
      final tolerance = requirement['tolerance']!;

      final yDiff = (angleY - targetY).abs();
      final zDiff = (angleZ - targetZ).abs();

      // More forgiving: only check the relevant angle (Y for left/right, Z for up/down)
      bool isValid = false;
      String message = _angleInstructions[_currentAngleIndex];

      if (kDebugMode) {
        debugPrint(
          '📐 Live angle check index=$_currentAngleIndex rawY=${rawAngleY.toStringAsFixed(1)} '
          'effectiveY=${angleY.toStringAsFixed(1)} z=${angleZ.toStringAsFixed(1)}',
        );
      }
      
      if (_currentAngleIndex == 0) {
        // Center: check both Y and Z are close to 0
        isValid = yDiff <= tolerance && zDiff <= tolerance;
        if (!isValid) {
          if (yDiff > tolerance) {
            message = angleY < 0 ? 'Turn head a little to the right' : 'Turn head a little to the left';
          } else if (zDiff > tolerance) {
            message = angleZ < 0 ? 'Tilt head down more' : 'Tilt head up more';
          }
        }
      } else if (_currentAngleIndex == 1) {
        // Left: check Y is negative (left turn)
        isValid = angleY <= targetY + tolerance && angleY >= targetY - tolerance && zDiff <= tolerance;
        if (!isValid) {
          if (angleY > targetY + tolerance) {
            message = 'Turn your head more to the left';
          } else if (angleY < targetY - tolerance) {
            message = 'Turn slightly back toward center';
          } else {
            message = 'Keep head level while turning left';
          }
        }
      } else if (_currentAngleIndex == 2) {
        // Right: check Y is positive (right turn)
        isValid = angleY >= targetY - tolerance && angleY <= targetY + tolerance && zDiff <= tolerance;
        if (!isValid) {
          if (angleY < targetY - tolerance) {
            message = 'Turn your head more to the right';
          } else if (angleY > targetY + tolerance) {
            message = 'Turn slightly back toward center';
          } else {
            message = 'Keep head level while turning right';
          }
        }
      }

      if (isValid) {
        return {
          'isValid': true,
          'message': 'Perfect! Hold still...',
        };
      } else {
        return {
          'isValid': false,
          'message': message,
        };
      }
    }

    // For single capture mode, check face angle (must be looking at camera)
    final angleY = face.headEulerAngleY?.abs() ?? 0.0;
    final angleZ = face.headEulerAngleZ?.abs() ?? 0.0;
    final angleX = face.headEulerAngleX?.abs() ?? 0.0;

    if (angleY > 20 || angleZ > 20 || angleX > 20) {
      return {
        'isValid': false,
        'message': 'Look directly at camera',
      };
    }

    // All checks passed
    return {
      'isValid': true,
      'message': 'Face detected. Scanning...',
    };
  }

  Future<void> _captureFace() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      if (kDebugMode) debugPrint('❌ Camera not initialized');
      return;
    }

    if (!_isFaceValid) {
      setState(() {
        _statusMessage = 'Please position your face correctly';
      });
      return;
    }

    // Stop image stream before capturing
    try {
      await _cameraController!.stopImageStream();
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ Error stopping stream: $e');
    }
    
    setState(() {
      _isScanning = false;
      _statusMessage = 'Capturing...';
    });

    try {
      if (kDebugMode) debugPrint('📸 Taking picture...');
      final image = await _cameraController!.takePicture();
      
      if (kDebugMode) debugPrint('✅ Picture taken: ${image.path}');
      
      // Verify face is still valid in captured image
      final inputImage = InputImage.fromFilePath(image.path);
      final faces = await _faceDetector.processImage(inputImage);

      if (faces.isEmpty) {
        // Restart scanning
        _isScanning = true;
        _startFaceDetection();
        setState(() {
          _statusMessage = 'Face lost. Please try again.';
        });
        return;
      }

      // Return captured image path
      if (mounted) {
        if (kDebugMode) debugPrint('✅ Returning captured image: ${image.path}');
        widget.onFaceScanned(image.path);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error capturing face: $e');
      // Restart scanning on error
      _isScanning = true;
      _startFaceDetection();
      setState(() {
        _statusMessage = 'Capture failed. Please try again.';
      });
    }
  }

  // Simple mode: Auto-capture logic
  final Map<int, int> _simpleModeAttempts = {0: 0, 1: 0, 2: 0};
  
  Future<void> _handleSimpleModeAutoCapture() async {
    // Find next photo that needs to be captured
    int nextIndex = -1;
    for (int i = 0; i < 3; i++) {
      if (_simpleModePhotos[i] == null) {
        nextIndex = i;
        break;
      }
    }
    
    if (nextIndex == -1) {
      // All photos captured - finish
      if (!_allPhotosCaptured()) return;
      await Future.delayed(const Duration(milliseconds: 500));
      await _finishSimpleCapture();
      return;
    }
    
    // Check head angle for current photo
    if (_detectedFace != null) {
      final rawAngleY = _detectedFace!.headEulerAngleY ?? 0.0;
      final angleY = -rawAngleY;
      final angleZ = _detectedFace!.headEulerAngleZ ?? 0.0;
      
      bool angleMatches = false;
      String angleMessage = '';
      
      if (nextIndex == 0) {
        // Front: both angles should be close to 0
        angleMatches = angleY.abs() < 12 && angleZ.abs() < 12;
        if (!angleMatches) {
          if (angleY.abs() > 12) {
            angleMessage = angleY < 0 ? 'Turn right' : 'Turn left';
          } else {
            angleMessage = angleZ < 0 ? 'Look up' : 'Look down';
          }
        }
      } else if (nextIndex == 1) {
        // Left: Y should be negative (left turn)
        angleMatches = angleY < -35 && angleY > -65 && angleZ.abs() < 15;
        if (!angleMatches) {
          if (angleY > -35) {
            angleMessage = 'Turn more to the left';
          } else if (angleY < -65) {
            angleMessage = 'Turn less (back to center)';
          } else {
            angleMessage = 'Keep head level';
          }
        }
      } else if (nextIndex == 2) {
        // Right: Y should be positive (right turn)
        angleMatches = angleY > 35 && angleY < 65 && angleZ.abs() < 15;
        if (!angleMatches) {
          if (angleY < 35) {
            angleMessage = 'Turn more to the right';
          } else if (angleY > 65) {
            angleMessage = 'Turn less (back to center)';
          } else {
            angleMessage = 'Keep head level';
          }
        }
      }
      
      if (angleMatches) {
        _simpleModeAttempts[nextIndex] = (_simpleModeAttempts[nextIndex] ?? 0) + 1;
        
        if (_simpleModeAttempts[nextIndex]! >= _requiredStableFrames) {
          // Ready to capture - prevent multiple captures
          if (!_isProcessingFrame && _simpleModePhotos[nextIndex] == null) {
            _isProcessingFrame = true;
            await Future.delayed(const Duration(milliseconds: 600));
            if (_isScanning && _simpleModePhotos[nextIndex] == null) {
              await _autoCaptureSimplePhoto(nextIndex);
            }
            _simpleModeAttempts[nextIndex] = 0;
            _isProcessingFrame = false;
          }
        } else {
          setState(() {
            _statusMessage = 'Hold still... ${_simpleModeLabels[nextIndex]}';
          });
        }
      } else {
        _simpleModeAttempts[nextIndex] = 0;
        setState(() {
          _statusMessage = angleMessage.isNotEmpty ? angleMessage : 'Position face for ${_simpleModeLabels[nextIndex]}';
        });
      }
    }
  }
  
  Future<void> _autoCaptureSimplePhoto(int index) async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      if (kDebugMode) debugPrint('❌ Camera not initialized');
      return;
    }

    if (_simpleModePhotos[index] != null) {
      return; // Already captured
    }

    try {
      // Stop image stream temporarily
      await _cameraController!.stopImageStream();
      
      setState(() {
        _statusMessage = 'Capturing ${_simpleModeLabels[index]}...';
      });
      
      if (kDebugMode) debugPrint('📸 Auto-capturing photo ${_simpleModeLabels[index]}...');
      final image = await _cameraController!.takePicture();
      
      if (kDebugMode) debugPrint('✅ Photo captured: ${image.path}');
      
      setState(() {
        _simpleModePhotos[index] = image.path;
        _statusMessage = '${_simpleModeLabels[index]} captured! ${index < 2 ? "Position for ${_simpleModeLabels[index + 1]}..." : "All photos captured!"}';
      });
      
      // Restart image stream for next photo
      if (index < 2) {
        _startFaceDetection();
      } else {
        // All photos captured - finish automatically
        await Future.delayed(const Duration(milliseconds: 1000));
        await _finishSimpleCapture();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error auto-capturing photo: $e');
      // Restart detection on error
      _startFaceDetection();
      setState(() {
        _statusMessage = 'Capture failed. Retrying...';
      });
    }
  }

  // Simple mode: Take photo manually (fallback)
  Future<void> _takeSimplePhoto(int index) async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      if (kDebugMode) debugPrint('❌ Camera not initialized');
      return;
    }

    try {
      await _cameraController!.stopImageStream();
      
      if (kDebugMode) debugPrint('📸 Taking photo ${_simpleModeLabels[index]}...');
      final image = await _cameraController!.takePicture();
      
      if (kDebugMode) debugPrint('✅ Photo taken: ${image.path}');
      
      setState(() {
        _simpleModePhotos[index] = image.path;
      });
      
      _startFaceDetection();
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error taking photo: $e');
      _startFaceDetection();
    }
  }

  bool _allPhotosCaptured() {
    return _simpleModePhotos.every((photo) => photo != null);
  }

  Future<void> _finishSimpleCapture() async {
    if (!_allPhotosCaptured()) {
      return;
    }

    final capturedPaths = _simpleModePhotos.where((p) => p != null).cast<String>().toList();
    
    if (kDebugMode) {
      debugPrint('✅ All 3 photos captured. Sending to backend: $capturedPaths');
    }

    // Return all captured images
    if (mounted) {
      if (widget.onMultiAngleScanned != null) {
        widget.onMultiAngleScanned!(capturedPaths);
      } else {
        // Fallback to single callback with first image
        widget.onFaceScanned(capturedPaths.first);
      }
    }
  }

  Future<void> _captureAngle() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      if (kDebugMode) debugPrint('❌ Camera not initialized');
      return;
    }

    if (!_isFaceValid || _angleCompleted[_currentAngleIndex]) {
      if (kDebugMode) debugPrint('⚠️ Face not valid or angle already completed');
      return;
    }

    // Stop image stream temporarily for capture
    await _cameraController!.stopImageStream();
    
    setState(() {
      _statusMessage = 'Capturing angle ${_currentAngleIndex + 1}/${_angleInstructions.length}...';
    });

    try {
      if (kDebugMode) debugPrint('📸 Taking picture for angle ${_currentAngleIndex + 1}...');
      final image = await _cameraController!.takePicture();
      
      if (kDebugMode) debugPrint('✅ Picture taken for angle ${_currentAngleIndex + 1}: ${image.path}');
      
      // Verify face is still valid in captured image
      final inputImage = InputImage.fromFilePath(image.path);
      final faces = await _faceDetector.processImage(inputImage);

      if (faces.isEmpty) {
        // Restart scanning
        _isScanning = true;
        _startFaceDetection();
        setState(() {
          _statusMessage = 'Face lost. ${_angleInstructions[_currentAngleIndex]}';
        });
        return;
      }

      // Mark this angle as completed
      setState(() {
        _capturedAngles.add(image.path);
        _angleCompleted[_currentAngleIndex] = true;
      });

      if (kDebugMode) {
        debugPrint('✅ Angle ${_currentAngleIndex + 1} captured. Total: ${_capturedAngles.length}');
      }

      // Move to next angle
      if (_currentAngleIndex < _angleRequirements.length - 1) {
        // Restart image stream for next angle
        _isScanning = true;
        _startFaceDetection();
        
        setState(() {
          _currentAngleIndex++;
          _statusMessage = _angleInstructions[_currentAngleIndex];
          _scanAttempts = 0; // Reset attempts for next angle
        });
      } else {
        // All angles captured - complete!
        setState(() {
          _isScanning = false;
          _statusMessage = 'All photos captured! Processing...';
        });

        await Future.delayed(const Duration(milliseconds: 500));

        // Return all captured images
        if (mounted) {
          if (kDebugMode) {
            debugPrint('✅ All ${_capturedAngles.length} angles captured. Returning images.');
          }
          if (widget.onMultiAngleScanned != null) {
            widget.onMultiAngleScanned!(_capturedAngles);
          } else {
            // Fallback to single callback with first image
            widget.onFaceScanned(_capturedAngles.first);
          }
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error capturing angle: $e');
      // Restart scanning on error
      _isScanning = true;
      _startFaceDetection();
      setState(() {
        _statusMessage = 'Capture failed. ${_angleInstructions[_currentAngleIndex]}';
      });
    }
  }

  @override
  void dispose() {
    if (_cameraResumeSuppressActive) {
      _cameraResumeSuppressActive = false;
      Future<void>.delayed(const Duration(milliseconds: 300), () {
        SessionMonitor.endSuppressResumeLock();
      });
    }
    _faceDetectionTimer?.cancel();
    _scanAnimationController.dispose();
    _pulseController.dispose();
    // Stop image stream before disposing camera
    _cameraController?.stopImageStream();
    _cameraController?.dispose();
    _faceDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: Colors.white),
              const SizedBox(height: 20),
              Text(
                _statusMessage ?? 'Initializing camera...',
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
      );
    }

    // Simple mode: Manual camera with buttons
    if (widget.simpleMode) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            widget.title ?? 'Capture Face Photos',
            style: const TextStyle(color: Colors.white),
          ),
        ),
        body: Column(
          children: [
            // Camera preview
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CameraPreview(_cameraController!),
                  ),
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.68),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Manual Guided Capture',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _statusMessage ??
                                'Front: look straight. Left/Right: turn strongly, but keep one eye and nose slightly visible.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.86),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            // Captured photos thumbnails
            Container(
              height: 100,
              color: Colors.black.withValues(alpha: 0.8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(3, (index) {
                  final photoPath = _simpleModePhotos[index];
                  final label = _simpleModeLabels[index];
                  
                  return Column(
                    children: [
                      GestureDetector(
                        onTap: () async {
                          await _takeSimplePhoto(index);
                        },
                        child: Container(
                          width: 70,
                          height: 70,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: photoPath != null ? Colors.green : Colors.white.withValues(alpha: 0.3),
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: photoPath != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: Image.file(
                                    File(photoPath),
                                    fit: BoxFit.cover,
                                  ),
                                )
                              : Icon(
                                  Icons.camera_alt,
                                  color: Colors.white.withValues(alpha: 0.5),
                                  size: 30,
                                ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        label,
                        style: TextStyle(
                          color: photoPath != null ? Colors.green : Colors.white.withValues(alpha: 0.7),
                          fontSize: 12,
                          fontWeight: photoPath != null ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ],
                  );
                }),
              ),
            ),
            
            // Capture buttons
            Container(
              padding: const EdgeInsets.all(20),
              color: Colors.black,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Front Photo Button
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _takeSimplePhoto(0),
                      icon: Icon(_simpleModePhotos[0] != null ? Icons.refresh : Icons.camera_alt),
                      label: Text(_simpleModePhotos[0] != null ? 'Retake Front' : 'Take Front'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _simpleModePhotos[0] != null ? Colors.orange : Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Left Photo Button
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _takeSimplePhoto(1),
                      icon: Icon(_simpleModePhotos[1] != null ? Icons.refresh : Icons.camera_alt),
                      label: Text(_simpleModePhotos[1] != null ? 'Retake Left' : 'Take Left'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _simpleModePhotos[1] != null ? Colors.orange : Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Right Photo Button
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _takeSimplePhoto(2),
                      icon: Icon(_simpleModePhotos[2] != null ? Icons.refresh : Icons.camera_alt),
                      label: Text(_simpleModePhotos[2] != null ? 'Retake Right' : 'Take Right'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _simpleModePhotos[2] != null ? Colors.orange : Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            // Done button
            Container(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _allPhotosCaptured() ? _finishSimpleCapture : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _allPhotosCaptured() ? Colors.green : Colors.grey,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text(
                    'Done',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.title ?? 'Face ID Scanner',
          style: const TextStyle(color: Colors.white),
        ),
      ),
      body: Stack(
        children: [
          // Camera preview
          Positioned.fill(
            child: CameraPreview(_cameraController!),
          ),

          // Overlay with scanning UI
          Positioned.fill(
            child: AnimatedBuilder(
              animation: Listenable.merge([_scanAnimationController, _pulseController]),
              builder: (context, child) {
                return CustomPaint(
                  painter: FaceScannerOverlayPainter(
                    face: _detectedFace,
                    isValid: _isFaceValid,
                    scanAnimation: _scanAnimation.value,
                    pulseAnimation: _pulseAnimation.value,
                  ),
                );
              },
            ),
          ),

          // Status message
          Positioned(
            bottom: widget.multiAngleMode ? 150 : 100,
            left: 16,
            right: 16,
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 400),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_isFaceValid)
                      const Icon(
                        Icons.check_circle,
                        color: Colors.green,
                        size: 32,
                      )
                    else
                      const Icon(
                        Icons.face_retouching_off,
                        color: Colors.orange,
                        size: 32,
                      ),
                    const SizedBox(height: 8),
                    Text(
                      _statusMessage ?? 'Position your face',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (widget.subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        widget.subtitle!,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

          // Progress dots for multi-angle mode (iPhone-style)
          if (widget.multiAngleMode)
            Positioned(
              bottom: 80,
              left: 16,
              right: 16,
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 300),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_angleInstructions.length, (index) {
                      final isCompleted = _angleCompleted[index];
                      final isCurrent = index == _currentAngleIndex && !isCompleted;
                      
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: isCurrent ? 12 : 10,
                        height: isCurrent ? 12 : 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isCompleted
                              ? Colors.green
                              : isCurrent
                                  ? Colors.blue
                                  : Colors.white.withValues(alpha: 0.3),
                          border: isCurrent
                              ? Border.all(color: Colors.blue, width: 2)
                              : null,
                        ),
                        child: isCompleted
                            ? const Icon(
                                Icons.check,
                                size: 8,
                                color: Colors.white,
                              )
                            : null,
                      );
                    }),
                  ),
                ),
              ),
            ),

          // Manual capture button (if auto-capture is disabled)
          if (!widget.autoCapture)
            Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: Center(
                child: FloatingActionButton(
                  onPressed: _isFaceValid ? _captureFace : null,
                  backgroundColor: _isFaceValid ? Colors.green : Colors.grey,
                  child: const Icon(Icons.camera_alt, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Custom painter for Face ID-like scanning overlay
class FaceScannerOverlayPainter extends CustomPainter {
  final Face? face;
  final bool isValid;
  final double scanAnimation;
  final double pulseAnimation;

  FaceScannerOverlayPainter({
    required this.face,
    required this.isValid,
    required this.scanAnimation,
    required this.pulseAnimation,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    // Calculate circular face frame position (center of screen)
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    // Use larger radius - 50% of screen width or height (whichever is smaller), with larger min/max
    final maxRadius = size.width < size.height ? size.width * 0.5 : size.height * 0.5;
    final radius = maxRadius.clamp(150.0, 300.0); // Min 150, max 300 for larger circle
    final center = Offset(centerX, centerY);

    // Professional dimmed overlay with transparent cutout
    final fullScreen = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final cutout = Path()..addOval(Rect.fromCircle(center: center, radius: radius + 2));
    final overlayPath = Path.combine(PathOperation.difference, fullScreen, cutout);
    final overlayPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.55)
      ..style = PaintingStyle.fill;
    canvas.drawPath(overlayPath, overlayPaint);

    // Soft outer glow ring
    final glowPaint = Paint()
      ..color = (isValid ? Colors.greenAccent : Colors.white).withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawCircle(center, radius, glowPaint);

    // Draw outer circle border
    paint.color = (isValid ? Colors.greenAccent : Colors.white).withValues(alpha: 0.95);
    paint.strokeWidth = 3.0;
    canvas.drawCircle(center, radius, paint);

    // Inner thin ring for premium layered look
    final innerRingPaint = Paint()
      ..color = Colors.white.withValues(alpha: isValid ? 0.22 : 0.14)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, radius - 10, innerRingPaint);

    // Draw scanning arc animation (rotating around the circle like Face ID)
    final scanPaint = Paint()
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: 2 * math.pi,
        colors: isValid
            ? [
                Colors.greenAccent.withValues(alpha: 0.0),
                Colors.greenAccent.withValues(alpha: 0.18),
                Colors.greenAccent.withValues(alpha: 0.95),
                Colors.greenAccent.withValues(alpha: 0.18),
                Colors.greenAccent.withValues(alpha: 0.0),
              ]
            : [
                Colors.white.withValues(alpha: 0.0),
                Colors.white.withValues(alpha: 0.12),
                Colors.white.withValues(alpha: 0.7),
                Colors.white.withValues(alpha: 0.12),
                Colors.white.withValues(alpha: 0.0),
              ],
        stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
        transform: GradientRotation(scanAnimation * 2 * math.pi),
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.0
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      0,
      2 * math.pi,
      false,
      scanPaint,
    );

    // Draw pulse animation (expanding circle)
    if (isValid) {
      final pulsePaint = Paint()
        ..color = Colors.greenAccent.withValues(alpha: 0.28 * (1 - pulseAnimation))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      
      final pulseRadius = radius * (1 + pulseAnimation * 0.2); // Expand by 20%
      canvas.drawCircle(center, pulseRadius, pulsePaint);
    }

    // Draw guide dots around the circle (like Face ID)
    final dotCount = 16;
    final dotRadius = 2.8;
    final dotPaint = Paint()
      ..style = PaintingStyle.fill;
    
    for (int i = 0; i < dotCount; i++) {
      final angle = (i / dotCount) * 2 * math.pi;
      final dotX = centerX + (radius + 20) * math.cos(angle);
      final dotY = centerY + (radius + 20) * math.sin(angle);
      
      // Smooth highlight wave based on scan animation
      final wave = ((scanAnimation * dotCount - i).abs() % dotCount);
      final dotOpacity = wave < 2 ? 0.95 : (wave < 4 ? 0.65 : 0.28);
      dotPaint.color = isValid 
          ? Colors.greenAccent.withValues(alpha: dotOpacity)
          : Colors.white.withValues(alpha: 0.55 * dotOpacity);
      
      canvas.drawCircle(Offset(dotX, dotY), dotRadius, dotPaint);
    }

    // Draw detected face bounding box if available (as reference circle)
    if (face != null) {
      final faceBox = face!.boundingBox;
      final scaleX = size.width / 640; // Adjust based on camera resolution
      final scaleY = size.height / 480;

      final facePaint = Paint()
        ..color = isValid
            ? Colors.greenAccent.withValues(alpha: 0.24)
            : Colors.orangeAccent.withValues(alpha: 0.26)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      // Draw as a circle around the face center
      final faceCenterX = (faceBox.left + faceBox.width / 2) * scaleX;
      final faceCenterY = (faceBox.top + faceBox.height / 2) * scaleY;
      final faceRadius = (faceBox.width * scaleX / 2).clamp(20.0, radius);
      
      canvas.drawCircle(
        Offset(faceCenterX, faceCenterY),
        faceRadius,
        facePaint,
      );
    }
  }

  @override
  bool shouldRepaint(FaceScannerOverlayPainter oldDelegate) {
    return oldDelegate.face != face ||
        oldDelegate.isValid != isValid ||
        oldDelegate.scanAnimation != scanAnimation ||
        oldDelegate.pulseAnimation != pulseAnimation;
  }
}
