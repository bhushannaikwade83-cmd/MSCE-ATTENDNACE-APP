# "Before & After Same Values" - Troubleshooting

## Problem
```
Before merge: 2876 records
After merge:  2876 records  ← Same! Should be less!
```

## Why This Happens

### Reason 1: Merge SQL Didn't Execute ❌
**The DELETE step failed silently**
```
Solution: Check if duplicates still exist
Run: DIAGNOSE_MERGE_STATUS.sql → Query #1
```

### Reason 2: Backup Table Not Yet Created ❌
**Backup was dropped already**
```
Solution: Can't compare - backup is gone
Run: DIAGNOSE_MERGE_STATUS.sql → Query #4
```

### Reason 3: Wrong Backup/Wrong Institutes ❌
**Counting different data**
```
Solution: Check which institutes have duplicates
Run: DIAGNOSE_MERGE_STATUS.sql → Query #1
```

### Reason 4: Merge Worked BUT Backup Dropped ✓
**Actually the merge IS working, backup just gone**
```
Proof: Run Query #1
  If NO duplicates found → Merge worked! ✓
  If duplicates found → Merge didn't work
```

---

## Step-by-Step Diagnosis

### Step 1: Check if duplicates still exist
```sql
SELECT
  i.institute_code,
  s.name,
  COUNT(*) as count
FROM public.students s
JOIN public.institutes i ON s.institute_id = i.id
GROUP BY i.id, i.institute_code, s.institute_id, s.name
HAVING COUNT(*) > 1;
```

**If returns ROWS:**
- Duplicates still exist → Merge FAILED ❌
- Run merge SQL again

**If returns EMPTY (0 rows):**
- No duplicates → Merge WORKED ✓
- Backup table might be dropped

---

### Step 2: Check if backup table exists
```sql
SELECT * FROM sr_no_backup_before_renumber LIMIT 1;
```

**If ERROR (table doesn't exist):**
- Backup was already dropped
- Merge probably worked, just no backup to compare

**If SUCCESS (shows rows):**
- Backup exists, can compare

---

### Step 3: Force fix the counts
If merge worked but you want to verify:

```sql
-- Count duplicates in backup
SELECT COUNT(*) FROM sr_no_backup_before_renumber;  -- Should be MORE

-- Count current students
SELECT COUNT(*) FROM public.students;  -- Should be LESS

-- Difference = how many were deleted
SELECT
  (SELECT COUNT(*) FROM sr_no_backup_before_renumber) -
  (SELECT COUNT(*) FROM public.students) as deleted_records;
```

---

## Complete Diagnostic Workflow

**Run these in order:**

### 1️⃣ Check if duplicates exist NOW
```sql
SELECT COUNT(*)
FROM (
  SELECT s.institute_id, s.name
  FROM public.students s
  GROUP BY s.institute_id, s.name
  HAVING COUNT(*) > 1
) dups;

-- Result = 0 → Merge worked ✓
-- Result > 0 → Merge failed ❌
```

### 2️⃣ Check if backup exists
```sql
SELECT COUNT(*) FROM sr_no_backup_before_renumber;
-- If ERROR → Already dropped (merge probably worked)
-- If OK → Can compare
```

### 3️⃣ If backup exists, compare
```sql
SELECT
  'Backup (before)' as stage,
  COUNT(*) as total
FROM sr_no_backup_before_renumber
UNION ALL
SELECT
  'Current (after)' as stage,
  COUNT(*) as total
FROM public.students;

-- Before > After → Merge worked ✓
-- Before = After → Merge didn't work ❌
```

### 4️⃣ If merge worked, check SR NO
```sql
SELECT
  i.institute_code,
  COUNT(*) as students,
  MAX(s.sr_no::int) as max_sr_no,
  CASE
    WHEN COUNT(*) = MAX(s.sr_no::int) THEN '✓ Sequential'
    ELSE '✗ Has gaps'
  END as status
FROM public.students s
JOIN public.institutes i ON s.institute_id = i.id
WHERE s.sr_no ~ '^[0-9]+$'
GROUP BY i.id, i.institute_code;
```

---

## Most Likely Scenario

### You're probably in this situation:

```
1. Ran merge SQL ✓
2. Merge deleted duplicates ✓
3. Checked counts early
4. Later dropped backup table
5. Now can't compare ✓ (This is normal)

SOLUTION: Don't worry!
- Run: SELECT COUNT(*) FROM public.students;
- Run: SELECT COUNT(DISTINCT name, institute_id) FROM public.students;
- They should be different if merge worked
```

---

## Simple Test: Did Merge Work?

```sql
-- Test: Show any student names that appear multiple times
SELECT
  i.institute_code,
  s.name,
  COUNT(*) as appears_how_many_times,
  string_agg(s.sr_no, ', ') as sr_nos
FROM public.students s
JOIN public.institutes i ON s.institute_id = i.id
GROUP BY i.id, i.institute_code, s.institute_id, s.name
HAVING COUNT(*) > 1;

-- EMPTY result = Merge worked ✓
-- Rows shown = Duplicates still exist ❌
```

---

## If Merge Didn't Work

### Re-run merge with this script:

```sql
-- Step 1: Backup again
CREATE TABLE merge_backup_new AS
SELECT * FROM public.students;

-- Step 2: Merge (update with combined subjects)
WITH dups AS (
  SELECT s.institute_id, s.name
  FROM public.students s
  GROUP BY s.institute_id, s.name
  HAVING COUNT(*) > 1
),
ranked AS (
  SELECT
    s.id,
    s.institute_id,
    s.name,
    ROW_NUMBER() OVER (
      PARTITION BY s.institute_id, s.name
      ORDER BY
        CASE WHEN s.face_photo_url IS NOT NULL THEN 0 ELSE 1 END,
        CASE WHEN s.face_embedding IS NOT NULL THEN 0 ELSE 1 END,
        s.created_at DESC
    ) as priority
  FROM dups
  JOIN public.students s ON dups.institute_id = s.institute_id AND dups.name = s.name
),
merged_subjects AS (
  SELECT
    r.institute_id,
    r.name,
    array_agg(DISTINCT subject ORDER BY subject) as all_subjects
  FROM ranked r
  JOIN public.students s ON r.institute_id = s.institute_id AND r.name = s.name,
  LATERAL unnest(COALESCE(s.subjects, ARRAY[]::text[])) as subject
  WHERE r.priority = 1
  GROUP BY r.institute_id, r.name
)
UPDATE public.students s
SET subjects = ms.all_subjects
FROM merged_subjects ms
WHERE s.institute_id = ms.institute_id
  AND s.name = ms.name
  AND s.id IN (
    SELECT id FROM ranked WHERE priority = 1
  );

-- Step 3: Delete old duplicates
DELETE FROM public.students
WHERE (institute_id, name) IN (
  SELECT s.institute_id, s.name
  FROM public.students s
  GROUP BY s.institute_id, s.name
  HAVING COUNT(*) > 1
)
AND id NOT IN (
  SELECT id FROM (
    SELECT
      s.id,
      ROW_NUMBER() OVER (
        PARTITION BY s.institute_id, s.name
        ORDER BY
          CASE WHEN s.face_photo_url IS NOT NULL THEN 0 ELSE 1 END,
          s.created_at DESC
      ) as prio
    FROM public.students s
  ) ranked
  WHERE prio = 1
);

-- Step 4: Verify
SELECT COUNT(*) as deleted
FROM merge_backup_new
WHERE id NOT IN (SELECT id FROM public.students);
```

---

## Summary

| Situation | Check | Fix |
|-----------|-------|-----|
| Before = After count | Run `SELECT COUNT(*) FROM students` before backup drop | Merge might have worked, no duplicate students now |
| Duplicates still exist | Query #1 finds > 0 rows | Re-run merge SQL |
| Backup gone | Can't access table | Run `SELECT COUNT(*)` to verify no duplicates |
| SR NO has gaps | Max SR NO > Student count | Renumber sequentially |

**Action:** Run `DIAGNOSE_MERGE_STATUS.sql` to get the truth about your data!
