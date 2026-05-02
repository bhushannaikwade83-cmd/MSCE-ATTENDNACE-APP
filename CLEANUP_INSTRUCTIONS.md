# 🗑️ Remove Student: bhushan naiwkad

## Quick Steps

### Step 1: Find Student ID (in Supabase)

Go to **Supabase Dashboard** → **SQL Editor** and run:

```sql
SELECT id, name, institute_id
FROM students
WHERE LOWER(name) LIKE LOWER('%bhushan%naiwkad%')
LIMIT 5;
```

**Note the `id` value** (looks like UUID: `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`)

---

### Step 2: Delete All Data (in Supabase)

Replace `YOUR_STUDENT_ID` with the actual ID from Step 1, then run:

```sql
-- Delete attendance records
DELETE FROM attendance_records
WHERE student_id = 'YOUR_STUDENT_ID';

-- Delete face registration embedding
DELETE FROM student_registrations
WHERE student_id = 'YOUR_STUDENT_ID';

-- Delete student record
DELETE FROM students
WHERE id = 'YOUR_STUDENT_ID';
```

---

### Step 3: Verify Deletion

Run this to confirm everything is removed:

```sql
SELECT
  (SELECT COUNT(*) FROM students WHERE id = 'YOUR_STUDENT_ID') as students_left,
  (SELECT COUNT(*) FROM student_registrations WHERE student_id = 'YOUR_STUDENT_ID') as registrations_left,
  (SELECT COUNT(*) FROM attendance_records WHERE student_id = 'YOUR_STUDENT_ID') as attendance_left;
```

**Expected:** All values should be `0`

---

### Step 4: Delete Photos from B2 (Optional)

If you want to also remove photos from B2 storage:

**Go to B2 Console** → Find files with paths:
- `registrations/{institute_id}/{student_id}_registration.jpg`
- `attendance/{institute_id}/{student_id}_*.jpg`

Delete them manually from the B2 console.

---

## Complete SQL Script

Or run everything at once with this script:

```sql
-- Replace YOUR_STUDENT_ID with actual student ID
BEGIN;

-- Delete attendance
DELETE FROM attendance_records WHERE student_id = 'YOUR_STUDENT_ID';

-- Delete registration embedding
DELETE FROM student_registrations WHERE student_id = 'YOUR_STUDENT_ID';

-- Delete student
DELETE FROM students WHERE id = 'YOUR_STUDENT_ID';

-- Verify
SELECT 
  'DELETED' as status,
  'YOUR_STUDENT_ID' as student_id,
  NOW() as deleted_at;

COMMIT;
```

---

## Result ✅

After following these steps:
- ✅ Student removed from database
- ✅ All attendance records deleted
- ✅ Face embedding deleted
- ✅ Registration photo URL reference deleted
- ⚠️ Photos in B2 storage (optional manual cleanup)

**The student "bhushan naiwkad" will be completely removed from the system.**
