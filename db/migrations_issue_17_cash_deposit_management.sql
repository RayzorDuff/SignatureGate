-- SignatureGate Issue #17: Cash Deposit Management backend.
--
-- This migration implements the operational cash-deposit lifecycle only.
-- ERPNext / RootedOps synchronization belongs to Issue #18.
--
-- Deposit batches consume verified cash donations by donation_id. Donor identity
-- (individual contributor, organization, anonymous) remains owned by the
-- donation record and is intentionally not duplicated here.
--
-- Lifecycle:
--   draft -> confirmed
--   draft -> cancelled
--
-- Confirmed batches are immutable. Cancelled batches release their donation
-- items back to the cash-on-hand queue.

\set ON_ERROR_STOP on

BEGIN;

DO $$
BEGIN
  IF to_regclass('public.donations') IS NULL THEN
    RAISE EXCEPTION 'Issue #17 requires public.donations.';
  END IF;

  IF to_regclass('public.audit_log') IS NULL THEN
    RAISE EXCEPTION 'Issue #17 requires public.audit_log.';
  END IF;

  IF to_regprocedure('public.set_updated_at()') IS NULL THEN
    RAISE EXCEPTION 'Issue #17 requires public.set_updated_at().';
  END IF;
END
$$;

CREATE TABLE IF NOT EXISTS public.cash_deposit_batches (
  deposit_batch_id uuid PRIMARY KEY DEFAULT public.uuid_generate_v4(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  status text NOT NULL DEFAULT 'draft',

  deposit_date date,
  deposit_slip_number text,

  preparer_id uuid NOT NULL REFERENCES public.members(member_id),
  verifier_id uuid REFERENCES public.members(member_id),

  expected_amount_cents integer NOT NULL DEFAULT 0,
  actual_amount_cents integer,

  confirmed_at timestamptz,
  cancelled_at timestamptz,
  cancelled_by uuid REFERENCES public.members(member_id),

  notes text,

  CONSTRAINT cash_deposit_batches_status_check
    CHECK (status IN ('draft', 'confirmed', 'cancelled')),

  CONSTRAINT cash_deposit_batches_expected_amount_check
    CHECK (expected_amount_cents >= 0),

  CONSTRAINT cash_deposit_batches_actual_amount_check
    CHECK (actual_amount_cents IS NULL OR actual_amount_cents >= 0),

  CONSTRAINT cash_deposit_batches_confirmed_fields_check
    CHECK (
      (status = 'confirmed'
        AND deposit_date IS NOT NULL
        AND NULLIF(btrim(deposit_slip_number), '') IS NOT NULL
        AND verifier_id IS NOT NULL
        AND actual_amount_cents IS NOT NULL
        AND confirmed_at IS NOT NULL)
      OR
      (status <> 'confirmed')
    ),

  CONSTRAINT cash_deposit_batches_cancelled_fields_check
    CHECK (
      (status = 'cancelled'
        AND cancelled_at IS NOT NULL
        AND cancelled_by IS NOT NULL)
      OR
      (status <> 'cancelled')
    ),

  CONSTRAINT cash_deposit_batches_actual_equals_expected_check
    CHECK (
      status <> 'confirmed'
      OR actual_amount_cents = expected_amount_cents
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_cash_deposit_batches_slip_number
  ON public.cash_deposit_batches (lower(btrim(deposit_slip_number)))
  WHERE deposit_slip_number IS NOT NULL
    AND NULLIF(btrim(deposit_slip_number), '') IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_cash_deposit_batches_status_date
  ON public.cash_deposit_batches (status, deposit_date DESC NULLS LAST, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_cash_deposit_batches_preparer
  ON public.cash_deposit_batches (preparer_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_cash_deposit_batches_verifier
  ON public.cash_deposit_batches (verifier_id, confirmed_at DESC);

CREATE TABLE IF NOT EXISTS public.cash_deposit_batch_items (
  deposit_batch_item_id uuid PRIMARY KEY DEFAULT public.uuid_generate_v4(),
  created_at timestamptz NOT NULL DEFAULT now(),

  deposit_batch_id uuid NOT NULL
    REFERENCES public.cash_deposit_batches(deposit_batch_id)
    ON DELETE RESTRICT,

  donation_id uuid NOT NULL
    REFERENCES public.donations(donation_id)
    ON DELETE RESTRICT,

  amount_cents integer NOT NULL,

  CONSTRAINT cash_deposit_batch_items_amount_check
    CHECK (amount_cents > 0)
);

-- A donation can be in at most one live deposit batch. Cancellation removes
-- its items, after which it may legitimately return to Cash on Hand.
CREATE UNIQUE INDEX IF NOT EXISTS uq_cash_deposit_batch_items_donation
  ON public.cash_deposit_batch_items (donation_id);

CREATE INDEX IF NOT EXISTS idx_cash_deposit_batch_items_batch
  ON public.cash_deposit_batch_items (deposit_batch_id, created_at);

CREATE INDEX IF NOT EXISTS idx_cash_deposit_batch_items_donation
  ON public.cash_deposit_batch_items (donation_id);

DROP TRIGGER IF EXISTS trg_cash_deposit_batches_updated_at
  ON public.cash_deposit_batches;
CREATE TRIGGER trg_cash_deposit_batches_updated_at
BEFORE UPDATE ON public.cash_deposit_batches
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

-- Confirmed batches are an accounting/physical-custody fact and may not be
-- edited or deleted. Cancellation is the only supported draft cleanup path.
CREATE OR REPLACE FUNCTION public.prevent_confirmed_cash_deposit_mutation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF OLD.status = 'confirmed' THEN
    RAISE EXCEPTION
      'Confirmed cash deposit batch % is immutable.',
      OLD.deposit_batch_id;
  END IF;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_cash_deposit_batches_immutable
  ON public.cash_deposit_batches;
CREATE TRIGGER trg_cash_deposit_batches_immutable
BEFORE UPDATE OR DELETE ON public.cash_deposit_batches
FOR EACH ROW
EXECUTE FUNCTION public.prevent_confirmed_cash_deposit_mutation();

CREATE OR REPLACE FUNCTION public.prevent_confirmed_cash_deposit_item_mutation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  v_batch_status text;
BEGIN
  SELECT status
  INTO v_batch_status
  FROM public.cash_deposit_batches
  WHERE deposit_batch_id =
    CASE WHEN TG_OP = 'DELETE'
      THEN OLD.deposit_batch_id
      ELSE NEW.deposit_batch_id
    END;

  IF v_batch_status = 'confirmed' THEN
    RAISE EXCEPTION
      'Items in confirmed cash deposit batch % are immutable.',
      CASE WHEN TG_OP = 'DELETE'
        THEN OLD.deposit_batch_id
        ELSE NEW.deposit_batch_id
      END;
  END IF;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_cash_deposit_items_immutable
  ON public.cash_deposit_batch_items;
CREATE TRIGGER trg_cash_deposit_items_immutable
BEFORE UPDATE OR DELETE ON public.cash_deposit_batch_items
FOR EACH ROW
EXECUTE FUNCTION public.prevent_confirmed_cash_deposit_item_mutation();

CREATE OR REPLACE FUNCTION public.cash_deposit_actor_email(p_member_id uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
  SELECT COALESCE(NULLIF(lower(btrim(m.email)), ''), p_member_id::text)
  FROM public.members m
  WHERE m.member_id = p_member_id;
$$;

CREATE OR REPLACE FUNCTION public.assert_cash_deposit_preparer(p_member_id uuid)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF p_member_id IS NULL OR NOT EXISTS (
    SELECT 1
    FROM public.members m
    WHERE m.member_id = p_member_id
      AND m.status = 'active'
      AND m.is_facilitator IS TRUE
  ) THEN
    RAISE EXCEPTION 'An active facilitator is required as cash-deposit preparer.';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.assert_cash_deposit_verifier(p_member_id uuid)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF p_member_id IS NULL OR NOT EXISTS (
    SELECT 1
    FROM public.members m
    WHERE m.member_id = p_member_id
      AND m.status = 'active'
      AND m.is_facilitator IS TRUE
      AND m.is_donations_reviewer IS TRUE
  ) THEN
    RAISE EXCEPTION
      'An active donations reviewer is required as cash-deposit verifier.';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_cash_deposit_batch(
  p_preparer_id uuid,
  p_deposit_date date DEFAULT CURRENT_DATE,
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
BEGIN
  PERFORM public.assert_cash_deposit_preparer(p_preparer_id);

  INSERT INTO public.cash_deposit_batches (
    preparer_id,
    deposit_date,
    deposit_slip_number,
    notes
  )
  VALUES (
    p_preparer_id,
    p_deposit_date,
    NULLIF(btrim(p_deposit_slip_number), ''),
    NULLIF(btrim(p_notes), '')
  )
  RETURNING * INTO v_batch;

  INSERT INTO public.audit_log (
    actor, action, entity_type, entity_id, details
  )
  VALUES (
    public.cash_deposit_actor_email(p_preparer_id),
    'cash_deposit_batch.created',
    'cash_deposit_batch',
    v_batch.deposit_batch_id::text,
    jsonb_build_object(
      'preparer_id', p_preparer_id,
      'deposit_date', v_batch.deposit_date,
      'deposit_slip_number', v_batch.deposit_slip_number
    )
  );

  RETURN v_batch;
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
      'Cash deposit batch % is %, not draft.',
      p_deposit_batch_id, v_batch.status;
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

  IF v_donation.provider <> 'cash' THEN
    RAISE EXCEPTION
      'Donation % is not a cash donation.',
      p_donation_id;
  END IF;

  IF v_donation.status <> 'verified' THEN
    RAISE EXCEPTION
      'Donation % is %, not verified.',
      p_donation_id, v_donation.status;
  END IF;

  IF v_donation.donor_kind NOT IN ('identified', 'anonymous') THEN
    RAISE EXCEPTION
      'Donation % has donor identity %, which is not deposit eligible.',
      p_donation_id, v_donation.donor_kind;
  END IF;

  IF v_donation.amount_cents IS NULL OR v_donation.amount_cents <= 0 THEN
    RAISE EXCEPTION
      'Donation % does not have a positive amount.',
      p_donation_id;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.cash_deposit_batch_items i
    JOIN public.cash_deposit_batches b
      ON b.deposit_batch_id = i.deposit_batch_id
    WHERE i.donation_id = p_donation_id
      AND b.status <> 'cancelled'
  ) THEN
    RAISE EXCEPTION
      'Donation % is already assigned to a non-cancelled deposit batch.',
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
  )
  WHERE b.deposit_batch_id = p_deposit_batch_id;

  INSERT INTO public.audit_log (
    actor, action, entity_type, entity_id, details
  )
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

CREATE OR REPLACE FUNCTION public.remove_cash_deposit_item(
  p_deposit_batch_id uuid,
  p_donation_id uuid,
  p_actor_id uuid
)
RETURNS void
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_batch public.cash_deposit_batches%ROWTYPE;
  v_amount_cents integer;
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
      'Cash deposit batch % is %, not draft.',
      p_deposit_batch_id, v_batch.status;
  END IF;

  IF p_actor_id IS NULL OR p_actor_id <> v_batch.preparer_id THEN
    RAISE EXCEPTION
      'Only the deposit preparer may modify a draft cash deposit batch.';
  END IF;

  SELECT amount_cents
  INTO v_amount_cents
  FROM public.cash_deposit_batch_items
  WHERE deposit_batch_id = p_deposit_batch_id
    AND donation_id = p_donation_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION
      'Donation % is not in cash deposit batch %.',
      p_donation_id, p_deposit_batch_id;
  END IF;

  DELETE FROM public.cash_deposit_batch_items
  WHERE deposit_batch_id = p_deposit_batch_id
    AND donation_id = p_donation_id;

  UPDATE public.cash_deposit_batches b
  SET expected_amount_cents = (
    SELECT COALESCE(sum(i.amount_cents), 0)
    FROM public.cash_deposit_batch_items i
    WHERE i.deposit_batch_id = b.deposit_batch_id
  )
  WHERE b.deposit_batch_id = p_deposit_batch_id;

  INSERT INTO public.audit_log (
    actor, action, entity_type, entity_id, details
  )
  VALUES (
    public.cash_deposit_actor_email(p_actor_id),
    'cash_deposit_batch.item_removed',
    'cash_deposit_batch',
    p_deposit_batch_id::text,
    jsonb_build_object(
      'donation_id', p_donation_id,
      'amount_cents', v_amount_cents
    )
  );
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
  v_donation_ids jsonb;
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
      'Only draft cash deposit batches may be cancelled.';
  END IF;

  IF p_actor_id IS NULL OR p_actor_id <> v_batch.preparer_id THEN
    RAISE EXCEPTION
      'Only the deposit preparer may cancel a draft cash deposit batch.';
  END IF;

  SELECT COALESCE(
    jsonb_agg(i.donation_id ORDER BY i.donation_id),
    '[]'::jsonb
  )
  INTO v_donation_ids
  FROM public.cash_deposit_batch_items i
  WHERE i.deposit_batch_id = p_deposit_batch_id;

  INSERT INTO public.audit_log (
    actor, action, entity_type, entity_id, details
  )
  VALUES (
    public.cash_deposit_actor_email(p_actor_id),
    'cash_deposit_batch.cancelled',
    'cash_deposit_batch',
    p_deposit_batch_id::text,
    jsonb_build_object(
      'donation_ids_released', v_donation_ids,
      'reason', NULLIF(btrim(p_reason), '')
    )
  );

  DELETE FROM public.cash_deposit_batch_items
  WHERE deposit_batch_id = p_deposit_batch_id;

  UPDATE public.cash_deposit_batches
  SET
    status = 'cancelled',
    cancelled_at = now(),
    cancelled_by = p_actor_id,
    expected_amount_cents = 0
  WHERE deposit_batch_id = p_deposit_batch_id
  RETURNING * INTO v_batch;

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

  IF v_batch.status <> 'draft' THEN
    RAISE EXCEPTION
      'Cash deposit batch % is %, not draft.',
      p_deposit_batch_id, v_batch.status;
  END IF;

  SELECT
    count(*),
    COALESCE(sum(i.amount_cents), 0)
  INTO v_item_count, v_expected_amount
  FROM public.cash_deposit_batch_items i
  WHERE i.deposit_batch_id = p_deposit_batch_id;

  IF v_item_count = 0 THEN
    RAISE EXCEPTION 'A cash deposit batch must contain at least one donation.';
  END IF;

  SELECT count(*)
  INTO v_invalid_count
  FROM public.cash_deposit_batch_items i
  JOIN public.donations d ON d.donation_id = i.donation_id
  WHERE i.deposit_batch_id = p_deposit_batch_id
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

  IF NULLIF(btrim(COALESCE(p_deposit_slip_number, v_batch.deposit_slip_number)), '') IS NULL THEN
    RAISE EXCEPTION 'A deposit slip number is required to confirm a cash deposit.';
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

  INSERT INTO public.audit_log (
    actor, action, entity_type, entity_id, details
  )
  VALUES (
    public.cash_deposit_actor_email(p_verifier_id),
    'cash_deposit_batch.confirmed',
    'cash_deposit_batch',
    p_deposit_batch_id::text,
    jsonb_build_object(
      'preparer_id', v_batch.preparer_id,
      'verifier_id', p_verifier_id,
      'deposit_date', v_batch.deposit_date,
      'deposit_slip_number', v_batch.deposit_slip_number,
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
      JOIN public.cash_deposit_batches b
        ON b.deposit_batch_id = i.deposit_batch_id
      WHERE i.donation_id = d.donation_id
        AND b.status <> 'cancelled'
    )
  ORDER BY d.donated_at NULLS LAST, d.created_at, d.donation_id;
$$;

CREATE OR REPLACE FUNCTION public.cash_on_hand_total_cents()
RETURNS bigint
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
  SELECT COALESCE(sum(amount_cents), 0)::bigint
  FROM public.cash_on_hand_donations();
$$;

COMMENT ON TABLE public.cash_deposit_batches IS
  'Operational physical cash-deposit batches. Confirmed batches are immutable; ERPNext synchronization is Issue #18.';

COMMENT ON TABLE public.cash_deposit_batch_items IS
  'Verified cash donations included in a deposit batch. Each donation may belong to at most one non-cancelled batch.';

COMMENT ON FUNCTION public.cash_on_hand_donations() IS
  'Returns verified cash donations that have not been assigned to a confirmed or active draft deposit batch.';

COMMENT ON FUNCTION public.cash_on_hand_total_cents() IS
  'Returns the total verified cash currently held outside confirmed or active draft deposit batches.';

COMMIT;

-- Deployment verification: these invariants must return zero rows.
SELECT donation_id
FROM public.donations d
WHERE d.provider = 'cash'
  AND d.status = 'verified'
  AND d.donor_kind IN ('identified', 'anonymous')
  AND d.amount_cents > 0
  AND EXISTS (
    SELECT 1
    FROM public.cash_deposit_batch_items i
    JOIN public.cash_deposit_batches b
      ON b.deposit_batch_id = i.deposit_batch_id
    WHERE i.donation_id = d.donation_id
      AND b.status <> 'cancelled'
  )
GROUP BY donation_id
HAVING count(*) > 1;
