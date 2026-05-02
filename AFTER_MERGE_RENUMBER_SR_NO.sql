-- AUTO-RENUMBER SR NO AFTER MERGE
-- Run this AFTER the merge is complete to fix SR NO gaps
-- Example: If SR NO 002 was deleted, renumber so: 001, 003, 004 → 001, 002, 003

-- ========================================
-- STEP 1: Backup before renumbering (optional but recommended)
-- ========================================

CREATE TABLE sr_no_backup_before_renumber AS
SELECT * FROM public.students;

SELECT COUNT(*) as backed_up_records FROM sr_no_backup_before_renumber;

-- ========================================
-- STEP 2: Check current SR NO gaps (before renumbering)
-- ========================================

SELECT
  i.institute_code,
  i.name as institute_name,
  COUNT(*) as total_students,
  COUNT(DISTINCT s.sr_no) as distinct_sr_nos,
  MAX(CAST(COALESCE(s.sr_no, '0') AS INTEGER)) as max_sr_no,
  string_agg(DISTINCT s.sr_no, ', ' ORDER BY s.sr_no) as all_sr_nos
FROM public.students s
JOIN public.institutes i ON s.institute_id = i.id
GROUP BY i.id, i.institute_code, i.name
ORDER BY i.institute_code;

-- Example output:
-- Institute 11063: 2 students but SR NO are: 001, 003 (gap!)
-- Should be: 001, 002

-- ========================================
-- STEP 3: RENUMBER SR NO sequentially within each institute
-- ========================================

WITH students_with_new_sr_no AS (
  SELECT
    s.id,
    s.institute_id,
    s.name,
    s.sr_no as old_sr_no,
    ROW_NUMBER() OVER (
      PARTITION BY s.institute_id
      ORDER BY
        -- Order by: existing SR NO (as number), then creation date
        CASE
          WHEN s.sr_no ~ '^[0-9]+$' THEN (s.sr_no::INTEGER)
          ELSE 99999
        END ASC,
        s.created_at ASC
    ) as new_sr_no_int
  FROM public.students s
)
UPDATE public.students s
SET sr_no = LPAD(sn.new_sr_no_int::text, 3, '0')
FROM students_with_new_sr_no sn
WHERE s.id = sn.id
  AND s.sr_no != LPAD(sn.new_sr_no_int::text, 3, '0');

-- ========================================
-- STEP 4: Verify renumbering was successful
-- ========================================

SELECT
  i.institute_code,
  i.name as institute_name,
  COUNT(*) as total_students,
  COUNT(DISTINCT s.sr_no) as distinct_sr_nos,
  MAX(CAST(COALESCE(s.sr_no, '0') AS INTEGER)) as max_sr_no,
  string_agg(DISTINCT s.sr_no, ', ' ORDER BY s.sr_no) as all_sr_nos
FROM public.students s
JOIN public.institutes i ON s.institute_id = i.id
GROUP BY i.id, i.institute_code, i.name
ORDER BY i.institute_code;

-- Expected:
-- If 2 students: 001, 002 ✓
-- If 3 students: 001, 002, 003 ✓
-- No gaps!

-- ========================================
-- STEP 5: Show students with renamed SR NO (what changed)
-- ========================================

SELECT
  i.institute_code,
  s.id,
  s.name,
  s.sr_no as new_sr_no,
  b.sr_no as old_sr_no
FROM public.students s
JOIN public.institutes i ON s.institute_id = i.id
JOIN sr_no_backup_before_renumber b ON s.id = b.id
WHERE s.sr_no != b.sr_no
ORDER BY i.institute_code, s.sr_no
LIMIT 50;

-- ========================================
-- STEP 6: Show final student list per institute
-- ========================================

SELECT
  i.institute_code,
  s.sr_no,
  s.name,
  s.year,
  s.user_id,
  CASE WHEN s.face_photo_url IS NOT NULL THEN 'YES' ELSE 'NO' END as has_photo,
  array_length(s.subjects, 1) as subject_count
FROM public.students s
JOIN public.institutes i ON s.institute_id = i.id
ORDER BY i.institute_code, s.sr_no::int;

-- ========================================
-- STEP 7: Compare before & after
-- ========================================

SELECT
  'Before renumber' as stage,
  COUNT(*) as total_students,
  COUNT(DISTINCT institute_id) as institutes
FROM sr_no_backup_before_renumber
UNION ALL
SELECT
  'After renumber' as stage,
  COUNT(*) as total_students,
  COUNT(DISTINCT institute_id) as institutes
FROM public.students;

-- Should be same or fewer (if duplicates were deleted)

-- ========================================
-- STEP 8: Optional - Cleanup backup (when verified)
-- ========================================

-- When you're sure renumbering is correct:
-- DROP TABLE sr_no_backup_before_renumber;

-- ========================================
-- TROUBLESHOOTING
-- ========================================

-- If something went wrong, restore from backup:
-- INSERT INTO public.students SELECT * FROM sr_no_backup_before_renumber;

-- Check for NULL sr_no (should not happen):
SELECT
  i.institute_code,
  s.name,
  s.sr_no,
  s.id,
  COUNT(*) OVER (PARTITION BY s.institute_id) as students_in_institute
FROM public.students s
JOIN public.institutes i ON s.institute_id = i.id
WHERE s.sr_no IS NULL OR s.sr_no = ''
ORDER BY i.institute_code;

-- Verify sequential SR NOs (should have no gaps):
WITH sequential_check AS (
  SELECT
    i.institute_code,
    s.sr_no::int as sr_num,
    ROW_NUMBER() OVER (PARTITION BY i.institute_id ORDER BY s.sr_no::int) as expected_num
  FROM public.students s
  JOIN public.institutes i ON s.institute_id = i.id
  WHERE s.sr_no ~ '^[0-9]+$'
)
SELECT
  institute_code,
  sr_num,
  expected_num,
  CASE
    WHEN sr_num = expected_num THEN '✓ OK'
    ELSE '✗ GAP FOUND'
  END as status
FROM sequential_check
ORDER BY institute_code, sr_num;
