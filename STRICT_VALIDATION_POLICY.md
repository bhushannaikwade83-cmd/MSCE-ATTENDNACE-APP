# Strict Validation Policy - No Editing Allowed

## Overview

**STRICT MODE ENABLED** ✅

Once a student is registered with:
- ✅ Name
- ✅ Mobile Number  
- ✅ Photo/Face

These **CANNOT be changed** - even for editing existing students.

---

## Policy Details

### **Student Name** 🚫
- **Once set**: LOCKED
- **Cannot be edited to**: Any name already in the system
- **Even if**: It's the same student trying to update
- **Error Message**: "Student with name 'X' already exists. Each student must have a unique name. Cannot edit to duplicate name."

### **Mobile Number** 🚫
- **Once set**: LOCKED
- **Cannot be edited to**: Any mobile already in the system
- **Even if**: It's the same student trying to update
- **Error Message**: "Mobile number X already registered. Cannot edit to duplicate mobile."

### **Photo/Face** 🚫
- **Once registered**: LOCKED
- **Cannot be changed to**: Any face already in the system
- **Even if**: Same student wants to update their photo
- **Error Message**: "Face already registered to another student. Cannot edit to duplicate photo."

---

## Why This Policy?

✅ **Data Integrity** - No accidental overwrites
✅ **Security** - Prevents impersonation/fraud  
✅ **Audit Trail** - Every registration is permanent
✅ **Simple** - One name = One student, always
✅ **Legal Compliance** - Complete attendance records require fixed identities

---

## What CAN Be Edited?

| Field | Can Edit? | Notes |
|-------|-----------|-------|
| Name | ❌ NO | Permanently locked |
| Mobile | ❌ NO | Permanently locked |
| Photo | ❌ NO | Permanently locked |
| Batch | ✅ YES | Can change |
| Subject | ✅ YES | Can change |
| Email | ✅ YES | Can change |
| Address | ✅ YES | Can change |
| Status | ✅ YES | Can change |

---

## Implementation

### **Validation Code**

```dart
import 'package:smart_attendance_app/services/student_validation_service.dart';

// ALWAYS validate - applies to both NEW and EDITING
final error = await StudentValidationService.validateNewStudentRegistration(
  studentName: newName,
  mobileNumber: newMobile,
  instituteId: instituteId,
);

if (error != null) {
  // Block the operation
  showError(error);
  return;
}

// Safe to proceed
saveStudent();
```

### **No Exclusions**

The old code had:
```dart
// ❌ OLD - ALLOWED EXCEPTIONS
excludeStudentId: 'STU_001' // Could edit own name
```

The new code has:
```dart
// ✅ NEW - STRICT, NO EXCEPTIONS
excludeStudentId: null // All validations apply
```

---

## User Scenarios

### Scenario 1: New Student Registration
```
User enters: Name = "John Doe", Mobile = "9876543210"
System checks: Is "John Doe" taken? Is "9876543210" taken?
Result: ✅ Allow if both unique
        ❌ Block if either exists
```

### Scenario 2: Edit Student Name
```
User wants to change: "John Doe" → "John D"
System checks: Is "John D" taken in the system?
Result: ❌ BLOCK - even if it's John's own student record
        This prevents accidental name changes
```

### Scenario 3: Re-register Student Photo
```
User wants to: Update photo for Student 001
System checks: Is this face already registered?
Result: ❌ BLOCK - Cannot change registered photo
        User must deactivate old record and create new one
```

### Scenario 4: Edit Other Fields
```
User wants to change: Batch or Subject for existing student
System checks: Only name, mobile, photo are locked
Result: ✅ ALLOW - Other fields can be freely edited
```

---

## Error Scenarios

### ❌ Duplicate Name
```
Error: "Student with name 'X' already exists. 
Each student must have a unique name. 
Cannot edit to duplicate name."

Action: Use a different name
```

### ❌ Duplicate Mobile
```
Error: "Mobile number X already registered to another student. 
Each student must have a unique mobile number. 
Cannot edit to duplicate mobile."

Action: Use a different mobile number
```

### ❌ Duplicate Photo
```
Error: "Face already registered to another student. 
Cannot edit to duplicate photo."

Action: Use a different photo/face
```

---

## What If Student Name Actually Changed?

**Real-world scenario**: Student got married, changed name legally

### Solution
You MUST create a new student record:

1. **Deactivate** old record (Mark as inactive)
2. **Create NEW** record with new name
3. **Link records** in comments/notes for reference
4. **Migrate attendance** if needed (admin operation)

```dart
// In admin panel
// Student: John Doe (ID: STU_001) - Status: INACTIVE
// Student: Jane Smith (ID: STU_002) - Status: ACTIVE
// Note: Jane Smith is previous John Doe - transferred from STU_001
```

---

## Database Constraints

These validations are now STRICT in the system:

```sql
-- Name must be unique per institute
ALTER TABLE students ADD CONSTRAINT unique_name_per_institute
UNIQUE (institute_id, LOWER(name));

-- Mobile must be unique per institute (if provided)
ALTER TABLE students ADD CONSTRAINT unique_mobile_per_institute
UNIQUE (institute_id, contact_number) 
WHERE contact_number IS NOT NULL;

-- Face embeddings prevent duplicates via application logic
-- (Database level: no direct constraint, but application blocks)
```

---

## Testing the Strict Policy

### Test 1: Block Duplicate Name
```
✅ Register: "Alice" with mobile "9999999999"
❌ Try to register: "Alice" with mobile "8888888888"
Result: Error shown, registration blocked
```

### Test 2: Block Duplicate Mobile
```
✅ Register: "Bob" with mobile "9999999999"
❌ Try to register: "Robert" with mobile "9999999999"
Result: Error shown, registration blocked
```

### Test 3: Block Duplicate Photo
```
✅ Register: Student "Charlie" with photo X
❌ Try to register: Student "Charles" with same photo X
Result: Error shown, registration blocked
```

### Test 4: Edit Attempts
```
✅ Existing: Student "David" with mobile "7777777777"
❌ Try to edit: Change name to "Diana" (who already exists)
Result: Error shown, edit blocked
```

---

## FAQ

**Q: What if a student's name is misspelled during registration?**
A: Unfortunately, the name is locked. You would need to:
   1. Create a new record with correct name
   2. Deactivate old record
   3. Transfer attendance records (admin operation)

**Q: Can a parent change the student's phone number?**
A: No. Phone numbers are locked once registered. It's considered a security feature to prevent account takeover. Parents should contact the institute to change this.

**Q: What if the student changes schools?**
A: Create a new student record at the new school. The old record remains in the old school's system for historical records.

**Q: Is there an admin override?**
A: No. Even administrators cannot bypass these validations. This ensures data integrity and prevents accidental changes.

---

## Admin Operations (If Needed)

### For Super-Admin to Fix Issues

```dart
// Super-admin operation - not exposed to regular admin
// Only use in extreme cases (data migration, corrections)

// 1. Deactivate old student
await db.from('students')
  .update({'status': 'inactive'})
  .eq('id', oldStudentId);

// 2. Create new student record
// 3. Manually migrate attendance records
// 4. Keep audit trail of changes
```

---

## Summary

| Aspect | Before | After |
|--------|--------|-------|
| Name Editing | ✅ Allowed | ❌ BLOCKED |
| Mobile Editing | ✅ Allowed | ❌ BLOCKED |
| Photo Editing | ✅ Allowed | ❌ BLOCKED |
| Validation Applies | Only new students | Both new AND editing |
| Exemptions | Some allowed | NONE |

**Result: 100% Data Integrity** ✅
