-- Find duplicate students: same institute + same sr_no/user_id + same name, but DIFFERENT subjects

-- 1. Duplicates by user_id (if filled)
SELECT
  institute_id,
  user_id,
  name,
  COUNT(*) as duplicate_count,
  COUNT(DISTINCT subjects::text) as different_subject_combinations,
  string_agg(DISTINCT subjects::text, ' | ') as subject_variations
FROM public.students
WHERE user_id IS NOT NULL
  AND user_id::text != ''
GROUP BY institute_id, user_id, name
HAVING COUNT(*) > 1
ORDER BY duplicate_count DESC;

-- 2. Duplicates by sr_no (if filled)
SELECT
  institute_id,
  sr_no,
  name,
  COUNT(*) as duplicate_count,
  COUNT(DISTINCT subjects::text) as different_subject_combinations,
  string_agg(DISTINCT subjects::text, ' | ') as subject_variations
FROM public.students
WHERE sr_no IS NOT NULL
  AND sr_no::text != ''
GROUP BY institute_id, sr_no, name
HAVING COUNT(*) > 1
ORDER BY duplicate_count DESC;

-- 3. Show ALL details of duplicates by user_id
SELECT
  id,
  institute_id,
  user_id,
  sr_no,
  name,
  subjects,
  subject as single_subject,
  year,
  created_at
FROM public.students
WHERE (institute_id, user_id, name) IN (
  SELECT institute_id, user_id, name
  FROM public.students
  WHERE user_id IS NOT NULL AND user_id::text != ''
  GROUP BY institute_id, user_id, name
  HAVING COUNT(*) > 1
)
ORDER BY institute_id, user_id, name, created_at;

-- 4. Show ALL details of duplicates by sr_no
SELECT
  id,
  institute_id,
  sr_no,
  user_id,
  name,
  subjects,
  subject as single_subject,
  year,
  created_at
FROM public.students
WHERE (institute_id, sr_no, name) IN (
  SELECT institute_id, sr_no, name
  FROM public.students
  WHERE sr_no IS NOT NULL AND sr_no::text != ''
  GROUP BY institute_id, sr_no, name
  HAVING COUNT(*) > 1
)
ORDER BY institute_id, sr_no, name, created_at;

-- 5. Count total duplicates
SELECT
  'Duplicates by user_id' as type,
  COUNT(DISTINCT (institute_id, user_id, name)) as total_duplicate_groups
FROM public.students
WHERE user_id IS NOT NULL AND user_id::text != ''
GROUP BY 1
UNION ALL
SELECT
  'Duplicates by sr_no' as type,
  COUNT(DISTINCT (institute_id, sr_no, name)) as total_duplicate_groups
FROM public.students
WHERE sr_no IS NOT NULL AND sr_no::text != ''
GROUP BY 1;

-- 6. Summary: Institutes with most duplicates
SELECT
  i.institute_code,
  i.name as institute_name,
  COUNT(DISTINCT (s.user_id, s.name)) as duplicate_groups_by_user_id,
  COUNT(DISTINCT (s.sr_no, s.name)) as duplicate_groups_by_sr_no
FROM public.students s
JOIN public.institutes i ON s.institute_id = i.id
WHERE (
  (s.user_id IS NOT NULL AND s.user_id::text != '')
  OR
  (s.sr_no IS NOT NULL AND s.sr_no::text != '')
)
GROUP BY i.id, i.institute_code, i.name
HAVING
  COUNT(DISTINCT (s.user_id, s.name)) > 0
  OR
  COUNT(DISTINCT (s.sr_no, s.name)) > 0
ORDER BY
  (COUNT(DISTINCT (s.user_id, s.name)) + COUNT(DISTINCT (s.sr_no, s.name))) DESC;
