-- SignatureGate v1.0.4: Documenso expiration support and canonical
-- agreement cancellation spelling.
--
-- Addresses #11 and supports #13:
-- - persist Documenso expired webhooks as member_agreements.status = 'expired';
-- - keep an explicit expired_at timestamp;
-- - normalize legacy British-spelled 'cancelled' rows to the canonical
--   SignatureGate status value 'canceled'.

BEGIN;

ALTER TABLE public.member_agreements
  ADD COLUMN IF NOT EXISTS expired_at timestamptz;

UPDATE public.member_agreements
SET
  status = 'canceled',
  updated_at = now()
WHERE status = 'cancelled';

-- Replace older status CHECK constraints with the v1.0.4 status set.
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT c.conname
    FROM pg_constraint c
    JOIN pg_class t ON t.oid = c.conrelid
    JOIN pg_namespace n ON n.oid = t.relnamespace
    WHERE n.nspname = 'public'
      AND t.relname = 'member_agreements'
      AND c.contype = 'c'
      AND pg_get_constraintdef(c.oid) ILIKE '%status%'
  LOOP
    EXECUTE format('ALTER TABLE public.member_agreements DROP CONSTRAINT %I', r.conname);
  END LOOP;
END $$;

ALTER TABLE public.member_agreements
  ADD CONSTRAINT member_agreements_status_chk
  CHECK (
    status IS NULL OR status IN (
      'pending_review',
      'pending_email_send',
      'pending_signature',
      'signed',
      'rejected',
      'revoked',
      'canceled',
      'cancelled',
      'expired'
    )
  ) NOT VALID;

CREATE INDEX IF NOT EXISTS idx_member_agreements_expired_at
  ON public.member_agreements (expired_at)
  WHERE expired_at IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_member_agreements_documenso_expirable
  ON public.member_agreements (status, documenso_external_id, documenso_document_id)
  WHERE signature_method = 'documenso'
    AND status IN ('pending_email_send', 'pending_signature');

COMMENT ON COLUMN public.member_agreements.expired_at IS
  'Timestamp when Documenso reported that the agreement expired before signing.';

COMMIT;
