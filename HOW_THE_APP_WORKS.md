# How The Attendance App Works - Complete Explanation

## 🚀 Starting the App

### Step 1: App Launch
When you open the app, it goes through this sequence:

1. **Splash Screen** appears first
   - Shows app logo/loading
   - Checks if you're already logged in
   - Decides where to send you next

2. **Routing Decision:**
   - **If NOT logged in** → Goes to **Login Screen**
   - **If logged in + Biometric enabled** → Goes to **Biometric Lock Screen**
   - **If logged in + No biometric** → Goes directly to **Home Dashboard**

---

## 🔐 Authentication Process

### Scenario A: First Time / Not Logged In

1. **Login Screen** appears
   - You see options:
     - Email/Password login
     - PIN login (IRCTC-style)
     - Biometric login (if enabled)
     - "Change User Account" button

2. **Login Methods:**

   **Method 1: Email/Password**
   - Enter email and password
   - Tap "Login"
   - System verifies with Firebase
   - If correct → Proceeds to next step

   **Method 2: PIN Login**
   - Enter 4-6 digit PIN
   - System hashes PIN (SHA-256) and compares
   - If correct → Proceeds to next step

   **Method 3: Biometric**
   - Tap biometric button
   - Use fingerprint/face ID
   - If verified → Proceeds to next step

3. **After Successful Login:**
   - If biometric is enabled → **Biometric Lock Screen**
   - If biometric NOT enabled → **Home Dashboard**

### Scenario B: Already Logged In

1. **Biometric Lock Screen** (if biometric enabled)
   - App automatically triggers biometric (300ms delay)
   - You can:
     - Use biometric (fingerprint/face ID)
     - OR enter PIN manually
   - PIN input is always visible
   - Auto-submits PIN after 6 digits
   - Once verified → **Home Dashboard**

2. **If App Goes to Background:**
   - App automatically locks
   - When you return → **Biometric Lock Screen** appears again
   - Must authenticate again to continue

---

## 🏠 Home Dashboard

Once authenticated, you see the **Home Dashboard**:

### What You See:
- **Quick Stats Card:**
  - Total Students
  - Present Today
  - Absent Today
  - Attendance Rate (percentage with progress bar)

- **Quick Access Buttons:**
  - Mark Attendance
  - Add Student
  - View Students
  - Batch Management
  - Reports
  - Settings

- **Recent Activity:**
  - Last attendance marked
  - Recent student additions

### Navigation:
- **Bottom Navigation Bar** with 5 tabs:
  1. Home
  2. Attendance
  3. Students
  4. Batches
  5. Settings

---

## 👥 Student Registration Process

### How to Add a New Student:

1. **Navigate to Add Student:**
   - From Home → Tap "Add Student"
   - OR from Students tab → Tap "+" button

2. **Fill Student Information:**

   **Basic Details:**
   - **Name**: Student's full name
   - **Roll Number (G.R. No.)**: Unique identifier (e.g., GR001)
   - **Contact**: Phone number

   **Academic Details:**
   - **Semester**: Select from dropdown
     - Semester 1 (Jan-Jun) OR Semester 2 (Jul-Dec)
     - Year is auto-detected (e.g., 2026)

   - **Batches**: Select multiple batches (checkboxes)
     - Shows all available batches
     - Can select 1, 2, 3, or more batches
     - Student can attend any of these batches

   - **Subjects**: Select 2-3 subjects (checkboxes)
     - Only 8 predefined subjects available:
       - GCC-TBC ENGLISH 30 WPM
       - GCC-TBC ENGLISH 40 WPM
       - GCC-TBC ENGLISH 50 WPM
       - GCC-TBC ENGLISH 60 WPM
       - GCC-TBC MARATHI 30 WPM
       - GCC-TBC MARATHI 40 WPM
       - GCC-TBC HINDI 30 WPM
       - GCC-TBC HINDI 40 WPM
     - Can select 2-3 subjects (for simultaneous admission)

   **Photo:**
   - Tap "Capture Photo" or "Select from Gallery"
   - Camera opens
   - Take/select student photo
   - Photo is used for face recognition

3. **Submit:**
   - Tap "Add Student" button
   - System validates all fields
   - Uploads photo to Firebase Storage
   - Creates face template for recognition
   - Saves student record to Firestore
   - Shows success message

### What Happens Behind the Scenes:

1. **Photo Processing:**
   - Photo uploaded to Firebase Storage
   - Face template extracted using ML Kit
   - Template saved for future recognition

2. **Data Storage:**
   - Student record created in Firestore
   - Linked to institute
   - Batch assignments saved
   - Subject enrollments saved

3. **Result:**
   - Student appears in student list
   - Can now mark attendance
   - Face recognition ready

---

## ⏰ Batch Management

### Creating Batches - Two Methods:

### Method 1: Auto-Generate Batches (Recommended)

1. **Access:**
   - Go to Batch Management screen
   - Tap "Auto-Generate Batches" button (⚡ icon)

2. **Configure Settings:**

   **Institute Timing:**
   - **Open Time**: Select when institute opens
     - Example: 7:00 AM, 8:00 AM, or 9:00 AM
   - **Close Time**: Select when institute closes
     - Example: 7:00 PM, 8:00 PM, or 9:00 PM
   - **Total**: 12 hours operating window

   **Batch Duration:**
   - **60 Minutes (Regular)**: Standard 1-hour batches
     - Default option
     - For regular students
   - **120 Minutes (Late Admission)**: 2-hour batches
     - For late admission students
     - Batch names include "- Late Admission" suffix

   **Semester:**
   - Select Semester 1 (Jan-Jun) OR Semester 2 (Jul-Dec)
   - Year auto-detected from device date

   **Subjects:**
   - Select 2-3 subjects (checkboxes)
   - All selected subjects will run simultaneously in each batch
   - Only predefined subjects available

3. **Generate:**
   - Tap "Generate Batches" button
   - System calculates time slots
   - Creates all batches automatically
   - Shows success message with count

### Example: 8 AM to 8 PM (60 Minutes)

**What Gets Created:**
- Batch 1: 08:00 - 09:00
- Batch 2: 09:00 - 10:00
- Batch 3: 10:00 - 11:00
- Batch 4: 11:00 - 12:00
- Batch 5: 12:00 - 13:00
- Batch 6: 13:00 - 14:00
- Batch 7: 14:00 - 15:00
- Batch 8: 15:00 - 16:00
- Batch 9: 16:00 - 17:00
- Batch 10: 17:00 - 18:00
- Batch 11: 18:00 - 19:00
- Batch 12: 19:00 - 20:00

**Total: 12 batches** (one for each hour)

### Example: 8 AM to 8 PM (120 Minutes - Late Admission)

**What Gets Created:**
- Batch 1: 08:00 - 10:00 - Late Admission
- Batch 2: 10:00 - 12:00 - Late Admission
- Batch 3: 12:00 - 14:00 - Late Admission
- Batch 4: 14:00 - 16:00 - Late Admission
- Batch 5: 16:00 - 18:00 - Late Admission
- Batch 6: 18:00 - 20:00 - Late Admission

**Total: 6 batches** (one for each 2-hour period)

### Method 2: Manual Batch Creation

1. **Access:**
   - Go to Batch Management screen
   - Tap "Create Batch" button

2. **Fill Details:**
   - Batch Name
   - Year
   - Start Time & End Time
   - Select subjects (dropdown - predefined only)

3. **Submit:**
   - Creates single batch
   - Useful for special batches

---

## ✅ Attendance Marking Process

### Complete Step-by-Step:

1. **Navigate to Attendance Screen:**
   - From Home → Tap "Mark Attendance"
   - OR from Attendance tab

2. **Select Batch (Optional):**
   - Choose batch from dropdown
   - This is for filtering only
   - **Important**: Students can mark attendance in ANY batch, regardless of assignment

3. **Find Student:**
   - **Option A**: Search by name or roll number
     - Type in search box
     - Results filter automatically
   - **Option B**: Scroll through student list
     - All students from institute shown
     - Not limited to batch-specific students

4. **Select Student:**
   - Tap on student card
   - Student details appear
   - Shows:
     - Name, Roll Number
     - Assigned batches
     - Enrolled subjects
     - Current attendance status

5. **Mark Entry:**

   **Tap "Mark Entry" button:**
   
   **Step 1: Face Recognition**
   - Camera opens automatically
   - Student's face captured
   - System compares with saved face template
   - If match → Proceeds
   - If no match → Shows error, retry

   **Step 2: GPS Verification**
   - System checks current location
   - Compares with institute location
   - Verifies if within 30-meter radius
   - If within radius → Proceeds
   - If outside → Shows error "Must be within 30 meters"

   **Step 3: Photo Capture**
   - Entry photo captured automatically
   - Timestamp added to photo
   - Photo uploaded to Firebase Storage

   **Step 4: Time Recording**
   - Entry time recorded (e.g., 08:30:00)
   - Date recorded (e.g., 2026-01-15)
   - Location coordinates saved

   **Step 5: Save to Database**
   - Attendance record created in Firestore
   - Status: "Entry Marked"
   - Entry photo URL saved
   - Entry timestamp saved

   **Result:**
   - Success message shown
   - Entry status updated on screen
   - Entry photo thumbnail displayed
   - Entry time shown

6. **Mark Exit:**

   **Tap "Mark Exit" button:**
   
   **Step 1: Face Recognition**
   - Camera opens again
   - Face verified against template
   - Must match same student

   **Step 2: GPS Verification**
   - Location checked again
   - Must be within 30 meters

   **Step 3: Photo Capture**
   - Exit photo captured
   - Timestamp added
   - Uploaded to storage

   **Step 4: Time Recording**
   - Exit time recorded (e.g., 09:00:00)
   - Duration calculated (e.g., 30 minutes)

   **Step 5: Update Record**
   - Attendance record updated
   - Status: "Entry & Exit Marked"
   - Exit photo URL saved
   - Exit timestamp saved

   **Result:**
   - Success message shown
   - Exit status updated
   - Exit photo thumbnail displayed
   - Exit time shown
   - Complete attendance record visible

7. **View Attendance Details:**
   - Tap on photo thumbnail
   - Full-size photo opens
   - Timestamp displayed
   - Can view entry and exit photos separately

### Key Features:

- **Flexible Attendance:**
  - Student can mark in ANY batch
  - Not restricted to assigned batches
  - Focus on in/out times, not batch assignment

- **Security Checks:**
  - Face recognition (prevents proxy)
  - GPS verification (prevents remote marking)
  - Photo evidence (with timestamps)
  - Time validation (no future dates)

- **Photo Evidence:**
  - Entry photo with timestamp
  - Exit photo with timestamp
  - Stored permanently
  - Viewable anytime

---

## 📊 Reports & Analytics

### Generating Reports:

1. **Navigate to Reports:**
   - From Home → Tap "Reports"
   - OR from Reports tab

2. **Select Date Range:**
   - Tap "From Date" → Select start date
   - Tap "To Date" → Select end date
   - **Maximum Range**: 1 month (31 days)
   - If you select more than 1 month:
     - System shows warning
     - End date auto-adjusts to 1 month from start date

3. **Generate Report:**
   - Tap "Generate Report" button
   - System filters attendance records
   - Shows results

4. **Report Contents:**
   - Student-wise attendance
   - Date-wise breakdown
   - Entry times
   - Exit times
   - Entry photos (thumbnails)
   - Exit photos (thumbnails)
   - Total attendance count
   - Attendance percentage

5. **Export Options:**
   - Download as PDF
   - Download as Excel
   - Share via email
   - Print report

### Calendar View:

1. **Access Calendar:**
   - From Reports → Tap "Calendar View"
   - OR from Home → Calendar icon

2. **View Monthly Calendar:**
   - Shows current month
   - Days with attendance highlighted
   - Color indicators:
     - Green: High attendance
     - Yellow: Medium attendance
     - Red: Low attendance

3. **View Details:**
   - Tap on any date
   - Shows attendance for that day
   - List of students who marked attendance
   - Entry/exit times

4. **Navigate:**
   - Swipe left/right to change months
   - OR use arrow buttons
   - Jump to specific month/year

### Trend Analysis:

- **Charts:**
  - Bar charts showing attendance trends
  - Line charts showing patterns
  - Pie charts for distribution

- **Time Periods:**
  - Daily view
  - Weekly view
  - Monthly view

- **Insights:**
  - Attendance rate trends
  - Peak attendance times
  - Low attendance patterns

---

## ⚙️ Settings & Configuration

### GPS Settings:

1. **Access:**
   - From Settings tab
   - OR from Home → Settings

2. **Configure Location:**
   - **Set Institute Location:**
     - Enter latitude
     - Enter longitude
     - OR use map picker
     - Tap "Set Location"

   - **Set Radius:**
     - Default: 30 meters
     - Can adjust if needed
     - **Note**: Existing 25-meter settings automatically upgraded to 30 meters

3. **Test Location:**
   - Tap "Test Current Location"
   - Shows if you're within geofence
   - Displays distance from center
   - Visual indicator on map

4. **Save:**
   - Settings saved to Firestore
   - Applied immediately
   - All attendance marking uses new settings

### Theme Settings:

1. **Access:**
   - From Settings → Theme

2. **Toggle Dark Mode:**
   - Switch between Light and Dark
   - Change applies immediately
   - Preference saved automatically
   - Persists across app sessions

### Help & Support:

1. **Help Desk:**
   - Access from Settings → Help
   - FAQ section
   - Feature explanations
   - Troubleshooting tips

2. **Contact Support:**
   - Email support
   - Phone support
   - In-app messaging

---

## 🔄 Complete Workflow Example

### Scenario: Daily Attendance Marking

**Morning (8:00 AM):**

1. **Admin opens app**
   - Biometric lock screen appears
   - Uses fingerprint to unlock
   - Home dashboard loads

2. **Student arrives (8:30 AM)**
   - Admin navigates to Attendance screen
   - Searches for student "John Doe"
   - Selects student

3. **Mark Entry:**
   - Taps "Mark Entry"
   - Camera opens, captures face
   - Face recognized ✓
   - GPS checked (within 30m) ✓
   - Entry photo taken
   - Entry time: 08:30:00 recorded
   - Success message shown

4. **Student attends class**
   - Student in class from 8:30 AM to 9:30 AM

**Afternoon (9:30 AM):**

5. **Mark Exit:**
   - Admin navigates to Attendance screen
   - Finds same student
   - Taps "Mark Exit"
   - Camera opens, captures face
   - Face recognized ✓
   - GPS checked (within 30m) ✓
   - Exit photo taken
   - Exit time: 09:30:00 recorded
   - Duration: 1 hour calculated
   - Success message shown

6. **View Record:**
   - Attendance card shows:
     - Entry: 08:30:00 (with photo)
     - Exit: 09:30:00 (with photo)
     - Status: Complete
   - Can tap photos to view full-size

**End of Day:**

7. **Generate Report:**
   - Admin goes to Reports
   - Selects date range (today)
   - Generates report
   - Views all attendance for the day
   - Exports if needed

---

## 🗄️ Data Storage

### Where Data is Stored:

1. **Firebase Authentication:**
   - User accounts
   - Login credentials
   - Session tokens

2. **Cloud Firestore:**
   - Student records
   - Batch information
   - Attendance records
   - Institute settings
   - Subject list

3. **Firebase Storage:**
   - Student photos
   - Entry photos
   - Exit photos

4. **Local Storage (Device):**
   - Biometric preference
   - Theme preference
   - PIN hash (encrypted)

### Data Structure:

**Student Record:**
```json
{
  "name": "John Doe",
  "rollNumber": "GR001",
  "semester": "1-2026",
  "batchIds": ["batch1", "batch2"],
  "subjects": ["GCC-TBC ENGLISH 30 WPM"],
  "photoUrl": "https://...",
  "faceTemplate": "..."
}
```

**Attendance Record:**
```json
{
  "studentId": "student123",
  "date": "2026-01-15",
  "entryTime": "08:30:00",
  "exitTime": "09:30:00",
  "entryPhoto": "https://...",
  "exitPhoto": "https://...",
  "entryLocation": {"lat": 18.5, "lng": 73.8}
}
```

---

## 🔒 Security Features

### Multi-Layer Security:

1. **Authentication:**
   - Biometric (fingerprint/face ID)
   - PIN (SHA-256 hashed)
   - Email/Password (Firebase Auth)

2. **Session Security:**
   - Auto-lock on app minimize
   - Session expiry
   - Secure logout

3. **Attendance Security:**
   - Face recognition (prevents proxy)
   - GPS geofencing (prevents remote marking)
   - Photo evidence (with timestamps)
   - Time validation (no future dates)

4. **Data Security:**
   - Encrypted data transmission
   - Secure Firestore rules
   - Role-based access control

---

## 📱 App Features Summary

### Core Features:
✅ Biometric & PIN authentication  
✅ Student registration with photos  
✅ Auto-generate batches (60/120 min)  
✅ Flexible attendance marking  
✅ Face recognition verification  
✅ GPS geofencing (30m radius)  
✅ Entry/exit photos with timestamps  
✅ Date range reports (max 1 month)  
✅ Calendar view  
✅ Dark mode  

### Predefined Data:
✅ 8 fixed subjects (computer typing)  
✅ 2 semesters (Jan-Jun, Jul-Dec)  
✅ Auto year detection  

### Batch Options:
✅ 60-minute regular batches  
✅ 120-minute late admission batches  
✅ Multiple subjects per batch (2-3)  
✅ 12-hour operating windows  

---

## 🎯 Quick Reference

### Most Common Tasks:

1. **Add Student:**
   Home → Add Student → Fill form → Submit

2. **Create Batches:**
   Batches → Auto-Generate → Configure → Generate

3. **Mark Attendance:**
   Attendance → Select Student → Mark Entry → Mark Exit

4. **View Reports:**
   Reports → Select Date Range → Generate

5. **Change Settings:**
   Settings → GPS/Theme/Help

---

## 💡 Tips & Best Practices

1. **Enable Biometric:**
   - Faster access
   - More secure
   - Better user experience

2. **Set GPS Location Accurately:**
   - Use map picker for precision
   - Test location before marking attendance
   - Ensure 30-meter radius covers institute area

3. **Regular Reports:**
   - Generate weekly reports
   - Export for record keeping
   - Review attendance trends

4. **Photo Quality:**
   - Ensure good lighting for photos
   - Clear face visibility
   - Helps with face recognition

5. **Batch Planning:**
   - Use auto-generate for efficiency
   - Plan batches according to institute timings
   - Consider late admission batches if needed

---

**This is how the complete attendance app works from start to finish!**

Every feature is designed to be secure, efficient, and user-friendly. The app handles everything from authentication to attendance marking to report generation, all while maintaining high security standards.
