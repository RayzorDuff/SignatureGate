-- Rollback-only verification for SignatureGate Issue #18 cash-deposit ERP sync state.
\set ON_ERROR_STOP on
BEGIN;

DO $$
DECLARE
  v_actor uuid := public.uuid_generate_v4();
  v_actor_person uuid := public.uuid_generate_v4();
  v_donation uuid := public.uuid_generate_v4();
  v_batch public.cash_deposit_batches%ROWTYPE;
  v_sync public.cash_deposit_erp_sync%ROWTYPE;
  v_begin record;
BEGIN
  INSERT INTO public.people (
    person_id,
    display_name,
    first_name,
    last_name
  )
  VALUES (
    v_actor_person,
    'ERP Sync Test Reviewer',
    'ERP Sync',
    'Reviewer'
  );

  INSERT INTO public.members (
    member_id,
    person_id,
    email,
    status,
    is_facilitator,
    is_donations_reviewer
  )
  VALUES (
    v_actor,
    v_actor_person,
    'cash-deposit-erp-sync@example.invalid',
    'active',
    true,
    true
  );

  INSERT INTO public.donations (
    donation_id,
    donor_kind,
    provider,
    amount_cents,
    currency,
    donated_at,
    status,
    facilitator_id
  )
  VALUES (
    v_donation,
    'anonymous',
    'cash',
    73700,
    'USD',
    now(),
    'verified',
    v_actor
  );

  SELECT *
  INTO v_batch
  FROM public.create_cash_deposit_batch(
    v_actor,
    CURRENT_DATE,
    NULL,
    'ERP synchronization regression test'
  );

  PERFORM public.add_cash_deposit_item(
    v_batch.deposit_batch_id,
    v_donation,
    v_actor
  );

  SELECT *
  INTO v_batch
  FROM public.prepare_cash_deposit_batch(
    v_batch.deposit_batch_id,
    v_actor,
    CURRENT_DATE,
    'ERP-SYNC-TEST',
    'Rooted Psyche Checking',
    NULL
  );

  SELECT *
  INTO v_batch
  FROM public.confirm_cash_deposit_batch(
    v_batch.deposit_batch_id,
    v_actor,
    73700,
    CURRENT_DATE,
    'ERP-SYNC-TEST',
    NULL
  );

  SELECT *
  INTO STRICT v_sync
  FROM public.cash_deposit_erp_sync
  WHERE deposit_batch_id = v_batch.deposit_batch_id;

  IF v_sync.status <> 'pending'
     OR v_sync.attempt_count <> 0
     OR v_sync.source_key <>
       'signaturegate:deposit_batch:' || v_batch.deposit_batch_id::text
  THEN
    RAISE EXCEPTION
      'Confirmation did not queue the expected ERP synchronization row.';
  END IF;

  SELECT *
  INTO v_begin
  FROM public.begin_cash_deposit_erp_sync(v_batch.deposit_batch_id);

  IF v_begin.sync_status <> 'processing'
     OR v_begin.attempt_count <> 1
     OR v_begin.already_succeeded IS TRUE
     OR v_begin.actual_amount_cents <> 73700
     OR v_begin.batch_status <> 'confirmed'
  THEN
    RAISE EXCEPTION
      'Beginning ERP synchronization returned unexpected state.';
  END IF;

  SELECT *
  INTO v_sync
  FROM public.complete_cash_deposit_erp_sync(
    v_batch.deposit_batch_id,
    true,
    'Journal Entry',
    'ACC-JV-ERP-SYNC-TEST',
    NULL,
    '{"ok":true}'::jsonb
  );

  IF v_sync.status <> 'succeeded'
     OR v_sync.erp_doctype <> 'Journal Entry'
     OR v_sync.erp_name <> 'ACC-JV-ERP-SYNC-TEST'
     OR v_sync.synced_at IS NULL
  THEN
    RAISE EXCEPTION
      'Completing ERP synchronization did not persist success.';
  END IF;

  SELECT *
  INTO v_begin
  FROM public.begin_cash_deposit_erp_sync(v_batch.deposit_batch_id);

  IF v_begin.already_succeeded IS NOT TRUE
     OR v_begin.attempt_count <> 1
     OR v_begin.erp_name <> 'ACC-JV-ERP-SYNC-TEST'
  THEN
    RAISE EXCEPTION
      'Successful ERP synchronization was not idempotent on retry.';
  END IF;

  IF (
    SELECT count(*)
    FROM public.audit_log
    WHERE entity_type = 'cash_deposit_batch'
      AND entity_id = v_batch.deposit_batch_id::text
      AND action IN (
        'cash_deposit_batch.erp_sync_queued',
        'cash_deposit_batch.erp_sync_started',
        'cash_deposit_batch.erp_sync_succeeded'
      )
  ) <> 3
  THEN
    RAISE EXCEPTION
      'Expected ERP synchronization audit events were not written.';
  END IF;

  RAISE NOTICE
    'Cash deposit ERP synchronization state checks passed; synthetic records will roll back.';
END
$$;

ROLLBACK;

SELECT 'Cash deposit ERP sync verification passed.' AS result;
