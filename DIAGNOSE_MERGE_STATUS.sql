-- DIAGNOSE: Why merge/renumber showing same values

-- ========================================
-- 1. CHECK: Are there still duplicates in database?
-- ========================================

SELECT
  i.institute_code,
  i.name as institute_name,
  s.name as student_name,
  COUNT(*) as duplicate_count,
  string_agg(s.sr_no, ', ' ORDER BY s.sr_no) as all_sr_nos,
  string_agg(s.id, ', ') as record_ids
FROM public.students s
JOIN public.institutes i ON s.institute_id = i.id
GROUP BY i.id, i.institute_code, i.name, s.institute_id, s.name
HAVING COUNT(*) > 1
ORDER BY i.institute_code, s.name
LIMIT 50;

-- If this returns ROWS → Duplicates still exist! ❌
-- If EMPTY result → All merged successfully ✓

-- ========================================
-- 2. CHECK: Total student count
-- ========================================

SELECT
  COUNT(*) as total_students,
  COUNT(DISTINCT institute_id) as institutes,
  COUNT(DISTINCT name) as unique_names
FROM public.students;

-- ========================================
-- 3. CHECK: SR NO gaps per institute
-- ========================================

WITH all_students AS (
  SELECT
    i.institute_code,
    s.sr_no::int as sr_num,
    s.name,
    COUNT(*) as count
  FROM public.students s
  JOIN public.institutes i ON s.institute_id = i.id
  WHERE s.sr_no ~ '^[0-9]+$'
  GROUP BY i.institute_code, s.sr_no::int, s.name
)
SELECT
  institute_code,
  MAX(sr_num) as max_sr_no,
  COUNT(*) as total_students,
  CASE
    WHEN COUNT(*) = MAX(sr_num) THEN '✓ Sequential (no gaps)'
    WHEN COUNT(*) < MAX(sr_num) THEN '✗ Gaps exist!'
    ELSE '? Check manually'
  END as status
FROM all_students
GROUP BY institute_code
ORDER BY institute_code;

-- ========================================
-- 4. CHECK: Backup table still exists?
-- ========================================

SELECT
  tablename
FROM pg_tables
WHERE schemaname = 'public'
  AND tablename LIKE '%backup%'
ORDER BY tablename;

-- If backup table doesn't exist → It was dropped already
-- If exists → Can compare with current

-- ========================================
-- 5. CHECK: Count in backup vs current
-- ========================================

-- Only run if backup table exists!

SELECT
  'Before (backup)' as stage,
  COUNT(*) as count
FROM sr_no_backup_before_renumber
UNION ALL
SELECT
  'After (current)' as stage,
  COUNT(*) as count
FROM public.students;

-- If same count: No records were deleted (merge didn't work)
-- If different: Merge happened, renumber next

-- ========================================
-- 6. CHECK: Detailed changes
-- ========================================

-- Compare student names and counts by institute

SELECT
  i.institute_code,
  (
    SELECT COUNT(*)
    FROM sr_no_backup_before_renumber b
    WHERE b.institute_id = i.id
  ) as count_before_merge,
  (
    SELECT COUNT(*)
    FROM public.students s
    WHERE s.institute_id = i.id
  ) as count_after_merge,
  (
    SELECT COUNT(*)
    FROM sr_no_backup_before_renumber b
    WHERE b.institute_id = i.id
  ) -
  (
    SELECT COUNT(*)
    FROM public.students s
    WHERE s.institute_id = i.id
  ) as records_deleted
FROM public.institutes i
WHERE (
  SELECT COUNT(*)
  FROM sr_no_backup_before_renumber b
  WHERE b.institute_id = i.id
) > 0
ORDER BY i.institute_code;

-- ========================================
-- 7. CHECK: Show first 20 merged students
-- ========================================

SELECT
  i.institute_code,
  s.sr_no,
  s.name,
  s.user_id,
  array_length(s.subjects, 1) as subject_count,
  s.subjects as merged_subjects,
  CASE WHEN s.face_photo_url IS NOT NULL THEN 'YES' ELSE 'NO' END as has_photo,
  s.created_at
FROM public.students s
JOIN public.institutes i ON s.institute_id = i.id
ORDER BY i.institute_code, s.sr_no::int
LIMIT 20;

-- ========================================
-- DIAGNOSIS QUESTIONS
-- ========================================

/*
If before=after count (no change):
  Q: Did the merge DELETE happen?
  A: Check query #1 - are duplicates still there?

If before > after (records deleted):
  Q: Why are values same then?
  A: Maybe you're looking at wrong institutes or wrong backup table

If SR NO has gaps:
  Q: Is renumbering broken?
  A: Run this SQL to check and fix:

    WITH seq_check AS (
      SELECT
        s.id,
        s.institute_id,
        ROW_NUMBER() OVER (
          PARTITION BY s.institute_id
          ORDER BY s.sr_no::int, s.created_at
        ) as expected_num
      FROM public.students s
    )
    UPDATE public.students s
    SET sr_no = LPAD(expected_num::text, 3, '0')
    FROM seq_check sc
    WHERE s.id = sc.id;
*/
