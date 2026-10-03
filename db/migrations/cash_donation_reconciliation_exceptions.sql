-- Cash donation reconciliation exceptions.
--
-- Records cash donations that were verified but cannot be reconciled to an
-- actual cash deposit. The donation itself is retained unchanged; an explicit
-- operational exception removes it from Cash on Hand and from deposit-batch
-- eligibility.
--
-- This is intentionally separate from donation status because "not reconciled
-- to a deposit" is an operational/accounting disposition, not evidence that
-- the original donation record was invalid.

\set ON_ERROR_STOP on
BEGIN;

CREATE TABLE IF NOT EXISTS public.cash_deposit_donation_exclusions (
  exclusion_id uuid PRIMARY KEY DEFAULT public.uuid_generate_v4(),
  donation_id uuid NOT NULL
    REFERENCES public.donations(donation_id)
    ON DELETE RESTRICT,
  excluded_at timestamptz NOT NULL DEFAULT now(),
  excluded_by uuid NOT NULL REFERENCES public.members(member_id),
  reason text NOT NULL,
  notes text,
  CONSTRAINT cash_deposit_donation_exclusions_reason_check
    CHECK (NULLIF(btrim(reason), '') IS NOT NULL)
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_cash_deposit_donation_exclusions_active
  ON public.cash_deposit_donation_exclusions (donation_id);

CREATE INDEX IF NOT EXISTS idx_cash_deposit_donation_exclusions_excluded_at
  ON public.cash_deposit_donation_exclusions (excluded_at DESC);

CREATE OR REPLACE FUNCTION public.exclude_cash_donation_from_deposit(
  p_donation_id uuid,
  p_actor_id uuid,
  p_reason text,
  p_notes text DEFAULT NULL
)
RETURNS public.cash_deposit_donation_exclusions
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_exclusion public.cash_deposit_donation_exclusions%ROWTYPE;
BEGIN
  PERFORM public.assert_cash_deposit_verifier(p_actor_id);

  PERFORM 1
  FROM public.donations
  WHERE donation_id = p_donation_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Donation % was not found.', p_donation_id;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.donations
    WHERE donation_id = p_donation_id
      AND provider = 'cash'
      AND status = 'verified'
      AND donor_kind IN ('identified', 'anonymous')
      AND amount_cents IS NOT NULL
      AND amount_cents > 0
  ) THEN
    RAISE EXCEPTION
      'Donation % is not a verified, positive cash donation eligible for reconciliation disposition.',
      p_donation_id;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.cash_deposit_batch_items i
    WHERE i.donation_id = p_donation_id
      AND i.removed_at IS NULL
  ) THEN
    RAISE EXCEPTION
      'Donation % is already assigned to an active deposit batch.',
      p_donation_id;
  END IF;

  IF NULLIF(btrim(p_reason), '') IS NULL THEN
    RAISE EXCEPTION 'A reason is required when excluding a cash donation from deposit reconciliation.';
  END IF;

  INSERT INTO public.cash_deposit_donation_exclusions (
    donation_id,
    excluded_by,
    reason,
    notes
  )
  VALUES (
    p_donation_id,
    p_actor_id,
    btrim(p_reason),
    NULLIF(btrim(p_notes), '')
  )
  RETURNING * INTO v_exclusion;

  INSERT INTO public.audit_log (actor, action, entity_type, entity_id, details)
  VALUES (
    public.cash_deposit_actor_email(p_actor_id),
    'cash_donation.deposit_reconciliation_excluded',
    'donation',
    p_donation_id::text,
    jsonb_build_object(
      'exclusion_id', v_exclusion.exclusion_id,
      'reason', v_exclusion.reason,
      'notes', v_exclusion.notes
    )
  );

  RETURN v_exclusion;
END;
$$;

CREATE OR REPLACE FUNCTION public.prevent_excluded_cash_deposit_item()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.cash_deposit_donation_exclusions e
    WHERE e.donation_id = NEW.donation_id
  ) THEN
    RAISE EXCEPTION
      'Donation % is excluded from cash-deposit reconciliation.',
      NEW.donation_id;
  END IF;

  RETURN NEW;
END;
$;

DROP TRIGGER IF EXISTS trg_cash_deposit_items_exclusion_guard
  ON public.cash_deposit_batch_items;

CREATE TRIGGER trg_cash_deposit_items_exclusion_guard
BEFORE INSERT ON public.cash_deposit_batch_items
FOR EACH ROW
EXECUTE FUNCTION public.prevent_excluded_cash_deposit_item();

CREATE OR REPLACE FUNCTION public.cash_on_hand_donations()
RETURNS TABLE (
  donation_id uuid,
  donated_at timestamptz,
  amount_cents integer,
  currency text,
  donor_kind text,
  member_id uuid,
  contributor_id uuid,
  notes text
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
  SELECT
    d.donation_id,
    d.donated_at,
    d.amount_cents,
    d.currency,
    d.donor_kind,
    d.member_id,
    d.contributor_id,
    d.notes
  FROM public.donations d
  WHERE d.provider = 'cash'
    AND d.status = 'verified'
    AND d.donor_kind IN ('identified', 'anonymous')
    AND d.amount_cents IS NOT NULL
    AND d.amount_cents > 0
    AND NOT EXISTS (
      SELECT 1
      FROM public.cash_deposit_batch_items i
      WHERE i.donation_id = d.donation_id
        AND i.removed_at IS NULL
    )
    AND NOT EXISTS (
      SELECT 1
      FROM public.cash_deposit_donation_exclusions e
      WHERE e.donation_id = d.donation_id
    )
  ORDER BY d.donated_at NULLS LAST, d.created_at, d.donation_id;
$$;

COMMENT ON TABLE public.cash_deposit_donation_exclusions IS
  'Explicit operational/accounting exceptions for verified cash donations that cannot be reconciled to a physical deposit. The underlying donation record is retained unchanged.';

COMMENT ON FUNCTION public.exclude_cash_donation_from_deposit(uuid, uuid, text, text) IS
  'Marks a verified cash donation as excluded from deposit reconciliation. Requires an active donations reviewer and an explicit reason; does not alter the donation record.';

COMMIT;
