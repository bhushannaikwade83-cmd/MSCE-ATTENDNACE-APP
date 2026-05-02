-- ============================================
-- DELETE STUDENT: MANUAL_1776969546681
-- Student: Bhushan Naikwade
-- ============================================
-- ⚠️ WARNING: PERMANENT DELETION
-- Confirmed deletion: deleteall with photos
-- Date: April 24, 2026
-- ============================================

-- STEP 1: VERIFY Student to be deleted
SELECT
  id,
  name,
  sr_no,
  user_id,
  institute_id,
  photo_url,
  face_photo_url,
  created_at
FROM students
WHERE id = 'MANUAL_1776969546681';

-- STEP 2: Count records to be deleted
SELECT
  (SELECT COUNT(*) FROM attendance_records WHERE student_id = 'MANUAL_1776969546681') as attendance_count,
  (SELECT COUNT(*) FROM student_registrations WHERE student_id = 'MANUAL_1776969546681') as registration_count;

-- STEP 3: Show all photos to be deleted (for B2 cleanup reference)
SELECT
  'student_photo' as type,
  photo_url as file_url
FROM students
WHERE id = 'MANUAL_1776969546681'
  AND photo_url IS NOT NULL

UNION ALL

SELECT
  'face_photo' as type,
  face_photo_url as file_url
FROM students
WHERE id = 'MANUAL_1776969546681'
  AND face_photo_url IS NOT NULL

UNION ALL

SELECT
  'attendance_photo' as type,
  photo_url as file_url
FROM attendance_records
WHERE student_id = 'MANUAL_1776969546681'
  AND photo_url IS NOT NULL;

-- ============================================
-- DELETION COMMANDS (Execute in order)
-- ============================================

-- DELETE 1: All attendance records
DELETE FROM attendance_records
WHERE student_id = 'MANUAL_1776969546681';

-- DELETE 2: Face registration data
DELETE FROM student_registrations
WHERE student_id = 'MANUAL_1776969546681';

-- DELETE 3: Student record (FINAL)
DELETE FROM students
WHERE id = 'MANUAL_1776969546681';

-- ============================================
-- VERIFY: All data deleted
-- ============================================
SELECT
  (SELECT COUNT(*) FROM students WHERE id = 'MANUAL_1776969546681') as students_remaining,
  (SELECT COUNT(*) FROM attendance_records WHERE student_id = 'MANUAL_1776969546681') as attendance_remaining,
  (SELECT COUNT(*) FROM student_registrations WHERE student_id = 'MANUAL_1776969546681') as registration_remaining;

-- Expected result: All counts should be 0 if deletion successful
