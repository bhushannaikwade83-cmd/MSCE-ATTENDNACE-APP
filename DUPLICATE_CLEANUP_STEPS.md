# Duplicate Student Cleanup - Step by Step

## ⚠️ READ FIRST: What This Does

**Before cleaning up, understand:**
- ✅ Finds students who registered twice
- ✅ Keeps the best record (newest with photo)
- ✅ Deletes old duplicate records
- ❌ **CANNOT be undone** - deleted data is gone

**If unsure, SKIP this and ask first!**

---

## STEP 1: See All Duplicates (SAFE - Read Only)

**Run this query first:**
```sql
-- From FIND_STUDENTS_REGISTERED_TWICE.sql - QUERY 1
SELECT
  i.institute_code,
  i.name as institute_name,
  s.sr_no,
  s.user_id,
  s.name as student_name,
  COUNT(*) as total_registrations,
  string_agg(DISTINCT s.subjects::text, ' | ') as all_subjects,
  MIN(s.created_at) as first_registered,
  MAX(s.created_at) as last_registered,
  (MAX(s.created_at) - MIN(s.created_at)) as days_between_registrations
FROM public.students s
JOIN public.institutes i ON s.institute_id = i.id
GROUP BY i.id, i.institute_code, i.name, s.institute_id, s.sr_no, s.user_id, s.name
HAVING COUNT(*) >= 2
ORDER BY total_registrations DESC, i.institute_code, s.name;
```

**What you'll see:**
```
Institute Code | Student Name         | Registrations | Subjects
23101          | Bhushan Naikwade     | 2            | [Math,Physics] | [Chemistry,Biology]
23101          | Rahul Sharma         | 3            | [Science] | [Biology] | [Physics]
```

**Action:** Write down students with duplicates

---

## STEP 2: See Details (SAFE - Read Only)

**For one specific student, run:**
```sql
-- From FIND_STUDENTS_REGISTERED_TWICE.sql - QUERY 2
SELECT
  i.institute_code,
  s.sr_no,
  s.name,
  s.id as student_record_id,
  s.subjects,
  s.year,
  s.created_at,
  CASE WHEN s.face_photo_url IS NOT NULL THEN 'YES' ELSE 'NO' END as has_photo
FROM public.students s
JOIN public.institutes i ON s.institute_id = i.id
WHERE s.name = 'Bhushan Naikwade'
  AND s.institute_id = (SELECT id FROM public.institutes WHERE institute_code = '23101')
ORDER BY s.created_at;
```

**What you'll see:**
```
Institute | SR NO | Name               | Record ID | Subjects              | Year | Created At  | Photo
23101     | 001   | Bhushan Naikwade   | abc123    | [Math, Physics]       | 2024 | 2024-01-01  | NO
23101     | 001   | Bhushan Naikwade   | def456    | [Chemistry, Biology]  | 2024 | 2024-01-15  | YES ← NEWER & HAS PHOTO
```

**Decision:** Keep `def456` (newer, has photo), delete `abc123`

---

## STEP 3: Confirm Which to DELETE (SAFE - Read Only)

**Run this query:**
```sql
-- From FIND_STUDENTS_REGISTERED_TWICE.sql - QUERY 7
WITH duplicates AS (
  SELECT
    s.id,
    s.institute_id,
    s.sr_no,
    s.user_id,
    s.name,
    s.created_at,
    s.face_photo_url,
    ROW_NUMBER() OVER (
      PARTITION BY s.institute_id, COALESCE(s.sr_no, s.user_id), s.name
      ORDER BY
        CASE WHEN s.face_photo_url IS NOT NULL THEN 0 ELSE 1 END,
        s.created_at DESC
    ) as priority
  FROM public.students s
)
SELECT
  'DELETE' as action,
  i.institute_code,
  d.sr_no,
  d.name,
  d.id as student_record_id,
  d.created_at,
  'DELETE FROM public.students WHERE id = ''' || d.id || ''';' as delete_sql
FROM duplicates d
JOIN public.institutes i ON d.institute_id = i.id
WHERE d.priority > 1
ORDER BY i.institute_code, d.name;
```

**What you'll see:**
```
Action | Institute | Name              | Record ID | Delete Command
DELETE | 23101     | Bhushan Naikwade  | abc123    | DELETE FROM public.students WHERE id = 'abc123';
DELETE | 23101     | Rahul Sharma      | old111    | DELETE FROM public.students WHERE id = 'old111';
DELETE | 23101     | Rahul Sharma      | old222    | DELETE FROM public.students WHERE id = 'old222';
```

**Verify:** These are the records to DELETE (older ones)

---

## STEP 4: BACKUP Before Deleting (RECOMMENDED)

**Create a safety backup:**
```sql
-- Create backup table
CREATE TABLE students_duplicates_backup AS
SELECT * FROM public.students
WHERE id IN (
  'abc123',    -- From query above
  'old111',
  'old222'
);

-- Verify backup
SELECT COUNT(*) FROM students_duplicates_backup;
-- Should show: 3
```

**Important:** Save these IDs somewhere safe!

---

## STEP 5: DELETE - ONE AT A TIME ⚠️

**Delete the FIRST duplicate only:**
```sql
DELETE FROM public.students WHERE id = 'abc123';
```

**Verify it's gone:**
```sql
SELECT COUNT(*) FROM public.students
WHERE sr_no = '001' AND name = 'Bhushan Naikwade';
-- Should show: 1 (not 2 anymore)
```

**Test in app:**
1. Search student "Bhushan Naikwade"
2. Should show only 1 result
3. Photo should be there
4. Subjects should be correct

**If OK:** Continue to next record
**If PROBLEM:** Restore from backup!

---

## STEP 6: Delete Next Record

**Repeat step 5 for each record:**
```sql
-- Second deletion
DELETE FROM public.students WHERE id = 'old111';

-- Verify
SELECT COUNT(*) FROM public.students
WHERE sr_no = '005' AND name = 'Rahul Sharma';
-- Should show: 2 (was 3, now 2)

-- Test in app - check if Rahul appears correct
```

**Do this ONE BY ONE, not all at once!**

---

## STEP 7: Final Verification

**After all deletions, run:**
```sql
-- Should show NO rows (no more duplicates)
SELECT
  s.institute_id,
  s.sr_no,
  s.name,
  COUNT(*) as count
FROM public.students s
GROUP BY s.institute_id, s.sr_no, s.name
HAVING COUNT(*) > 1;
```

**Expected result:**
```
(No rows - SUCCESS!)
```

---

## STEP 8: Final Count

```sql
-- See how many deleted
SELECT COUNT(*) FROM students_duplicates_backup;
-- e.g., 3 records deleted

-- Check total students now
SELECT COUNT(*) FROM public.students;
-- Should be less than before
```

---

## Quick Summary

| Step | What | Command | Risk |
|------|------|---------|------|
| 1 | List duplicates | QUERY 1 | None (read) |
| 2 | See details | QUERY 2 | None (read) |
| 3 | Get delete list | QUERY 7 | None (read) |
| 4 | Backup | CREATE TABLE | Low |
| 5 | Delete one | DELETE... | Medium |
| 6 | Repeat | DELETE... | Medium |
| 7 | Verify | SELECT... | None (read) |
| 8 | Final count | SELECT... | None (read) |

---

## If Something Goes Wrong

### Problem: Deleted Wrong Student!

**Restore from backup:**
```sql
INSERT INTO public.students
SELECT * FROM students_duplicates_backup
WHERE id = 'abc123';  -- The one you deleted
```

### Problem: Still Seeing Duplicates

**Check if deletion worked:**
```sql
SELECT * FROM public.students WHERE id = 'abc123';
-- Should return: (No rows)

SELECT * FROM public.students
WHERE sr_no = '001' AND name = 'Bhushan Naikwade';
-- Should return: 1 row (not 2)
```

### Problem: App Shows Errors

**Restart app** - It may have cached old data

---

## Helpful Queries

### See what you're about to delete:
```sql
SELECT * FROM public.students WHERE id = 'abc123';
```

### Count duplicates before cleaning:
```sql
SELECT COUNT(*)
FROM (
  SELECT sr_no, name, institute_id, COUNT(*)
  FROM public.students
  WHERE sr_no IS NOT NULL
  GROUP BY sr_no, name, institute_id
  HAVING COUNT(*) > 1
) t;
```

### List all records for one student:
```sql
SELECT * FROM public.students
WHERE name = 'Bhushan Naikwade'
  AND institute_id = 'xyz'
ORDER BY created_at;
```

---

## Before You Start Cleanup

✅ Do you have a backup?
✅ Have you tested the queries?
✅ Do you understand which records to delete?
✅ Can you access the database?
✅ Is there a test environment you can try first?

**If NO to any of these:** DO NOT PROCEED

---

## Timeline

**Expected time:**
- Query & Review: 5-10 minutes
- Backup: 2 minutes
- Deletion (per student): 1-2 minutes
- **Total for 10 students:** ~20-30 minutes

**Do NOT rush - go slowly!**

---

## Final Checklist

- [ ] Ran QUERY 1 - saw list of duplicates
- [ ] Ran QUERY 2 - confirmed which records to keep/delete
- [ ] Ran QUERY 7 - got delete statements
- [ ] Created backup with CREATE TABLE
- [ ] Verified backup has data
- [ ] Deleted FIRST record only
- [ ] Tested in app - works OK
- [ ] Deleted remaining records ONE BY ONE
- [ ] Ran final verification query
- [ ] Result shows (No rows) - SUCCESS!
- [ ] Cleaned up backup table when done

---

## When Done

```sql
-- Optional: Delete the backup table
DROP TABLE students_duplicates_backup;
```

**Status:** Duplicate students cleaned up ✅
