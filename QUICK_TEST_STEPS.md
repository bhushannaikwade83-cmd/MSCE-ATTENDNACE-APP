# ⚡ Quick Testing Steps

## ✅ Pre-Flight Check

1. **Model File**: Check `assets/models/mobilefacenet.tflite` exists
2. **Initialization**: Already done in `lib/main.dart` (line 54)
3. **Firebase**: Should be initialized
4. **Backend URL**: Check `.env` file has `FACE_RECOGNITION_API_URL`

---

## 🚀 Quick Test (5 Minutes)

### Step 1: Register a Test Student
1. Open app → Login
2. Go to **Add Student**
3. Fill:
   - Name: "Test Student"
   - Roll Number: "TEST001"
   - Batch Year: "2024"
   - Subject: Any subject
4. Click **Capture Face Photo**
5. Take a clear photo (eyes open, looking at camera)
6. Wait for "✅ Face registered successfully"

**Check Console Logs:**
```
📸 Registering face for Roll TEST001...
✅ Face features extracted successfully
✅ Neural embedding extracted (192-dim, L2-normalized)
✅ Face template saved for Roll TEST001
✅ Face registered successfully
```

### Step 2: Verify in Firebase
1. Go to Firebase Console → Firestore
2. Navigate: `institutes/{yourInstituteId}/students/{studentId}`
3. Check `faceTemplate` field exists with:
   - `embedding`: Array of 192 numbers
   - `version`: 2
   - `modelVersion`: "mobilefacenet_arcface_v1"

### Step 3: Test Recognition
1. Go to **Admin Attendance**
2. Select subject and date
3. Click **Mark Attendance**
4. **Don't select roll number** (for 1:N recognition)
5. Take photo of same person
6. Should identify: "Test Student (Roll TEST001)"

**Check Console Logs:**
```
🔍 Recognizing student from photo...
✅ Face features extracted successfully
✅ Neural embedding extracted
🎯 Student TEST001: Similarity = 85.2%
✅ Student identified: Test Student (Roll TEST001) - 85.2% match
```

### Step 4: Test Verification
1. Go to **Admin Attendance**
2. Select subject and date
3. **Select "TEST001"** from roll number dropdown
4. Click **Mark Attendance**
5. Take photo of same person
6. Should verify: "✅ Attendance marked successfully"

**Check Console Logs:**
```
🎯 Face verification for Roll TEST001: 85.2% match (threshold: 60%)
✅ Face match verified - correct student
```

### Step 5: Test Wrong Person (Security)
1. Go to **Admin Attendance**
2. Select "TEST001"
3. Take photo of **different person**
4. Should fail: "❌ Face Recognition Failed"

**Check Console Logs:**
```
🎯 Face verification for Roll TEST001: 35.1% match (threshold: 60%)
❌ SECURITY: Similarity below threshold - BLOCKED
```

---

## 🐛 Troubleshooting

### "MobileFaceNet not initialized"
- **Fix**: Already initialized in `main.dart` line 54
- **If still error**: Check model file exists at `assets/models/mobilefacenet.tflite`

### "No face detected"
- **Fix**: Better lighting, remove glasses, face camera directly

### "Liveness check failed"
- **Fix**: Eyes must be open, look at camera, use live photo (not printed)

### "Face recognition failed"
- **Check**: Is face registered? Check Firebase Firestore
- **Check**: Is it the same person? Similarity might be too low

### "Embedding dimension mismatch"
- **Fix**: Ensure using MobileFaceNet (192-dim), not ArcFace (512-dim)

---

## 📊 Expected Performance

- **Face Detection**: 50-100ms
- **Embedding Extraction**: 200ms
- **Firestore Search**: 50-200ms
- **Total**: 300-500ms

---

## ✅ Success Criteria

- [x] Face registration works
- [x] Face recognition works (finds correct student)
- [x] Face verification works (matches selected student)
- [x] Wrong person is rejected
- [x] Liveness detection works
- [x] Embeddings saved to Firestore
- [x] Performance < 500ms

---

## 🎯 Next: Full Testing

See `TESTING_GUIDE.md` for comprehensive testing scenarios.
