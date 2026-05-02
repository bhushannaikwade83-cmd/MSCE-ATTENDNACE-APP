# 📸 Attendance Photo Angle Detection

## Feature: Photo Angle Detection During Attendance Marking

**Status:** ✅ IMPLEMENTED

---

## Overview

When students mark attendance, the system now:
1. **Detects the head angle** in the photo (LEFT 45°, FRONT, RIGHT 45°)
2. **Shows the detected angle** to the user
3. **Provides success/retake options** so users can confirm or retake if needed

---

## How It Works

### Step 1: Photo Capture
```
Student clicks "Mark Attendance"
  ↓
Camera opens (front-facing)
  ↓
Student takes photo
```

### Step 2: Validation (Existing)
```
Face detected in photo? ✅
Photo of photo detected? ❌
Liveness check passed? ✅
```

### Step 3: Angle Detection (NEW)
```
Extract face from photo
  ↓
Detect head rotation angle using headEulerAngleY
  ↓
Classify as LEFT 45°, FRONT, or RIGHT 45°
  ↓
Show detected angle in dialog
```

### Step 4: User Confirmation (NEW)
```
Dialog shows:
  ├─ 📸 Photo Angle Detected
  ├─ [Icon for angle]
  ├─ "LEFT 45°" / "FRONT" / "RIGHT 45°"
  └─ [Retake] [Confirm & Mark Attendance]

User chooses:
  ├─ Retake: Start over with camera
  └─ Confirm: Upload and mark attendance
```

### Step 5: Attendance Recording
```
Upload photo to storage
  ↓
Save attendance record with:
  ├─ Photo URL
  ├─ Timestamp
  ├─ Detected Angle  ← NEW
  └─ Student info
  ↓
Show success: "✅ Attendance Marked Successfully (FRONT)"
```

---

## Code Implementation

### File: `lib/presentation/screens/attendance_screen.dart`

#### Method 1: Detect Photo Angle
```dart
Future<String> _detectPhotoAngle(String photoPath) async {
  // Extract face from photo
  final faces = await _faceDetector.processImage(...);
  
  // Get head rotation (headEulerAngleY)
  // LEFT 45°: > 30 degrees
  // FRONT: between -30 and +30 degrees
  // RIGHT 45°: < -30 degrees
  
  return 'LEFT 45°' | 'FRONT' | 'RIGHT 45°' | 'UNKNOWN';
}
```

**Location:** Lines 309-330
**Inputs:** Photo file path
**Output:** Detected angle string

#### Method 2: Show Confirmation Dialog
```dart
Future<bool> _showAngleConfirmationDialog(
  String detectedAngle,
  String photoPath,
) async {
  // Show dialog with:
  // - Detected angle icon and text
  // - Retake button (returns false)
  // - Confirm button (returns true)
  
  return await showDialog<bool>(...);
}
```

**Location:** Lines 332-387
**Inputs:** Detected angle, photo path
**Output:** true (confirm) or false (retake)

#### Method 3: Modified Attendance Marking
Modified `_markAttendance()` method to:
1. Call `_detectPhotoAngle()` after validation
2. Call `_showAngleConfirmationDialog()` to get user input
3. If user chooses retake, recursively call `_markAttendance()` again
4. If user confirms, upload and record attendance
5. Store detected angle in attendance record

**Location:** Lines 255-283

---

## Angle Detection Classification

### LEFT 45° Profile
```
Characteristics:
  ├─ Head turned left
  ├─ Left ear visible
  ├─ Right side of face less visible
  └─ headEulerAngleY > 30°

Icon: 🔄 (rotation right icon)
```

### FRONT Full Face
```
Characteristics:
  ├─ Head facing camera directly
  ├─ Both ears equally visible
  ├─ Full face visible
  └─ headEulerAngleY between -30° and +30°

Icon: 👤 (face icon)
```

### RIGHT 45° Profile
```
Characteristics:
  ├─ Head turned right
  ├─ Right ear visible
  ├─ Left side of face less visible
  └─ headEulerAngleY < -30°

Icon: 🔄 (rotation left icon)
```

### UNKNOWN Angle
```
Characteristics:
  ├─ Face not detected
  ├─ Head angle cannot be determined
  ├─ Photo quality too low
  └─ headEulerAngleY = undefined

Action: User can retake
```

---

## User Experience Flow

### Scenario 1: User Takes Perfect Front Photo
```
1. Student clicks "Mark Attendance"
2. Camera opens
3. Student takes front-facing photo
4. System validates: ✅ Face detected, ✅ Liveness OK
5. System detects angle: ✅ "FRONT"
6. Dialog shows: 👤 "FRONT"
7. User clicks: [✅ Confirm & Mark Attendance]
8. Success: "✅ Attendance Marked Successfully (FRONT)"
```

### Scenario 2: User Takes Side Profile Photo
```
1. Student clicks "Mark Attendance"
2. Camera opens
3. Student takes left profile photo
4. System validates: ✅ Face detected, ✅ Liveness OK
5. System detects angle: ✅ "LEFT 45°"
6. Dialog shows: 🔄 "LEFT 45°"
7. User thinks: "I wanted front view"
8. User clicks: [🔄 Retake]
9. Camera opens again
10. Student takes front photo
11. System detects: ✅ "FRONT"
12. User confirms
13. Success: "✅ Attendance Marked Successfully (FRONT)"
```

### Scenario 3: User Takes Blurry Photo
```
1. Student clicks "Mark Attendance"
2. Camera opens
3. Student takes blurry photo
4. System detects angle: ❌ "UNKNOWN" (no clear face)
5. Dialog shows: ? "Could not detect angle"
6. User clicks: [🔄 Retake]
7. Camera opens again
8. Student takes clear photo
9. System detects: ✅ "FRONT"
10. Success: "✅ Attendance Marked Successfully (FRONT)"
```

---

## Attendance Record Storage

Each attendance record now includes detected angle in payload:

```dart
await appDb.from('teacher_attendance').upsert({
  'id': docId,
  'institute_id': instituteId,
  'student_id': userId,
  'date': date,
  'status': 'present',
  'verification_selfie': photoUrl,
  'payload': {
    'timestamp': timestamp,
    'markedBy': 'Student',
    'detectedAngle': 'FRONT',  // ← NEW
    'locationVerified': true,
  },
});
```

---

## Benefits

✅ **User Feedback:** Users see what angle was detected
✅ **Quality Control:** Can retake if angle is not ideal
✅ **Data Recording:** Angle stored for future analytics
✅ **Multi-angle Support:** System aware of different face angles
✅ **Better Security:** Prevents blurry/bad quality photos

---

## Technical Details

### Face Detection Library
- **Library:** Google ML Kit for Flutter
- **API:** `FaceDetector.processImage()`
- **Returns:** List of Face objects with headEulerAngleY

### headEulerAngleY Values
- **Range:** -180° to +180°
- **LEFT 45°:** > +30°
- **FRONT:** -30° to +30°
- **RIGHT 45°:** < -30°

### Platform Support
- ✅ **Android:** Full support (uses Google ML Kit)
- ✅ **iOS:** Full support (uses Google ML Kit)
- ⚠️ **Web:** Defaults to "FRONT" (no face detection on web)

---

## Error Handling

```
Scenario: Face not detected
  └─ Detected Angle: "UNKNOWN"
  └─ User Action: Click "Retake"
  └─ Result: Camera opens again

Scenario: Angle detection fails
  └─ Caught in try-catch block
  └─ Returns: "UNKNOWN"
  └─ User can still retake
```

---

## Testing Checklist

- [ ] Take FRONT facing photo
  - ✅ Detects as "FRONT"
  - ✅ Shows dialog with face icon
  - ✅ Confirm marks attendance with "FRONT" in payload

- [ ] Take LEFT profile photo (turn head left ~45°)
  - ✅ Detects as "LEFT 45°"
  - ✅ Shows dialog with rotation-right icon
  - ✅ Can retake to get different angle

- [ ] Take RIGHT profile photo (turn head right ~45°)
  - ✅ Detects as "RIGHT 45°"
  - ✅ Shows dialog with rotation-left icon
  - ✅ Confirm marks attendance with "RIGHT 45°" in payload

- [ ] Take very blurry photo
  - ✅ May detect as "UNKNOWN"
  - ✅ Can retake
  - ✅ Option to confirm anyway if needed

- [ ] Test retake multiple times
  - ✅ User can click retake multiple times
  - ✅ Camera opens each time
  - ✅ Different angles detected properly

---

## Success Message Format

After attendance is marked, user sees:
```
✅ Attendance Marked Successfully (FRONT)
✅ Attendance Marked Successfully (LEFT 45°)
✅ Attendance Marked Successfully (RIGHT 45°)
✅ Attendance Marked Successfully (UNKNOWN)
```

---

## Future Enhancements

1. **Multi-angle collection:** Require all 3 angles during attendance
2. **Angle validation:** Reject certain angles (e.g., only accept FRONT)
3. **Analytics:** Generate reports showing angle distribution
4. **Auto-detection:** Detect and suggest retake based on angle quality
5. **Angle trends:** Track if same student always uses same angle

---

## Summary

✅ **Feature Complete**
- Angle detection integrated into attendance marking
- User sees detected angle and can confirm/retake
- Angle stored in attendance record
- Clear UI feedback with icons and messages
- Error handling for edge cases

**Users now have full control over their attendance photo quality with angle feedback!**
