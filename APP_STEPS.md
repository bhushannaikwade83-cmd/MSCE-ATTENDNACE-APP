# MSCE Attendance App - Complete App Flow

## 1. Sign Up (First Time Only - OTP Verification)

1. Open app for first time
2. Click **"Sign Up"** button
3. Enter **Institute ID**
4. Click **"Get OTP"**
5. OTP sent to registered phone/email
6. Enter **OTP** received
7. Click **"Verify"**
8. Account created - ready for login

**Note:** All user data (email, name, institute) prefetched from database

---

## 2. Login (Institute ID + Password)

1. Open app (after sign up)
2. Enter:
   - **Institute ID**
   - **Password**
3. Click **"Login"**
4. App loads Admin Home Dashboard

**Note:** NO email login - only Institute ID + Password

---

## 3. PIN Setup (First Time - Before GPS)

1. After login, app prompts for PIN setup
2. Enter **4-digit PIN** (4 digits for security)
3. Confirm PIN
4. PIN saved ✅
5. Now proceed to GPS Settings

---

## 4. GPS Settings (First Time MANDATORY - Required for Dashboard Access)

⚠️ **MUST COMPLETE THIS BEFORE ACCESSING DASHBOARD**

1. After PIN setup, app shows: **"Lock your attendance zone before continuing"**
2. Click **"GPS Settings"** button
3. App opens GPS Settings screen
4. Click **"Lock Current Location"** button
5. App captures your current GPS coordinates
6. Set radius (e.g., 500m) - students within this radius can mark attendance
7. Click **"Save"**
8. Geofencing locked ✅
9. **NOW you can access Dashboard**

**Without GPS geofencing locked:**
- ❌ Cannot access dashboard
- ❌ Cannot mark attendance
- ❌ Cannot view students
- ❌ Cannot view reports

**Why:** Prevents students from marking attendance outside institute location

---

## 5. Holiday Close/Open (Daily Decision)

### On Admin Home Dashboard - Top Section

Three buttons appear: **🟢 Open | 🏖️ Holiday | 🔴 Close**

### Mark as Holiday
1. Click **"🏖️ Holiday"** button
2. Select reason:
   - Holiday
   - Government Holiday
   - Festival
   - Emergency Closure
   - Other Holiday
3. Confirm - institute marked as Holiday
4. Result: No attendance counted for this day

### Open Institute (Default)
1. Click **"🟢 Open"** button
2. Confirm - institute marked as Open
3. Result: Can mark attendance normally

### Close Institute (End of Day)
1. Click **"🔴 Close"** button (available near end of day ~10 PM)
2. Confirm - all unmarked students auto-marked absent
3. Result: Day finalized, no more attendance marking

### One-Day Decision Lock
- Choose EITHER Open OR Holiday for one day
- Once chosen, other option disabled for that day
- Close available at end of day

---

## 6. View Students (Fetched from Database)

1. From Admin Home, click **"Students"** button
2. App fetches all students from database
3. Students list shows:
   - Student name and roll number
   - All merged subjects (dropdown to select)
   - Current attendance status (today)
   - Entry/Exit buttons for each subject

---

## 7. Register Student Face (If Not Done)

**ONLY if student has NOT registered face yet:**

1. In Students list, find student
2. Click **face icon** 🟢 (green face icon on right side)
3. App opens face registration screen
4. Take **CLOSE-UP PHOTO** of student face:
   - Face fills 8-10% of frame minimum
   - Good lighting, eyes visible, looking at camera
   - Only one person in frame
5. Click **"Save"** or **"Register"**
6. System stores face data - ready for attendance

**Note:** If face already registered, icon shows ✅ (checkmark) - skip this step

---

## 8. Mark Attendance - Entry Photo

1. In Students list, select student
2. Choose subject from dropdown (if multiple subjects)
3. Click **"Entry"** button (green)
4. Take **ENTRY PHOTO** (close-up):
   - Face fills frame (8-10% minimum)
   - Clear lighting, eyes open, looking at camera
5. System verifies:
   - GPS location within radius ✅
   - Face matches student ✅
6. ✅ Entry recorded with timestamp

---

## 9. Mark Attendance - Exit Photo

1. When student leaves, click **"Exit"** button (yellow)
2. Take **EXIT PHOTO** (same close-up requirements):
   - Clear face, looking at camera, good lighting
3. System processes exit:
   - If exit within 2.5 hours: ✅ Exit recorded
   - Credited hours = actual seated time (capped at 2.5 hrs/subject/day)
4. If NO exit OR after 2.5 hours:
   - ⏰ Auto-closed by system automatically
   - Credited hours = 1.0 h (fixed)
   - Report note: "No exit photo within 2.5h — credited 1.0h"

---

## 10. View Reports

1. From Admin Home, click **"Reports"** button
2. Select date range (max 6 months)
3. Choose filter:
   - **"All Students"** - all students
   - **"Defaulters"** - absent > present
4. Click **"Load All"** or **"Load Defaulters"**
5. Students list shows:
   - Present days
   - Absent days
   - Attendance percentage

### Download Student PDF Report
1. Click on student name
2. Select **"View PDF Report"** or **"Download PDF"**
3. PDF shows:
   - Student details and photo
   - Daily attendance table (Date | Subject | Entry | Exit | Hours | Status)
   - Auto-closed sessions marked as "No exit photo (1.0 h credited)"
   - Holiday dates and reasons

---

## Quick Reference: First Time Setup Flow

```
1. Sign Up (Institute ID + OTP verification - data prefetched)
   ↓
2. Login (Institute ID + Password)
   ↓
3. PIN Setup (4-digit PIN)
   ↓
4. GPS Settings MANDATORY (lock current location, set radius)
   ⚠️ WITHOUT THIS: NO DASHBOARD ACCESS
   ↓
5. Access Dashboard ✅
   ↓
6. Holiday/Close/Open decision (daily)
   ↓
7. Mark Attendance (Entry → Exit photos)
```

---

## Important Notes

### Sign Up & Login
- **Sign Up:** Institute ID + OTP (data prefetched from database)
- **Login:** Institute ID + Password
- **Optional:** Use PIN for quicker access after setup

### Face Photo Requirements
- **MUST be CLOSE-UP** - face fills 8-10% of frame minimum
- **NOT from distance** - will REJECT if face too small
- Good lighting, eyes visible, one person only

### GPS Geofencing
- **First time:** Lock your location, set radius
- **Every attendance:** System checks if device is within radius
- **Prevents:** Marking attendance from outside institute

### Auto-Close Policy
- No exit within 2.5 hours = System auto-closes
- Automatic 1 hour credit given
- Report shows: "No exit photo (1.0 h credited)"

### Students from Database
- All students fetched from database (not added in app)
- Database managed externally
- App displays merged subjects automatically

