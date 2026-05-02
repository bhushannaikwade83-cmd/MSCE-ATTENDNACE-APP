-- Check Prima institute email registration status

-- Check if email exists in admin_invites
SELECT 'admin_invites' as table_name, id, institute_id, full_name, email, claimed, created_at
FROM public.admin_invites
WHERE email = 'primacomputer@gmail.com';

-- Check if email exists in profiles (auth users)
SELECT 'profiles' as table_name, id, email, created_at
FROM public.profiles
WHERE email = 'primacomputer@gmail.com';

-- Check Prima institute details
SELECT 'institutes' as table_name, id, institute_code, name, admin_email
FROM public.institutes
WHERE institute_code = '12345' OR id = '12345';

-- Check for any registration records
SELECT 'student_registrations' as table_name, COUNT(*) as count
FROM public.student_registrations
WHERE email = 'primacomputer@gmail.com';
