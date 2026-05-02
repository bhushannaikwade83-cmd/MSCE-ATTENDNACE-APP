-- Find: Students with SAME NAME but DIFFERENT SR_NO in same institute
-- Example: "Bhushan Naikwade" with SR 001 AND SR 002 in Prima (23101)

-- 1. MAIN: Show all students grouped by name (same institute)
SELECT
  i.institute_code,
  i.name as institute_name,
  s.name as student_name,
  COUNT(*) as how_many_records,
  COUNT(DISTINCT s.sr_no) as different_sr_nos,
  string_agg(DISTINCT s.sr_no, ', ' ORDER BY s.sr_no) as all_sr_nos,
  COUNT(DISTINCT s.subjects::text) as different_subject_sets,
  string_agg(DISTINCT s.subjects::text, ' | ' ORDER BY s.subjects::text) as all_subject_combinations
FROM public.students s
JOIN public.institutes i ON s.institute_id = i.id
GROUP BY i.id, i.institute_code, i.name, s.name
HAVING COUNT(DISTINCT s.sr_no) > 1  -- Same name with DIFFERENT SR_NO
ORDER BY i.institute_code, s.name;

-- 2. DETAILED: Show each record for students with same name, different SR_NO
SELECT
  i.institute_code,
  s.name as student_name,
  s.sr_no,
  s.user_id,
  s.subjects,
  s.year,
  s.id,
  s.created_at,
  CASE WHEN s.face_photo_url IS NOT NULL THEN 'YES' ELSE 'NO' END as has_photo
FROM public.students s
JOIN public.institutes i ON s.institute_id = i.id
WHERE (i.institute_code, s.name) IN (
  SELECT i2.institute_code, s2.name
  FROM public.students s2
  JOIN public.institutes i2 ON s2.institute_id = i2.id
  GROUP BY i2.institute_code, s2.name
  HAVING COUNT(DISTINCT s2.sr_no) > 1
)
ORDER BY i.institute_code, s.name, s.sr_no;

-- 3. COUNT: How many students have this issue (same name, different SR_NO)
SELECT
  COUNT(DISTINCT s.name) as students_with_same_name_different_srno,
  COUNT(*) as total_records_involved
FROM (
  SELECT i.institute_code, s.name, COUNT(DISTINCT s.sr_no) as sr_count
  FROM public.students s
  JOIN public.institutes i ON s.institute_id = i.id
  GROUP BY i.institute_code, s.name
  HAVING COUNT(DISTINCT s.sr_no) > 1
) subquery;

-- 4. BY INSTITUTE: Which institutes have this problem?
SELECT
  i.institute_code,
  i.name as institute_name,
  COUNT(DISTINCT s.name) as students_with_multiple_sr_nos,
  COUNT(*) as total_records,
  string_agg(DISTINCT s.name, ', ' ORDER BY s.name) as student_names
FROM public.students s
JOIN public.institutes i ON s.institute_id = i.id
WHERE (i.institute_code, s.name) IN (
  SELECT i2.institute_code, s2.name
  FROM public.students s2
  JOIN public.institutes i2 ON s2.institute_id = i2.id
  GROUP BY i2.institute_code, s2.name
  HAVING COUNT(DISTINCT s2.sr_no) > 1
)
GROUP BY i.id, i.institute_code, i.name
ORDER BY students_with_multiple_sr_nos DESC;

-- 5. EXAMPLE: Show specific case
-- (e.g., all "Bhushan Naikwade" records in Prima)
SELECT
  i.institute_code,
  s.name,
  s.sr_no as 'SR NO (different!)',
  s.user_id,
  s.subjects as 'Subjects (different!)',
  s.year,
  s.created_at
FROM public.students s
JOIN public.institutes i ON s.institute_id = i.id
WHERE i.institute_code = '23101'  -- Change institute code
  AND s.name ILIKE '%bhushan%'     -- Change student name
ORDER BY s.sr_no;

-- 6. IS THIS CORRECT DATA?
-- Check if these are REALLY different students with same name
-- or if they're duplicate registrations
SELECT
  i.institute_code,
  s.name,
  string_agg(DISTINCT s.sr_no, ', ') as sr_nos,
  COUNT(*) as records,
  COUNT(DISTINCT s.user_id) as different_user_ids,
  COUNT(DISTINCT s.subjects::text) as different_subjects,
  'Likely DIFFERENT students' as assessment
FROM public.students s
JOIN public.institutes i ON s.institute_id = i.id
WHERE (i.institute_code, s.name) IN (
  SELECT i2.institute_code, s2.name
  FROM public.students s2
  JOIN public.institutes i2 ON s2.institute_id = i2.id
  GROUP BY i2.institute_code, s2.name
  HAVING COUNT(DISTINCT s2.sr_no) > 1
)
GROUP BY i.id, i.institute_code, s.name
ORDER BY i.institute_code;

-- 7. ARE THEY DUPLICATES OR DIFFERENT STUDENTS?
-- If they have different SR_NO and different subjects, they're probably DIFFERENT students
-- (just happen to have same/similar name)
SELECT
  i.institute_code,
  s.name,
  s.sr_no,
  s.subjects,
  CASE
    WHEN COUNT(DISTINCT s.sr_no) OVER (PARTITION BY i.institute_code, s.name) > 1
      AND COUNT(DISTINCT s.subjects::text) OVER (PARTITION BY i.institute_code, s.name) > 1
    THEN '✓ Likely DIFFERENT students (different SR_NO + subjects)'
    ELSE '✗ Likely DUPLICATES'
  END as assessment
FROM public.students s
JOIN public.institutes i ON s.institute_id = i.id
WHERE (i.institute_code, s.name) IN (
  SELECT i2.institute_code, s2.name
  FROM public.students s2
  JOIN public.institutes i2 ON s2.institute_id = i2.id
  GROUP BY i2.institute_code, s2.name
  HAVING COUNT(DISTINCT s2.sr_no) > 1
)
ORDER BY i.institute_code, s.name, s.sr_no;

-- 8. SUMMARY: Are these real students or data errors?
WITH name_groups AS (
  SELECT
    i.institute_code,
    s.name,
    COUNT(DISTINCT s.sr_no) as different_sr_nos,
    COUNT(DISTINCT s.subjects::text) as different_subjects,
    COUNT(*) as total_records
  FROM public.students s
  JOIN public.institutes i ON s.institute_id = i.id
  GROUP BY i.institute_code, s.name
  HAVING COUNT(DISTINCT s.sr_no) > 1
)
SELECT
  'Data Quality Issue' as category,
  COUNT(*) as groups_affected,
  SUM(different_sr_nos) as total_different_sr_nos,
  SUM(total_records) as total_records_involved
FROM name_groups;
