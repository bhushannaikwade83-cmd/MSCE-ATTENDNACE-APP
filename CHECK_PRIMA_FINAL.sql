-- Check Prima email - final version

-- 1. Is primacomputer@gmail.com in profiles?
SELECT 'IN PROFILES' as status, COUNT(*) as count
FROM public.profiles
WHERE email = 'primacomputer@gmail.com';

-- 2. Is primacomputer@gmail.com in admin_invites?
SELECT 'IN ADMIN_INVITES' as status, COUNT(*) as count
FROM public.admin_invites
WHERE email = 'primacomputer@gmail.com';

-- 3. Details for Prima institute (23101)
SELECT
  i.institute_code,
  i.name,
  i.admin_full_name,
  i.admin_email,
  ai.full_name as invite_name,
  ai.email as invite_email,
  ai.phone,
  ai.claimed
FROM public.institutes i
LEFT JOIN public.admin_invites ai ON ai.institute_id = i.id
WHERE i.institute_code = '23101' OR i.id = '23101';
