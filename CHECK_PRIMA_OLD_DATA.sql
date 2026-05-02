-- Check if Prima email still has password/PIN in database

-- Check profiles table
SELECT 'profiles' as location, id, email, created_at
FROM public.profiles
WHERE email = 'primacomputer@gmail.com';

-- Check admin_setup table (if exists)
SELECT 'admin_setup' as location, id, email, pin_set, created_at
FROM public.admin_setup
WHERE email = 'primacomputer@gmail.com'
UNION ALL

-- Check institute_admin_setup (if exists)
SELECT 'institute_admin_setup' as location, id, admin_email as email, pin_set, created_at
FROM public.institute_admin_setup
WHERE admin_email = 'primacomputer@gmail.com'
UNION ALL

-- Check for any auth.users record
SELECT 'auth.users' as location, id::text, email, created_at
FROM auth.users
WHERE email = 'primacomputer@gmail.com'
UNION ALL

-- Check admin_invites
SELECT 'admin_invites' as location, id::text, email, created_at
FROM public.admin_invites
WHERE email = 'primacomputer@gmail.com';
