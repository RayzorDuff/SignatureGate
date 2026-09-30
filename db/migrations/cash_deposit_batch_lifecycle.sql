-- Cash deposit batch lifecycle refinement.
--
-- Extends the operational cash-deposit workflow with:
--   draft -> prepared -> confirmed
--   draft/prepared -> cancelled
--
-- Removed batch items remain as audit history. Active membership in a batch is
-- represented by removed_at IS NULL. ERPNext synchronization remains outside
-- this migration.

\set ON_ERROR_STOP on
BEGIN;

ALTER TABLE public.cash_deposit_batches
  ADD COLUMN IF NOT EXISTS destination_bank_account text,
  ADD COLUMN IF NOT EXISTS prepared_at timestamptz,
  ADD COLUMN IF NOT EXISTS prepared_by uuid REFERENCES public.members(member_id);

ALTER TABLE public.cash_deposit_batch_items
  ADD COLUMN IF NOT EXISTS removed_at timestamptz,
  ADD COLUMN IF NOT EXISTS removed_by uuid REFERENCES public.members(member_id),
  ADD COLUMN IF NOT EXISTS removal_reason text;

ALTER TABLE public.cash_deposit_batches
  DROP CONSTRAINT IF EXISTS cash_deposit_batches_status_check;

ALTER TABLE public.cash_deposit_batches
  ADD CONSTRAINT cash_deposit_batches_status_check
  CHECK (status IN ('draft', 'prepared', 'confirmed', 'cancelled'));

ALTER TABLE public.cash_deposit_batches
  DROP CONSTRAINT IF EXISTS cash_deposit_batches_confirmed_fields_check;

ALTER TABLE public.cash_deposit_batches
  ADD CONSTRAINT cash_deposit_batches_confirmed_fields_check
  CHECK (
    (status = 'confirmed'
      AND deposit_date IS NOT NULL
      AND NULLIF(btrim(deposit_slip_number), '') IS NOT NULL
      AND NULLIF(btrim(destination_bank_account), '') IS NOT NULL
      AND prepared_by IS NOT NULL
      AND prepared_at IS NOT NULL
      AND verifier_id IS NOT NULL
      AND actual_amount_cents IS NOT NULL
      AND confirmed_at IS NOT NULL)
    OR
    (status <> 'confirmed')
  );

ALTER TABLE public.cash_deposit_batches
  DROP CONSTRAINT IF EXISTS cash_deposit_batches_prepared_fields_check;

ALTER TABLE public.cash_deposit_batches
  ADD CONSTRAINT cash_deposit_batches_prepared_fields_check
  CHECK (
    status NOT IN ('prepared', 'confirmed')
    OR (
      deposit_date IS NOT NULL
      AND NULLIF(btrim(deposit_slip_number), '') IS NOT NULL
      AND NULLIF(btrim(destination_bank_account), '') IS NOT NULL
      AND prepared_by IS NOT NULL
      AND prepared_at IS NOT NULL
    )
  );

DROP INDEX IF EXISTS public.uq_cash_deposit_batch_items_donation;

CREATE UNIQUE INDEX uq_cash_deposit_batch_items_donation
  ON public.cash_deposit_batch_items (donation_id)
  WHERE removed_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_cash_deposit_batch_items_active
  ON public.cash_deposit_batch_items (deposit_batch_id, created_at)
  WHERE removed_at IS NULL;

CREATE OR REPLACE FUNCTION public.prevent_confirmed_cash_deposit_item_mutation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  v_batch_status text;
  v_batch_id uuid;
BEGIN
  v_batch_id := CASE
    WHEN TG_OP = 'DELETE' THEN OLD.deposit_batch_id
    ELSE NEW.deposit_batch_id
  END;

  SELECT status
  INTO v_batch_status
  FROM public.cash_deposit_batches
  WHERE deposit_batch_id = v_batch_id;

  IF v_batch_status = 'confirmed' THEN
    RAISE EXCEPTION
      'Items in confirmed cash deposit batch % are immutable.',
      v_batch_id;
  END IF;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.add_cash_deposit_item(
  p_deposit_batch_id uuid,
  p_donation_id uuid,
  p_actor_id uuid
)
RETURNS public.cash_deposit_batch_items
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_batch public.cash_deposit_batches%ROWTYPE;
  v_donation public.donations%ROWTYPE;
  v_item public.cash_deposit_batch_items%ROWTYPE;
BEGIN
  SELECT *
  INTO v_batch
  FROM public.cash_deposit_batches
  WHERE deposit_batch_id = p_deposit_batch_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Cash deposit batch % was not found.', p_deposit_batch_id;
  END IF;

  IF v_batch.status <> 'draft' THEN
    RAISE EXCEPTION
      'Cash deposit batch % is %, not draft.', p_deposit_batch_id, v_batch.status;
  END IF;

  IF p_actor_id IS NULL OR p_actor_id <> v_batch.preparer_id THEN
    RAISE EXCEPTION
      'Only the deposit preparer may modify a draft cash deposit batch.';
  END IF;

  PERFORM public.assert_cash_deposit_preparer(p_actor_id);

  SELECT *
  INTO v_donation
  FROM public.donations
  WHERE donation_id = p_donation_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Donation % was not found.', p_donation_id;
  END IF;

  IF v_donation.provider <> 'cash'
     OR v_donation.status <> 'verified'
     OR v_donation.donor_kind NOT IN ('identified', 'anonymous')
     OR v_donation.amount_cents IS NULL
     OR v_donation.amount_cents <= 0
  THEN
    RAISE EXCEPTION
      'Donation % is not currently eligible for a cash deposit batch.',
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

  INSERT INTO public.cash_deposit_batch_items (
    deposit_batch_id,
    donation_id,
    amount_cents
  )
  VALUES (
    p_deposit_batch_id,
    p_donation_id,
    v_donation.amount_cents
  )
  RETURNING * INTO v_item;

  UPDATE public.cash_deposit_batches b
  SET expected_amount_cents = (
    SELECT COALESCE(sum(i.amount_cents), 0)
    FROM public.cash_deposit_batch_items i
    WHERE i.deposit_batch_id = b.deposit_batch_id
      AND i.removed_at IS NULL
  )
  WHERE b.deposit_batch_id = p_deposit_batch_id;

  INSERT INTO public.audit_log (actor, action, entity_type, entity_id, details)
  VALUES (
    public.cash_deposit_actor_email(p_actor_id),
    'cash_deposit_batch.item_added',
    'cash_deposit_batch',
    p_deposit_batch_id::text,
    jsonb_build_object(
      'donation_id', p_donation_id,
      'deposit_batch_item_id', v_item.deposit_batch_item_id,
      'amount_cents', v_item.amount_cents
    )
  );

  RETURN v_item;
END;
$$;

DROP FUNCTION IF EXISTS public.remove_cash_deposit_item(uuid, uuid, uuid);

CREATE OR REPLACE FUNCTION public.remove_cash_deposit_item(
  p_deposit_batch_id uuid,
  p_donation_id uuid,
  p_actor_id uuid,
  p_reason text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_batch public.cash_deposit_batches%ROWTYPE;
  v_item public.cash_deposit_batch_items%ROWTYPE;
BEGIN
  SELECT *
  INTO v_batch
  FROM public.cash_deposit_batches
  WHERE deposit_batch_id = p_deposit_batch_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Cash deposit batch % was not found.', p_deposit_batch_id;
  END IF;

  IF v_batch.status <> 'draft' THEN
    RAISE EXCEPTION
      'Cash deposit batch % is %, not draft.', p_deposit_batch_id, v_batch.status;
  END IF;

  IF p_actor_id IS NULL OR p_actor_id <> v_batch.preparer_id THEN
    RAISE EXCEPTION
      'Only the deposit preparer may modify a draft cash deposit batch.';
  END IF;

  SELECT *
  INTO v_item
  FROM public.cash_deposit_batch_items
  WHERE deposit_batch_id = p_deposit_batch_id
    AND donation_id = p_donation_id
    AND removed_at IS NULL
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION
      'Donation % is not an active item in cash deposit batch %.',
      p_donation_id, p_deposit_batch_id;
  END IF;

  UPDATE public.cash_deposit_batch_items
  SET
    removed_at = now(),
    removed_by = p_actor_id,
    removal_reason = NULLIF(btrim(p_reason), '')
  WHERE deposit_batch_item_id = v_item.deposit_batch_item_id;

  UPDATE public.cash_deposit_batches b
  SET expected_amount_cents = (
    SELECT COALESCE(sum(i.amount_cents), 0)
    FROM public.cash_deposit_batch_items i
    WHERE i.deposit_batch_id = b.deposit_batch_id
      AND i.removed_at IS NULL
  )
  WHERE b.deposit_batch_id = p_deposit_batch_id;

  INSERT INTO public.audit_log (actor, action, entity_type, entity_id, details)
  VALUES (
    public.cash_deposit_actor_email(p_actor_id),
    'cash_deposit_batch.item_removed',
    'cash_deposit_batch',
    p_deposit_batch_id::text,
    jsonb_build_object(
      'donation_id', p_donation_id,
      'deposit_batch_item_id', v_item.deposit_batch_item_id,
      'amount_cents', v_item.amount_cents,
      'reason', NULLIF(btrim(p_reason), '')
    )
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.prepare_cash_deposit_batch(
  p_deposit_batch_id uuid,
  p_actor_id uuid,
  p_deposit_date date DEFAULT NULL,
  p_deposit_slip_number text DEFAULT NULL,
  p_destination_bank_account text DEFAULT NULL,
  p_notes text DEFAULT NULL
)
RETURNS public.cash_deposit_batches
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_batch public.cash_deposit_batches%ROWTYPE;
  v_expected_amount integer;
  v_item_count integer;
  v_invalid_count integer;
BEGIN
  PERFORM public.assert_cash_deposit_preparer(p_actor_id);

  SELECT *
  INTO v_batch
  FROM public.cash_deposit_batches
  WHERE deposit_batch_id = p_deposit_batch_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Cash deposit batch % was not found.', p_deposit_batch_id;
  END IF;

  IF v_batch.status <> 'draft' THEN
    RAISE EXCEPTION
      'Cash deposit batch % is %, not draft.', p_deposit_batch_id, v_batch.status;
  END IF;

  IF v_batch.preparer_id <> p_actor_id THEN
    RAISE EXCEPTION
      'Only the deposit preparer may prepare a cash deposit batch.';
  END IF;

  SELECT count(*), COALESCE(sum(i.amount_cents), 0)
  INTO v_item_count, v_expected_amount
  FROM public.cash_deposit_batch_items i
  WHERE i.deposit_batch_id = p_deposit_batch_id
    AND i.removed_at IS NULL;

  IF v_item_count = 0 THEN
    RAISE EXCEPTION 'A cash deposit batch must contain at least one active donation.';
  END IF;

  SELECT count(*)
  INTO v_invalid_count
  FROM public.cash_deposit_batch_items i
  JOIN public.donations d ON d.donation_id = i.donation_id
  WHERE i.deposit_batch_id = p_deposit_batch_id
    AND i.removed_at IS NULL
    AND (
      d.provider <> 'cash'
      OR d.status <> 'verified'
      OR d.donor_kind NOT IN ('identified', 'anonymous')
      OR d.amount_cents IS NULL
      OR d.amount_cents <= 0
      OR d.amount_cents <> i.amount_cents
    );

  IF v_invalid_count > 0 THEN
    RAISE EXCEPTION
      'Cash deposit batch % contains % donation(s) that are no longer deposit eligible or whose amount changed.',
      p_deposit_batch_id, v_invalid_count;
  END IF;

  IF NULLIF(btrim(COALESCE(p_deposit_slip_number, v_batch.deposit_slip_number)), '') IS NULL THEN
    RAISE EXCEPTION 'A deposit slip number is required to prepare a cash deposit.';
  END IF;

  IF NULLIF(btrim(COALESCE(p_destination_bank_account, v_batch.destination_bank_account)), '') IS NULL THEN
    RAISE EXCEPTION 'A destination bank account is required to prepare a cash deposit.';
  END IF;

  UPDATE public.cash_deposit_batches
  SET
    status = 'prepared',
    deposit_date = COALESCE(p_deposit_date, deposit_date, CURRENT_DATE),
    deposit_slip_number = NULLIF(
      btrim(COALESCE(p_deposit_slip_number, deposit_slip_number)), ''
    ),
    destination_bank_account = NULLIF(
      btrim(COALESCE(p_destination_bank_account, destination_bank_account)), ''
    ),
    prepared_by = p_actor_id,
    prepared_at = now(),
    expected_amount_cents = v_expected_amount,
    notes = COALESCE(NULLIF(btrim(p_notes), ''), notes)
  WHERE deposit_batch_id = p_deposit_batch_id
  RETURNING * INTO v_batch;

  INSERT INTO public.audit_log (actor, action, entity_type, entity_id, details)
  VALUES (
    public.cash_deposit_actor_email(p_actor_id),
    'cash_deposit_batch.prepared',
    'cash_deposit_batch',
    p_deposit_batch_id::text,
    jsonb_build_object(
      'preparer_id', p_actor_id,
      'prepared_at', v_batch.prepared_at,
      'deposit_date', v_batch.deposit_date,
      'deposit_slip_number', v_batch.deposit_slip_number,
      'destination_bank_account', v_batch.destination_bank_account,
      'item_count', v_item_count,
      'expected_amount_cents', v_expected_amount
    )
  );

  RETURN v_batch;
END;
$$;

CREATE OR REPLACE FUNCTION public.cancel_cash_deposit_batch(
  p_deposit_batch_id uuid,
  p_actor_id uuid,
  p_reason text DEFAULT NULL
)
RETURNS public.cash_deposit_batches
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_batch public.cash_deposit_batches%ROWTYPE;
  v_item_ids jsonb;
BEGIN
  SELECT *
  INTO v_batch
  FROM public.cash_deposit_batches
  WHERE deposit_batch_id = p_deposit_batch_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Cash deposit batch % was not found.', p_deposit_batch_id;
  END IF;

  IF v_batch.status NOT IN ('draft', 'prepared') THEN
    RAISE EXCEPTION
      'Only draft or prepared cash deposit batches may be cancelled.';
  END IF;

  IF p_actor_id IS NULL
     OR (p_actor_id <> v_batch.preparer_id AND p_actor_id <> v_batch.prepared_by)
  THEN
    RAISE EXCEPTION
      'Only the cash deposit preparer may cancel this batch.';
  END IF;

  SELECT COALESCE(
    jsonb_agg(jsonb_build_object(
      'deposit_batch_item_id', i.deposit_batch_item_id,
      'donation_id', i.donation_id,
      'amount_cents', i.amount_cents
    ) ORDER BY i.donation_id),
    '[]'::jsonb
  )
  INTO v_item_ids
  FROM public.cash_deposit_batch_items i
  WHERE i.deposit_batch_id = p_deposit_batch_id
    AND i.removed_at IS NULL;

  UPDATE public.cash_deposit_batch_items
  SET
    removed_at = now(),
    removed_by = p_actor_id,
    removal_reason = COALESCE(
      NULLIF(btrim(p_reason), ''),
      'Deposit batch cancelled'
    )
  WHERE deposit_batch_id = p_deposit_batch_id
    AND removed_at IS NULL;

  UPDATE public.cash_deposit_batches
  SET
    status = 'cancelled',
    cancelled_at = now(),
    cancelled_by = p_actor_id,
    expected_amount_cents = 0
  WHERE deposit_batch_id = p_deposit_batch_id
  RETURNING * INTO v_batch;

  INSERT INTO public.audit_log (actor, action, entity_type, entity_id, details)
  VALUES (
    public.cash_deposit_actor_email(p_actor_id),
    'cash_deposit_batch.cancelled',
    'cash_deposit_batch',
    p_deposit_batch_id::text,
    jsonb_build_object(
      'items_released', v_item_ids,
      'reason', NULLIF(btrim(p_reason), '')
    )
  );

  RETURN v_batch;
END;
$$;

CREATE OR REPLACE FUNCTION public.confirm_cash_deposit_batch(
  p_deposit_batch_id uuid,
  p_verifier_id uuid,
  p_actual_amount_cents integer,
  p_deposit_date date DEFAULT NULL,
  p_deposit_slip_number text DEFAULT NULL,
  p_notes text DEFAULT NULL
)
RETURNS public.cash_deposit_batches
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_batch public.cash_deposit_batches%ROWTYPE;
  v_expected_amount integer;
  v_item_count integer;
  v_invalid_count integer;
BEGIN
  PERFORM public.assert_cash_deposit_verifier(p_verifier_id);

  SELECT *
  INTO v_batch
  FROM public.cash_deposit_batches
  WHERE deposit_batch_id = p_deposit_batch_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Cash deposit batch % was not found.', p_deposit_batch_id;
  END IF;

  IF v_batch.status <> 'prepared' THEN
    RAISE EXCEPTION
      'Cash deposit batch % is %, not prepared.',
      p_deposit_batch_id, v_batch.status;
  END IF;

  SELECT count(*), COALESCE(sum(i.amount_cents), 0)
  INTO v_item_count, v_expected_amount
  FROM public.cash_deposit_batch_items i
  WHERE i.deposit_batch_id = p_deposit_batch_id
    AND i.removed_at IS NULL;

  IF v_item_count = 0 THEN
    RAISE EXCEPTION 'A cash deposit batch must contain at least one active donation.';
  END IF;

  SELECT count(*)
  INTO v_invalid_count
  FROM public.cash_deposit_batch_items i
  JOIN public.donations d ON d.donation_id = i.donation_id
  WHERE i.deposit_batch_id = p_deposit_batch_id
    AND i.removed_at IS NULL
    AND (
      d.provider <> 'cash'
      OR d.status <> 'verified'
      OR d.donor_kind NOT IN ('identified', 'anonymous')
      OR d.amount_cents IS NULL
      OR d.amount_cents <= 0
      OR d.amount_cents <> i.amount_cents
    );

  IF v_invalid_count > 0 THEN
    RAISE EXCEPTION
      'Cash deposit batch % contains % donation(s) that are no longer deposit eligible or whose amount changed.',
      p_deposit_batch_id, v_invalid_count;
  END IF;

  IF p_actual_amount_cents IS NULL OR p_actual_amount_cents <= 0 THEN
    RAISE EXCEPTION 'Actual deposited amount must be positive.';
  END IF;

  IF p_actual_amount_cents <> v_expected_amount THEN
    RAISE EXCEPTION
      'Actual deposited amount % does not equal expected deposit amount %.',
      p_actual_amount_cents, v_expected_amount;
  END IF;

  UPDATE public.cash_deposit_batches
  SET
    status = 'confirmed',
    deposit_date = COALESCE(p_deposit_date, deposit_date, CURRENT_DATE),
    deposit_slip_number = NULLIF(
      btrim(COALESCE(p_deposit_slip_number, deposit_slip_number)), ''
    ),
    verifier_id = p_verifier_id,
    expected_amount_cents = v_expected_amount,
    actual_amount_cents = p_actual_amount_cents,
    confirmed_at = now(),
    notes = COALESCE(NULLIF(btrim(p_notes), ''), notes)
  WHERE deposit_batch_id = p_deposit_batch_id
  RETURNING * INTO v_batch;

  INSERT INTO public.audit_log (actor, action, entity_type, entity_id, details)
  VALUES (
    public.cash_deposit_actor_email(p_verifier_id),
    'cash_deposit_batch.confirmed',
    'cash_deposit_batch',
    p_deposit_batch_id::text,
    jsonb_build_object(
      'preparer_id', v_batch.preparer_id,
      'prepared_by', v_batch.prepared_by,
      'prepared_at', v_batch.prepared_at,
      'verifier_id', p_verifier_id,
      'deposit_date', v_batch.deposit_date,
      'deposit_slip_number', v_batch.deposit_slip_number,
      'destination_bank_account', v_batch.destination_bank_account,
      'item_count', v_item_count,
      'expected_amount_cents', v_expected_amount,
      'actual_amount_cents', p_actual_amount_cents,
      'donation_ids', (
        SELECT COALESCE(
          jsonb_agg(i.donation_id ORDER BY i.donation_id),
          '[]'::jsonb
        )
        FROM public.cash_deposit_batch_items i
        WHERE i.deposit_batch_id = p_deposit_batch_id
          AND i.removed_at IS NULL
      )
    )
  );

  RETURN v_batch;
END;
$$;

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
  ORDER BY d.donated_at NULLS LAST, d.created_at, d.donation_id;
$$;

COMMENT ON TABLE public.cash_deposit_batches IS
  'Operational physical cash-deposit batches. Lifecycle is draft -> prepared -> confirmed or cancellation; ERPNext synchronization is separate.';

COMMENT ON TABLE public.cash_deposit_batch_items IS
  'Cash donations assigned to a batch. Removed items are retained as audit history and no longer count toward the batch.';

COMMIT;

SELECT status, count(*)
FROM public.cash_deposit_batches
GROUP BY status
ORDER BY status;
