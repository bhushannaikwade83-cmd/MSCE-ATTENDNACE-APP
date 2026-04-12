# 📋 Complete Error & Success Messages Documentation

## 🎯 Face Recognition Messages

### ✅ **SUCCESS: Face Recognition Passed**
**When:** Face matches the selected student (similarity ≥ 80%)

**Message:** (No visible message - proceeds to attendance marking)

**Debug Log:**
```
✅ Face ID verification passed for Roll [ROLL_NUMBER] - correct student confirmed
```

---

### ❌ **ERROR 1: Face Recognition Failed**
**When:** 
- No face detected in photo
- Face not registered for student
- Face similarity < 80% (below threshold)
- Backend API error

**Message:**
```
❌ Face Recognition Failed

Possible reasons:
• Face not registered for this student
• Face does not match registered face
• No face detected in photo

Please ensure:
• Student face is registered first
• The CORRECT student is present
• Good lighting and clear face view
• Looking directly at camera
```

**Color:** 🔴 Red  
**Duration:** 10 seconds  
**Icon:** ⚠️ Error icon

---

### 🔒 **ERROR 2: Wrong Student Detected (SECURITY)**
**When:** Face recognized but roll number doesn't match selected student

**Message:**
```
❌ SECURITY: Wrong Student Detected

Face recognized as: [STUDENT_NAME] (Roll [DETECTED_ROLL])
But selected: Roll [SELECTED_ROLL]

SECURITY BLOCKED: Wrong person detected!
```

**Color:** 🔴 Red  
**Duration:** 10 seconds  
**Icon:** 🔒 Security icon

**Action:** Attendance is **BLOCKED** - cannot proceed

---

## 📸 Photo Upload Messages

### ❌ **ERROR 3: Photo Too Large**
**When:** Photo file size > 50KB

**Message:**
```
Photo is too large ([SIZE] KB).

Maximum allowed: 50 KB

Please take a new photo. The app will automatically compress it.
```

**Color:** 🔴 Red  
**Action:** User must retake photo

---

## ✅ Attendance Marking Success Messages

### ✅ **SUCCESS 1: Entry Photo Recorded**
**When:** Entry photo successfully uploaded

**Message:**
```
✅ Entry photo recorded for [ROLL_NUMBER]
⚠️ Attendance will be marked as present only after exit photo is taken!
⚠️ Remember to take exit photo before leaving!
```

**Color:** 🟢 Green  
**Duration:** 3 seconds  
**Icon:** ✅ Check circle

---

### ✅ **SUCCESS 2: Exit Attendance Marked**
**When:** Exit photo successfully uploaded and attendance marked

**Message:**
```
✅ Exit attendance marked for [ROLL_NUMBER]
⏰ Total hours: [HOURS] hours
```

**Color:** 🟢 Green  
**Duration:** 3 seconds  
**Icon:** ✅ Check circle

---

### ✅ **SUCCESS 3: Lecture Scan Marked**
**When:** Lecture face scan successfully recorded

**Message:**
```
✅ Lecture [LECTURE_NUMBER] face scan marked for [ROLL_NUMBER]
```

**Color:** 🟢 Green  
**Duration:** 3 seconds  
**Icon:** ✅ Check circle

---

### ✅ **SUCCESS 4: General Attendance Marked**
**When:** Attendance marked (fallback message)

**Message:**
```
✅ Attendance marked for [ROLL_NUMBER]
```

**Color:** 🟢 Green  
**Duration:** 3 seconds  
**Icon:** ✅ Check circle

---

## ⚠️ Attendance Already Marked Messages

### ⚠️ **WARNING: Attendance Fully Marked**
**When:** Both entry and exit photos already recorded for today

**Message:**
```
⚠️ Attendance fully marked for this student (Entry: [TIME], Exit: [TIME]).

Both entry and exit photos are already recorded.
```

**Color:** 🟠 Orange  
**Duration:** 5 seconds

---

## ❌ General Error Messages (During Attendance Marking)

### ❌ **ERROR 4: Storage Configuration Error**
**When:** B2B storage authentication/configuration issue

**Message:**
```
Storage service configuration error. Please contact technical support.
```

**Color:** 🔴 Red  
**Title:** "Attendance Marking Failed"

---

### ❌ **ERROR 5: Upload Failed**
**When:** Photo upload to B2B storage fails

**Message:**
```
Failed to upload photo. Please check your internet connection and try again.
```

**Color:** 🔴 Red  
**Title:** "Attendance Marking Failed"

---

### ❌ **ERROR 6: Network Connection Issue**
**When:** Network timeout or connection error

**Message:**
```
Network connection issue. Please check your internet connection and try again.
```

**Color:** 🔴 Red  
**Title:** "Attendance Marking Failed"

---

### ❌ **ERROR 7: Location Verification Failed**
**When:** GPS location check fails or outside 30m radius

**Message:**
```
Location verification failed. Please enable location services and ensure you are within 30 meters of the institute.
```

**Color:** 🔴 Red  
**Title:** "Attendance Marking Failed"

---

### ❌ **ERROR 8: Time Window Error**
**When:** Attempting to mark attendance outside allowed time window

**Message:**
```
Attendance can only be marked during the allowed time window. Please check the batch timing and try again.
```

**Color:** 🔴 Red  
**Title:** "Attendance Marking Failed"

---

### ❌ **ERROR 9: Photo Quality Too Low**
**When:** Photo blur detection or quality check fails

**Message:**
```
Photo quality is too low. Please ensure good lighting, keep the camera steady, and take a clear photo.
```

**Color:** 🔴 Red  
**Title:** "Attendance Marking Failed"

---

### ❌ **ERROR 10: Invalid Photo Detected**
**When:** System detects photo of a photo (not live capture)

**Message:**
```
Invalid photo detected. Please take a live photo of the student, not a photo of a photo.
```

**Color:** 🔴 Red  
**Title:** "Attendance Marking Failed"

---

### ❌ **ERROR 11: System Configuration Error**
**When:** .env file not loaded or configuration missing

**Message:**
```
System configuration error. Please contact technical support.
```

**Color:** 🔴 Red  
**Title:** "Attendance Marking Failed"

---

### ❌ **ERROR 12: Generic Error**
**When:** Any other unexpected error

**Message:**
```
An error occurred while marking attendance. Please try again. If the problem persists, contact support.
```

**Color:** 🔴 Red  
**Title:** "Attendance Marking Failed"

---

## 👤 Student Registration Messages

### ✅ **SUCCESS: Student Added Successfully**
**When:** Student created and face registered successfully

**Message:**
```
Student Added Successfully

[STUDENT_NAME] has been registered. Face recognition is enabled for attendance marking.
```

**Color:** 🟢 Green  
**Action Button:** "Done"

---

### ❌ **ERROR: Failed to Add Student**
**When:** Student creation fails

**Message:**
```
Failed to Add Student

[PROFESSIONAL_ERROR_MESSAGE]
```

**Possible Error Messages:**
- `Permission denied. Please check Firestore security rules for students collection.`
- `Network error. Please check your internet connection and try again.`
- `Request timed out. Please check your connection and try again.`
- `An unexpected error occurred: [ERROR_DETAILS]`

**Color:** 🔴 Red

---

## 📍 Location Lock Messages

### 🔒 **Location Locked**
**When:** Admin location is locked on another device

**Message:**
```
Location is locked and away from location
```

**Color:** 🔴 Red

---

### 🔓 **Location Unlocked**
**When:** Super admin unlocks location

**Message:**
```
Location unlocked
```

**Color:** 🟢 Green

---

## 📊 Message Summary Table

| Scenario | Message Type | Color | Duration | Icon |
|----------|-------------|-------|----------|------|
| Face Recognition Failed | Error | 🔴 Red | 10s | ⚠️ |
| Wrong Student Detected | Security Error | 🔴 Red | 10s | 🔒 |
| Photo Too Large | Error | 🔴 Red | - | ⚠️ |
| Entry Photo Recorded | Success | 🟢 Green | 3s | ✅ |
| Exit Attendance Marked | Success | 🟢 Green | 3s | ✅ |
| Lecture Scan Marked | Success | 🟢 Green | 3s | ✅ |
| Attendance Fully Marked | Warning | 🟠 Orange | 5s | ⚠️ |
| Network Error | Error | 🔴 Red | - | ⚠️ |
| Location Error | Error | 🔴 Red | - | ⚠️ |
| Student Added | Success | 🟢 Green | - | ✅ |
| Student Add Failed | Error | 🔴 Red | - | ⚠️ |

---

## 🔍 Message Flow Diagram

### **Successful Attendance Flow:**
```
1. Face Recognition ✅ (No message - proceeds)
   ↓
2. Photo Upload ✅
   ↓
3. Attendance Saved ✅
   ↓
4. Success Message: "✅ Exit attendance marked for [ROLL]"
```

### **Failed Attendance Flow:**
```
1. Face Recognition ❌
   ↓
   Message: "❌ Face Recognition Failed"
   [STOP - Cannot proceed]
```

OR

```
1. Face Recognition ✅
   ↓
2. Wrong Roll Number Detected ❌
   ↓
   Message: "❌ SECURITY: Wrong Student Detected"
   [STOP - Cannot proceed]
```

OR

```
1. Face Recognition ✅
   ↓
2. Photo Upload ❌
   ↓
   Message: "[Specific Error Message]"
   [STOP - Cannot proceed]
```

---

## 🎨 Message Styling

### **Success Messages:**
- **Background:** Green (`Colors.green`)
- **Icon:** ✅ Check circle (`Icons.check_circle`)
- **Text Color:** White
- **Duration:** 3 seconds (attendance), varies (others)

### **Error Messages:**
- **Background:** Red (`Colors.red`)
- **Icon:** ⚠️ Error outline (`Icons.error_outline`) or 🔒 Security (`Icons.security`)
- **Text Color:** White
- **Duration:** 10 seconds (face recognition), varies (others)

### **Warning Messages:**
- **Background:** Orange (`Colors.orange`)
- **Text Color:** White
- **Duration:** 5 seconds

---

## 📝 Notes

1. **Face Recognition Messages** are shown as SnackBars with detailed explanations
2. **Success Messages** are brief and confirm the action
3. **Error Messages** provide actionable guidance
4. **Security Messages** (wrong student) are prominently displayed with red background
5. All messages are user-friendly and avoid technical jargon
6. Messages include emojis for quick visual recognition
7. Error messages suggest solutions when possible
