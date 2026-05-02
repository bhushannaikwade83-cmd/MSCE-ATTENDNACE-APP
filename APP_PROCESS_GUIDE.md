# MSCE Attendance Management System - Complete Process Guide

## 📋 Overview

The MSCE Attendance Management System is a comprehensive mobile and web-based attendance tracking solution with face recognition, GPS verification, and automated report generation.

---

## 🎯 System Features

### Core Capabilities
- ✅ **Face Recognition Attendance** - Biometric verification with high accuracy
- ✅ **GPS Geofencing** - Location-based attendance validation
- ✅ **Auto-Close Policy** - Automatic attendance closure after 2.5 hours without exit
- ✅ **Real-time Reports** - Instant PDF reports with daily attendance details
- ✅ **Multi-Subject Support** - Track attendance across multiple subjects per student
- ✅ **Institute Isolation** - Complete data separation between institutes
- ✅ **Offline Mode** - Works without internet connection (syncs when online)

---

## 📱 For Teachers/Admin - Marking Attendance

### Step 1: Open Attendance Screen
1. Open the mobile app on your device
2. Navigate to **"Mark Attendance"** or **"Admin Attendance"**
3. Ensure location permission is enabled (for GPS validation)

### Step 2: Select Student
1. Choose the student from the dropdown list
2. Student list shows all **merged subjects** for that student
3. If no subjects show, student hasn't been assigned subjects yet

### Step 3: Take Entry Photo (IMPORTANT)
⚠️ **FACE DISTANCE REQUIREMENT**
- **You MUST take a CLOSE-UP photo**
- Face must fill a significant portion of the frame (at least 8-10% of photo area)
- Photos taken from distance WILL BE REJECTED
- Requirements:
  - Clear, well-lit photo
  - Face looking directly at camera
  - Only ONE person in frame
  - Eyes clearly visible and open
  - No blur or motion

**Example:**
- ✅ **ACCEPT**: Face takes up ~30-40% of frame, clear lighting, looking at camera
- ❌ **REJECT**: Face is tiny in corner, photo taken from 5+ feet away
- ❌ **REJECT**: Multiple faces visible
- ❌ **REJECT**: Blurry or too dark

### Step 4: GPS Verification
- System verifies you're within the institute's GPS radius
- If out of radius: ❌ Attendance REJECTED with message showing distance
- If within radius: ✅ Continues to face matching

### Step 5: Face Matching
- System compares your photo with student's registered face
- Must have >55% confidence match
- If not matched: ❌ Photo rejected, try again

### Step 6: Take Exit Photo
- When student leaves, take EXIT photo using same requirements as entry
- Same face distance rule applies
- Clear, close-up photo required

### Step 7: System Response

#### Option A: Manual Exit (Preferred)
- Student exits within 2.5 hours with exit photo
- Attendance shows: ✅ **Present** - Exit recorded
- Credited hours: Actual seated time (capped at 2.5 hours/subject/day)

#### Option B: Auto-Close (Missing Exit Photo)
- Student doesn't exit or no exit photo within 2.5 hours
- System AUTOMATICALLY closes attendance
- Attendance shows: ✅ **Present (Policy)** - Auto-closed
- Message: "No exit within 2.5h — credited 1.0h without exit photo"
- Credited hours: **1.0 hour** (fixed credit for no exit photo)

---

## 📊 Reports Section

### Generating Reports

#### Institute-Wide Report
1. Click **"Generate Report"** button
2. Select date range (max 6 months)
3. Choose filter: **"All Students"** or **"Defaulters"**
4. Click **"Load All"** or **"Load Defaulters"**

#### Per-Student Report
1. Click on any student in the list
2. Select **"View PDF Report"** option
3. Report downloads automatically or opens in PDF viewer

### What Reports Show

#### Daily Attendance Table
| Field | Shows |
|-------|-------|
| **Date** | Attendance date |
| **Subject** | Subject for that session |
| **Entry Time** | When student arrived |
| **Exit Time** | When student left OR "No Exit" |
| **Seated** | Actual hours OR "No exit photo (1.00 h credited)" |
| **Status** | Present / Absent / Holiday / Present (policy) |

#### Special Cases in Reports
- **"No exit photo (1.00 h credited)"** = Auto-closed session
- **"Present (policy)"** = System auto-closed after 2.5 hours
- **Holiday** = Institute holiday (shows reason)
- **Absent** = No entry recorded

### PDF Report Download
1. Click any student in report list
2. Select **"Download / Save to Files"**
3. Choose **"Files"** in share options to save
4. PDF named: `attendance_STUDENTNAME_ROLLNO_DATE_DATE.pdf`

---

## 👥 Student Management

### Adding Students
1. Go to **"Student Management"** section
2. Click **"Add Student"**
3. Enter:
   - Student name
   - Roll number / SR No
   - Subjects (comma-separated)
4. Take registration photo (close-up, same face requirements as attendance)
5. System stores face embedding for future attendance verification

### Viewing Student List
- Shows all students with their:
  - Name and SR No
  - All merged subjects (after deduplication)
  - Enrollment status

### Face Distance Issue
- If "Face too small" error: **Move phone closer to student's face**
- Photo must clearly show face filling most of the frame
- Lighting must be adequate (no shadows on face)

---

## 🔒 Security Features

### GPS Geofencing
- Institute has set location radius (e.g., 500m)
- Attendance only marked if within radius
- Prevents marking attendance from home or other locations
- Uses multiple GPS samples for accuracy

### Face Recognition
- On-device face detection (no photo sent to external servers)
- MobileFaceNet 192-dimensional neural embeddings
- Each student has unique face embedding stored securely
- Face matching requires >55% confidence threshold

### Liveness Detection
- Eyes must be open and visible
- Prevents photo spoofing/printed photos
- Detects genuine live face presence

### Data Isolation
- Each institute sees ONLY their students
- Cross-institute data access: **BLOCKED**
- Students from other institutes: **NOT VISIBLE**

---

## ⚙️ Configuration for Institute Admin

### Institute Settings
1. Go to **"Settings"** → **"Institute Settings"**
2. Set GPS radius (recommended: 500-1000m)
3. Configure working hours
4. Set lecture schedule/timing

### Subject Setup
1. Add subjects under **"Subject Management"**
2. Assign subjects to students
3. System handles subject merging automatically

### Holiday Management
1. Add institute holidays
2. Mark dates as holidays
3. Holidays appear in attendance reports

---

## 📈 Attendance Policy Explanation

### 2.5-Hour Auto-Close Rule

**Why?**
- Prevents students from forgetting to mark exit
- Ensures attendance closes automatically at day end
- Provides guaranteed 1-hour credit for partial days

**How it works:**
1. Student marks entry at 9:00 AM
2. Student forgets to mark exit
3. System waits 2.5 hours (deadline: 11:30 AM)
4. At 11:30 AM or later: **Auto-closed automatically**
5. Attendance marked: Present (1 hour credited)
6. Report notes: "No exit within 2.5h — credited 1.0h without exit photo"

**Example Timeline:**
```
Entry: 09:00 AM
Deadline: 11:30 AM (2.5 hours later)
At 11:35 AM: Auto-closed ✅
Credit: 1.0 h (fixed, regardless of actual time)
Status: Present (policy)
```

---

## 🚨 Common Issues & Solutions

### Face Too Small Error
**Problem:** "Face too small. Move closer to camera."

**Solution:**
- Move phone 6-12 inches from student's face
- Face should fill ~30-40% of the photo frame
- Ensure good lighting on face
- No shadows or glare on face

### Out of Radius Error
**Problem:** "Out of radius: You are XXm away. Attendance can only be marked within XXXm."

**Solution:**
- Move closer to institute location
- Turn off Mock Location apps (if used for testing)
- Ensure GPS is enabled and has clear sky view
- Wait 30 seconds for GPS to stabilize
- Retry attendance marking

### Face Not Accepted Error
**Problem:** "Face not accepted. Check lighting, one clear face, and look at the camera."

**Solution:**
- Ensure good lighting (avoid backlighting)
- Only one person in frame
- Face directly toward camera (no side angles)
- Eyes open and clearly visible
- Take another photo

### Student Profile Incomplete
**Problem:** "Student registration incomplete (missing face data)"

**Solution:**
- Go to Student Management
- Find student
- Take registration photo (close-up)
- System stores face embedding
- Now can mark attendance

### Multiple Faces Detected
**Problem:** "Multiple faces detected. Only one person allowed."

**Solution:**
- Ask other people to move out of frame
- Retake photo with only student visible
- Ensure no one else in background

### No Students in Institute
**Problem:** When clicking "Load All" or "Load Defaulters" - "No students available"

**Solution:**
- Add students in Student Management section first
- Assign subjects to students
- Then try loading reports again

---

## 📱 Mobile App Workflow (Step-by-Step)

### Daily Attendance Process

```
1. Teacher opens app
   ↓
2. Navigates to "Mark Attendance"
   ↓
3. Selects student from dropdown
   ↓
4. App verifies GPS location is within radius
   ↓
5. Teacher takes ENTRY PHOTO (close-up, facing camera)
   ↓
6. App extracts face embedding from photo
   ↓
7. App compares with student's registered face
   ↓
8. If match (>55%): ✅ Entry recorded
   If no match: ❌ Reject, ask for another photo
   ↓
9. [Later when student leaves]
   ↓
10. Teacher takes EXIT PHOTO (same requirements)
    ↓
11. If taken within 2.5 hours: ✅ Exit recorded, credit hours = actual seated time
    If after 2.5 hours: ⏰ Auto-closed, credit hours = 1.0 h fixed
    ↓
12. Report generated with status and hours
```

---

## 🖥️ Web Admin Portal (For Institute Admin)

### Dashboard
- View all attendance records
- See student attendance percentage
- Download institute-wide reports

### Reports Section
- Filter by date range
- View all students or defaulters only
- Export to PDF
- See daily attendance summary

### Data Isolation
- Only this institute's data visible
- Other institutes' students: NOT accessible
- Complete data privacy between institutes

---

## 📞 Troubleshooting Checklist

### Before Marking Attendance
- [ ] Phone has camera permission
- [ ] Location permission enabled
- [ ] Good lighting in room
- [ ] GPS signal available (check location indicator)
- [ ] Student has registered face (check Student Management)

### If Attendance Fails
- [ ] Check error message
- [ ] For face issues: retake close-up photo
- [ ] For GPS issues: move closer to institute
- [ ] For mismatch: verify correct student selected
- [ ] Try again after 30 seconds

### If Reports Don't Show
- [ ] Verify students exist in Student Management
- [ ] Check date range (max 6 months)
- [ ] Ensure attendance marked for those dates
- [ ] Check institute selection if multi-institute

---

## 🔐 Privacy & Security

### Data Protection
- Face embeddings stored securely (not raw photos)
- GPS coordinates only during attendance marking
- All data isolated by institute
- No cross-institute data leakage

### Photo Management
- Entry/exit photos stored securely
- Only used for face matching
- Can be deleted from admin panel if needed

### User Roles
- **Teacher**: Can mark attendance only
- **Admin**: Can view reports, manage students, configure settings
- **Super Admin**: Full system access

---

## 📋 System Requirements

### Mobile (Android/iOS)
- Android 8.0+ or iOS 12.0+
- Camera and location permissions
- Internet connection (for sync) or offline mode
- 100MB free storage

### Web (Admin Portal)
- Any modern browser (Chrome, Firefox, Safari, Edge)
- Desktop/tablet preferred for reports
- Internet connection

---

## ✅ Quick Start Checklist for Institute

1. **Setup**
   - [ ] Create admin account
   - [ ] Configure institute settings
   - [ ] Set GPS radius
   - [ ] Add working hours

2. **Students**
   - [ ] Add all students to system
   - [ ] Assign subjects to each student
   - [ ] Take registration photos (close-up)

3. **Teachers**
   - [ ] Train on marking attendance
   - [ ] Emphasize close-up photo requirement
   - [ ] Practice with test student

4. **Testing**
   - [ ] Mark test attendance
   - [ ] Verify GPS working
   - [ ] Check report generation
   - [ ] Verify auto-close at 2.5 hours

5. **Live**
   - [ ] Start marking daily attendance
   - [ ] Review reports weekly
   - [ ] Monitor attendance trends

---

## 📞 Support & Contact

For technical issues:
- Check troubleshooting section above
- Verify all requirements are met
- Contact system administrator
- Provide error messages and screenshots

---

**Version:** 1.0  
**Last Updated:** May 2026  
**System:** MSCE Attendance Management v1.0
