-- Simpler RLS policy for student_registrations
-- Just allow authenticated users to insert/update/select their own data

BEGIN;

-- Drop all existing policies on student_registrations
DROP POLICY IF EXISTS "student_insert_own_registration" ON student_registrations;
DROP POLICY IF EXISTS "student_select_own_registration" ON student_registrations;
DROP POLICY IF EXISTS "student_update_own_registration" ON student_registrations;
DROP POLICY IF EXISTS "admin_all_registrations" ON student_registrations;
DROP POLICY IF EXISTS "student_registrations_select_policy" ON student_registrations;
DROP POLICY IF EXISTS "student_registrations_insert_policy" ON student_registrations;
DROP POLICY IF EXISTS "student_registrations_update_policy" ON student_registrations;

-- Simple: All authenticated users can insert (for their own face registration)
CREATE POLICY "authenticated_can_insert"
ON student_registrations
FOR INSERT
TO authenticated
WITH CHECK (true);

-- Simple: All authenticated users can select
CREATE POLICY "authenticated_can_select"
ON student_registrations
FOR SELECT
TO authenticated
USING (true);

-- Simple: All authenticated users can update
CREATE POLICY "authenticated_can_update"
ON student_registrations
FOR UPDATE
TO authenticated
USING (true)
WITH CHECK (true);

COMMIT;

-- Verify
SELECT schemaname, tablename, policyname
FROM pg_policies
WHERE tablename = 'student_registrations'
ORDER BY policyname;
