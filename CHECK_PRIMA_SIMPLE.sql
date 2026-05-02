-- Simple check for Prima email conflicts

-- 1. Check profiles table
SELECT 'profiles' as source, COUNT(*) as count
FROM public.profiles
WHERE email = 'primacomputer@gmail.com';

-- 2. Check admin_invites table
SELECT 'admin_invites' as source, COUNT(*) as count
FROM public.admin_invites
WHERE email = 'primacomputer@gmail.com';

-- 3. Show all records for Prima email
SELECT 'profiles' as table_name, id, email, created_at
FROM public.profiles
WHERE email = 'primacomputer@gmail.com'
UNION ALL
SELECT 'admin_invites' as table_name, id::text, email, created_at
FROM public.admin_invites
WHERE email = 'primacomputer@gmail.com';

-- 4. Check institute 23101 admin_invites
SELECT ai.id, ai.institute_id, ai.full_name, ai.email, ai.phone, ai.claimed
FROM public.admin_invites ai
JOIN public.institutes i ON ai.institute_id = i.id
WHERE i.institute_code = '23101' OR i.id = '23101';
