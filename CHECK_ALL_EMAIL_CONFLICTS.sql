-- Find emails that exist in BOTH profiles AND admin_invites (causing conflicts)

SELECT
  ai.email,
  i.institute_code,
  i.name as institute_name,
  ai.full_name as admin_name,
  ai.phone,
  ai.claimed,
  p.id as profile_id,
  p.created_at as profile_created_at,
  ai.created_at as invite_created_at
FROM public.admin_invites ai
JOIN public.institutes i ON ai.institute_id = i.id
JOIN public.profiles p ON ai.email = p.email
ORDER BY ai.email, i.institute_code;

-- Count total conflicts
SELECT COUNT(DISTINCT ai.email) as total_conflict_emails
FROM public.admin_invites ai
JOIN public.profiles p ON ai.email = p.email;

-- Show summary by institute
SELECT
  i.institute_code,
  i.name,
  COUNT(DISTINCT ai.email) as conflicting_emails
FROM public.admin_invites ai
JOIN public.institutes i ON ai.institute_id = i.id
JOIN public.profiles p ON ai.email = p.email
GROUP BY i.id, i.institute_code, i.name
ORDER BY conflicting_emails DESC;
