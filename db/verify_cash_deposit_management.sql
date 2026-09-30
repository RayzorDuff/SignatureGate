-- SignatureGate Issue #17: rollback-only verification for cash deposit backend.
--
-- This script targets the current Issue #19 canonical identity schema. It creates synthetic members/donations and exercises the operational
-- invariants inside one transaction. No test data survives.

\set ON_ERROR_STOP on
BEGIN;

DO $$
BEGIN
  IF to_regprocedure('public.create_cash_deposit_batch(uuid,date,text,text)') IS NULL
     OR to_regprocedure('public.add_cash_deposit_item(uuid,uuid,uuid)') IS NULL
     OR to_regprocedure('public.remove_cash_deposit_item(uuid,uuid,uuid)') IS NULL
     OR to_regprocedure('public.confirm_cash_deposit_batch(uuid,uuid,integer,date,text,text)') IS NULL
     OR to_regprocedure('public.cancel_cash_deposit_batch(uuid,uuid,text)') IS NULL
     OR to_regprocedure('public.cash_on_hand_donations()') IS NULL
     OR to_regclass('public.cash_deposit_batches') IS NULL
  THEN
    RAISE EXCEPTION 'Issue #17 cash deposit backend is not installed.';
  END IF;
END
$$;

DO $$
DECLARE
  v_preparer uuid := public.uuid_generate_v4();
  v_reviewer uuid := public.uuid_generate_v4();
  v_non_reviewer uuid := public.uuid_generate_v4();
  v_member uuid := public.uuid_generate_v4();
  v_preparer_person uuid := public.uuid_generate_v4();
  v_reviewer_person uuid := public.uuid_generate_v4();
  v_non_reviewer_person uuid := public.uuid_generate_v4();
  v_person uuid := public.uuid_generate_v4();
  v_contributor uuid;
  v_donation_a uuid := public.uuid_generate_v4();
  v_donation_b uuid := public.uuid_generate_v4();
  v_batch public.cash_deposit_batches%ROWTYPE;
  v_item public.cash_deposit_batch_items%ROWTYPE;
  v_count integer;
  v_total bigint;
BEGIN
  INSERT INTO public.people (person_id, display_name, first_name, last_name)
  VALUES
    (v_preparer_person, 'Issue17 Preparer', 'Issue17', 'Preparer'),
    (v_reviewer_person, 'Issue17 Reviewer', 'Issue17', 'Reviewer'),
    (v_non_reviewer_person, 'Issue17 Other', 'Issue17', 'Other'),
    (v_person, 'Issue17 Donor', 'Issue17', 'Donor');

  INSERT INTO public.members (
    member_id, person_id, email, status,
    is_facilitator, is_donations_reviewer
  )
  VALUES
    (v_preparer, v_preparer_person, 'issue17-preparer@example.invalid',
     'active', true, false),
    (v_reviewer, v_reviewer_person, 'issue17-reviewer@example.invalid',
     'active', true, true),
    (v_non_reviewer, v_non_reviewer_person, 'issue17-other@example.invalid',
     'active', true, false),
    (v_member, v_person, 'issue17-donor@example.invalid',
     'active', false, false);

  v_contributor := public.ensure_member_contributor(v_member);

  INSERT INTO public.donations (
    donation_id, member_id, contributor_id, donor_kind, provider, amount_cents,
    currency, donated_at, status, facilitator_id
  )
  VALUES
    (v_donation_a, v_member, v_contributor, 'identified', 'cash', 12500, 'USD',
     now(), 'verified', v_preparer),
    (v_donation_b, NULL, NULL, 'anonymous', 'cash', 7500, 'USD',
     now(), 'verified', v_preparer);

  SELECT count(*), COALESCE(sum(amount_cents), 0)
  INTO v_count, v_total
  FROM public.cash_on_hand_donations()
  WHERE donation_id IN (v_donation_a, v_donation_b);

  IF v_count <> 2 OR v_total <> 20000 THEN
    RAISE EXCEPTION
      'Cash on Hand expected 2 donations / 20000 cents; got % / %.',
      v_count, v_total;
  END IF;

  SELECT * INTO v_batch
  FROM public.create_cash_deposit_batch(
    v_preparer, CURRENT_DATE, 'ISSUE17-SMOKE-001', 'rollback-only smoke test'
  );

  SELECT * INTO v_item
  FROM public.add_cash_deposit_item(v_batch.deposit_batch_id, v_donation_a, v_preparer);

  IF v_item.amount_cents <> 12500 THEN
    RAISE EXCEPTION 'Expected donation amount snapshot 12500; got %.', v_item.amount_cents;
  END IF;

  SELECT * INTO v_item
  FROM public.add_cash_deposit_item(v_batch.deposit_batch_id, v_donation_b, v_preparer);

  SELECT expected_amount_cents INTO v_count
  FROM public.cash_deposit_batches
  WHERE deposit_batch_id = v_batch.deposit_batch_id;

  IF v_count <> 20000 THEN
    RAISE EXCEPTION 'Expected batch total 20000; got %.', v_count;
  END IF;

  BEGIN
    PERFORM public.add_cash_deposit_item(
      v_batch.deposit_batch_id, v_donation_a, v_preparer
    );
    RAISE EXCEPTION 'Duplicate donation assignment was accepted.';
  EXCEPTION WHEN OTHERS THEN
    IF position('already assigned' IN SQLERRM) = 0 THEN
      RAISE;
    END IF;
  END;

  BEGIN
    PERFORM public.confirm_cash_deposit_batch(
      v_batch.deposit_batch_id, v_non_reviewer, 20000,
      CURRENT_DATE, 'ISSUE17-SMOKE-001', NULL
    );
    RAISE EXCEPTION 'Non-reviewer confirmed a cash deposit batch.';
  EXCEPTION WHEN OTHERS THEN
    IF position('donations reviewer' IN SQLERRM) = 0 THEN
      RAISE;
    END IF;
  END;

  BEGIN
    PERFORM public.confirm_cash_deposit_batch(
      v_batch.deposit_batch_id, v_reviewer, 19999,
      CURRENT_DATE, 'ISSUE17-SMOKE-001', NULL
    );
    RAISE EXCEPTION 'Mismatched actual amount was accepted.';
  EXCEPTION WHEN OTHERS THEN
    IF position('does not equal expected' IN SQLERRM) = 0 THEN
      RAISE;
    END IF;
  END;

  SELECT * INTO v_batch
  FROM public.confirm_cash_deposit_batch(
    v_batch.deposit_batch_id, v_reviewer, 20000,
    CURRENT_DATE, 'ISSUE17-SMOKE-001', 'confirmed smoke test'
  );

  IF v_batch.status <> 'confirmed'
     OR v_batch.expected_amount_cents <> 20000
     OR v_batch.actual_amount_cents <> 20000
     OR v_batch.verifier_id <> v_reviewer
  THEN
    RAISE EXCEPTION 'Confirmed batch fields are incorrect.';
  END IF;

  SELECT count(*) INTO v_count
  FROM public.cash_on_hand_donations()
  WHERE donation_id IN (v_donation_a, v_donation_b);

  IF v_count <> 0 THEN
    RAISE EXCEPTION 'Confirmed donations remain in Cash on Hand.';
  END IF;

  BEGIN
    PERFORM public.remove_cash_deposit_item(
      v_batch.deposit_batch_id, v_donation_a, v_preparer
    );
    RAISE EXCEPTION 'Confirmed batch item was mutable.';
  EXCEPTION WHEN OTHERS THEN
    IF position('immutable' IN SQLERRM) = 0 THEN
      RAISE;
    END IF;
  END;

  BEGIN
    UPDATE public.cash_deposit_batches
    SET notes = 'illegal mutation'
    WHERE deposit_batch_id = v_batch.deposit_batch_id;
    RAISE EXCEPTION 'Confirmed batch header was mutable.';
  EXCEPTION WHEN OTHERS THEN
    IF position('immutable' IN SQLERRM) = 0 THEN
      RAISE;
    END IF;
  END;

  -- A cancelled draft releases its donations back to Cash on Hand.
  v_donation_a := public.uuid_generate_v4();

  INSERT INTO public.donations (
    donation_id, member_id, contributor_id, donor_kind, provider, amount_cents,
    currency, donated_at, status, facilitator_id
  )
  VALUES (
    v_donation_a, v_member, v_contributor, 'identified', 'cash', 3000, 'USD',
    now(), 'verified', v_preparer
  );

  SELECT * INTO v_batch
  FROM public.create_cash_deposit_batch(
    v_preparer, CURRENT_DATE, 'ISSUE17-SMOKE-002', NULL
  );

  PERFORM public.add_cash_deposit_item(
    v_batch.deposit_batch_id, v_donation_a, v_preparer
  );

  PERFORM public.cancel_cash_deposit_batch(
    v_batch.deposit_batch_id, v_preparer, 'rollback-only test'
  );

  SELECT count(*) INTO v_count
  FROM public.cash_on_hand_donations()
  WHERE donation_id = v_donation_a;

  IF v_count <> 1 THEN
    RAISE EXCEPTION 'Cancelled batch did not release donation to Cash on Hand.';
  END IF;
END
$$;

ROLLBACK;

SELECT 'Issue #17 cash deposit backend smoke test passed.' AS result;
