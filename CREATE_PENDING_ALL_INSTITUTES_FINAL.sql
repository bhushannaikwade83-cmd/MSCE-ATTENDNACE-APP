-- Create pending admin registrations for ALL institutes
-- Using correct admin_invites columns

BEGIN;

DELETE FROM public.admin_invites;

INSERT INTO public.admin_invites (id, institute_id, full_name, email, phone, claimed, created_at)
SELECT
  gen_random_uuid(),
  id,
  'Admin ' || name,
  'admin_' || id || '@institute.test',
  '9876543210',
  false,
  NOW()
FROM public.institutes
ORDER BY id;

SELECT COUNT(*) as total_pending FROM public.admin_invites;

COMMIT;
