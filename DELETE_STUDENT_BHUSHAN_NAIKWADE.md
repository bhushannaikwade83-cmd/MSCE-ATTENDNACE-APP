# Delete Student: Bhushan Naikwade - Complete Deletion Guide

## ⚠️ WARNING: Permanent Deletion

This guide will **permanently delete**:
- ✅ Student record (all profile data)
- ✅ All attendance records
- ✅ Face registration embedding
- ✅ Photos from B2 cloud storage
- ✅ All associated database entries

**This action CANNOT be undone**

---

## Step 1: Find Student ID

Go to **Supabase Dashboard** → **SQL Editor** and run:

```sql
SELECT 
  id,
  name,
  sr_no,
  user_id,
  institute_id,
  created_at
FROM students
WHERE 
  LOWER(name) LIKE LOWER('%bhushan%naikw%')
  OR LOWER(name) LIKE LOWER('%naikw%bhushan%')
LIMIT 5;
```

**Note down the student ID** (looks like `student_xxx_yyy`)

---

## Step 2: Find All Photos to Delete

Before deleting database records, identify all photos in B2:

```sql
-- Find registration photo
SELECT 
  'registration' as type,
  face_photo_url,
  photo_url
FROM students
WHERE id = 'STUDENT_ID_FROM_STEP_1';

-- Find all attendance photos
SELECT 
  'attendance' as type,
  COUNT(*) as photo_count,
  STRING_AGG(id, ',') as record_ids
FROM attendance_records
WHERE student_id = 'STUDENT_ID_FROM_STEP_1';
```

---

## Step 3: Delete All Database Records

Run these DELETE statements IN ORDER:

```sql
-- Step 3a: Delete all attendance records
DELETE FROM attendance_records
WHERE student_id = 'STUDENT_ID_FROM_STEP_1';

-- Step 3b: Delete face registration data (if using separate table)
DELETE FROM students_registrations
WHERE student_id = 'STUDENT_ID_FROM_STEP_1';

-- Step 3c: Delete student record (FINAL - after all references deleted)
DELETE FROM students
WHERE id = 'STUDENT_ID_FROM_STEP_1';
```

---

## Step 4: Verify Deletion

```sql
-- Should return 0 rows
SELECT COUNT(*) FROM students 
WHERE id = 'STUDENT_ID_FROM_STEP_1';

-- Should return 0 rows
SELECT COUNT(*) FROM attendance_records 
WHERE student_id = 'STUDENT_ID_FROM_STEP_1';

-- Should return 0 rows
SELECT COUNT(*) FROM students_registrations 
WHERE student_id = 'STUDENT_ID_FROM_STEP_1';
```

---

## Step 5: Delete Photos from B2 Cloud Storage

### Option A: Via B2 Web Console
1. Go to **B2 Cloud Storage Console**
2. Open bucket: `edusetu-attendance-app`
3. Navigate to:
   - `registrations/{institute_id}/{student_id}*` - Delete all registration photos
   - `attendance/{institute_id}/{student_id}_*.jpg` - Delete all attendance photos
4. Delete each file manually

### Option B: Via B2 CLI

```bash
# Install B2 CLI (if not already installed)
pip install b2

# Configure B2 credentials
b2 authorize_account YOUR_ACCOUNT_ID YOUR_APP_KEY

# Delete registration photos
b2 ls edusetu-attendance-app registrations/ | grep 'STUDENT_ID_FROM_STEP_1' | awk '{print $1}' | xargs -I {} b2 delete-file-version {} registrations/{}

# Delete attendance photos
b2 ls edusetu-attendance-app attendance/ | grep 'STUDENT_ID_FROM_STEP_1' | awk '{print $1}' | xargs -I {} b2 delete-file-version {} attendance/{}
```

### Option C: Programmatically (Dart)

The app can delete files by calling:

```dart
// Delete a photo from B2
await B2BStorageService.deleteFile('path/to/photo.jpg');
```

---

## Complete SQL Script

**Copy and paste this into Supabase SQL Editor** (after replacing STUDENT_ID):

```sql
-- ============================================
-- DELETE STUDENT: Bhushan Naikwade - COMPLETE
-- ============================================
-- ⚠️ WARNING: PERMANENT DELETION - Cannot be undone
-- 
-- Replace 'STUDENT_ID_HERE' with actual student ID
-- 
-- ============================================

-- 1. VERIFY: Show student being deleted
SELECT 
  id, name, sr_no, user_id, institute_id, created_at
FROM students
WHERE id = 'STUDENT_ID_HERE'
LIMIT 1;

-- 2. COUNT: How many attendance records will be deleted
SELECT 
  COUNT(*) as attendance_records_to_delete
FROM attendance_records
WHERE student_id = 'STUDENT_ID_HERE';

-- 3. BACKUP: Show attendance record details (for reference)
SELECT 
  id, attended_at, embedding_similarity, photo_url
FROM attendance_records
WHERE student_id = 'STUDENT_ID_HERE'
ORDER BY attended_at DESC;

-- ============================================
-- DELETION (Execute in this order)
-- ============================================

-- 4. DELETE: All attendance records
DELETE FROM attendance_records
WHERE student_id = 'STUDENT_ID_HERE';

-- 5. DELETE: Face registration data
DELETE FROM students_registrations
WHERE student_id = 'STUDENT_ID_HERE';

-- 6. DELETE: Student record (FINAL)
DELETE FROM students
WHERE id = 'STUDENT_ID_HERE';

-- ============================================
-- VERIFY: Deletion successful
-- ============================================

-- All should return 0 rows
SELECT COUNT(*) as students_remaining
FROM students 
WHERE id = 'STUDENT_ID_HERE';

SELECT COUNT(*) as attendance_remaining
FROM attendance_records 
WHERE student_id = 'STUDENT_ID_HERE';

SELECT COUNT(*) as registration_remaining
FROM students_registrations 
WHERE student_id = 'STUDENT_ID_HERE';
```

---

## Deletion Checklist

- [ ] **Step 1:** Found student ID and noted it down
- [ ] **Step 2:** Identified all photos to delete (for B2 cleanup)
- [ ] **Step 3:** Ran DELETE statements in SQL Editor
- [ ] **Step 4:** Verified all database records deleted (0 count)
- [ ] **Step 5:** Deleted photos from B2 Cloud Storage
- [ ] **Final Check:** No database records remain for this student

---

## What Gets Deleted

### Database Tables

#### students
- ❌ Name: Bhushan Naikwade
- ❌ Roll number (sr_no)
- ❌ Institute ID
- ❌ Face embedding data
- ❌ Profile photo URL

#### attendance_records
- ❌ All attendance entries for this student
- ❌ Attendance photos
- ❌ Similarity scores
- ❌ Attendance timestamps

#### students_registrations
- ❌ Face registration embedding
- ❌ Registration metadata

### B2 Cloud Storage

Photos deleted:
- ❌ `/registrations/{institute_id}/{student_id}_*.jpg`
- ❌ `/attendance/{institute_id}/{student_id}_*.jpg`

---

## After Deletion

✅ Student will not appear in:
- Student list
- Attendance marking screen
- Reports
- Any queries

✅ No orphaned data remains

✅ All photos removed from storage (no wasted space)

---

## Rollback / Recovery

**If deletion was done in error:**

1. Contact Supabase support for database restore
2. Database may have automatic backups
3. B2 may have deleted file recovery (within 24 hours)

**Best Practice:** Always keep backup before mass deletion

---

## Commands Summary

### Supabase SQL Dashboard
1. Navigate to: https://app.supabase.com → Project → SQL Editor
2. Paste the complete script above
3. Replace `STUDENT_ID_HERE` with actual ID from Step 1
4. Execute query

### B2 CLI (If using command line)
```bash
# List files to delete
b2 ls edusetu-attendance-app attendance/ | grep 'STUDENT_ID'

# Delete specific file
b2 delete-file-version {FILE_ID} {FILE_NAME}
```

---

## Support

If you encounter errors:

1. **FK Constraint Error:** Ensure you delete in correct order (attendance → registrations → students)
2. **File Not Found in B2:** Some photos may not exist - that's OK, just skip them
3. **Transaction Error:** Run one DELETE statement at a time instead of all together

---

**Date:** April 24, 2026
**Status:** Ready for Execution
**Confirmed User:** Yes - "deleteall with photos"
