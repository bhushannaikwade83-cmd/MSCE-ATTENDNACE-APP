-- =============================================================================
-- HARD DELETE — Student: Bhushan Ashok Naikwade (+ photos/metadata in Postgres)
--
-- Matches when name contains all three (case-insensitive): bhushan, ashok, naikwade
--
-- Deletes (when present): teacher_attendance, attendance_in_out (id + roll keys),
-- attendance_records, institute_daily_status, student_leaves, student_registrations,
-- students row(s).
--
-- Does NOT delete: auth.users, profiles (admin). If this student shares a login
-- profile row, unlink manually if needed.
--
-- B2 / object storage: DB rows embed URLs/paths — remove files separately in Backblaze
-- (registration + attendance prefixes for this institute/sr/user) if required for
-- compliance; this script clears Supabase-only data.
--
-- Run whole script in Supabase SQL Editor once. Prefer service_role/postgres if RLS blocks DELETE.
-- =============================================================================

CREATE TEMP TABLE _del_tgt AS
SELECT
  trim(both FROM id::text) AS id,
  trim(both FROM institute_id::text) AS institute_id,
  trim(both FROM coalesce(user_id, '')) AS user_id,
  trim(both FROM coalesce(sr_no, '')) AS sr_no,
  trim(both FROM coalesce(name, '')) AS name
FROM public.students
WHERE name ILIKE '%bhushan%'
  AND name ILIKE '%ashok%'
  AND name ILIKE '%naikwade%';

-- ---------------------------------------------------------------------------
-- 0) REVIEW targets (confirm before destructive steps)
-- ---------------------------------------------------------------------------
SELECT *
FROM _del_tgt;

SELECT
  s.id,
  s.name,
  s.institute_id,
  s.user_id,
  s.sr_no
FROM public.students s
WHERE s.id IN (SELECT id FROM _del_tgt);

-- Photo paths / embeddings (optional preview — skip this block if `student_registrations` does not exist)
SELECT sr.*
FROM student_registrations sr
WHERE sr.student_id IN (SELECT id FROM _del_tgt);


-- ---------------------------------------------------------------------------
-- 1) Attendance / marks
-- ---------------------------------------------------------------------------
DELETE FROM teacher_attendance ta
WHERE EXISTS (
      SELECT 1
      FROM _del_tgt s
      WHERE ta.institute_id = s.institute_id
        AND trim(both FROM coalesce(ta.student_id, '')) <> ''
        AND (
             trim(both FROM ta.student_id) = trim(both FROM s.user_id)
          OR trim(both FROM ta.student_id) = trim(both FROM s.sr_no)
          OR trim(both FROM ta.student_id) = trim(both FROM s.id::text)
        )
    )
   OR EXISTS (
      SELECT 1
      FROM _del_tgt s
      WHERE trim(both FROM coalesce(ta.student_id, '')) = trim(both FROM s.id::text)
    );

DELETE FROM attendance_in_out aio
USING _del_tgt s
JOIN public.institutes i ON i.id = s.institute_id
WHERE (
     trim(both FROM aio.student_id) = trim(both FROM s.id::text)
  OR (s.user_id <> '' AND trim(both FROM aio.student_id) = s.user_id)
  OR (s.sr_no <> '' AND trim(both FROM aio.student_id) = s.sr_no)
)
AND (
     trim(both FROM aio.institute_code) = trim(both FROM s.institute_id)
  OR (
       coalesce(nullif(trim(both FROM i.institute_code), ''), '') <> ''
       AND trim(both FROM aio.institute_code) = trim(both FROM i.institute_code)
     )
);

DO $body$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_name = 'attendance_records'
  ) THEN
    DELETE FROM attendance_records ar
    WHERE ar.student_id IN (SELECT id FROM _del_tgt)
       OR ar.student_id::text IN (SELECT user_id FROM _del_tgt WHERE user_id <> '')
       OR ar.student_id::text IN (SELECT sr_no FROM _del_tgt WHERE sr_no <> '');
  END IF;
END
$body$;

-- ---------------------------------------------------------------------------
-- 2) Other student-scoped rows
-- ---------------------------------------------------------------------------
DELETE FROM institute_daily_status d
USING _del_tgt s
WHERE d.institute_id = s.institute_id
  AND (
       trim(both FROM d.student_id) = trim(both FROM s.id::text)
    OR (s.user_id <> '' AND trim(both FROM d.student_id) = s.user_id)
    OR (s.sr_no <> '' AND trim(both FROM d.student_id) = s.sr_no)
  );

DELETE FROM student_leaves le
USING _del_tgt s
WHERE le.institute_id = s.institute_id
  AND (
       trim(both FROM coalesce(le.student_id, '')) = trim(both FROM s.id::text)
    OR (s.user_id <> '' AND trim(both FROM coalesce(le.student_id, '')) = s.user_id)
    OR (s.sr_no <> '' AND trim(both FROM coalesce(le.student_id, '')) = s.sr_no)
    OR (s.user_id <> '' AND trim(both FROM coalesce(le.user_id, '')) = s.user_id)
  );

-- Face / registration payloads (embedding + paths)
DELETE FROM student_registrations sr
WHERE sr.student_id IN (SELECT id FROM _del_tgt);

-- ---------------------------------------------------------------------------
-- 3) Student row — removes Postgres-side photo URLs / embedding snapshot
-- ---------------------------------------------------------------------------
DELETE FROM public.students st
WHERE st.id IN (SELECT id FROM _del_tgt);

-- ---------------------------------------------------------------------------
-- 4) VERIFY
-- ---------------------------------------------------------------------------
SELECT 'students_remaining' AS check_name, COUNT(*)::bigint AS n
FROM public.students
WHERE name ILIKE '%bhushan%'
  AND name ILIKE '%ashok%'
  AND name ILIKE '%naikwade%'

UNION ALL
SELECT 'registrations_remaining', COUNT(*)::bigint
FROM student_registrations
WHERE student_id IN (SELECT id FROM _del_tgt)

UNION ALL
SELECT 'teacher_attendance_matching_id', COUNT(*)::bigint
FROM teacher_attendance ta
WHERE EXISTS (
  SELECT 1
  FROM _del_tgt s
  WHERE ta.institute_id = s.institute_id
    AND (
          trim(both FROM ta.student_id) = trim(both FROM s.id::text)
       OR ta.student_id IS NOT DISTINCT FROM NULLIF(trim(s.user_id), '')
       OR ta.student_id IS NOT DISTINCT FROM NULLIF(trim(s.sr_no), '')
    )
);

DROP TABLE IF EXISTS _del_tgt;
