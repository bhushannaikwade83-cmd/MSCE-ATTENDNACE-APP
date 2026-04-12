# Complete Attendance App Guide - How It Works

## 📱 App Overview

**EduSetu By Digitrix Media** is a comprehensive biometric attendance management system designed for educational institutes. The app provides secure, automated attendance tracking using face recognition, GPS geofencing, and flexible batch management.

---

## 🎯 Key Features

### 1. **IRCTC-Style Biometric Security**
- **Biometric Authentication**: Fingerprint/Face ID for quick app unlock
- **PIN Authentication**: 4-6 digit PIN as fallback
- **Auto-Lock**: App automatically locks when minimized or backgrounded
- **Session Management**: Secure session handling with auto-logout

### 2. **Student Management**
- **Student Registration**: Add students with photo, roll number, contact, semester, batches, and subjects
- **Multiple Batches**: Students can be assigned to multiple batch times
- **Multiple Subjects**: Students can enroll in 2-3 subjects simultaneously
- **Photo Storage**: Student photos stored for face recognition
- **Flexible Attendance**: Students can mark attendance in any batch, regardless of assignment

### 3. **Batch Management**
- **Auto-Generate Batches**: Automatically create batches based on institute timings
- **Flexible Duration**: 
  - **60 Minutes (Regular)**: Standard 1-hour batches
  - **120 Minutes (Late Admission)**: 2-hour batches for late admission students
- **Multiple Subjects**: 2-3 subjects can run simultaneously in the same batch
- **Institute Timings**: Supports 12-hour operating windows (7-7, 8-8, 9-9)

### 4. **Predefined Subjects**
- **8 Fixed Subjects** (Computer Typing):
  - GCC-TBC ENGLISH 30 WPM
  - GCC-TBC ENGLISH 40 WPM
  - GCC-TBC ENGLISH 50 WPM
  - GCC-TBC ENGLISH 60 WPM
  - GCC-TBC MARATHI 30 WPM
  - GCC-TBC MARATHI 40 WPM
  - GCC-TBC HINDI 30 WPM
  - GCC-TBC HINDI 40 WPM
- **No Custom Subjects**: Only predefined subjects allowed

### 5. **Semester System**
- **Predefined Semesters**:
  - **Semester 1**: January to June
  - **Semester 2**: July to December
- **Auto Year Detection**: Year automatically detected from device date

### 6. **Attendance Marking**
- **Face Recognition**: Biometric verification using saved face templates
- **GPS Geofencing**: 30-meter radius location verification
- **Entry/Exit Tracking**: Separate entry and exit times with photos
- **Flexible System**: Students can mark attendance in any batch
- **Photo Timestamps**: Entry and exit photos stored with timestamps

### 7. **GPS Geofencing**
- **30-Meter Radius**: Location-based attendance restriction
- **Automatic Migration**: Existing 25-meter settings automatically upgraded to 30 meters
- **Configurable**: Institute can set custom geofence location

### 8. **Reports & Analytics**
- **Date Range Reports**: Generate reports for any date range (max 1 month)
- **Attendance Calendar**: Monthly calendar view with attendance indicators
- **Trend Analysis**: Visual charts showing attendance patterns
- **Export Options**: Download reports for record keeping

### 9. **Dark Mode**
- **Theme Toggle**: Switch between light and dark themes
- **Persistent Preference**: Theme choice saved across app sessions

---

## 🔐 Authentication & Security

### Login Flow

1. **Splash Screen**
   - Checks if user is logged in
   - If logged in and biometric enabled → Navigate to Biometric Lock Screen
   - If logged in but no biometric → Navigate to Main Screen
   - If not logged in → Navigate to Login Screen

2. **Login Screen**
   - Email/Password login
   - PIN login (IRCTC-style)
   - "Change User Account" option to go to setup screen
   - Biometric login option (if enabled)

3. **Biometric Lock Screen**
   - Auto-triggers biometric authentication on app open
   - PIN input always visible
   - Auto-submits PIN after 6 digits
   - Biometric button always visible if enabled
   - Appears when app resumes from background

4. **Session Management**
   - Auto-locks app when minimized
   - Session expiry handling
   - Secure logout

---

## 👥 User Roles

### 1. **Admin/Institute User**
- Full access to all features
- Student management
- Batch management
- Attendance marking
- Reports generation
- GPS settings configuration

### 2. **Super Admin**
- Institute creation and management
- System-wide access

---

## 📚 Student Registration Process

### Step-by-Step Flow

1. **Navigate to Add Student Screen**
   - From Home → Add Student
   - Or from Student Management → Add New

2. **Fill Student Details**:
   - **Name**: Student's full name
   - **Roll Number (G.R. No.)**: Unique identifier
   - **Semester**: Select from dropdown (1 or 2)
   - **Batches**: Select multiple batches (checkboxes)
   - **Subjects**: Select 2-3 subjects (checkboxes)
   - **Contact**: Phone number
   - **Photo**: Capture or select photo for face recognition

3. **Submit**
   - Validates all fields
   - Uploads photo to Firebase Storage
   - Creates face template for recognition
   - Saves student record to Firestore
   - Assigns student to selected batches and subjects

### Student Data Structure

```json
{
  "name": "Student Name",
  "rollNumber": "GR001",
  "semester": "1-2026",
  "semesterName": "Semester 1 - Jan to Jun 2026",
  "batchIds": ["batch1", "batch2"],
  "subjects": ["GCC-TBC ENGLISH 30 WPM", "GCC-TBC ENGLISH 40 WPM"],
  "contact": "1234567890",
  "photoUrl": "https://...",
  "faceTemplate": "...",
  "instituteId": "institute123",
  "createdAt": "2026-01-15T10:30:00Z"
}
```

---

## ⏰ Batch Management

### Auto-Generate Batches

1. **Access Feature**
   - Go to Batch Management screen
   - Click "Auto-Generate Batches" button

2. **Configure Settings**:
   - **Institute Timing**:
     - Open Time (e.g., 7:00 AM, 8:00 AM, 9:00 AM)
     - Close Time (e.g., 7:00 PM, 8:00 PM, 9:00 PM)
     - Total: 12 hours
   - **Batch Duration**:
     - 60 Minutes (Regular) - Default
     - 120 Minutes (Late Admission)
   - **Semester**: Select 1 or 2
   - **Subjects**: Select 2-3 subjects (for simultaneous admission)

3. **Generate**
   - System calculates time slots
   - Creates batches with selected duration
   - Assigns all selected subjects to each batch
   - Saves to Firestore

### Example: 8 AM to 8 PM (12 hours)

**60 Minutes (Regular)**:
- Generates 12 batches: 8-9, 9-10, 10-11, ..., 7-8 PM
- Each batch: 1 hour
- Multiple subjects run simultaneously

**120 Minutes (Late Admission)**:
- Generates 6 batches: 8-10, 10-12, 12-2, 2-4, 4-6, 6-8 PM
- Each batch: 2 hours
- Batch names include "- Late Admission" suffix

### Manual Batch Creation

- Can create batches manually with custom timings
- Same subject selection and semester assignment
- Useful for special batches or exceptions

---

## ✅ Attendance Marking Process

### Step-by-Step Flow

1. **Navigate to Attendance Screen**
   - From Home → Mark Attendance
   - Or from Main Navigation → Attendance

2. **Select Batch** (Optional)
   - Choose batch from dropdown
   - Or leave empty for flexible attendance

3. **Student Search/Selection**
   - Search by name or roll number
   - Or select from list
   - System loads all students (not just batch-specific)

4. **Mark Entry**
   - Tap "Mark Entry" button
   - **Face Recognition**: Camera captures face, verifies against saved template
   - **GPS Verification**: Checks if within 30-meter radius
   - **Photo Capture**: Takes entry photo with timestamp
   - **Time Recording**: Records entry time

5. **Mark Exit**
   - Tap "Mark Exit" button
   - **Face Recognition**: Verifies student identity again
   - **GPS Verification**: Confirms location
   - **Photo Capture**: Takes exit photo with timestamp
   - **Time Recording**: Records exit time

6. **View Attendance**
   - Entry/Exit status displayed
   - Photos shown with timestamps
   - Can view full-size photos by tapping

### Attendance Data Structure

```json
{
  "studentId": "student123",
  "rollNumber": "GR001",
  "name": "Student Name",
  "batchId": "batch1",
  "batchName": "Batch 1 (08:00 - 09:00)",
  "date": "2026-01-15",
  "entryTime": "08:30:00",
  "exitTime": "09:00:00",
  "entryPhoto": "https://...",
  "exitPhoto": "https://...",
  "entryLocation": {"lat": 18.5, "lng": 73.8},
  "exitLocation": {"lat": 18.5, "lng": 73.8},
  "instituteId": "institute123",
  "markedBy": "admin_user_id",
  "createdAt": "2026-01-15T08:30:00Z"
}
```

### Flexible Attendance Rules

- **No Batch Restriction**: Students can mark attendance in any batch
- **Focus on Time**: System tracks in/out times, not batch assignment
- **Face Verification**: Always required for entry and exit
- **Location Verification**: Must be within 30-meter radius

---

## 📊 Reports & Analytics

### Attendance Reports

1. **Date Range Selection**
   - Select "From Date" and "To Date"
   - Maximum range: 1 month (31 days)
   - System auto-adjusts if range exceeds limit

2. **Report Generation**
   - Filters attendance records by date range
   - Shows student-wise attendance
   - Displays entry/exit times
   - Includes photos with timestamps

3. **Export Options**
   - Download as PDF/Excel
   - Share via email
   - Print reports

### Calendar View

- **Monthly Calendar**: Visual representation of attendance
- **Color Indicators**: Days with attendance highlighted
- **Click to View**: Tap date to see attendance details
- **Navigation**: Swipe or use arrows to change months

### Trend Analysis

- **Charts**: Bar charts showing attendance trends
- **Time Periods**: View by day, week, or month
- **Patterns**: Identify attendance patterns and trends

---

## ⚙️ Settings & Configuration

### GPS Settings

1. **Access GPS Settings**
   - From Settings → GPS Settings
   - Or from Main Navigation → Settings

2. **Configure Geofence**
   - Set institute location (latitude/longitude)
   - **Radius**: 30 meters (default)
   - **Auto-Migration**: Existing 25-meter settings upgraded to 30 meters

3. **Test Location**
   - Test if current location is within geofence
   - View geofence on map

### Theme Settings

- **Dark Mode Toggle**: Switch between light and dark themes
- **Persistent**: Theme choice saved automatically
- **System-Wide**: Applies to all screens

### Help & Support

- **Help Desk**: Access help documentation
- **FAQ**: Common questions and answers
- **Contact Support**: Reach out for assistance

---

## 🔄 App Flow Diagram

```
App Launch
    ↓
Splash Screen
    ↓
    ├─→ Not Logged In → Login Screen
    │       ↓
    │   Login (Email/PIN/Biometric)
    │       ↓
    │   Biometric Lock Screen (if enabled)
    │       ↓
    │   Main Navigation Screen
    │
    └─→ Logged In → Biometric Lock Screen (if enabled)
            ↓
        Main Navigation Screen
            ↓
        ├─→ Home Dashboard
        ├─→ Attendance Marking
        ├─→ Student Management
        ├─→ Batch Management
        ├─→ Reports
        └─→ Settings
```

---

## 📱 Main Screens

### 1. **Home Dashboard**
- Quick stats (Present, Absent, Total)
- Attendance rate percentage
- Quick access to all features
- Recent activity

### 2. **Attendance Screen**
- Mark entry/exit
- Student search
- Batch selection
- Face recognition
- GPS verification

### 3. **Student Management**
- View all students
- Search/filter students
- Edit student details
- Delete students
- Add new student

### 4. **Batch Management**
- View all batches
- Auto-generate batches
- Create manual batches
- Edit/delete batches
- Batch statistics

### 5. **Reports Screen**
- Date range selection
- Generate reports
- View attendance history
- Export reports

### 6. **Settings**
- GPS configuration
- Theme settings
- Help & support
- Logout

---

## 🗄️ Database Structure

### Firestore Collections

#### 1. **institutes/{instituteId}**
- Institute information
- Settings
- GPS configuration

#### 2. **institutes/{instituteId}/users/{userId}**
- User profiles
- Roles and permissions

#### 3. **institutes/{instituteId}/students/{studentId}**
- Student records
- Photos
- Face templates
- Batch assignments
- Subject enrollments

#### 4. **institutes/{instituteId}/batches/{batchId}**
- Batch information
- Timings
- Subjects
- Semester and year

#### 5. **institutes/{instituteId}/subjects/{subjectId}**
- Predefined subjects (8 subjects)
- Subject codes

#### 6. **attendance/{attendanceId}**
- Attendance records
- Entry/exit times
- Photos
- Locations
- Timestamps

---

## 🔒 Security Features

### 1. **Biometric Authentication**
- Fingerprint/Face ID
- Quick app unlock
- IRCTC-style implementation

### 2. **PIN Security**
- SHA-256 hashed PINs
- 4-6 digit PINs
- Secure storage

### 3. **Session Management**
- Auto-lock on app minimize
- Session expiry
- Secure logout

### 4. **GPS Geofencing**
- Location-based verification
- 30-meter radius restriction
- Prevents remote attendance marking

### 5. **Face Recognition**
- Biometric verification
- Prevents proxy attendance
- Photo-based identification

### 6. **Firestore Security Rules**
- Role-based access control
- Data validation
- Secure read/write permissions

---

## 📋 Use Cases

### Use Case 1: Daily Attendance Marking

1. Admin opens app
2. Biometric/PIN authentication
3. Navigate to Attendance screen
4. Select batch (optional)
5. Search for student
6. Mark entry (face recognition + GPS)
7. Mark exit (face recognition + GPS)
8. View attendance with photos

### Use Case 2: New Semester Setup

1. Admin navigates to Batch Management
2. Click "Auto-Generate Batches"
3. Set institute timings (e.g., 8 AM to 8 PM)
4. Select batch duration (60 or 120 minutes)
5. Select semester (1 or 2)
6. Select 2-3 subjects
7. Generate batches
8. System creates all batches automatically

### Use Case 3: Student Registration

1. Admin navigates to Add Student
2. Fill student details:
   - Name, Roll Number
   - Semester
   - Select multiple batches
   - Select 2-3 subjects
   - Contact number
   - Capture photo
3. Submit
4. System saves student and creates face template

### Use Case 4: Generate Monthly Report

1. Admin navigates to Reports
2. Select date range (max 1 month)
3. Generate report
4. View attendance statistics
5. Export/Share report

---

## 🎨 UI/UX Features

### Modern Design
- Glassmorphic design elements
- Smooth animations
- Responsive layout
- Dark mode support

### User Experience
- Intuitive navigation
- Quick access buttons
- Search functionality
- Visual feedback
- Error handling

### Accessibility
- Large touch targets
- Clear labels
- Color contrast
- Readable fonts

---

## 📱 Technical Stack

### Frontend
- **Flutter**: Cross-platform mobile framework
- **Dart**: Programming language
- **Material Design**: UI components

### Backend
- **Firebase Authentication**: User authentication
- **Cloud Firestore**: NoSQL database
- **Firebase Storage**: Photo storage
- **Firebase Functions**: Serverless functions (if needed)

### Services
- **Face Recognition**: ML Kit or custom implementation
- **GPS/Location**: Geolocator package
- **Biometric Auth**: Local authentication
- **Shared Preferences**: Local storage

---

## 🚀 Getting Started

### For Administrators

1. **First Time Setup**
   - Download and install app
   - Complete onboarding
   - Login with credentials
   - Enable biometric (optional)

2. **Configure Institute**
   - Set GPS location
   - Configure geofence radius (30 meters)
   - Set institute timings

3. **Create Batches**
   - Use auto-generate feature
   - Or create manually

4. **Add Students**
   - Register students with photos
   - Assign batches and subjects
   - Verify face templates

5. **Start Marking Attendance**
   - Use attendance screen
   - Mark entry/exit
   - Verify with face recognition

### For End Users

1. **Login**
   - Use email/password or PIN
   - Enable biometric for quick access

2. **Navigate**
   - Use bottom navigation
   - Access features from home screen

3. **Mark Attendance**
   - Select student
   - Mark entry/exit
   - Verify location

4. **View Reports**
   - Generate reports
   - View statistics
   - Export data

---

## 📞 Support & Help

### Help Desk
- Access from Settings → Help Desk
- FAQ section
- Contact support

### Documentation
- User guides
- Feature explanations
- Troubleshooting tips

---

## ✅ Summary

**EduSetu By Digitrix Media** is a comprehensive attendance management system that provides:

- ✅ **Secure Authentication**: IRCTC-style biometric and PIN
- ✅ **Flexible Batches**: 60-minute regular and 120-minute late admission
- ✅ **Multiple Subjects**: 2-3 subjects running simultaneously
- ✅ **Face Recognition**: Biometric verification for attendance
- ✅ **GPS Geofencing**: 30-meter radius location verification
- ✅ **Flexible Attendance**: Students can mark in any batch
- ✅ **Comprehensive Reports**: Date range reports with photos
- ✅ **Predefined Subjects**: 8 fixed computer typing subjects
- ✅ **Semester System**: Auto-detected year with predefined semesters
- ✅ **Modern UI**: Dark mode, animations, responsive design

The app is designed to be user-friendly, secure, and efficient for managing attendance in educational institutes.

---

**Version**: 1.0  
**Last Updated**: January 2026  
**Developed By**: Digitrix Media
