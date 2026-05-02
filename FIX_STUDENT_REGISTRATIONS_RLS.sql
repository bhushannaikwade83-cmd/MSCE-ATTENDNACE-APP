-- Fix RLS policies on student_registrations table
-- Allow students to insert/update their own registration records

BEGIN;

-- Disable RLS temporarily
ALTER TABLE student_registrations DISABLE ROW LEVEL SECURITY;

-- Drop existing restrictive policies
DROP POLICY IF EXISTS "student_registrations_select_policy" ON student_registrations;
DROP POLICY IF EXISTS "student_registrations_insert_policy" ON student_registrations;
DROP POLICY IF EXISTS "student_registrations_update_policy" ON student_registrations;

-- Re-enable RLS
ALTER TABLE student_registrations ENABLE ROW LEVEL SECURITY;

-- Policy 1: Students can INSERT their own registration
CREATE POLICY "student_insert_own_registration"
ON student_registrations
FOR INSERT
TO authenticated
WITH CHECK (
  student_id IN (SELECT id FROM students WHERE user_id = auth.uid()::text) OR
  auth.jwt() ->> 'role' = 'admin' OR
  auth.jwt() ->> 'role' = 'service_role'
);

-- Policy 2: Students can SELECT their own registration
CREATE POLICY "student_select_own_registration"
ON student_registrations
FOR SELECT
TO authenticated
USING (
  student_id IN (SELECT id FROM students WHERE user_id = auth.uid()::text) OR
  auth.jwt() ->> 'role' = 'admin' OR
  auth.jwt() ->> 'role' = 'service_role'
);

-- Policy 3: Students can UPDATE their own registration
CREATE POLICY "student_update_own_registration"
ON student_registrations
FOR UPDATE
TO authenticated
USING (
  student_id IN (SELECT id FROM students WHERE user_id = auth.uid()::text) OR
  auth.jwt() ->> 'role' = 'admin' OR
  auth.jwt() ->> 'role' = 'service_role'
)
WITH CHECK (
  student_id IN (SELECT id FROM students WHERE user_id = auth.uid()::text) OR
  auth.jwt() ->> 'role' = 'admin' OR
  auth.jwt() ->> 'role' = 'service_role'
);

-- Policy 4: Admins can do everything
CREATE POLICY "admin_all_registrations"
ON student_registrations
FOR ALL
TO authenticated
USING (auth.jwt() ->> 'role' = 'admin' OR auth.jwt() ->> 'role' = 'service_role')
WITH CHECK (auth.jwt() ->> 'role' = 'admin' OR auth.jwt() ->> 'role' = 'service_role');

COMMIT;

-- Verify policies
SELECT schemaname, tablename, policyname
FROM pg_policies
WHERE tablename = 'student_registrations'
ORDER BY policyname;
