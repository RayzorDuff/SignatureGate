-- SignatureGate issue #7: cancel pending Documenso agreements
-- Adds cancellation metadata used by Appsmith qMemberAgreements and the
-- SignatureGate - Documenso - Cancel Agreement n8n workflow.

BEGIN;

ALTER TABLE public.member_agreements
  ADD COLUMN IF NOT EXISTS canceled_at timestamptz,
  ADD COLUMN IF NOT EXISTS canceled_by uuid,
  ADD COLUMN IF NOT EXISTS cancel_reason text,
  ADD COLUMN IF NOT EXISTS documenso_cancel_response jsonb;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'member_agreements_canceled_by_fkey'
      AND conrelid = 'public.member_agreements'::regclass
  ) THEN
    ALTER TABLE public.member_agreements
      ADD CONSTRAINT member_agreements_canceled_by_fkey
      FOREIGN KEY (canceled_by)
      REFERENCES public.members(member_id)
      ON DELETE SET NULL;
  END IF;
END $$;

-- If an existing status CHECK constraint predates the electronic cancellation
-- workflow and does not include 'canceled', replace it with the current
-- SignatureGate agreement status set.
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT c.conname, pg_get_constraintdef(c.oid) AS constraint_def
    FROM pg_constraint c
    JOIN pg_class t ON t.oid = c.conrelid
    JOIN pg_namespace n ON n.oid = t.relnamespace
    WHERE n.nspname = 'public'
      AND t.relname = 'member_agreements'
      AND c.contype = 'c'
      AND pg_get_constraintdef(c.oid) ILIKE '%status%'
  LOOP
    IF r.constraint_def NOT ILIKE '%canceled%' THEN
      EXECUTE format('ALTER TABLE public.member_agreements DROP CONSTRAINT %I', r.conname);
    END IF;
  END LOOP;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint c
    JOIN pg_class t ON t.oid = c.conrelid
    JOIN pg_namespace n ON n.oid = t.relnamespace
    WHERE n.nspname = 'public'
      AND t.relname = 'member_agreements'
      AND c.contype = 'c'
      AND pg_get_constraintdef(c.oid) ILIKE '%status%'
  ) THEN
    ALTER TABLE public.member_agreements
      ADD CONSTRAINT member_agreements_status_chk
      CHECK (
        status IS NULL OR status IN (
          'pending_review',
          'pending_email_send',
          'pending_signature',
          'signed',
          'rejected',
          'canceled'
        )
      ) NOT VALID;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_member_agreements_documenso_pending_cancel
  ON public.member_agreements (member_agreement_id, documenso_document_id)
  WHERE signature_method = 'documenso'
    AND status = 'pending_signature';

CREATE INDEX IF NOT EXISTS idx_member_agreements_canceled_at
  ON public.member_agreements (canceled_at)
  WHERE canceled_at IS NOT NULL;

COMMENT ON COLUMN public.member_agreements.canceled_at IS
  'Timestamp when a pending Documenso agreement was canceled before signing.';
COMMENT ON COLUMN public.member_agreements.canceled_by IS
  'Member/facilitator who initiated cancellation of a pending Documenso agreement.';
COMMENT ON COLUMN public.member_agreements.cancel_reason IS
  'Review/Cancel Notes supplied when canceling a pending Documenso agreement.';
COMMENT ON COLUMN public.member_agreements.documenso_cancel_response IS
  'Raw/minimal response payload returned by the Documenso cancel/delete envelope API.';

COMMIT;
