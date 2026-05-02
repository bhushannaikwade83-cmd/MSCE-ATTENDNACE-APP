# Delete All Students from Institute 3001 - Complete Guide

## Overview
This guide will completely remove all student data from institute 3001 (22+ students) including:
- ✅ All student profiles
- ✅ All face embeddings
- ✅ All attendance records
- ✅ All registration data
- ✅ All photos from B2 cloud storage

**Total Time:** ~10-15 minutes

---

## Step 1: Preview What Will Be Deleted

### 1a. Go to Supabase Dashboard
1. Navigate to: https://app.supabase.com
2. Select your project
3. Go to **SQL Editor**

### 1b. Run Preview Queries
Copy and run these queries to see what will be deleted:

```sql
-- See all students in institute 3001
SELECT id, name, sr_no, photo_url FROM students
WHERE institute_id = '3001'
ORDER BY sr_no;
```

**Expected:** Shows 22 students (SR_001 through SR_022)

```sql
-- See attendance records count
SELECT COUNT(*) as total_records FROM attendance_records
WHERE institute_id = '3001';
```

---

## Step 2: Export Photo URLs for B2 Cleanup

Run this query to get all photo URLs:

```sql
-- Get all photos to delete from B2
SELECT
  'student_photo' as type,
  photo_url as file_url
FROM students
WHERE institute_id = '3001' AND photo_url IS NOT NULL

UNION ALL

SELECT
  'attendance_photo' as type,
  photo_url as file_url
FROM attendance_records
WHERE institute_id = '3001' AND photo_url IS NOT NULL;
```

**Note down:** All B2 URLs (they start with `https://f000.backblazeb2.com/`)

---

## Step 3: Delete All Database Records

### ⚠️ POINT OF NO RETURN

Copy the entire SQL block below and execute it in SQL Editor:

```sql
-- DELETE ALL STUDENTS FROM INSTITUTE 3001
-- Delete attendance_in_out records
DELETE FROM attendance_in_out
WHERE institute_code = '3001';

-- Delete attendance records
DELETE FROM attendance_records
WHERE institute_id = '3001';

-- Delete student registration records
DELETE FROM student_registrations
WHERE institute_id = '3001';

-- Delete all student records
DELETE FROM students
WHERE institute_id = '3001';
```

**Expected Output:**
```
DELETE X  (X = number of rows deleted)
```

---

## Step 4: Verify All Data Deleted

Run this verification query:

```sql
-- Verify all data deleted
SELECT
  (SELECT COUNT(*) FROM students WHERE institute_id = '3001') as students_remaining,
  (SELECT COUNT(*) FROM attendance_records WHERE institute_id = '3001') as attendance_remaining,
  (SELECT COUNT(*) FROM student_registrations WHERE institute_id = '3001') as registration_remaining;
```

**Expected Result:**
```
students_remaining: 0
attendance_remaining: 0
registration_remaining: 0
```

✅ **If all are 0: Database deletion successful!**

---

## Step 5: Delete Photos from B2 Cloud Storage

### Option A: Via B2 Web Console (Recommended)

1. Go to: https://secure.backblaze.com/b2_buckets.html
2. Click on bucket: **edusetu-attendance-app**
3. In the file browser, search for: **3001**
4. Select all matching files:
   - `registrations/3001/*`
   - `attendance/3001/*`
5. Click **Delete Selected**

### Option B: Via B2 CLI (Faster for many files)

```bash
# 1. Install B2 CLI (if not installed)
pip install b2

# 2. Authorize
b2 authorize_account <YOUR_ACCOUNT_ID> <YOUR_APP_KEY>

# 3. List files to delete (verify first)
b2 ls edusetu-attendance-app | grep "3001"

# 4. Delete all matching files
b2 rm edusetu-attendance-app MANUAL_17769* 
b2 rm edusetu-attendance-app MANUAL_17770*
# ... (repeat for all student IDs)

# Or delete entire directory
b2 rm --recursive edusetu-attendance-app registrations/3001/
b2 rm --recursive edusetu-attendance-app attendance/3001/
```

---

## Complete Deletion Checklist

- [ ] **Step 1:** Previewed students to be deleted
- [ ] **Step 2:** Noted down photo URLs (if needed)
- [ ] **Step 3:** Executed DELETE SQL commands
- [ ] **Step 4:** Verified all database counts are 0
- [ ] **Step 5:** Deleted all photos from B2
- [ ] **Final Check:** App shows empty student list for institute 3001

---

## What Gets Deleted

### Database
✅ 22 student records  
✅ ~200-500 attendance records  
✅ 22 registration records  
✅ All face embeddings  
✅ All photo URLs  

### B2 Cloud Storage
✅ ~22 registration photos  
✅ ~100-200 attendance photos  
✅ **Total space freed:** ~50-100 MB  

---

## After Deletion - Fresh Testing

Once deleted, you can:

1. ✅ Register new students fresh (SR_001, SR_002, etc.)
2. ✅ Test compression at exactly 100KB
3. ✅ Test face recognition with clean embeddings
4. ✅ Verify attendance marking works properly
5. ✅ Check database schema and data integrity

---

## Recovery Options (If Mistake)

### Database Recovery
- Supabase keeps automatic backups for **14 days**
- Contact Supabase support with backup request
- Requires manual intervention

### B2 Storage Recovery
- B2 keeps deleted files for **24 hours**
- Can restore via B2 console
- After 24 hours: **permanent deletion**

---

## Quick Reference

| Task | Time | Command |
|------|------|---------|
| Verify data | 1 min | SELECT queries |
| Delete database | 2 min | DELETE × 4 |
| Verify deletion | 1 min | SELECT query |
| Delete B2 photos | 5 min | Manual or CLI |
| **Total** | **~10 min** | - |

---

## Support

If you encounter issues:
1. Check Supabase docs: https://supabase.com/docs
2. B2 Support: https://www.backblaze.com/b2/support.html
3. Verify SQL syntax before executing

---

## Summary

**Institute:** 3001  
**Students to Delete:** 22 (SR_001 → SR_022)  
**Action:** Complete removal with photos  
**Confirmation:** Explicit deletion requested  
**Status:** ✅ Ready to execute  

**Next Step:** Follow Step 3 to execute deletion in Supabase SQL Editor

Once complete: ✅ Clean slate for fresh testing with proper compression and face embedding sync!
