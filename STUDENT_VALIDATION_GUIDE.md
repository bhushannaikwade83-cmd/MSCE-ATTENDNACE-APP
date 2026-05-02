# Student Validation Guide - Prevent Duplicates

## Overview

The app now validates:
- ✅ **Duplicate Names** - One student name per institute
- ✅ **Duplicate Mobile** - One mobile number per institute
- ✅ **Duplicate Photos** - Same face cannot register twice
- ✅ **Duplicate Attendance** - Cannot mark same student twice in one day

---

## 1. Validating During Student Registration

### Where to Add

File: `lib/presentation/screens/add_student_screen.dart` (in the save button handler)

### Code Example

```dart
import 'package:smart_attendance_app/services/student_validation_service.dart';

// In your save button onPressed handler
Future<void> _saveStudent() async {
  // Get form values
  final name = _nameController.text.trim();
  final mobile = _mobileController.text.trim();
  final photoPath = _capturedPhotoPath; // Your photo path variable

  // Step 1: Validate basic info (name, mobile, etc)
  final basicError = await StudentValidationService.validateNewStudentRegistration(
    studentName: name,
    mobileNumber: mobile,
    instituteId: _instituteId,
  );

  if (basicError != null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(basicError), backgroundColor: Colors.red),
    );
    return;
  }

  // Step 2: Validate photo is unique
  final photoError = await StudentValidationService.validateDuplicatePhoto(
    photoPath: photoPath,
    instituteId: _instituteId,
  );

  if (photoError != null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(photoError), backgroundColor: Colors.red),
    );
    return;
  }

  // Step 3: If all validations pass, save the student
  // ... your existing save logic ...
  
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('✅ Student registered successfully!'), backgroundColor: Colors.green),
  );
}
```

---

## 2. Validating During Attendance Marking

### Where to Add

File: `lib/presentation/screens/admin_attendance_screen.dart` (when student is selected)

### Code Example

```dart
import 'package:smart_attendance_app/services/student_validation_service.dart';

// When marking attendance for a student
Future<void> _markAttendance(String studentId) async {
  // Validate student is ready and not already marked
  final error = await StudentValidationService.validateAttendanceMarking(
    studentId: studentId,
    instituteCode: _instituteCode,
    instituteId: _instituteId,
    attendanceDate: DateTime.now(),
  );

  if (error != null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error), backgroundColor: Colors.red),
    );
    return;
  }

  // If validation passes, proceed with attendance marking
  // ... your existing attendance marking logic ...
}
```

---

## 3. Validating Student Name

### Standalone Usage

```dart
import 'package:smart_attendance_app/services/student_validation_service.dart';

// Check if name already exists
final nameError = await StudentValidationService.validateDuplicateName(
  studentName: 'John Doe',
  instituteId: 'INST_001',
);

if (nameError != null) {
  print('❌ Error: $nameError');
} else {
  print('✅ Name is available');
}
```

### In Real-Time Validation (TextField)

```dart
TextFormField(
  controller: _nameController,
  decoration: InputDecoration(
    labelText: 'Student Name',
    errorText: _nameError, // Show error dynamically
  ),
  onChanged: (value) async {
    // Validate as user types (debounce for performance)
    if (value.length > 2) {
      final error = await StudentValidationService.validateDuplicateName(
        studentName: value,
        instituteId: _instituteId,
      );
      setState(() => _nameError = error);
    }
  },
)
```

---

## 4. Validating Mobile Number

### Standalone Usage

```dart
// Check if mobile already exists
final mobileError = await StudentValidationService.validateDuplicateMobileNumber(
  mobileNumber: '9876543210',
  instituteId: 'INST_001',
);

if (mobileError != null) {
  print('❌ Error: $mobileError');
} else {
  print('✅ Mobile number is available');
}
```

### With Validation Rules

```dart
// Mobile number must be:
// - 10 digits
// - Unique per institute
// - Not assigned to another student

final error = await StudentValidationService.validateDuplicateMobileNumber(
  mobileNumber: '+919876543210',  // Will fail - includes +91
  instituteId: 'INST_001',
);
// Returns: "Mobile number must be 10 digits"
```

---

## 5. Validating Duplicate Photos

### Usage During Registration

```dart
// After student captures photo
final photoError = await StudentValidationService.validateDuplicatePhoto(
  photoPath: '/path/to/photo.jpg',
  instituteId: _instituteId,
);

if (photoError != null) {
  print('❌ $photoError');
  // Show error to user
} else {
  print('✅ Photo is unique - can proceed with registration');
}
```

---

## 6. Validating Duplicate Attendance

### Usage Before Marking Attendance

```dart
// Check if student already marked attendance today
final attendanceError = await StudentValidationService.validateDuplicateAttendanceToday(
  studentId: 'STU_001',
  instituteCode: 'INST_001',
  attendanceDate: DateTime.now(),
);

if (attendanceError != null) {
  print('⚠️ $attendanceError');
  // Show warning to user
} else {
  print('✅ Student can be marked for attendance');
}
```

---

## 7. Editing Existing Student

When editing, exclude the current student ID to allow keeping their own data:

```dart
// Validating name when EDITING (not creating)
final nameError = await StudentValidationService.validateDuplicateName(
  studentName: 'John Doe',
  instituteId: 'INST_001',
  excludeStudentId: 'STU_001', // Current student ID
);

// Now it will allow 'John Doe' if the current student is already named that
// But will reject if another student named 'John Doe' exists
```

---

## Error Messages Returned

### Name Validation
```
✅ null = Name is unique
❌ "Student with name "X" already exists. Names must be unique per institute."
❌ "Student name cannot be empty"
⚠️ "Error checking duplicate name: ..."
```

### Mobile Validation
```
✅ null = Mobile is unique
❌ "Mobile number must be 10 digits"
❌ "Mobile number 98765432110 already registered to another student."
⚠️ "Error checking mobile: ..."
```

### Photo Validation
```
✅ null = Photo is unique
❌ "This face is already registered for another student (Roll X)."
❌ "Could not read face from photo. Try a clearer photo."
⚠️ "Error checking photo: ..."
```

### Attendance Validation
```
✅ null = Ready for attendance
❌ "Student face not registered. Register face first..."
❌ "This student already has attendance marked for today..."
⚠️ "Error checking attendance: ..."
```

---

## Database Queries Used

### Check Duplicate Name
```sql
SELECT id, name FROM students 
WHERE institute_id = ? 
AND LOWER(name) = LOWER(?)
AND id != ? -- Exclude self when editing
```

### Check Duplicate Mobile
```sql
SELECT id, contact_number FROM students 
WHERE institute_id = ? 
AND contact_number = ?
AND id != ? -- Exclude self when editing
```

### Check Duplicate Attendance
```sql
SELECT id FROM attendance_in_out 
WHERE student_id = ? 
AND institute_code = ? 
AND attendance_date = ?
```

---

## Performance Considerations

✅ **Optimized for Real-Time:**
- Queries are indexed by institute_id
- Use async/await to not block UI
- Consider debouncing for real-time validation

```dart
// Example debounce implementation
Timer? _debounce;

void _validateName(String value) {
  if (_debounce?.isActive ?? false) _debounce?.cancel();
  _debounce = Timer(const Duration(milliseconds: 500), () async {
    final error = await StudentValidationService.validateDuplicateName(
      studentName: value,
      instituteId: _instituteId,
    );
    setState(() => _nameError = error);
  });
}
```

---

## Security Features

✅ **Duplicate Photo Detection:**
- Uses face embedding comparison
- 75% similarity blocks duplicate
- Prevents fraudulent registrations

✅ **Cross-Checking:**
- Prevents same mobile for multiple students
- Prevents same name for multiple students
- Prevents attendance fraud (double marking)

✅ **Graceful Editing:**
- Allows keeping original data when editing
- Uses excludeStudentId parameter
- Won't block student's own name/mobile

---

## Implementation Checklist

- [ ] Import `StudentValidationService` in add_student_screen.dart
- [ ] Add validation before saving new student
- [ ] Add photo validation after photo capture
- [ ] Import `StudentValidationService` in attendance_screen.dart
- [ ] Add validation before marking attendance
- [ ] Add real-time validation for name (optional)
- [ ] Add real-time validation for mobile (optional)
- [ ] Test with duplicate names
- [ ] Test with duplicate mobile numbers
- [ ] Test with duplicate photos
- [ ] Test duplicate attendance marking
- [ ] Test editing existing student

---

## Example: Complete Registration Flow

```dart
Future<void> _completeRegistration() async {
  final name = _nameController.text.trim();
  final mobile = _mobileController.text.trim();
  final photoPath = _capturedPhoto;

  // 1. Validate name & mobile
  final basicError = await StudentValidationService.validateNewStudentRegistration(
    studentName: name,
    mobileNumber: mobile,
    instituteId: _instituteId,
  );
  if (basicError != null) {
    _showError(basicError);
    return;
  }

  // 2. Validate photo is unique
  final photoError = await StudentValidationService.validateDuplicatePhoto(
    photoPath: photoPath,
    instituteId: _instituteId,
  );
  if (photoError != null) {
    _showError(photoError);
    return;
  }

  // 3. Save student to database
  final success = await _saveStudentToDatabase(name, mobile, photoPath);
  if (success) {
    _showSuccess('✅ Student registered successfully!');
    Navigator.pop(context);
  } else {
    _showError('Failed to save student');
  }
}
```

---

**All validations are now in place to prevent duplicates!** 🎉
