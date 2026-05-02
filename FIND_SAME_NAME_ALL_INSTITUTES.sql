-- Find students with SAME FULL NAME across ALL INSTITUTES
-- Shows students that might be confused/appearing multiple times

-- ========================================
-- QUERY 1: Students with SAME NAME appearing in MULTIPLE records
-- ========================================

SELECT
  s.name as student_name,
  COUNT(*) as total_records,
  COUNT(DISTINCT s.institute_id) as different_institutes,
  COUNT(DISTINCT s.sr_no) as different_sr_nos,
  COUNT(DISTINCT s.user_id) as different_user_ids,
  COUNT(DISTINCT s.subjects::text) as different_subject_sets,
  string_agg(DISTINCT i.institute_code, ', ' ORDER BY i.institute_code) as institute_codes,
  string_agg(DISTINCT s.sr_no::text, ', ' ORDER BY s.sr_no::text) as all_sr_nos,
  string_agg(DISTINCT s.user_id, ', ' ORDER BY s.user_id) as all_user_ids
FROM public.students s
LEFT JOIN public.institutes i ON s.institute_id = i.id
GROUP BY s.name
HAVING COUNT(*) > 1
ORDER BY COUNT(*) DESC;

-- ========================================
-- QUERY 2: For SAME NAME students - show ALL their details
-- ========================================

SELECT
  s.name as student_name,
  i.institute_code,
  i.name as institute_name,
  s.sr_no,
  s.user_id,
  s.id as record_id,
  s.subjects,
  s.year,
  s.created_at,
  CASE WHEN s.face_photo_url IS NOT NULL THEN 'YES' ELSE 'NO' END as has_photo
FROM public.students s
LEFT JOIN public.institutes i ON s.institute_id = i.id
WHERE s.name IN (
  SELECT s2.name
  FROM public.students s2
  GROUP BY s2.name
  HAVING COUNT(*) > 1
)
ORDER BY s.name, i.institute_code, s.sr_no;

-- ========================================
-- QUERY 3: Students with SAME NAME + SAME INSTITUTE (these are the duplicates)
-- ========================================

SELECT
  i.institute_code,
  s.name as student_name,
  COUNT(*) as duplicate_count,
  COUNT(DISTINCT s.sr_no) as different_sr_nos,
  COUNT(DISTINCT s.user_id) as different_user_ids,
  COUNT(DISTINCT s.subjects::text) as different_subject_sets,
  string_agg(DISTINCT s.sr_no::text, ', ' ORDER BY s.sr_no::text) as all_sr_nos,
  string_agg(s.id::text, ' | ') as all_record_ids
FROM public.students s
JOIN public.institutes i ON s.institute_id = i.id
GROUP BY i.institute_code, i.id, s.institute_id, s.name
HAVING COUNT(*) > 1
ORDER BY i.institute_code, s.name;

-- ========================================
-- QUERY 4: Students with SAME NAME but DIFFERENT INSTITUTES
-- (These are probably different people, not duplicates)
-- ========================================

SELECT
  s.name as student_name,
  COUNT(DISTINCT s.institute_id) as appears_in_institutes,
  string_agg(DISTINCT i.institute_code, ', ' ORDER BY i.institute_code) as institute_codes,
  string_agg(DISTINCT i.name, ' | ' ORDER BY i.name) as institute_names,
  COUNT(DISTINCT s.sr_no) as total_different_sr_nos,
  COUNT(DISTINCT s.user_id) as total_different_user_ids,
  COUNT(*) as total_records
FROM public.students s
LEFT JOIN public.institutes i ON s.institute_id = i.id
GROUP BY s.name
HAVING COUNT(DISTINCT s.institute_id) > 1
ORDER BY COUNT(DISTINCT s.institute_id) DESC;

-- ========================================
-- QUERY 5: For ONE student name, see all records side-by-side
-- (Change the name in the WHERE clause)
-- ========================================

SELECT
  s.name,
  i.institute_code,
  s.sr_no,
  s.user_id,
  s.id,
  s.subjects,
  s.created_at,
  CASE WHEN s.face_photo_url IS NOT NULL THEN 'YES' ELSE 'NO' END as has_photo,
  CASE WHEN s.face_embedding IS NOT NULL THEN 'YES' ELSE 'NO' END as has_embedding
FROM public.students s
LEFT JOIN public.institutes i ON s.institute_id = i.id
WHERE LOWER(s.name) = LOWER('AASHISH BALARAM GAIKAR')  -- CHANGE THIS NAME
ORDER BY i.institute_code, s.created_at;

-- ========================================
-- QUERY 6: Show duplicate status summary
-- ========================================

WITH all_names AS (
  SELECT s.name
  FROM public.students s
  GROUP BY s.name
  HAVING COUNT(*) > 1
),
same_institute_duplicates AS (
  SELECT
    i.institute_code,
    s.name,
    s.institute_id,
    COUNT(*) as count
  FROM public.students s
  JOIN public.institutes i ON s.institute_id = i.id
  WHERE s.name IN (SELECT name FROM all_names)
  GROUP BY i.institute_code, i.id, s.institute_id, s.name
  HAVING COUNT(*) > 1
),
different_institute_same_name AS (
  SELECT
    s.name,
    COUNT(DISTINCT s.institute_id) as institute_count
  FROM public.students s
  WHERE s.name IN (SELECT name FROM all_names)
  GROUP BY s.name
  HAVING COUNT(DISTINCT s.institute_id) > 1
)
SELECT
  'Same name, SAME institute (DUPLICATES - need merge)' as category,
  COUNT(*) as affected_groups,
  SUM(count) as total_records
FROM same_institute_duplicates
UNION ALL
SELECT
  'Same name, DIFFERENT institutes (likely different people)' as category,
  COUNT(*) as affected_groups,
  0 as total_records
FROM different_institute_same_name;

-- ========================================
-- QUERY 7: Which student names appear in MULTIPLE institutes?
-- ========================================

SELECT
  s.name,
  COUNT(DISTINCT s.institute_id) as num_institutes,
  string_agg(DISTINCT i.institute_code || ' (' || i.name || ')', ' | ' ORDER BY i.institute_code) as institutes,
  COUNT(DISTINCT s.user_id) as num_user_ids,
  COUNT(*) as total_records,
  CASE
    WHEN COUNT(DISTINCT s.institute_id) > 1 THEN 'Same name, different institutes (probably different people)'
    ELSE 'Same name, same institute (probably duplicates)'
  END as assessment
FROM public.students s
LEFT JOIN public.institutes i ON s.institute_id = i.id
GROUP BY s.name
HAVING COUNT(*) > 1
ORDER BY COUNT(DISTINCT s.institute_id) DESC, COUNT(*) DESC;

-- ========================================
-- QUERY 8: Check if they're showing in app
-- (This is what the app actually fetches for student management screen)
-- ========================================

-- Check one institute's student list
SELECT
  s.id,
  s.name,
  s.user_id,
  s.sr_no,
  s.year,
  s.subject,
  s.subjects,
  CASE WHEN s.face_photo_url IS NOT NULL THEN 'HAS PHOTO' ELSE 'NO PHOTO' END as photo_status,
  COUNT(*) OVER (PARTITION BY s.name, s.institute_id) as duplicate_count
FROM public.students s
WHERE s.institute_id = (
  SELECT id FROM public.institutes WHERE institute_code = '11063'  -- CHANGE THIS CODE
)
ORDER BY s.name, s.sr_no
LIMIT 100;

-- ========================================
-- QUERY 9: Count totals
-- ========================================

SELECT
  'Total students in database' as metric,
  COUNT(*) as count
FROM public.students
UNION ALL
SELECT
  'Students with duplicate name in SAME institute' as metric,
  COUNT(DISTINCT s.institute_id || '|' || s.name)
FROM public.students s
GROUP BY s.institute_id, s.name
HAVING COUNT(*) > 1
UNION ALL
SELECT
  'Unique student names (total)' as metric,
  COUNT(DISTINCT name)
FROM public.students
UNION ALL
SELECT
  'Student names appearing multiple times' as metric,
  COUNT(*)
FROM (
  SELECT s.name FROM public.students s GROUP BY s.name HAVING COUNT(*) > 1
) x;
