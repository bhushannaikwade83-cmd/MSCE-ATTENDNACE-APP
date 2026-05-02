-- Check what columns exist in admin_invites table
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'admin_invites'
ORDER BY ordinal_position;
