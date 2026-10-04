-- Restore an excluded cash donation to Cash on Hand.
-- The original exclusion record is removed only after the donation is
-- validated and any active deposit-batch assignment is ruled out.

CREATE OR REPLACE FUNCTION public.revive_cash_donation_from_deposit(
  p_donation_id uuid,
  p_actor_id uuid
)
RETURNS public.cash_deposit_donation_exclusions
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $revive_cash_donation$
DECLARE
  v_exclusion public.cash_deposit_donation_exclusions%ROWTYPE;
  v_provider text;
  v_status text;
  v_donor_kind text;
  v_amount_cents integer;
BEGIN
  PERFORM public.assert_cash_deposit_verifier(p_actor_id);

  SELECT provider, status, donor_kind, amount_cents
  INTO v_provider, v_status, v_donor_kind, v_amount_cents
  FROM public.donations
  WHERE donation_id = p_donation_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Donation % was not found.', p_donation_id;
  END IF;

  IF v_provider <> 'cash'
     OR v_status <> 'verified'
     OR v_donor_kind NOT IN ('identified', 'anonymous')
     OR v_amount_cents IS NULL
     OR v_amount_cents <= 0
  THEN
    RAISE EXCEPTION
      'Donation % is not a verified, positive cash donation eligible for reconciliation disposition.',
      p_donation_id;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.cash_deposit_batch_items i
    WHERE i.donation_id = p_donation_id AND i.removed_at IS NULL
  ) THEN
    RAISE EXCEPTION
      'Donation % is already assigned to an active deposit batch.', p_donation_id;
  END IF;

  DELETE FROM public.cash_deposit_donation_exclusions
  WHERE donation_id = p_donation_id
  RETURNING * INTO v_exclusion;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Donation % is not currently excluded from deposit reconciliation.', p_donation_id;
  END IF;

  INSERT INTO public.audit_log (actor, action, entity_type, entity_id, details)
  VALUES (
    public.cash_deposit_actor_email(p_actor_id),
    'cash_donation.deposit_reconciliation_revived',
    'donation',
    p_donation_id::text,
    jsonb_build_object(
      'exclusion_id', v_exclusion.exclusion_id,
      'excluded_at', v_exclusion.excluded_at,
      'excluded_by', v_exclusion.excluded_by,
      'reason', v_exclusion.reason,
      'notes', v_exclusion.notes
    )
  );

  RETURN v_exclusion;
END;
$revive_cash_donation$;
