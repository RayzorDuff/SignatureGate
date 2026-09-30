-- Rollback-only verification for the cash deposit batch tally.
\set ON_ERROR_STOP on
BEGIN;

DO $$
DECLARE
  v_preparer uuid := public.uuid_generate_v4();
  v_person uuid := public.uuid_generate_v4();
  v_member uuid := public.uuid_generate_v4();
  v_contributor uuid;
  v_donation_a uuid := public.uuid_generate_v4();
  v_donation_b uuid := public.uuid_generate_v4();
  v_batch public.cash_deposit_batches%ROWTYPE;
  v_item_count integer;
  v_total integer;
BEGIN
  INSERT INTO public.people (person_id, display_name, first_name, last_name)
  VALUES (v_person, 'Tally Test', 'Tally', 'Test');

  INSERT INTO public.members (
    member_id, person_id, email, status, is_facilitator
  )
  VALUES (
    v_member, v_person, 'cash-deposit-tally@example.invalid',
    'active', true
  );

  v_contributor := public.ensure_member_contributor(v_member);

  INSERT INTO public.donations (
    donation_id, member_id, contributor_id, donor_kind, provider,
    amount_cents, currency, donated_at, status, facilitator_id
  )
  VALUES
    (v_donation_a, v_member, v_contributor, 'identified', 'cash',
     4200, 'USD', now(), 'verified', v_preparer),
    (v_donation_b, NULL, NULL, 'anonymous', 'cash',
     1800, 'USD', now(), 'verified', v_preparer);

  SELECT * INTO v_batch
  FROM public.create_cash_deposit_batch(
    v_preparer, CURRENT_DATE, 'TALLY-001', NULL
  );

  PERFORM public.add_cash_deposit_item(
    v_batch.deposit_batch_id, v_donation_a, v_preparer
  );
  PERFORM public.add_cash_deposit_item(
    v_batch.deposit_batch_id, v_donation_b, v_preparer
  );

  SELECT
    max(item_count),
    max(item_total_cents)
  INTO v_item_count, v_total
  FROM public.cash_deposit_batch_tally
  WHERE deposit_batch_id = v_batch.deposit_batch_id;

  IF v_item_count <> 2 OR v_total <> 6000 THEN
    RAISE EXCEPTION
      'Batch tally expected 2 items / 6000 cents; got % / %.',
      v_item_count, v_total;
  END IF;

  IF (
    SELECT count(*)
    FROM public.cash_deposit_batch_tally
    WHERE deposit_batch_id = v_batch.deposit_batch_id
      AND donor_kind = 'anonymous'
      AND member_id IS NULL
      AND contributor_id IS NULL
  ) <> 1 THEN
    RAISE EXCEPTION 'Anonymous tally row did not preserve anonymous identity.';
  END IF;

  PERFORM public.remove_cash_deposit_item(
    v_batch.deposit_batch_id, v_donation_a, v_preparer
  );

  SELECT
    max(item_count),
    max(item_total_cents)
  INTO v_item_count, v_total
  FROM public.cash_deposit_batch_tally
  WHERE deposit_batch_id = v_batch.deposit_batch_id;

  IF v_item_count <> 1 OR v_total <> 1800 THEN
    RAISE EXCEPTION
      'Active tally after removal expected 1 item / 1800 cents; got % / %.',
      v_item_count, v_total;
  END IF;

  RAISE NOTICE 'Cash deposit batch tally checks passed; rolling back synthetic records.';
END $$;

ROLLBACK;
