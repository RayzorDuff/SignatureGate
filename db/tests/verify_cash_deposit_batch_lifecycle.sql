-- Rollback-only verification for the cash deposit batch lifecycle refinement.
--
-- Targets the canonical schema, including the cash-deposit lifecycle refinement.

\set ON_ERROR_STOP on
BEGIN;

DO $$
BEGIN
  IF to_regprocedure('public.prepare_cash_deposit_batch(uuid,uuid,date,text,text,text)') IS NULL
     OR NOT EXISTS (
       SELECT 1
       FROM information_schema.columns
       WHERE table_schema = 'public'
         AND table_name = 'cash_deposit_batch_items'
         AND column_name = 'removed_at'
     )
  THEN
    RAISE EXCEPTION 'Cash deposit batch lifecycle refinement is not installed.';
  END IF;
END
$$;

DO $$
DECLARE
  v_preparer uuid := public.uuid_generate_v4();
  v_reviewer uuid := public.uuid_generate_v4();
  v_person_a uuid := public.uuid_generate_v4();
  v_person_b uuid := public.uuid_generate_v4();
  v_donor_person_a uuid := public.uuid_generate_v4();
  v_donor_person_b uuid := public.uuid_generate_v4();
  v_member_a uuid := public.uuid_generate_v4();
  v_member_b uuid := public.uuid_generate_v4();
  v_contributor_a uuid;
  v_contributor_b uuid;
  v_donation_a uuid := public.uuid_generate_v4();
  v_donation_b uuid := public.uuid_generate_v4();
  v_donation_c uuid := public.uuid_generate_v4();
  v_batch public.cash_deposit_batches%ROWTYPE;
  v_second_batch public.cash_deposit_batches%ROWTYPE;
  v_item public.cash_deposit_batch_items%ROWTYPE;
  v_count integer;
BEGIN
  INSERT INTO public.people (person_id, display_name, first_name, last_name)
  VALUES
    (v_person_a, 'Deposit Lifecycle Preparer', 'Deposit', 'Preparer'),
    (v_person_b, 'Deposit Lifecycle Reviewer', 'Deposit', 'Reviewer'),
    (v_donor_person_a, 'Deposit Lifecycle Donor A', 'Deposit', 'Donor A'),
    (v_donor_person_b, 'Deposit Lifecycle Donor B', 'Deposit', 'Donor B');

  INSERT INTO public.members (
    member_id, person_id, email, status,
    is_facilitator, is_donations_reviewer
  )
  VALUES
    (v_preparer, v_person_a, 'deposit-lifecycle-preparer@example.invalid',
     'active', true, false),
    (v_reviewer, v_person_b, 'deposit-lifecycle-reviewer@example.invalid',
     'active', true, true),
    (v_member_a, v_donor_person_a, 'deposit-lifecycle-donor-a@example.invalid',
     'active', false, false),
    (v_member_b, v_donor_person_b, 'deposit-lifecycle-donor-b@example.invalid',
     'active', false, false);

  v_contributor_a := public.ensure_member_contributor(v_member_a);
  v_contributor_b := public.ensure_member_contributor(v_member_b);

  INSERT INTO public.donations (
    donation_id, member_id, contributor_id, donor_kind, provider,
    amount_cents, currency, donated_at, status, facilitator_id
  )
  VALUES
    (v_donation_a, v_member_a, v_contributor_a, 'identified', 'cash',
     12500, 'USD', now(), 'verified', v_preparer),
    (v_donation_b, v_member_b, v_contributor_b, 'identified', 'cash',
     7500, 'USD', now(), 'verified', v_preparer),
    (v_donation_c, v_member_a, v_contributor_a, 'identified', 'cash',
     3000, 'USD', now(), 'verified', v_preparer);

  SELECT * INTO v_batch
  FROM public.create_cash_deposit_batch(
    v_preparer, CURRENT_DATE, NULL, 'lifecycle smoke test'
  );

  BEGIN
    PERFORM public.confirm_cash_deposit_batch(
      v_batch.deposit_batch_id, v_reviewer, 12500,
      CURRENT_DATE, 'LIFECYCLE-001', NULL
    );
    RAISE EXCEPTION 'Draft cash deposit batch was confirmable.';
  EXCEPTION WHEN OTHERS THEN
    IF position('not prepared' IN SQLERRM) = 0 THEN
      RAISE;
    END IF;
  END;

  PERFORM public.add_cash_deposit_item(
    v_batch.deposit_batch_id, v_donation_a, v_preparer
  );
  PERFORM public.add_cash_deposit_item(
    v_batch.deposit_batch_id, v_donation_b, v_preparer
  );

  SELECT * INTO v_batch
  FROM public.prepare_cash_deposit_batch(
    v_batch.deposit_batch_id,
    v_preparer,
    CURRENT_DATE,
    'LIFECYCLE-001',
    'SignatureGate Operating Account',
    'prepared lifecycle smoke test'
  );

  IF v_batch.status <> 'prepared'
     OR v_batch.prepared_by <> v_preparer
     OR v_batch.prepared_at IS NULL
     OR v_batch.destination_bank_account <> 'SignatureGate Operating Account'
     OR v_batch.expected_amount_cents <> 20000
  THEN
    RAISE EXCEPTION 'Prepared batch fields are incorrect.';
  END IF;

  BEGIN
    PERFORM public.add_cash_deposit_item(
      v_batch.deposit_batch_id, public.uuid_generate_v4(), v_preparer
    );
    RAISE EXCEPTION 'Prepared batch accepted a new item.';
  EXCEPTION WHEN OTHERS THEN
    IF position('not draft' IN SQLERRM) = 0 THEN
      RAISE;
    END IF;
  END;

  SELECT * INTO v_batch
  FROM public.create_cash_deposit_batch(
    v_preparer, CURRENT_DATE, NULL, NULL
  );

  PERFORM public.add_cash_deposit_item(
    v_batch.deposit_batch_id, v_donation_c, v_preparer
  );

  PERFORM public.remove_cash_deposit_item(
    v_batch.deposit_batch_id, v_donation_c, v_preparer, 'remove and re-add test'
  );

  SELECT count(*) INTO v_count
  FROM public.cash_deposit_batch_items
  WHERE deposit_batch_id = v_batch.deposit_batch_id
    AND donation_id = v_donation_c
    AND removed_at IS NOT NULL
    AND removed_by = v_preparer
    AND removal_reason = 'remove and re-add test';

  IF v_count <> 1 THEN
    RAISE EXCEPTION 'Removed batch item history was not preserved.';
  END IF;

  SELECT * INTO v_item
  FROM public.add_cash_deposit_item(
    v_batch.deposit_batch_id, v_donation_c, v_preparer
  );

  IF v_item.removed_at IS NOT NULL THEN
    RAISE EXCEPTION 'Re-added batch item is still marked removed.';
  END IF;

  SELECT count(*) INTO v_count
  FROM public.cash_deposit_batch_items
  WHERE deposit_batch_id = v_batch.deposit_batch_id
    AND donation_id = v_donation_c;

  IF v_count <> 2 THEN
    RAISE EXCEPTION 'Expected preserved removal plus active re-add history.';
  END IF;

  -- An active donation cannot be assigned to a second batch concurrently.
  SELECT * INTO v_second_batch
  FROM public.create_cash_deposit_batch(
    v_preparer, CURRENT_DATE, NULL, NULL
  );

  BEGIN
    PERFORM public.add_cash_deposit_item(
      v_second_batch.deposit_batch_id, v_donation_c, v_preparer
    );
    RAISE EXCEPTION 'Donation was assigned to a second active batch.';
  EXCEPTION WHEN OTHERS THEN
    IF position('already assigned' IN SQLERRM) = 0 THEN
      RAISE;
    END IF;
  END;

  PERFORM public.cancel_cash_deposit_batch(
    v_batch.deposit_batch_id, v_preparer, 'cancel prepared deposit test'
  );

  SELECT count(*) INTO v_count
  FROM public.cash_deposit_batch_items
  WHERE deposit_batch_id = v_batch.deposit_batch_id
    AND removed_at IS NOT NULL;

  IF v_count <> 2 THEN
    RAISE EXCEPTION 'Cancellation did not preserve and release active item history.';
  END IF;

  IF (SELECT count(*) FROM public.cash_on_hand_donations()
      WHERE donation_id = v_donation_c) <> 1
  THEN
    RAISE EXCEPTION 'Cancelled batch did not return donation to Cash on Hand.';
  END IF;

  -- A prepared batch may also be cancelled, preserving its active item history.
  SELECT * INTO v_batch
  FROM public.create_cash_deposit_batch(
    v_preparer, CURRENT_DATE, NULL, NULL
  );

  PERFORM public.add_cash_deposit_item(
    v_batch.deposit_batch_id, v_donation_c, v_preparer
  );

  SELECT * INTO v_batch
  FROM public.prepare_cash_deposit_batch(
    v_batch.deposit_batch_id,
    v_preparer,
    CURRENT_DATE,
    'LIFECYCLE-CANCEL-001',
    'SignatureGate Operating Account',
    'prepared cancellation smoke test'
  );

  IF v_batch.status <> 'prepared' THEN
    RAISE EXCEPTION 'Expected batch to be prepared before cancellation.';
  END IF;

  PERFORM public.cancel_cash_deposit_batch(
    v_batch.deposit_batch_id, v_preparer, 'cancel prepared batch test'
  );

  IF (SELECT status
      FROM public.cash_deposit_batches
      WHERE deposit_batch_id = v_batch.deposit_batch_id) <> 'cancelled'
  THEN
    RAISE EXCEPTION 'Prepared batch did not transition to cancelled.';
  END IF;

  SELECT count(*) INTO v_count
  FROM public.cash_deposit_batch_items
  WHERE deposit_batch_id = v_batch.deposit_batch_id
    AND donation_id = v_donation_c
    AND removed_at IS NOT NULL
    AND removal_reason = 'cancel prepared batch test';

  IF v_count <> 1 THEN
    RAISE EXCEPTION 'Prepared-batch cancellation did not preserve item history.';
  END IF;

  IF (SELECT count(*) FROM public.cash_on_hand_donations()
      WHERE donation_id = v_donation_c) <> 1
  THEN
    RAISE EXCEPTION 'Prepared-batch cancellation did not return donation to Cash on Hand.';
  END IF;

  SELECT * INTO v_batch
  FROM public.create_cash_deposit_batch(
    v_preparer, CURRENT_DATE, NULL, NULL
  );

  PERFORM public.add_cash_deposit_item(
    v_batch.deposit_batch_id, v_donation_c, v_preparer
  );

  BEGIN
    PERFORM public.prepare_cash_deposit_batch(
      v_batch.deposit_batch_id,
      v_preparer,
      CURRENT_DATE,
      'LIFECYCLE-002',
      NULL,
      NULL
    );
    RAISE EXCEPTION 'Batch was prepared without a destination bank account.';
  EXCEPTION WHEN OTHERS THEN
    IF position('destination bank account' IN SQLERRM) = 0 THEN
      RAISE;
    END IF;
  END;

  PERFORM public.prepare_cash_deposit_batch(
    v_batch.deposit_batch_id,
    v_preparer,
    CURRENT_DATE,
    'LIFECYCLE-002',
    'SignatureGate Operating Account',
    NULL
  );

  SELECT * INTO v_batch
  FROM public.confirm_cash_deposit_batch(
    v_batch.deposit_batch_id,
    v_reviewer,
    3000,
    CURRENT_DATE,
    'LIFECYCLE-002',
    NULL
  );

  IF v_batch.status <> 'confirmed'
     OR v_batch.actual_amount_cents <> 3000
     OR v_batch.verifier_id <> v_reviewer
  THEN
    RAISE EXCEPTION 'Confirmed lifecycle batch fields are incorrect.';
  END IF;

  BEGIN
    UPDATE public.cash_deposit_batch_items
    SET removal_reason = 'illegal mutation'
    WHERE deposit_batch_item_id = (
      SELECT deposit_batch_item_id
      FROM public.cash_deposit_batch_items
      WHERE deposit_batch_id = v_batch.deposit_batch_id
        AND removed_at IS NULL
    );
    RAISE EXCEPTION 'Confirmed batch item was mutable.';
  EXCEPTION WHEN OTHERS THEN
    IF position('immutable' IN SQLERRM) = 0 THEN
      RAISE;
    END IF;
  END;
END
$$;

ROLLBACK;

SELECT 'Cash deposit batch lifecycle smoke test passed.' AS result;
