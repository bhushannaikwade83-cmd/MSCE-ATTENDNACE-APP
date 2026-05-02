-- Identify which duplicate student records should be deleted
-- Keep: Most recent or one with most data
-- Delete: Older or incomplete records

-- 1. Find duplicates and mark which ones should be deleted (keep newest)
WITH duplicate_groups AS (
  SELECT
    institute_id,
    user_id,
    sr_no,
    name,
    id,
    subjects,
    subject,
    year,
    face_photo_url,
    face_embedding,
    created_at,
    ROW_NUMBER() OVER (
      PARTITION BY institute_id,
                   COALESCE(user_id, sr_no),
                   name
      ORDER BY created_at DESC, id
    ) as rn,
    COUNT(*) OVER (
      PARTITION BY institute_id,
                   COALESCE(user_id, sr_no),
                   name
    ) as total_duplicates
  FROM public.students
  WHERE (
    (user_id IS NOT NULL AND user_id::text != '')
    OR
    (sr_no IS NOT NULL AND sr_no::text != '')
  )
)
SELECT
  'KEEP' as action,
  institute_id,
  user_id,
  sr_no,
  name,
  id,
  subjects,
  year,
  created_at,
  CASE
    WHEN face_photo_url IS NOT NULL THEN 'Has photo'
    ELSE 'No photo'
  END as photo_status,
  CASE
    WHEN face_embedding IS NOT NULL THEN 'Has embedding'
    ELSE 'No embedding'
  END as embedding_status
FROM duplicate_groups
WHERE rn = 1 AND total_duplicates > 1
ORDER BY institute_id, user_id, sr_no, name;

-- 2. Get records to DELETE (older duplicates, keep newest)
WITH duplicate_groups AS (
  SELECT
    institute_id,
    user_id,
    sr_no,
    name,
    id,
    subjects,
    subject,
    year,
    face_photo_url,
    face_embedding,
    created_at,
    ROW_NUMBER() OVER (
      PARTITION BY institute_id,
                   COALESCE(user_id, sr_no),
                   name
      ORDER BY created_at DESC, id
    ) as rn,
    COUNT(*) OVER (
      PARTITION BY institute_id,
                   COALESCE(user_id, sr_no),
                   name
    ) as total_duplicates
  FROM public.students
  WHERE (
    (user_id IS NOT NULL AND user_id::text != '')
    OR
    (sr_no IS NOT NULL AND sr_no::text != '')
  )
)
SELECT
  'DELETE' as action,
  institute_id,
  user_id,
  sr_no,
  name,
  id,
  subjects,
  year,
  created_at,
  rn as duplicate_number,
  CASE
    WHEN face_photo_url IS NOT NULL THEN 'Has photo'
    ELSE 'No photo'
  END as photo_status
FROM duplicate_groups
WHERE rn > 1 AND total_duplicates > 1
ORDER BY institute_id, user_id, sr_no, name, created_at DESC;

-- 3. Summary of duplicates to clean up
WITH duplicate_groups AS (
  SELECT
    institute_id,
    user_id,
    sr_no,
    name,
    id,
    ROW_NUMBER() OVER (
      PARTITION BY institute_id,
                   COALESCE(user_id, sr_no),
                   name
      ORDER BY created_at DESC, id
    ) as rn
  FROM public.students
  WHERE (
    (user_id IS NOT NULL AND user_id::text != '')
    OR
    (sr_no IS NOT NULL AND sr_no::text != '')
  )
)
SELECT
  COUNT(*) as total_duplicate_records_to_delete,
  COUNT(DISTINCT (institute_id, COALESCE(user_id, sr_no), name)) as unique_student_duplicates
FROM duplicate_groups
WHERE rn > 1;

-- 4. Show institutes with duplicates needing cleanup
WITH duplicate_groups AS (
  SELECT
    institute_id,
    user_id,
    sr_no,
    name,
    id,
    ROW_NUMBER() OVER (
      PARTITION BY institute_id,
                   COALESCE(user_id, sr_no),
                   name
      ORDER BY created_at DESC, id
    ) as rn
  FROM public.students
  WHERE (
    (user_id IS NOT NULL AND user_id::text != '')
    OR
    (sr_no IS NOT NULL AND sr_no::text != '')
  )
)
SELECT
  i.institute_code,
  i.name as institute_name,
  COUNT(*) as records_to_delete,
  COUNT(DISTINCT (dg.institute_id, COALESCE(dg.user_id, dg.sr_no), dg.name)) as unique_duplicates
FROM duplicate_groups dg
JOIN public.institutes i ON dg.institute_id = i.id
WHERE dg.rn > 1
GROUP BY i.id, i.institute_code, i.name
ORDER BY records_to_delete DESC;

-- 5. Generate DELETE statement (VERIFY BEFORE RUNNING)
WITH duplicate_groups AS (
  SELECT
    institute_id,
    user_id,
    sr_no,
    name,
    id,
    ROW_NUMBER() OVER (
      PARTITION BY institute_id,
                   COALESCE(user_id, sr_no),
                   name
      ORDER BY created_at DESC, id
    ) as rn
  FROM public.students
  WHERE (
    (user_id IS NOT NULL AND user_id::text != '')
    OR
    (sr_no IS NOT NULL AND sr_no::text != '')
  )
)
SELECT
  'DELETE FROM public.students WHERE id = ''' || id || ''';' as delete_statement,
  institute_id,
  user_id,
  sr_no,
  name,
  rn
FROM duplicate_groups
WHERE rn > 1
ORDER BY institute_id, user_id, sr_no, name, rn;
