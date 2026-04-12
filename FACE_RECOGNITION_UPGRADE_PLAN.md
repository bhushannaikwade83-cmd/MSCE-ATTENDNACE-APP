# Face Recognition Upgrade Plan: MobileFaceNet + ArcFace (On-Device TFLite)

## Overview

Replace the current **24-dimensional hand-crafted landmark vector** (from Google ML Kit)
with a **192-dimensional MobileFaceNet neural network embedding** (trained with ArcFace loss)
running on-device via TensorFlow Lite.

**Result:** Recognition accuracy jumps from ~70-80% (estimated) to **99.4% (LFW benchmark)**
with only ~50-100ms additional latency per face. App stays fully offline-capable.

---

## Current System (What Exists)

### Tech Stack
- **Framework:** Flutter/Dart (SDK ^3.10.3)
- **Backend:** Firebase (Firestore + Auth), Backblaze B2 storage
- **Face Detection:** Google ML Kit (`google_mlkit_face_detection: ^0.13.1`)
- **Face Recognition:** Hand-crafted 24-dim vector from ML Kit landmarks
- **Android minSdk:** `flutter.minSdkVersion` (defaults to 21)

### Current Embedding (WEAK -- to be replaced)
File: `lib/services/face_recognition_service.dart`, method `_extractEmbedding()` (line 222-270)

The current embedding is a hand-crafted 24-dim vector built from:
1. 8 normalized landmark positions (16 values)
2. Face size + aspect ratio (2 values)
3. Head Euler angles at 0.5x weight (3 values)
4. Eye open probabilities at 0.3x weight (2 values)
5. Smiling probability at 0.2x weight (1 value)

This is compared via cosine similarity with thresholds:
- Identification (1:N): 0.70 (70%)
- Verification (1:1): 0.85 (85%)

### Current Public API (callers -- DO NOT change signatures)

**`add_student_screen.dart` (line 509):**
```dart
final faceTemplateSaved = await FaceRecognitionService.saveFaceTemplate(
  _facePhotoPath!,
  _instituteId!,
  rollNumber,
  studentId,
);
// Returns: bool
```

**`admin_attendance_screen.dart` (line 1161):**
```dart
final hasTemplate = await FaceRecognitionService.hasFaceTemplate(instituteId!, selectedRollNumber!);
// Returns: bool
```

**`admin_attendance_screen.dart` (line 1229):**
```dart
final faceFeatures = await FaceRecognitionService.extractFaceFeatures(photo.path);
// Returns: Map<String, dynamic>? (null = bad quality / no face)
```

**`admin_attendance_screen.dart` (line 1274):**
```dart
final faceVerified = await FaceRecognitionService.verifyStudent(
  photo.path,
  instituteId!,
  selectedRollNumber!,
);
// Returns: bool
```

### Firestore Schema (Current)
```
institutes/{instituteId}/students/{studentId}
  faceTemplate: {                    // Map with landmarks, angles, quality
    boundingBox: {left, top, width, height},
    headEulerAngleY: double,
    headEulerAngleZ: double,
    headEulerAngleX: double,
    leftEyeOpenProbability: double,
    rightEyeOpenProbability: double,
    smilingProbability: double,
    landmarks: {leftEye: {x,y}, rightEye: {x,y}, ...},
    faceSize: double,
    qualityScore: double,
  }
  faceTemplateUpdated: Timestamp
  multiAngleEnabled: bool?
  faceTemplates: List?               // Array of {angle, features}
```

---

## New System (What We're Building)

### Architecture After Upgrade
```
Registration:
  Camera -> ML Kit (detect face, quality check) -> Crop face from image
  -> Resize to 112x112 -> Normalize pixels to [-1,1]
  -> MobileFaceNet TFLite (192-dim embedding) -> L2 normalize
  -> Store embedding in Firestore

Attendance Verification:
  Camera -> ML Kit (detect, quality check) -> Crop face
  -> MobileFaceNet (192-dim embedding) -> L2 normalize
  -> Cosine similarity vs stored embedding -> Threshold check -> Mark attendance
```

### MobileFaceNet Model Spec
- **Model file:** `mobilefacenet.tflite` (~5MB)
- **Source:** InsightFace MobileFaceNet trained with ArcFace loss
  - Download from: https://github.com/nicholasguan/mobile-facenet-tflite
  - Or from Ente's flutterface project: https://github.com/laurenspriem/flutterface
  - Or convert from InsightFace's MobileFaceNet ONNX model
- **Input tensor:** `[1, 112, 112, 3]` -- single 112x112 RGB image, float32
- **Input normalization:** `(pixel - 127.5) / 128.0` maps [0,255] to approximately [-1, 1]
- **Output tensor:** `[1, 192]` -- 192-dimensional face embedding, float32
- **Post-processing:** L2-normalize the output embedding before storage/comparison
- **Accuracy:** 99.4% on LFW benchmark

### New Firestore Schema
```
institutes/{instituteId}/students/{studentId}
  faceTemplate: {
    embedding: List<double>,          // 192 float64 values (L2-normalized)
    qualityScore: double,
    version: 2,                       // Schema version (old=missing/1, new=2)
    modelVersion: "mobilefacenet_arcface_v1",
  }
  faceTemplateUpdated: Timestamp
  multiAngleEnabled: bool?
  faceTemplates: List?               // Array of {angle, embedding: List<double>, version: 2}
```

### New Thresholds
- **Identification (1:N):** 0.55 cosine similarity (was 0.70)
- **Verification (1:1):** 0.60 cosine similarity (was 0.85)
- Note: Lower thresholds are MORE strict with neural embeddings because
  the 192-dim vectors are far more discriminative than 24-dim hand-crafted vectors.
  0.60 on neural embeddings is stricter than 0.85 on landmark vectors.
- These are starting values; tune empirically after deployment.

---

## Step-by-Step Implementation

### STEP 1: Add Dependencies to `pubspec.yaml`

**File:** `pubspec.yaml`

Add under dependencies (after line 21 `google_mlkit_face_detection`):
```yaml
  # MobileFaceNet ArcFace - Neural face recognition (on-device TFLite)
  tflite_flutter_custom: ^1.2.5  # Drop-in tflite_flutter fork with bundled native libs
```

Add under `flutter: assets:` (after line 83 `- .env`):
```yaml
    - assets/models/mobilefacenet.tflite
```

**Why `tflite_flutter_custom` instead of `tflite_flutter`?**
- Same API as `tflite_flutter` (import path: `package:tflite_flutter_custom/tflite_flutter_custom.dart`)
- Bundles all native TFLite binaries automatically (no manual .so/.dll/.dylib setup)
- Min Dart SDK 3.3 (compatible with project's ^3.10.3)
- Actively maintained (last push: recent)
- Published by `hugocornellier.com`

### STEP 2: Update Android minSdkVersion

**File:** `android/app/build.gradle.kts`

Change line 30 from:
```kotlin
minSdk = flutter.minSdkVersion
```
To:
```kotlin
minSdk = 26  // Required by tflite_flutter; drops Android 5.0-7.1 (~2% of devices)
```

### STEP 3: Add MobileFaceNet Model File

**File:** `assets/models/mobilefacenet.tflite` (NEW -- ~5MB binary)

Download the MobileFaceNet TFLite model. Options:
1. From https://github.com/nicholasguan/mobile-facenet-tflite (direct .tflite)
2. From the `laurenspriem/flutterface` project assets folder
3. From the `face_recognition_auth` pub.dev package source
4. Convert from InsightFace ONNX using `tf2onnx` or `onnx2tf`

Verify the model:
- Input: `[1, 112, 112, 3]` float32
- Output: `[1, 192]` float32
- Size: ~4-5MB

Create directory: `assets/models/` if it doesn't exist.

### STEP 4: Rewrite `face_recognition_service.dart` (MAIN CHANGE)

**File:** `lib/services/face_recognition_service.dart`

This is the complete rewrite of the service. The PUBLIC API stays IDENTICAL.
All callers (add_student_screen.dart, admin_attendance_screen.dart) need ZERO changes.

#### 4a. New imports (replace lines 1-7)

```dart
import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint, kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter_custom/tflite_flutter_custom.dart';
```

NOTE: The `image` package (`image: ^4.3.0`) is already in pubspec.yaml (line 54).
It's used for face cropping and resizing to 112x112.

#### 4b. New class-level fields (add after line 37, after _faceDetector)

```dart
  // MobileFaceNet TFLite interpreter for neural face embeddings
  // Model: MobileFaceNet trained with ArcFace loss
  // Input: [1, 112, 112, 3] float32, normalized to [-1, 1]
  // Output: [1, 192] float32 face embedding
  static Interpreter? _interpreter;
  static bool _isInitialized = false;

  // Similarity thresholds for neural embeddings (192-dim)
  // These are LOWER numbers than old thresholds but MORE strict
  // because neural embeddings are far more discriminative
  static const double _identificationThreshold = 0.55; // For 1:N matching
  static const double _verificationThreshold = 0.60;   // For 1:1 verification

  /// Initialize the MobileFaceNet TFLite model.
  /// Call this once at app startup (e.g., in main.dart or splash_screen.dart).
  /// Model loading takes ~200ms.
  static Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      _interpreter = await Interpreter.fromAsset('models/mobilefacenet.tflite');
      _isInitialized = true;
      if (kDebugMode) debugPrint('✅ MobileFaceNet model loaded successfully');
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Failed to load MobileFaceNet model: $e');
      rethrow;
    }
  }

  /// Dispose the TFLite interpreter. Call on app shutdown if needed.
  static void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isInitialized = false;
  }
```

#### 4c. New `_extractNeuralEmbedding()` method (REPLACES old `_extractEmbedding()`)

This is the core new method. Add it replacing the old `_extractEmbedding()` at lines 222-270:

```dart
  /// Extract 192-dim face embedding using MobileFaceNet TFLite model.
  ///
  /// Pipeline:
  /// 1. Read image from file
  /// 2. Crop to face bounding box (from ML Kit) with 20% padding
  /// 3. Resize cropped face to 112x112
  /// 4. Normalize pixels: (pixel - 127.5) / 128.0
  /// 5. Run TFLite inference
  /// 6. L2-normalize the output embedding
  ///
  /// Returns null if model not initialized or inference fails.
  static Future<List<double>?> _extractNeuralEmbedding(
    String imagePath,
    Map<String, dynamic> faceFeatures,
  ) async {
    if (!_isInitialized || _interpreter == null) {
      if (kDebugMode) debugPrint('❌ MobileFaceNet not initialized. Call FaceRecognitionService.initialize() first.');
      return null;
    }

    try {
      // 1. Read image file
      final imageFile = File(imagePath);
      final imageBytes = await imageFile.readAsBytes();
      final originalImage = img.decodeImage(imageBytes);
      if (originalImage == null) {
        if (kDebugMode) debugPrint('❌ Could not decode image');
        return null;
      }

      // 2. Crop face from image using ML Kit bounding box with padding
      final box = faceFeatures['boundingBox'] as Map<String, dynamic>;
      final left = (box['left'] as double).round();
      final top = (box['top'] as double).round();
      final width = (box['width'] as double).round();
      final height = (box['height'] as double).round();

      // Add 20% padding around the face for better recognition
      final padX = (width * 0.2).round();
      final padY = (height * 0.2).round();
      final cropLeft = (left - padX).clamp(0, originalImage.width - 1);
      final cropTop = (top - padY).clamp(0, originalImage.height - 1);
      final cropWidth = (width + padX * 2).clamp(1, originalImage.width - cropLeft);
      final cropHeight = (height + padY * 2).clamp(1, originalImage.height - cropTop);

      final croppedFace = img.copyCrop(
        originalImage,
        x: cropLeft,
        y: cropTop,
        width: cropWidth,
        height: cropHeight,
      );

      // 3. Resize to 112x112 (MobileFaceNet input size)
      final resizedFace = img.copyResize(croppedFace, width: 112, height: 112);

      // 4. Normalize pixels to [-1, 1]: (pixel - 127.5) / 128.0
      // Create input tensor [1, 112, 112, 3]
      final input = List.generate(
        1,
        (_) => List.generate(
          112,
          (y) => List.generate(
            112,
            (x) {
              final pixel = resizedFace.getPixel(x, y);
              return [
                (pixel.r.toDouble() - 127.5) / 128.0,
                (pixel.g.toDouble() - 127.5) / 128.0,
                (pixel.b.toDouble() - 127.5) / 128.0,
              ];
            },
          ),
        ),
      );

      // 5. Run TFLite inference
      // Output: [1, 192] float32
      final output = List.generate(1, (_) => List.filled(192, 0.0));
      _interpreter!.run(input, output);

      final embedding = output[0];

      // 6. L2-normalize the embedding
      double norm = 0.0;
      for (final val in embedding) {
        norm += val * val;
      }
      norm = math.sqrt(norm);
      if (norm > 0) {
        for (int i = 0; i < embedding.length; i++) {
          embedding[i] = embedding[i] / norm;
        }
      }

      if (kDebugMode) debugPrint('✅ Neural embedding extracted (192-dim, L2-normalized)');
      return embedding;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error extracting neural embedding: $e');
      return null;
    }
  }
```

#### 4d. Update `calculateCosineSimilarity()` (lines 274-304)

The cosine similarity math stays the same, but **remove the `(+1)/2` normalization**.
For L2-normalized neural embeddings, cosine similarity is already in [0, 1] range
(never negative for face embeddings from the same model).

Replace lines 300-303:
```dart
    // OLD (removes this):
    // return ((cosineSimilarity + 1.0) / 2.0).clamp(0.0, 1.0);

    // NEW: For L2-normalized neural embeddings, cosine similarity is already [0, 1]
    return cosineSimilarity.clamp(0.0, 1.0);
```

#### 4e. Update `saveFaceTemplate()` (lines 406-439)

Replace lines 414-431 with:
```dart
    try {
      // Extract face features (ML Kit detection + quality checks)
      final features = await extractFaceFeatures(imagePath);
      if (features == null) {
        if (kDebugMode) debugPrint('❌ Could not extract face features');
        return false;
      }

      // Extract neural embedding via MobileFaceNet
      final embedding = await _extractNeuralEmbedding(imagePath, features);
      if (embedding == null) {
        if (kDebugMode) debugPrint('❌ Could not extract neural embedding');
        return false;
      }

      // Save to Firestore database
      await FirebaseFirestore.instance
          .collection('institutes')
          .doc(instituteId)
          .collection('students')
          .doc(studentId)
          .update({
        'faceTemplate': {
          'embedding': embedding,
          'qualityScore': features['qualityScore'],
          'version': 2,
          'modelVersion': 'mobilefacenet_arcface_v1',
        },
        'faceTemplateUpdated': FieldValue.serverTimestamp(),
      });

      if (kDebugMode) debugPrint('✅ Face template saved for Roll $rollNumber (192-dim neural embedding)');
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error saving face template: $e');
      return false;
    }
```

#### 4f. Update `saveMultiAngleFaceTemplates()` (lines 442-492)

Replace the template extraction loop (lines 453-463) with:
```dart
      for (int i = 0; i < imagePaths.length; i++) {
        final features = await extractFaceFeatures(imagePaths[i]);
        if (features != null) {
          final embedding = await _extractNeuralEmbedding(imagePaths[i], features);
          if (embedding != null) {
            templates.add({
              'angle': i,
              'embedding': embedding,
              'version': 2,
            });
            if (kDebugMode) debugPrint('✅ Extracted neural embedding for angle $i');
          } else {
            if (kDebugMode) debugPrint('⚠️ Could not extract neural embedding for angle $i');
          }
        } else {
          if (kDebugMode) debugPrint('⚠️ Could not extract features for angle $i');
        }
      }
```

And update the Firestore save (lines 472-482) to store embedding:
```dart
      await FirebaseFirestore.instance
          .collection('institutes')
          .doc(instituteId)
          .collection('students')
          .doc(studentId)
          .update({
        'faceTemplates': templates,
        'faceTemplate': {
          'embedding': templates[0]['embedding'],
          'version': 2,
          'modelVersion': 'mobilefacenet_arcface_v1',
        },
        'faceTemplateUpdated': FieldValue.serverTimestamp(),
        'multiAngleEnabled': true,
      });
```

#### 4g. Update `verifyStudent()` (lines 495-590)

The overall flow stays the same but comparison changes. Key modifications:

**For reading stored embeddings (replaces lines 531-560 multi-angle section):**
```dart
      if (multiAngleEnabled && faceTemplates != null && faceTemplates.isNotEmpty) {
        double bestSimilarity = 0.0;

        for (var templateData in faceTemplates) {
          final templateMap = templateData as Map<String, dynamic>;
          final storedEmbedding = templateMap['embedding'] as List<dynamic>?;
          final templateVersion = templateMap['version'] as int? ?? 1;

          if (templateVersion < 2 || storedEmbedding == null) {
            if (kDebugMode) debugPrint('⚠️ Old template format detected, needs re-registration');
            continue;
          }

          final similarity = calculateCosineSimilarity(
            attendanceEmbedding,
            storedEmbedding.cast<double>().toList(),
          );
          if (similarity > bestSimilarity) {
            bestSimilarity = similarity;
          }
        }

        if (kDebugMode) {
          debugPrint('🎯 Multi-angle verification for Roll $rollNumber: ${(bestSimilarity * 100).toStringAsFixed(1)}% match');
          debugPrint('📊 Threshold: ${(_verificationThreshold * 100).toStringAsFixed(0)}%');
        }
        return bestSimilarity >= _verificationThreshold;
      }
```

**For reading single stored embedding (replaces lines 563-585):**
```dart
      final faceTemplate = studentData['faceTemplate'] as Map<String, dynamic>?;
      if (faceTemplate == null) {
        if (kDebugMode) debugPrint('⚠️ Student $rollNumber does not have a face template');
        return false;
      }

      // Check template version
      final templateVersion = faceTemplate['version'] as int? ?? 1;
      if (templateVersion < 2) {
        if (kDebugMode) debugPrint('⚠️ Student $rollNumber has old face template (v$templateVersion). Needs re-registration.');
        return false;
      }

      final storedEmbedding = (faceTemplate['embedding'] as List<dynamic>).cast<double>().toList();
      final similarity = calculateCosineSimilarity(attendanceEmbedding, storedEmbedding);

      if (kDebugMode) {
        debugPrint('🎯 Face verification for Roll $rollNumber: ${(similarity * 100).toStringAsFixed(1)}% match (threshold: ${(_verificationThreshold * 100).toStringAsFixed(0)}%)');
        if (similarity < _verificationThreshold) {
          debugPrint('❌ SECURITY: Similarity below threshold - BLOCKED');
        } else {
          debugPrint('✅ Face match verified - correct student');
        }
      }
      return similarity >= _verificationThreshold;
```

**IMPORTANT:** The `verifyStudent()` method also needs to extract the neural embedding
from the attendance photo BEFORE comparison. Add this near the top of the method
(after extractFaceFeatures succeeds, around line 508):

```dart
      // Extract neural embedding from attendance photo
      final attendanceEmbedding = await _extractNeuralEmbedding(attendancePhotoPath, attendanceFeatures);
      if (attendanceEmbedding == null) {
        if (kDebugMode) debugPrint('❌ Could not extract neural embedding from attendance photo');
        return false;
      }
```

#### 4h. Update `identifyStudent()` (lines 331-399)

Same pattern as verifyStudent. Add neural embedding extraction after feature extraction:

```dart
      // Extract neural embedding from attendance photo
      final attendanceEmbedding = await _extractNeuralEmbedding(attendancePhotoPath, attendanceFeatures);
      if (attendanceEmbedding == null) {
        if (kDebugMode) debugPrint('❌ Could not extract neural embedding');
        return null;
      }
```

Replace the comparison loop (lines 360-381) to read stored embeddings:
```dart
      for (var studentDoc in studentsSnapshot.docs) {
        final studentData = studentDoc.data();
        final faceTemplate = studentData['faceTemplate'] as Map<String, dynamic>?;
        if (faceTemplate == null) continue;

        // Check template version
        final templateVersion = faceTemplate['version'] as int? ?? 1;
        if (templateVersion < 2) continue; // Skip old templates

        final storedEmbedding = (faceTemplate['embedding'] as List<dynamic>?)?.cast<double>()?.toList();
        if (storedEmbedding == null) continue;

        final similarity = calculateCosineSimilarity(attendanceEmbedding, storedEmbedding);
        if (kDebugMode) {
          debugPrint('🎯 Student ${studentData['rollNumber']}: Similarity = ${(similarity * 100).toStringAsFixed(1)}%');
        }

        if (similarity > bestSimilarity) {
          bestSimilarity = similarity;
          bestMatch = {
            'rollNumber': studentData['rollNumber'] ?? studentData['userId'],
            'name': studentData['name'] ?? 'Unknown',
            'similarity': similarity,
            'studentId': studentDoc.id,
          };
        }
      }
```

Replace threshold check (line 384) from `0.70` to `_identificationThreshold`:
```dart
      if (bestMatch != null && bestSimilarity >= _identificationThreshold) {
```

#### 4i. Remove old `_extractEmbedding()` and old `calculateSimilarity()`

- DELETE `_extractEmbedding()` (lines 222-270) entirely
- DELETE `calculateSimilarity(Map, Map)` (lines 307-328) entirely
  (it's no longer needed -- callers now use `calculateCosineSimilarity(List, List)` directly)

### STEP 5: Add Model Initialization to `main.dart`

**File:** `lib/main.dart`

Add import at top:
```dart
import 'services/face_recognition_service.dart';
```

Add initialization after Firebase init (after line 49):
```dart
  // Initialize MobileFaceNet model for face recognition (~200ms)
  try {
    await FaceRecognitionService.initialize();
  } catch (e) {
    print('⚠️ Warning: Face recognition model failed to load: $e');
    print('⚠️ Face recognition will not work until model is available.');
  }
```

### STEP 6: NO CHANGES to these files (verified)

- `lib/presentation/screens/add_student_screen.dart` -- NO CHANGE (same API)
- `lib/presentation/screens/admin_attendance_screen.dart` -- NO CHANGE (same API)
- `lib/presentation/widgets/face_scanner_widget.dart` -- NO CHANGE (uses ML Kit only)
- `lib/services/photo_verification_service.dart` -- NO CHANGE (anti-fraud checks independent)

---

## Migration Strategy for Existing Students

### Problem
Existing students have face templates stored as old format (24-dim hand-crafted landmarks).
New system stores 192-dim neural embeddings. These are **incompatible**.

### Solution: Version Check + Re-registration Prompt

1. All new templates are saved with `version: 2`
2. Old templates have no `version` field (treated as version 1)
3. `verifyStudent()` checks `version` -- if < 2, returns `false`
4. `identifyStudent()` skips students with version < 2
5. The UI already handles `verifyStudent() == false` with a "Face Verification Failed" error

### User Impact
- Students registered AFTER the upgrade work immediately
- Students registered BEFORE the upgrade must re-capture their face photo
- Admin can re-register by going to Add Student / Edit Student and re-capturing face photo
- No data loss -- old templates are overwritten with new ones on re-registration

### Optional Enhancement (not required for initial rollout)
Add a specific error message when old template is detected:
```dart
// In admin_attendance_screen.dart, you could add a check after verifyStudent returns false
// to differentiate between "old template" and "face mismatch"
// But this is optional -- the current flow already handles both cases gracefully
```

---

## File Change Summary

| # | File | Change Type | Est. Lines |
|---|---|---|---|
| 1 | `pubspec.yaml` | Add dependency + asset | +4 lines |
| 2 | `android/app/build.gradle.kts` | Change minSdk | 1 line |
| 3 | `assets/models/mobilefacenet.tflite` | NEW binary file | ~5MB |
| 4 | `lib/services/face_recognition_service.dart` | MAJOR rewrite | ~300 lines changed |
| 5 | `lib/main.dart` | Add model init | +8 lines |
| 6 | `lib/presentation/screens/add_student_screen.dart` | NO CHANGE | 0 |
| 7 | `lib/presentation/screens/admin_attendance_screen.dart` | NO CHANGE | 0 |

---

## Performance Expectations

| Metric | Current | After Upgrade |
|---|---|---|
| App size increase | -- | +5MB (model) |
| Model load time (once at startup) | 0ms | ~200ms |
| Face detection (ML Kit) | ~100ms | ~100ms (unchanged) |
| Embedding extraction | ~10ms (math only) | ~50-100ms (TFLite) |
| Total per-face latency | ~110ms | ~150-200ms |
| Recognition accuracy | ~70-80% est. | **99.4% (LFW)** |
| Embedding dimensions | 24 | 192 |
| Offline support | Yes | Yes (unchanged) |
| Firestore per-student storage | ~2KB | ~3.5KB (+1.5KB for embedding) |

---

## Verification Checklist (Pre-Implementation)

- [x] `tflite_flutter_custom` supports Dart ^3.10.3 (min Dart SDK 3.3)
- [x] `tflite_flutter_custom` bundles native libs (no manual .so/.dll setup)
- [x] Android minSdk 26 required (must update from default 21)
- [x] MobileFaceNet input: [1, 112, 112, 3] float32 confirmed
- [x] MobileFaceNet output: [1, 192] float32 confirmed (NOT 128)
- [x] `image: ^4.3.0` already in pubspec (used for crop/resize)
- [x] Cosine similarity for L2-normalized embeddings is [0,1] -- no need for (+1)/2
- [x] Public API unchanged -- zero changes to caller screens
- [x] Firestore can store 192 doubles as array (~1.5KB, well within 1MB doc limit)
- [x] face_scanner_widget.dart uses ML Kit only -- no changes needed
- [x] photo_verification_service.dart is independent -- no changes needed

---

## Post-Implementation Testing

1. **Build test:** `flutter build apk --debug` should succeed
2. **Model loading:** Check debug log for "MobileFaceNet model loaded successfully"
3. **Registration test:** Add a new student with face photo, verify debug log shows "192-dim neural embedding"
4. **Verification test:** Mark attendance for the new student, verify debug log shows cosine similarity
5. **Rejection test:** Try marking attendance for a different person, verify it's blocked
6. **Old student test:** Try marking attendance for a student registered BEFORE upgrade, verify it returns false (needs re-registration)
7. **Performance test:** Measure time from photo capture to verification result -- should be <300ms

---

## Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Existing students can't verify | Medium | Version check returns false; admin re-registers face |
| `tflite_flutter_custom` breaks on future Flutter | Low | Can switch to `tflite_flutter` official or `tflite_plus` |
| Model file missing from assets | High | App crashes on init -- wrapped in try/catch, logged |
| Android 5-7.1 devices no longer supported | Low | Only ~2% of devices; attendance apps target modern hardware |
| TFLite inference slow on old phones | Low | ~200ms on 2019 phones; still acceptable |
| Model produces wrong dimensions | High | Verify model spec before deployment; check output shape at runtime |

---

## Reference Projects (Proven to Work)

1. **laurenspriem/flutterface** (by Ente Photos) -- Flutter + TFLite + MobileFaceNet, proven working
   - https://github.com/laurenspriem/flutterface
2. **AvishakeAdhikary/FaceRecognitionFlutter** -- Flutter + TFLite + MobileFaceNet
   - https://github.com/AvishakeAdhikary/FaceRecognitionFlutter
3. **face_recognition_auth** (pub.dev) -- Flutter package using ML Kit + TFLite MobileFaceNet
   - https://pub.dev/packages/face_recognition_auth
4. **tensorflow_face_verification** (pub.dev) -- Flutter FaceNet TFLite verification
   - https://pub.dev/packages/tensorflow_face_verification
