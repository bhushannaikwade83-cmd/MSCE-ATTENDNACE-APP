# 📸 Angle Detection Testing Guide

## Overview

The improved angle detection system now uses multiple methods to detect head angles. This guide helps you test if it's working correctly.

---

## How to Test

### Test 1: Front-Facing Photo

**Steps:**
1. Open app → Mark Attendance
2. Click "Mark Attendance" button
3. When camera opens, **face the camera directly**
4. Keep your head level (no tilting)
5. Take photo

**Expected Result:**
- Dialog shows: 👤 **"FRONT"** (or blue box)
- Message: "Your photo shows FRONT"
- Click "Confirm & Mark" to mark attendance
- Success: "✅ Attendance Marked Successfully (FRONT)"

**If not working:**
- Make sure face is centered in frame
- Ensure good lighting
- Face should be clearly visible

---

### Test 2: Left Profile (Turn Head Left ~45°)

**Steps:**
1. Open app → Mark Attendance
2. Click "Mark Attendance" button
3. When camera opens, **turn your head left** about 45 degrees
4. Left ear should be more visible
5. Right side of face less visible
6. Take photo

**Expected Result:**
- Dialog shows: 🔄 **"LEFT 45°"** (or rotation-right icon)
- Message: "Your photo shows LEFT 45°"
- Click "Confirm" or "Retake"
- Success: "✅ Attendance Marked Successfully (LEFT 45°)"

**If showing FRONT instead:**
- Turn head more (need larger angle)
- Make sure profile is clear
- Left ear should be clearly visible

---

### Test 3: Right Profile (Turn Head Right ~45°)

**Steps:**
1. Open app → Mark Attendance
2. Click "Mark Attendance" button
3. When camera opens, **turn your head right** about 45 degrees
4. Right ear should be more visible
5. Left side of face less visible
6. Take photo

**Expected Result:**
- Dialog shows: 🔄 **"RIGHT 45°"** (or rotation-left icon)
- Message: "Your photo shows RIGHT 45°"
- Click "Confirm" or "Retake"
- Success: "✅ Attendance Marked Successfully (RIGHT 45°)"

**If showing FRONT instead:**
- Turn head more (need larger angle)
- Make sure profile is clear
- Right ear should be clearly visible

---

### Test 4: Blurry Photo (Should show UNKNOWN)

**Steps:**
1. Open app → Mark Attendance
2. Click "Mark Attendance" button
3. When camera opens, **take a very blurry photo**
4. Or cover face partially
5. Take photo

**Expected Result:**
- Dialog shows: ⚠️ **"UNKNOWN"** (orange warning)
- Title: "⚠️ Angle Not Detected"
- Helpful tips displayed:
  - "Ensure face is clearly visible"
  - "Use good lighting"
  - "Face camera directly or turn head 45°"
- Button: "✅ Mark Anyway" (user can still mark)

---

### Test 5: Retake Option

**Steps:**
1. Take any photo
2. See angle detection dialog
3. Click **"🔄 Retake"** button
4. Camera should open again
5. Take a different photo

**Expected Result:**
- Camera opens again
- You can take new photo
- New angle is detected
- Different dialog appears
- You can confirm or retake again

---

## Debug Information

### Checking Debug Logs

The system logs angle detection info to debug console. Look for:

```
📐 Face angle detection:
   headEulerAngleY: 35.2
   headEulerAngleZ: 2.1
   headEulerAngleX: 5.0
   Using angle value: 35.2
```

This shows:
- **headEulerAngleY:** Head rotation left/right (main detection)
- **headEulerAngleZ:** Head tilt
- **headEulerAngleX:** Head pitch (up/down)

### Angle Thresholds

Current system uses:
```
LEFT 45°:   yaw > 20°
FRONT:      -20° ≤ yaw ≤ 20°
RIGHT 45°:  yaw < -20°
```

### Fallback Methods

If `headEulerAngleY` not available:
1. Try `headEulerAngleZ`
2. Analyze eye landmark positions
3. Determine if profile based on eye distance
4. Default to FRONT if detection fails

---

## Common Issues & Solutions

### Issue: Always showing "FRONT"

**Causes:**
- Head angle too small (need ~45° turn)
- Face detection library not reporting angles
- Fallback is correctly detecting as FRONT

**Solution:**
- Turn head more dramatically
- Check debug logs for angle values
- Ensure good lighting
- Try front-facing (should work)

---

### Issue: Showing "UNKNOWN"

**Causes:**
- Face not clearly detected
- Poor lighting
- Face partially obscured
- Very blurry photo

**Solution:**
- Use good lighting
- Ensure full face visible
- Keep photo steady
- Try with clearer shot
- User can click "Mark Anyway" to proceed

---

### Issue: Angle detected but dialog not showing

**Causes:**
- App crashed or closed
- Navigation error
- Device memory issue

**Solution:**
- Close app completely
- Reopen app
- Try again
- Check device has enough RAM

---

### Issue: Retake button not working

**Causes:**
- Navigation error
- State management issue

**Solution:**
- Close app
- Reopen
- Try marking attendance again

---

## Technical Details

### Detection Methods

#### Method 1: Head Euler Angles (Primary)
```dart
final yaw = face.headEulerAngleY ?? face.headEulerAngleZ;

if (yaw > 20) return 'LEFT 45°';
else if (yaw < -20) return 'RIGHT 45°';
else return 'FRONT';
```

#### Method 2: Landmark Analysis (Fallback)
```dart
- Get left eye and right eye positions
- Calculate eye distance
- Analyze face width
- If eyes close together = profile
- Check which eye is more visible
```

### Supported Platforms
- ✅ Android - Full support
- ✅ iOS - Full support
- ⚠️ Web - Defaults to "FRONT" (no face detection)

---

## Quick Test Checklist

- [ ] Take FRONT photo
  - ✅ Shows "FRONT"
  - ✅ Can confirm

- [ ] Take LEFT 45° photo
  - ✅ Shows "LEFT 45°"
  - ✅ Can retake or confirm

- [ ] Take RIGHT 45° photo
  - ✅ Shows "RIGHT 45°"
  - ✅ Can retake or confirm

- [ ] Take blurry photo
  - ✅ Shows "UNKNOWN"
  - ✅ Can still mark with "Mark Anyway"

- [ ] Test retake button
  - ✅ Opens camera again
  - ✅ Can take new photo

- [ ] Check success message
  - ✅ Shows angle in message
  - ✅ Message includes angle name

---

## Advanced Testing

### Test With Different Lighting
- Good lighting (should work)
- Dim lighting (may default to FRONT)
- Bright sunlight (may have glare)
- Backlit (face dark)

### Test With Different Face Sizes
- Large face (close to camera)
- Small face (far from camera)
- Face tilted up/down
- Face rotated but not profile

### Test on Different Devices
- Different phones (screen sizes)
- Different camera qualities
- Different Android/iOS versions
- Different ML Kit versions

---

## If Still Not Working

### Step 1: Check Permissions
```
- Camera permission granted? ✓
- Location permission (if needed)? ✓
```

### Step 2: Check ML Kit
```dart
- Is Google ML Kit imported? ✓
- Is FaceDetector initialized? ✓
- Can FaceDetector run on device? ✓
```

### Step 3: Check Debug Logs
```
- Do you see "📐 Face angle detection:" logs?
- What values are printed for angles?
- Any error messages?
```

### Step 4: Test with Native Camera App
```
- Can you take photos with camera app?
- Are photos clear?
- Does device support face detection?
```

### Step 5: Contact Support
If still not working:
- Provide debug logs
- Device model and OS version
- Sample photos that fail
- Expected vs actual behavior

---

## Summary

The angle detection system now:
✅ Detects FRONT, LEFT 45°, RIGHT 45° angles
✅ Shows helpful UI feedback
✅ Provides retake option
✅ Handles edge cases with UNKNOWN state
✅ Stores angle in attendance record
✅ Works on Android and iOS

**Test it and let us know if there are any issues!**
