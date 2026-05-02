# Execute Deletion: Student MANUAL_1776969546681 (Bhushan Naikwade)

## ⚠️ FINAL CONFIRMATION

**Student ID:** `MANUAL_1776969546681`  
**Name:** Bhushan Naikwade  
**Action:** Complete deletion with all photos  
**Status:** ✅ Confirmed - Ready to execute

---

## Execution Steps

### Phase 1: Database Deletion (5 minutes)

#### Step 1a: Verify Student Exists
1. Go to **Supabase Dashboard** → **SQL Editor**
2. Copy and run ONLY this query:

```sql
SELECT id, name, sr_no FROM students
WHERE id = 'MANUAL_1776969546681';
```

**Expected:** Shows 1 row with student details  
**If error:** Student ID may be incorrect - contact support

---

#### Step 1b: Identify Photos to Delete
Run this query to see all photos:

```sql
SELECT
  'student_photo' as type,
  photo_url as file_url
FROM students
WHERE id = 'MANUAL_1776969546681'
  AND photo_url IS NOT NULL

UNION ALL

SELECT
  'face_photo' as type,
  face_photo_url as file_url
FROM students
WHERE id = 'MANUAL_1776969546681'
  AND face_photo_url IS NOT NULL

UNION ALL

SELECT
  'attendance_photo' as type,
  photo_url as file_url
FROM attendance_records
WHERE student_id = 'MANUAL_1776969546681'
  AND photo_url IS NOT NULL;
```

**Note down any B2 URLs** (they look like: `https://f000.backblazeb2.com/...`)

---

#### Step 1c: Execute Deletion (POINT OF NO RETURN)

⚠️ **Once you run these commands, deletion CANNOT be undone**

Copy this entire block and run it in SQL Editor:

```sql
-- Delete attendance records
DELETE FROM attendance_records
WHERE student_id = 'MANUAL_1776969546681';

-- Delete registration data
DELETE FROM student_registrations
WHERE student_id = 'MANUAL_1776969546681';

-- Delete student record
DELETE FROM students
WHERE id = 'MANUAL_1776969546681';
```

**Expected output:** `DELETE 0` or `DELETE X` (X = number of rows deleted)

---

#### Step 1d: Verify Deletion Complete

Run this to confirm all records deleted:

```sql
SELECT
  (SELECT COUNT(*) FROM students WHERE id = 'MANUAL_1776969546681') as students_remaining,
  (SELECT COUNT(*) FROM attendance_records WHERE student_id = 'MANUAL_1776969546681') as attendance_remaining,
  (SELECT COUNT(*) FROM student_registrations WHERE student_id = 'MANUAL_1776969546681') as registration_remaining;
```

**Expected result:** All three values should be `0`

✅ **If all are 0: Database deletion successful!**

---

### Phase 2: B2 Cloud Storage Deletion (3-5 minutes)

#### Option A: Via B2 Web Console (Easiest)

1. Go to **B2 Cloud Storage Console** → `https://secure.backblaze.com/b2_buckets.html`
2. Click bucket: `edusetu-attendance-app`
3. Search for files with student ID: `MANUAL_1776969546681`
4. Delete all matching files:
   - Files starting with `registrations/.../MANUAL_1776969546681*`
   - Files starting with `attendance/.../MANUAL_1776969546681_*`

#### Option B: Via B2 CLI (Faster if many files)

```bash
# 1. Install B2 CLI (if not installed)
pip install b2

# 2. Authenticate
b2 authorize_account <your-account-id> <your-app-key>

# 3. List files to delete (review first)
b2 ls edusetu-attendance-app | grep MANUAL_1776969546681

# 4. Delete all matching files
b2 rm --dryRun edusetu-attendance-app MANUAL_1776969546681
b2 rm edusetu-attendance-app MANUAL_1776969546681
```

---

## Complete Deletion Checklist

- [ ] **Phase 1a:** Verified student exists in database
- [ ] **Phase 1b:** Noted down all B2 photo URLs (if any)
- [ ] **Phase 1c:** Executed DELETE commands in SQL Editor
- [ ] **Phase 1d:** Verified all database counts are 0
- [ ] **Phase 2:** Deleted all photos from B2 Cloud Storage
- [ ] **Final Check:** Student completely removed from system

---

## What Gets Deleted

### ✅ Database Deletion
- Student profile record
- Face embedding data
- All attendance history
- Registration data
- **Total records deleted:** Varies (typically 50-500 per student)

### ✅ B2 Cloud Storage
- Registration photo(s)
- Attendance photo(s)
- **Total files deleted:** Varies (typically 1-200 per student)

---

## After Deletion

### Student will no longer appear in:
- ✅ Student list
- ✅ Attendance marking screens
- ✅ Reports and dashboards
- ✅ Search results
- ✅ Database queries

### System status:
- ✅ No orphaned data remains
- ✅ No unused cloud storage
- ✅ Foreign key constraints satisfied
- ✅ Database integrity maintained

---

## Troubleshooting

### If you get "FK constraint" error:
- Ensure you delete in correct order: attendance → registrations → students
- Run one DELETE at a time instead of all together
- Check if there are other references to this student

### If photos not found in B2:
- Some photos may have already been deleted
- That's OK - just delete the ones that exist
- No issue if photo URLs don't correspond to actual files

### If deletion appears stuck:
- Check Supabase dashboard for running queries
- Wait 30 seconds and try again
- Contact Supabase support if persists

---

## Recovery Options (If Mistake)

### Database Recovery:
- Supabase keeps automatic backups for 14 days
- Contact Supabase support for restore
- Requires manual intervention

### B2 Storage Recovery:
- B2 keeps deleted files for 24 hours
- Can be restored via B2 console
- After 24 hours: permanent deletion

---

## Quick Reference

| Task | Time | Command |
|------|------|---------|
| Verify student | 1 min | SELECT query |
| Delete database | 2 min | DELETE × 3 |
| Verify deletion | 1 min | SELECT query |
| Delete B2 photos | 5 min | Manual or CLI |
| **Total** | **~10 min** | - |

---

## Support Contact

If you need help:
1. Check Supabase documentation: https://supabase.com/docs
2. B2 Support: https://www.backblaze.com/b2/support.html
3. App Administrator: Contact project maintainer

---

## Deletion Summary

**Student:** Bhushan Naikwade  
**ID:** MANUAL_1776969546681  
**Action:** Permanent deletion of all data and photos  
**Confirmation:** Explicit user approval given  
**Status:** ✅ Ready to execute  
**Date:** April 24, 2026

---

**Next Step:** Execute Phase 1c (DELETE commands) in Supabase SQL Editor

Once complete, confirm with message: ✅ Deletion executed and verified successful
