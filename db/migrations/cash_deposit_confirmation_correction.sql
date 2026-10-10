-- SignatureGate Issue #18: audited correction of confirmed deposit dates.
--
-- Confirmed deposit composition remains immutable. This narrow correction path
-- exists for confirmation metadata only and is allowed solely while ERP sync
-- has not succeeded.

\set ON_ERROR_STOP on
BEGIN;

CREATE OR REPLACE FUNCTION public.prevent_confirmed_cash_deposit_mutation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $
DECLARE
  v_sync_status text;
BEGIN
  IF OLD.status = 'confirmed' THEN
    IF TG_OP = 'UPDATE'
       AND NEW.deposit_date IS DISTINCT FROM OLD.deposit_date
       AND (
         to_jsonb(NEW) - 'deposit_date' - 'updated_at'
       ) = (
         to_jsonb(OLD) - 'deposit_date' - 'updated_at'
       )
    THEN
      SELECT status
      INTO v_sync_status
      FROM public.cash_deposit_erp_sync
      WHERE deposit_batch_id = OLD.deposit_batch_id;

      IF v_sync_status IS NULL
         OR v_sync_status IN ('pending', 'failed')
      THEN
        RETURN NEW;
      END IF;
    END IF;

    RAISE EXCEPTION
      'Confirmed cash deposit batch % is immutable.',
      OLD.deposit_batch_id;
  END IF;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;

  RETURN NEW;
END;
$;

CREATE OR REPLACE FUNCTION public.correct_confirmed_cash_deposit_date(
  p_deposit_batch_id uuid,
  p_actor_id uuid,
  p_deposit_date date,
  p_reason text
)
RETURNS public.cash_deposit_batches
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_batch public.cash_deposit_batches%ROWTYPE;
  v_old_date date;
  v_sync_status text;
BEGIN
  PERFORM public.assert_cash_deposit_verifier(p_actor_id);

  IF p_deposit_date IS NULL THEN
    RAISE EXCEPTION 'Corrected deposit date is required.';
  END IF;

  IF p_deposit_date > CURRENT_DATE THEN
    RAISE EXCEPTION 'Corrected deposit date % cannot be in the future.', p_deposit_date;
  END IF;

  IF NULLIF(btrim(p_reason), '') IS NULL THEN
    RAISE EXCEPTION 'A correction reason is required.';
  END IF;

  SELECT *
  INTO v_batch
  FROM public.cash_deposit_batches
  WHERE deposit_batch_id = p_deposit_batch_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Cash deposit batch % was not found.', p_deposit_batch_id;
  END IF;

  IF v_batch.status <> 'confirmed' THEN
    RAISE EXCEPTION
      'Cash deposit batch % is %, not confirmed.',
      p_deposit_batch_id,
      v_batch.status;
  END IF;

  SELECT status
  INTO v_sync_status
  FROM public.cash_deposit_erp_sync
  WHERE deposit_batch_id = p_deposit_batch_id
  FOR UPDATE;

  IF v_sync_status = 'succeeded' THEN
    RAISE EXCEPTION
      'Cash deposit batch % already synchronized to ERPNext and cannot be corrected here.',
      p_deposit_batch_id;
  END IF;

  IF v_sync_status = 'processing' THEN
    RAISE EXCEPTION
      'Cash deposit batch % ERP synchronization is currently processing; retry correction after it finishes.',
      p_deposit_batch_id;
  END IF;

  v_old_date := v_batch.deposit_date;

  IF v_old_date = p_deposit_date THEN
    RETURN v_batch;
  END IF;

  UPDATE public.cash_deposit_batches
  SET deposit_date = p_deposit_date
  WHERE deposit_batch_id = p_deposit_batch_id
  RETURNING * INTO v_batch;

  IF v_sync_status IS NOT NULL THEN
    UPDATE public.cash_deposit_erp_sync
    SET
      status = 'pending',
      last_error = NULL
    WHERE deposit_batch_id = p_deposit_batch_id;
  END IF;

  INSERT INTO public.audit_log (
    actor,
    action,
    entity_type,
    entity_id,
    details
  )
  VALUES (
    public.cash_deposit_actor_email(p_actor_id),
    'cash_deposit_batch.confirmed_date_corrected',
    'cash_deposit_batch',
    p_deposit_batch_id::text,
    jsonb_build_object(
      'old_deposit_date', v_old_date,
      'new_deposit_date', p_deposit_date,
      'reason', btrim(p_reason),
      'erp_sync_status_before', v_sync_status
    )
  );

  RETURN v_batch;
END;
$$;

COMMIT;
