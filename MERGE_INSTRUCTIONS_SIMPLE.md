# Merge Students - Simple Instructions

**Merge Pattern:**
- Same institute ✓
- Same full name ✓
- Different SR NO (001, 002, 003) ✓
- Different subjects ✓

---

## Step 1: See How Many Need Merging

Run this query:

```sql
SELECT
  i.institute_code,
  i.name as institute_name,
  s.name as student_name,
  COUNT(*) as duplicate_count,
  string_agg(DISTINCT s.sr_no::text, ', ' ORDER BY s.sr_no::text) as all_sr_nos,
  string_agg(DISTINCT s.subjects::text, ' | ') as all_subjects
FROM public.students s
JOIN public.institutes i ON s.institute_id = i.id
GROUP BY i.id, i.institute_code, i.name, s.institute_id, s.name
HAVING COUNT(*) > 1
  AND COUNT(DISTINCT s.sr_no) > 1
  AND COUNT(DISTINCT s.subjects::text) > 1
ORDER BY i.institute_code, s.name;
```

**What you'll see:**
```
Institute Code | Institute Name | Student Name            | Duplicates | SR NOs  | Subjects
11063          | Prima          | AASHISH BALARAM GAIKAR  | 2          | 001,002 | [Math,Physics]|[Chemistry,Biology]
11147          | Some School    | KALYANI SWAPNIL ZAGADE  | 2          | 005,006 | [English]|[Biology,English,History]
```

**Count how many** - Write it down!

---

## Step 2: Create Safety Backup

Run this ONCE:

```sql
CREATE TABLE merge_backup_same_name_same_inst AS
SELECT s.*
FROM public.students s
JOIN public.institutes i ON s.institute_id = i.id
WHERE (s.institute_id, s.name) IN (
  SELECT s2.institute_id, s2.name
  FROM public.students s2
  GROUP BY s2.institute_id, s2.name
  HAVING COUNT(*) > 1
    AND COUNT(DISTINCT s2.sr_no) > 1
    AND COUNT(DISTINCT s2.subjects::text) > 1
);

SELECT COUNT(*) FROM merge_backup_same_name_same_inst;
```

**Note the backup count** - This is how many old records are being saved

---

## Step 3: See Merged Subjects Preview

Run this to see what subjects will be combined:

```sql
WITH dups AS (
  SELECT
    s.institute_id,
    s.name
  FROM public.students s
  GROUP BY s.institute_id, s.name
  HAVING COUNT(*) > 1
    AND COUNT(DISTINCT s.sr_no) > 1
    AND COUNT(DISTINCT s.subjects::text) > 1
)
SELECT
  i.institute_code,
  d.name as student_name,
  array_agg(DISTINCT elem ORDER BY elem) as merged_subjects
FROM dups d
JOIN public.institutes i ON d.institute_id = i.id
JOIN public.students s ON d.institute_id = s.institute_id AND d.name = s.name,
LATERAL jsonb_array_elements_text(COALESCE(s.subjects, '[]'::jsonb)) as elem
GROUP BY i.id, i.institute_code, d.institute_id, d.name
ORDER BY i.institute_code, d.name;
```

**Example result:**
```
11063 | AASHISH BALARAM GAIKAR | [Biology, Chemistry, Math, Physics]
11147 | KALYANI SWAPNIL ZAGADE | [Biology, English, History]
```

---

## Step 4: Merge - Update Kept Records

Run this to update all kept records with merged subjects:

```sql
WITH dups_to_merge AS (
  SELECT
    s.institute_id,
    s.name
  FROM public.students s
  GROUP BY s.institute_id, s.name
  HAVING COUNT(*) > 1
    AND COUNT(DISTINCT s.sr_no) > 1
    AND COUNT(DISTINCT s.subjects::text) > 1
),
records_with_priority AS (
  SELECT
    s.id,
    s.institute_id,
    s.name,
    ROW_NUMBER() OVER (
      PARTITION BY s.institute_id, s.name
      ORDER BY
        CASE WHEN s.face_photo_url IS NOT NULL THEN 0 ELSE 1 END ASC,
        CASE WHEN s.face_embedding IS NOT NULL THEN 0 ELSE 1 END ASC,
        s.created_at DESC
    ) as priority
  FROM dups_to_merge dtm
  JOIN public.students s ON dtm.institute_id = s.institute_id AND dtm.name = s.name
),
merged_subjects_per_group AS (
  SELECT
    rwp.institute_id,
    rwp.name,
    array_agg(DISTINCT elem ORDER BY elem) as all_subjects
  FROM records_with_priority rwp
  JOIN public.students s ON rwp.institute_id = s.institute_id AND rwp.name = s.name,
  LATERAL jsonb_array_elements_text(COALESCE(s.subjects, '[]'::jsonb)) as elem
  WHERE rwp.priority = 1
  GROUP BY rwp.institute_id, rwp.name
)
UPDATE public.students s
SET subjects = to_jsonb(msg.all_subjects)
FROM merged_subjects_per_group msg
WHERE s.institute_id = msg.institute_id
  AND s.name = msg.name
  AND s.id IN (
    SELECT id FROM records_with_priority WHERE priority = 1
  );
```

**What this does:**
- Finds the BEST record for each student (newest, has photo)
- Combines all subjects into that ONE record
- Updates the database

---

## Step 5: Merge - Delete Old Duplicate Records

Run this to delete the old duplicate records:

```sql
WITH dups_to_merge AS (
  SELECT
    s.institute_id,
    s.name
  FROM public.students s
  GROUP BY s.institute_id, s.name
  HAVING COUNT(*) > 1
    AND COUNT(DISTINCT s.sr_no) > 1
    AND COUNT(DISTINCT s.subjects::text) > 1
),
records_with_priority AS (
  SELECT
    s.id,
    s.institute_id,
    s.name,
    ROW_NUMBER() OVER (
      PARTITION BY s.institute_id, s.name
      ORDER BY
        CASE WHEN s.face_photo_url IS NOT NULL THEN 0 ELSE 1 END ASC,
        CASE WHEN s.face_embedding IS NOT NULL THEN 0 ELSE 1 END ASC,
        s.created_at DESC
    ) as priority
  FROM dups_to_merge dtm
  JOIN public.students s ON dtm.institute_id = s.institute_id AND dtm.name = s.name
)
DELETE FROM public.students s
WHERE (s.institute_id, s.name) IN (
  SELECT institute_id, name FROM dups_to_merge
)
AND s.id NOT IN (
  SELECT id FROM records_with_priority WHERE priority = 1
);
```

**What this does:**
- Deletes all the old duplicate records
- Keeps only the best one (with merged subjects)

---

## Step 6: Verify Success

Run this to check if merge worked:

```sql
SELECT
  i.institute_code,
  s.name as student_name,
  COUNT(*) as remaining_count
FROM public.students s
JOIN public.institutes i ON s.institute_id = i.id
GROUP BY i.id, i.institute_code, s.institute_id, s.name
HAVING COUNT(*) > 1
  AND COUNT(DISTINCT s.sr_no) > 1
  AND COUNT(DISTINCT s.subjects::text) > 1
ORDER BY i.institute_code, s.name;
```

**Expected result:** NO ROWS (empty result)

If you see NO ROWS → Merge successful! ✅

---

## Step 7: Show Results

See the merged data:

```sql
SELECT
  i.institute_code,
  s.name,
  COUNT(*) as record_count,
  s.subjects as all_merged_subjects
FROM public.students s
JOIN public.institutes i ON s.institute_id = i.id
WHERE (s.institute_id, s.name) IN (
  SELECT s2.institute_id, s2.name
  FROM merge_backup_same_name_same_inst s2
  GROUP BY s2.institute_id, s2.name
)
GROUP BY i.id, i.institute_code, s.institute_id, s.name, s.subjects
ORDER BY i.institute_code, s.name;
```

**Expected result:**
```
Institute | Student Name            | Records | Merged Subjects
11063     | AASHISH BALARAM GAIKAR  | 1       | [Biology, Chemistry, Math, Physics]
11147     | KALYANI SWAPNIL ZAGADE  | 1       | [Biology, English, History]
```

---

## Step 8: Compare Before & After

```sql
SELECT
  'Before merge' as stage,
  COUNT(*) as total_records
FROM merge_backup_same_name_same_inst
UNION ALL
SELECT
  'After merge' as stage,
  COUNT(*) as total_records
FROM public.students;
```

**Example:**
```
Stage         | Total Records
Before merge  | 2876 (includes duplicates)
After merge   | 2761 (duplicates removed)
Deleted       | 115 records
```

---

## Step 9: Test in App

1. Open student management screen
2. Search for one of the merged students
3. Should see **only 1 record** (not 2)
4. Should have **all subjects** combined
5. Should have **photo** (from the kept record)

---

## If Something Goes Wrong

### Problem: Merge didn't work

**Restore from backup:**
```sql
INSERT INTO public.students
SELECT * FROM merge_backup_same_name_same_inst
WHERE name = 'AASHISH BALARAM GAIKAR';
```

Then try again.

### Problem: Can't find the backup table

**Check if backup exists:**
```sql
SELECT COUNT(*) FROM merge_backup_same_name_same_inst;
```

If it doesn't exist, create it again (Step 2).

---

## Timeline

| Step | What | Time |
|------|------|------|
| 1 | Count duplicates | 2 min |
| 2 | Create backup | 2 min |
| 3 | Preview merge | 2 min |
| 4 | Update records | 3 min |
| 5 | Delete duplicates | 2 min |
| 6 | Verify | 2 min |
| 7 | Show results | 2 min |
| 8 | Compare | 1 min |
| 9 | Test in app | 5 min |
| **TOTAL** | | **~21 min** |

---

## Checklist

- [ ] Step 1: Counted duplicates
- [ ] Step 2: Created backup
- [ ] Step 3: Previewed merged subjects
- [ ] Step 4: Updated kept records
- [ ] Step 5: Deleted old duplicates
- [ ] Step 6: Verified (got NO ROWS)
- [ ] Step 7: Showed merged results
- [ ] Step 8: Compared before/after
- [ ] Step 9: Tested in app
- [ ] Done! ✓

---

## Optional Cleanup

When done and verified, optionally drop the backup:

```sql
DROP TABLE merge_backup_same_name_same_inst;
```

**Status:** Duplicates merged successfully! ✅
