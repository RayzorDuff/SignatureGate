-- SignatureGate Issue #17: anonymous cash donation identity and review.
--
-- This migration implements the anonymous-donation portion of Issue #17.
-- Deposit batches, ERP posting, and bank reconciliation remain separate
-- follow-up slices.
--
-- Donor identity states:
--   member     - deliberately linked to a real member
--   anonymous  - deliberately anonymous cash; never linked to a fake member
--   unresolved - provider import awaiting identity review

\set ON_ERROR_STOP on

BEGIN;

LOCK TABLE public.donations IN SHARE ROW EXCLUSIVE MODE;

ALTER TABLE public.donations
  ADD COLUMN IF NOT EXISTS donor_kind text;

-- An old cash row without a member cannot safely be assumed anonymous. Stop
-- and require review rather than silently changing its donor identity.
DO $$
DECLARE
  v_count integer;
BEGIN
  SELECT count(*)
  INTO v_count
  FROM public.donations
  WHERE provider = 'cash'
    AND member_id IS NULL
    AND donor_kind IS NULL;

  IF v_count > 0 THEN
    RAISE EXCEPTION
      'Issue #17 migration stopped: % pre-existing cash donation(s) have no member. Review them before classifying donor identity.',
      v_count;
  END IF;
END;
$$;

UPDATE public.donations
SET donor_kind = CASE
  WHEN member_id IS NOT NULL THEN 'member'
  ELSE 'unresolved'
END
WHERE donor_kind IS NULL;

ALTER TABLE public.donations
  ALTER COLUMN donor_kind SET NOT NULL;

ALTER TABLE public.donations
  DROP CONSTRAINT IF EXISTS donations_donor_kind_check,
  DROP CONSTRAINT IF EXISTS donations_donor_identity_check,
  DROP CONSTRAINT IF EXISTS donations_donor_kind_provider_check;

ALTER TABLE public.donations
  ADD CONSTRAINT donations_donor_kind_check
    CHECK (donor_kind IN ('member', 'anonymous', 'unresolved')),
  ADD CONSTRAINT donations_donor_identity_check
    CHECK (
      (donor_kind = 'member' AND member_id IS NOT NULL)
      OR
      (donor_kind IN ('anonymous', 'unresolved') AND member_id IS NULL)
    ),
  ADD CONSTRAINT donations_donor_kind_provider_check
    CHECK (
      (donor_kind <> 'anonymous' OR provider = 'cash')
      AND
      (donor_kind <> 'unresolved' OR provider <> 'cash')
    );

CREATE INDEX IF NOT EXISTS idx_donations_donor_kind_status
  ON public.donations (donor_kind, status, donated_at DESC NULLS LAST);

CREATE OR REPLACE FUNCTION public.donation_set_donor_kind()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.donor_kind IS NULL THEN
    IF NEW.member_id IS NOT NULL THEN
      NEW.donor_kind := 'member';
    ELSIF NEW.provider = 'cash' THEN
      RAISE EXCEPTION
        'Cash donations without a member must explicitly use donor_kind anonymous.';
    ELSE
      NEW.donor_kind := 'unresolved';
    END IF;
  ELSIF TG_OP = 'UPDATE' THEN
    IF OLD.donor_kind = 'unresolved'
      AND OLD.member_id IS NULL
      AND NEW.member_id IS NOT NULL
      AND NEW.provider <> 'cash'
    THEN
      -- Preserve compatibility with an in-flight provider-review action while
      -- still preventing anonymous cash from being silently reclassified.
      NEW.donor_kind := 'member';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_donations_set_donor_kind
  ON public.donations;
CREATE TRIGGER trg_donations_set_donor_kind
BEFORE INSERT OR UPDATE OF member_id, donor_kind, provider
ON public.donations
FOR EACH ROW
EXECUTE FUNCTION public.donation_set_donor_kind();

CREATE OR REPLACE FUNCTION public.record_cash_donation(
  p_member_id uuid,
  p_is_anonymous boolean,
  p_amount_cents integer,
  p_donated_at timestamptz,
  p_notes text,
  p_facilitator_id uuid
)
RETURNS public.donations
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_result public.donations%ROWTYPE;
BEGIN
  IF p_facilitator_id IS NULL OR NOT EXISTS (
    SELECT 1
    FROM public.members m
    WHERE m.member_id = p_facilitator_id
      AND m.status = 'active'
      AND m.is_facilitator IS TRUE
  ) THEN
    RAISE EXCEPTION 'An active facilitator is required to record a cash donation.';
  END IF;

  IF p_amount_cents IS NULL OR p_amount_cents <= 0 THEN
    RAISE EXCEPTION 'Cash donation amount must be positive.';
  END IF;

  IF COALESCE(p_is_anonymous, false) THEN
    IF p_member_id IS NOT NULL THEN
      RAISE EXCEPTION 'Anonymous cash donations cannot reference a member.';
    END IF;
  ELSE
    IF p_member_id IS NULL THEN
      RAISE EXCEPTION 'A member is required unless the cash donation is explicitly anonymous.';
    END IF;

    IF NOT EXISTS (
      SELECT 1
      FROM public.members m
      WHERE m.member_id = p_member_id
        AND m.status = 'active'
    ) THEN
      RAISE EXCEPTION 'The selected member is not active.';
    END IF;
  END IF;

  INSERT INTO public.donations (
    member_id,
    donor_kind,
    provider,
    amount_cents,
    currency,
    donated_at,
    notes,
    status,
    facilitator_id
  )
  VALUES (
    CASE WHEN COALESCE(p_is_anonymous, false) THEN NULL ELSE p_member_id END,
    CASE WHEN COALESCE(p_is_anonymous, false) THEN 'anonymous' ELSE 'member' END,
    'cash',
    p_amount_cents,
    'USD',
    COALESCE(p_donated_at, now()),
    NULLIF(btrim(p_notes), ''),
    'pending_review',
    p_facilitator_id
  )
  RETURNING * INTO v_result;

  RETURN v_result;
END;
$$;

CREATE OR REPLACE FUNCTION public.review_pending_donation(
  p_donation_id uuid,
  p_reviewer_id uuid,
  p_new_status text,
  p_review_notes text DEFAULT NULL
)
RETURNS public.donations
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_donation public.donations%ROWTYPE;
BEGIN
  IF p_reviewer_id IS NULL OR NOT EXISTS (
    SELECT 1
    FROM public.members m
    WHERE m.member_id = p_reviewer_id
      AND m.status = 'active'
      AND m.is_facilitator IS TRUE
      AND m.is_donations_reviewer IS TRUE
  ) THEN
    RAISE EXCEPTION 'An active donations reviewer is required.';
  END IF;

  SELECT *
  INTO v_donation
  FROM public.donations d
  WHERE d.donation_id = p_donation_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Donation % was not found.', p_donation_id;
  END IF;

  IF v_donation.status <> 'pending_review' THEN
    RAISE EXCEPTION
      'Donation % is %, not pending_review.',
      p_donation_id,
      v_donation.status;
  END IF;

  IF v_donation.provider = 'cash' THEN
    IF v_donation.donor_kind NOT IN ('member', 'anonymous') THEN
      RAISE EXCEPTION 'Cash donation % has invalid donor identity.', p_donation_id;
    END IF;

    IF v_donation.amount_cents IS NULL OR v_donation.amount_cents <= 0 THEN
      RAISE EXCEPTION 'Cash donation % must have a positive amount.', p_donation_id;
    END IF;

    IF p_new_status IS NULL
      OR p_new_status NOT IN ('verified', 'rejected')
    THEN
      RAISE EXCEPTION 'Cash review status must be verified or rejected.';
    END IF;
  ELSE
    IF v_donation.donor_kind <> 'unresolved'
      OR v_donation.member_id IS NOT NULL
      OR p_new_status IS NULL
      OR p_new_status <> 'ignored'
    THEN
      RAISE EXCEPTION
        'Only unresolved provider donations may be ignored through this action.';
    END IF;
  END IF;

  UPDATE public.donations
  SET
    status = p_new_status,
    reviewer_id = p_reviewer_id,
    reviewed_at = now(),
    review_notes = NULLIF(btrim(p_review_notes), '')
  WHERE donation_id = p_donation_id
  RETURNING * INTO v_donation;

  RETURN v_donation;
END;
$$;

COMMENT ON COLUMN public.donations.donor_kind IS
  'Explicit donor identity: member, deliberately anonymous cash, or unresolved provider import.';

COMMENT ON FUNCTION public.record_cash_donation(
  uuid,
  boolean,
  integer,
  timestamptz,
  text,
  uuid
) IS
  'Records member-linked or deliberately anonymous cash as pending review without creating a synthetic member.';

COMMENT ON FUNCTION public.review_pending_donation(
  uuid,
  uuid,
  text,
  text
) IS
  'Verifies/rejects pending cash or ignores an unresolved provider donation, enforcing donations-reviewer authority.';

COMMIT;

-- Deployment verification: these queries must return zero rows.
SELECT donation_id, member_id, donor_kind, provider
FROM public.donations
WHERE (donor_kind = 'member' AND member_id IS NULL)
   OR (donor_kind IN ('anonymous', 'unresolved') AND member_id IS NOT NULL)
   OR (donor_kind = 'anonymous' AND provider <> 'cash')
   OR (donor_kind = 'unresolved' AND provider = 'cash');
