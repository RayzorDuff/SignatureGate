-- Rollback-only end-to-end verification for the cash deposit management flow.
--
-- Uses the bootstrapped directory-manager identity as the preparer and a
-- synthetic donations reviewer as verifier. All synthetic records roll back.

\set ON_ERROR_STOP on
BEGIN;

DO $$
DECLARE
  v_preparer uuid;
  v_reviewer uuid := public.uuid_generate_v4();
  v_reviewer_person uuid := public.uuid_generate_v4();
  v_donor_person uuid := public.uuid_generate_v4();
  v_donor_member uuid := public.uuid_generate_v4();
  v_contributor uuid;
  v_donation uuid := public.uuid_generate_v4();
  v_batch public.cash_deposit_batches%ROWTYPE;
  v_tally record;
  v_audit_count integer;
BEGIN
  SELECT m.member_id
  INTO v_preparer
  FROM public.members m
  JOIN public.people p ON p.person_id = m.person_id
  JOIN public.person_app_accounts paa ON paa.person_id = p.person_id
  WHERE lower(paa.email) = 'ray@edanks.com'
    AND m.status = 'active'
    AND m.is_facilitator = true
  LIMIT 1;

  IF v_preparer IS NULL THEN
    RAISE EXCEPTION
      'Bootstrapped preparer ray@edanks.com was not found as an active facilitator.';
  END IF;

  INSERT INTO public.people (person_id, display_name, first_name, last_name)
  VALUES
    (v_reviewer_person, 'End-to-End Deposit Reviewer', 'End-to-End', 'Reviewer'),
    (v_donor_person, 'End-to-End Deposit Donor', 'End-to-End', 'Donor');

  INSERT INTO public.members (
    member_id, person_id, email, status,
    is_facilitator, is_donations_reviewer
  )
  VALUES
    (v_reviewer, v_reviewer_person,
     'cash-deposit-e2e-reviewer@example.invalid',
     'active', true, true),
    (v_donor_member, v_donor_person,
     'cash-deposit-e2e-donor@example.invalid',
     'active', false, false);

  v_contributor := public.ensure_member_contributor(v_donor_member);

  INSERT INTO public.donations (
    donation_id, member_id, contributor_id, donor_kind, provider,
    amount_cents, currency, donated_at, status, facilitator_id
  )
  VALUES (
    v_donation, v_donor_member, v_contributor, 'identified', 'cash',
    2750, 'USD', now(), 'verified', v_preparer
  );

  IF (
    SELECT count(*) FROM public.cash_on_hand_donations()
    WHERE donation_id = v_donation
  ) <> 1 THEN
    RAISE EXCEPTION 'Verified cash donation did not enter Cash on Hand.';
  END IF;

  SELECT * INTO v_batch
  FROM public.create_cash_deposit_batch(
    v_preparer, CURRENT_DATE, NULL, 'end-to-end cash deposit smoke test'
  );

  PERFORM public.add_cash_deposit_item(
    v_batch.deposit_batch_id, v_donation, v_preparer
  );

  IF (
    SELECT count(*) FROM public.cash_on_hand_donations()
    WHERE donation_id = v_donation
  ) <> 0 THEN
    RAISE EXCEPTION 'Assigned cash donation remained in Cash on Hand.';
  END IF;

  SELECT * INTO v_tally
  FROM public.cash_deposit_batch_tally
  WHERE deposit_batch_id = v_batch.deposit_batch_id
    AND donation_id = v_donation;

  IF v_tally.status <> 'draft'
     OR v_tally.item_count <> 1
     OR v_tally.item_total_cents <> 2750
     OR v_tally.item_amount_cents <> 2750
     OR v_tally.member_id <> v_donor_member
     OR v_tally.contributor_id <> v_contributor
  THEN
    RAISE EXCEPTION 'Draft batch tally does not match the assigned donation.';
  END IF;

  SELECT * INTO v_batch
  FROM public.prepare_cash_deposit_batch(
    v_batch.deposit_batch_id, v_preparer, CURRENT_DATE,
    'E2E-001', 'SignatureGate Operating Account', 'end-to-end preparation'
  );

  IF v_batch.status <> 'prepared'
     OR v_batch.expected_amount_cents <> 2750
     OR v_batch.prepared_by <> v_preparer
     OR v_batch.prepared_at IS NULL
  THEN
    RAISE EXCEPTION 'Prepared batch does not contain the expected lifecycle fields.';
  END IF;

  SELECT * INTO v_tally
  FROM public.cash_deposit_batch_tally
  WHERE deposit_batch_id = v_batch.deposit_batch_id
    AND donation_id = v_donation;

  IF v_tally.status <> 'prepared'
     OR v_tally.expected_amount_cents <> 2750
     OR v_tally.item_total_cents <> 2750
  THEN
    RAISE EXCEPTION 'Prepared batch tally is inconsistent with the prepared batch.';
  END IF;

  SELECT * INTO v_batch
  FROM public.confirm_cash_deposit_batch(
    v_batch.deposit_batch_id, v_reviewer, 2750,
    CURRENT_DATE, 'E2E-001', 'end-to-end confirmation'
  );

  IF v_batch.status <> 'confirmed'
     OR v_batch.actual_amount_cents <> 2750
     OR v_batch.verifier_id <> v_reviewer
     OR v_batch.confirmed_at IS NULL
  THEN
    RAISE EXCEPTION 'Confirmed batch does not contain the expected lifecycle fields.';
  END IF;

  IF (
    SELECT count(*) FROM public.cash_on_hand_donations()
    WHERE donation_id = v_donation
  ) <> 0 THEN
    RAISE EXCEPTION 'Confirmed cash donation returned to Cash on Hand.';
  END IF;

  SELECT * INTO v_tally
  FROM public.cash_deposit_batch_tally
  WHERE deposit_batch_id = v_batch.deposit_batch_id
    AND donation_id = v_donation;

  IF v_tally.status <> 'confirmed'
     OR v_tally.actual_amount_cents <> 2750
     OR v_tally.item_total_cents <> 2750
  THEN
    RAISE EXCEPTION 'Confirmed batch tally is inconsistent with the confirmed batch.';
  END IF;

  BEGIN
    PERFORM public.prepare_cash_deposit_batch(
      v_batch.deposit_batch_id, v_preparer, CURRENT_DATE,
      'E2E-002', 'SignatureGate Operating Account', NULL
    );
    RAISE EXCEPTION 'Confirmed batch was mutable through preparation.';
  EXCEPTION WHEN OTHERS THEN
    IF position('not draft' IN SQLERRM) = 0
       AND position('confirmed' IN SQLERRM) = 0
       AND position('immutable' IN SQLERRM) = 0
    THEN
      RAISE;
    END IF;
  END;

  SELECT count(*) INTO v_audit_count
  FROM public.audit_log
  WHERE entity_type = 'cash_deposit_batch'
    AND entity_id = v_batch.deposit_batch_id::text
    AND action IN (
      'cash_deposit_batch.created',
      'cash_deposit_batch.item_added',
      'cash_deposit_batch.prepared',
      'cash_deposit_batch.confirmed'
    );

  IF v_audit_count < 4 THEN
    RAISE EXCEPTION
      'Expected batch audit history for creation, item assignment, preparation, and confirmation; found % rows.',
      v_audit_count;
  END IF;

  RAISE NOTICE
    'Cash deposit end-to-end checks passed using % as preparer; synthetic records will roll back.',
    v_preparer;
END
$$;

ROLLBACK;

SELECT 'Cash deposit end-to-end smoke test passed.' AS result;
