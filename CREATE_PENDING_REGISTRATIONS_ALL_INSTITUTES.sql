-- Create pending admin registrations for ALL institutes
-- This adds sample admin_invites for testing across all institutes

BEGIN;

-- Clear existing admin_invites first
DELETE FROM public.admin_invites;

-- Create pending registrations for every institute
INSERT INTO public.admin_invites (
  id,
  institute_id,
  full_name,
  email,
  phone,
  role,
  status,
  created_at,
  expires_at
)
SELECT
  gen_random_uuid()::text,
  id as institute_id,
  'Admin ' || name as full_name,
  'admin_' || id || '@institute.test' as email,
  '9876543210' as phone,
  'admin' as role,
  'pending' as status,
  NOW() as created_at,
  NOW() + INTERVAL '30 days' as expires_at
FROM public.institutes
ORDER BY id;

-- Verify
SELECT COUNT(*) as total_pending_registrations
FROM public.admin_invites;

SELECT institute_id, full_name, email, status
FROM public.admin_invites
LIMIT 10;

COMMIT;
