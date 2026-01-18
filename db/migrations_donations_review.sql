-- SignatureGate migration: donation review workflow (cash + provider imports)
--
-- Goal:
-- - Show donation history on member profile
-- - Allow facilitators to record cash donations (pending_review)
-- - Allow reviewers to verify/approve (verified) or reject
--
-- Notes:
-- - Givebutter (provider imports) can be inserted as 'imported' or 'verified'
--   depending on how strict you want to be.

BEGIN;

	ALTER TABLE public.donations
	  ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'imported',
	  ADD COLUMN IF NOT EXISTS facilitator_id uuid REFERENCES public.members(member_id),
	  ADD COLUMN IF NOT EXISTS reviewer_id uuid REFERENCES public.members(member_id),
	  ADD COLUMN IF NOT EXISTS reviewed_at timestamptz,
	  ADD COLUMN IF NOT EXISTS review_notes text;

	-- Common status values:
--   imported | pending_review | verified | rejected

CREATE INDEX IF NOT EXISTS idx_donations_member_date
  ON public.donations (member_id, donated_at DESC NULLS LAST, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_donations_pending_review
  ON public.donations (status, created_at DESC)
  WHERE status = 'pending_review';

COMMIT;

