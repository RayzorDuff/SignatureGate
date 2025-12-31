-- SignatureGate migration: facilitator + paper-review workflow
-- Apply after baseline schema.sql

BEGIN;

-- 1) Member roles
ALTER TABLE members
  ADD COLUMN IF NOT EXISTS is_facilitator boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS is_document_reviewer boolean NOT NULL DEFAULT false;

-- 2) Agreement multi-signer + review workflow
ALTER TABLE member_agreements
  ADD COLUMN IF NOT EXISTS facilitator_id uuid REFERENCES members(member_id),
  ADD COLUMN IF NOT EXISTS reviewer_id uuid REFERENCES members(member_id),
  ADD COLUMN IF NOT EXISTS member_signed_at timestamptz,
  ADD COLUMN IF NOT EXISTS facilitator_signed_at timestamptz,
  ADD COLUMN IF NOT EXISTS opensign_document_id text,
  ADD COLUMN IF NOT EXISTS evidence jsonb NOT NULL DEFAULT '[]'::jsonb;

-- Keep old evidence_url column (if present) for backward compat; optional backfill
-- UPDATE member_agreements SET evidence = jsonb_build_array(jsonb_build_object('type','url','url',evidence_url))
-- WHERE evidence_url IS NOT NULL AND evidence_url <> '' AND evidence = '[]'::jsonb;

-- 3) Status expansion: pending_signature vs pending_review
-- If you want stricter enforcement, convert status to an enum later.
-- For now, just document intended values:
--   pending_signature | pending_review | signed | rejected | revoked

-- 4) Helpful indexes
CREATE INDEX IF NOT EXISTS idx_members_facilitator_active
  ON members (is_facilitator, status);

CREATE INDEX IF NOT EXISTS idx_member_agreements_member
  ON member_agreements (member_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_member_agreements_facilitator
  ON member_agreements (facilitator_id, created_at DESC);

COMMIT;
