-- Rollback-only verification for confirmed cash-deposit date correction.
\set ON_ERROR_STOP on
BEGIN;

DO $$
DECLARE
  v_actor uuid := public.uuid_generate_v4();
  v_actor_person uuid := public.uuid_generate_v4();
  v_donation uuid := public.uuid_generate_v4();
  v_batch public.cash_deposit_batches%ROWTYPE;
  v_sync public.cash_deposit_erp_sync%ROWTYPE;
BEGIN
  INSERT INTO public.people (
    person_id, display_name, first_name, last_name
  )
  VALUES (
    v_actor_person, 'Cash Deposit Correction Reviewer', 'Cash Deposit', 'Reviewer'
  );

  INSERT INTO public.members (
    member_id, person_id, email, status, is_facilitator, is_donations_reviewer
  )
  VALUES (
    v_actor, v_actor_person, 'cash-deposit-correction@example.invalid',
    'active', true, true
  );

  INSERT INTO public.donations (
    donation_id, donor_kind, provider, amount_cents, currency,
    donated_at, status, facilitator_id
  )
  VALUES (
    v_donation, 'anonymous', 'cash', 1000, 'USD',
    now(), 'verified', v_actor
  );

  SELECT * INTO v_batch
  FROM public.create_cash_deposit_batch(
    v_actor, CURRENT_DATE - 2, NULL, 'Correction regression test'
  );

  PERFORM public.add_cash_deposit_item(
    v_batch.deposit_batch_id, v_donation, v_actor
  );

  SELECT * INTO v_batch
  FROM public.prepare_cash_deposit_batch(
    v_batch.deposit_batch_id,
    v_actor,
    CURRENT_DATE - 2,
    'CORRECTION-TEST',
    'Test bank account',
    NULL
  );

  SELECT * INTO v_batch
  FROM public.confirm_cash_deposit_batch(
    v_batch.deposit_batch_id,
    v_actor,
    1000,
    CURRENT_DATE,
    'CORRECTION-TEST',
    NULL
  );

  SELECT * INTO v_sync
  FROM public.cash_deposit_erp_sync
  WHERE deposit_batch_id = v_batch.deposit_batch_id;

  UPDATE public.cash_deposit_erp_sync
  SET
    status = 'failed',
    attempt_count = 1,
    last_error = 'Synthetic failed bank match'
  WHERE deposit_batch_id = v_batch.deposit_batch_id;

  BEGIN
    UPDATE public.cash_deposit_batches
    SET deposit_date = CURRENT_DATE - 1
    WHERE deposit_batch_id = v_batch.deposit_batch_id;

    RAISE EXCEPTION
      'Direct confirmed-batch deposit-date mutation unexpectedly succeeded.';
  EXCEPTION
    WHEN raise_exception THEN
      IF SQLERRM NOT LIKE 'Confirmed cash deposit batch % is immutable.' THEN
        RAISE;
      END IF;
  END;

  SELECT * INTO v_batch
  FROM public.correct_confirmed_cash_deposit_date(
    v_batch.deposit_batch_id,
    v_actor,
    CURRENT_DATE - 2,
    'Date picker defaulted to confirmation date during regression test.'
  );

  IF v_batch.deposit_date <> CURRENT_DATE - 2 THEN
    RAISE EXCEPTION 'Confirmed deposit date correction did not persist.';
  END IF;

  SELECT * INTO v_sync
  FROM public.cash_deposit_erp_sync
  WHERE deposit_batch_id = v_batch.deposit_batch_id;

  IF v_sync.status <> 'pending'
     OR v_sync.attempt_count <> 1
     OR v_sync.last_error IS NOT NULL
  THEN
    RAISE EXCEPTION 'ERP sync state was not safely reset for retry.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.audit_log
    WHERE entity_type = 'cash_deposit_batch'
      AND entity_id = v_batch.deposit_batch_id::text
      AND action = 'cash_deposit_batch.confirmed_date_corrected'
  ) THEN
    RAISE EXCEPTION 'Deposit-date correction audit event was not written.';
  END IF;

  RAISE NOTICE
    'Confirmed cash-deposit date correction checks passed; synthetic records will roll back.';
END
$$;

ROLLBACK;

SELECT 'Confirmed cash-deposit date correction verification passed.' AS result;
