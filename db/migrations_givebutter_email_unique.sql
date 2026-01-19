-- SignatureGate migration: enforce unique member emails (case-insensitive)
--
-- Why:
-- - Givebutter (and other provider) donation webhooks match members by email.
-- - A case-insensitive uniqueness constraint prevents duplicate member rows and
--   makes webhook ingestion deterministic.
--
-- NOTE:
-- This will FAIL if you already have duplicate emails differing only by case,
-- or multiple members sharing the same email. Before applying, you can find
-- duplicates with:
--
--   SELECT lower(email) AS email_lc, COUNT(*)
--   FROM public.members
--   WHERE email IS NOT NULL AND btrim(email) <> ''
--   GROUP BY lower(email)
--   HAVING COUNT(*) > 1;

BEGIN;

	-- Unique, case-insensitive email for non-empty emails.
-- Using an index instead of a UNIQUE constraint keeps it simple and fast.
CREATE UNIQUE INDEX IF NOT EXISTS uq_members_email_lower
  ON public.members (lower(btrim(email)))
  WHERE email IS NOT NULL AND btrim(email) <> '';

COMMIT;

