-- Find students who registered TWICE with DIFFERENT SUBJECTS
-- (Same student name, same institute, same student ID, but different subjects)

-- 1. MAIN QUERY: Show all duplicate students with their subject differences
SELECT
  i.institute_code,
  i.name as institute_name,
  s.sr_no,
  s.user_id,
  s.name as student_name,
  COUNT(*) as total_registrations,
  string_agg(DISTINCT s.subjects::text, ' | ' ORDER BY s.subjects::text) as all_subjects,
  string_agg(DISTINCT s.subject, ', ' ORDER BY s.subject) as all_single_subjects,
  MIN(s.created_at) as first_registered,
  MAX(s.created_at) as last_registered,
  (MAX(s.created_at) - MIN(s.created_at)) as days_between_registrations
FROM public.students s
JOIN public.institutes i ON s.institute_id = i.id
WHERE
  (s.sr_no IS NOT NULL AND s.sr_no::text != '')
  OR
  (s.user_id IS NOT NULL AND s.user_id::text != '')
GROUP BY i.id, i.institute_code, i.name, s.institute_id, s.sr_no, s.user_id, s.name
HAVING COUNT(*) >= 2  -- Only students with 2 or more registrations
ORDER BY total_registrations DESC, i.institute_code, s.name;

-- 2. DETAILED: Show each registration record separately
SELECT
  i.institute_code,
  i.name as institute_name,
  s.sr_no,
  s.user_id,
  s.name as student_name,
  s.id as student_record_id,
  s.subjects,
  s.subject as single_subject,
  s.year,
  s.created_at as registered_at,
  CASE
    WHEN s.face_photo_url IS NOT NULL THEN 'YES'
    ELSE 'NO'
  END as has_photo,
  CASE
    WHEN s.face_embedding IS NOT NULL THEN 'YES'
    ELSE 'NO'
  END as has_face_embedding
FROM public.students s
JOIN public.institutes i ON s.institute_id = i.id
WHERE (s.institute_id, COALESCE(s.sr_no, s.user_id), s.name) IN (
  SELECT s2.institute_id, COALESCE(s2.sr_no, s2.user_id), s2.name
  FROM public.students s2
  GROUP BY s2.institute_id, COALESCE(s2.sr_no, s2.user_id), s2.name
  HAVING COUNT(*) >= 2
)
ORDER BY i.institute_code, s.sr_no, s.user_id, s.name, s.created_at;

-- 3. SUMMARY: Count by institute how many students registered twice
SELECT
  i.institute_code,
  i.name as institute_name,
  COUNT(DISTINCT COALESCE(s.sr_no, s.user_id, s.name)) as students_with_duplicate_registrations,
  SUM(
    (SELECT COUNT(*) - 1 FROM public.students s2
     WHERE s2.institute_id = s.institute_id
     AND COALESCE(s2.sr_no, s2.user_id) = COALESCE(s.sr_no, s.user_id)
     AND s2.name = s.name)
  ) as total_extra_registrations
FROM public.students s
JOIN public.institutes i ON s.institute_id = i.id
WHERE (s.institute_id, COALESCE(s.sr_no, s.user_id), s.name) IN (
  SELECT s2.institute_id, COALESCE(s2.sr_no, s2.user_id), s2.name
  FROM public.students s2
  GROUP BY s2.institute_id, COALESCE(s2.sr_no, s2.user_id), s2.name
  HAVING COUNT(*) >= 2
)
GROUP BY i.id, i.institute_code, i.name
ORDER BY students_with_duplicate_registrations DESC;

-- 4. SPECIFIC EXAMPLE: Show specific student who registered twice
-- (Uncomment and modify student name to check specific student)
/*
SELECT
  s.sr_no,
  s.user_id,
  s.name,
  s.subjects,
  s.year,
  s.created_at,
  s.id
FROM public.students s
WHERE s.name ILIKE '%bhushan%'
  AND s.institute_id = (
    SELECT id FROM public.institutes WHERE institute_code = '23101'
  )
ORDER BY s.created_at;
*/

-- 5. DATA QUALITY CHECK: Find students with confusing data
SELECT
  i.institute_code,
  s.sr_no,
  s.user_id,
  s.name,
  COUNT(*) as duplicate_count,
  COUNT(DISTINCT s.subjects::text) as different_subject_lists,
  COUNT(DISTINCT s.subject) as different_single_subjects,
  COUNT(DISTINCT s.year) as different_years
FROM public.students s
JOIN public.institutes i ON s.institute_id = i.id
WHERE (s.sr_no IS NOT NULL OR s.user_id IS NOT NULL)
GROUP BY i.id, i.institute_code, s.sr_no, s.user_id, s.name
HAVING
  COUNT(*) >= 2
  AND
  (COUNT(DISTINCT s.subjects::text) > 1 OR COUNT(DISTINCT s.subject) > 1)
ORDER BY duplicate_count DESC, i.institute_code, s.name;

-- 6. WHICH TO KEEP: Show recommended records to keep (newest with photo)
WITH duplicates AS (
  SELECT
    s.id,
    s.institute_id,
    s.sr_no,
    s.user_id,
    s.name,
    s.created_at,
    s.face_photo_url,
    s.face_embedding,
    ROW_NUMBER() OVER (
      PARTITION BY s.institute_id, COALESCE(s.sr_no, s.user_id), s.name
      ORDER BY
        CASE WHEN s.face_photo_url IS NOT NULL THEN 0 ELSE 1 END,
        s.created_at DESC
    ) as priority
  FROM public.students s
  WHERE (s.institute_id, COALESCE(s.sr_no, s.user_id), s.name) IN (
    SELECT s2.institute_id, COALESCE(s2.sr_no, s2.user_id), s2.name
    FROM public.students s2
    GROUP BY s2.institute_id, COALESCE(s2.sr_no, s2.user_id), s2.name
    HAVING COUNT(*) >= 2
  )
)
SELECT
  'KEEP' as action,
  i.institute_code,
  d.sr_no,
  d.user_id,
  d.name,
  d.id as student_record_id,
  d.created_at,
  CASE WHEN d.face_photo_url IS NOT NULL THEN 'HAS PHOTO' ELSE 'NO PHOTO' END as photo_status
FROM duplicates d
JOIN public.institutes i ON d.institute_id = i.id
WHERE d.priority = 1
ORDER BY i.institute_code, d.name;

-- 7. DELETE LIST: Show records to delete
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
  WHERE (s.institute_id, COALESCE(s.sr_no, s.user_id), s.name) IN (
    SELECT s2.institute_id, COALESCE(s2.sr_no, s2.user_id), s2.name
    FROM public.students s2
    GROUP BY s2.institute_id, COALESCE(s2.sr_no, s2.user_id), s2.name
    HAVING COUNT(*) >= 2
  )
)
SELECT
  'DELETE' as action,
  i.institute_code,
  d.sr_no,
  d.user_id,
  d.name,
  d.id as student_record_id,
  d.created_at,
  'DELETE FROM public.students WHERE id = ''' || d.id || ''';' as delete_sql
FROM duplicates d
JOIN public.institutes i ON d.institute_id = i.id
WHERE d.priority > 1
ORDER BY i.institute_code, d.name, d.priority;

-- 8. FINAL COUNT: How many duplicates total?
WITH duplicates AS (
  SELECT
    s.id,
    ROW_NUMBER() OVER (
      PARTITION BY s.institute_id, COALESCE(s.sr_no, s.user_id), s.name
      ORDER BY s.created_at DESC
    ) as priority
  FROM public.students s
  WHERE (s.institute_id, COALESCE(s.sr_no, s.user_id), s.name) IN (
    SELECT s2.institute_id, COALESCE(s2.sr_no, s2.user_id), s2.name
    FROM public.students s2
    GROUP BY s2.institute_id, COALESCE(s2.sr_no, s2.user_id), s2.name
    HAVING COUNT(*) >= 2
  )
)
SELECT
  'Total students with duplicate registrations' as metric,
  COUNT(DISTINCT CASE WHEN priority = 1 THEN id END) as count
FROM duplicates
UNION ALL
SELECT
  'Total duplicate records to delete',
  COUNT(*) - COUNT(DISTINCT CASE WHEN priority = 1 THEN id END)
FROM duplicates;
