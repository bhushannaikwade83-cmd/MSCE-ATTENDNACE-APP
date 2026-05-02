-- ============================================
-- DATABASE CLEANUP: Remove Unused Columns
-- Keep ONLY columns that are integrated in the app
-- ============================================

-- ============================================
-- TABLE 1: students
-- ============================================
-- CURRENTLY USED COLUMNS:
--   ✅ id (PK)
--   ✅ institute_id (FK)
--   ✅ user_id (admin/user reference)
--   ✅ sr_no (sequential student number)
--   ✅ name (student name)
--   ✅ batch_id (batch reference)
--   ✅ face_embedding (neural embedding for attendance)
--   ✅ photo_url (student photo)
--   ✅ face_photo_url (face photo from registration)
--   ✅ subjects (JSON array of subject IDs)
--   ✅ created_at
--   ✅ updated_at

-- UNUSED/REMOVE:
-- ❌ roll_number (replaced by sr_no)
-- ❌ contact (not used anywhere)
-- ❌ semester (redundant with batch)
-- ❌ father_name (not used)
-- ❌ mother_name (not used)
-- ❌ dob (not used)
-- ❌ address (not used)
-- ❌ email (not used)
-- ❌ status (not used)
-- ❌ face_match_threshold (not used)
-- ❌ registration_photo_path (duplicate of photo_url)
-- ❌ embedding_version (redundant with face_embedding.version)
-- ❌ quality_score (duplicate of face_embedding.qualityScore)

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
-- TABLE 2: attendance_records
-- ============================================
-- CURRENTLY USED COLUMNS:
--   ✅ id (PK)
--   ✅ student_id (FK to students)
--   ✅ institute_id (FK to institutes)
--   ✅ status ('present', 'absent', 'leave')
--   ✅ embedding_similarity (face match score 0-1)
--   ✅ anti_spoof_confidence (liveness score)
--   ✅ photo_url (attendance photo)
--   ✅ attended_at (timestamp of attendance)
--   ✅ created_at
--   ✅ updated_at

-- UNUSED/REMOVE:
-- ❌ roll_number (use student_id instead)
-- ❌ latitude/longitude (use attendance_in_out table)
-- ❌ device_id (not used for verification)
-- ❌ admin_id (not used)
-- ❌ notes (not used)
-- ❌ source (not used)

ALTER TABLE attendance_records
DROP COLUMN IF EXISTS roll_number,
DROP COLUMN IF EXISTS latitude,
DROP COLUMN IF EXISTS longitude,
DROP COLUMN IF EXISTS device_id,
DROP COLUMN IF EXISTS admin_id,
DROP COLUMN IF EXISTS notes,
DROP COLUMN IF EXISTS source;

-- ============================================
-- TABLE 3: attendance_in_out
-- ============================================
-- CURRENTLY USED COLUMNS:
--   ✅ id (PK)
--   ✅ student_id (FK to students)
--   ✅ institute_code (institute reference)
--   ✅ date (attendance date YYYY-MM-DD)
--   ✅ entry_time (entry timestamp)
--   ✅ entry_photo_url (entry photo)
--   ✅ entry_embedding_similarity (entry face match)
--   ✅ exit_time (exit timestamp)
--   ✅ exit_photo_url (exit photo)
--   ✅ exit_embedding_similarity (exit face match)
--   ✅ created_at
--   ✅ updated_at

-- UNUSED/REMOVE:
-- ❌ entry_latitude/entry_longitude (GPS not fully integrated)
-- ❌ exit_latitude/exit_longitude (GPS not fully integrated)
-- ❌ entry_device_id (not used)
-- ❌ exit_device_id (not used)
-- ❌ entry_admin_id (not used)
-- ❌ exit_admin_id (not used)

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
-- TABLE 4: student_registrations
-- ============================================
-- CURRENTLY USED COLUMNS:
--   ✅ id (PK)
--   ✅ student_id (FK to students)
--   ✅ face_embedding (registration embedding)
--   ✅ registration_photo_path (initial registration photo)
--   ✅ created_at

-- UNUSED/REMOVE:
-- ❌ embedding_version (redundant with face_embedding.version)
-- ❌ quality_score (duplicate of face_embedding.qualityScore)
-- ❌ institute_id (can get from student)
-- ❌ updated_at (not used for registrations)

ALTER TABLE student_registrations
DROP COLUMN IF EXISTS embedding_version,
DROP COLUMN IF EXISTS quality_score,
DROP COLUMN IF EXISTS institute_id,
DROP COLUMN IF EXISTS updated_at;

-- ============================================
-- VERIFY CLEANUP
-- ============================================

-- Show students table structure
\d students;

-- Show attendance_records table structure
\d attendance_records;

-- Show attendance_in_out table structure
\d attendance_in_out;

-- Show student_registrations table structure
\d student_registrations;

-- ============================================
-- FINAL VERIFICATION: Count data integrity
-- ============================================

SELECT
  (SELECT COUNT(*) FROM students) as student_records,
  (SELECT COUNT(*) FROM attendance_records) as attendance_records,
  (SELECT COUNT(*) FROM attendance_in_out) as attendance_in_out_records,
  (SELECT COUNT(*) FROM student_registrations) as registration_records;
