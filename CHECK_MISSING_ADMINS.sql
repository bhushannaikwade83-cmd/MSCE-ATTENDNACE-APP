-- Check which institutes are ACTUALLY missing admin details
-- Run this FIRST to see what needs to be imported

-- How many institutes have no admin name?
SELECT COUNT(*) as institutes_missing_admin
FROM public.institutes
WHERE admin_full_name IS NULL OR btrim(admin_full_name) = '';

-- Show examples of institutes with NO admin details
SELECT id, institute_code, name, admin_full_name, admin_email, admin_phone
FROM public.institutes
WHERE admin_full_name IS NULL OR btrim(admin_full_name) = ''
LIMIT 20;

-- Show examples of institutes that HAVE admin details
SELECT id, institute_code, name, admin_full_name, admin_email, admin_phone
FROM public.institutes
WHERE admin_full_name IS NOT NULL AND btrim(admin_full_name) != ''
LIMIT 20;

-- Count how many have admin details
SELECT COUNT(*) as institutes_with_admin
FROM public.institutes
WHERE admin_full_name IS NOT NULL AND btrim(admin_full_name) != '';
