-- SignatureGate Issue #18: ERP synchronization state for confirmed cash deposits.
--
-- SignatureGate remains authoritative for cash custody and deposit composition.
-- RootedOps/ERPNext owns accounting creation and bank reconciliation.
--
-- A confirmed deposit queues exactly one stable source event:
--   signaturegate:deposit_batch:<deposit_batch_id>
--
-- Synchronization state is intentionally stored outside cash_deposit_batches so
-- confirmed operational batches remain immutable while ERP retries can continue.

\set ON_ERROR_STOP on
BEGIN;

CREATE TABLE IF NOT EXISTS public.cash_deposit_erp_sync (
  deposit_batch_id uuid PRIMARY KEY
    REFERENCES public.cash_deposit_batches(deposit_batch_id)
    ON DELETE RESTRICT,
  source_key text NOT NULL UNIQUE,
  status text NOT NULL DEFAULT 'pending',
  attempt_count integer NOT NULL DEFAULT 0,
  last_attempt_at timestamptz,
  synced_at timestamptz,
  erp_doctype text,
  erp_name text,
  last_error text,
  last_response jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT cash_deposit_erp_sync_status_check
    CHECK (status IN ('pending', 'processing', 'succeeded', 'failed')),
  CONSTRAINT cash_deposit_erp_sync_attempt_count_check
    CHECK (attempt_count >= 0),
  CONSTRAINT cash_deposit_erp_sync_success_fields_check
    CHECK (
      status <> 'succeeded'
      OR (
        NULLIF(btrim(erp_doctype), '') IS NOT NULL
        AND NULLIF(btrim(erp_name), '') IS NOT NULL
        AND synced_at IS NOT NULL
      )
    )
);

COMMENT ON TABLE public.cash_deposit_erp_sync IS
  'Issue #18 ERP synchronization state for immutable confirmed cash deposit batches.';

DROP TRIGGER IF EXISTS trg_cash_deposit_erp_sync_updated_at
  ON public.cash_deposit_erp_sync;
CREATE TRIGGER trg_cash_deposit_erp_sync_updated_at
BEFORE UPDATE ON public.cash_deposit_erp_sync
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

CREATE OR REPLACE FUNCTION public.enqueue_cash_deposit_erp_sync_on_confirmation()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.status = 'confirmed'
     AND OLD.status IS DISTINCT FROM 'confirmed'
  THEN
    INSERT INTO public.cash_deposit_erp_sync (
      deposit_batch_id,
      source_key,
      status
    )
    VALUES (
      NEW.deposit_batch_id,
      'signaturegate:deposit_batch:' || NEW.deposit_batch_id::text,
      'pending'
    )
    ON CONFLICT (deposit_batch_id) DO NOTHING;

    INSERT INTO public.audit_log (
      actor,
      action,
      entity_type,
      entity_id,
      details
    )
    VALUES (
      public.cash_deposit_actor_email(NEW.verifier_id),
      'cash_deposit_batch.erp_sync_queued',
      'cash_deposit_batch',
      NEW.deposit_batch_id::text,
      jsonb_build_object(
        'source_key',
          'signaturegate:deposit_batch:' || NEW.deposit_batch_id::text,
        'actual_amount_cents', NEW.actual_amount_cents,
        'deposit_date', NEW.deposit_date,
        'deposit_slip_number', NEW.deposit_slip_number,
        'destination_bank_account', NEW.destination_bank_account
      )
    );
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_cash_deposit_erp_sync_on_confirmation
  ON public.cash_deposit_batches;
CREATE TRIGGER trg_cash_deposit_erp_sync_on_confirmation
AFTER UPDATE OF status ON public.cash_deposit_batches
FOR EACH ROW
EXECUTE FUNCTION public.enqueue_cash_deposit_erp_sync_on_confirmation();

-- Safe forward backfill for any confirmed batches that predate this migration.
INSERT INTO public.cash_deposit_erp_sync (
  deposit_batch_id,
  source_key,
  status
)
SELECT
  b.deposit_batch_id,
  'signaturegate:deposit_batch:' || b.deposit_batch_id::text,
  'pending'
FROM public.cash_deposit_batches b
WHERE b.status = 'confirmed'
ON CONFLICT (deposit_batch_id) DO NOTHING;

CREATE OR REPLACE FUNCTION public.begin_cash_deposit_erp_sync(
  p_deposit_batch_id uuid
)
RETURNS TABLE (
  source_key text,
  deposit_batch_id uuid,
  batch_status text,
  deposit_date date,
  deposit_slip_number text,
  destination_bank_account text,
  expected_amount_cents integer,
  actual_amount_cents integer,
  confirmed_at timestamptz,
  verifier_id uuid,
  sync_status text,
  attempt_count integer,
  already_succeeded boolean,
  erp_doctype text,
  erp_name text
)
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_batch public.cash_deposit_batches%ROWTYPE;
  v_sync public.cash_deposit_erp_sync%ROWTYPE;
BEGIN
  SELECT *
  INTO v_batch
  FROM public.cash_deposit_batches
  WHERE cash_deposit_batches.deposit_batch_id = p_deposit_batch_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION
      'Cash deposit batch % was not found.',
      p_deposit_batch_id;
  END IF;

  IF v_batch.status <> 'confirmed' THEN
    RAISE EXCEPTION
      'Cash deposit batch % is %, not confirmed.',
      p_deposit_batch_id,
      v_batch.status;
  END IF;

  INSERT INTO public.cash_deposit_erp_sync (
    deposit_batch_id,
    source_key,
    status
  )
  VALUES (
    v_batch.deposit_batch_id,
    'signaturegate:deposit_batch:' || v_batch.deposit_batch_id::text,
    'pending'
  )
  ON CONFLICT (deposit_batch_id) DO NOTHING;

  SELECT *
  INTO v_sync
  FROM public.cash_deposit_erp_sync
  WHERE cash_deposit_erp_sync.deposit_batch_id = p_deposit_batch_id
  FOR UPDATE;

  IF v_sync.status = 'succeeded' THEN
    RETURN QUERY
    SELECT
      v_sync.source_key,
      v_batch.deposit_batch_id,
      v_batch.status,
      v_batch.deposit_date,
      v_batch.deposit_slip_number,
      v_batch.destination_bank_account,
      v_batch.expected_amount_cents,
      v_batch.actual_amount_cents,
      v_batch.confirmed_at,
      v_batch.verifier_id,
      v_sync.status,
      v_sync.attempt_count,
      true,
      v_sync.erp_doctype,
      v_sync.erp_name;
    RETURN;
  END IF;

  UPDATE public.cash_deposit_erp_sync
  SET
    status = 'processing',
    attempt_count = attempt_count + 1,
    last_attempt_at = now(),
    last_error = NULL
  WHERE cash_deposit_erp_sync.deposit_batch_id = p_deposit_batch_id
  RETURNING * INTO v_sync;

  INSERT INTO public.audit_log (
    actor,
    action,
    entity_type,
    entity_id,
    details
  )
  VALUES (
    public.cash_deposit_actor_email(v_batch.verifier_id),
    'cash_deposit_batch.erp_sync_started',
    'cash_deposit_batch',
    v_batch.deposit_batch_id::text,
    jsonb_build_object(
      'source_key', v_sync.source_key,
      'attempt_count', v_sync.attempt_count
    )
  );

  RETURN QUERY
  SELECT
    v_sync.source_key,
    v_batch.deposit_batch_id,
    v_batch.status,
    v_batch.deposit_date,
    v_batch.deposit_slip_number,
    v_batch.destination_bank_account,
    v_batch.expected_amount_cents,
    v_batch.actual_amount_cents,
    v_batch.confirmed_at,
    v_batch.verifier_id,
    v_sync.status,
    v_sync.attempt_count,
    false,
    v_sync.erp_doctype,
    v_sync.erp_name;
END;
$$;

CREATE OR REPLACE FUNCTION public.complete_cash_deposit_erp_sync(
  p_deposit_batch_id uuid,
  p_success boolean,
  p_erp_doctype text DEFAULT NULL,
  p_erp_name text DEFAULT NULL,
  p_error text DEFAULT NULL,
  p_response jsonb DEFAULT '{}'::jsonb
)
RETURNS public.cash_deposit_erp_sync
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_batch public.cash_deposit_batches%ROWTYPE;
  v_sync public.cash_deposit_erp_sync%ROWTYPE;
BEGIN
  SELECT *
  INTO v_batch
  FROM public.cash_deposit_batches
  WHERE cash_deposit_batches.deposit_batch_id = p_deposit_batch_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION
      'Cash deposit batch % was not found.',
      p_deposit_batch_id;
  END IF;

  IF v_batch.status <> 'confirmed' THEN
    RAISE EXCEPTION
      'Cash deposit batch % is %, not confirmed.',
      p_deposit_batch_id,
      v_batch.status;
  END IF;

  SELECT *
  INTO v_sync
  FROM public.cash_deposit_erp_sync
  WHERE cash_deposit_erp_sync.deposit_batch_id = p_deposit_batch_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION
      'Cash deposit ERP sync row for batch % was not found.',
      p_deposit_batch_id;
  END IF;

  -- Never downgrade a completed synchronization because a later client timed
  -- out or retried after the ERP document was already created.
  IF v_sync.status = 'succeeded' THEN
    RETURN v_sync;
  END IF;

  IF COALESCE(p_success, false) THEN
    IF NULLIF(btrim(p_erp_doctype), '') IS NULL
       OR NULLIF(btrim(p_erp_name), '') IS NULL
    THEN
      RAISE EXCEPTION
        'ERP DocType and document name are required for a successful synchronization.';
    END IF;

    UPDATE public.cash_deposit_erp_sync
    SET
      status = 'succeeded',
      erp_doctype = btrim(p_erp_doctype),
      erp_name = btrim(p_erp_name),
      synced_at = now(),
      last_error = NULL,
      last_response = COALESCE(p_response, '{}'::jsonb)
    WHERE cash_deposit_erp_sync.deposit_batch_id = p_deposit_batch_id
    RETURNING * INTO v_sync;

    INSERT INTO public.audit_log (
      actor,
      action,
      entity_type,
      entity_id,
      details
    )
    VALUES (
      public.cash_deposit_actor_email(v_batch.verifier_id),
      'cash_deposit_batch.erp_sync_succeeded',
      'cash_deposit_batch',
      v_batch.deposit_batch_id::text,
      jsonb_build_object(
        'source_key', v_sync.source_key,
        'attempt_count', v_sync.attempt_count,
        'erp_doctype', v_sync.erp_doctype,
        'erp_name', v_sync.erp_name
      )
    );
  ELSE
    UPDATE public.cash_deposit_erp_sync
    SET
      status = 'failed',
      last_error = COALESCE(
        NULLIF(btrim(p_error), ''),
        'RootedOps synchronization failed.'
      ),
      last_response = COALESCE(p_response, '{}'::jsonb)
    WHERE cash_deposit_erp_sync.deposit_batch_id = p_deposit_batch_id
    RETURNING * INTO v_sync;

    INSERT INTO public.audit_log (
      actor,
      action,
      entity_type,
      entity_id,
      details
    )
    VALUES (
      public.cash_deposit_actor_email(v_batch.verifier_id),
      'cash_deposit_batch.erp_sync_failed',
      'cash_deposit_batch',
      v_batch.deposit_batch_id::text,
      jsonb_build_object(
        'source_key', v_sync.source_key,
        'attempt_count', v_sync.attempt_count,
        'error', v_sync.last_error
      )
    );
  END IF;

  RETURN v_sync;
END;
$$;

COMMIT;

SELECT
  status,
  count(*)
FROM public.cash_deposit_erp_sync
GROUP BY status
ORDER BY status;
