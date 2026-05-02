# Merge Duplicate Student Subjects - Step by Step

## ⚠️ READ FIRST: What This Does

**Instead of deleting, we MERGE:**
- ✅ Finds students who registered twice
- ✅ Combines their subjects into ONE record
- ✅ Example: [Math, Physics] + [Chemistry, Biology] = [Chemistry, Biology, Math, Physics]
- ✅ Keeps the BEST record (newest with photo)
- ✅ Deletes DUPLICATE records
- ❌ **CANNOT be undone** - deleted records are gone (but backup is created first)

**Key Difference from deletion:**
- ❌ DELETE approach: Keep one, lose other's subjects
- ✅ MERGE approach: Keep one, ADD other's subjects to it

---

## STEP 1: See What Will Be Merged (SAFE - Read Only)

**Run this query first:**
```sql
-- From MERGE_DUPLICATE_STUDENTS_SUBJECTS.sql - QUERY 1
SELECT
  i.institute_code,
  s.name as student_name,
  COUNT(*) as total_registrations,
  COUNT(DISTINCT s.sr_no) as different_sr_nos,
  string_agg(DISTINCT s.sr_no::text, ', ' ORDER BY s.sr_no::text) as all_sr_nos,
  string_agg(s.id::text, ', ') as all_record_ids,
  MIN(s.created_at) as oldest_registered,
  MAX(s.created_at) as newest_registered
FROM public.students s
JOIN public.institutes i ON s.institute_id = i.id
WHERE (i.institute_code, s.name) IN (
  -- (copy list from script)
)
GROUP BY i.institute_code, s.name
ORDER BY i.institute_code, s.name;
```

**What you'll see:**
```
Institute | Student Name       | Total Regs | SR NOs   | Record IDs          | Oldest        | Newest
11063     | AASHISH BALARAM... | 2          | 001, 002 | abc123, def456      | 2024-01-01    | 2024-01-15
11147     | KALYANI SWAPNIL... | 2          | 005, 006 | xyz789, uvw012      | 2024-01-05    | 2024-01-20
```

**Action:** Understand how many duplicates will be merged

---

## STEP 2: See Detailed Records (SAFE - Read Only)

**For each duplicate, see what it looks like:**
```sql
-- From MERGE_DUPLICATE_STUDENTS_SUBJECTS.sql - QUERY 2
SELECT
  i.institute_code,
  s.name as student_name,
  s.sr_no,
  s.user_id,
  s.id as record_id,
  s.subjects as current_subjects,
  s.year,
  s.created_at,
  CASE WHEN s.face_photo_url IS NOT NULL THEN 'YES' ELSE 'NO' END as has_photo,
  CASE WHEN s.face_embedding IS NOT NULL THEN 'YES' ELSE 'NO' END as has_embedding
FROM public.students s
JOIN public.institutes i ON s.institute_id = i.id
WHERE (i.institute_code, s.name) IN (
  -- (copy list from script)
)
ORDER BY i.institute_code, s.name, s.created_at;
```

**What you'll see:**
```
Institute | Name              | SR | ID    | Subjects              | Photo | Embedding | Created At
11063     | AASHISH BALARAM   | 001| abc   | [Math, Physics]       | NO    | NO        | 2024-01-01
11063     | AASHISH BALARAM   | 002| def   | [Chemistry, Biology]  | YES   | YES       | 2024-01-15 ← NEWER
```

**Analysis:** Record `def` has photo and is newer → This will be KEPT

---

## STEP 3: See What the Merged Subjects Will Look Like (SAFE - Read Only)

**Run this to see the final merged subjects:**
```sql
-- From MERGE_DUPLICATE_STUDENTS_SUBJECTS.sql - QUERY 5
WITH all_subjects AS (
  SELECT
    s.institute_id,
    s.name,
    array_agg(DISTINCT jsonb_array_elements(s.subjects)::text ORDER BY jsonb_array_elements(s.subjects)::text) as merged_subjects,
    string_agg(DISTINCT s.id::text, ', ') as all_record_ids
  FROM public.students s
  WHERE (
    SELECT COUNT(*)
    FROM public.students s2
    WHERE s2.institute_id = s.institute_id AND s2.name = s.name
  ) > 1
  GROUP BY s.institute_id, s.name
)
SELECT
  i.institute_code,
  a.name as student_name,
  a.merged_subjects as new_merged_subjects
FROM all_subjects a
JOIN public.institutes i ON a.institute_id = i.id
WHERE -- (copy list from script)
ORDER BY i.institute_code, a.name;
```

**What you'll see:**
```
Institute | Student Name      | New Merged Subjects
11063     | AASHISH BALARAM   | [Biology, Chemistry, Math, Physics]
11147     | KALYANI SWAPNIL   | [Biology, English, History, Math, Science]
```

**Important:** All subjects are combined and sorted alphabetically, duplicates removed

---

## STEP 4: Create Backup (RECOMMENDED) ⚠️

**Save all duplicate records BEFORE merging:**
```sql
-- From MERGE_DUPLICATE_STUDENTS_SUBJECTS.sql - STEP 4
CREATE TABLE students_merge_backup_2024_12_15 AS
SELECT *
FROM public.students s
WHERE -- (all institutes and students from list)
AND (s.institute_id, s.name) IN (
  SELECT s2.institute_id, s2.name
  FROM public.students s2
  GROUP BY s2.institute_id, s2.name
  HAVING COUNT(*) > 1
);

-- Verify backup
SELECT COUNT(*) FROM students_merge_backup_2024_12_15;
-- Should show: ~115+ records
```

**Why?** If something goes wrong, restore from backup

---

## STEP 5: See Which Record Will Be Kept (SAFE - Read Only)

**The system will keep the BEST record (newest with photo preferred):**
```sql
-- From MERGE_DUPLICATE_STUDENTS_SUBJECTS.sql - QUERY 4
-- Shows which record will be kept
-- Priority: Has photo + Has embedding > Just newer > Just has photo > Newest
```

**Decision logic:**
1. If one has photo + embedding → KEEP that one
2. Else if one has photo → KEEP that one
3. Else → KEEP the newest one

**Example:**
```
Student: AASHISH BALARAM
Record 1: SR 001, [Math, Physics], Photo=NO,  Created=2024-01-01
Record 2: SR 002, [Chemistry, Biology], Photo=YES, Created=2024-01-15

Decision: KEEP Record 2 (has photo, newer)
Result: One record with [Biology, Chemistry, Math, Physics]
```

---

## STEP 6: Merge Records (ACTUAL EXECUTION) ⚠️

**This is the actual merge - it will:**
1. Update the BEST record with merged subjects
2. Delete the OLD/DUPLICATE records

```sql
-- From MERGE_DUPLICATE_STUDENTS_SUBJECTS.sql - STEP 6a & 6b
-- Run both UPDATE and DELETE statements

-- This updates the kept record with all subjects
UPDATE public.students s
SET subjects = merged_subjects
WHERE -- (kept record IDs)

-- This deletes the duplicate records
DELETE FROM public.students s
WHERE -- (old record IDs)
```

**IMPORTANT:** Only run this after you've verified everything in steps 1-5!

---

## STEP 7: Verify Merge Was Successful (SAFE - Read Only)

**Check that merge worked correctly:**
```sql
-- From MERGE_DUPLICATE_STUDENTS_SUBJECTS.sql - STEP 7

-- Should show only 1 record per student
SELECT
  i.institute_code,
  s.name,
  COUNT(*) as remaining_records,
  s.subjects as merged_subjects
FROM public.students s
JOIN public.institutes i ON s.institute_id = i.id
WHERE (i.institute_code, s.name) IN (
  -- (copy list from script)
)
GROUP BY i.institute_code, s.name, s.subjects
ORDER BY i.institute_code, s.name;
```

**Expected result:**
```
Institute | Name              | Remaining Records | Subjects
11063     | AASHISH BALARAM   | 1                 | [Biology, Chemistry, Math, Physics]
11063     | POURNIMA ASHOK    | 1                 | [Biology, Physics, Science]
11147     | KALYANI SWAPNIL   | 1                 | [Biology, English, History, Math]
...
```

**If all show remaining_records = 1:** ✅ SUCCESS!

---

## STEP 8: Test in App

**Verify the merged data works in your app:**

1. **Check Student Search:**
   - Search for "AASHISH BALARAM"
   - Should show **1 result** (not 2)
   - Should have all subjects combined

2. **Check Student Details:**
   - Click the student
   - Should see merged subjects: [Biology, Chemistry, Math, Physics]
   - Photo should be there (from the kept record)

3. **Check Attendance:**
   - Should be able to mark attendance
   - Should show all merged subjects

4. **Check Institute Count:**
   - Total students should be less (duplicates removed)

---

## Quick Reference Table

| Step | What | Risk | Time |
|------|------|------|------|
| 1 | List all merges | None (read) | 2 min |
| 2 | See details | None (read) | 3 min |
| 3 | Preview merged subjects | None (read) | 2 min |
| 4 | Create backup | Low | 2 min |
| 5 | Check which to keep | None (read) | 2 min |
| 6 | Actually merge & delete | HIGH ⚠️ | 5 min |
| 7 | Verify success | None (read) | 2 min |
| 8 | Test in app | None (test) | 5 min |
| **TOTAL** | | | **~23 min** |

---

## If Something Goes Wrong

### Problem: Deleted data but subjects not merged!

**Restore from backup:**
```sql
-- Restore a specific student
INSERT INTO public.students
SELECT * FROM students_merge_backup_2024_12_15
WHERE name = 'AASHISH BALARAM GAIKAR';
```

### Problem: Still showing duplicates in app!

**Check if deletion worked:**
```sql
SELECT COUNT(*) FROM public.students
WHERE name = 'AASHISH BALARAM GAIKAR'
  AND institute_id = (SELECT id FROM institutes WHERE institute_code='11063');
-- Should return: 1
```

**If it returns 2:** Deletion didn't work, check backup

### Problem: App shows no subjects for student!

**Check if UPDATE worked:**
```sql
SELECT id, name, subjects FROM public.students
WHERE name = 'AASHISH BALARAM GAIKAR';
-- Should show merged subjects like [Biology, Chemistry, Math, Physics]
```

---

## Before You Start Merge

✅ Do you have a backup?
✅ Have you tested the queries?
✅ Do you understand the merge logic?
✅ Can you access the database?
✅ Is there a test environment you can try first?

**If NO to any of these:** DO NOT PROCEED

---

## Merge Process Flowchart

```
START: 115+ duplicate students
    ↓
RUN QUERY 1: See all merges to happen
    ↓
RUN QUERY 2: See detailed records for each
    ↓
RUN QUERY 5: Preview merged subjects
    ↓
CREATE BACKUP: Save original records
    ↓
RUN QUERY 4: Confirm which records to keep
    ↓
RUN STEP 6: UPDATE + DELETE (actual merge)
    ↓
RUN QUERY 7: Verify no duplicates remain
    ↓
TEST IN APP: Check student list/search
    ↓
SUCCESS ✓ Subjects merged, duplicates gone
```

---

## Example: Before & After

### BEFORE Merge:
```
Student: AASHISH BALARAM GAIKAR
Institute: Prima (11063)

Record 1 (OLD):
  SR NO: 001
  Subjects: [Math, Physics]
  Photo: NO
  Created: 2024-01-01

Record 2 (NEW):
  SR NO: 002
  Subjects: [Chemistry, Biology]
  Photo: YES
  Created: 2024-01-15

Problem: Student shows twice in app!
```

### AFTER Merge:
```
Student: AASHISH BALARAM GAIKAR
Institute: Prima (11063)

Record (MERGED):
  SR NO: 002 (kept the newer one)
  Subjects: [Biology, Chemistry, Math, Physics] ← ALL COMBINED!
  Photo: YES ← from Record 2
  Created: 2024-01-15

Result: Student shows ONCE, with ALL subjects! ✓
```

---

## Final Checklist

- [ ] Ran QUERY 1 - saw all merges
- [ ] Ran QUERY 2 - confirmed which records to keep/delete
- [ ] Ran QUERY 5 - verified merged subjects look correct
- [ ] Created BACKUP table (students_merge_backup_[DATE])
- [ ] Verified backup has all old records
- [ ] Ran QUERY 4 - checked keep logic
- [ ] Ran STEP 6a - UPDATE kept records with merged subjects
- [ ] Ran STEP 6b - DELETE old duplicate records
- [ ] Ran QUERY 7 - verified only 1 record per student
- [ ] Tested in app - student shows once, all subjects visible
- [ ] Cleaned up backup table when done (optional)

---

## When You're Done

```sql
-- Optional: Delete the backup table
DROP TABLE students_merge_backup_[DATE];

-- Check final count
SELECT COUNT(*) FROM public.students;
-- Should be less than before merge
```

**Status:** Duplicate student subjects merged ✅
