-- ============================================
-- DELETE ALL STUDENTS FROM INSTITUTE 3001
-- Complete data removal for fresh testing
-- ============================================
-- ⚠️ WARNING: PERMANENT DELETION
-- This will delete:
-- - All 22+ students
-- - All attendance records
-- - All registration data
-- - All face embeddings
-- - All photo references
-- ============================================

-- STEP 1: List all students to be deleted
SELECT
  COUNT(*) as total_students,
  COUNT(DISTINCT id) as unique_students,
  COUNT(CASE WHEN face_embedding IS NOT NULL THEN 1 END) as with_embedding,
  COUNT(CASE WHEN photo_url IS NOT NULL THEN 1 END) as with_photo
FROM students
WHERE institute_id = '3001';

-- STEP 2: Show all student IDs and photos for B2 cleanup reference
SELECT
  id,
  name,
  sr_no,
  photo_url,
  face_photo_url,
  created_at
FROM students
WHERE institute_id = '3001'
ORDER BY sr_no;

-- STEP 3: Show all photos to be deleted from B2
SELECT
  'student_photo' as type,
  photo_url as file_url
FROM students
WHERE institute_id = '3001' AND photo_url IS NOT NULL

UNION ALL

SELECT
  'face_photo' as type,
  face_photo_url as file_url
FROM students
WHERE institute_id = '3001' AND face_photo_url IS NOT NULL

UNION ALL

SELECT
  'attendance_photo' as type,
  photo_url as file_url
FROM attendance_records
WHERE institute_id = '3001' AND photo_url IS NOT NULL;

-- STEP 4: Count records to be deleted
SELECT
  (SELECT COUNT(*) FROM students WHERE institute_id = '3001') as student_records,
  (SELECT COUNT(*) FROM attendance_records WHERE institute_id = '3001') as attendance_records,
  (SELECT COUNT(*) FROM attendance_in_out WHERE institute_code = '3001') as attendance_in_out_records,
  (SELECT COUNT(*) FROM student_registrations WHERE institute_id = '3001') as registration_records;

-- ============================================
-- DELETION COMMANDS (Execute in this order)
-- ============================================

-- DELETE 1: Attendance in/out records
DELETE FROM attendance_in_out
WHERE institute_code = '3001';

-- DELETE 2: Attendance records
DELETE FROM attendance_records
WHERE institute_id = '3001';

-- DELETE 3: Student registration records
DELETE FROM student_registrations
WHERE institute_id = '3001';

-- DELETE 4: All student records (FINAL)
DELETE FROM students
WHERE institute_id = '3001';

-- ============================================
-- VERIFY: All data deleted
-- ============================================
SELECT
  (SELECT COUNT(*) FROM students WHERE institute_id = '3001') as students_remaining,
  (SELECT COUNT(*) FROM attendance_records WHERE institute_id = '3001') as attendance_remaining,
  (SELECT COUNT(*) FROM attendance_in_out WHERE institute_code = '3001') as attendance_in_out_remaining,
  (SELECT COUNT(*) FROM student_registrations WHERE institute_id = '3001') as registration_remaining;

-- Expected result: All counts should be 0 if deletion successful
