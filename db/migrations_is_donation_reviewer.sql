-- migrations_is_donations_reviewer.sql
-- Purpose: allow separate permissioning for donations review / cash donation intake visibility.

BEGIN;

	ALTER TABLE public.members
	  ADD COLUMN IF NOT EXISTS is_donations_reviewer boolean NOT NULL DEFAULT FALSE;

	COMMENT ON COLUMN public.members.is_donations_reviewer IS
	  'If true, facilitator can view/select all members for donation intake and can verify/review cash donations.';

	-- Optional: helpful partial index if you frequently query reviewer facilitators
CREATE INDEX IF NOT EXISTS idx_members_is_donations_reviewer_true
  ON public.members (member_id)
  WHERE is_donations_reviewer IS TRUE;

COMMIT;

