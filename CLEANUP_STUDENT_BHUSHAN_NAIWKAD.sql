-- ============================================
-- CLEANUP: Remove Student "bhushan naiwkad"
-- ============================================
-- This script removes the student and ALL associated data

-- Step 1: Find the student ID
-- Run this first to identify the student
SELECT
  id,
  name,
  institute_id,
  user_id,
  created_at,
  updated_at
FROM students
WHERE
  LOWER(name) LIKE LOWER('%bhushan%naiwkad%')
  OR LOWER(name) LIKE LOWER('%naiwkad%bhushan%')
LIMIT 5;

-- ============================================
-- DELETION SCRIPT (Run after identifying student ID)
-- ============================================
-- Replace 'STUDENT_ID_HERE' with actual student ID from above

-- Step 2: Get photos to delete from B2 (for reference)
SELECT
  'registration_photo_path' as photo_type,
  registration_photo_path as path
FROM student_registrations
WHERE student_id = 'STUDENT_ID_HERE'

UNION ALL

SELECT
  'attendance_photo' as photo_type,
  attendance_photo_path as path
FROM attendance_records
WHERE student_id = 'STUDENT_ID_HERE';

-- ============================================
-- DELETE IN ORDER (respect foreign keys)
-- ============================================

-- Step 3: Delete attendance records
DELETE FROM attendance_records
WHERE student_id = 'STUDENT_ID_HERE';

-- Step 4: Delete face registration embedding
DELETE FROM student_registrations
WHERE student_id = 'STUDENT_ID_HERE';

-- Step 5: Delete student record
DELETE FROM students
WHERE id = 'STUDENT_ID_HERE';

-- ============================================
-- VERIFY DELETION
-- ============================================
SELECT
  (SELECT COUNT(*) FROM students WHERE id = 'STUDENT_ID_HERE') as student_count,
  (SELECT COUNT(*) FROM student_registrations WHERE student_id = 'STUDENT_ID_HERE') as registration_count,
  (SELECT COUNT(*) FROM attendance_records WHERE student_id = 'STUDENT_ID_HERE') as attendance_count;

-- Expected result: All counts should be 0

-- ============================================
-- B2 STORAGE CLEANUP (Manual)
-- ============================================
-- After deleting database records, also delete photos from B2:
--
-- Paths to delete:
-- - registrations/{institute_id}/{student_id}_registration.jpg
-- - attendance/{institute_id}/{student_id}_*.jpg
--
-- Can be done via B2 console or b2 CLI:
-- b2 delete-file-version {fileId} {fileName}
