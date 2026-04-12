# 🧪 Testing Guide: ML Kit + MobileFaceNet Architecture

## Prerequisites

### 1. Initialize MobileFaceNet Model
The MobileFaceNet TFLite model must be initialized at app startup.

**Location**: `lib/main.dart` or your app initialization file

```dart
import 'package:smart_attendance_app/services/face_recognition_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase
  await Firebase.initializeApp();
  
  // Initialize MobileFaceNet model (REQUIRED)
  await FaceRecognitionService.initialize();
  
  runApp(MyApp());
}
```

### 2. Check Model File
Ensure the TFLite model exists:
- **Path**: `assets/models/mobilefacenet.tflite`
- **Size**: ~4-5 MB
- **Format**: TFLite (TensorFlow Lite)

If missing, download from:
- MobileFaceNet trained with ArcFace loss
- Input: 112x112x3 (RGB)
- Output: 192-dim embedding

### 3. Environment Variables
Check `.env` file has:
```
FACE_RECOGNITION_API_URL=https://your-backend-url.com/api/v1
```

---

## Test 1: Face Registration

### Steps:
1. Open the app
2. Navigate to **Add Student** screen
3. Fill in student details:
   - Name
   - Roll Number
   - Batch Year
   - Subject
4. Click **Capture Face Photo**
5. Use front camera to take photo
6. Wait for processing

### Expected Results:
✅ **Success**:
- Face detected by ML Kit
- Liveness check passes (eyes open, looking at camera)
- 192-dim embedding generated
- Embedding saved to Firebase Firestore
- Image uploaded to Backblaze B2 (if configured)
- Success message: "✅ Face registered successfully"

❌ **Failure Scenarios**:
- **No face detected**: "No face detected. Position your face in the frame."
- **Liveness failed**: "Liveness check failed. Please use a live photo with eyes open."
- **Face too small**: "Face too small. Move closer to camera."
- **Face angle wrong**: "Face not looking at camera. Look straight ahead."

### Debug Logs to Check:
```dart
📸 Registering face for Roll {rollNumber}...
✅ Face features extracted successfully (Quality: 0.8)
✅ Neural embedding extracted (192-dim, L2-normalized)
✅ Face template saved for Roll {rollNumber} (192-dim neural embedding)
✅ Face registered successfully for Roll {rollNumber}
   - Embedding stored in Firestore
   - Image URL: {url or "Not uploaded"}
```

### Verify in Firebase Console:
1. Go to Firestore Database
2. Navigate to: `institutes/{instituteId}/students/{studentId}`
3. Check `faceTemplate` field:
   ```json
   {
     "embedding": [0.123, -0.456, ...], // 192 numbers
     "qualityScore": 0.8,
     "version": 2,
     "modelVersion": "mobilefacenet_arcface_v1"
   }
   ```

---

## Test 2: Face Recognition (1:N Identification)

### Steps:
1. Navigate to **Admin Attendance** screen
2. Select a subject and date
3. Click **Mark Attendance**
4. Take a photo (without selecting roll number)
5. Wait for recognition

### Expected Results:
✅ **Success**:
- Face detected
- Liveness check passes
- Embedding generated
- Best match found in Firestore
- Similarity >= 0.55 (55%)
- Student identified with name and roll number

❌ **Failure**:
- **No match found**: "No student match found. Similarity too low."
- **Multiple faces**: "Multiple faces detected. Please ensure only one person in frame."

### Debug Logs:
```dart
🔍 Recognizing student from photo...
✅ Face features extracted successfully
✅ Neural embedding extracted (192-dim, L2-normalized)
🎯 Student Roll123: Similarity = 87.5%
✅ Student identified: John Doe (Roll 123) - 87.5% match
```

### Test Cases:
1. **Same person, same photo**: Should match with high similarity (>80%)
2. **Same person, different photo**: Should match with good similarity (>60%)
3. **Different person**: Should not match or very low similarity (<50%)
4. **No registered students**: Should return null

---

## Test 3: Face Verification (1:1)

### Steps:
1. Navigate to **Admin Attendance** screen
2. Select a subject and date
3. **Select a roll number** from dropdown
4. Click **Mark Attendance**
5. Take a photo
6. Wait for verification

### Expected Results:
✅ **Success**:
- Face detected
- Liveness check passes
- Embedding generated
- Compared with selected student's embedding
- Similarity >= 0.60 (60%)
- Verification passed: "✅ Attendance marked successfully"

❌ **Failure**:
- **Face doesn't match**: "Face Recognition Failed - Face does not match registered face"
- **No face registered**: "Face Recognition Failed - Face not registered for this student"
- **Liveness failed**: "Liveness check failed. Please use a live photo."

### Debug Logs:
```dart
🎯 Face verification for Roll 123: 75.2% match (threshold: 60%)
✅ Face match verified - correct student
```

### Test Cases:
1. **Correct student**: Should verify with >60% similarity
2. **Wrong student**: Should fail verification (<60% similarity)
3. **Unregistered student**: Should fail (no face template)

---

## Test 4: Liveness Detection

### Test Blink Detection:
1. Take photo with **eyes closed**
2. Expected: ❌ "Eyes must be open. Please open your eyes."

### Test Head Movement:
1. Take photo with **head turned away** (>30 degrees)
2. Expected: ❌ "Face not looking at camera. Look straight ahead."

### Test Photo Spoofing:
1. Try using a **printed photo** of a person
2. Expected: ❌ "Liveness check failed. Please use a live photo."

### Test Live Person:
1. Take photo with **eyes open, looking at camera**
2. Expected: ✅ Liveness check passes

### Debug Logs:
```dart
🔍 Liveness Detection Results:
   Is Live: true
   Confidence: 0.85
   Eye Open Probability: 0.92
   Looking at Camera: true
   Head Pose Yaw: 5.2
   Head Pose Pitch: 3.1
```

---

## Test 5: Backend Integration

### Test Embedding Registration:
1. Register a face
2. Check backend logs for:
   ```
   ✅ Embedding received for Roll {rollNumber} (192-dim MobileFaceNet)
      Institute: {instituteId}, Student: {studentId}
      Embedding norm: 1.0000
   ```

### Test Backend Endpoint (Manual):
```bash
# Test register-embedding endpoint
curl -X POST "https://your-backend-url.com/api/v1/register-embedding" \
  -F "institute_id=test_institute" \
  -F "student_id=test_student" \
  -F "roll_number=123" \
  -F "name=Test Student" \
  -F "embedding=[0.123,-0.456,...]"  # 192 numbers
```

Expected Response:
```json
{
  "success": true,
  "message": "Embedding received (stored in Firestore, backend indexing pending)",
  "student_id": "test_student",
  "roll_number": "123"
}
```

---

## Test 6: Performance Testing

### Measure Processing Times:
1. **Face Detection**: Should be ~50-100ms
2. **Embedding Extraction**: Should be ~200ms
3. **Firestore Read**: Should be ~50-200ms
4. **Total Recognition**: Should be ~300-500ms

### Debug Logs:
```dart
⏱️ Face detection: 85ms
⏱️ Embedding extraction: 210ms
⏱️ Firestore search: 120ms
⏱️ Total: 415ms
```

### Test with Large Dataset:
1. Register 100+ students
2. Test recognition speed
3. Should still be <500ms for local Firestore search
4. For 300k+ students, use backend FAISS (when implemented)

---

## Common Issues & Troubleshooting

### Issue 1: "MobileFaceNet not initialized"
**Solution**: Add `FaceRecognitionService.initialize()` in `main.dart`

### Issue 2: "Model file not found"
**Solution**: 
- Check `assets/models/mobilefacenet.tflite` exists
- Check `pubspec.yaml` has:
  ```yaml
  assets:
    - assets/models/mobilefacenet.tflite
  ```
- Run `flutter pub get` and rebuild

### Issue 3: "No face detected"
**Solutions**:
- Ensure good lighting
- Face should be clearly visible
- Remove glasses/mask if needed
- Move closer to camera

### Issue 4: "Liveness check failed"
**Solutions**:
- Ensure eyes are open
- Look directly at camera
- Use live photo (not printed photo)
- Good lighting required

### Issue 5: "Embedding dimension mismatch"
**Solution**: Ensure using 192-dim MobileFaceNet, not 512-dim ArcFace

### Issue 6: "Firestore permission denied"
**Solution**: Check Firestore security rules allow read/write

### Issue 7: "Backblaze B2 upload failed"
**Solution**: 
- Check B2 credentials in `b2b_storage_config.dart`
- Check network connection
- Non-critical (embedding still saved to Firestore)

---

## Automated Testing

### Unit Tests:
```dart
// test/services/mlkit_facenet_service_test.dart
void main() {
  test('Face registration saves embedding to Firestore', () async {
    // Test implementation
  });
  
  test('Face recognition finds correct student', () async {
    // Test implementation
  });
  
  test('Liveness detection rejects printed photos', () async {
    // Test implementation
  });
}
```

### Integration Tests:
1. Test full registration flow
2. Test recognition flow
3. Test verification flow
4. Test error handling

---

## Test Checklist

- [ ] MobileFaceNet model initialized
- [ ] Face registration works
- [ ] Face recognition works (1:N)
- [ ] Face verification works (1:1)
- [ ] Liveness detection works (blink + head movement)
- [ ] Embeddings saved to Firestore
- [ ] Images uploaded to Backblaze B2
- [ ] Backend endpoints respond correctly
- [ ] Error handling works
- [ ] Performance is acceptable (<500ms)

---

## Next Steps After Testing

1. **If all tests pass**: Remove old `ArcFaceBackendService` references
2. **If backend FAISS needed**: Implement 192-dim FAISS index
3. **If performance issues**: Optimize Firestore queries or use backend FAISS
4. **If accuracy issues**: Adjust similarity thresholds

---

## Support

If you encounter issues:
1. Check debug logs in Flutter console
2. Check backend logs
3. Check Firebase Console for data
4. Review `ARCHITECTURE_MIGRATION_COMPLETE.md` for architecture details
