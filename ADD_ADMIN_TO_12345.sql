-- Add admin details to institute 12345

-- Part 1: Update institutes table
UPDATE public.institutes
SET
  admin_full_name = 'Nitin Duryodhan Kirdakar',
  admin_email = 'nitin.kirdakar@gmail.com',
  admin_phone = '8329012808'
WHERE institute_code = '12345' OR id = '12345';

-- Part 2: Add/Update admin_invites
INSERT INTO public.admin_invites (id, institute_id, full_name, email, phone, claimed, created_at)
SELECT
  gen_random_uuid(),
  id,
  'Nitin Duryodhan Kirdakar',
  'nitin.kirdakar@gmail.com',
  '8329012808',
  false,
  NOW()
FROM public.institutes
WHERE (institute_code = '12345' OR id = '12345')
  AND NOT EXISTS (
    SELECT 1 FROM public.admin_invites
    WHERE institute_id = institutes.id
  );

-- Part 3: Verify
SELECT id, institute_code, name, admin_full_name, admin_email, admin_phone
FROM public.institutes
WHERE institute_code = '12345' OR id = '12345';
