# Student Registration Guide - How It Works

## 📋 Overview

The **Student Registration** feature allows admins to add students to the system with all necessary information including semester, batches, subjects, and face photo for attendance verification.

---

## 🎯 Registration Flow

### Step 1: Access the Screen
1. Go to **Student Management** screen
2. Click **"Add Student"** button (or FAB with ➕ icon)
3. The **Add Student** screen opens

### Step 2: Fill in Student Details

#### Required Fields:

1. **Full Name**
   - Enter student's full name
   - Example: "John Doe"

2. **Roll Number (G.R. No.)**
   - Enter unique roll number
   - Example: "ROLL001"
   - Must be unique within the institute

3. **Year**
   - Enter academic year
   - Example: "First Year", "Second Year", etc.

4. **Semester** (Dropdown)
   - Select from predefined semesters:
     - **Semester 1**: Jan to Jun 2026
     - **Semester 2**: Jul to Dec 2026
   - Year is auto-detected from device date
   - Default: Current semester

5. **Select Batches** (Multiple Selection - Checkboxes)
   - Select one or more batches
   - Shows batch name, year, and timing
   - Example:
     - ✅ Batch 1 (08:00 - 09:00) (2026)
     - ✅ Batch 2 (09:00 - 10:00) (2026)
   - **Note**: Batch timing is automatically used from selected batch (no manual time entry)

6. **Select Subjects** (Multiple Selection - Checkboxes)
   - Select one or more subjects
   - Example:
     - ✅ GCC TBC English 30
     - ✅ GCC TBC English 40
     - ✅ GCC TBC English 50
   - **Note**: Subjects are predefined in the database

7. **Contact Number**
   - Enter student's contact number
   - Example: "1234567890"

8. **Face Photo** (Required)
   - Click **"Take Photo"** button
   - Camera opens to capture student's face
   - Photo is used for:
     - Face recognition during attendance marking
     - Preventing photo-of-photo fraud
   - **Note**: Face photo is mandatory for attendance verification

### Step 3: Submit

Click **"Add Student"** button. The system will:

1. **Validate all fields**
2. **Check for duplicate roll number** (within same batch)
3. **Save student data** to Firestore
4. **Save face template** for face recognition
5. **Increment batch student count** for all selected batches
6. **Show success message**

---

## 📊 Data Structure

### Student Document in Firestore

**Path:** `institutes/{instituteId}/students/{studentId}`

**Fields:**
```json
{
  "uid": "MANUAL_1234567890",
  "userId": "ROLL001",
  "name": "John Doe",
  "email": "",
  "phoneNumber": "1234567890",
  "year": "First Year",
  "semester": "1-2026",
  "semesterName": "Semester 1 - Jan to Jun 2026",
  "batchId": "batch123",              // Primary batch ID
  "batchIds": ["batch123", "batch456"], // Multiple batch IDs
  "batchName": "Batch 1 (08:00 - 09:00), Batch 2 (09:00 - 10:00)",
  "batchTiming": "08:00 - 09:00; 09:00 - 10:00",
  "subject": "GCC TBC English 30, GCC TBC English 40", // For backward compatibility
  "subjects": ["GCC TBC English 30", "GCC TBC English 40"], // Multiple subjects
  "role": "student",
  "status": "approved",
  "hasDevice": false,
  "instituteId": "institute123",
  "createdAt": "2026-01-15T10:30:00Z",
  "lastLogin": null
}
```

---

## 🔍 Key Features

### 1. **Multiple Batch Selection**
- Students can be assigned to multiple batches
- Example: A student can attend both morning (8-9 AM) and evening (6-7 PM) batches
- All selected batches are stored in `batchIds` array

### 2. **Multiple Subject Selection**
- Students can be enrolled in multiple subjects
- Example: A student can take English 30, English 40, and English 50
- All selected subjects are stored in `subjects` array

### 3. **Semester Management**
- Semester is predefined (1 or 2)
- Year is auto-detected from device date
- Format: `"1-2026"` or `"2-2026"`

### 4. **Face Recognition**
- Face photo is **mandatory** for attendance verification
- Face template is saved during registration
- Used to verify student identity during attendance marking
- Prevents photo-of-photo fraud

### 5. **Batch Timing Auto-Use**
- Batch timing is automatically taken from selected batch
- No manual time entry needed
- Ensures consistency with batch definitions

### 6. **Duplicate Prevention**
- Checks if roll number already exists in the same batch
- Prevents duplicate registrations
- Shows error message if duplicate found

---

## 📐 Example Registration

### Example 1: Single Batch Student

**Input:**
- Name: "John Doe"
- Roll Number: "ROLL001"
- Year: "First Year"
- Semester: "Semester 1 - Jan to Jun 2026"
- Batches: ✅ Batch 1 (08:00 - 09:00) (2026)
- Subjects: ✅ GCC TBC English 30
- Contact: "1234567890"
- Face Photo: ✅ Captured

**Result:**
- Student created with 1 batch and 1 subject
- Face template saved
- Batch student count incremented

### Example 2: Multiple Batch Student

**Input:**
- Name: "Jane Smith"
- Roll Number: "ROLL002"
- Year: "Second Year"
- Semester: "Semester 2 - Jul to Dec 2026"
- Batches: 
  - ✅ Batch 1 (08:00 - 09:00) (2026)
  - ✅ Batch 5 (12:00 - 13:00) (2026)
- Subjects: 
  - ✅ GCC TBC English 30
  - ✅ GCC TBC English 40
  - ✅ GCC TBC English 50
- Contact: "9876543210"
- Face Photo: ✅ Captured

**Result:**
- Student created with 2 batches and 3 subjects
- Face template saved
- Both batch student counts incremented

---

## ✅ Validation Rules

### Required Fields:
- ✅ Full Name (cannot be empty)
- ✅ Roll Number (cannot be empty, must be unique)
- ✅ Year (cannot be empty)
- ✅ Semester (must be selected)
- ✅ At least one Batch (must select at least one)
- ✅ At least one Subject (must select at least one)
- ✅ Contact Number (cannot be empty)
- ✅ Face Photo (must be captured)

### Duplicate Check:
- Roll number must be unique within the same batch
- If roll number exists in same batch, shows error:
  - "Roll Number already exists in this batch"

### Batch Requirements:
- At least one batch must exist before adding students
- If no batches, shows message:
  - "No batches found. Please create a batch first."

### Subject Requirements:
- At least one subject must exist
- If no subjects, default subjects are auto-created

---

## 🔧 Technical Details

### Face Template Saving:
1. Photo is captured using `ImagePicker`
2. Photo is verified for quality (not blurry, has face, etc.)
3. Face template is extracted using ML Kit
4. Template is saved to Firestore for attendance verification

### Batch Student Count:
- When student is added, all selected batches' `studentCount` is incremented
- This helps track how many students are in each batch

### Data Storage:
- Student data is stored in `institutes/{instituteId}/students/{studentId}`
- Face template is stored separately for face recognition
- All data is saved atomically (all or nothing)

---

## 🎨 UI Flow

```
Student Management Screen
    ↓
Click "Add Student" Button
    ↓
Add Student Screen Opens
    ↓
Fill in:
  - Name
  - Roll Number
  - Year
  - Select Semester (dropdown)
  - Select Batches (checkboxes - multiple)
  - Select Subjects (checkboxes - multiple)
  - Contact Number
  - Take Face Photo (camera)
    ↓
Click "Add Student" Button
    ↓
Validation:
  - All fields required?
  - Duplicate roll number?
  - At least one batch selected?
  - At least one subject selected?
  - Face photo captured?
    ↓
Saving:
  - Save student data to Firestore
  - Save face template
  - Increment batch student counts
    ↓
Success Message: "Student Added Successfully"
    ↓
Screen Closes
    ↓
Student List Refreshes (shows new student)
```

---

## 🆘 Troubleshooting

### Problem: "No batches found"
- **Solution**: Create batches first using Batch Management → Create Batch or Auto-Generate

### Problem: "Roll Number already exists"
- **Solution**: Use a different roll number, or check if student already exists

### Problem: "Please select at least one batch"
- **Solution**: Select at least one batch from the list

### Problem: "Please select at least one subject"
- **Solution**: Select at least one subject from the list

### Problem: "Please capture student face photo"
- **Solution**: Click "Take Photo" button and capture student's face

### Problem: "Photo is blurry"
- **Solution**: Ensure good lighting, hold camera steady, ensure face is clearly visible

### Problem: "No face detected"
- **Solution**: Ensure student's face is clearly visible in the camera frame

---

## 💡 Tips

1. **Batch Timing**: Batch timing is automatically used from selected batch - no need to enter manually
2. **Multiple Batches**: Students can be assigned to multiple batches (e.g., morning and evening)
3. **Multiple Subjects**: Students can be enrolled in multiple subjects
4. **Face Photo Quality**: Ensure good lighting and clear face visibility for better face recognition
5. **Roll Number**: Use consistent roll number format (e.g., "ROLL001", "STU001")
6. **Semester**: Semester is auto-selected based on current date, but can be changed

---

## 🔄 Alternative: MSCE Portal Integration

**Note**: The system also supports fetching students from MSCE portal (mentioned in requirements). This feature would:
- Fetch student data (Name, G.R. No., Semester, Contact, Subject, Photo)
- Allow institute to assign Batch Time later
- Currently, this is a planned feature

---

## 📊 Example Use Cases

### Use Case 1: New Semester Registration
1. Semester 1 starts (Jan 2026)
2. Admin creates batches for Semester 1
3. Admin registers all students with:
   - Semester: "Semester 1 - Jan to Jun 2026"
   - Appropriate batches
   - Appropriate subjects
4. All students are ready for attendance marking

### Use Case 2: Student Taking Multiple Batches
1. Student wants to attend both morning (8-9 AM) and evening (6-7 PM) batches
2. Admin selects both batches during registration
3. Student can mark attendance in either batch

### Use Case 3: Student Taking Multiple Subjects
1. Student is enrolled in English 30, 40, and 50
2. Admin selects all three subjects during registration
3. Student's attendance is tracked for all three subjects

---

## ✅ Verification

After registration, verify:

1. **Student Management Screen**: Student should appear in the list
2. **Firestore Console**: 
   - Go to `institutes/{instituteId}/students/{studentId}`
   - Check all fields are saved correctly
3. **Batch Management**: Batch student count should be incremented
4. **Face Recognition**: Student should be able to mark attendance using face recognition
