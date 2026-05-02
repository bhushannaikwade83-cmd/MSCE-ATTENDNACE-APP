-- Fix RLS policies on students table to allow face registration updates
-- This allows students to update their own face_embedding

BEGIN;

-- Disable RLS temporarily to check existing policies
ALTER TABLE students DISABLE ROW LEVEL SECURITY;

-- Drop existing restrictive policies if they exist
DROP POLICY IF EXISTS "students_select_policy" ON students;
DROP POLICY IF EXISTS "students_insert_policy" ON students;
DROP POLICY IF EXISTS "students_update_policy" ON students;
DROP POLICY IF EXISTS "Students can view their own data" ON students;
DROP POLICY IF EXISTS "Students can update their own data" ON students;

-- Re-enable RLS
ALTER TABLE students ENABLE ROW LEVEL SECURITY;

-- Policy 1: Students can SELECT their own record
CREATE POLICY "student_select_own"
ON students
FOR SELECT
TO authenticated
USING (
  auth.uid()::text = user_id OR
  auth.jwt() ->> 'role' = 'admin' OR
  auth.jwt() ->> 'role' = 'service_role'
);

-- Policy 2: Students can UPDATE their own face_embedding (CRITICAL for face registration)
CREATE POLICY "student_update_own_face_embedding"
ON students
FOR UPDATE
TO authenticated
USING (
  auth.uid()::text = user_id OR
  auth.jwt() ->> 'role' = 'admin' OR
  auth.jwt() ->> 'role' = 'service_role'
)
WITH CHECK (
  auth.uid()::text = user_id OR
  auth.jwt() ->> 'role' = 'admin' OR
  auth.jwt() ->> 'role' = 'service_role'
);

-- Policy 3: Admins can SELECT all students
CREATE POLICY "admin_select_all"
ON students
FOR SELECT
TO authenticated
USING (
  auth.jwt() ->> 'role' = 'admin' OR
  auth.jwt() ->> 'role' = 'service_role'
);

-- Policy 4: Admins can UPDATE all students
CREATE POLICY "admin_update_all"
ON students
FOR UPDATE
TO authenticated
USING (auth.jwt() ->> 'role' = 'admin' OR auth.jwt() ->> 'role' = 'service_role')
WITH CHECK (auth.jwt() ->> 'role' = 'admin' OR auth.jwt() ->> 'role' = 'service_role');

-- Policy 5: Allow ANON reads (for public registration)
CREATE POLICY "anon_select_institute_students"
ON students
FOR SELECT
TO anon
USING (true);

COMMIT;

-- Verify policies are in place
SELECT schemaname, tablename, policyname
FROM pg_policies
WHERE tablename = 'students'
ORDER BY policyname;
