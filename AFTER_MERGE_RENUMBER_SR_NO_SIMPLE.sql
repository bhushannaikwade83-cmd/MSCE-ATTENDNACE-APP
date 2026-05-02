-- SIMPLE: AUTO-RENUMBER SR NO AFTER MERGE (FIXED VERSION)
-- Just copy & paste this - it will fix SR NO gaps

-- ========================================
-- STEP 1: Backup (just in case)
-- ========================================

CREATE TABLE sr_no_backup_before_renumber AS
SELECT * FROM public.students;

SELECT COUNT(*) as backed_up_records FROM sr_no_backup_before_renumber;

-- ========================================
-- STEP 2: RENUMBER SR NO (This is the fix!)
-- ========================================

WITH students_with_new_sr_no AS (
  SELECT
    s.id,
    s.institute_id,
    ROW_NUMBER() OVER (
      PARTITION BY s.institute_id
      ORDER BY
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
-- STEP 3: Verify - Check for gaps
-- ========================================

SELECT
  i.institute_code,
  COUNT(*) as total_students,
  string_agg(DISTINCT s.sr_no, ', ' ORDER BY s.sr_no) as all_sr_nos,
  CASE
    WHEN COUNT(*) = COUNT(DISTINCT s.sr_no) THEN '✅ Sequential (no gaps)'
    ELSE '⚠️ Check manually'
  END as status
FROM public.students s
JOIN public.institutes i ON s.institute_id = i.id
GROUP BY i.id, i.institute_code
ORDER BY i.institute_code;

-- ========================================
-- STEP 4: Show what changed (before vs after)
-- ========================================

SELECT
  i.institute_code,
  s.name,
  s.sr_no as new_sr_no,
  b.sr_no as old_sr_no,
  CASE
    WHEN s.sr_no = b.sr_no THEN '→ No change'
    WHEN s.sr_no != b.sr_no THEN '→ CHANGED'
  END as change_status
FROM public.students s
JOIN public.institutes i ON s.institute_id = i.id
JOIN sr_no_backup_before_renumber b ON s.id = b.id
WHERE s.sr_no != b.sr_no
ORDER BY i.institute_code, s.sr_no
LIMIT 100;

-- ========================================
-- STEP 5: Final check - before vs after
-- ========================================

SELECT
  'Before merge' as stage,
  COUNT(*) as total_records
FROM sr_no_backup_before_renumber
UNION ALL
SELECT
  'After merge' as stage,
  COUNT(*) as total_records
FROM public.students;

-- ========================================
-- OPTIONAL: Cleanup backup when verified
-- ========================================
-- DROP TABLE sr_no_backup_before_renumber;
