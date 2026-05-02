-- ============================================
-- DELETE ALL STUDENTS FROM INSTITUTE 3001
-- Simplified approach - working around schema differences
-- ============================================

-- STEP 1: Get all student IDs in institute 3001
SELECT id, name, sr_no FROM students
WHERE institute_id = '3001'
ORDER BY sr_no;

-- STEP 2: Count records before deletion
SELECT
  (SELECT COUNT(*) FROM students WHERE institute_id = '3001') as students_count,
  (SELECT COUNT(*) FROM attendance_records WHERE institute_id = '3001') as attendance_count,
  (SELECT COUNT(*) FROM attendance_in_out WHERE institute_code = '3001') as attendance_in_out_count;

-- ============================================
-- DELETION COMMANDS (Execute in order)
-- ============================================

-- DELETE 1: Delete attendance_in_out by institute code
DELETE FROM attendance_in_out
WHERE institute_code = '3001';

-- DELETE 2: Delete all attendance records
DELETE FROM attendance_records
WHERE institute_id = '3001';

-- DELETE 3: Delete registration records (by student_id)
DELETE FROM student_registrations
WHERE student_id IN (
  SELECT id FROM students WHERE institute_id = '3001'
);

-- DELETE 4: Delete all student records
DELETE FROM students
WHERE institute_id = '3001';

-- ============================================
-- VERIFY: All data deleted
-- ============================================
SELECT
  (SELECT COUNT(*) FROM students WHERE institute_id = '3001') as students_remaining,
  (SELECT COUNT(*) FROM attendance_records WHERE institute_id = '3001') as attendance_remaining,
  (SELECT COUNT(*) FROM attendance_in_out WHERE institute_code = '3001') as attendance_in_out_remaining,
  (SELECT COUNT(*) FROM student_registrations WHERE student_id IN (SELECT id FROM students WHERE institute_id = '3001')) as registration_remaining;

-- Expected: All should be 0
