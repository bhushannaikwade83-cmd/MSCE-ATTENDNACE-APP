-- Clear all pending admin/website registrations for a fresh app
-- This deletes all rows from admin_invites table

BEGIN;

-- Delete all pending registrations
DELETE FROM public.admin_invites;

-- Verify all are deleted
SELECT COUNT(*) as remaining_pending_registrations
FROM public.admin_invites;

COMMIT;

-- Result should show: remaining_pending_registrations = 0
