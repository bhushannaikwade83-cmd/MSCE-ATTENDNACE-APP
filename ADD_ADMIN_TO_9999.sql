-- Add admin details to institute 9999

-- Part 1: Update institutes table
UPDATE public.institutes
SET
  admin_full_name = 'Nandkumar Bedse',
  admin_email = 'bedse2014@gmail.com',
  admin_phone = '7020745525'
WHERE institute_code = '9999' OR id = '9999';

-- Part 2: Add/Update admin_invites
INSERT INTO public.admin_invites (id, institute_id, full_name, email, phone, claimed, created_at)
SELECT
  gen_random_uuid(),
  id,
  'Nandkumar Bedse',
  'bedse2014@gmail.com',
  '7020745525',
  false,
  NOW()
FROM public.institutes
WHERE (institute_code = '9999' OR id = '9999')
  AND NOT EXISTS (
    SELECT 1 FROM public.admin_invites
    WHERE institute_id = institutes.id
  );

-- Part 3: Verify
SELECT id, institute_code, name, admin_full_name, admin_email, admin_phone
FROM public.institutes
WHERE institute_code = '9999' OR id = '9999';
