-- ============================================
-- DATABASE CLEANUP: Remove Unused Columns
-- CLEAN VERSION - No psql commands
-- ============================================

-- ============================================
-- 1. STUDENTS TABLE - Remove unused columns
-- ============================================

ALTER TABLE students
DROP COLUMN IF EXISTS roll_number,
DROP COLUMN IF EXISTS contact,
DROP COLUMN IF EXISTS semester,
DROP COLUMN IF EXISTS father_name,
DROP COLUMN IF EXISTS mother_name,
DROP COLUMN IF EXISTS dob,
DROP COLUMN IF EXISTS address,
DROP COLUMN IF EXISTS email,
DROP COLUMN IF EXISTS status,
DROP COLUMN IF EXISTS face_match_threshold,
DROP COLUMN IF EXISTS registration_photo_path,
DROP COLUMN IF EXISTS embedding_version,
DROP COLUMN IF EXISTS quality_score;

-- ============================================
-- 2. ATTENDANCE_RECORDS TABLE - Remove unused
-- ============================================

ALTER TABLE attendance_records
DROP COLUMN IF EXISTS roll_number,
DROP COLUMN IF EXISTS latitude,
DROP COLUMN IF EXISTS longitude,
DROP COLUMN IF EXISTS device_id,
DROP COLUMN IF EXISTS admin_id,
DROP COLUMN IF EXISTS notes,
DROP COLUMN IF EXISTS source;

-- ============================================
-- 3. ATTENDANCE_IN_OUT TABLE - Remove unused
-- ============================================

ALTER TABLE attendance_in_out
DROP COLUMN IF EXISTS entry_latitude,
DROP COLUMN IF EXISTS entry_longitude,
DROP COLUMN IF EXISTS exit_latitude,
DROP COLUMN IF EXISTS exit_longitude,
DROP COLUMN IF EXISTS entry_device_id,
DROP COLUMN IF EXISTS exit_device_id,
DROP COLUMN IF EXISTS entry_admin_id,
DROP COLUMN IF EXISTS exit_admin_id;

-- ============================================
-- 4. STUDENT_REGISTRATIONS TABLE - Remove unused
-- ============================================

ALTER TABLE student_registrations
DROP COLUMN IF EXISTS embedding_version,
DROP COLUMN IF EXISTS quality_score,
DROP COLUMN IF EXISTS institute_id,
DROP COLUMN IF EXISTS updated_at;

-- ============================================
-- VERIFY CLEANUP - Data integrity check
-- ============================================

-- Count records in each table
SELECT
  'students' as table_name,
  COUNT(*) as record_count
FROM students

UNION ALL

SELECT
  'attendance_records' as table_name,
  COUNT(*) as record_count
FROM attendance_records

UNION ALL

SELECT
  'attendance_in_out' as table_name,
  COUNT(*) as record_count
FROM attendance_in_out

UNION ALL

SELECT
  'student_registrations' as table_name,
  COUNT(*) as record_count
FROM student_registrations;

-- ============================================
-- Verify students table columns
-- ============================================

SELECT column_name
FROM information_schema.columns
WHERE table_name = 'students'
ORDER BY ordinal_position;

-- ============================================
-- Verify attendance_records table columns
-- ============================================

SELECT column_name
FROM information_schema.columns
WHERE table_name = 'attendance_records'
ORDER BY ordinal_position;

-- ============================================
-- Verify attendance_in_out table columns
-- ============================================

SELECT column_name
FROM information_schema.columns
WHERE table_name = 'attendance_in_out'
ORDER BY ordinal_position;

-- ============================================
-- Verify student_registrations table columns
-- ============================================

SELECT column_name
FROM information_schema.columns
WHERE table_name = 'student_registrations'
ORDER BY ordinal_position;
