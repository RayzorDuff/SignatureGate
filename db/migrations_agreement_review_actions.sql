-- SignatureGate migration: explicit reviewer approve/reject actions
--
-- Why: Paper/manual uploads need a reviewer workflow with clear approve/reject,
-- while keeping an audit trail.
--
-- Intended status values in member_agreements.status:
--   pending_signature | pending_review | signed | rejected | revoked
--
-- This migration adds fields that make reviewer actions explicit and queryable.

BEGIN;

	ALTER TABLE public.member_agreements
	  ADD COLUMN IF NOT EXISTS reviewer_id uuid REFERENCES public.members(member_id),
	  ADD COLUMN IF NOT EXISTS reviewed_at timestamptz,
	  ADD COLUMN IF NOT EXISTS review_notes text;

	-- Backward compat: if older columns exist, keep them populated.
-- verified_by / verified_at appear in schema.sql; they are retained.

-- Helpful index for the review queue
CREATE INDEX IF NOT EXISTS idx_member_agreements_pending_review
  ON public.member_agreements (status, created_at DESC)
  WHERE status = 'pending_review';

COMMIT;

