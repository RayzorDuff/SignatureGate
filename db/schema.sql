--
-- PostgreSQL database dump
--

\restrict NHLVQVgbba0D5IcC8UQcS0GHuAZy5P0xtUsr5yQME14holwVZ63lXkr4ez9d3Ys

-- Dumped from database version 16.13 (Debian 16.13-1.pgdg13+1)
-- Dumped by pg_dump version 16.13 (Debian 16.13-1.pgdg13+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: uuid-ossp; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;


--
-- Name: EXTENSION "uuid-ossp"; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION "uuid-ossp" IS 'generate universally unique identifiers (UUIDs)';


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: cash_deposit_batch_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cash_deposit_batch_items (
    deposit_batch_item_id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    deposit_batch_id uuid NOT NULL,
    donation_id uuid NOT NULL,
    amount_cents integer NOT NULL,
    CONSTRAINT cash_deposit_batch_items_amount_check CHECK ((amount_cents > 0))
);


--
-- Name: TABLE cash_deposit_batch_items; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.cash_deposit_batch_items IS 'Verified cash donations included in a deposit batch. Each donation may belong to at most one non-cancelled batch.';


--
-- Name: add_cash_deposit_item(uuid, uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_cash_deposit_item(p_deposit_batch_id uuid, p_donation_id uuid, p_actor_id uuid) RETURNS public.cash_deposit_batch_items
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: add_donation_payload_to_contributor(uuid, uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_donation_payload_to_contributor(p_contributor_id uuid, p_donation_id uuid, p_source text DEFAULT 'givebutter_review'::text) RETURNS void
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_payload jsonb := COALESCE(public.donation_provider_payload(p_donation_id), '{}'::jsonb);
  v_email text;
  v_phone text;
  v_address jsonb;
  v_provider text;
  v_provider_identity text;
BEGIN
  SELECT d.provider INTO v_provider
  FROM public.donations d
  WHERE d.donation_id = p_donation_id;

  v_email := NULLIF(lower(btrim(COALESCE(
    v_payload->>'email',
    v_payload #>> '{donor,email}',
    v_payload #>> '{supporter,email}',
    v_payload #>> '{payer,email}',
    v_payload #>> '{customer,email}'
  ))), '');

  v_phone := NULLIF(btrim(COALESCE(
    v_payload->>'phone',
    v_payload #>> '{donor,phone}',
    v_payload #>> '{supporter,phone}',
    v_payload #>> '{payer,phone}',
    v_payload #>> '{customer,phone}'
  )), '');

  v_provider_identity := NULLIF(btrim(COALESCE(
    v_payload->>'contact_id',
    v_payload #>> '{donor,id}',
    v_payload #>> '{supporter,id}',
    v_payload #>> '{customer,id}'
  )), '');

  IF v_email IS NOT NULL THEN
    INSERT INTO public.contributor_emails (
      contributor_id, email, is_primary, source, notes
    )
    VALUES (
      p_contributor_id, v_email, true, p_source,
      'Added from donation ' || p_donation_id::text
    )
    ON CONFLICT (contributor_id, email_normalized)
    WHERE status = 'active'
      AND email_normalized IS NOT NULL
      AND email_normalized <> ''
    DO NOTHING;
  END IF;

  IF NULLIF(public.normalize_us_phone(v_phone), '') IS NOT NULL THEN
    INSERT INTO public.contributor_phones (
      contributor_id, phone, is_primary, source, notes
    )
    VALUES (
      p_contributor_id, v_phone, true, p_source,
      'Added from donation ' || p_donation_id::text
    )
    ON CONFLICT (contributor_id, phone_normalized)
    WHERE status = 'active'
      AND phone_normalized IS NOT NULL
      AND phone_normalized <> ''
    DO NOTHING;
  END IF;

  v_address := COALESCE(v_payload->'address', '{}'::jsonb);
  IF NULLIF(btrim(COALESCE(
    v_address->>'address_1',
    v_address->>'line1',
    v_address->>'street',
    v_address->>'street_address'
  )), '') IS NOT NULL THEN
    PERFORM public.upsert_contributor_address(
      p_contributor_id => p_contributor_id,
      p_address_1 => COALESCE(
        v_address->>'address_1',
        v_address->>'line1',
        v_address->>'street',
        v_address->>'street_address'
      ),
      p_address_type => 'mailing',
      p_address_2 => COALESCE(
        v_address->>'address_2',
        v_address->>'line2',
        v_address->>'suite'
      ),
      p_city => v_address->>'city',
      p_state => COALESCE(v_address->>'state', v_address->>'province'),
      p_postal_code => COALESCE(
        v_address->>'zipcode',
        v_address->>'postal_code',
        v_address->>'zip'
      ),
      p_country => COALESCE(NULLIF(v_address->>'country', ''), 'USA'),
      p_is_primary => true,
      p_source => p_source,
      p_notes => 'Added from donation ' || p_donation_id::text
    );
  END IF;

  PERFORM public.add_provider_identity_to_contributor(
    p_contributor_id,
    v_provider,
    v_provider_identity,
    p_source,
    jsonb_build_object('donation_id', p_donation_id)
  );
END;
$$;


--
-- Name: add_provider_identity_to_contributor(uuid, text, text, text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_provider_identity_to_contributor(p_contributor_id uuid, p_provider text, p_provider_identity text, p_source text DEFAULT NULL::text, p_metadata jsonb DEFAULT '{}'::jsonb) RETURNS void
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
BEGIN
  IF NULLIF(btrim(p_provider_identity), '') IS NULL THEN
    RETURN;
  END IF;

  INSERT INTO public.contributor_external_identities (
    contributor_id,
    provider,
    provider_identity,
    source,
    metadata
  )
  VALUES (
    p_contributor_id,
    lower(btrim(p_provider)),
    btrim(p_provider_identity),
    NULLIF(btrim(p_source), ''),
    COALESCE(p_metadata, '{}'::jsonb)
  )
  ON CONFLICT (lower(btrim(provider)), btrim(provider_identity))
  WHERE status = 'active'
  DO UPDATE SET
    metadata = public.contributor_external_identities.metadata || EXCLUDED.metadata,
    source = COALESCE(EXCLUDED.source, public.contributor_external_identities.source);

  IF EXISTS (
    SELECT 1
    FROM public.contributor_external_identities cei
    WHERE lower(btrim(cei.provider)) = lower(btrim(p_provider))
      AND btrim(cei.provider_identity) = btrim(p_provider_identity)
      AND cei.status = 'active'
      AND cei.contributor_id <> p_contributor_id
  ) THEN
    RAISE EXCEPTION 'Provider identity already belongs to another contributor.';
  END IF;
END;
$$;


--
-- Name: assert_cash_deposit_preparer(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assert_cash_deposit_preparer(p_member_id uuid) RETURNS void
    LANGUAGE plpgsql STABLE
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: assert_cash_deposit_verifier(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assert_cash_deposit_verifier(p_member_id uuid) RETURNS void
    LANGUAGE plpgsql STABLE
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: cash_deposit_batches; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cash_deposit_batches (
    deposit_batch_id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    status text DEFAULT 'draft'::text NOT NULL,
    deposit_date date,
    deposit_slip_number text,
    preparer_id uuid NOT NULL,
    verifier_id uuid,
    expected_amount_cents integer DEFAULT 0 NOT NULL,
    actual_amount_cents integer,
    confirmed_at timestamp with time zone,
    cancelled_at timestamp with time zone,
    cancelled_by uuid,
    notes text,
    CONSTRAINT cash_deposit_batches_actual_amount_check CHECK (((actual_amount_cents IS NULL) OR (actual_amount_cents >= 0))),
    CONSTRAINT cash_deposit_batches_actual_equals_expected_check CHECK (((status <> 'confirmed'::text) OR (actual_amount_cents = expected_amount_cents))),
    CONSTRAINT cash_deposit_batches_cancelled_fields_check CHECK ((((status = 'cancelled'::text) AND (cancelled_at IS NOT NULL) AND (cancelled_by IS NOT NULL)) OR (status <> 'cancelled'::text))),
    CONSTRAINT cash_deposit_batches_confirmed_fields_check CHECK ((((status = 'confirmed'::text) AND (deposit_date IS NOT NULL) AND (NULLIF(btrim(deposit_slip_number), ''::text) IS NOT NULL) AND (verifier_id IS NOT NULL) AND (actual_amount_cents IS NOT NULL) AND (confirmed_at IS NOT NULL)) OR (status <> 'confirmed'::text))),
    CONSTRAINT cash_deposit_batches_expected_amount_check CHECK ((expected_amount_cents >= 0)),
    CONSTRAINT cash_deposit_batches_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'confirmed'::text, 'cancelled'::text])))
);


--
-- Name: TABLE cash_deposit_batches; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.cash_deposit_batches IS 'Operational physical cash-deposit batches. Confirmed batches are immutable; ERPNext synchronization is Issue #18.';


--
-- Name: cancel_cash_deposit_batch(uuid, uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cancel_cash_deposit_batch(p_deposit_batch_id uuid, p_actor_id uuid, p_reason text DEFAULT NULL::text) RETURNS public.cash_deposit_batches
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: cash_deposit_actor_email(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cash_deposit_actor_email(p_member_id uuid) RETURNS text
    LANGUAGE sql STABLE
    SET search_path TO 'public', 'pg_temp'
    AS $$
  SELECT COALESCE(NULLIF(lower(btrim(m.email)), ''), p_member_id::text)
  FROM public.members m
  WHERE m.member_id = p_member_id;
$$;


--
-- Name: cash_on_hand_donations(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cash_on_hand_donations() RETURNS TABLE(donation_id uuid, donated_at timestamp with time zone, amount_cents integer, currency text, donor_kind text, member_id uuid, contributor_id uuid, notes text)
    LANGUAGE sql STABLE
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: FUNCTION cash_on_hand_donations(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.cash_on_hand_donations() IS 'Returns verified cash donations that have not been assigned to a confirmed or active draft deposit batch.';


--
-- Name: cash_on_hand_total_cents(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cash_on_hand_total_cents() RETURNS bigint
    LANGUAGE sql STABLE
    SET search_path TO 'public', 'pg_temp'
    AS $$
  SELECT COALESCE(sum(amount_cents), 0)::bigint
  FROM public.cash_on_hand_donations();
$$;


--
-- Name: FUNCTION cash_on_hand_total_cents(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.cash_on_hand_total_cents() IS 'Returns the total verified cash currently held outside confirmed or active draft deposit batches.';


--
-- Name: check_linked_person_identity(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.check_linked_person_identity() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.contributor_member_links cml
    JOIN public.members m ON m.member_id = cml.member_id
    JOIN public.contributors c ON c.contributor_id = cml.contributor_id
    WHERE cml.status = 'active' AND m.person_id <> c.person_id
  ) THEN
    RAISE EXCEPTION 'An active contributor/member link crosses two people.';
  END IF;
  RETURN NULL;
END $$;


--
-- Name: confirm_cash_deposit_batch(uuid, uuid, integer, date, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.confirm_cash_deposit_batch(p_deposit_batch_id uuid, p_verifier_id uuid, p_actual_amount_cents integer, p_deposit_date date DEFAULT NULL::date, p_deposit_slip_number text DEFAULT NULL::text, p_notes text DEFAULT NULL::text) RETURNS public.cash_deposit_batches
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: create_cash_deposit_batch(uuid, date, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_cash_deposit_batch(p_preparer_id uuid, p_deposit_date date DEFAULT CURRENT_DATE, p_deposit_slip_number text DEFAULT NULL::text, p_notes text DEFAULT NULL::text) RETURNS public.cash_deposit_batches
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: contributors; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contributors (
    contributor_id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    contributor_type text NOT NULL,
    status text DEFAULT 'active'::text NOT NULL,
    source text,
    notes text,
    merged_into_contributor_id uuid,
    archived_at timestamp with time zone,
    archived_by uuid,
    archive_reason text,
    person_id uuid,
    organization_id uuid,
    CONSTRAINT contributors_merge_check CHECK ((((status = 'merged'::text) AND (merged_into_contributor_id IS NOT NULL)) OR ((status <> 'merged'::text) AND (merged_into_contributor_id IS NULL)))),
    CONSTRAINT contributors_not_self_merged_check CHECK (((merged_into_contributor_id IS NULL) OR (merged_into_contributor_id <> contributor_id))),
    CONSTRAINT contributors_party_identity_check CHECK ((((contributor_type = 'individual'::text) AND (person_id IS NOT NULL) AND (organization_id IS NULL)) OR ((contributor_type = 'organization'::text) AND (organization_id IS NOT NULL) AND (person_id IS NULL)))),
    CONSTRAINT contributors_status_check CHECK ((status = ANY (ARRAY['active'::text, 'archived'::text, 'merged'::text]))),
    CONSTRAINT contributors_type_check CHECK ((contributor_type = ANY (ARRAY['individual'::text, 'organization'::text])))
);


--
-- Name: TABLE contributors; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.contributors IS 'Donation contributor identities independent of membership; may be individuals or organizations.';


--
-- Name: COLUMN contributors.person_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.contributors.person_id IS 'Individual donor party linked to a person; null for organization donors.';


--
-- Name: create_contributor_from_pending_donation(uuid, uuid, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_contributor_from_pending_donation(p_donation_id uuid, p_reviewer_id uuid, p_contributor_type text DEFAULT 'individual'::text, p_organization_name text DEFAULT NULL::text, p_review_notes text DEFAULT NULL::text) RETURNS public.contributors
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_payload jsonb;
  v_first_name text;
  v_last_name text;
  v_email text;
  v_organization_name text;
  v_display_name text;
  v_contributor public.contributors%ROWTYPE;
  v_person_id uuid;
  v_organization_id uuid;
BEGIN
  IF p_reviewer_id IS NULL OR NOT EXISTS (
    SELECT 1
    FROM public.members m
    WHERE m.member_id = p_reviewer_id
      AND m.status = 'active'
      AND m.is_facilitator IS TRUE
      AND m.is_donations_reviewer IS TRUE
  ) THEN
    RAISE EXCEPTION 'An active donations reviewer is required.';
  END IF;

  IF p_contributor_type NOT IN ('individual', 'organization') THEN
    RAISE EXCEPTION 'Contributor type must be individual or organization.';
  END IF;

  PERFORM 1
  FROM public.donations d
  WHERE d.donation_id = p_donation_id
    AND d.provider <> 'cash'
    AND d.donor_kind = 'unresolved'
    AND d.status = 'pending_review'
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Only an unresolved provider donation can create a contributor.';
  END IF;

  v_payload := COALESCE(public.donation_provider_payload(p_donation_id), '{}'::jsonb);
  v_first_name := NULLIF(btrim(COALESCE(
    v_payload->>'first_name',
    v_payload #>> '{donor,first_name}',
    v_payload #>> '{supporter,first_name}'
  )), '');
  v_last_name := NULLIF(btrim(COALESCE(
    v_payload->>'last_name',
    v_payload #>> '{donor,last_name}',
    v_payload #>> '{supporter,last_name}'
  )), '');
  v_email := NULLIF(lower(btrim(COALESCE(
    v_payload->>'email',
    v_payload #>> '{donor,email}',
    v_payload #>> '{supporter,email}'
  ))), '');
  v_organization_name := NULLIF(btrim(COALESCE(
    p_organization_name,
    v_payload->>'organization_name',
    v_payload->>'company_name',
    v_payload->>'company',
    v_payload->>'business_name',
    v_payload #>> '{donor,company}',
    v_payload #>> '{supporter,company}'
  )), '');

  IF p_contributor_type = 'organization' AND v_organization_name IS NULL THEN
    RAISE EXCEPTION
      'The provider payload has no organization name; enter or correct it before creating an organization contributor.';
  END IF;

  v_display_name := CASE
    WHEN p_contributor_type = 'organization' THEN v_organization_name
    ELSE COALESCE(
      NULLIF(btrim(concat_ws(' ', v_first_name, v_last_name)), ''),
      v_email
    )
  END;

  IF v_display_name IS NULL THEN
    RAISE EXCEPTION 'The provider payload does not contain enough contributor identity.';
  END IF;

  IF p_contributor_type = 'individual' THEN
    INSERT INTO public.people (display_name, first_name, last_name)
    VALUES (v_display_name, v_first_name, v_last_name)
    RETURNING person_id INTO v_person_id;
  ELSE
    INSERT INTO public.organizations (organization_name)
    VALUES (v_organization_name)
    RETURNING organization_id INTO v_organization_id;
  END IF;
  INSERT INTO public.contributors
    (contributor_type, person_id, organization_id, status, source, notes)
  VALUES (p_contributor_type, v_person_id, v_organization_id, 'active',
    'givebutter_review', 'Created from pending donation ' || p_donation_id::text)
  RETURNING * INTO v_contributor;

  PERFORM public.resolve_pending_donation(
    p_donation_id,
    p_reviewer_id,
    v_contributor.contributor_id,
    p_review_notes
  );

  INSERT INTO public.audit_log (actor, action, entity_type, entity_id, details)
  SELECT
    reviewer.email,
    'contributor.created_from_donation',
    'contributor',
    v_contributor.contributor_id::text,
    jsonb_build_object(
      'donation_id', p_donation_id,
      'contributor_type', p_contributor_type,
      'reviewer_id', p_reviewer_id
    )
  FROM public.members reviewer
  WHERE reviewer.member_id = p_reviewer_id;

  RETURN v_contributor;
END;
$$;


--
-- Name: create_member_from_intake(text, text, text, text, date, text, boolean, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_member_from_intake(p_first_name text, p_last_name text, p_email text DEFAULT NULL::text, p_phone text DEFAULT NULL::text, p_date_of_birth date DEFAULT NULL::date, p_notes text DEFAULT NULL::text, p_is_facilitator boolean DEFAULT false, p_created_by_facilitator_id uuid DEFAULT NULL::uuid) RETURNS TABLE(member_id uuid, duplicate_blocked boolean)
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_first_name text := NULLIF(btrim(p_first_name), '');
  v_last_name text := NULLIF(btrim(p_last_name), '');
  v_email text := NULLIF(lower(btrim(p_email)), '');
  v_phone text := NULLIF(btrim(p_phone), '');
  v_phone_normalized text :=
    NULLIF(public.normalize_us_phone(p_phone), '');
  v_member_id uuid;
  v_person_id uuid;
BEGIN
  IF v_first_name IS NULL OR v_last_name IS NULL THEN
    RAISE EXCEPTION 'First and last name are required.';
  END IF;

  -- Intake volume is low. Serialize the duplicate-check/insert section across
  -- the member and contact tables so a concurrent member or contact insert
  -- cannot race the final exact-email or exact-phone check.
  LOCK TABLE
    public.members,
    public.people,
    public.member_emails,
    public.member_phones
  IN SHARE ROW EXCLUSIVE MODE;

  IF (
    v_email IS NOT NULL
    AND (
      EXISTS (
        SELECT 1
        FROM public.members m
        WHERE m.status = 'active'
          AND lower(btrim(m.email)) = v_email
      )
      OR EXISTS (
        SELECT 1
        FROM public.member_emails me
        JOIN public.members m
          ON m.member_id = me.member_id
        WHERE me.email_normalized = v_email
          AND COALESCE(me.status, 'active') = 'active'
          AND m.status = 'active'
      )
    )
  )
  OR (
    v_phone_normalized IS NOT NULL
    AND (
      EXISTS (
        SELECT 1
        FROM public.member_phones mp
        JOIN public.members m
          ON m.member_id = mp.member_id
        WHERE mp.phone_normalized = v_phone_normalized
          AND COALESCE(mp.status, 'active') = 'active'
          AND m.status = 'active'
      )
      OR EXISTS (
        SELECT 1
        FROM public.members m
        WHERE m.status = 'active'
          AND public.normalize_us_phone(m.phone) =
              v_phone_normalized
      )
    )
  )
  OR (
    p_date_of_birth IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM public.members m
      JOIN public.people p ON p.person_id = m.person_id
      WHERE m.status = 'active'
        AND lower(btrim(p.first_name)) =
            lower(v_first_name)
        AND lower(btrim(p.last_name)) =
            lower(v_last_name)
        AND p.date_of_birth = p_date_of_birth
    )
  )
  THEN
    member_id := NULL;
    duplicate_blocked := TRUE;
    RETURN NEXT;
    RETURN;
  END IF;

  BEGIN
    INSERT INTO public.people (display_name, first_name, last_name, date_of_birth)
    VALUES (concat_ws(' ', v_first_name, v_last_name),
      v_first_name, v_last_name, p_date_of_birth)
    RETURNING person_id INTO v_person_id;
    INSERT INTO public.members AS m
      (person_id, email, phone, notes, is_facilitator, created_by_facilitator_id)
    VALUES (v_person_id, v_email, v_phone, NULLIF(btrim(p_notes), ''),
      COALESCE(p_is_facilitator, false), p_created_by_facilitator_id)
    RETURNING m.member_id INTO v_member_id;
  EXCEPTION
    WHEN unique_violation THEN
      member_id := NULL;
      duplicate_blocked := TRUE;
      RETURN NEXT;
      RETURN;
  END;

  member_id := v_member_id;
  duplicate_blocked := FALSE;
  RETURN NEXT;
END;
$$;


--
-- Name: FUNCTION create_member_from_intake(p_first_name text, p_last_name text, p_email text, p_phone text, p_date_of_birth date, p_notes text, p_is_facilitator boolean, p_created_by_facilitator_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.create_member_from_intake(p_first_name text, p_last_name text, p_email text, p_phone text, p_date_of_birth date, p_notes text, p_is_facilitator boolean, p_created_by_facilitator_id uuid) IS 'Serializes Intake duplicate detection and creation; blocks exact active email, exact active phone, and exact name-plus-date-of-birth matches without exposing the matching member.';


--
-- Name: members; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.members (
    member_id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    status text DEFAULT 'active'::text NOT NULL,
    email text,
    phone text,
    notes text,
    is_facilitator boolean DEFAULT false NOT NULL,
    is_document_reviewer boolean DEFAULT false NOT NULL,
    created_by_facilitator_id uuid,
    is_donations_reviewer boolean DEFAULT false NOT NULL,
    person_id uuid NOT NULL,
    membership_ended_at timestamp with time zone,
    membership_ended_by text,
    membership_end_reason text
);


--
-- Name: COLUMN members.is_donations_reviewer; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.members.is_donations_reviewer IS 'If true, facilitator can view/select all members for donation intake and can verify/review cash donations.';


--
-- Name: COLUMN members.person_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.members.person_id IS 'Member-specific record for this person; historical member_id references remain valid.';


--
-- Name: COLUMN members.membership_ended_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.members.membership_ended_at IS 'When an active membership was ended through the Issue #19 directory workflow; member ID and history remain.';


--
-- Name: create_member_from_pending_donation(uuid, uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_member_from_pending_donation(p_donation_id uuid, p_reviewer_id uuid, p_review_notes text DEFAULT NULL::text) RETURNS public.members
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_payload jsonb;
  v_contributor public.contributors%ROWTYPE;
  v_first_name text;
  v_last_name text;
  v_member public.members%ROWTYPE;
  v_member_id uuid;
  v_duplicate_blocked boolean;
BEGIN
  SELECT *
  INTO v_contributor
  FROM public.create_contributor_from_pending_donation(
    p_donation_id,
    p_reviewer_id,
    'individual',
    NULL,
    p_review_notes
  );

  SELECT p.first_name, p.last_name INTO v_first_name, v_last_name
  FROM public.people p WHERE p.person_id = v_contributor.person_id;

  v_payload := COALESCE(public.donation_provider_payload(p_donation_id), '{}'::jsonb);

  SELECT created.member_id, created.duplicate_blocked
  INTO v_member_id, v_duplicate_blocked
  FROM public.create_member_from_intake(
    p_first_name => v_first_name,
    p_last_name => v_last_name,
    p_email => COALESCE(
      v_payload->>'email',
      v_payload #>> '{donor,email}',
      v_payload #>> '{supporter,email}'
    ),
    p_phone => COALESCE(
      v_payload->>'phone',
      v_payload #>> '{donor,phone}',
      v_payload #>> '{supporter,phone}'
    ),
    p_date_of_birth => NULL,
    p_notes => 'Created from pending donation ' || p_donation_id::text,
    p_is_facilitator => false,
    p_created_by_facilitator_id => p_reviewer_id
  ) created;

  IF COALESCE(v_duplicate_blocked, false) OR v_member_id IS NULL THEN
    RAISE EXCEPTION
      'Member creation was blocked by an existing identity. Resolve the donation to the existing member/contributor instead.';
  END IF;

  PERFORM public.link_contributor_to_member(
    v_contributor.contributor_id,
    v_member_id,
    p_reviewer_id,
    'Member created from pending donation ' || p_donation_id::text
  );

  INSERT INTO public.member_emails (
    member_id,
    email,
    is_primary,
    is_verified,
    source,
    notes
  )
  SELECT
    v_member_id,
    ce.email,
    ce.is_primary,
    ce.is_verified,
    'contributor_promotion',
    'Copied from contributor ' || v_contributor.contributor_id::text
  FROM public.contributor_emails ce
  WHERE ce.contributor_id = v_contributor.contributor_id
    AND ce.status = 'active'
  ON CONFLICT (email_normalized)
  WHERE email_normalized IS NOT NULL
    AND email_normalized <> ''
    AND status = 'active'
  DO NOTHING;

  INSERT INTO public.member_phones (
    member_id,
    phone,
    is_primary,
    is_verified,
    source,
    notes
  )
  SELECT
    v_member_id,
    cp.phone,
    cp.is_primary,
    cp.is_verified,
    'contributor_promotion',
    'Copied from contributor ' || v_contributor.contributor_id::text
  FROM public.contributor_phones cp
  WHERE cp.contributor_id = v_contributor.contributor_id
    AND cp.status = 'active'
    AND NOT EXISTS (
      SELECT 1
      FROM public.member_phones mp
      WHERE mp.member_id = v_member_id
        AND mp.phone_normalized = cp.phone_normalized
        AND mp.status = 'active'
    );

  PERFORM public.upsert_member_address(
    p_member_id => v_member_id,
    p_address_1 => ca.address_1,
    p_address_type => COALESCE(NULLIF(ca.address_type, ''), 'home'),
    p_address_2 => ca.address_2,
    p_city => ca.city,
    p_state => ca.state,
    p_postal_code => ca.postal_code,
    p_country => ca.country,
    p_is_primary => ca.is_primary,
    p_source => 'contributor_promotion',
    p_notes => 'Copied from contributor ' || v_contributor.contributor_id::text
  )
  FROM public.contributor_addresses ca
  WHERE ca.contributor_id = v_contributor.contributor_id
    AND ca.status = 'active'
    AND NULLIF(btrim(ca.address_1), '') IS NOT NULL;

  SELECT * INTO v_member
  FROM public.members m
  WHERE m.member_id = v_member_id;

  RETURN v_member;
END;
$$;


--
-- Name: donation_provider_payload(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.donation_provider_payload(p_donation_id uuid) RETURNS jsonb
    LANGUAGE sql STABLE
    SET search_path TO 'public', 'pg_temp'
    AS $$
  SELECT COALESCE(
    al.details->'raw'->'data',
    al.details->'raw'->'payload',
    al.details->'raw'->'transaction',
    al.details->'raw',
    '{}'::jsonb
  )
  FROM public.audit_log al
  WHERE al.entity_type = 'donation'
    AND al.entity_id = p_donation_id::text
    AND al.details ? 'raw'
  ORDER BY al.created_at DESC, al.audit_log_id DESC
  LIMIT 1;
$$;


--
-- Name: donation_set_donor_kind(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.donation_set_donor_kind() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_linked_member_id uuid;
BEGIN
  -- Temporary compatibility for an Appsmith or n8n deployment that is still
  -- sending the Issue #17 value during a staggered rollout.
  IF NEW.donor_kind = 'member' THEN
    NEW.donor_kind := 'identified';
  END IF;

  IF NEW.contributor_id IS NULL AND NEW.member_id IS NOT NULL THEN
    NEW.contributor_id := public.ensure_member_contributor(NEW.member_id);
    NEW.donor_kind := 'identified';
  END IF;

  IF NEW.contributor_id IS NOT NULL THEN
    SELECT cml.member_id
    INTO v_linked_member_id
    FROM public.contributor_member_links cml
    WHERE cml.contributor_id = NEW.contributor_id
      AND cml.status = 'active'
    LIMIT 1;

    IF NEW.member_id IS NULL THEN
      NEW.member_id := v_linked_member_id;
    ELSIF v_linked_member_id IS NULL OR NEW.member_id <> v_linked_member_id THEN
      RAISE EXCEPTION
        'Donation member % is not the active member linked to contributor %.',
        NEW.member_id,
        NEW.contributor_id;
    END IF;

    NEW.donor_kind := 'identified';
  ELSIF NEW.donor_kind IS NULL THEN
    NEW.donor_kind := CASE
      WHEN NEW.provider = 'cash' THEN NULL
      ELSE 'unresolved'
    END;
  END IF;

  IF NEW.provider = 'cash' AND NEW.donor_kind IS NULL THEN
    RAISE EXCEPTION
      'Cash donations require an identified contributor or explicit anonymous identity.';
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: enqueue_listmonk_email_sync(uuid, text, text, text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.enqueue_listmonk_email_sync(p_member_email_id uuid, p_event_type text, p_source text DEFAULT 'signaturegate'::text, p_actor text DEFAULT NULL::text, p_details jsonb DEFAULT '{}'::jsonb) RETURNS uuid
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_email public.member_emails%ROWTYPE;
  v_queue_id uuid;
  v_action text;
BEGIN
  IF p_event_type NOT IN ('subscribe', 'unsubscribe') THEN
    RAISE EXCEPTION 'Unsupported listmonk sync event_type: %', p_event_type;
  END IF;

  SELECT * INTO v_email
  FROM public.member_emails
  WHERE member_email_id = p_member_email_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'member_email_id % not found', p_member_email_id;
  END IF;

  IF v_email.email_normalized IS NULL OR v_email.email_normalized = '' THEN
    RAISE EXCEPTION 'member_email_id % has no normalized email', p_member_email_id;
  END IF;

  INSERT INTO public.listmonk_sync_queue (
    member_email_id,
    email_normalized,
    listmonk_list_id,
    event_type,
    source,
    actor,
    details
  ) VALUES (
    v_email.member_email_id,
    v_email.email_normalized,
    v_email.listmonk_list_id,
    p_event_type,
    COALESCE(NULLIF(p_source, ''), 'signaturegate'),
    NULLIF(lower(btrim(p_actor)), ''),
    COALESCE(p_details, '{}'::jsonb)
  )
  RETURNING listmonk_sync_queue_id INTO v_queue_id;

  v_action := CASE p_event_type
    WHEN 'subscribe' THEN 'mailing.subscribe_queued'
    ELSE 'mailing.unsubscribe_queued'
  END;

  INSERT INTO public.audit_log (actor, action, entity_type, entity_id, details)
  VALUES (
    NULLIF(lower(btrim(p_actor)), ''),
    v_action,
    'member_email',
    v_email.member_email_id::text,
    jsonb_build_object(
      'queue_id', v_queue_id,
      'email', v_email.email,
      'email_normalized', v_email.email_normalized,
      'member_id', v_email.member_id,
      'source', COALESCE(NULLIF(p_source, ''), 'signaturegate'),
      'event_type', p_event_type,
      'details', COALESCE(p_details, '{}'::jsonb)
    )
  );

  UPDATE public.member_emails
  SET listmonk_sync_status = 'pending',
      listmonk_sync_error = NULL,
      updated_at = now()
  WHERE member_email_id = v_email.member_email_id;

  RETURN v_queue_id;
END;
$$;


--
-- Name: ensure_member_contributor(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ensure_member_contributor(p_member_id uuid) RETURNS uuid
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_contributor_id uuid;
  v_member public.member_profiles%ROWTYPE;
BEGIN
  IF p_member_id IS NULL THEN
    RAISE EXCEPTION 'A member is required.';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(p_member_id::text, 190019));

  SELECT cml.contributor_id
  INTO v_contributor_id
  FROM public.contributor_member_links cml
  JOIN public.contributors c ON c.contributor_id = cml.contributor_id
  JOIN public.members m ON m.member_id = cml.member_id
  WHERE cml.member_id = p_member_id
    AND (
      (cml.status = 'active' AND c.status = 'active')
      OR
      (m.status <> 'active' AND cml.status = 'ended' AND c.status = 'archived')
    )
  ORDER BY CASE WHEN cml.status = 'active' THEN 0 ELSE 1 END, cml.linked_at DESC
  LIMIT 1;

  IF v_contributor_id IS NOT NULL THEN
    RETURN v_contributor_id;
  END IF;

  SELECT *
  INTO v_member
  FROM public.member_profiles m
  WHERE m.member_id = p_member_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Member % was not found.', p_member_id;
  END IF;

  -- A person may already have a contributor from an earlier, ended membership
  -- link. Reuse that role instead of violating the unique person identity.
  SELECT c.contributor_id INTO v_contributor_id
  FROM public.contributors c
  WHERE c.person_id = v_member.person_id
    AND c.status = 'active';
  IF FOUND THEN
    IF v_member.status <> 'active' THEN
      RAISE EXCEPTION 'Review the existing contributor for inactive member %.', p_member_id;
    END IF;
    INSERT INTO public.contributor_member_links
      (contributor_id, member_id, status, link_reason)
    VALUES (v_contributor_id, p_member_id, 'active',
      'Re-linked existing contributor to member for Issue #19');
    RETURN v_contributor_id;
  END IF;

  INSERT INTO public.contributors (contributor_type, person_id, status, source, notes)
  VALUES ('individual', v_member.person_id,
    CASE WHEN v_member.status = 'active' THEN 'active' ELSE 'archived' END,
    'member_backfill', 'Created from member identity for Issue #19')
  RETURNING contributor_id INTO v_contributor_id;

  -- Historical donations can reference inactive members. Their contributor is
  -- retained as archived but still receives a historical ended link.
  IF v_member.status = 'active' THEN
    INSERT INTO public.contributor_member_links (
      contributor_id,
      member_id,
      status,
      link_reason
    )
    VALUES (
      v_contributor_id,
      p_member_id,
      'active',
      'Member contributor backfill for Issue #19'
    );
  ELSE
    INSERT INTO public.contributor_member_links (
      contributor_id,
      member_id,
      status,
      link_reason,
      ended_at,
      end_reason
    )
    VALUES (
      v_contributor_id,
      p_member_id,
      'ended',
      'Member contributor backfill for Issue #19',
      now(),
      'Member was not active when contributor identity was created'
    );
  END IF;

  INSERT INTO public.contributor_emails (
    contributor_id, email, is_primary, is_verified, source, notes
  )
  SELECT
    v_contributor_id,
    me.email,
    me.is_primary,
    me.is_verified,
    'member_backfill',
    'Copied from member email for Issue #19'
  FROM public.member_emails me
  WHERE me.member_id = p_member_id
    AND me.status = 'active'
    AND NULLIF(btrim(me.email), '') IS NOT NULL
  ON CONFLICT (contributor_id, email_normalized)
  WHERE status = 'active'
    AND email_normalized IS NOT NULL
    AND email_normalized <> ''
  DO NOTHING;

  IF NOT EXISTS (
    SELECT 1 FROM public.contributor_emails ce
    WHERE ce.contributor_id = v_contributor_id
      AND ce.status = 'active'
  ) AND NULLIF(btrim(v_member.email), '') IS NOT NULL THEN
    INSERT INTO public.contributor_emails (
      contributor_id, email, is_primary, source, notes
    )
    VALUES (
      v_contributor_id,
      v_member.email,
      true,
      'members.email',
      'Copied from member compatibility email for Issue #19'
    )
    ON CONFLICT (contributor_id, email_normalized)
    WHERE status = 'active'
      AND email_normalized IS NOT NULL
      AND email_normalized <> ''
    DO NOTHING;
  END IF;

  INSERT INTO public.contributor_phones (
    contributor_id, phone, is_primary, is_verified, source, notes
  )
  SELECT
    v_contributor_id,
    mp.phone,
    mp.is_primary,
    mp.is_verified,
    'member_backfill',
    'Copied from member phone for Issue #19'
  FROM public.member_phones mp
  WHERE mp.member_id = p_member_id
    AND mp.status = 'active'
    AND NULLIF(public.normalize_us_phone(mp.phone), '') IS NOT NULL
  ON CONFLICT (contributor_id, phone_normalized)
  WHERE status = 'active'
    AND phone_normalized IS NOT NULL
    AND phone_normalized <> ''
  DO NOTHING;

  IF NOT EXISTS (
    SELECT 1 FROM public.contributor_phones cp
    WHERE cp.contributor_id = v_contributor_id
      AND cp.status = 'active'
  ) AND NULLIF(public.normalize_us_phone(v_member.phone), '') IS NOT NULL THEN
    INSERT INTO public.contributor_phones (
      contributor_id, phone, is_primary, source, notes
    )
    VALUES (
      v_contributor_id,
      v_member.phone,
      true,
      'members.phone',
      'Copied from member compatibility phone for Issue #19'
    )
    ON CONFLICT (contributor_id, phone_normalized)
    WHERE status = 'active'
      AND phone_normalized IS NOT NULL
      AND phone_normalized <> ''
    DO NOTHING;
  END IF;

  INSERT INTO public.contributor_addresses (
    contributor_id,
    address_type,
    address_1,
    address_2,
    city,
    state,
    postal_code,
    country,
    is_primary,
    source,
    notes
  )
  SELECT
    v_contributor_id,
    ma.address_type,
    ma.address_1,
    ma.address_2,
    ma.city,
    ma.state,
    ma.postal_code,
    ma.country,
    ma.is_primary,
    'member_backfill',
    'Copied from member address for Issue #19'
  FROM public.member_addresses ma
  WHERE ma.member_id = p_member_id
    AND ma.status = 'active'
  ON CONFLICT (contributor_id, address_identity_key)
  WHERE status = 'active'
    AND address_identity_key IS NOT NULL
    AND address_identity_key <> ''
  DO NOTHING;

  RETURN v_contributor_id;
END;
$$;


--
-- Name: FUNCTION ensure_member_contributor(p_member_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.ensure_member_contributor(p_member_id uuid) IS 'Returns the active contributor linked to a member or creates one with copied active contact data.';


--
-- Name: ingest_provider_donation(text, text, integer, text, timestamp with time zone, text, jsonb, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ingest_provider_donation(p_provider text, p_provider_reference text, p_amount_cents integer, p_currency text, p_donated_at timestamp with time zone, p_notes text, p_raw jsonb, p_email text DEFAULT NULL::text, p_phone text DEFAULT NULL::text, p_provider_identity text DEFAULT NULL::text) RETURNS TABLE(donation_id uuid, contributor_id uuid, member_id uuid, donor_kind text, status text, match_method text, match_score integer, inserted boolean)
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_provider text := NULLIF(lower(btrim(p_provider)), '');
  v_reference text := NULLIF(btrim(p_provider_reference), '');
  v_match record;
  v_donation public.donations%ROWTYPE;
  v_inserted boolean := false;
BEGIN
  IF v_provider IS NULL OR v_provider = 'cash' THEN
    RAISE EXCEPTION 'Provider ingestion requires a non-cash provider.';
  END IF;
  IF v_reference IS NULL THEN
    RAISE EXCEPTION 'Provider reference is required.';
  END IF;

  SELECT * INTO v_match
  FROM public.match_contributor_identity(
    v_provider,
    p_provider_identity,
    p_email,
    p_phone
  )
  LIMIT 1;

  INSERT INTO public.donations (
    contributor_id,
    member_id,
    donor_kind,
    provider,
    provider_reference,
    amount_cents,
    currency,
    donated_at,
    notes,
    status
  )
  VALUES (
    v_match.contributor_id,
    v_match.member_id,
    CASE WHEN v_match.contributor_id IS NULL THEN 'unresolved' ELSE 'identified' END,
    v_provider,
    v_reference,
    p_amount_cents,
    COALESCE(NULLIF(upper(btrim(p_currency)), ''), 'USD'),
    p_donated_at,
    NULLIF(btrim(p_notes), ''),
    CASE WHEN v_match.contributor_id IS NULL THEN 'pending_review' ELSE 'verified' END
  )
  ON CONFLICT (provider, provider_reference)
  WHERE provider_reference IS NOT NULL
    AND btrim(provider_reference) <> ''
  DO NOTHING
  RETURNING * INTO v_donation;

  IF FOUND THEN
    v_inserted := true;

    INSERT INTO public.audit_log (actor, action, entity_type, entity_id, details)
    VALUES (
      v_provider,
      CASE
        WHEN v_donation.donor_kind = 'unresolved' THEN 'donation.pending_review'
        ELSE 'donation.verified'
      END,
      'donation',
      v_donation.donation_id::text,
      jsonb_build_object(
        'raw', COALESCE(p_raw, '{}'::jsonb),
        'matched_contributor_id', v_donation.contributor_id,
        'matched_member_id', v_donation.member_id,
        'match_method', v_match.match_method,
        'match_score', v_match.match_score,
        'email', NULLIF(lower(btrim(p_email)), ''),
        'phone_digits', NULLIF(public.normalize_us_phone(p_phone), ''),
        'provider_identity', NULLIF(btrim(p_provider_identity), '')
      )
    );

    IF v_donation.contributor_id IS NOT NULL THEN
      PERFORM public.add_provider_identity_to_contributor(
        v_donation.contributor_id,
        v_provider,
        p_provider_identity,
        v_provider,
        jsonb_build_object('provider_reference', v_reference)
      );
      PERFORM public.add_donation_payload_to_contributor(
        v_donation.contributor_id,
        v_donation.donation_id,
        v_provider
      );
    END IF;
  ELSE
    SELECT * INTO v_donation
    FROM public.donations d
    WHERE d.provider = v_provider
      AND d.provider_reference = v_reference;
  END IF;

  donation_id := v_donation.donation_id;
  contributor_id := v_donation.contributor_id;
  member_id := v_donation.member_id;
  donor_kind := v_donation.donor_kind;
  status := v_donation.status;
  match_method := CASE WHEN v_inserted THEN v_match.match_method ELSE 'duplicate_reference' END;
  match_score := CASE WHEN v_inserted THEN v_match.match_score ELSE NULL END;
  inserted := v_inserted;
  RETURN NEXT;
END;
$$;


--
-- Name: FUNCTION ingest_provider_donation(p_provider text, p_provider_reference text, p_amount_cents integer, p_currency text, p_donated_at timestamp with time zone, p_notes text, p_raw jsonb, p_email text, p_phone text, p_provider_identity text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.ingest_provider_donation(p_provider text, p_provider_reference text, p_amount_cents integer, p_currency text, p_donated_at timestamp with time zone, p_notes text, p_raw jsonb, p_email text, p_phone text, p_provider_identity text) IS 'Idempotently records a provider donation using contributor-first matching and preserves the raw payload for review.';


--
-- Name: issue19_add_contributor_address(text, text, uuid, text, text, text, text, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.issue19_add_contributor_address(p_actor_email text, p_party_kind text, p_party_id uuid, p_address_1 text, p_address_2 text, p_city text, p_state text, p_postal_code text, p_country text, p_reason text) RETURNS uuid
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_contributor_id uuid;
  v_address_id uuid;
  v_key text;
  v_primary boolean;
  v_country text := COALESCE(NULLIF(btrim(p_country),''),'USA');
BEGIN
  IF NOT public.issue19_has_role(p_actor_email,'donations_reviewer') THEN
    RAISE EXCEPTION 'Donations reviewer permission required';
  END IF;
  IF NULLIF(btrim(p_address_1),'') IS NULL
    OR NULLIF(btrim(p_city),'') IS NULL
    OR NULLIF(btrim(p_state),'') IS NULL
    OR NULLIF(btrim(p_postal_code),'') IS NULL
    OR NULLIF(btrim(p_reason),'') IS NULL THEN
    RAISE EXCEPTION 'Street, city, state, postal code and reason are required';
  END IF;
  v_key := public.member_address_identity_key(
    p_address_1,p_address_2,p_postal_code,v_country);
  IF v_key IS NULL THEN RAISE EXCEPTION 'Enter a complete physical address'; END IF;
  SELECT c.contributor_id INTO v_contributor_id FROM public.contributors c
  WHERE c.status='active'
    AND ((p_party_kind='individual' AND c.person_id=p_party_id)
      OR (p_party_kind='organization' AND c.organization_id=p_party_id))
  FOR UPDATE;
  IF v_contributor_id IS NULL THEN
    RAISE EXCEPTION 'Active contributor not found for this profile';
  END IF;
  IF EXISTS (SELECT 1 FROM public.contributor_addresses a
      WHERE a.contributor_id=v_contributor_id AND a.status='active'
        AND a.address_identity_key=v_key) THEN
    RAISE EXCEPTION 'This contributor already has this active physical address';
  END IF;
  v_primary := NOT EXISTS (SELECT 1 FROM public.contributor_addresses a
    WHERE a.contributor_id=v_contributor_id AND a.status='active'
      AND a.is_primary);
  INSERT INTO public.contributor_addresses
    (contributor_id,address_type,address_1,address_2,city,state,
      postal_code,country,is_primary,source)
  VALUES (v_contributor_id,'mailing',btrim(p_address_1),
    NULLIF(btrim(p_address_2),''),btrim(p_city),btrim(p_state),
    btrim(p_postal_code),v_country,v_primary,'directory_profile')
  RETURNING contributor_address_id INTO v_address_id;
  INSERT INTO public.audit_log(actor,action,entity_type,entity_id,details)
  VALUES (lower(btrim(p_actor_email)),'contributor_address.added',
    'contributor_address',v_address_id::text,
    jsonb_build_object('contributor_id',v_contributor_id,'party_kind',p_party_kind,
      'party_id',p_party_id,'reason',btrim(p_reason)));
  RETURN v_address_id;
END;
$$;


--
-- Name: issue19_add_contributor_contact(text, text, uuid, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.issue19_add_contributor_contact(p_actor_email text, p_party_kind text, p_party_id uuid, p_contact_kind text, p_contact_value text, p_reason text) RETURNS uuid
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_contributor_id uuid;
  v_contact_id uuid;
  v_value text := NULLIF(btrim(p_contact_value), '');
  v_identity text;
BEGIN
  IF NOT public.issue19_has_role(p_actor_email, 'donations_reviewer') THEN
    RAISE EXCEPTION 'Donations reviewer permission required';
  END IF;
  IF p_contact_kind NOT IN ('email','phone') OR v_value IS NULL
    OR NULLIF(btrim(p_reason), '') IS NULL THEN
    RAISE EXCEPTION 'Contact type, value, and reason are required';
  END IF;
  IF p_contact_kind = 'email' THEN
    v_identity := lower(v_value);
    IF position('@' in v_identity) < 2 OR v_identity ~ '[[:space:]]' THEN
      RAISE EXCEPTION 'Enter a valid contact email';
    END IF;
  ELSE
    v_identity := NULLIF(public.normalize_us_phone(v_value), '');
    IF v_identity IS NULL OR length(v_identity) <> 10 THEN
      RAISE EXCEPTION 'Enter a ten-digit phone number';
    END IF;
  END IF;

  SELECT c.contributor_id INTO v_contributor_id
  FROM public.contributors c WHERE c.status = 'active'
    AND ((p_party_kind = 'individual' AND c.person_id = p_party_id)
      OR (p_party_kind = 'organization' AND c.organization_id = p_party_id))
  FOR UPDATE;
  IF v_contributor_id IS NULL THEN
    RAISE EXCEPTION 'Active contributor not found for this profile';
  END IF;
  LOCK TABLE public.member_emails, public.member_phones,
    public.contributor_emails, public.contributor_phones,
    public.party_contacts IN SHARE ROW EXCLUSIVE MODE;

  IF EXISTS (SELECT 1 FROM public.party_contacts pc
      WHERE pc.status = 'active' AND pc.contact_kind = p_contact_kind
        AND pc.identity_key = v_identity
        AND ((p_party_kind='individual'
            AND pc.person_id IS DISTINCT FROM p_party_id)
          OR (p_party_kind='organization'
            AND pc.organization_id IS DISTINCT FROM p_party_id)))
    OR (p_contact_kind = 'email' AND EXISTS (
      SELECT 1 FROM public.members m WHERE m.status='active'
        AND lower(btrim(m.email))=v_identity
        AND (p_party_kind <> 'individual' OR m.person_id <> p_party_id)))
    OR (p_contact_kind = 'phone' AND EXISTS (
      SELECT 1 FROM public.members m WHERE m.status='active'
        AND public.normalize_us_phone(m.phone)=v_identity
        AND (p_party_kind <> 'individual' OR m.person_id <> p_party_id))) THEN
    RAISE EXCEPTION 'Contact belongs to another party; review before sharing it';
  END IF;

  IF p_contact_kind = 'email' THEN
    IF EXISTS (SELECT 1 FROM public.contributor_emails e
      WHERE e.contributor_id=v_contributor_id AND e.status='active'
        AND e.email_normalized=v_identity) THEN
      RAISE EXCEPTION 'This contributor already has that active email';
    END IF;
    UPDATE public.contributor_emails SET is_primary=false
      WHERE contributor_id=v_contributor_id AND status='active' AND is_primary;
    INSERT INTO public.contributor_emails
      (contributor_id,email,is_primary,source)
    VALUES (v_contributor_id,v_value,true,'directory_profile')
    RETURNING contributor_email_id INTO v_contact_id;
  ELSE
    IF EXISTS (SELECT 1 FROM public.contributor_phones p
      WHERE p.contributor_id=v_contributor_id AND p.status='active'
        AND p.phone_normalized=v_identity) THEN
      RAISE EXCEPTION 'This contributor already has that active phone';
    END IF;
    UPDATE public.contributor_phones SET is_primary=false
      WHERE contributor_id=v_contributor_id AND status='active' AND is_primary;
    INSERT INTO public.contributor_phones
      (contributor_id,phone,is_primary,source)
    VALUES (v_contributor_id,v_value,true,'directory_profile')
    RETURNING contributor_phone_id INTO v_contact_id;
  END IF;
  INSERT INTO public.audit_log(actor,action,entity_type,entity_id,details)
  VALUES (lower(btrim(p_actor_email)),'contributor_contact.added',
    'contributor_contact',v_contact_id::text,
    jsonb_build_object('contributor_id',v_contributor_id,
      'contact_kind',p_contact_kind,'reason',btrim(p_reason)));
  RETURN v_contact_id;
END;
$$;


--
-- Name: issue19_add_membership_address(text, uuid, text, text, text, text, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.issue19_add_membership_address(p_actor_email text, p_person_id uuid, p_address_1 text, p_address_2 text, p_city text, p_state text, p_postal_code text, p_country text, p_reason text) RETURNS uuid
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_member_id uuid;
  v_key text;
  v_primary boolean;
  v_country text := COALESCE(NULLIF(btrim(p_country),''),'USA');
  v_address public.member_addresses%ROWTYPE;
BEGIN
  IF NOT public.issue19_has_role(p_actor_email,'document_reviewer') THEN
    RAISE EXCEPTION 'Document reviewer permission required';
  END IF;
  IF p_person_id IS NULL
    OR NULLIF(btrim(p_address_1),'') IS NULL
    OR NULLIF(btrim(p_city),'') IS NULL
    OR NULLIF(btrim(p_state),'') IS NULL
    OR NULLIF(btrim(p_postal_code),'') IS NULL
    OR NULLIF(btrim(p_reason),'') IS NULL THEN
    RAISE EXCEPTION 'Street, city, state, postal code and reason are required';
  END IF;
  v_key := public.member_address_identity_key(
    p_address_1,p_address_2,p_postal_code,v_country);
  IF v_key IS NULL THEN
    RAISE EXCEPTION 'Enter a complete physical address';
  END IF;

  SELECT operations.member_id INTO v_member_id
  FROM public.issue19_person_member_operations_state(
    p_actor_email,p_person_id) operations
  WHERE operations.can_manage AND operations.membership_status='active';
  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'An active membership and document reviewer access are required';
  END IF;

  LOCK TABLE public.member_addresses, public.contributor_addresses,
    public.party_contacts, public.party_contact_sources
    IN SHARE ROW EXCLUSIVE MODE;

  IF EXISTS (SELECT 1 FROM public.member_addresses address
      WHERE address.member_id=v_member_id AND address.status='active'
        AND address.address_identity_key=v_key) THEN
    RAISE EXCEPTION 'This membership already has this active physical address';
  END IF;

  -- A same-person contributor address must pass through the reviewed
  -- capacity-assignment workflow so the two independent source rows remain
  -- deliberate. The same physical address may still belong to other parties.
  IF EXISTS (SELECT 1 FROM public.party_contacts contact
      JOIN public.party_contact_sources source
        ON source.party_contact_id=contact.party_contact_id
      WHERE contact.status='active' AND contact.person_id=p_person_id
        AND contact.contact_kind='address' AND contact.identity_key=v_key
        AND source.status='active'
        AND source.source_table='contributor_addresses') THEN
    RAISE EXCEPTION 'This is an existing contributor address; use the reviewed cross-role assignment control';
  END IF;

  SELECT NOT EXISTS (SELECT 1 FROM public.member_addresses address
    WHERE address.member_id=v_member_id AND address.status='active'
      AND address.is_primary) INTO v_primary;
  SELECT * INTO STRICT v_address FROM public.upsert_member_address(
    v_member_id,btrim(p_address_1),'mailing',NULLIF(btrim(p_address_2),''),
    btrim(p_city),btrim(p_state),btrim(p_postal_code),v_country,v_primary,
    'issue19_individual_profile',btrim(p_reason));

  INSERT INTO public.audit_log(actor,action,entity_type,entity_id,details)
  VALUES (lower(btrim(p_actor_email)),'membership_address.added',
    'membership_address',v_address.member_address_id::text,
    jsonb_build_object('person_id',p_person_id,'member_id',v_member_id,
      'reason',btrim(p_reason)));
  RETURN v_address.member_address_id;
END;
$$;


--
-- Name: FUNCTION issue19_add_membership_address(p_actor_email text, p_person_id uuid, p_address_1 text, p_address_2 text, p_city text, p_state text, p_postal_code text, p_country text, p_reason text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.issue19_add_membership_address(p_actor_email text, p_person_id uuid, p_address_1 text, p_address_2 text, p_city text, p_state text, p_postal_code text, p_country text, p_reason text) IS 'Adds an audited membership-purpose address; contributor addresses require their own write or reviewed capacity assignment.';


--
-- Name: issue19_add_membership_contact(text, uuid, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.issue19_add_membership_contact(p_actor_email text, p_person_id uuid, p_contact_kind text, p_contact_value text, p_reason text) RETURNS uuid
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_member_id uuid;
  v_contact_id uuid;
  v_value text := NULLIF(btrim(p_contact_value),'');
  v_identity text;
  v_primary boolean;
BEGIN
  IF NOT public.issue19_has_role(p_actor_email,'document_reviewer') THEN
    RAISE EXCEPTION 'Document reviewer permission required';
  END IF;
  IF p_person_id IS NULL OR p_contact_kind NOT IN ('email','phone')
     OR v_value IS NULL OR NULLIF(btrim(p_reason),'') IS NULL THEN
    RAISE EXCEPTION 'Contact type, value, and reason are required';
  END IF;
  IF p_contact_kind='email' THEN
    v_identity := lower(v_value);
    IF position('@' in v_identity) < 2 OR v_identity ~ '[[:space:]]' THEN
      RAISE EXCEPTION 'Enter a valid contact email';
    END IF;
  ELSE
    v_identity := NULLIF(public.normalize_us_phone(v_value),'');
    IF v_identity IS NULL OR length(v_identity) <> 10 THEN
      RAISE EXCEPTION 'Enter a ten-digit phone number';
    END IF;
  END IF;

  SELECT state.member_id INTO v_member_id
  FROM public.issue19_person_member_operations_state(
    p_actor_email,p_person_id) state
  WHERE state.can_manage AND state.membership_status='active';
  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'An active membership and document reviewer access are required';
  END IF;

  LOCK TABLE public.member_emails, public.member_phones,
    public.contributor_emails, public.contributor_phones,
    public.party_contacts IN SHARE ROW EXCLUSIVE MODE;

  -- A contact owned by another person cannot be reassigned by this shortcut.
  -- A contact on this same person's contributor capacity is allowed only via
  -- the explicit reviewed cross-role assignment function, not this add path.
  IF EXISTS (SELECT 1 FROM public.party_contacts contact
      WHERE contact.status='active'
        AND contact.contact_kind=p_contact_kind
        AND contact.identity_key=v_identity
        AND contact.person_id IS DISTINCT FROM p_person_id) THEN
    RAISE EXCEPTION 'Contact belongs to another party; review before sharing it';
  END IF;
  IF EXISTS (SELECT 1 FROM public.party_contacts contact
      JOIN public.party_contact_sources source
        ON source.party_contact_id=contact.party_contact_id
      WHERE contact.status='active' AND contact.person_id=p_person_id
        AND contact.contact_kind=p_contact_kind
        AND contact.identity_key=v_identity
        AND source.status='active'
        AND source.source_table IN ('contributor_emails','contributor_phones')) THEN
    RAISE EXCEPTION 'This is an existing contributor contact; use the reviewed cross-role assignment control';
  END IF;

  IF p_contact_kind='email' THEN
    IF EXISTS (SELECT 1 FROM public.member_emails email
      WHERE email.status='active' AND email.email_normalized=v_identity) THEN
      RAISE EXCEPTION 'This email is already assigned to an active membership';
    END IF;
    SELECT NOT EXISTS (SELECT 1 FROM public.member_emails email
      WHERE email.member_id=v_member_id AND email.status='active'
        AND email.is_primary) INTO v_primary;
    INSERT INTO public.member_emails(
      member_id,email,is_primary,mailing_subscription_status,
      mailing_subscription_source,source,notes)
    VALUES (v_member_id,v_value,v_primary,'not_subscribed',
      'issue19_individual_profile','issue19_individual_profile',btrim(p_reason))
    RETURNING member_email_id INTO v_contact_id;
  ELSE
    IF EXISTS (SELECT 1 FROM public.member_phones phone
      WHERE phone.status='active' AND phone.phone_normalized=v_identity) THEN
      RAISE EXCEPTION 'This phone is already assigned to an active membership';
    END IF;
    SELECT NOT EXISTS (SELECT 1 FROM public.member_phones phone
      WHERE phone.member_id=v_member_id AND phone.status='active'
        AND phone.is_primary) INTO v_primary;
    INSERT INTO public.member_phones(member_id,phone,is_primary,source,notes)
    VALUES (v_member_id,v_value,v_primary,
      'issue19_individual_profile',btrim(p_reason))
    RETURNING member_phone_id INTO v_contact_id;
  END IF;

  INSERT INTO public.audit_log(actor,action,entity_type,entity_id,details)
  VALUES (lower(btrim(p_actor_email)),'membership_contact.added',
    'membership_contact',v_contact_id::text,
    jsonb_build_object('person_id',p_person_id,'member_id',v_member_id,
      'contact_kind',p_contact_kind,'reason',btrim(p_reason)));
  RETURN v_contact_id;
END;
$$;


--
-- Name: FUNCTION issue19_add_membership_contact(p_actor_email text, p_person_id uuid, p_contact_kind text, p_contact_value text, p_reason text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.issue19_add_membership_contact(p_actor_email text, p_person_id uuid, p_contact_kind text, p_contact_value text, p_reason text) IS 'Adds a membership-purpose email or phone; contributor contacts require the separate reviewed assignment workflow.';


--
-- Name: issue19_archive_contributor_address(text, text, uuid, uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.issue19_archive_contributor_address(p_actor_email text, p_party_kind text, p_party_id uuid, p_address_id uuid, p_reason text) RETURNS boolean
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_contributor_id uuid;
  v_archived_by uuid;
  v_was_primary boolean;
BEGIN
  IF NOT public.issue19_has_role(p_actor_email,'donations_reviewer') THEN
    RAISE EXCEPTION 'Donations reviewer permission required';
  END IF;
  IF p_address_id IS NULL OR NULLIF(btrim(p_reason),'') IS NULL THEN
    RAISE EXCEPTION 'Select an address and enter a reason';
  END IF;
  SELECT c.contributor_id INTO v_contributor_id FROM public.contributors c
  WHERE c.status='active'
    AND ((p_party_kind='individual' AND c.person_id=p_party_id)
      OR (p_party_kind='organization' AND c.organization_id=p_party_id))
  FOR UPDATE;
  IF v_contributor_id IS NULL THEN
    RAISE EXCEPTION 'Active contributor not found for this profile';
  END IF;
  SELECT a.is_primary INTO v_was_primary FROM public.contributor_addresses a
  WHERE a.contributor_address_id=p_address_id
    AND a.contributor_id=v_contributor_id AND a.status='active' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Active address not found for this contributor'; END IF;
  SELECT m.member_id INTO v_archived_by
  FROM public.person_app_accounts account
  JOIN public.members m ON m.person_id=account.person_id AND m.status='active'
  WHERE account.status='active'
    AND account.email_normalized=lower(btrim(p_actor_email));
  UPDATE public.contributor_addresses SET status='archived',is_primary=false,
    archived_at=now(),archived_by=v_archived_by,archive_reason=btrim(p_reason)
  WHERE contributor_address_id=p_address_id;
  IF v_was_primary THEN
    UPDATE public.contributor_addresses a SET is_primary=true
    WHERE a.contributor_address_id=(SELECT a2.contributor_address_id
      FROM public.contributor_addresses a2
      WHERE a2.contributor_id=v_contributor_id AND a2.status='active'
      ORDER BY a2.created_at,a2.contributor_address_id LIMIT 1);
  END IF;
  INSERT INTO public.audit_log(actor,action,entity_type,entity_id,details)
  VALUES (lower(btrim(p_actor_email)),'contributor_address.archived',
    'contributor_address',p_address_id::text,
    jsonb_build_object('contributor_id',v_contributor_id,'party_kind',p_party_kind,
      'party_id',p_party_id,'reason',btrim(p_reason)));
  RETURN true;
END;
$$;


--
-- Name: issue19_archive_contributor_contact(text, text, uuid, text, uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.issue19_archive_contributor_contact(p_actor_email text, p_party_kind text, p_party_id uuid, p_contact_kind text, p_contact_id uuid, p_reason text) RETURNS boolean
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_contributor_id uuid;
  v_archived_by uuid;
  v_was_primary boolean;
BEGIN
  IF NOT public.issue19_has_role(p_actor_email, 'donations_reviewer') THEN
    RAISE EXCEPTION 'Donations reviewer permission required';
  END IF;
  IF p_contact_kind NOT IN ('email','phone') OR p_contact_id IS NULL
    OR NULLIF(btrim(p_reason), '') IS NULL THEN
    RAISE EXCEPTION 'Select a contact and enter a reason';
  END IF;
  SELECT c.contributor_id INTO v_contributor_id FROM public.contributors c
  WHERE c.status='active'
    AND ((p_party_kind='individual' AND c.person_id=p_party_id)
      OR (p_party_kind='organization' AND c.organization_id=p_party_id))
  FOR UPDATE;
  IF v_contributor_id IS NULL THEN
    RAISE EXCEPTION 'Active contributor not found for this profile';
  END IF;
  SELECT m.member_id INTO v_archived_by
  FROM public.person_app_accounts a
  JOIN public.members m ON m.person_id=a.person_id AND m.status='active'
  WHERE a.status='active'
    AND a.email_normalized=lower(btrim(p_actor_email));

  IF p_contact_kind='email' THEN
    SELECT e.is_primary INTO v_was_primary FROM public.contributor_emails e
    WHERE e.contributor_email_id=p_contact_id
      AND e.contributor_id=v_contributor_id AND e.status='active' FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Active email not found for this contributor'; END IF;
    UPDATE public.contributor_emails SET status='archived',is_primary=false,
      archived_at=now(),archived_by=v_archived_by,archive_reason=btrim(p_reason)
    WHERE contributor_email_id=p_contact_id;
    IF v_was_primary THEN
      UPDATE public.contributor_emails e SET is_primary=true
      WHERE e.contributor_email_id=(SELECT e2.contributor_email_id
        FROM public.contributor_emails e2
        WHERE e2.contributor_id=v_contributor_id AND e2.status='active'
        ORDER BY e2.created_at,e2.contributor_email_id LIMIT 1);
    END IF;
  ELSE
    SELECT p.is_primary INTO v_was_primary FROM public.contributor_phones p
    WHERE p.contributor_phone_id=p_contact_id
      AND p.contributor_id=v_contributor_id AND p.status='active' FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Active phone not found for this contributor'; END IF;
    UPDATE public.contributor_phones SET status='archived',is_primary=false,
      archived_at=now(),archived_by=v_archived_by,archive_reason=btrim(p_reason)
    WHERE contributor_phone_id=p_contact_id;
    IF v_was_primary THEN
      UPDATE public.contributor_phones p SET is_primary=true
      WHERE p.contributor_phone_id=(SELECT p2.contributor_phone_id
        FROM public.contributor_phones p2
        WHERE p2.contributor_id=v_contributor_id AND p2.status='active'
        ORDER BY p2.created_at,p2.contributor_phone_id LIMIT 1);
    END IF;
  END IF;
  INSERT INTO public.audit_log(actor,action,entity_type,entity_id,details)
  VALUES (lower(btrim(p_actor_email)),'contributor_contact.archived',
    'contributor_contact',p_contact_id::text,
    jsonb_build_object('contributor_id',v_contributor_id,
      'contact_kind',p_contact_kind,'reason',btrim(p_reason)));
  RETURN true;
END;
$$;


--
-- Name: issue19_archive_membership_address(text, uuid, uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.issue19_archive_membership_address(p_actor_email text, p_person_id uuid, p_address_id uuid, p_reason text) RETURNS boolean
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_member_id uuid;
  v_actor_member_id uuid;
  v_was_primary boolean;
BEGIN
  IF NOT public.issue19_has_role(p_actor_email,'document_reviewer') THEN
    RAISE EXCEPTION 'Document reviewer permission required';
  END IF;
  IF p_person_id IS NULL OR p_address_id IS NULL
     OR NULLIF(btrim(p_reason),'') IS NULL THEN
    RAISE EXCEPTION 'Select an address and enter a reason';
  END IF;
  SELECT operations.member_id INTO v_member_id
  FROM public.issue19_person_member_operations_state(
    p_actor_email,p_person_id) operations
  WHERE operations.can_manage AND operations.membership_status='active';
  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'An active membership and document reviewer access are required';
  END IF;
  SELECT member.member_id INTO v_actor_member_id
  FROM public.person_app_accounts account
  JOIN public.members member
    ON member.person_id=account.person_id AND member.status='active'
  WHERE account.status='active'
    AND account.email_normalized=lower(btrim(p_actor_email));

  SELECT address.is_primary INTO v_was_primary
  FROM public.member_addresses address
  WHERE address.member_address_id=p_address_id
    AND address.member_id=v_member_id AND address.status='active' FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Active membership address not found';
  END IF;
  UPDATE public.member_addresses SET status='archived',is_primary=false,
    archived_at=now(),archived_by=v_actor_member_id,
    archive_reason=btrim(p_reason),
    notes=concat_ws(E'\n',NULLIF(notes,''),btrim(p_reason))
  WHERE member_address_id=p_address_id;
  IF v_was_primary THEN
    UPDATE public.member_addresses address SET is_primary=true
    WHERE address.member_address_id=(SELECT candidate.member_address_id
      FROM public.member_addresses candidate
      WHERE candidate.member_id=v_member_id AND candidate.status='active'
      ORDER BY candidate.created_at,candidate.member_address_id LIMIT 1);
  END IF;

  INSERT INTO public.audit_log(actor,action,entity_type,entity_id,details)
  VALUES (lower(btrim(p_actor_email)),'membership_address.archived',
    'membership_address',p_address_id::text,
    jsonb_build_object('person_id',p_person_id,'member_id',v_member_id,
      'reason',btrim(p_reason)));
  RETURN true;
END;
$$;


--
-- Name: FUNCTION issue19_archive_membership_address(p_actor_email text, p_person_id uuid, p_address_id uuid, p_reason text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.issue19_archive_membership_address(p_actor_email text, p_person_id uuid, p_address_id uuid, p_reason text) IS 'Archives one membership-purpose address while retaining canonical and contributor history.';


--
-- Name: issue19_archive_membership_contact(text, uuid, text, uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.issue19_archive_membership_contact(p_actor_email text, p_person_id uuid, p_contact_kind text, p_contact_id uuid, p_reason text) RETURNS boolean
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_member_id uuid;
  v_actor_member_id uuid;
  v_was_primary boolean;
BEGIN
  IF NOT public.issue19_has_role(p_actor_email,'document_reviewer') THEN
    RAISE EXCEPTION 'Document reviewer permission required';
  END IF;
  IF p_person_id IS NULL OR p_contact_kind NOT IN ('email','phone')
     OR p_contact_id IS NULL OR NULLIF(btrim(p_reason),'') IS NULL THEN
    RAISE EXCEPTION 'Select a contact and enter a reason';
  END IF;
  SELECT state.member_id INTO v_member_id
  FROM public.issue19_person_member_operations_state(
    p_actor_email,p_person_id) state
  WHERE state.can_manage AND state.membership_status='active';
  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'An active membership and document reviewer access are required';
  END IF;
  SELECT member.member_id INTO v_actor_member_id
  FROM public.person_app_accounts account
  JOIN public.members member
    ON member.person_id=account.person_id AND member.status='active'
  WHERE account.status='active'
    AND account.email_normalized=lower(btrim(p_actor_email));

  IF p_contact_kind='email' THEN
    SELECT email.is_primary INTO v_was_primary
    FROM public.member_emails email
    WHERE email.member_email_id=p_contact_id
      AND email.member_id=v_member_id AND email.status='active' FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Active membership email not found';
    END IF;
    UPDATE public.member_emails SET status='archived',is_primary=false,
      archived_at=now(),archived_by=v_actor_member_id,
      archive_reason=btrim(p_reason),
      notes=concat_ws(E'\n',NULLIF(notes,''),btrim(p_reason))
    WHERE member_email_id=p_contact_id;
    IF v_was_primary THEN
      UPDATE public.member_emails email SET is_primary=true
      WHERE email.member_email_id=(SELECT candidate.member_email_id
        FROM public.member_emails candidate
        WHERE candidate.member_id=v_member_id AND candidate.status='active'
        ORDER BY candidate.created_at,candidate.member_email_id LIMIT 1);
    END IF;
  ELSE
    SELECT phone.is_primary INTO v_was_primary
    FROM public.member_phones phone
    WHERE phone.member_phone_id=p_contact_id
      AND phone.member_id=v_member_id AND phone.status='active' FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Active membership phone not found';
    END IF;
    UPDATE public.member_phones SET status='archived',is_primary=false,
      archived_at=now(),archived_by=v_actor_member_id,
      archive_reason=btrim(p_reason),
      notes=concat_ws(E'\n',NULLIF(notes,''),btrim(p_reason))
    WHERE member_phone_id=p_contact_id;
    IF v_was_primary THEN
      UPDATE public.member_phones phone SET is_primary=true
      WHERE phone.member_phone_id=(SELECT candidate.member_phone_id
        FROM public.member_phones candidate
        WHERE candidate.member_id=v_member_id AND candidate.status='active'
        ORDER BY candidate.created_at,candidate.member_phone_id LIMIT 1);
    END IF;
  END IF;

  INSERT INTO public.audit_log(actor,action,entity_type,entity_id,details)
  VALUES (lower(btrim(p_actor_email)),'membership_contact.archived',
    'membership_contact',p_contact_id::text,
    jsonb_build_object('person_id',p_person_id,'member_id',v_member_id,
      'contact_kind',p_contact_kind,'reason',btrim(p_reason)));
  RETURN true;
END;
$$;


--
-- Name: FUNCTION issue19_archive_membership_contact(p_actor_email text, p_person_id uuid, p_contact_kind text, p_contact_id uuid, p_reason text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.issue19_archive_membership_contact(p_actor_email text, p_person_id uuid, p_contact_kind text, p_contact_id uuid, p_reason text) IS 'Archives one membership-purpose contact while retaining canonical and contributor history.';


--
-- Name: issue19_assign_member_practitioner(text, uuid, uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.issue19_assign_member_practitioner(p_actor_email text, p_person_id uuid, p_practitioner_person_id uuid, p_notes text, p_reason text) RETURNS uuid
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_actor_person_id uuid;
  v_actor_member_id uuid;
  v_member_id uuid;
  v_practitioner_member_id uuid;
  v_assignment_id uuid;
BEGIN
  IF NOT public.issue19_has_role(p_actor_email,'document_reviewer') THEN
    RAISE EXCEPTION 'Document reviewer permission required';
  END IF;
  IF p_person_id IS NULL OR p_practitioner_person_id IS NULL
     OR NULLIF(btrim(p_reason),'') IS NULL THEN
    RAISE EXCEPTION 'Select a member and practitioner and enter a reason';
  END IF;
  SELECT account.person_id INTO v_actor_person_id
  FROM public.person_app_accounts account
  WHERE account.status='active'
    AND account.email_normalized=lower(btrim(p_actor_email));
  SELECT m.member_id INTO v_actor_member_id FROM public.members m
  WHERE m.person_id=v_actor_person_id AND m.status='active'
  ORDER BY m.created_at DESC LIMIT 1;
  SELECT m.member_id INTO v_member_id FROM public.members m
  WHERE m.person_id=p_person_id AND m.status='active' FOR UPDATE;
  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'This person has no active membership';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.person_roles role
      WHERE role.person_id=p_practitioner_person_id
        AND role.role_key='practitioner') THEN
    RAISE EXCEPTION 'Selected person does not hold the practitioner appointment';
  END IF;

  INSERT INTO public.member_practitioner_assignments(
    member_id,practitioner_person_id,assigned_by_person_id,status,notes)
  VALUES (v_member_id,p_practitioner_person_id,v_actor_person_id,'active',
    NULLIF(btrim(p_notes),''))
  ON CONFLICT (member_id,practitioner_person_id) DO UPDATE SET
    assigned_by_person_id=EXCLUDED.assigned_by_person_id,status='active',
    notes=COALESCE(EXCLUDED.notes,
      public.member_practitioner_assignments.notes),
    ended_at=NULL,ended_by_person_id=NULL,end_reason=NULL,updated_at=now()
  RETURNING member_practitioner_assignment_id INTO v_assignment_id;

  -- Compatibility projection for legacy agreement/release pages. A person
  -- without membership remains a valid canonical practitioner assignment.
  SELECT m.member_id INTO v_practitioner_member_id FROM public.members m
  WHERE m.person_id=p_practitioner_person_id AND m.status='active'
  ORDER BY m.created_at DESC LIMIT 1;
  IF v_practitioner_member_id IS NOT NULL THEN
    INSERT INTO public.member_facilitators(
      member_id,facilitator_id,assigned_by_member_id,status,notes)
    VALUES (v_member_id,v_practitioner_member_id,v_actor_member_id,'active',
      NULLIF(btrim(p_notes),''))
    ON CONFLICT (member_id,facilitator_id) DO UPDATE SET
      assigned_by_member_id=EXCLUDED.assigned_by_member_id,status='active',
      notes=COALESCE(EXCLUDED.notes,public.member_facilitators.notes),
      updated_at=now();
  END IF;

  INSERT INTO public.audit_log(actor,action,entity_type,entity_id,details)
  VALUES (lower(btrim(p_actor_email)),'member_practitioner.assigned',
    'member_practitioner_assignment',v_assignment_id::text,
    jsonb_build_object('member_id',v_member_id,'member_person_id',p_person_id,
      'practitioner_person_id',p_practitioner_person_id,
      'legacy_member_projection',v_practitioner_member_id IS NOT NULL,
      'reason',btrim(p_reason),'notes',NULLIF(btrim(p_notes),'')));
  RETURN v_assignment_id;
END;
$$;


--
-- Name: FUNCTION issue19_assign_member_practitioner(p_actor_email text, p_person_id uuid, p_practitioner_person_id uuid, p_notes text, p_reason text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.issue19_assign_member_practitioner(p_actor_email text, p_person_id uuid, p_practitioner_person_id uuid, p_notes text, p_reason text) IS 'Assigns a person holding the practitioner role to an active membership and creates a legacy projection when possible.';


--
-- Name: issue19_assign_person_contact_role(text, uuid, text, uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.issue19_assign_person_contact_role(p_actor_email text, p_person_id uuid, p_source_table text, p_source_id uuid, p_reason text) RETURNS uuid
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_member_id uuid;
  v_contributor_id uuid;
  v_source jsonb;
  v_kind text;
  v_target_table text;
  v_identity text;
  v_party_contact_id uuid;
  v_target_id uuid;
  v_primary boolean;
BEGIN
  IF NOT public.issue19_has_role(p_actor_email,'directory_manager')
    OR NOT public.issue19_has_role(p_actor_email,'document_reviewer')
    OR NOT public.issue19_has_role(p_actor_email,'donations_reviewer') THEN
    RAISE EXCEPTION 'Directory manager and both reviewer permissions required';
  END IF;
  IF p_person_id IS NULL OR p_source_id IS NULL
     OR NULLIF(btrim(p_reason),'') IS NULL THEN
    RAISE EXCEPTION 'Select a contact and enter a reason';
  END IF;
  v_kind := CASE p_source_table
    WHEN 'member_emails' THEN 'email' WHEN 'contributor_emails' THEN 'email'
    WHEN 'member_phones' THEN 'phone' WHEN 'contributor_phones' THEN 'phone'
    WHEN 'member_addresses' THEN 'address'
    WHEN 'contributor_addresses' THEN 'address' END;
  IF v_kind IS NULL THEN RAISE EXCEPTION 'Unsupported contact source'; END IF;
  v_target_table := CASE p_source_table
    WHEN 'member_emails' THEN 'contributor_emails'
    WHEN 'member_phones' THEN 'contributor_phones'
    WHEN 'member_addresses' THEN 'contributor_addresses'
    WHEN 'contributor_emails' THEN 'member_emails'
    WHEN 'contributor_phones' THEN 'member_phones'
    WHEN 'contributor_addresses' THEN 'member_addresses' END;
  SELECT m.member_id INTO v_member_id FROM public.members m
  WHERE m.person_id=p_person_id AND m.status='active' FOR UPDATE;
  SELECT c.contributor_id INTO v_contributor_id FROM public.contributors c
  WHERE c.person_id=p_person_id AND c.contributor_type='individual'
    AND c.status='active' FOR UPDATE;
  IF v_target_table LIKE 'contributor_%' AND v_contributor_id IS NULL THEN
    RAISE EXCEPTION 'Enable this person as a contributor before assigning this contact';
  END IF;
  IF v_target_table LIKE 'member_%' AND v_member_id IS NULL THEN
    RAISE EXCEPTION 'An active membership is required to assign a membership contact';
  END IF;

  -- Lock each real source row and check its owner. Client-supplied IDs never
  -- authorize reading another person's contact or an archived source.
  CASE p_source_table
    WHEN 'member_emails' THEN
      SELECT to_jsonb(x) INTO v_source FROM public.member_emails x
      JOIN public.members m ON m.member_id=x.member_id
      WHERE x.member_email_id=p_source_id AND m.person_id=p_person_id
        AND x.status='active' FOR SHARE OF x;
    WHEN 'member_phones' THEN
      SELECT to_jsonb(x) INTO v_source FROM public.member_phones x
      JOIN public.members m ON m.member_id=x.member_id
      WHERE x.member_phone_id=p_source_id AND m.person_id=p_person_id
        AND x.status='active' FOR SHARE OF x;
    WHEN 'member_addresses' THEN
      SELECT to_jsonb(x) INTO v_source FROM public.member_addresses x
      JOIN public.members m ON m.member_id=x.member_id
      WHERE x.member_address_id=p_source_id AND m.person_id=p_person_id
        AND x.status='active' FOR SHARE OF x;
    WHEN 'contributor_emails' THEN
      SELECT to_jsonb(x) INTO v_source FROM public.contributor_emails x
      WHERE x.contributor_email_id=p_source_id AND x.contributor_id=v_contributor_id
        AND x.status='active' FOR SHARE;
    WHEN 'contributor_phones' THEN
      SELECT to_jsonb(x) INTO v_source FROM public.contributor_phones x
      WHERE x.contributor_phone_id=p_source_id AND x.contributor_id=v_contributor_id
        AND x.status='active' FOR SHARE;
    WHEN 'contributor_addresses' THEN
      SELECT to_jsonb(x) INTO v_source FROM public.contributor_addresses x
      WHERE x.contributor_address_id=p_source_id AND x.contributor_id=v_contributor_id
        AND x.status='active' FOR SHARE;
  END CASE;
  IF v_source IS NULL THEN
    RAISE EXCEPTION 'Active contact does not belong to this person and capacity';
  END IF;
  v_identity := CASE v_kind
    WHEN 'email' THEN NULLIF(lower(btrim(v_source->>'email')),'')
    WHEN 'phone' THEN NULLIF(public.normalize_us_phone(v_source->>'phone'),'')
    ELSE public.member_address_identity_key(v_source->>'address_1',
      v_source->>'address_2',v_source->>'postal_code',v_source->>'country') END;
  IF v_identity IS NULL THEN
    RAISE EXCEPTION 'Complete the source contact before assigning it to another capacity';
  END IF;
  IF v_kind='phone' AND length(v_identity)<>10 THEN
    RAISE EXCEPTION 'A ten-digit phone number is required';
  END IF;
  SELECT pc.party_contact_id INTO v_party_contact_id
  FROM public.party_contact_sources ps
  JOIN public.party_contacts pc ON pc.party_contact_id=ps.party_contact_id
  WHERE ps.source_table=p_source_table AND ps.source_id=p_source_id
    AND ps.status='active' AND pc.status='active'
    AND pc.person_id=p_person_id AND pc.contact_kind=v_kind
    AND pc.identity_key=v_identity;
  IF v_party_contact_id IS NULL THEN
    RAISE EXCEPTION 'Contact mapping needs review before capacity assignment';
  END IF;
  IF v_kind IN ('email','phone') AND EXISTS (
    SELECT 1 FROM public.party_contacts pc
    WHERE pc.status='active' AND pc.contact_kind=v_kind
      AND pc.identity_key=v_identity
      AND pc.person_id IS DISTINCT FROM p_person_id) THEN
    RAISE EXCEPTION 'Contact belongs to another party; review before sharing it';
  END IF;
  IF EXISTS (SELECT 1 FROM public.party_contact_sources ps
    WHERE ps.party_contact_id=v_party_contact_id
      AND ps.source_table=v_target_table AND ps.status='active') THEN
    RAISE EXCEPTION 'Contact is already assigned to the other capacity';
  END IF;
  IF v_target_table='member_emails' AND EXISTS (
    SELECT 1 FROM public.member_emails e WHERE e.status='active'
      AND e.email_normalized=v_identity AND e.member_id<>v_member_id) THEN
    RAISE EXCEPTION 'Email already belongs to a different active member';
  END IF;

  IF v_target_table='contributor_emails' THEN
    SELECT NOT EXISTS (SELECT 1 FROM public.contributor_emails e WHERE
      e.contributor_id=v_contributor_id AND e.status='active' AND e.is_primary)
      INTO v_primary;
    INSERT INTO public.contributor_emails
      (contributor_id,email,is_primary,source,notes)
    VALUES (v_contributor_id,v_source->>'email',v_primary,
      'issue19_capacity_assignment',btrim(p_reason))
    RETURNING contributor_email_id INTO v_target_id;
  ELSIF v_target_table='contributor_phones' THEN
    SELECT NOT EXISTS (SELECT 1 FROM public.contributor_phones x WHERE
      x.contributor_id=v_contributor_id AND x.status='active' AND x.is_primary)
      INTO v_primary;
    INSERT INTO public.contributor_phones
      (contributor_id,phone,is_primary,source,notes)
    VALUES (v_contributor_id,v_source->>'phone',v_primary,
      'issue19_capacity_assignment',btrim(p_reason))
    RETURNING contributor_phone_id INTO v_target_id;
  ELSIF v_target_table='contributor_addresses' THEN
    SELECT NOT EXISTS (SELECT 1 FROM public.contributor_addresses x WHERE
      x.contributor_id=v_contributor_id AND x.status='active' AND x.is_primary)
      INTO v_primary;
    INSERT INTO public.contributor_addresses
      (contributor_id,address_type,address_1,address_2,city,state,
       postal_code,country,is_primary,source,notes)
    VALUES (v_contributor_id,COALESCE(v_source->>'address_type','mailing'),
      v_source->>'address_1',v_source->>'address_2',v_source->>'city',
      v_source->>'state',v_source->>'postal_code',v_source->>'country',
      v_primary,'issue19_capacity_assignment',btrim(p_reason))
    RETURNING contributor_address_id INTO v_target_id;
  ELSIF v_target_table='member_emails' THEN
    SELECT NOT EXISTS (SELECT 1 FROM public.member_emails e WHERE
      e.member_id=v_member_id AND e.status='active' AND e.is_primary)
      INTO v_primary;
    -- Never turn donation contact reuse into mailing-list consent.
    INSERT INTO public.member_emails
      (member_id,email,is_primary,mailing_subscription_status,
       mailing_subscription_source,source,notes)
    VALUES (v_member_id,v_source->>'email',v_primary,'not_subscribed',
      'issue19_capacity_assignment','issue19_capacity_assignment',btrim(p_reason))
    RETURNING member_email_id INTO v_target_id;
  ELSIF v_target_table='member_phones' THEN
    SELECT NOT EXISTS (SELECT 1 FROM public.member_phones x WHERE
      x.member_id=v_member_id AND x.status='active' AND x.is_primary)
      INTO v_primary;
    INSERT INTO public.member_phones
      (member_id,phone,is_primary,source,notes)
    VALUES (v_member_id,v_source->>'phone',v_primary,
      'issue19_capacity_assignment',btrim(p_reason))
    RETURNING member_phone_id INTO v_target_id;
  ELSE
    SELECT NOT EXISTS (SELECT 1 FROM public.member_addresses x WHERE
      x.member_id=v_member_id AND x.status='active' AND x.is_primary)
      INTO v_primary;
    INSERT INTO public.member_addresses
      (member_id,address_type,address_1,address_2,city,state,
       postal_code,country,is_primary,source,notes)
    VALUES (v_member_id,COALESCE(v_source->>'address_type','mailing'),
      v_source->>'address_1',v_source->>'address_2',v_source->>'city',
      v_source->>'state',v_source->>'postal_code',v_source->>'country',
      v_primary,'issue19_capacity_assignment',btrim(p_reason))
    RETURNING member_address_id INTO v_target_id;
  END IF;
  -- The existing triggers should map both role records to one person contact.
  IF NOT EXISTS (SELECT 1 FROM public.party_contact_sources ps
    WHERE ps.source_table=v_target_table AND ps.source_id=v_target_id
      AND ps.party_contact_id=v_party_contact_id AND ps.status='active') THEN
    RAISE EXCEPTION 'Capacity assignment did not preserve the person contact mapping';
  END IF;
  INSERT INTO public.audit_log(actor,action,entity_type,entity_id,details)
  VALUES (lower(btrim(p_actor_email)),'person_contact.capacity_assigned',
    'person_contact',v_party_contact_id::text,
    jsonb_build_object('person_id',p_person_id,'source_table',p_source_table,
      'source_id',p_source_id,'target_table',v_target_table,
      'target_id',v_target_id,'reason',btrim(p_reason)));
  RETURN v_target_id;
END;
$$;


--
-- Name: issue19_available_member_practitioners(text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.issue19_available_member_practitioners(p_actor_email text, p_person_id uuid) RETURNS TABLE(practitioner_person_id uuid, display_name text, account_email text, has_active_membership boolean, already_assigned boolean)
    LANGUAGE sql STABLE
    SET search_path TO 'public', 'pg_temp'
    AS $$
SELECT practitioner.person_id,practitioner.display_name,account.email,
  EXISTS (SELECT 1 FROM public.members m
    WHERE m.person_id=practitioner.person_id AND m.status='active'),
  EXISTS (SELECT 1 FROM public.member_practitioner_assignments assignment
    WHERE assignment.member_id=state.member_id
      AND assignment.practitioner_person_id=practitioner.person_id
      AND assignment.status='active')
FROM public.issue19_person_member_operations_state(
  p_actor_email,p_person_id) state
JOIN public.person_roles role ON role.role_key='practitioner'
JOIN public.people practitioner ON practitioner.person_id=role.person_id
LEFT JOIN public.person_app_accounts account
  ON account.person_id=practitioner.person_id AND account.status='active'
WHERE state.can_manage AND state.membership_status='active'
ORDER BY practitioner.display_name,practitioner.person_id;
$$;


--
-- Name: issue19_contribution_history(text, text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.issue19_contribution_history(p_actor_email text, p_party_kind text, p_party_id uuid) RETURNS TABLE(donation_id uuid, donation_date timestamp with time zone, amount_cents integer, currency text, provider text, provider_reference text, status text, created_at timestamp with time zone)
    LANGUAGE sql STABLE
    SET search_path TO 'public', 'pg_temp'
    AS $$
SELECT d.donation_id,
  COALESCE(d.donated_at,d.created_at) AS donation_date,
  d.amount_cents,d.currency,d.provider,d.provider_reference,d.status,d.created_at
FROM public.issue19_directory_entries(p_actor_email) visible
JOIN public.contributors c ON c.contributor_id=visible.contributor_id
JOIN public.donations d ON d.contributor_id=c.contributor_id
WHERE visible.party_kind=p_party_kind AND visible.party_id=p_party_id
  AND visible.can_view_contributions
ORDER BY COALESCE(d.donated_at,d.created_at) DESC,d.donation_id;
$$;


--
-- Name: FUNCTION issue19_contribution_history(p_actor_email text, p_party_kind text, p_party_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.issue19_contribution_history(p_actor_email text, p_party_kind text, p_party_id uuid) IS 'Contributor-attributed donation history filtered through Issue #19 directory contribution scope.';


--
-- Name: issue19_contributor_addresses(text, text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.issue19_contributor_addresses(p_actor_email text, p_party_kind text, p_party_id uuid) RETURNS TABLE(address_id uuid, address_type text, address_1 text, address_2 text, city text, state text, postal_code text, country text, is_primary boolean)
    LANGUAGE sql STABLE
    SET search_path TO 'public', 'pg_temp'
    AS $$
SELECT a.contributor_address_id,a.address_type,a.address_1,a.address_2,
  a.city,a.state,a.postal_code,a.country,a.is_primary
FROM public.contributors c JOIN public.contributor_addresses a
  ON a.contributor_id=c.contributor_id AND a.status='active'
WHERE c.status='active'
  AND ((p_party_kind='individual' AND c.person_id=p_party_id)
    OR (p_party_kind='organization' AND c.organization_id=p_party_id))
  AND public.issue19_has_role(p_actor_email,'donations_reviewer')
ORDER BY a.is_primary DESC,a.created_at,a.contributor_address_id;
$$;


--
-- Name: issue19_contributor_contacts(text, text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.issue19_contributor_contacts(p_actor_email text, p_party_kind text, p_party_id uuid) RETURNS TABLE(contact_id uuid, contact_kind text, contact_value text, is_primary boolean, is_verified boolean)
    LANGUAGE sql STABLE
    SET search_path TO 'public', 'pg_temp'
    AS $$
WITH owned AS (
  SELECT c.contributor_id
  FROM public.contributors c
  WHERE c.status = 'active'
    AND ((p_party_kind = 'individual' AND c.person_id = p_party_id)
      OR (p_party_kind = 'organization' AND c.organization_id = p_party_id))
    AND public.issue19_has_role(p_actor_email, 'donations_reviewer')
)
SELECT e.contributor_email_id, 'email'::text, e.email,
  e.is_primary, e.is_verified
FROM owned JOIN public.contributor_emails e USING (contributor_id)
WHERE e.status = 'active'
UNION ALL
SELECT p.contributor_phone_id, 'phone'::text, p.phone,
  p.is_primary, p.is_verified
FROM owned JOIN public.contributor_phones p USING (contributor_id)
WHERE p.status = 'active';
$$;


--
-- Name: issue19_contributor_provider_identities(text, text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.issue19_contributor_provider_identities(p_actor_email text, p_party_kind text, p_party_id uuid) RETURNS TABLE(contributor_external_identity_id uuid, provider text, provider_identity text, status text, source text, created_at timestamp with time zone)
    LANGUAGE sql STABLE
    SET search_path TO 'public', 'pg_temp'
    AS $$
SELECT x.contributor_external_identity_id,x.provider,x.provider_identity,
  x.status,x.source,x.created_at
FROM public.issue19_directory_entries(p_actor_email) visible
JOIN public.contributors c ON c.contributor_id=visible.contributor_id
JOIN public.contributor_external_identities x
  ON x.contributor_id=c.contributor_id
WHERE visible.party_kind=p_party_kind AND visible.party_id=p_party_id
  AND visible.can_view_contributions
ORDER BY (x.status='active') DESC,x.provider,x.created_at,x.contributor_external_identity_id;
$$;


--
-- Name: FUNCTION issue19_contributor_provider_identities(p_actor_email text, p_party_kind text, p_party_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.issue19_contributor_provider_identities(p_actor_email text, p_party_kind text, p_party_id uuid) IS 'Contributor external identities filtered through Issue #19 directory contribution scope.';


--
-- Name: issue19_contributor_status_state(text, text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.issue19_contributor_status_state(p_actor_email text, p_party_kind text, p_party_id uuid) RETURNS TABLE(contributor_id uuid, current_status text, can_archive boolean, can_reactivate boolean, status_note text)
    LANGUAGE sql STABLE
    SET search_path TO 'public', 'pg_temp'
    AS $$
SELECT c.contributor_id,c.status,
  c.status='active',c.status='archived',
  CASE c.status
    WHEN 'active' THEN 'Active contributor. Archive to stop future use while retaining history.'
    WHEN 'archived' THEN 'Archived contributor. Reactivate to use this contributor again.'
    ELSE 'Merged contributors cannot be changed from this profile.' END
FROM public.issue19_directory_entries(p_actor_email) visible
JOIN public.contributors c ON c.contributor_id=visible.contributor_id
WHERE visible.party_kind=p_party_kind AND visible.party_id=p_party_id
  AND public.issue19_has_role(p_actor_email,'directory_manager')
  AND public.issue19_has_role(p_actor_email,'donations_reviewer');
$$;


--
-- Name: issue19_create_contributor(text, text, text, text, text, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.issue19_create_contributor(p_actor_email text, p_party_kind text, p_first_name text, p_last_name text, p_organization_name text, p_email text, p_phone text, p_reason text) RETURNS TABLE(party_kind text, party_id uuid, contributor_id uuid)
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_person_id uuid;
  v_organization_id uuid;
  v_contributor_id uuid;
  v_first_name text := NULLIF(btrim(p_first_name), '');
  v_last_name text := NULLIF(btrim(p_last_name), '');
  v_org_name text := NULLIF(btrim(p_organization_name), '');
  v_email text := NULLIF(lower(btrim(p_email)), '');
  v_phone text := NULLIF(btrim(p_phone), '');
  v_normalized_phone text := NULLIF(public.normalize_us_phone(p_phone), '');
BEGIN
  IF NOT public.issue19_has_role(p_actor_email, 'donations_reviewer') THEN
    RAISE EXCEPTION 'Donations reviewer permission required';
  END IF;
  IF NULLIF(btrim(p_reason), '') IS NULL THEN
    RAISE EXCEPTION 'A reason is required';
  END IF;
  IF p_party_kind NOT IN ('individual','organization') THEN
    RAISE EXCEPTION 'Select individual or organization';
  END IF;
  IF (p_party_kind = 'individual' AND (v_first_name IS NULL OR v_last_name IS NULL))
    OR (p_party_kind = 'organization' AND v_org_name IS NULL) THEN
    RAISE EXCEPTION 'Individual first/last name or company name is required';
  END IF;
  IF v_email IS NOT NULL AND (position('@' in v_email) < 2
      OR v_email ~ '[[:space:]]') THEN
    RAISE EXCEPTION 'Enter a valid contact email';
  END IF;
  IF v_phone IS NOT NULL AND
     (v_normalized_phone IS NULL OR length(v_normalized_phone) <> 10) THEN
    RAISE EXCEPTION 'Enter a ten-digit phone number';
  END IF;

  -- The same contact can legitimately belong to a household/company, but it
  -- must be reviewed before creating a separate identity. Leave either field
  -- blank to create a known distinct party with a shared contact later.
  LOCK TABLE public.people, public.organizations, public.members,
    public.contributors, public.party_contacts, public.member_emails,
    public.member_phones, public.contributor_emails,
    public.contributor_phones IN SHARE ROW EXCLUSIVE MODE;
  IF (v_email IS NOT NULL AND (
    EXISTS (SELECT 1 FROM public.party_contacts pc
      WHERE pc.contact_kind = 'email' AND pc.identity_key = v_email
        AND pc.status = 'active')
    OR EXISTS (SELECT 1 FROM public.members m
      WHERE m.status = 'active' AND lower(btrim(m.email)) = v_email)))
    OR (v_normalized_phone IS NOT NULL AND (
      EXISTS (SELECT 1 FROM public.party_contacts pc
        WHERE pc.contact_kind = 'phone' AND pc.identity_key = v_normalized_phone
          AND pc.status = 'active')
      OR EXISTS (SELECT 1 FROM public.members m
        WHERE m.status = 'active'
          AND public.normalize_us_phone(m.phone) = v_normalized_phone))) THEN
    RAISE EXCEPTION 'Contact is already in use; review the Directory before creating a new identity';
  END IF;

  IF p_party_kind = 'individual' THEN
    INSERT INTO public.people(display_name,first_name,last_name)
    VALUES (concat_ws(' ',v_first_name,v_last_name),v_first_name,v_last_name)
    RETURNING person_id INTO v_person_id;
  ELSE
    INSERT INTO public.organizations(organization_name)
    VALUES (v_org_name) RETURNING organization_id INTO v_organization_id;
  END IF;
  INSERT INTO public.contributors(contributor_type,person_id,organization_id,source,notes)
  VALUES (p_party_kind,v_person_id,v_organization_id,
    'directory_intake',NULLIF(btrim(p_reason),''))
  RETURNING contributors.contributor_id INTO v_contributor_id;
  IF v_email IS NOT NULL THEN
    INSERT INTO public.contributor_emails(contributor_id,email,is_primary,source)
    VALUES (v_contributor_id,v_email,true,'directory_intake');
  END IF;
  IF v_phone IS NOT NULL THEN
    INSERT INTO public.contributor_phones(contributor_id,phone,is_primary,source)
    VALUES (v_contributor_id,v_phone,true,'directory_intake');
  END IF;
  INSERT INTO public.audit_log(actor,action,entity_type,entity_id,details)
  VALUES (lower(btrim(p_actor_email)),'contributor.created_from_directory',
    'contributor',v_contributor_id::text,
    jsonb_build_object('party_kind',p_party_kind,
      'party_id',COALESCE(v_person_id,v_organization_id),
      'reason',btrim(p_reason)));
  party_kind := p_party_kind;
  party_id := COALESCE(v_person_id,v_organization_id);
  contributor_id := v_contributor_id;
  RETURN NEXT;
END;
$$;


--
-- Name: issue19_create_member_agreement(text, uuid, uuid, uuid, text, text, jsonb, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.issue19_create_member_agreement(p_actor_email text, p_member_id uuid, p_practitioner_person_id uuid, p_agreement_template_id uuid, p_signature_method text, p_status text, p_evidence jsonb DEFAULT '[]'::jsonb, p_member_email_id uuid DEFAULT NULL::uuid) RETURNS TABLE(member_agreement_id uuid, practitioner_person_id uuid, facilitator_id uuid)
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_actor record;
  v_legacy_member_id uuid;
  v_agreement_id uuid;
  v_method text := lower(NULLIF(btrim(p_signature_method),''));
  v_status text := lower(NULLIF(btrim(p_status),''));
BEGIN
  SELECT * INTO v_actor FROM public.issue19_current_release_actor(p_actor_email);
  IF v_actor.person_id IS NULL OR NOT v_actor.is_practitioner THEN
    RAISE EXCEPTION 'Practitioner appointment required to create a member agreement';
  END IF;
  IF p_member_id IS NULL OR p_practitioner_person_id IS NULL
     OR v_method IS NULL OR v_status IS NULL THEN
    RAISE EXCEPTION 'Member, practitioner, signature method, and status are required';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.members
      WHERE member_id=p_member_id AND status='active') THEN
    RAISE EXCEPTION 'An active membership is required for a member agreement';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.issue19_release_practitioners(
      p_actor_email,p_member_id) available
      WHERE available.practitioner_person_id=p_practitioner_person_id) THEN
    RAISE EXCEPTION 'Selected practitioner is not available for this member';
  END IF;
  IF (v_method='documenso' AND v_status<>'pending_email_send')
     OR (v_method='paper' AND v_status<>'pending_review')
     OR v_method NOT IN ('documenso','paper') THEN
    RAISE EXCEPTION 'Unsupported agreement signature method/status transition';
  END IF;
  IF v_method='documenso' AND p_agreement_template_id IS NULL THEN
    RAISE EXCEPTION 'A template is required for a Documenso agreement';
  END IF;
  IF p_agreement_template_id IS NOT NULL AND NOT EXISTS (
      SELECT 1 FROM public.agreement_templates
      WHERE agreement_template_id=p_agreement_template_id AND active) THEN
    RAISE EXCEPTION 'Selected agreement template is not active';
  END IF;
  IF p_member_email_id IS NOT NULL AND NOT EXISTS (
      SELECT 1 FROM public.member_emails
      WHERE member_email_id=p_member_email_id AND member_id=p_member_id
        AND COALESCE(status,'active')='active') THEN
    RAISE EXCEPTION 'Selected member email is not active for this member';
  END IF;

  SELECT member_id INTO v_legacy_member_id FROM public.members
  WHERE person_id=p_practitioner_person_id
  ORDER BY (status='active') DESC,created_at DESC LIMIT 1;

  INSERT INTO public.member_agreements(
    member_id,practitioner_person_id,facilitator_id,
    agreement_template_id,signature_method,status,evidence,member_email_id)
  VALUES (p_member_id,p_practitioner_person_id,v_legacy_member_id,
    p_agreement_template_id,v_method,v_status,
    COALESCE(p_evidence,'[]'::jsonb),p_member_email_id)
  RETURNING public.member_agreements.member_agreement_id
    INTO v_agreement_id;

  INSERT INTO public.audit_log(actor,action,entity_type,entity_id,details)
  VALUES (lower(btrim(p_actor_email)),
    'member_agreement.practitioner_attributed','member_agreement',
    v_agreement_id::text,jsonb_build_object(
      'member_id',p_member_id,
      'practitioner_person_id',p_practitioner_person_id,
      'legacy_facilitator_member_id',v_legacy_member_id,
      'agreement_template_id',p_agreement_template_id,
      'signature_method',v_method,'status',v_status));

  RETURN QUERY SELECT v_agreement_id,p_practitioner_person_id,
    v_legacy_member_id;
END;
$$;


--
-- Name: FUNCTION issue19_create_member_agreement(p_actor_email text, p_member_id uuid, p_practitioner_person_id uuid, p_agreement_template_id uuid, p_signature_method text, p_status text, p_evidence jsonb, p_member_email_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.issue19_create_member_agreement(p_actor_email text, p_member_id uuid, p_practitioner_person_id uuid, p_agreement_template_id uuid, p_signature_method text, p_status text, p_evidence jsonb, p_member_email_id uuid) IS 'Creates a guarded member agreement using the assigned canonical practitioner person.';


--
-- Name: issue19_current_release_actor(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.issue19_current_release_actor(p_actor_email text) RETURNS TABLE(person_id uuid, member_id uuid, display_name text, first_name text, last_name text, email text, is_practitioner boolean, is_document_reviewer boolean, is_donations_reviewer boolean, practitioner_singular_label text, practitioner_plural_label text)
    LANGUAGE sql STABLE
    SET search_path TO 'public', 'pg_temp'
    AS $$
SELECT account.person_id,
  (SELECT m.member_id FROM public.members m
    WHERE m.person_id=account.person_id
    ORDER BY (m.status='active') DESC,m.created_at DESC LIMIT 1),
  person.display_name,person.first_name,person.last_name,account.email,
  public.issue19_has_role(p_actor_email,'practitioner'),
  public.issue19_has_role(p_actor_email,'document_reviewer'),
  public.issue19_has_role(p_actor_email,'donations_reviewer'),
  COALESCE(term.singular_label,'Practitioner'),
  COALESCE(term.plural_label,'Practitioners')
FROM public.person_app_accounts account
JOIN public.people person ON person.person_id=account.person_id
LEFT JOIN public.issue20_organization_terminology() term
  ON term.concept_key='practitioner'
WHERE account.status='active'
  AND account.email_normalized=lower(btrim(p_actor_email));
$$;


--
-- Name: issue19_directory_contacts(text, text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.issue19_directory_contacts(p_actor_email text, p_party_kind text, p_party_id uuid) RETURNS TABLE(contact_kind text, contact_detail text, purpose text, is_primary boolean, is_verified boolean)
    LANGUAGE sql STABLE
    SET search_path TO 'public', 'pg_temp'
    AS $$
SELECT DISTINCT pc.contact_kind,
  CASE WHEN pc.contact_kind = 'address'
    THEN concat_ws(', ', NULLIF(concat_ws(' ',pc.address_1,pc.address_2),''),
      pc.city, pc.state, pc.postal_code, pc.country)
    ELSE pc.contact_value END AS contact_detail,
  CASE WHEN ps.source_table LIKE 'member_%' THEN 'membership'::text
    ELSE 'contributions'::text END AS purpose,
  ps.is_primary, ps.is_verified
FROM public.issue19_directory_entries(p_actor_email) visible
JOIN public.party_contacts pc
  ON (visible.party_kind = 'individual' AND pc.person_id = visible.party_id)
  OR (visible.party_kind = 'organization' AND pc.organization_id = visible.party_id)
JOIN public.party_contact_sources ps ON ps.party_contact_id = pc.party_contact_id
WHERE visible.party_kind = p_party_kind AND visible.party_id = p_party_id
  AND pc.status = 'active' AND ps.status = 'active'
  AND ((ps.source_table LIKE 'member_%' AND visible.can_view_membership)
    OR (ps.source_table LIKE 'contributor_%' AND visible.can_view_contributions))
ORDER BY contact_kind, contact_detail, purpose, is_primary DESC;
$$;


--
-- Name: FUNCTION issue19_directory_contacts(p_actor_email text, p_party_kind text, p_party_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.issue19_directory_contacts(p_actor_email text, p_party_kind text, p_party_id uuid) IS 'Contact details filtered by the same party and member/contributor scope as the Appsmith directory.';


--
-- Name: issue19_directory_entries(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.issue19_directory_entries(p_actor_email text) RETURNS TABLE(party_kind text, party_id uuid, display_name text, member_id uuid, contributor_id uuid, membership_status text, contributor_status text, email text, phone text, created_at timestamp with time zone, can_view_membership boolean, can_view_contributions boolean)
    LANGUAGE sql STABLE
    SET search_path TO 'public', 'pg_temp'
    AS $$
WITH actor AS (
  SELECT account.person_id,
    public.issue19_has_role(p_actor_email,'document_reviewer') AS can_member,
    public.issue19_has_role(p_actor_email,'donations_reviewer') AS can_donor,
    public.issue19_has_role(p_actor_email,'directory_manager') AS can_manage,
    public.issue19_has_role(p_actor_email,'practitioner') AS is_practitioner
  FROM public.person_app_accounts account
  WHERE account.status='active'
    AND account.email_normalized=lower(btrim(p_actor_email))
), people_scope AS (
  SELECT p.person_id,p.display_name,p.created_at,
    m.member_id AS actual_member_id,c.contributor_id AS actual_contributor_id,
    m.status AS actual_membership_status,c.status AS actual_contributor_status,
    (m.member_id IS NOT NULL AND
      (a.can_member OR a.can_manage OR p.person_id=a.person_id
       OR (a.is_practitioner AND EXISTS (
        SELECT 1 FROM public.member_practitioner_assignments assignment
        WHERE assignment.member_id=m.member_id
          AND assignment.practitioner_person_id=a.person_id
          AND assignment.status='active')))) AS may_view_member,
    (c.contributor_id IS NOT NULL AND (
      (c.status='active' AND (a.can_donor OR a.can_manage
       OR (a.is_practitioner AND EXISTS (
        SELECT 1 FROM public.contributor_member_links link
        JOIN public.member_practitioner_assignments assignment
          ON assignment.member_id=link.member_id
        WHERE link.contributor_id=c.contributor_id AND link.status='active'
          AND assignment.practitioner_person_id=a.person_id
          AND assignment.status='active'))))
      OR (c.status='archived' AND a.can_donor AND a.can_manage)
    )) AS may_view_donor,
    (a.can_manage OR a.person_id=p.person_id) AS may_view_person
  FROM public.people p CROSS JOIN actor a
  LEFT JOIN public.members m ON m.person_id=p.person_id AND m.status='active'
  LEFT JOIN public.contributors c ON c.person_id=p.person_id
    AND c.status IN ('active','archived')
), org_scope AS (
  SELECT o.organization_id,o.organization_name,o.created_at,
    c.contributor_id,c.status AS contributor_status
  FROM public.organizations o
  JOIN public.contributors c ON c.organization_id=o.organization_id
    AND c.status IN ('active','archived')
  CROSS JOIN actor a
  WHERE (c.status='active' AND (a.can_donor OR a.can_manage))
     OR (c.status='archived' AND a.can_donor AND a.can_manage)
), visible AS (
  SELECT 'individual'::text AS kind,s.person_id AS id,
    s.display_name AS name,s.created_at,
    CASE WHEN s.may_view_member THEN s.actual_member_id END AS member_id,
    CASE WHEN s.may_view_donor THEN s.actual_contributor_id END AS contributor_id,
    CASE WHEN s.may_view_member THEN s.actual_membership_status END AS membership_status,
    CASE WHEN s.may_view_donor THEN s.actual_contributor_status END AS contributor_status,
    s.may_view_member AS can_member,s.may_view_donor AS can_donor
  FROM people_scope s
  WHERE s.may_view_member OR s.may_view_donor OR s.may_view_person
  UNION ALL
  SELECT 'organization',s.organization_id,s.organization_name,s.created_at,
    NULL::uuid,s.contributor_id,NULL::text,s.contributor_status,false,true
  FROM org_scope s
)
SELECT v.kind,v.id,v.name,v.member_id,v.contributor_id,
  v.membership_status,v.contributor_status,
  (SELECT pc.contact_value FROM public.party_contacts pc
    JOIN public.party_contact_sources ps
      ON ps.party_contact_id=pc.party_contact_id
    WHERE pc.status='active' AND pc.contact_kind='email'
      AND ((v.kind='individual' AND pc.person_id=v.id)
        OR (v.kind='organization' AND pc.organization_id=v.id))
      AND ps.status='active'
      AND ((ps.source_table='member_emails' AND v.can_member)
        OR (ps.source_table='contributor_emails' AND v.can_donor))
    ORDER BY ps.is_primary DESC,ps.created_at,ps.source_id LIMIT 1),
  (SELECT pc.contact_value FROM public.party_contacts pc
    JOIN public.party_contact_sources ps
      ON ps.party_contact_id=pc.party_contact_id
    WHERE pc.status='active' AND pc.contact_kind='phone'
      AND ((v.kind='individual' AND pc.person_id=v.id)
        OR (v.kind='organization' AND pc.organization_id=v.id))
      AND ps.status='active'
      AND ((ps.source_table='member_phones' AND v.can_member)
        OR (ps.source_table='contributor_phones' AND v.can_donor))
    ORDER BY ps.is_primary DESC,ps.created_at,ps.source_id LIMIT 1),
  v.created_at,v.can_member,v.can_donor
FROM visible v;
$$;


--
-- Name: FUNCTION issue19_directory_entries(p_actor_email text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.issue19_directory_entries(p_actor_email text) IS 'Read-only Appsmith directory projection for the current email-based facilitator/reviewer account model. The trusted Appsmith user email is supplied by the application.';


--
-- Name: issue19_enable_person_contributor(text, uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.issue19_enable_person_contributor(p_actor_email text, p_person_id uuid, p_reason text) RETURNS uuid
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE v_contributor_id uuid;
BEGIN
  IF NOT public.issue19_has_role(p_actor_email, 'donations_reviewer')
     OR NOT public.issue19_has_role(p_actor_email, 'directory_manager') THEN
    RAISE EXCEPTION 'Directory manager and donations reviewer permissions required';
  END IF;
  IF p_person_id IS NULL OR NULLIF(btrim(p_reason), '') IS NULL THEN
    RAISE EXCEPTION 'Select an individual and enter a reason';
  END IF;
  PERFORM 1 FROM public.people WHERE person_id = p_person_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Person not found'; END IF;
  IF EXISTS (SELECT 1 FROM public.contributors
    WHERE person_id = p_person_id) THEN
    RAISE EXCEPTION 'This person already has a contributor record; review its status';
  END IF;
  INSERT INTO public.contributors(contributor_type,person_id,source,notes)
  VALUES ('individual',p_person_id,'directory_profile',btrim(p_reason))
  RETURNING contributors.contributor_id INTO v_contributor_id;
  INSERT INTO public.audit_log(actor,action,entity_type,entity_id,details)
  VALUES (lower(btrim(p_actor_email)),'contributor.enabled_for_person',
    'contributor',v_contributor_id::text,
    jsonb_build_object('person_id',p_person_id,'reason',btrim(p_reason)));
  RETURN v_contributor_id;
END;
$$;


--
-- Name: issue19_enable_person_membership(text, uuid, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.issue19_enable_person_membership(p_actor_email text, p_person_id uuid, p_first_name text, p_last_name text, p_reason text) RETURNS uuid
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_member_id uuid;
  v_contributor_id uuid;
  v_actor_member_id uuid;
  v_person public.people%ROWTYPE;
  v_first_name text := NULLIF(btrim(p_first_name), '');
  v_last_name text := NULLIF(btrim(p_last_name), '');
  v_completed_name boolean := false;
BEGIN
  IF NOT public.issue19_has_role(p_actor_email, 'document_reviewer')
     OR NOT public.issue19_has_role(p_actor_email, 'directory_manager') THEN
    RAISE EXCEPTION 'Directory manager and document reviewer permissions required';
  END IF;
  IF p_person_id IS NULL OR NULLIF(btrim(p_reason), '') IS NULL THEN
    RAISE EXCEPTION 'Select an individual and enter a reason';
  END IF;

  SELECT * INTO v_person FROM public.people
  WHERE person_id=p_person_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Person not found'; END IF;
  IF v_first_name IS NULL OR v_last_name IS NULL THEN
    RAISE EXCEPTION 'Reviewed first and last name are required for membership';
  END IF;
  -- An archived membership has its own agreements/history. Do not create a
  -- second member ID for that person or silently reactivate the old record.
  IF EXISTS (SELECT 1 FROM public.members WHERE person_id=p_person_id) THEN
    RAISE EXCEPTION 'This person already has a membership record; review its status';
  END IF;
  IF (NULLIF(btrim(v_person.first_name),'') IS NOT NULL
      AND v_person.first_name IS DISTINCT FROM v_first_name)
    OR (NULLIF(btrim(v_person.last_name),'') IS NOT NULL
      AND v_person.last_name IS DISTINCT FROM v_last_name) THEN
    RAISE EXCEPTION 'The supplied name differs from this person; review identity separately';
  END IF;
  v_completed_name := NULLIF(btrim(v_person.first_name),'') IS NULL
    OR NULLIF(btrim(v_person.last_name),'') IS NULL;
  IF v_completed_name THEN
    UPDATE public.people SET first_name=v_first_name,last_name=v_last_name,
      display_name=concat_ws(' ',v_first_name,v_last_name),updated_at=now()
    WHERE person_id=p_person_id;
  END IF;
  SELECT m.member_id INTO v_actor_member_id
  FROM public.person_app_accounts a JOIN public.members m
    ON m.person_id=a.person_id AND m.status='active'
  WHERE a.status='active'
    AND a.email_normalized=lower(btrim(p_actor_email));
  INSERT INTO public.members(person_id,notes)
  VALUES (p_person_id,'Created from existing person for Issue #19: ' || btrim(p_reason))
  RETURNING member_id INTO v_member_id;

  -- Link an existing individual contributor for identity compatibility.
  -- Its historical donations remain contributor-owned with their original
  -- member_id values; membership does not rewrite donor history.
  SELECT c.contributor_id INTO v_contributor_id
  FROM public.contributors c
  WHERE c.person_id=p_person_id AND c.status='active';
  IF v_contributor_id IS NOT NULL THEN
    INSERT INTO public.contributor_member_links
      (contributor_id,member_id,status,linked_by,link_reason)
    VALUES (v_contributor_id,v_member_id,'active',v_actor_member_id,
      'Membership enabled for existing person: ' || btrim(p_reason));
  END IF;
  INSERT INTO public.audit_log(actor,action,entity_type,entity_id,details)
  VALUES (lower(btrim(p_actor_email)),'membership.enabled_for_person',
    'member',v_member_id::text,
    jsonb_build_object('person_id',p_person_id,
      'contributor_id',v_contributor_id,'reason',btrim(p_reason),
      'completed_name',v_completed_name,
      'previous_display_name',CASE WHEN v_completed_name
        THEN v_person.display_name ELSE NULL END));
  RETURN v_member_id;
END;
$$;


--
-- Name: issue19_end_member_practitioner(text, uuid, uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.issue19_end_member_practitioner(p_actor_email text, p_person_id uuid, p_assignment_id uuid, p_reason text) RETURNS uuid
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_actor_person_id uuid;
  v_member_id uuid;
  v_practitioner_person_id uuid;
  v_practitioner_member_id uuid;
BEGIN
  IF NOT public.issue19_has_role(p_actor_email,'document_reviewer') THEN
    RAISE EXCEPTION 'Document reviewer permission required';
  END IF;
  IF p_person_id IS NULL OR p_assignment_id IS NULL
     OR NULLIF(btrim(p_reason),'') IS NULL THEN
    RAISE EXCEPTION 'Select an active assignment and enter a reason';
  END IF;
  SELECT account.person_id INTO v_actor_person_id
  FROM public.person_app_accounts account
  WHERE account.status='active'
    AND account.email_normalized=lower(btrim(p_actor_email));
  SELECT assignment.member_id,assignment.practitioner_person_id
    INTO v_member_id,v_practitioner_person_id
  FROM public.member_practitioner_assignments assignment
  JOIN public.members member ON member.member_id=assignment.member_id
  WHERE assignment.member_practitioner_assignment_id=p_assignment_id
    AND member.person_id=p_person_id AND assignment.status='active'
  FOR UPDATE OF assignment;
  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'Active practitioner assignment not found for this member';
  END IF;

  UPDATE public.member_practitioner_assignments SET status='inactive',
    ended_at=now(),ended_by_person_id=v_actor_person_id,
    end_reason=btrim(p_reason),updated_at=now()
  WHERE member_practitioner_assignment_id=p_assignment_id;

  SELECT m.member_id INTO v_practitioner_member_id FROM public.members m
  WHERE m.person_id=v_practitioner_person_id
  ORDER BY (m.status='active') DESC,m.created_at DESC LIMIT 1;
  IF v_practitioner_member_id IS NOT NULL THEN
    UPDATE public.member_facilitators SET status='inactive',updated_at=now(),
      notes=concat_ws(E'\n',NULLIF(notes,''),
        'Ended from Individual Profile: ' || btrim(p_reason))
    WHERE member_id=v_member_id AND facilitator_id=v_practitioner_member_id
      AND status='active';
  END IF;

  INSERT INTO public.audit_log(actor,action,entity_type,entity_id,details)
  VALUES (lower(btrim(p_actor_email)),'member_practitioner.ended',
    'member_practitioner_assignment',p_assignment_id::text,
    jsonb_build_object('member_id',v_member_id,'member_person_id',p_person_id,
      'practitioner_person_id',v_practitioner_person_id,
      'reason',btrim(p_reason)));
  RETURN p_assignment_id;
END;
$$;


--
-- Name: FUNCTION issue19_end_member_practitioner(p_actor_email text, p_person_id uuid, p_assignment_id uuid, p_reason text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.issue19_end_member_practitioner(p_actor_email text, p_person_id uuid, p_assignment_id uuid, p_reason text) IS 'Ends a canonical practitioner assignment without removing the practitioner role or changing membership/contributor capacity.';


--
-- Name: issue19_end_person_membership(text, uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.issue19_end_person_membership(p_actor_email text, p_person_id uuid, p_reason text) RETURNS uuid
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_member public.members%ROWTYPE;
  v_contributor_id uuid;
  v_actor_member_id uuid;
  v_links_ended integer;
BEGIN
  IF NOT public.issue19_has_role(p_actor_email,'directory_manager')
     OR NOT public.issue19_has_role(p_actor_email,'document_reviewer') THEN
    RAISE EXCEPTION 'Directory manager and document reviewer permissions required';
  END IF;
  IF p_person_id IS NULL OR NULLIF(btrim(p_reason),'') IS NULL THEN
    RAISE EXCEPTION 'Select an individual and enter a reason';
  END IF;
  PERFORM 1 FROM public.people WHERE person_id=p_person_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Person not found'; END IF;
  SELECT * INTO v_member FROM public.members
  WHERE person_id=p_person_id AND status='active' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'This person has no active membership'; END IF;

  -- Contributor capacity is optional. Lock and preserve it when present, but
  -- never create one merely because membership is ending.
  SELECT c.contributor_id INTO v_contributor_id FROM public.contributors c
  WHERE c.person_id=p_person_id AND c.contributor_type='individual'
    AND c.status='active'
  ORDER BY c.created_at,c.contributor_id
  LIMIT 1 FOR UPDATE;

  IF EXISTS (SELECT 1 FROM public.person_roles r WHERE r.person_id=p_person_id)
    OR v_member.is_facilitator OR v_member.is_document_reviewer
    OR v_member.is_donations_reviewer
    OR EXISTS (SELECT 1 FROM public.member_facilitators f
      WHERE f.facilitator_id=v_member.member_id AND f.status='active') THEN
    RAISE EXCEPTION 'Reassign active facilitator work and remove appointments and permissions before ending membership';
  END IF;
  IF EXISTS (SELECT 1 FROM public.member_agreements a
    WHERE a.member_id=v_member.member_id AND a.status IN
      ('pending_review','pending_email_send','pending_signature')) THEN
    RAISE EXCEPTION 'Resolve pending membership agreements before ending membership';
  END IF;

  SELECT m.member_id INTO v_actor_member_id
  FROM public.person_app_accounts account
  JOIN public.members m ON m.person_id=account.person_id AND m.status='active'
  WHERE account.status='active'
    AND account.email_normalized=lower(btrim(p_actor_email));

  UPDATE public.contributor_member_links link SET status='ended',
    ended_at=now(), ended_by=v_actor_member_id,
    end_reason='Membership ended: ' || btrim(p_reason), updated_at=now()
  WHERE link.member_id=v_member.member_id AND link.status='active';
  GET DIAGNOSTICS v_links_ended = ROW_COUNT;

  UPDATE public.members SET status='inactive', updated_at=now(),
    membership_ended_at=now(), membership_ended_by=lower(btrim(p_actor_email)),
    membership_end_reason=btrim(p_reason)
  WHERE member_id=v_member.member_id;

  INSERT INTO public.audit_log(actor,action,entity_type,entity_id,details)
  VALUES (lower(btrim(p_actor_email)),'membership.ended_for_person',
    'member',v_member.member_id::text,
    jsonb_build_object('person_id',p_person_id,
      'contributor_id',v_contributor_id,
      'had_active_contributor',v_contributor_id IS NOT NULL,
      'reason',btrim(p_reason),'links_ended',v_links_ended));
  RETURN v_member.member_id;
END;
$$;


--
-- Name: FUNCTION issue19_end_person_membership(p_actor_email text, p_person_id uuid, p_reason text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.issue19_end_person_membership(p_actor_email text, p_person_id uuid, p_reason text) IS 'Ends membership without creating, requiring, archiving, or otherwise changing contributor capacity; any active member/contributor link is ended.';


--
-- Name: issue19_former_member_contacts(text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.issue19_former_member_contacts(p_actor_email text, p_person_id uuid) RETURNS TABLE(contact_kind text, contact_detail text, purpose text, is_primary boolean, is_verified boolean)
    LANGUAGE sql STABLE
    SET search_path TO 'public', 'pg_temp'
    AS $$
SELECT DISTINCT pc.contact_kind,
  CASE WHEN pc.contact_kind='address' THEN concat_ws(', ',
    NULLIF(concat_ws(' ',pc.address_1,pc.address_2),''),
    pc.city,pc.state,pc.postal_code,pc.country)
    ELSE pc.contact_value END AS contact_detail,
  'former membership'::text AS purpose, ps.is_primary, ps.is_verified
FROM public.party_contacts pc
JOIN public.party_contact_sources ps ON ps.party_contact_id=pc.party_contact_id
WHERE pc.person_id=p_person_id AND pc.status='active' AND ps.status='active'
  AND ps.source_table IN ('member_emails','member_phones','member_addresses')
  AND public.issue19_has_role(p_actor_email,'directory_manager')
  AND public.issue19_has_role(p_actor_email,'document_reviewer')
  AND EXISTS (SELECT 1 FROM public.members m
    WHERE m.person_id=p_person_id AND m.status='inactive'
      AND (ps.source_table='member_emails' AND EXISTS (
        SELECT 1 FROM public.member_emails e
        WHERE e.member_email_id=ps.source_id AND e.member_id=m.member_id AND e.status='active')
        OR ps.source_table='member_phones' AND EXISTS (
        SELECT 1 FROM public.member_phones x
        WHERE x.member_phone_id=ps.source_id AND x.member_id=m.member_id AND x.status='active')
        OR ps.source_table='member_addresses' AND EXISTS (
        SELECT 1 FROM public.member_addresses a
        WHERE a.member_address_id=ps.source_id AND a.member_id=m.member_id AND a.status='active')))
ORDER BY contact_kind,contact_detail,purpose,is_primary DESC;
$$;


--
-- Name: FUNCTION issue19_former_member_contacts(p_actor_email text, p_person_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.issue19_former_member_contacts(p_actor_email text, p_person_id uuid) IS 'Restricted read-only projection of active contact sources on an ended membership.';


--
-- Name: issue19_guard_practitioner_role_removal(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.issue19_guard_practitioner_role_removal() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
BEGIN
  IF OLD.role_key='practitioner' AND (
      EXISTS (SELECT 1 FROM public.member_practitioner_assignments assignment
        WHERE assignment.practitioner_person_id=OLD.person_id
          AND assignment.status='active')
      OR EXISTS (SELECT 1
        FROM public.practitioner_storage_location_access location_access
        WHERE location_access.practitioner_person_id=OLD.person_id
          AND location_access.status='active')) THEN
    RAISE EXCEPTION 'End active practitioner assignments and storage access before removing the practitioner appointment';
  END IF;
  RETURN OLD;
END;
$$;


--
-- Name: issue19_has_role(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.issue19_has_role(p_actor_email text, p_role_key text) RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO 'public', 'pg_temp'
    AS $$
SELECT EXISTS (
  SELECT 1 FROM public.person_app_accounts account
  JOIN public.person_roles role ON role.person_id = account.person_id
  WHERE account.email_normalized = lower(btrim(p_actor_email))
    AND account.status = 'active' AND role.role_key = p_role_key
);
$$;


--
-- Name: issue19_party_identity_state(text, text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.issue19_party_identity_state(p_actor_email text, p_party_kind text, p_party_id uuid) RETURNS TABLE(party_kind text, party_id uuid, display_name text, first_name text, last_name text, date_of_birth date, identity_version text, can_edit boolean)
    LANGUAGE sql STABLE
    SET search_path TO 'public', 'pg_temp'
    AS $$
SELECT 'individual'::text,p.person_id,p.display_name,p.first_name,p.last_name,
  p.date_of_birth,
  md5(jsonb_build_array(p.display_name,p.first_name,p.last_name,p.date_of_birth)::text),
  true
FROM public.issue19_directory_entries(p_actor_email) visible
JOIN public.people p ON p.person_id=visible.party_id
WHERE p_party_kind='individual' AND visible.party_kind='individual'
  AND visible.party_id=p_party_id
  AND public.issue19_has_role(p_actor_email,'directory_manager')
UNION ALL
SELECT 'organization',o.organization_id,o.organization_name,NULL::text,NULL::text,
  NULL::date,md5(jsonb_build_array(o.organization_name)::text),true
FROM public.issue19_directory_entries(p_actor_email) visible
JOIN public.organizations o ON o.organization_id=visible.party_id
WHERE p_party_kind='organization' AND visible.party_kind='organization'
  AND visible.party_id=p_party_id
  AND public.issue19_has_role(p_actor_email,'directory_manager');
$$;


--
-- Name: FUNCTION issue19_party_identity_state(p_actor_email text, p_party_kind text, p_party_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.issue19_party_identity_state(p_actor_email text, p_party_kind text, p_party_id uuid) IS 'Returns canonical identity fields only to a directory manager who can reach the profile.';


--
-- Name: issue19_person_member_agreements(text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.issue19_person_member_agreements(p_actor_email text, p_person_id uuid) RETURNS TABLE(member_id uuid, membership_status text, member_agreement_id uuid, created_at timestamp with time zone, template_name text, agreement_scope text, agreement_status text, signature_method text, member_signed_at timestamp with time zone, practitioner_signed_at timestamp with time zone, evidence_attached boolean, review_notes text)
    LANGUAGE sql STABLE
    SET search_path TO 'public', 'pg_temp'
    AS $$
SELECT state.member_id,state.membership_status,
  agreement.member_agreement_id,agreement.created_at,
  COALESCE(template.name,'Paper agreement - no template'),
  COALESCE(array_to_string(template.required_for,', '),''),
  agreement.status,agreement.signature_method,
  agreement.member_signed_at,agreement.facilitator_signed_at,
  agreement.evidence IS NOT NULL
    AND btrim(agreement.evidence::text) NOT IN ('','null','[]'),
  agreement.review_notes
FROM public.issue19_person_member_operations_state(
  p_actor_email,p_person_id) state
JOIN public.member_agreements agreement ON agreement.member_id=state.member_id
LEFT JOIN public.agreement_templates template
  ON template.agreement_template_id=agreement.agreement_template_id
WHERE state.can_view
ORDER BY agreement.created_at DESC,agreement.member_agreement_id;
$$;


--
-- Name: FUNCTION issue19_person_member_agreements(p_actor_email text, p_person_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.issue19_person_member_agreements(p_actor_email text, p_person_id uuid) IS 'Returns agreement history only to a document reviewer or practitioner actively assigned to the member.';


--
-- Name: issue19_person_member_operations_state(text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.issue19_person_member_operations_state(p_actor_email text, p_person_id uuid) RETURNS TABLE(member_id uuid, membership_status text, can_view boolean, can_manage boolean)
    LANGUAGE sql STABLE
    SET search_path TO 'public', 'pg_temp'
    AS $$
WITH actor AS (
  SELECT account.person_id,
    public.issue19_has_role(p_actor_email,'document_reviewer') AS can_review,
    public.issue19_has_role(p_actor_email,'practitioner') AS is_practitioner
  FROM public.person_app_accounts account
  WHERE account.status='active'
    AND account.email_normalized=lower(btrim(p_actor_email))
), target AS (
  SELECT m.member_id,m.status
  FROM public.members m WHERE m.person_id=p_person_id
  ORDER BY (m.status='active') DESC,m.created_at DESC LIMIT 1
)
SELECT target.member_id,target.status,
  (actor.can_review OR (actor.is_practitioner AND EXISTS (
    SELECT 1 FROM public.member_practitioner_assignments assignment
    WHERE assignment.member_id=target.member_id
      AND assignment.practitioner_person_id=actor.person_id
      AND assignment.status='active'))),
  actor.can_review
FROM target CROSS JOIN actor;
$$;


--
-- Name: FUNCTION issue19_person_member_operations_state(p_actor_email text, p_person_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.issue19_person_member_operations_state(p_actor_email text, p_person_id uuid) IS 'Returns the latest membership and legacy-equivalent operations access for an Individual Profile.';


--
-- Name: issue19_person_membership_addresses(text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.issue19_person_membership_addresses(p_actor_email text, p_person_id uuid) RETURNS TABLE(address_id uuid, address_type text, address_1 text, address_2 text, city text, state text, postal_code text, country text, is_primary boolean, created_at timestamp with time zone)
    LANGUAGE sql STABLE
    SET search_path TO 'public', 'pg_temp'
    AS $$
SELECT address.member_address_id,address.address_type,address.address_1,
  address.address_2,address.city,address.state,address.postal_code,
  address.country,address.is_primary,address.created_at
FROM public.issue19_person_member_operations_state(
  p_actor_email,p_person_id) state
JOIN public.member_addresses address ON address.member_id=state.member_id
WHERE state.can_view AND address.status='active'
ORDER BY address.is_primary DESC,address.created_at,address.member_address_id;
$$;


--
-- Name: FUNCTION issue19_person_membership_addresses(p_actor_email text, p_person_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.issue19_person_membership_addresses(p_actor_email text, p_person_id uuid) IS 'Returns active membership-purpose mailing addresses without exposing contributor address rows.';


--
-- Name: issue19_person_membership_contacts(text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.issue19_person_membership_contacts(p_actor_email text, p_person_id uuid) RETURNS TABLE(contact_id uuid, contact_kind text, contact_value text, is_primary boolean, is_verified boolean, mailing_subscription_status text, created_at timestamp with time zone)
    LANGUAGE sql STABLE
    SET search_path TO 'public', 'pg_temp'
    AS $$
SELECT email.member_email_id, 'email'::text, email.email,
  email.is_primary, email.is_verified,
  email.mailing_subscription_status, email.created_at
FROM public.issue19_person_member_operations_state(
  p_actor_email,p_person_id) state
JOIN public.member_emails email ON email.member_id=state.member_id
WHERE state.can_view AND email.status='active'
UNION ALL
SELECT phone.member_phone_id, 'phone'::text, phone.phone,
  phone.is_primary, phone.is_verified, NULL::text, phone.created_at
FROM public.issue19_person_member_operations_state(
  p_actor_email,p_person_id) state
JOIN public.member_phones phone ON phone.member_id=state.member_id
WHERE state.can_view AND phone.status='active';
$$;


--
-- Name: FUNCTION issue19_person_membership_contacts(p_actor_email text, p_person_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.issue19_person_membership_contacts(p_actor_email text, p_person_id uuid) IS 'Returns active membership-purpose email and phone records without exposing contributor contact rows.';


--
-- Name: issue19_person_membership_state(text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.issue19_person_membership_state(p_actor_email text, p_person_id uuid) RETURNS TABLE(member_id uuid, membership_status text, membership_ended_at timestamp with time zone, membership_end_reason text, can_end boolean)
    LANGUAGE sql STABLE
    SET search_path TO 'public', 'pg_temp'
    AS $$
SELECT m.member_id, m.status, m.membership_ended_at, m.membership_end_reason,
  (m.status = 'active'
    AND NOT EXISTS (SELECT 1 FROM public.person_roles r
      WHERE r.person_id=m.person_id)
    AND NOT (m.is_facilitator OR m.is_document_reviewer
      OR m.is_donations_reviewer)
    AND NOT EXISTS (SELECT 1 FROM public.member_facilitators f
      WHERE f.facilitator_id=m.member_id AND f.status='active')
    AND NOT EXISTS (SELECT 1 FROM public.member_agreements a
      WHERE a.member_id=m.member_id AND a.status IN
        ('pending_review','pending_email_send','pending_signature'))
  ) AS can_end
FROM public.members m
WHERE m.person_id=p_person_id
  AND public.issue19_has_role(p_actor_email,'directory_manager')
  AND public.issue19_has_role(p_actor_email,'document_reviewer')
ORDER BY (m.status='active') DESC, m.created_at DESC
LIMIT 1;
$$;


--
-- Name: issue19_person_practitioner_assignments(text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.issue19_person_practitioner_assignments(p_actor_email text, p_person_id uuid) RETURNS TABLE(member_id uuid, membership_status text, member_facilitator_id uuid, member_practitioner_assignment_id uuid, practitioner_person_id uuid, practitioner_name text, practitioner_email text, assignment_status text, assigned_at timestamp with time zone, updated_at timestamp with time zone, notes text, ended_at timestamp with time zone, end_reason text)
    LANGUAGE sql STABLE
    SET search_path TO 'public', 'pg_temp'
    AS $$
SELECT state.member_id,state.membership_status,
  assignment.member_practitioner_assignment_id,
  assignment.member_practitioner_assignment_id,
  assignment.practitioner_person_id,practitioner.display_name,
  account.email,assignment.status,assignment.created_at,
  assignment.updated_at,assignment.notes,assignment.ended_at,
  assignment.end_reason
FROM public.issue19_person_member_operations_state(
  p_actor_email,p_person_id) state
JOIN public.member_practitioner_assignments assignment
  ON assignment.member_id=state.member_id
JOIN public.people practitioner
  ON practitioner.person_id=assignment.practitioner_person_id
LEFT JOIN public.person_app_accounts account
  ON account.person_id=practitioner.person_id AND account.status='active'
WHERE state.can_view
ORDER BY (assignment.status='active') DESC,
  practitioner.display_name,assignment.created_at;
$$;


--
-- Name: issue19_profile_account(text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.issue19_profile_account(p_actor_email text, p_person_id uuid) RETURNS TABLE(email text, status text)
    LANGUAGE sql STABLE
    SET search_path TO 'public', 'pg_temp'
    AS $$
SELECT account.email, account.status
FROM public.person_app_accounts account
WHERE account.person_id = p_person_id
  AND public.issue19_has_role(p_actor_email, 'directory_manager');
$$;


--
-- Name: issue19_profile_roles(text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.issue19_profile_roles(p_actor_email text, p_person_id uuid) RETURNS TABLE(role_key text)
    LANGUAGE sql STABLE
    SET search_path TO 'public', 'pg_temp'
    AS $$
SELECT role.role_key
FROM public.person_roles role
WHERE role.person_id = p_person_id
  AND EXISTS (
    SELECT 1 FROM public.issue19_directory_entries(p_actor_email) d
    WHERE d.party_kind = 'individual' AND d.party_id = p_person_id
  )
  AND (public.issue19_has_role(p_actor_email, 'directory_manager')
    OR (role.role_key = 'practitioner' AND
        public.issue19_has_role(p_actor_email, 'document_reviewer'))
    OR (role.role_key = 'donations_reviewer' AND
        public.issue19_has_role(p_actor_email, 'donations_reviewer')));
$$;


--
-- Name: issue19_reassign_person_contact(text, uuid, text, text, uuid, uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.issue19_reassign_person_contact(p_actor_email text, p_source_person_id uuid, p_capacity text, p_contact_kind text, p_contact_id uuid, p_target_person_id uuid, p_reason text) RETURNS boolean
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_source_table text;
  v_target_id uuid;
  v_source_owner_id uuid;
  v_target_owner_id uuid;
  v_source_contact_id uuid;
  v_party_contact_id uuid;
  v_identity text;
  v_was_primary boolean;
  v_contact_detail text;
BEGIN
  IF p_source_person_id IS NULL OR p_target_person_id IS NULL
     OR p_source_person_id = p_target_person_id THEN
    RAISE EXCEPTION 'A different target individual is required';
  END IF;
  IF p_capacity NOT IN ('member','contributor')
     OR p_contact_kind NOT IN ('email','phone','address')
     OR p_contact_id IS NULL
     OR NULLIF(btrim(p_reason),'') IS NULL THEN
    RAISE EXCEPTION 'Capacity, contact, target, and reason are required';
  END IF;

  IF p_capacity = 'member' THEN
    IF NOT public.issue19_has_role(p_actor_email,'document_reviewer') THEN
      RAISE EXCEPTION 'Document reviewer permission required';
    END IF;
    v_source_table := CASE p_contact_kind
      WHEN 'email' THEN 'member_emails'
      WHEN 'phone' THEN 'member_phones'
      ELSE 'member_addresses' END;
  ELSE
    IF NOT public.issue19_has_role(p_actor_email,'donations_reviewer') THEN
      RAISE EXCEPTION 'Donations reviewer permission required';
    END IF;
    v_source_table := CASE p_contact_kind
      WHEN 'email' THEN 'contributor_emails'
      WHEN 'phone' THEN 'contributor_phones'
      ELSE 'contributor_addresses' END;
  END IF;

  IF p_capacity = 'member' THEN
    SELECT m.member_id INTO v_source_owner_id
    FROM public.members m
    WHERE m.person_id = p_source_person_id AND m.status = 'active'
    FOR UPDATE;
    IF v_source_owner_id IS NULL THEN
      RAISE EXCEPTION 'Active membership not found for source individual';
    END IF;

    SELECT m.member_id INTO v_target_owner_id
    FROM public.members m
    JOIN public.people p ON p.person_id = m.person_id
    WHERE m.person_id = p_target_person_id AND m.status = 'active'
    FOR UPDATE;
    IF v_target_owner_id IS NULL THEN
      RAISE EXCEPTION 'Active membership not found for target individual';
    END IF;
  ELSE
    SELECT c.contributor_id INTO v_source_owner_id
    FROM public.contributors c
    WHERE c.person_id = p_source_person_id
      AND c.contributor_type = 'individual'
      AND c.status = 'active'
    FOR UPDATE;
    IF v_source_owner_id IS NULL THEN
      RAISE EXCEPTION 'Active individual contributor not found for source individual';
    END IF;

    SELECT c.contributor_id INTO v_target_owner_id
    FROM public.contributors c
    WHERE c.person_id = p_target_person_id
      AND c.contributor_type = 'individual'
      AND c.status = 'active'
    FOR UPDATE;
    IF v_target_owner_id IS NULL THEN
      RAISE EXCEPTION 'Active individual contributor not found for target individual';
    END IF;
  END IF;

  IF p_capacity = 'member' THEN
    IF p_contact_kind = 'email' THEN
      SELECT e.is_primary, e.email, e.email_normalized, e.member_email_id
      INTO v_was_primary, v_contact_detail, v_identity, v_source_contact_id
      FROM public.member_emails e
      WHERE e.member_email_id = p_contact_id
        AND e.member_id = v_source_owner_id
        AND e.status = 'active'
      FOR UPDATE;
    ELSIF p_contact_kind = 'phone' THEN
      SELECT p.is_primary, p.phone, p.phone_normalized, p.member_phone_id
      INTO v_was_primary, v_contact_detail, v_identity, v_source_contact_id
      FROM public.member_phones p
      WHERE p.member_phone_id = p_contact_id
        AND p.member_id = v_source_owner_id
        AND p.status = 'active'
      FOR UPDATE;
    ELSE
      SELECT a.is_primary,
        concat_ws(', ', a.address_1, a.address_2, a.city, a.state,
          a.postal_code, a.country),
        public.member_address_identity_key(
          a.address_1,a.address_2,a.postal_code,a.country),
        a.member_address_id
      INTO v_was_primary, v_contact_detail, v_identity, v_source_contact_id
      FROM public.member_addresses a
      WHERE a.member_address_id = p_contact_id
        AND a.member_id = v_source_owner_id
        AND a.status = 'active'
      FOR UPDATE;
    END IF;
  ELSE
    IF p_contact_kind = 'email' THEN
      SELECT e.is_primary, e.email, e.email_normalized, e.contributor_email_id
      INTO v_was_primary, v_contact_detail, v_identity, v_source_contact_id
      FROM public.contributor_emails e
      WHERE e.contributor_email_id = p_contact_id
        AND e.contributor_id = v_source_owner_id
        AND e.status = 'active'
      FOR UPDATE;
    ELSIF p_contact_kind = 'phone' THEN
      SELECT p.is_primary, p.phone, p.phone_normalized, p.contributor_phone_id
      INTO v_was_primary, v_contact_detail, v_identity, v_source_contact_id
      FROM public.contributor_phones p
      WHERE p.contributor_phone_id = p_contact_id
        AND p.contributor_id = v_source_owner_id
        AND p.status = 'active'
      FOR UPDATE;
    ELSE
      SELECT a.is_primary,
        concat_ws(', ', a.address_1, a.address_2, a.city, a.state,
          a.postal_code, a.country),
        public.member_address_identity_key(
          a.address_1,a.address_2,a.postal_code,a.country),
        a.contributor_address_id
      INTO v_was_primary, v_contact_detail, v_identity, v_source_contact_id
      FROM public.contributor_addresses a
      WHERE a.contributor_address_id = p_contact_id
        AND a.contributor_id = v_source_owner_id
        AND a.status = 'active'
      FOR UPDATE;
    END IF;
  END IF;

  IF v_contact_detail IS NULL OR v_identity IS NULL THEN
    RAISE EXCEPTION 'Active contact does not belong to the selected source individual';
  END IF;

  SELECT ps.party_contact_id INTO v_party_contact_id
  FROM public.party_contact_sources ps
  JOIN public.party_contacts pc ON pc.party_contact_id = ps.party_contact_id
  WHERE ps.source_table = v_source_table
    AND ps.source_id = p_contact_id
    AND ps.status = 'active'
    AND pc.status = 'active'
    AND pc.person_id = p_source_person_id
    AND pc.contact_kind = p_contact_kind
    AND pc.identity_key = v_identity
  FOR UPDATE;
  IF v_party_contact_id IS NULL THEN
    RAISE EXCEPTION 'Contact mapping needs review before reassignment';
  END IF;

  IF p_capacity = 'member' THEN
    IF p_contact_kind = 'email' AND EXISTS (
      SELECT 1 FROM public.member_emails e
      WHERE e.member_id = v_target_owner_id AND e.status = 'active'
        AND e.email_normalized = v_identity AND e.member_email_id <> p_contact_id) THEN
      RAISE EXCEPTION 'Target membership already has this email';
    ELSIF p_contact_kind = 'phone' AND EXISTS (
      SELECT 1 FROM public.member_phones x
      WHERE x.member_id = v_target_owner_id AND x.status = 'active'
        AND x.phone_normalized = v_identity AND x.member_phone_id <> p_contact_id) THEN
      RAISE EXCEPTION 'Target membership already has this phone';
    ELSIF p_contact_kind = 'address' AND EXISTS (
      SELECT 1 FROM public.member_addresses x
      WHERE x.member_id = v_target_owner_id AND x.status = 'active'
        AND public.member_address_identity_key(
          x.address_1,x.address_2,x.postal_code,x.country) = v_identity
        AND x.member_address_id <> p_contact_id) THEN
      RAISE EXCEPTION 'Target membership already has this address';
    END IF;
  ELSE
    IF p_contact_kind = 'email' AND EXISTS (
      SELECT 1 FROM public.contributor_emails e
      WHERE e.contributor_id = v_target_owner_id AND e.status = 'active'
        AND e.email_normalized = v_identity AND e.contributor_email_id <> p_contact_id) THEN
      RAISE EXCEPTION 'Target contributor already has this email';
    ELSIF p_contact_kind = 'phone' AND EXISTS (
      SELECT 1 FROM public.contributor_phones x
      WHERE x.contributor_id = v_target_owner_id AND x.status = 'active'
        AND x.phone_normalized = v_identity AND x.contributor_phone_id <> p_contact_id) THEN
      RAISE EXCEPTION 'Target contributor already has this phone';
    ELSIF p_contact_kind = 'address' AND EXISTS (
      SELECT 1 FROM public.contributor_addresses x
      WHERE x.contributor_id = v_target_owner_id AND x.status = 'active'
        AND x.address_identity_key = v_identity
        AND x.contributor_address_id <> p_contact_id) THEN
      RAISE EXCEPTION 'Target contributor already has this address';
    END IF;
  END IF;

  IF p_capacity = 'member' THEN
    IF p_contact_kind = 'email' THEN
      UPDATE public.member_emails
      SET member_id = v_target_owner_id,
          is_primary = false,
          updated_at = now(),
          notes = concat_ws(E'\n',NULLIF(notes,''),'Reassigned from individual ' ||
            p_source_person_id::text || ': ' || btrim(p_reason))
      WHERE member_email_id = p_contact_id;
    ELSIF p_contact_kind = 'phone' THEN
      UPDATE public.member_phones
      SET member_id = v_target_owner_id,
          is_primary = false,
          updated_at = now(),
          notes = concat_ws(E'\n',NULLIF(notes,''),'Reassigned from individual ' ||
            p_source_person_id::text || ': ' || btrim(p_reason))
      WHERE member_phone_id = p_contact_id;
    ELSE
      UPDATE public.member_addresses
      SET member_id = v_target_owner_id,
          is_primary = false,
          updated_at = now(),
          notes = concat_ws(E'\n',NULLIF(notes,''),'Reassigned from individual ' ||
            p_source_person_id::text || ': ' || btrim(p_reason))
      WHERE member_address_id = p_contact_id;
    END IF;
  ELSE
    IF p_contact_kind = 'email' THEN
      UPDATE public.contributor_emails
      SET contributor_id = v_target_owner_id,
          is_primary = false,
          updated_at = now(),
          notes = concat_ws(E'\n',NULLIF(notes,''),'Reassigned from individual ' ||
            p_source_person_id::text || ': ' || btrim(p_reason))
      WHERE contributor_email_id = p_contact_id;
    ELSIF p_contact_kind = 'phone' THEN
      UPDATE public.contributor_phones
      SET contributor_id = v_target_owner_id,
          is_primary = false,
          updated_at = now(),
          notes = concat_ws(E'\n',NULLIF(notes,''),'Reassigned from individual ' ||
            p_source_person_id::text || ': ' || btrim(p_reason))
      WHERE contributor_phone_id = p_contact_id;
    ELSE
      UPDATE public.contributor_addresses
      SET contributor_id = v_target_owner_id,
          is_primary = false,
          updated_at = now(),
          notes = concat_ws(E'\n',NULLIF(notes,''),'Reassigned from individual ' ||
            p_source_person_id::text || ': ' || btrim(p_reason))
      WHERE contributor_address_id = p_contact_id;
    END IF;
  END IF;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Contact reassignment did not update the source row';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.party_contact_sources ps
    JOIN public.party_contacts pc ON pc.party_contact_id = ps.party_contact_id
    WHERE ps.source_table = v_source_table
      AND ps.source_id = p_contact_id
      AND ps.status = 'active'
      AND pc.status = 'active'
      AND pc.person_id = p_target_person_id
      AND pc.contact_kind = p_contact_kind
      AND pc.identity_key = v_identity
  ) THEN
    RAISE EXCEPTION 'Contact reassignment did not preserve canonical person ownership';
  END IF;

  INSERT INTO public.audit_log(actor,action,entity_type,entity_id,details)
  VALUES
    (lower(btrim(p_actor_email)),
     'person_contact.reassigned',
     'person_contact',
     v_party_contact_id::text,
     jsonb_build_object(
       'source_person_id',p_source_person_id,
       'target_person_id',p_target_person_id,
       'capacity',p_capacity,
       'contact_kind',p_contact_kind,
       'contact_id',p_contact_id,
       'reason',btrim(p_reason),
       'was_primary',COALESCE(v_was_primary,false),
       'contact_detail',v_contact_detail
     ));

  RETURN true;
END;
$$;


--
-- Name: FUNCTION issue19_reassign_person_contact(p_actor_email text, p_source_person_id uuid, p_capacity text, p_contact_kind text, p_contact_id uuid, p_target_person_id uuid, p_reason text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.issue19_reassign_person_contact(p_actor_email text, p_source_person_id uuid, p_capacity text, p_contact_kind text, p_contact_id uuid, p_target_person_id uuid, p_reason text) IS 'Moves one active membership- or contributor-purpose contact from one individual to another while preserving its source ID, canonical party-contact mapping, history, and audit trail.';


--
-- Name: issue19_record_sacrament_release(text, uuid, uuid, uuid, text, text, numeric, text, integer, text, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.issue19_record_sacrament_release(p_actor_email text, p_member_id uuid, p_practitioner_person_id uuid, p_member_agreement_id uuid, p_mushroomprocess_product_id text, p_item_name text, p_quantity numeric, p_unit text, p_net_weight_g integer, p_strain text, p_storage_location_name text, p_notes text, p_override_reason text DEFAULT NULL::text) RETURNS TABLE(release_id uuid, practitioner_person_id uuid, facilitator_id uuid)
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_actor record;
  v_legacy_member_id uuid;
  v_release_id uuid;
  v_location text := NULLIF(btrim(p_storage_location_name),'');
  v_override_reason text := NULLIF(btrim(p_override_reason),'');
BEGIN
  SELECT * INTO v_actor FROM public.issue19_current_release_actor(p_actor_email);
  IF v_actor.person_id IS NULL OR NOT v_actor.is_practitioner THEN
    RAISE EXCEPTION 'Practitioner appointment required to record a sacrament release';
  END IF;
  IF p_member_id IS NULL OR p_practitioner_person_id IS NULL
     OR NULLIF(btrim(p_mushroomprocess_product_id),'') IS NULL
     OR v_location IS NULL OR p_quantity IS NULL OR p_quantity<=0 THEN
    RAISE EXCEPTION 'Member, practitioner, product, quantity, and storage location are required';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.members
      WHERE member_id=p_member_id AND status='active') THEN
    RAISE EXCEPTION 'An active membership is required for sacrament release';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.issue19_release_practitioners(
      p_actor_email,p_member_id) available
      WHERE available.practitioner_person_id=p_practitioner_person_id) THEN
    RAISE EXCEPTION 'Selected practitioner is not available for this member';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.issue19_release_storage_locations(
      p_actor_email,p_member_id,p_practitioner_person_id) location_access
      WHERE lower(btrim(location_access.storage_location_name))=
        lower(v_location)) THEN
    RAISE EXCEPTION 'Selected practitioner does not have access to this storage location';
  END IF;

  IF p_member_agreement_id IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1
        FROM public.issue19_sacrament_release_agreement(p_member_id) agreement
        WHERE agreement.member_agreement_id=p_member_agreement_id) THEN
      RAISE EXCEPTION 'Selected agreement does not authorize sacrament release';
    END IF;
  ELSIF NOT v_actor.is_document_reviewer OR v_override_reason IS NULL THEN
    RAISE EXCEPTION 'A signed sacrament agreement or documented reviewer override is required';
  END IF;

  SELECT member_id INTO v_legacy_member_id FROM public.members
  WHERE person_id=p_practitioner_person_id
  ORDER BY (status='active') DESC,created_at DESC LIMIT 1;

  INSERT INTO public.releases(
    member_id,release_type,member_agreement_id,
    mushroomprocess_product_id,item_name,quantity,unit,net_weight_g,strain,
    practitioner_person_id,facilitator_id,storage_location_name,
    released_by,notes)
  VALUES (p_member_id,'sacrament_release',p_member_agreement_id,
    btrim(p_mushroomprocess_product_id),NULLIF(btrim(p_item_name),''),
    p_quantity,COALESCE(NULLIF(btrim(p_unit),''),'g'),p_net_weight_g,
    NULLIF(btrim(p_strain),''),p_practitioner_person_id,v_legacy_member_id,
    v_location,lower(btrim(p_actor_email)),NULLIF(btrim(p_notes),''))
  RETURNING public.releases.release_id INTO v_release_id;

  INSERT INTO public.audit_log(actor,action,entity_type,entity_id,details)
  VALUES (lower(btrim(p_actor_email)),'release.issued','release',
    v_release_id::text,jsonb_build_object(
      'member_id',p_member_id,'release_type','sacrament_release',
      'member_agreement_id',p_member_agreement_id,
      'practitioner_person_id',p_practitioner_person_id,
      'legacy_facilitator_member_id',v_legacy_member_id,
      'mushroomprocess_product_id',btrim(p_mushroomprocess_product_id),
      'storage_location_name',v_location,
      'agreement_override',p_member_agreement_id IS NULL,
      'override_reason',v_override_reason));

  RETURN QUERY SELECT v_release_id,p_practitioner_person_id,v_legacy_member_id;
END;
$$;


--
-- Name: FUNCTION issue19_record_sacrament_release(p_actor_email text, p_member_id uuid, p_practitioner_person_id uuid, p_member_agreement_id uuid, p_mushroomprocess_product_id text, p_item_name text, p_quantity numeric, p_unit text, p_net_weight_g integer, p_strain text, p_storage_location_name text, p_notes text, p_override_reason text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.issue19_record_sacrament_release(p_actor_email text, p_member_id uuid, p_practitioner_person_id uuid, p_member_agreement_id uuid, p_mushroomprocess_product_id text, p_item_name text, p_quantity numeric, p_unit text, p_net_weight_g integer, p_strain text, p_storage_location_name text, p_notes text, p_override_reason text) IS 'Records a guarded sacrament transfer using canonical practitioner identity and person-owned storage access.';


--
-- Name: issue19_release_practitioners(text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.issue19_release_practitioners(p_actor_email text, p_member_id uuid) RETURNS TABLE(practitioner_person_id uuid, display_name text, first_name text, last_name text, account_email text, legacy_member_id uuid, is_current_actor boolean)
    LANGUAGE sql STABLE
    SET search_path TO 'public', 'pg_temp'
    AS $$
WITH actor AS (
  SELECT current_actor.person_id,current_actor.is_document_reviewer
  FROM public.issue19_current_release_actor(p_actor_email) current_actor
  WHERE current_actor.is_practitioner
)
SELECT person.person_id,person.display_name,person.first_name,person.last_name,
  account.email,
  (SELECT member.member_id FROM public.members member
    WHERE member.person_id=person.person_id
    ORDER BY (member.status='active') DESC,member.created_at DESC LIMIT 1),
  person.person_id=actor.person_id
FROM actor
JOIN public.member_practitioner_assignments assignment
  ON assignment.member_id=p_member_id AND assignment.status='active'
JOIN public.person_roles role
  ON role.person_id=assignment.practitioner_person_id
  AND role.role_key='practitioner'
JOIN public.people person
  ON person.person_id=assignment.practitioner_person_id
LEFT JOIN public.person_app_accounts account
  ON account.person_id=person.person_id AND account.status='active'
WHERE actor.is_document_reviewer
   OR person.person_id=actor.person_id
ORDER BY (person.person_id=actor.person_id) DESC,person.display_name;
$$;


--
-- Name: issue19_release_storage_locations(text, uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.issue19_release_storage_locations(p_actor_email text, p_member_id uuid, p_practitioner_person_id uuid) RETURNS TABLE(storage_location_name text)
    LANGUAGE sql STABLE
    SET search_path TO 'public', 'pg_temp'
    AS $$
SELECT DISTINCT access.storage_location_name
FROM public.practitioner_storage_location_access access
WHERE access.practitioner_person_id=p_practitioner_person_id
  AND access.status='active'
  AND EXISTS (SELECT 1 FROM public.issue19_release_practitioners(
    p_actor_email,p_member_id) available
    WHERE available.practitioner_person_id=p_practitioner_person_id)
ORDER BY access.storage_location_name;
$$;


--
-- Name: issue19_require_active_release_member(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.issue19_require_active_release_member() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
BEGIN
  PERFORM 1 FROM public.members
  WHERE member_id=NEW.member_id AND status='active' FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'An active membership is required for a new release';
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: issue19_reusable_person_contacts(text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.issue19_reusable_person_contacts(p_actor_email text, p_person_id uuid) RETURNS TABLE(source_table text, source_id uuid, contact_kind text, contact_detail text, target_role text)
    LANGUAGE sql STABLE
    SET search_path TO 'public', 'pg_temp'
    AS $$
SELECT ps.source_table,ps.source_id,pc.contact_kind,
  CASE WHEN pc.contact_kind='address' THEN concat_ws(', ',
    NULLIF(concat_ws(' ',pc.address_1,pc.address_2),''),pc.city,
    pc.state,pc.postal_code,pc.country) ELSE pc.contact_value END,
  CASE WHEN ps.source_table LIKE 'member_%' THEN 'contributions'::text
    ELSE 'membership'::text END
FROM public.party_contacts pc
JOIN public.party_contact_sources ps ON ps.party_contact_id=pc.party_contact_id
WHERE pc.person_id=p_person_id AND pc.status='active'
  AND ps.status='active' AND pc.identity_key IS NOT NULL
  AND (pc.contact_kind <> 'phone' OR length(pc.identity_key)=10)
  AND ps.source_table IN ('member_emails','member_phones','member_addresses',
    'contributor_emails','contributor_phones','contributor_addresses')
  AND public.issue19_has_role(p_actor_email,'directory_manager')
  AND public.issue19_has_role(p_actor_email,'document_reviewer')
  AND public.issue19_has_role(p_actor_email,'donations_reviewer')
  AND (ps.source_table='member_emails' AND EXISTS (
      SELECT 1 FROM public.member_emails e JOIN public.members m USING(member_id)
      WHERE e.member_email_id=ps.source_id AND m.person_id=p_person_id AND e.status='active')
    OR ps.source_table='member_phones' AND EXISTS (
      SELECT 1 FROM public.member_phones x JOIN public.members m USING(member_id)
      WHERE x.member_phone_id=ps.source_id AND m.person_id=p_person_id AND x.status='active')
    OR ps.source_table='member_addresses' AND EXISTS (
      SELECT 1 FROM public.member_addresses a JOIN public.members m USING(member_id)
      WHERE a.member_address_id=ps.source_id AND m.person_id=p_person_id AND a.status='active')
    OR ps.source_table='contributor_emails' AND EXISTS (
      SELECT 1 FROM public.contributor_emails e JOIN public.contributors c USING(contributor_id)
      WHERE e.contributor_email_id=ps.source_id AND c.person_id=p_person_id
        AND c.contributor_type='individual' AND c.status='active' AND e.status='active')
    OR ps.source_table='contributor_phones' AND EXISTS (
      SELECT 1 FROM public.contributor_phones x JOIN public.contributors c USING(contributor_id)
      WHERE x.contributor_phone_id=ps.source_id AND c.person_id=p_person_id
        AND c.contributor_type='individual' AND c.status='active' AND x.status='active')
    OR ps.source_table='contributor_addresses' AND EXISTS (
      SELECT 1 FROM public.contributor_addresses a JOIN public.contributors c USING(contributor_id)
      WHERE a.contributor_address_id=ps.source_id AND c.person_id=p_person_id
        AND c.contributor_type='individual' AND c.status='active' AND a.status='active'))
  AND NOT EXISTS (SELECT 1 FROM public.party_contact_sources target
    WHERE target.party_contact_id=pc.party_contact_id
      AND target.status='active'
      AND target.source_table=CASE ps.source_table
        WHEN 'member_emails' THEN 'contributor_emails'
        WHEN 'member_phones' THEN 'contributor_phones'
        WHEN 'member_addresses' THEN 'contributor_addresses'
        WHEN 'contributor_emails' THEN 'member_emails'
        WHEN 'contributor_phones' THEN 'member_phones'
        WHEN 'contributor_addresses' THEN 'member_addresses' END)
ORDER BY pc.contact_kind,ps.source_table,ps.is_primary DESC,pc.created_at;
$$;


--
-- Name: issue19_sacrament_release_agreement(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.issue19_sacrament_release_agreement(p_member_id uuid) RETURNS TABLE(member_agreement_id uuid, agreement_template_id uuid, signed_at timestamp with time zone, template_name text, template_version text, template_active boolean, agreement_status text, signature_method text, eligibility_basis text)
    LANGUAGE sql STABLE
    SET search_path TO 'public', 'pg_temp'
    AS $$
SELECT agreement.member_agreement_id,
  agreement.agreement_template_id,
  agreement.signed_at,
  COALESCE(template.name,'Paper Agreement - No Template'),
  template.version,
  template.active,
  agreement.status,
  agreement.signature_method,
  CASE WHEN template.agreement_template_id IS NULL
    THEN 'reviewed_manual_agreement'
    ELSE 'signed_sacrament_template' END
FROM public.member_agreements agreement
LEFT JOIN public.agreement_templates template
  ON template.agreement_template_id=agreement.agreement_template_id
WHERE agreement.member_id=p_member_id
  AND lower(COALESCE(agreement.status,'')) IN
    ('signed','complete','completed')
  AND (
    'sacrament_release'=ANY(COALESCE(template.required_for,ARRAY[]::text[]))
    OR (agreement.agreement_template_id IS NULL
      AND lower(COALESCE(agreement.signature_method,'')) IN ('paper','manual'))
  )
ORDER BY agreement.signed_at DESC NULLS LAST,
  agreement.updated_at DESC,
  agreement.created_at DESC,
  agreement.member_agreement_id
LIMIT 1;
$$;


--
-- Name: FUNCTION issue19_sacrament_release_agreement(p_member_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.issue19_sacrament_release_agreement(p_member_id uuid) IS 'Returns the newest signed agreement authorizing sacrament release. Template version and active status do not invalidate a previously signed agreement; active only controls new template selection.';


--
-- Name: issue19_sacrament_release_members(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.issue19_sacrament_release_members(p_actor_email text) RETURNS TABLE(member_id uuid, first_name text, last_name text, email text, phone text, status text, is_facilitator boolean, created_at timestamp with time zone, member_emails_search text, member_phones_search text, member_addresses_search text, member_search_text text, latest_release_agreement_status text, last_release_at timestamp with time zone)
    LANGUAGE sql STABLE
    SET search_path TO 'public', 'pg_temp'
    AS $$
WITH actor AS (
  SELECT current_actor.person_id,current_actor.is_document_reviewer
  FROM public.issue19_current_release_actor(p_actor_email) current_actor
  WHERE current_actor.is_practitioner
), visible AS (
  SELECT profile.*
  FROM public.member_profiles profile CROSS JOIN actor
  WHERE profile.status='active' AND (
    actor.is_document_reviewer OR EXISTS (
      SELECT 1 FROM public.member_practitioner_assignments assignment
      WHERE assignment.member_id=profile.member_id
        AND assignment.practitioner_person_id=actor.person_id
        AND assignment.status='active'))
)
SELECT v.member_id,v.first_name,v.last_name,v.email,v.phone,v.status,
  EXISTS (SELECT 1 FROM public.person_roles role
    WHERE role.person_id=v.person_id AND role.role_key='practitioner'),
  v.created_at,
  COALESCE((SELECT string_agg(DISTINCT e.email,' ')
    FROM public.member_emails e WHERE e.member_id=v.member_id
      AND COALESCE(e.status,'active')='active'),'')::text,
  COALESCE((SELECT string_agg(DISTINCT p.phone,' ')
    FROM public.member_phones p WHERE p.member_id=v.member_id
      AND COALESCE(p.status,'active')='active'),'')::text,
  COALESCE((SELECT string_agg(DISTINCT concat_ws(' ',a.address_1,a.address_2,
      a.city,a.state,a.postal_code,a.country),' ')
    FROM public.member_addresses a WHERE a.member_id=v.member_id
      AND COALESCE(a.status,'active')='active'),'')::text,
  concat_ws(' ',v.member_id::text,v.first_name,v.last_name,v.email,v.phone,
    COALESCE((SELECT string_agg(DISTINCT e.email,' ')
      FROM public.member_emails e WHERE e.member_id=v.member_id
        AND COALESCE(e.status,'active')='active'),''),
    COALESCE((SELECT string_agg(DISTINCT p.phone,' ')
      FROM public.member_phones p WHERE p.member_id=v.member_id
        AND COALESCE(p.status,'active')='active'),''))::text,
  (SELECT agreement.agreement_status
    FROM public.issue19_sacrament_release_agreement(v.member_id) agreement
    LIMIT 1),
  (SELECT max(release.released_at) FROM public.releases release
    WHERE release.member_id=v.member_id)
FROM visible v
ORDER BY v.last_name NULLS LAST,v.first_name NULLS LAST,v.created_at DESC;
$$;


--
-- Name: issue19_set_contributor_status(text, text, uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.issue19_set_contributor_status(p_actor_email text, p_party_kind text, p_party_id uuid, p_target_status text, p_reason text) RETURNS uuid
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_contributor public.contributors%ROWTYPE;
  v_actor_member_id uuid;
BEGIN
  IF NOT public.issue19_has_role(p_actor_email,'directory_manager')
     OR NOT public.issue19_has_role(p_actor_email,'donations_reviewer') THEN
    RAISE EXCEPTION 'Directory manager and donations reviewer permissions required';
  END IF;
  IF p_party_kind NOT IN ('individual','organization') OR p_party_id IS NULL THEN
    RAISE EXCEPTION 'Select an individual or organization contributor';
  END IF;
  IF p_target_status NOT IN ('active','archived') THEN
    RAISE EXCEPTION 'Contributor status must be active or archived';
  END IF;
  IF NULLIF(btrim(p_reason),'') IS NULL THEN
    RAISE EXCEPTION 'Enter a reason for the contributor status change';
  END IF;

  SELECT c.* INTO v_contributor FROM public.contributors c
  WHERE c.contributor_type=p_party_kind
    AND ((p_party_kind='individual' AND c.person_id=p_party_id)
      OR (p_party_kind='organization' AND c.organization_id=p_party_id))
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Contributor not found'; END IF;
  IF v_contributor.status='merged' THEN
    RAISE EXCEPTION 'Merged contributors cannot be reactivated or archived';
  END IF;
  IF v_contributor.status=p_target_status THEN
    RETURN v_contributor.contributor_id;
  END IF;

  SELECT m.member_id INTO v_actor_member_id
  FROM public.person_app_accounts account
  JOIN public.members m ON m.person_id=account.person_id AND m.status='active'
  WHERE account.status='active'
    AND account.email_normalized=lower(btrim(p_actor_email));

  UPDATE public.contributors SET status=p_target_status,
    archived_at=CASE WHEN p_target_status='archived' THEN now() END,
    archived_by=CASE WHEN p_target_status='archived' THEN v_actor_member_id END,
    archive_reason=CASE WHEN p_target_status='archived' THEN btrim(p_reason) END,
    updated_at=now()
  WHERE contributor_id=v_contributor.contributor_id;

  INSERT INTO public.audit_log(actor,action,entity_type,entity_id,details)
  VALUES (lower(btrim(p_actor_email)),
    CASE p_target_status WHEN 'archived' THEN 'contributor.archived'
      ELSE 'contributor.reactivated' END,
    'contributor',v_contributor.contributor_id::text,
    jsonb_build_object('party_kind',p_party_kind,'party_id',p_party_id,
      'previous_status',v_contributor.status,'new_status',p_target_status,
      'reason',btrim(p_reason)));
  RETURN v_contributor.contributor_id;
END;
$$;


--
-- Name: FUNCTION issue19_set_contributor_status(p_actor_email text, p_party_kind text, p_party_id uuid, p_target_status text, p_reason text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.issue19_set_contributor_status(p_actor_email text, p_party_kind text, p_party_id uuid, p_target_status text, p_reason text) IS 'Archives or reactivates a contributor without changing identity, contacts, donations, provider identities, or membership links.';


--
-- Name: issue19_set_person_app_account(text, uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.issue19_set_person_app_account(p_actor_email text, p_person_id uuid, p_email text, p_reason text) RETURNS boolean
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE v_previous text;
BEGIN
  IF NOT public.issue19_has_role(p_actor_email, 'directory_manager') THEN
    RAISE EXCEPTION 'Directory manager permission required';
  END IF;
  IF NULLIF(btrim(p_email), '') IS NULL OR position('@' in btrim(p_email)) < 2
     OR NULLIF(btrim(p_reason), '') IS NULL THEN
    RAISE EXCEPTION 'Account email and reason required';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.people WHERE person_id = p_person_id) THEN
    RAISE EXCEPTION 'Person not found';
  END IF;
  SELECT email INTO v_previous FROM public.person_app_accounts
  WHERE person_id = p_person_id;
  IF v_previous IS NOT NULL
     AND lower(btrim(v_previous)) = lower(btrim(p_actor_email)) THEN
    RAISE EXCEPTION 'A directory manager cannot reassign their own account';
  END IF;
  IF v_previous IS NOT NULL AND lower(btrim(v_previous)) = lower(btrim(p_email))
  THEN RETURN false; END IF;
  INSERT INTO public.person_app_accounts(person_id, email)
  VALUES (p_person_id, lower(btrim(p_email)))
  ON CONFLICT (person_id) DO UPDATE SET
    email = EXCLUDED.email, status = 'active', updated_at = now();
  INSERT INTO public.audit_log(actor, action, entity_type, entity_id, details)
  VALUES (lower(btrim(p_actor_email)), 'person_app_account_changed', 'person',
    p_person_id::text,
    jsonb_build_object('previous_email', v_previous,
                       'email', lower(btrim(p_email)), 'reason', btrim(p_reason)));
  RETURN true;
END;
$$;


--
-- Name: issue19_set_person_role(text, uuid, text, boolean, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.issue19_set_person_role(p_actor_email text, p_person_id uuid, p_role_key text, p_enabled boolean, p_reason text) RETURNS boolean
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE v_changed boolean := false;
BEGIN
  IF NOT public.issue19_has_role(p_actor_email, 'directory_manager') THEN
    RAISE EXCEPTION 'Directory manager permission required';
  END IF;
  IF p_role_key NOT IN ('practitioner', 'document_reviewer', 'donations_reviewer')
     OR p_enabled IS NULL OR NULLIF(btrim(p_reason), '') IS NULL THEN
    RAISE EXCEPTION 'A supported role, desired state, and reason are required';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.people WHERE person_id = p_person_id) THEN
    RAISE EXCEPTION 'Person not found';
  END IF;
  -- directory_manager is intentionally excluded from this function. It is an
  -- operator-level role established through the explicit bootstrap/
  -- administration path. Operational roles may be assigned to oneself.
  IF p_enabled THEN
    INSERT INTO public.person_roles(person_id, role_key, assigned_by)
    VALUES (p_person_id, p_role_key, lower(btrim(p_actor_email)))
    ON CONFLICT DO NOTHING;
  ELSE
    DELETE FROM public.person_roles
    WHERE person_id = p_person_id AND role_key = p_role_key;
  END IF;
  v_changed := FOUND;

  -- A member's existing workflows still read these flags. In particular,
  -- do not imply practitioner status when granting a reviewer permission.
  UPDATE public.members m SET
    is_facilitator = CASE WHEN p_role_key = 'practitioner' THEN p_enabled
      ELSE m.is_facilitator END,
    is_document_reviewer = CASE WHEN p_role_key = 'document_reviewer'
      THEN p_enabled ELSE m.is_document_reviewer END,
    is_donations_reviewer = CASE WHEN p_role_key = 'donations_reviewer'
      THEN p_enabled ELSE m.is_donations_reviewer END,
    updated_at = now()
  WHERE m.person_id = p_person_id AND m.status = 'active'
    AND ((p_role_key = 'practitioner' AND m.is_facilitator IS DISTINCT FROM p_enabled)
      OR (p_role_key = 'document_reviewer' AND m.is_document_reviewer IS DISTINCT FROM p_enabled)
      OR (p_role_key = 'donations_reviewer' AND m.is_donations_reviewer IS DISTINCT FROM p_enabled));
  v_changed := v_changed OR FOUND;

  IF v_changed THEN
    INSERT INTO public.audit_log(actor, action, entity_type, entity_id, details)
    VALUES (lower(btrim(p_actor_email)), 'person_role_changed', 'person',
      p_person_id::text,
      jsonb_build_object('role', p_role_key, 'enabled', p_enabled,
                         'reason', btrim(p_reason)));
  END IF;
  RETURN v_changed;
END;
$$;


--
-- Name: issue19_set_practitioner_storage_location(text, uuid, text, boolean, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.issue19_set_practitioner_storage_location(p_actor_email text, p_practitioner_person_id uuid, p_storage_location_name text, p_active boolean, p_notes text, p_reason text) RETURNS uuid
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_actor_person_id uuid;
  v_actor_member_id uuid;
  v_practitioner_member_id uuid;
  v_access_id uuid;
  v_location text := NULLIF(btrim(p_storage_location_name),'');
BEGIN
  IF NOT public.issue19_has_role(p_actor_email,'document_reviewer') THEN
    RAISE EXCEPTION 'Document reviewer permission required';
  END IF;
  IF p_practitioner_person_id IS NULL OR v_location IS NULL
     OR p_active IS NULL OR NULLIF(btrim(p_reason),'') IS NULL THEN
    RAISE EXCEPTION 'Practitioner, storage location, desired state, and reason are required';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.person_roles
      WHERE person_id=p_practitioner_person_id
        AND role_key='practitioner') THEN
    RAISE EXCEPTION 'Selected person does not hold the practitioner appointment';
  END IF;
  SELECT person_id INTO v_actor_person_id
  FROM public.person_app_accounts
  WHERE email_normalized=lower(btrim(p_actor_email)) AND status='active';

  INSERT INTO public.practitioner_storage_location_access(
    practitioner_person_id,storage_location_name,status,
    assigned_by_person_id,notes)
  VALUES (p_practitioner_person_id,v_location,
    CASE WHEN p_active THEN 'active' ELSE 'inactive' END,
    v_actor_person_id,NULLIF(btrim(p_notes),''))
  ON CONFLICT (practitioner_person_id,storage_location_name) DO UPDATE SET
    status=EXCLUDED.status,assigned_by_person_id=EXCLUDED.assigned_by_person_id,
    notes=COALESCE(EXCLUDED.notes,
      public.practitioner_storage_location_access.notes),updated_at=now()
  RETURNING practitioner_storage_location_access_id INTO v_access_id;

  -- Project the grant when both people still have member IDs so older pages
  -- and reports remain usable. Nonmember practitioners are canonical-only.
  SELECT member_id INTO v_actor_member_id FROM public.members
  WHERE person_id=v_actor_person_id
  ORDER BY (status='active') DESC,created_at DESC LIMIT 1;
  SELECT member_id INTO v_practitioner_member_id FROM public.members
  WHERE person_id=p_practitioner_person_id
  ORDER BY (status='active') DESC,created_at DESC LIMIT 1;
  IF v_practitioner_member_id IS NOT NULL THEN
    INSERT INTO public.facilitator_storage_location_access(
      facilitator_storage_location_access_id,facilitator_id,
      storage_location_name,status,assigned_by_member_id,notes)
    VALUES (v_access_id,v_practitioner_member_id,v_location,
      CASE WHEN p_active THEN 'active' ELSE 'inactive' END,
      v_actor_member_id,NULLIF(btrim(p_notes),''))
    ON CONFLICT (facilitator_id,storage_location_name) DO UPDATE SET
      status=EXCLUDED.status,
      assigned_by_member_id=COALESCE(EXCLUDED.assigned_by_member_id,
        public.facilitator_storage_location_access.assigned_by_member_id),
      notes=COALESCE(EXCLUDED.notes,
        public.facilitator_storage_location_access.notes),updated_at=now();
  END IF;

  INSERT INTO public.audit_log(actor,action,entity_type,entity_id,details)
  VALUES (lower(btrim(p_actor_email)),
    CASE WHEN p_active THEN 'practitioner_storage_location.assigned'
      ELSE 'practitioner_storage_location.removed' END,
    'practitioner_storage_location_access',v_access_id::text,
    jsonb_build_object('practitioner_person_id',p_practitioner_person_id,
      'storage_location_name',v_location,'active',p_active,
      'legacy_member_projection',v_practitioner_member_id IS NOT NULL,
      'reason',btrim(p_reason),'notes',NULLIF(btrim(p_notes),'')));
  RETURN v_access_id;
END;
$$;


--
-- Name: issue19_sync_agreement_practitioner_identity(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.issue19_sync_agreement_practitioner_identity() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_member_person_id uuid;
  v_legacy_member_id uuid;
BEGIN
  IF NEW.facilitator_id IS NOT NULL THEN
    SELECT person_id INTO v_member_person_id FROM public.members
    WHERE member_id=NEW.facilitator_id;
    IF v_member_person_id IS NULL THEN
      RAISE EXCEPTION 'Agreement facilitator member does not resolve to a person';
    END IF;
    IF NEW.practitioner_person_id IS NULL THEN
      NEW.practitioner_person_id := v_member_person_id;
    ELSIF NEW.practitioner_person_id IS DISTINCT FROM v_member_person_id THEN
      RAISE EXCEPTION 'Agreement practitioner person and legacy facilitator member identify different people';
    END IF;
  ELSIF NEW.practitioner_person_id IS NOT NULL THEN
    SELECT member_id INTO v_legacy_member_id FROM public.members
    WHERE person_id=NEW.practitioner_person_id
    ORDER BY (status='active') DESC,created_at DESC LIMIT 1;
    NEW.facilitator_id := v_legacy_member_id;
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: issue19_sync_legacy_member_facilitator(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.issue19_sync_legacy_member_facilitator() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_practitioner_person_id uuid;
  v_assigned_by_person_id uuid;
  v_status text;
BEGIN
  SELECT person_id INTO v_practitioner_person_id
  FROM public.members
  WHERE member_id=CASE WHEN TG_OP='DELETE'
    THEN OLD.facilitator_id ELSE NEW.facilitator_id END;
  IF v_practitioner_person_id IS NULL THEN
    IF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
  END IF;

  IF TG_OP <> 'DELETE' AND NEW.assigned_by_member_id IS NOT NULL THEN
    SELECT person_id INTO v_assigned_by_person_id
    FROM public.members WHERE member_id=NEW.assigned_by_member_id;
  END IF;
  v_status := CASE
    WHEN TG_OP <> 'DELETE'
      AND lower(COALESCE(NEW.status,'active'))='active' THEN 'active'
    ELSE 'inactive' END;

  INSERT INTO public.member_practitioner_assignments(
    member_practitioner_assignment_id,member_id,practitioner_person_id,
    assigned_by_person_id,status,notes,created_at,updated_at,
    ended_at,end_reason)
  VALUES (
    CASE WHEN TG_OP='DELETE' THEN OLD.member_facilitator_id
      ELSE NEW.member_facilitator_id END,
    CASE WHEN TG_OP='DELETE' THEN OLD.member_id ELSE NEW.member_id END,
    v_practitioner_person_id,
    v_assigned_by_person_id,v_status,
    CASE WHEN TG_OP='DELETE' THEN OLD.notes ELSE NEW.notes END,
    CASE WHEN TG_OP='DELETE' THEN OLD.created_at ELSE NEW.created_at END,
    now(),CASE WHEN v_status='inactive' THEN now() END,
    CASE WHEN TG_OP='DELETE' THEN 'Legacy facilitator assignment deleted'
      WHEN v_status='inactive' THEN 'Legacy facilitator assignment ended'
    END)
  ON CONFLICT (member_id,practitioner_person_id) DO UPDATE SET
    assigned_by_person_id=COALESCE(EXCLUDED.assigned_by_person_id,
      public.member_practitioner_assignments.assigned_by_person_id),
    status=EXCLUDED.status,notes=EXCLUDED.notes,updated_at=now(),
    ended_at=CASE WHEN EXCLUDED.status='active' THEN NULL ELSE COALESCE(
      public.member_practitioner_assignments.ended_at,EXCLUDED.ended_at) END,
    end_reason=CASE WHEN EXCLUDED.status='active' THEN NULL ELSE COALESCE(
      public.member_practitioner_assignments.end_reason,EXCLUDED.end_reason) END,
    ended_by_person_id=CASE WHEN EXCLUDED.status='active' THEN NULL ELSE
      public.member_practitioner_assignments.ended_by_person_id END;
  IF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END;
$$;


--
-- Name: issue19_sync_legacy_practitioner_storage_location(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.issue19_sync_legacy_practitioner_storage_location() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_practitioner_person_id uuid;
  v_assigned_by_person_id uuid;
  v_status text;
BEGIN
  SELECT person_id INTO v_practitioner_person_id FROM public.members
  WHERE member_id=CASE WHEN TG_OP='DELETE'
    THEN OLD.facilitator_id ELSE NEW.facilitator_id END;
  IF v_practitioner_person_id IS NULL THEN
    IF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
  END IF;
  IF TG_OP<>'DELETE' AND NEW.assigned_by_member_id IS NOT NULL THEN
    SELECT person_id INTO v_assigned_by_person_id FROM public.members
    WHERE member_id=NEW.assigned_by_member_id;
  END IF;
  v_status := CASE WHEN TG_OP<>'DELETE'
    AND lower(COALESCE(NEW.status,'active'))='active'
    THEN 'active' ELSE 'inactive' END;

  INSERT INTO public.practitioner_storage_location_access(
    practitioner_storage_location_access_id,practitioner_person_id,
    storage_location_name,status,assigned_by_person_id,notes,
    created_at,updated_at)
  VALUES (
    CASE WHEN TG_OP='DELETE'
      THEN OLD.facilitator_storage_location_access_id
      ELSE NEW.facilitator_storage_location_access_id END,
    v_practitioner_person_id,
    CASE WHEN TG_OP='DELETE'
      THEN OLD.storage_location_name ELSE NEW.storage_location_name END,
    v_status,v_assigned_by_person_id,
    CASE WHEN TG_OP='DELETE' THEN OLD.notes ELSE NEW.notes END,
    CASE WHEN TG_OP='DELETE' THEN OLD.created_at ELSE NEW.created_at END,
    now())
  ON CONFLICT (practitioner_person_id,storage_location_name) DO UPDATE SET
    status=EXCLUDED.status,
    assigned_by_person_id=COALESCE(EXCLUDED.assigned_by_person_id,
      public.practitioner_storage_location_access.assigned_by_person_id),
    notes=COALESCE(EXCLUDED.notes,
      public.practitioner_storage_location_access.notes),updated_at=now();
  IF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END;
$$;


--
-- Name: issue19_sync_release_practitioner_identity(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.issue19_sync_release_practitioner_identity() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_member_person_id uuid;
  v_legacy_member_id uuid;
BEGIN
  IF NEW.facilitator_id IS NOT NULL THEN
    SELECT person_id INTO v_member_person_id FROM public.members
    WHERE member_id=NEW.facilitator_id;
    IF NEW.practitioner_person_id IS NULL THEN
      NEW.practitioner_person_id := v_member_person_id;
    ELSIF NEW.practitioner_person_id IS DISTINCT FROM v_member_person_id THEN
      RAISE EXCEPTION 'Release practitioner person does not match legacy facilitator member';
    END IF;
  ELSIF NEW.practitioner_person_id IS NOT NULL THEN
    SELECT member_id INTO v_legacy_member_id FROM public.members
    WHERE person_id=NEW.practitioner_person_id
    ORDER BY (status='active') DESC,created_at DESC LIMIT 1;
    NEW.facilitator_id := v_legacy_member_id;
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: issue19_update_organization_identity(text, uuid, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.issue19_update_organization_identity(p_actor_email text, p_organization_id uuid, p_organization_name text, p_expected_version text, p_reason text) RETURNS uuid
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_organization public.organizations%ROWTYPE;
  v_organization_name text := NULLIF(btrim(p_organization_name),'');
BEGIN
  IF NOT public.issue19_has_role(p_actor_email,'directory_manager') THEN
    RAISE EXCEPTION 'Directory manager permission required';
  END IF;
  IF p_organization_id IS NULL THEN RAISE EXCEPTION 'Select an organization'; END IF;
  IF v_organization_name IS NULL THEN RAISE EXCEPTION 'Organization name is required'; END IF;
  IF NULLIF(btrim(p_reason),'') IS NULL THEN
    RAISE EXCEPTION 'Enter a reason for the identity change';
  END IF;

  SELECT o.* INTO v_organization FROM public.organizations o
  WHERE o.organization_id=p_organization_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Organization not found'; END IF;
  IF p_expected_version IS NULL OR p_expected_version IS DISTINCT FROM
     md5(jsonb_build_array(v_organization.organization_name)::text) THEN
    RAISE EXCEPTION 'This identity changed after the profile loaded; refresh and review it before saving';
  END IF;
  IF v_organization.organization_name IS NOT DISTINCT FROM v_organization_name THEN
    RAISE EXCEPTION 'No identity changes were supplied';
  END IF;

  UPDATE public.organizations SET organization_name=v_organization_name
  WHERE organization_id=p_organization_id;

  INSERT INTO public.audit_log(actor,action,entity_type,entity_id,details)
  VALUES (lower(btrim(p_actor_email)),'organization.identity_updated',
    'organization',p_organization_id::text,jsonb_build_object(
      'reason',btrim(p_reason),
      'contributor_id',(SELECT c.contributor_id FROM public.contributors c
        WHERE c.organization_id=p_organization_id),
      'previous',jsonb_build_object('organization_name',v_organization.organization_name),
      'current',jsonb_build_object('organization_name',v_organization_name)));
  RETURN p_organization_id;
END;
$$;


--
-- Name: FUNCTION issue19_update_organization_identity(p_actor_email text, p_organization_id uuid, p_organization_name text, p_expected_version text, p_reason text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.issue19_update_organization_identity(p_actor_email text, p_organization_id uuid, p_organization_name text, p_expected_version text, p_reason text) IS 'Updates canonical organization identity with optimistic concurrency and old/new audit details.';


--
-- Name: issue19_update_person_identity(text, uuid, text, text, text, date, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.issue19_update_person_identity(p_actor_email text, p_person_id uuid, p_display_name text, p_first_name text, p_last_name text, p_date_of_birth date, p_expected_version text, p_reason text) RETURNS uuid
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_person public.people%ROWTYPE;
  v_display_name text := NULLIF(btrim(p_display_name),'');
  v_first_name text := NULLIF(btrim(p_first_name),'');
  v_last_name text := NULLIF(btrim(p_last_name),'');
BEGIN
  IF NOT public.issue19_has_role(p_actor_email,'directory_manager') THEN
    RAISE EXCEPTION 'Directory manager permission required';
  END IF;
  IF p_person_id IS NULL THEN RAISE EXCEPTION 'Select an individual'; END IF;
  IF v_display_name IS NULL THEN RAISE EXCEPTION 'Display name is required'; END IF;
  IF p_date_of_birth > current_date THEN
    RAISE EXCEPTION 'Birth date cannot be in the future';
  END IF;
  IF NULLIF(btrim(p_reason),'') IS NULL THEN
    RAISE EXCEPTION 'Enter a reason for the identity change';
  END IF;

  SELECT p.* INTO v_person FROM public.people p
  WHERE p.person_id=p_person_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Individual not found'; END IF;
  IF p_expected_version IS NULL OR p_expected_version IS DISTINCT FROM
     md5(jsonb_build_array(v_person.display_name,v_person.first_name,
       v_person.last_name,v_person.date_of_birth)::text) THEN
    RAISE EXCEPTION 'This identity changed after the profile loaded; refresh and review it before saving';
  END IF;
  IF v_person.display_name IS NOT DISTINCT FROM v_display_name
     AND v_person.first_name IS NOT DISTINCT FROM v_first_name
     AND v_person.last_name IS NOT DISTINCT FROM v_last_name
     AND v_person.date_of_birth IS NOT DISTINCT FROM p_date_of_birth THEN
    RAISE EXCEPTION 'No identity changes were supplied';
  END IF;

  UPDATE public.people SET display_name=v_display_name,
    first_name=v_first_name,last_name=v_last_name,date_of_birth=p_date_of_birth
  WHERE person_id=p_person_id;

  INSERT INTO public.audit_log(actor,action,entity_type,entity_id,details)
  VALUES (lower(btrim(p_actor_email)),'person.identity_updated','person',
    p_person_id::text,jsonb_build_object(
      'reason',btrim(p_reason),
      'member_id',(SELECT m.member_id FROM public.members m
        WHERE m.person_id=p_person_id),
      'contributor_id',(SELECT c.contributor_id FROM public.contributors c
        WHERE c.person_id=p_person_id),
      'previous',jsonb_build_object(
        'display_name',v_person.display_name,'first_name',v_person.first_name,
        'last_name',v_person.last_name,'date_of_birth',v_person.date_of_birth),
      'current',jsonb_build_object(
        'display_name',v_display_name,'first_name',v_first_name,
        'last_name',v_last_name,'date_of_birth',p_date_of_birth)));
  RETURN p_person_id;
END;
$$;


--
-- Name: FUNCTION issue19_update_person_identity(p_actor_email text, p_person_id uuid, p_display_name text, p_first_name text, p_last_name text, p_date_of_birth date, p_expected_version text, p_reason text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.issue19_update_person_identity(p_actor_email text, p_person_id uuid, p_display_name text, p_first_name text, p_last_name text, p_date_of_birth date, p_expected_version text, p_reason text) IS 'Updates canonical person identity with optimistic concurrency and old/new audit details.';


--
-- Name: issue20_organization_terminology(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.issue20_organization_terminology() RETURNS TABLE(concept_key text, concept_kind text, singular_label text, plural_label text, short_label text, is_active boolean, description text, updated_at timestamp with time zone)
    LANGUAGE sql STABLE
    SET search_path TO 'public', 'pg_temp'
    AS $$
SELECT concept.concept_key,concept.concept_kind,term.singular_label,
  term.plural_label,term.short_label,term.is_active,concept.description,
  term.updated_at
FROM public.terminology_concepts concept
JOIN public.organization_terminology term
  ON term.concept_key=concept.concept_key
ORDER BY concept.concept_kind,concept.concept_key;
$$;


--
-- Name: FUNCTION issue20_organization_terminology(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.issue20_organization_terminology() IS 'Returns stable concept keys and the deployment terminology used by application surfaces.';


--
-- Name: issue20_set_organization_terminology(text, text, text, text, text, boolean, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.issue20_set_organization_terminology(p_actor_email text, p_concept_key text, p_singular_label text, p_plural_label text, p_short_label text, p_is_active boolean, p_reason text) RETURNS boolean
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_previous public.organization_terminology%ROWTYPE;
  v_singular text := NULLIF(btrim(p_singular_label),'');
  v_plural text := NULLIF(btrim(p_plural_label),'');
  v_short text := NULLIF(btrim(p_short_label),'');
BEGIN
  IF NOT public.issue19_has_role(p_actor_email,'directory_manager') THEN
    RAISE EXCEPTION 'Directory manager permission required';
  END IF;
  IF NULLIF(btrim(p_concept_key),'') IS NULL OR v_singular IS NULL
     OR v_plural IS NULL OR p_is_active IS NULL
     OR NULLIF(btrim(p_reason),'') IS NULL THEN
    RAISE EXCEPTION 'Concept, singular and plural labels, active state, and reason are required';
  END IF;
  IF char_length(v_singular)>80 OR char_length(v_plural)>80
     OR char_length(v_short)>40 THEN
    RAISE EXCEPTION 'Terminology label is too long';
  END IF;

  SELECT * INTO v_previous FROM public.organization_terminology
  WHERE concept_key=p_concept_key FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Unknown terminology concept %',p_concept_key;
  END IF;
  IF v_previous.singular_label=v_singular
     AND v_previous.plural_label=v_plural
     AND v_previous.short_label IS NOT DISTINCT FROM v_short
     AND v_previous.is_active=p_is_active THEN
    RETURN false;
  END IF;

  UPDATE public.organization_terminology SET
    singular_label=v_singular,plural_label=v_plural,short_label=v_short,
    is_active=p_is_active,updated_by=lower(btrim(p_actor_email))
  WHERE concept_key=p_concept_key;

  INSERT INTO public.audit_log(actor,action,entity_type,entity_id,details)
  VALUES (lower(btrim(p_actor_email)),'organization_terminology.changed',
    'terminology_concept',p_concept_key,
    jsonb_build_object(
      'before',jsonb_build_object(
        'singular_label',v_previous.singular_label,
        'plural_label',v_previous.plural_label,
        'short_label',v_previous.short_label,
        'is_active',v_previous.is_active),
      'after',jsonb_build_object(
        'singular_label',v_singular,'plural_label',v_plural,
        'short_label',v_short,'is_active',p_is_active),
      'reason',btrim(p_reason)));
  RETURN true;
END;
$$;


--
-- Name: FUNCTION issue20_set_organization_terminology(p_actor_email text, p_concept_key text, p_singular_label text, p_plural_label text, p_short_label text, p_is_active boolean, p_reason text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.issue20_set_organization_terminology(p_actor_email text, p_concept_key text, p_singular_label text, p_plural_label text, p_short_label text, p_is_active boolean, p_reason text) IS 'Audited directory-manager terminology update; never changes role identity or authorization.';


--
-- Name: contributor_member_links; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contributor_member_links (
    contributor_member_link_id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    contributor_id uuid NOT NULL,
    member_id uuid NOT NULL,
    status text DEFAULT 'active'::text NOT NULL,
    linked_at timestamp with time zone DEFAULT now() NOT NULL,
    linked_by uuid,
    ended_at timestamp with time zone,
    ended_by uuid,
    link_reason text,
    end_reason text,
    CONSTRAINT contributor_member_links_end_check CHECK ((((status = 'active'::text) AND (ended_at IS NULL)) OR ((status = 'ended'::text) AND (ended_at IS NOT NULL)))),
    CONSTRAINT contributor_member_links_status_check CHECK ((status = ANY (ARRAY['active'::text, 'ended'::text])))
);


--
-- Name: TABLE contributor_member_links; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.contributor_member_links IS 'Auditable history connecting an individual contributor to a member without merging either record.';


--
-- Name: link_contributor_to_member(uuid, uuid, uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.link_contributor_to_member(p_contributor_id uuid, p_member_id uuid, p_actor_id uuid, p_reason text DEFAULT NULL::text) RETURNS public.contributor_member_links
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_link public.contributor_member_links%ROWTYPE;
BEGIN
  IF p_actor_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.members m WHERE m.member_id = p_actor_id
      AND m.status = 'active' AND m.is_facilitator IS TRUE
      AND m.is_donations_reviewer IS TRUE
  ) THEN RAISE EXCEPTION 'An active donations reviewer is required.'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.members m
    WHERE m.member_id = p_member_id AND m.status = 'active'
  ) THEN RAISE EXCEPTION 'The selected member is not active.'; END IF;

  INSERT INTO public.contributor_member_links
    (contributor_id, member_id, status, linked_by, link_reason)
  VALUES (p_contributor_id, p_member_id, 'active', p_actor_id,
          NULLIF(btrim(p_reason), ''))
  RETURNING * INTO v_link;

  INSERT INTO public.audit_log (actor, action, entity_type, entity_id, details)
  SELECT actor.email, 'contributor.member_linked', 'contributor',
         p_contributor_id::text,
         jsonb_build_object('member_id', p_member_id, 'actor_id', p_actor_id,
                            'reason', NULLIF(btrim(p_reason), ''))
  FROM public.members actor WHERE actor.member_id = p_actor_id;
  RETURN v_link;
END $$;


--
-- Name: FUNCTION link_contributor_to_member(p_contributor_id uuid, p_member_id uuid, p_actor_id uuid, p_reason text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.link_contributor_to_member(p_contributor_id uuid, p_member_id uuid, p_actor_id uuid, p_reason text) IS 'Links an individual contributor to an active member while preserving both records and link history.';


--
-- Name: listmonk_mark_sync_failure(uuid, text, jsonb, interval); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.listmonk_mark_sync_failure(p_queue_id uuid, p_error text, p_response jsonb DEFAULT '{}'::jsonb, p_retry_after interval DEFAULT '00:05:00'::interval) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_queue public.listmonk_sync_queue%ROWTYPE;
  v_final_status text;
BEGIN
  SELECT * INTO v_queue
  FROM public.listmonk_sync_queue
  WHERE listmonk_sync_queue_id = p_queue_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'listmonk_sync_queue_id % not found', p_queue_id;
  END IF;

  v_final_status := CASE WHEN v_queue.attempts >= 5 THEN 'failed' ELSE 'pending' END;

  UPDATE public.listmonk_sync_queue
  SET status = v_final_status,
      available_at = CASE WHEN v_final_status = 'pending' THEN now() + p_retry_after ELSE available_at END,
      locked_at = NULL,
      last_error = NULLIF(p_error, ''),
      response_payload = COALESCE(p_response, '{}'::jsonb),
      updated_at = now()
  WHERE listmonk_sync_queue_id = p_queue_id;

  UPDATE public.member_emails
  SET listmonk_sync_status = CASE WHEN v_final_status = 'failed' THEN 'failed' ELSE 'pending' END,
      listmonk_sync_error = NULLIF(p_error, ''),
      updated_at = now()
  WHERE member_email_id = v_queue.member_email_id;

  INSERT INTO public.audit_log (actor, action, entity_type, entity_id, details)
  VALUES (
    v_queue.actor,
    'mailing.listmonk_sync_failed',
    'member_email',
    v_queue.member_email_id::text,
    jsonb_build_object(
      'queue_id', v_queue.listmonk_sync_queue_id,
      'event_type', v_queue.event_type,
      'source', v_queue.source,
      'email_normalized', v_queue.email_normalized,
      'attempts', v_queue.attempts,
      'final_status', v_final_status,
      'error', NULLIF(p_error, ''),
      'response', COALESCE(p_response, '{}'::jsonb)
    )
  );
END;
$$;


--
-- Name: listmonk_mark_sync_success(uuid, integer, uuid, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.listmonk_mark_sync_success(p_queue_id uuid, p_listmonk_subscriber_id integer DEFAULT NULL::integer, p_listmonk_subscriber_uuid uuid DEFAULT NULL::uuid, p_response jsonb DEFAULT '{}'::jsonb) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_queue public.listmonk_sync_queue%ROWTYPE;
BEGIN
  UPDATE public.listmonk_sync_queue
  SET status = 'succeeded',
      processed_at = now(),
      locked_at = NULL,
      response_payload = COALESCE(p_response, '{}'::jsonb),
      last_error = NULL,
      updated_at = now()
  WHERE listmonk_sync_queue_id = p_queue_id
  RETURNING * INTO v_queue;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'listmonk_sync_queue_id % not found', p_queue_id;
  END IF;

  UPDATE public.member_emails
  SET listmonk_subscriber_id = COALESCE(p_listmonk_subscriber_id, listmonk_subscriber_id),
      listmonk_subscriber_uuid = COALESCE(p_listmonk_subscriber_uuid, listmonk_subscriber_uuid),
      listmonk_synced_at = now(),
      listmonk_sync_status = 'synced',
      listmonk_sync_error = NULL,
      updated_at = now()
  WHERE member_email_id = v_queue.member_email_id;

  INSERT INTO public.audit_log (actor, action, entity_type, entity_id, details)
  VALUES (
    v_queue.actor,
    'mailing.listmonk_sync_succeeded',
    'member_email',
    v_queue.member_email_id::text,
    jsonb_build_object(
      'queue_id', v_queue.listmonk_sync_queue_id,
      'event_type', v_queue.event_type,
      'source', v_queue.source,
      'email_normalized', v_queue.email_normalized,
      'listmonk_list_id', v_queue.listmonk_list_id,
      'listmonk_subscriber_id', p_listmonk_subscriber_id,
      'listmonk_subscriber_uuid', p_listmonk_subscriber_uuid,
      'response', COALESCE(p_response, '{}'::jsonb)
    )
  );
END;
$$;


--
-- Name: listmonk_record_external_unsubscribe(text, integer, uuid, text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.listmonk_record_external_unsubscribe(p_email text, p_listmonk_subscriber_id integer DEFAULT NULL::integer, p_listmonk_subscriber_uuid uuid DEFAULT NULL::uuid, p_source text DEFAULT 'listmonk_unsubscribe_poll'::text, p_raw jsonb DEFAULT '{}'::jsonb) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_count integer := 0;
  v_row public.member_emails%ROWTYPE;
BEGIN
  FOR v_row IN
    SELECT *
    FROM public.member_emails
    WHERE email_normalized = lower(btrim(p_email))
      AND COALESCE(status, 'active') = 'active'
  LOOP
    UPDATE public.member_emails
    SET mailing_subscription_status = 'unsubscribed',
        mailing_unsubscribed_at = COALESCE(mailing_unsubscribed_at, now()),
        mailing_unsubscribe_source = COALESCE(NULLIF(p_source, ''), 'listmonk_unsubscribe_poll'),
        mailing_unsubscribe_reason = 'Unsubscribe observed in listmonk',
        listmonk_subscriber_id = COALESCE(p_listmonk_subscriber_id, listmonk_subscriber_id),
        listmonk_subscriber_uuid = COALESCE(p_listmonk_subscriber_uuid, listmonk_subscriber_uuid),
        listmonk_synced_at = now(),
        listmonk_sync_status = 'synced',
        listmonk_sync_error = NULL,
        updated_at = now()
    WHERE member_email_id = v_row.member_email_id;

    INSERT INTO public.audit_log (actor, action, entity_type, entity_id, details)
    VALUES (
      'listmonk',
      'mailing.unsubscribe_observed_from_listmonk',
      'member_email',
      v_row.member_email_id::text,
      jsonb_build_object(
        'member_id', v_row.member_id,
        'email', v_row.email,
        'email_normalized', v_row.email_normalized,
        'source', COALESCE(NULLIF(p_source, ''), 'listmonk_unsubscribe_poll'),
        'listmonk_subscriber_id', p_listmonk_subscriber_id,
        'listmonk_subscriber_uuid', p_listmonk_subscriber_uuid,
        'raw', COALESCE(p_raw, '{}'::jsonb)
      )
    );

    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;


--
-- Name: match_contributor_identity(text, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.match_contributor_identity(p_provider text, p_provider_identity text DEFAULT NULL::text, p_email text DEFAULT NULL::text, p_phone text DEFAULT NULL::text) RETURNS TABLE(contributor_id uuid, member_id uuid, match_method text, match_score integer)
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_contributor_id uuid;
  v_member_id uuid;
  v_method text;
  v_score integer;
  v_email text := NULLIF(lower(btrim(p_email)), '');
  v_phone text := NULLIF(public.normalize_us_phone(p_phone), '');
BEGIN
  -- Provider-native contact identity is strongest and globally unique within
  -- the provider by schema constraint.
  IF NULLIF(btrim(p_provider_identity), '') IS NOT NULL THEN
    SELECT cei.contributor_id, 'provider_identity', 120
    INTO v_contributor_id, v_method, v_score
    FROM public.contributor_external_identities cei
    JOIN public.contributors c ON c.contributor_id = cei.contributor_id
    WHERE lower(btrim(cei.provider)) = lower(btrim(p_provider))
      AND btrim(cei.provider_identity) = btrim(p_provider_identity)
      AND cei.status = 'active'
      AND c.status = 'active'
    LIMIT 1;
  END IF;

  -- Email is an automatic match only when exactly one active contributor has
  -- it. Shared organization/person inboxes therefore go to review.
  IF v_contributor_id IS NULL AND v_email IS NOT NULL THEN
    SELECT min(ce.contributor_id::text)::uuid, 'contributor_email', 100
    INTO v_contributor_id, v_method, v_score
    FROM public.contributor_emails ce
    JOIN public.contributors c ON c.contributor_id = ce.contributor_id
    WHERE ce.email_normalized = v_email
      AND ce.status = 'active'
      AND c.status = 'active'
    HAVING count(DISTINCT ce.contributor_id) = 1;
  END IF;

  -- During migration, a member may not yet have a contributor. A unique member
  -- email match creates the compatibility contributor lazily.
  IF v_contributor_id IS NULL AND v_email IS NOT NULL THEN
    SELECT min(matches.member_id::text)::uuid
    INTO v_member_id
    FROM (
      SELECT me.member_id
      FROM public.member_emails me
      JOIN public.members m ON m.member_id = me.member_id
      WHERE me.email_normalized = v_email
        AND me.status = 'active'
        AND m.status = 'active'

      UNION

      SELECT m.member_id
      FROM public.members m
      WHERE lower(btrim(m.email)) = v_email
        AND m.status = 'active'
    ) matches
    HAVING count(DISTINCT matches.member_id) = 1;

    IF v_member_id IS NOT NULL THEN
      v_contributor_id := public.ensure_member_contributor(v_member_id);
      v_method := 'member_email';
      v_score := 95;
    END IF;
  END IF;

  -- Phones may be shared. Match only when the normalized value identifies one
  -- active contributor.
  IF v_contributor_id IS NULL AND v_phone IS NOT NULL THEN
    SELECT min(cp.contributor_id::text)::uuid, 'contributor_phone', 85
    INTO v_contributor_id, v_method, v_score
    FROM public.contributor_phones cp
    JOIN public.contributors c ON c.contributor_id = cp.contributor_id
    WHERE cp.phone_normalized = v_phone
      AND cp.status = 'active'
      AND c.status = 'active'
    HAVING count(DISTINCT cp.contributor_id) = 1;
  END IF;

  IF v_contributor_id IS NULL AND v_phone IS NOT NULL THEN
    SELECT min(matches.member_id::text)::uuid
    INTO v_member_id
    FROM (
      SELECT mp.member_id
      FROM public.member_phones mp
      JOIN public.members m ON m.member_id = mp.member_id
      WHERE mp.phone_normalized = v_phone
        AND mp.status = 'active'
        AND m.status = 'active'

      UNION

      SELECT m.member_id
      FROM public.members m
      WHERE public.normalize_us_phone(m.phone) = v_phone
        AND m.status = 'active'
    ) matches
    HAVING count(DISTINCT matches.member_id) = 1;

    IF v_member_id IS NOT NULL THEN
      v_contributor_id := public.ensure_member_contributor(v_member_id);
      v_method := 'member_phone';
      v_score := 80;
    END IF;
  END IF;

  IF v_contributor_id IS NULL THEN
    RETURN;
  END IF;

  SELECT cml.member_id
  INTO v_member_id
  FROM public.contributor_member_links cml
  WHERE cml.contributor_id = v_contributor_id
    AND cml.status = 'active'
  LIMIT 1;

  contributor_id := v_contributor_id;
  member_id := v_member_id;
  match_method := v_method;
  match_score := v_score;
  RETURN NEXT;
END;
$$;


--
-- Name: FUNCTION match_contributor_identity(p_provider text, p_provider_identity text, p_email text, p_phone text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.match_contributor_identity(p_provider text, p_provider_identity text, p_email text, p_phone text) IS 'Matches provider identity, unique contributor email/phone, then unique member contact fallback in descending confidence order.';


--
-- Name: member_address_fingerprint(text, text, text, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.member_address_fingerprint(p_address_1 text, p_address_2 text, p_city text, p_state text, p_postal_code text, p_country text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
  SELECT NULLIF(
    concat_ws('|',
      COALESCE(public.member_contact_normalize_text(p_address_1), ''),
      COALESCE(public.member_contact_normalize_text(p_address_2), ''),
      COALESCE(public.member_contact_normalize_text(p_city), ''),
      COALESCE(public.member_contact_normalize_text(p_state), ''),
      COALESCE(public.member_contact_normalize_postal_code(p_postal_code), ''),
      COALESCE(public.member_contact_normalize_text(COALESCE(NULLIF(p_country, ''), 'USA')), '')
    ),
    '|||||'
  );
$$;


--
-- Name: member_address_identity_key(text, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.member_address_identity_key(p_address_1 text, p_address_2 text, p_postal_code text, p_country text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
  WITH parts AS (
    SELECT
      public.member_address_normalize_street(p_address_1) AS address_1,
      public.member_address_normalize_unit(p_address_2) AS address_2,
      public.member_address_identity_postal(
        p_postal_code,
        p_country
      ) AS postal_code,
      public.member_address_normalize_country(p_country) AS country
  )
  SELECT CASE
    WHEN address_1 IS NULL OR postal_code IS NULL THEN NULL
    ELSE concat_ws(
      '|',
      address_1,
      COALESCE(address_2, ''),
      postal_code,
      country
    )
  END
  FROM parts;
$$;


--
-- Name: FUNCTION member_address_identity_key(p_address_1 text, p_address_2 text, p_postal_code text, p_country text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.member_address_identity_key(p_address_1 text, p_address_2 text, p_postal_code text, p_country text) IS 'Returns a stable physical-address identity key using normalized street, unit, postal code, and country; city, state, and address type are intentionally excluded.';


--
-- Name: member_address_identity_postal(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.member_address_identity_postal(p_postal_code text, p_country text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $_$
  WITH normalized AS (
    SELECT
      public.member_contact_normalize_postal_code(p_postal_code) AS postal,
      public.member_address_normalize_country(p_country) AS country
  )
  SELECT CASE
    WHEN postal IS NULL THEN NULL
    WHEN country = 'us' AND postal ~ '^[0-9]{5}([0-9]{4})?$'
      THEN left(postal, 5)
    ELSE postal
  END
  FROM normalized;
$_$;


--
-- Name: member_address_normalize_country(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.member_address_normalize_country(p_text text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
  SELECT CASE COALESCE(
    public.member_contact_normalize_text(NULLIF(p_text, '')),
    'usa'
  )
    WHEN 'us' THEN 'us'
    WHEN 'usa' THEN 'us'
    WHEN 'united states' THEN 'us'
    WHEN 'united states of america' THEN 'us'
    WHEN 'ca' THEN 'ca'
    WHEN 'canada' THEN 'ca'
    ELSE COALESCE(
      public.member_contact_normalize_text(NULLIF(p_text, '')),
      'us'
    )
  END;
$$;


--
-- Name: member_address_normalize_street(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.member_address_normalize_street(p_text text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $_$
  WITH normalized AS (
    SELECT COALESCE(public.member_contact_normalize_text(p_text), '') AS value
  )
  SELECT NULLIF(
    btrim(
      regexp_replace(
        regexp_replace(
          regexp_replace(
            regexp_replace(
              regexp_replace(
                regexp_replace(
                  regexp_replace(
                    regexp_replace(
                      regexp_replace(
                        regexp_replace(
                          regexp_replace(
                            regexp_replace(
                              regexp_replace(
                                regexp_replace(
                                  regexp_replace(
                                    regexp_replace(value, '(^| )north( |$)', '\1n\2', 'g'),
                                    '(^| )south( |$)', '\1s\2', 'g'
                                  ),
                                  '(^| )east( |$)', '\1e\2', 'g'
                                ),
                                '(^| )west( |$)', '\1w\2', 'g'
                              ),
                              '(^| )street( |$)', '\1st\2', 'g'
                            ),
                            '(^| )avenue( |$)', '\1ave\2', 'g'
                          ),
                          '(^| )road( |$)', '\1rd\2', 'g'
                        ),
                        '(^| )drive( |$)', '\1dr\2', 'g'
                      ),
                      '(^| )court( |$)', '\1ct\2', 'g'
                    ),
                    '(^| )lane( |$)', '\1ln\2', 'g'
                  ),
                  '(^| )boulevard( |$)', '\1blvd\2', 'g'
                ),
                '(^| )parkway( |$)', '\1pkwy\2', 'g'
              ),
              '(^| )place( |$)', '\1pl\2', 'g'
            ),
            '(^| )terrace( |$)', '\1ter\2', 'g'
          ),
          '(^| )trail( |$)', '\1trl\2', 'g'
        ),
        '(^| )highway( |$)', '\1hwy\2', 'g'
      )
    ),
    ''
  )
  FROM normalized;
$_$;


--
-- Name: member_address_normalize_unit(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.member_address_normalize_unit(p_text text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
  WITH normalized AS (
    SELECT COALESCE(public.member_contact_normalize_text(p_text), '') AS value
  )
  SELECT NULLIF(
    regexp_replace(
      value,
      '^(apartment|apt|unit|suite|ste) ',
      '',
      'g'
    ),
    ''
  )
  FROM normalized;
$$;


--
-- Name: member_contact_normalize_postal_code(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.member_contact_normalize_postal_code(p_text text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
  SELECT NULLIF(upper(regexp_replace(COALESCE(p_text, ''), '[^a-z0-9]+', '', 'gi')), '');
$$;


--
-- Name: member_contact_normalize_text(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.member_contact_normalize_text(p_text text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
  SELECT NULLIF(
    btrim(
      regexp_replace(
        regexp_replace(lower(COALESCE(p_text, '')), '[^a-z0-9]+', ' ', 'g'),
        '\s+',
        ' ',
        'g'
      )
    ),
    ''
  );
$$;


--
-- Name: member_emails; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.member_emails (
    member_email_id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    member_id uuid NOT NULL,
    email text NOT NULL,
    email_normalized text GENERATED ALWAYS AS (lower(btrim(email))) STORED,
    is_primary boolean DEFAULT false NOT NULL,
    is_verified boolean DEFAULT false NOT NULL,
    source text,
    notes text,
    status text DEFAULT 'active'::text NOT NULL,
    archived_at timestamp with time zone,
    archived_by uuid,
    archive_reason text,
    verified_at timestamp with time zone,
    verified_by uuid,
    verification_source text,
    verification_notes text,
    mailing_subscription_status text DEFAULT 'subscribed'::text NOT NULL,
    mailing_subscription_source text,
    mailing_unsubscribed_at timestamp with time zone,
    mailing_unsubscribe_source text,
    mailing_unsubscribe_reason text,
    listmonk_list_id integer,
    listmonk_subscriber_id integer,
    listmonk_subscriber_uuid uuid,
    listmonk_synced_at timestamp with time zone,
    listmonk_sync_status text,
    listmonk_sync_error text,
    CONSTRAINT member_emails_listmonk_sync_status_chk CHECK (((listmonk_sync_status IS NULL) OR (listmonk_sync_status = ANY (ARRAY['pending'::text, 'synced'::text, 'failed'::text])))),
    CONSTRAINT member_emails_mailing_subscription_status_chk CHECK ((mailing_subscription_status = ANY (ARRAY['subscribed'::text, 'not_subscribed'::text, 'unsubscribed'::text, 'suppressed'::text, 'sync_error'::text])))
);


--
-- Name: member_email_request_mailing_subscribe(uuid, text, text, text, jsonb, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.member_email_request_mailing_subscribe(p_member_email_id uuid, p_actor text DEFAULT NULL::text, p_source text DEFAULT 'signaturegate_interface'::text, p_reason text DEFAULT NULL::text, p_raw jsonb DEFAULT '{}'::jsonb, p_enqueue_listmonk boolean DEFAULT true) RETURNS public.member_emails
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_email public.member_emails%ROWTYPE;
BEGIN
  UPDATE public.member_emails
  SET mailing_subscription_status = 'subscribed',
      mailing_subscription_source = COALESCE(NULLIF(p_source, ''), 'signaturegate_interface'),
      mailing_unsubscribed_at = NULL,
      mailing_unsubscribe_source = NULL,
      mailing_unsubscribe_reason = NULL,
      listmonk_sync_status = CASE WHEN p_enqueue_listmonk THEN 'pending' ELSE 'synced' END,
      listmonk_sync_error = NULL,
      updated_at = now()
  WHERE member_email_id = p_member_email_id
  RETURNING * INTO v_email;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'member_email_id % not found', p_member_email_id;
  END IF;

  INSERT INTO public.audit_log (actor, action, entity_type, entity_id, details)
  VALUES (
    NULLIF(lower(btrim(p_actor)), ''),
    'mailing.subscribe_recorded',
    'member_email',
    v_email.member_email_id::text,
    jsonb_build_object(
      'member_id', v_email.member_id,
      'email', v_email.email,
      'email_normalized', v_email.email_normalized,
      'source', COALESCE(NULLIF(p_source, ''), 'signaturegate_interface'),
      'reason', NULLIF(p_reason, ''),
      'enqueue_listmonk', p_enqueue_listmonk,
      'raw', COALESCE(p_raw, '{}'::jsonb)
    )
  );

  IF p_enqueue_listmonk THEN
    PERFORM public.enqueue_listmonk_email_sync(
      v_email.member_email_id,
      'subscribe',
      COALESCE(NULLIF(p_source, ''), 'signaturegate_interface'),
      p_actor,
      jsonb_build_object('reason', NULLIF(p_reason, ''), 'raw', COALESCE(p_raw, '{}'::jsonb))
    );
  END IF;

  RETURN v_email;
END;
$$;


--
-- Name: member_email_request_mailing_unsubscribe(uuid, text, text, text, jsonb, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.member_email_request_mailing_unsubscribe(p_member_email_id uuid, p_actor text DEFAULT NULL::text, p_source text DEFAULT 'signaturegate_interface'::text, p_reason text DEFAULT NULL::text, p_raw jsonb DEFAULT '{}'::jsonb, p_enqueue_listmonk boolean DEFAULT true) RETURNS public.member_emails
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_email public.member_emails%ROWTYPE;
BEGIN
  UPDATE public.member_emails
  SET mailing_subscription_status = 'unsubscribed',
      mailing_unsubscribed_at = COALESCE(mailing_unsubscribed_at, now()),
      mailing_unsubscribe_source = COALESCE(NULLIF(p_source, ''), 'signaturegate_interface'),
      mailing_unsubscribe_reason = NULLIF(p_reason, ''),
      listmonk_sync_status = CASE WHEN p_enqueue_listmonk THEN 'pending' ELSE 'synced' END,
      listmonk_sync_error = NULL,
      updated_at = now()
  WHERE member_email_id = p_member_email_id
  RETURNING * INTO v_email;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'member_email_id % not found', p_member_email_id;
  END IF;

  INSERT INTO public.audit_log (actor, action, entity_type, entity_id, details)
  VALUES (
    NULLIF(lower(btrim(p_actor)), ''),
    'mailing.unsubscribe_recorded',
    'member_email',
    v_email.member_email_id::text,
    jsonb_build_object(
      'member_id', v_email.member_id,
      'email', v_email.email,
      'email_normalized', v_email.email_normalized,
      'source', COALESCE(NULLIF(p_source, ''), 'signaturegate_interface'),
      'reason', NULLIF(p_reason, ''),
      'enqueue_listmonk', p_enqueue_listmonk,
      'raw', COALESCE(p_raw, '{}'::jsonb)
    )
  );

  IF p_enqueue_listmonk THEN
    PERFORM public.enqueue_listmonk_email_sync(
      v_email.member_email_id,
      'unsubscribe',
      COALESCE(NULLIF(p_source, ''), 'signaturegate_interface'),
      p_actor,
      jsonb_build_object('reason', NULLIF(p_reason, ''), 'raw', COALESCE(p_raw, '{}'::jsonb))
    );
  END IF;

  RETURN v_email;
END;
$$;


--
-- Name: member_email_set_primary(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.member_email_set_primary(p_member_email_id uuid, p_actor_member_id uuid DEFAULT NULL::uuid) RETURNS public.member_emails
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_row public.member_emails;
BEGIN
  SELECT *
  INTO v_row
  FROM public.member_emails
  WHERE member_email_id = p_member_email_id
    AND COALESCE(status, 'active') = 'active';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Active member_email_id % not found', p_member_email_id
      USING ERRCODE = 'no_data_found';
  END IF;

  UPDATE public.member_emails
  SET
    is_primary = false,
    updated_at = now()
  WHERE member_id = v_row.member_id
    AND member_email_id <> p_member_email_id
    AND COALESCE(status, 'active') = 'active'
    AND COALESCE(is_primary, false) = true;

  UPDATE public.member_emails
  SET
    is_primary = true,
    updated_at = now(),
    verified_by = COALESCE(verified_by, p_actor_member_id)
  WHERE member_email_id = p_member_email_id
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;


--
-- Name: member_emails_enforce_single_primary_trg(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.member_emails_enforce_single_primary_trg() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF COALESCE(NEW.status, 'active') = 'active'
     AND COALESCE(NEW.is_primary, false) = true THEN
    UPDATE public.member_emails
    SET
      is_primary = false,
      updated_at = now()
    WHERE member_id = NEW.member_id
      AND member_email_id <> NEW.member_email_id
      AND COALESCE(status, 'active') = 'active'
      AND COALESCE(is_primary, false) = true;
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: normalize_us_phone(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.normalize_us_phone(p_phone text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
  SELECT CASE
    WHEN p_phone IS NULL THEN NULL
    WHEN length(regexp_replace(p_phone, '\D', '', 'g')) = 11
      AND left(regexp_replace(p_phone, '\D', '', 'g'), 1) = '1'
      THEN right(regexp_replace(p_phone, '\D', '', 'g'), 10)
    ELSE regexp_replace(p_phone, '\D', '', 'g')
  END;
$$;


--
-- Name: prevent_confirmed_cash_deposit_item_mutation(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.prevent_confirmed_cash_deposit_item_mutation() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: prevent_confirmed_cash_deposit_mutation(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.prevent_confirmed_cash_deposit_mutation() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: reconcile_linked_person(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.reconcile_linked_person() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_member_person uuid;
  v_donor_person uuid;
  v_keep uuid;
  v_drop uuid;
  v_member_name text;
  v_donor_name text;
  v_member_first text;
  v_member_last text;
  v_donor_first text;
  v_donor_last text;
BEGIN
  IF NEW.status <> 'active' THEN RETURN NULL; END IF;
  SELECT m.person_id, p.display_name, p.first_name, p.last_name
    INTO v_member_person, v_member_name, v_member_first, v_member_last
    FROM public.members m JOIN public.people p ON p.person_id = m.person_id
    WHERE m.member_id = NEW.member_id FOR UPDATE OF m;
  SELECT c.person_id, p.display_name, p.first_name, p.last_name
    INTO v_donor_person, v_donor_name, v_donor_first, v_donor_last
    FROM public.contributors c JOIN public.people p ON p.person_id = c.person_id
    WHERE c.contributor_id = NEW.contributor_id FOR UPDATE OF c;

  IF v_member_person = v_donor_person THEN RETURN NULL; END IF;
  SELECT CASE WHEN cp.created_at < mp.created_at
              THEN v_donor_person ELSE v_member_person END
  INTO v_keep
  FROM public.people cp CROSS JOIN public.people mp
  WHERE cp.person_id = v_donor_person AND mp.person_id = v_member_person;

  INSERT INTO public.person_identity_review
    (person_id, member_id, contributor_id, member_name, contributor_name,
     member_names, contributor_names)
  SELECT v_keep, NEW.member_id, NEW.contributor_id,
    v_member_name, v_donor_name,
    jsonb_build_object('first_name', v_member_first, 'last_name', v_member_last),
    jsonb_build_object('first_name', v_donor_first, 'last_name', v_donor_last)
  WHERE (v_member_first, v_member_last, lower(btrim(v_member_name)))
    IS DISTINCT FROM (v_donor_first, v_donor_last, lower(btrim(v_donor_name)))
  ON CONFLICT (member_id, contributor_id) DO NOTHING;

  IF v_keep = v_donor_person THEN
    v_drop := v_member_person;
    UPDATE public.members SET person_id = v_keep WHERE member_id = NEW.member_id;
  ELSE
    v_drop := v_donor_person;
    UPDATE public.contributors SET person_id = v_keep
    WHERE contributor_id = NEW.contributor_id;
  END IF;

  DELETE FROM public.people p WHERE p.person_id = v_drop
    AND NOT EXISTS (SELECT 1 FROM public.members m WHERE m.person_id = v_drop)
    AND NOT EXISTS (SELECT 1 FROM public.contributors c WHERE c.person_id = v_drop)
    AND NOT EXISTS (SELECT 1 FROM public.person_identity_review r WHERE r.person_id = v_drop);
  RETURN NULL;
END $$;


--
-- Name: donations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.donations (
    donation_id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    member_id uuid,
    provider text NOT NULL,
    provider_reference text,
    amount_cents integer,
    currency text DEFAULT 'USD'::text,
    donated_at timestamp with time zone,
    notes text,
    status text DEFAULT 'imported'::text NOT NULL,
    facilitator_id uuid,
    reviewer_id uuid,
    reviewed_at timestamp with time zone,
    review_notes text,
    donor_kind text NOT NULL,
    contributor_id uuid,
    CONSTRAINT donations_donor_identity_check CHECK ((((donor_kind = 'identified'::text) AND (contributor_id IS NOT NULL)) OR ((donor_kind = ANY (ARRAY['anonymous'::text, 'unresolved'::text])) AND (contributor_id IS NULL) AND (member_id IS NULL)))),
    CONSTRAINT donations_donor_kind_check CHECK ((donor_kind = ANY (ARRAY['identified'::text, 'anonymous'::text, 'unresolved'::text]))),
    CONSTRAINT donations_donor_kind_provider_check CHECK ((((donor_kind <> 'anonymous'::text) OR (provider = 'cash'::text)) AND ((donor_kind <> 'unresolved'::text) OR (provider <> 'cash'::text))))
);


--
-- Name: COLUMN donations.donor_kind; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.donations.donor_kind IS 'Donation identity state: identified contributor, deliberately anonymous cash, or unresolved provider import.';


--
-- Name: COLUMN donations.contributor_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.donations.contributor_id IS 'Identified contributor for the donation. Membership remains optional and is retained in member_id only as a compatibility projection.';


--
-- Name: record_cash_donation(uuid, boolean, integer, timestamp with time zone, text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.record_cash_donation(p_member_id uuid, p_is_anonymous boolean, p_amount_cents integer, p_donated_at timestamp with time zone, p_notes text, p_facilitator_id uuid) RETURNS public.donations
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
BEGIN
  RETURN public.record_cash_donation_for_contributor(
    CASE
      WHEN COALESCE(p_is_anonymous, false) THEN NULL
      ELSE public.ensure_member_contributor(p_member_id)
    END,
    p_is_anonymous,
    p_amount_cents,
    p_donated_at,
    p_notes,
    p_facilitator_id
  );
END;
$$;


--
-- Name: FUNCTION record_cash_donation(p_member_id uuid, p_is_anonymous boolean, p_amount_cents integer, p_donated_at timestamp with time zone, p_notes text, p_facilitator_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.record_cash_donation(p_member_id uuid, p_is_anonymous boolean, p_amount_cents integer, p_donated_at timestamp with time zone, p_notes text, p_facilitator_id uuid) IS 'Records member-linked or deliberately anonymous cash as pending review without creating a synthetic member.';


--
-- Name: record_cash_donation_for_contributor(uuid, boolean, integer, timestamp with time zone, text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.record_cash_donation_for_contributor(p_contributor_id uuid, p_is_anonymous boolean, p_amount_cents integer, p_donated_at timestamp with time zone, p_notes text, p_facilitator_id uuid) RETURNS public.donations
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_result public.donations%ROWTYPE;
  v_member_id uuid;
BEGIN
  IF p_facilitator_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.members m
    WHERE m.member_id = p_facilitator_id
      AND m.status = 'active'
      AND m.is_facilitator IS TRUE
  ) THEN
    RAISE EXCEPTION 'An active facilitator is required to record a cash donation.';
  END IF;

  IF p_amount_cents IS NULL OR p_amount_cents <= 0 THEN
    RAISE EXCEPTION 'Cash donation amount must be positive.';
  END IF;

  IF COALESCE(p_is_anonymous, false) THEN
    IF p_contributor_id IS NOT NULL THEN
      RAISE EXCEPTION 'Anonymous cash donations cannot reference a contributor.';
    END IF;
  ELSIF p_contributor_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.contributors c
    WHERE c.contributor_id = p_contributor_id
      AND c.status = 'active'
  ) THEN
    RAISE EXCEPTION 'An active contributor is required unless cash is explicitly anonymous.';
  END IF;

  IF p_contributor_id IS NOT NULL THEN
    SELECT cml.member_id INTO v_member_id
    FROM public.contributor_member_links cml
    WHERE cml.contributor_id = p_contributor_id
      AND cml.status = 'active'
    LIMIT 1;
  END IF;

  INSERT INTO public.donations (
    contributor_id,
    member_id,
    donor_kind,
    provider,
    amount_cents,
    currency,
    donated_at,
    notes,
    status,
    facilitator_id
  )
  VALUES (
    CASE WHEN COALESCE(p_is_anonymous, false) THEN NULL ELSE p_contributor_id END,
    CASE WHEN COALESCE(p_is_anonymous, false) THEN NULL ELSE v_member_id END,
    CASE WHEN COALESCE(p_is_anonymous, false) THEN 'anonymous' ELSE 'identified' END,
    'cash',
    p_amount_cents,
    'USD',
    COALESCE(p_donated_at, now()),
    NULLIF(btrim(p_notes), ''),
    'pending_review',
    p_facilitator_id
  )
  RETURNING * INTO v_result;

  RETURN v_result;
END;
$$;


--
-- Name: record_cash_donation_identity(text, boolean, integer, timestamp with time zone, text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.record_cash_donation_identity(p_choice text, p_is_anonymous boolean, p_amount_cents integer, p_donated_at timestamp with time zone, p_notes text, p_facilitator_id uuid) RETURNS public.donations
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_contributor_id uuid;
BEGIN
  IF COALESCE(p_is_anonymous, false) OR p_choice = '__anonymous__' THEN
    RETURN public.record_cash_donation_for_contributor(
      NULL, true, p_amount_cents, p_donated_at, p_notes, p_facilitator_id
    );
  ELSIF p_choice LIKE 'contributor:%' THEN
    v_contributor_id := substring(p_choice FROM 13)::uuid;
  ELSIF p_choice LIKE 'member:%' THEN
    v_contributor_id := public.ensure_member_contributor(substring(p_choice FROM 8)::uuid);
  ELSE
    RAISE EXCEPTION 'Select an existing contributor, member, or Anonymous cash donor.';
  END IF;

  RETURN public.record_cash_donation_for_contributor(
    v_contributor_id,
    false,
    p_amount_cents,
    p_donated_at,
    p_notes,
    p_facilitator_id
  );
END;
$$;


--
-- Name: refresh_party_contact_status(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.refresh_party_contact_status(p_contact_id uuid) RETURNS void
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE v_active boolean; v_verified boolean;
BEGIN
  SELECT COALESCE(bool_or(status = 'active'), false),
    COALESCE(bool_or(status = 'active' AND is_verified), false)
  INTO v_active, v_verified FROM public.party_contact_sources
  WHERE party_contact_id = p_contact_id;
  UPDATE public.party_contacts c
  SET status = CASE WHEN v_active THEN 'active' ELSE 'archived' END,
      is_verified = v_verified
  WHERE c.party_contact_id = p_contact_id
    AND (c.status, c.is_verified) IS DISTINCT FROM
      (CASE WHEN v_active THEN 'active' ELSE 'archived' END, v_verified);
END $$;


--
-- Name: remove_cash_deposit_item(uuid, uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.remove_cash_deposit_item(p_deposit_batch_id uuid, p_donation_id uuid, p_actor_id uuid) RETURNS void
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: resolve_pending_donation(uuid, uuid, uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.resolve_pending_donation(p_donation_id uuid, p_reviewer_id uuid, p_contributor_id uuid, p_review_notes text DEFAULT NULL::text) RETURNS public.donations
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_donation public.donations%ROWTYPE;
  v_member_id uuid;
BEGIN
  IF p_reviewer_id IS NULL OR NOT EXISTS (
    SELECT 1
    FROM public.members m
    WHERE m.member_id = p_reviewer_id
      AND m.status = 'active'
      AND m.is_facilitator IS TRUE
      AND m.is_donations_reviewer IS TRUE
  ) THEN
    RAISE EXCEPTION 'An active donations reviewer is required.';
  END IF;

  IF p_contributor_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.contributors c
    WHERE c.contributor_id = p_contributor_id
      AND c.status = 'active'
  ) THEN
    RAISE EXCEPTION 'An active contributor is required.';
  END IF;

  SELECT *
  INTO v_donation
  FROM public.donations d
  WHERE d.donation_id = p_donation_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Donation % was not found.', p_donation_id;
  END IF;

  IF v_donation.provider = 'cash'
    OR v_donation.donor_kind <> 'unresolved'
    OR v_donation.status <> 'pending_review'
  THEN
    RAISE EXCEPTION 'Only an unresolved provider donation can be assigned.';
  END IF;

  SELECT cml.member_id
  INTO v_member_id
  FROM public.contributor_member_links cml
  WHERE cml.contributor_id = p_contributor_id
    AND cml.status = 'active'
  LIMIT 1;

  UPDATE public.donations d
  SET
    contributor_id = p_contributor_id,
    member_id = v_member_id,
    donor_kind = 'identified',
    status = 'verified',
    reviewer_id = p_reviewer_id,
    reviewed_at = now(),
    review_notes = NULLIF(btrim(p_review_notes), '')
  WHERE d.donation_id = p_donation_id
  RETURNING * INTO v_donation;

  PERFORM public.add_donation_payload_to_contributor(
    p_contributor_id,
    p_donation_id,
    v_donation.provider || '_review'
  );

  INSERT INTO public.audit_log (actor, action, entity_type, entity_id, details)
  SELECT
    reviewer.email,
    'donation.contributor_resolved',
    'donation',
    p_donation_id::text,
    jsonb_build_object(
      'contributor_id', p_contributor_id,
      'member_id', v_member_id,
      'reviewer_id', p_reviewer_id,
      'review_notes', NULLIF(btrim(p_review_notes), '')
    )
  FROM public.members reviewer
  WHERE reviewer.member_id = p_reviewer_id;

  RETURN v_donation;
END;
$$;


--
-- Name: FUNCTION resolve_pending_donation(p_donation_id uuid, p_reviewer_id uuid, p_contributor_id uuid, p_review_notes text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.resolve_pending_donation(p_donation_id uuid, p_reviewer_id uuid, p_contributor_id uuid, p_review_notes text) IS 'Assigns an unresolved provider donation to an existing contributor and records reviewer audit data.';


--
-- Name: resolve_pending_donation_choice(uuid, uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.resolve_pending_donation_choice(p_donation_id uuid, p_reviewer_id uuid, p_choice text, p_review_notes text DEFAULT NULL::text) RETURNS public.donations
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_contributor_id uuid;
  v_kind text;
  v_donation public.donations%ROWTYPE;
BEGIN
  IF p_choice LIKE 'contributor:%' THEN
    v_contributor_id := substring(p_choice FROM 13)::uuid;
  ELSIF p_choice LIKE 'member:%' THEN
    v_contributor_id := public.ensure_member_contributor(substring(p_choice FROM 8)::uuid);
  ELSIF p_choice IN ('__new_individual__', '__new_organization__') THEN
    v_kind := CASE
      WHEN p_choice = '__new_organization__' THEN 'organization'
      ELSE 'individual'
    END;

    SELECT c.contributor_id
    INTO v_contributor_id
    FROM public.create_contributor_from_pending_donation(
      p_donation_id,
      p_reviewer_id,
      v_kind,
      NULL,
      p_review_notes
    ) c;
  ELSE
    RAISE EXCEPTION 'Unsupported contributor resolution choice.';
  END IF;

  IF p_choice IN ('__new_individual__', '__new_organization__') THEN
    SELECT * INTO v_donation
    FROM public.donations d
    WHERE d.donation_id = p_donation_id;

    RETURN v_donation;
  END IF;

  RETURN public.resolve_pending_donation(
    p_donation_id,
    p_reviewer_id,
    v_contributor_id,
    p_review_notes
  );
END;
$$;


--
-- Name: review_pending_donation(uuid, uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.review_pending_donation(p_donation_id uuid, p_reviewer_id uuid, p_new_status text, p_review_notes text DEFAULT NULL::text) RETURNS public.donations
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_donation public.donations%ROWTYPE;
BEGIN
  IF p_reviewer_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.members m
    WHERE m.member_id = p_reviewer_id
      AND m.status = 'active'
      AND m.is_facilitator IS TRUE
      AND m.is_donations_reviewer IS TRUE
  ) THEN
    RAISE EXCEPTION 'An active donations reviewer is required.';
  END IF;

  SELECT * INTO v_donation
  FROM public.donations d
  WHERE d.donation_id = p_donation_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Donation % was not found.', p_donation_id;
  END IF;

  IF v_donation.status <> 'pending_review' THEN
    RAISE EXCEPTION 'Donation % is %, not pending_review.', p_donation_id, v_donation.status;
  END IF;

  IF v_donation.provider = 'cash' THEN
    IF v_donation.donor_kind NOT IN ('identified', 'anonymous') THEN
      RAISE EXCEPTION 'Cash donation % has invalid donor identity.', p_donation_id;
    END IF;
    IF v_donation.amount_cents IS NULL OR v_donation.amount_cents <= 0 THEN
      RAISE EXCEPTION 'Cash donation % must have a positive amount.', p_donation_id;
    END IF;
    IF p_new_status IS NULL OR p_new_status NOT IN ('verified', 'rejected') THEN
      RAISE EXCEPTION 'Cash review status must be verified or rejected.';
    END IF;
  ELSE
    IF v_donation.donor_kind <> 'unresolved'
      OR v_donation.contributor_id IS NOT NULL
      OR v_donation.member_id IS NOT NULL
      OR p_new_status IS DISTINCT FROM 'ignored'
    THEN
      RAISE EXCEPTION 'Only unresolved provider donations may be ignored through this action.';
    END IF;
  END IF;

  UPDATE public.donations
  SET
    status = p_new_status,
    reviewer_id = p_reviewer_id,
    reviewed_at = now(),
    review_notes = NULLIF(btrim(p_review_notes), '')
  WHERE donation_id = p_donation_id
  RETURNING * INTO v_donation;

  RETURN v_donation;
END;
$$;


--
-- Name: FUNCTION review_pending_donation(p_donation_id uuid, p_reviewer_id uuid, p_new_status text, p_review_notes text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.review_pending_donation(p_donation_id uuid, p_reviewer_id uuid, p_new_status text, p_review_notes text) IS 'Verifies/rejects pending cash or ignores an unresolved provider donation, enforcing donations-reviewer authority.';


--
-- Name: set_agreement_templates_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_agreement_templates_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;


--
-- Name: set_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;


--
-- Name: sync_party_contact_source(text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sync_party_contact_source(p_table text, p_source_id uuid) RETURNS void
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $_$
DECLARE
  v_id_column text;
  v_row jsonb;
  v_person_id uuid;
  v_organization_id uuid;
  v_party_id uuid;
  v_kind text;
  v_value text;
  v_address_1 text;
  v_address_2 text;
  v_city text;
  v_state text;
  v_postal_code text;
  v_country text;
  v_key text;
  v_contact_id uuid;
  v_old_contact_id uuid;
BEGIN
  IF p_source_id IS NULL THEN RAISE EXCEPTION 'A contact source ID is required'; END IF;
  CASE p_table
    WHEN 'member_emails' THEN v_id_column := 'member_email_id'; v_kind := 'email';
    WHEN 'member_phones' THEN v_id_column := 'member_phone_id'; v_kind := 'phone';
    WHEN 'member_addresses' THEN v_id_column := 'member_address_id'; v_kind := 'address';
    WHEN 'contributor_emails' THEN v_id_column := 'contributor_email_id'; v_kind := 'email';
    WHEN 'contributor_phones' THEN v_id_column := 'contributor_phone_id'; v_kind := 'phone';
    WHEN 'contributor_addresses' THEN v_id_column := 'contributor_address_id'; v_kind := 'address';
    ELSE RAISE EXCEPTION 'Unsupported contact source table %', p_table;
  END CASE;

  SELECT party_contact_id INTO v_old_contact_id FROM public.party_contact_sources
  WHERE source_table = p_table AND source_id = p_source_id;
  IF left(p_table, 7) = 'member_' THEN
    EXECUTE format('SELECT to_jsonb(t), m.person_id, NULL::uuid
      FROM public.%I t JOIN public.members m ON m.member_id = t.member_id
      WHERE t.%I = $1', p_table, v_id_column)
      INTO v_row, v_person_id, v_organization_id USING p_source_id;
  ELSE
    EXECUTE format('SELECT to_jsonb(t), c.person_id, c.organization_id
      FROM public.%I t JOIN public.contributors c
      ON c.contributor_id = t.contributor_id WHERE t.%I = $1',
      p_table, v_id_column)
      INTO v_row, v_person_id, v_organization_id USING p_source_id;
  END IF;

  IF v_row IS NULL THEN
    DELETE FROM public.party_contact_sources
    WHERE source_table = p_table AND source_id = p_source_id;
    IF v_old_contact_id IS NOT NULL THEN
      PERFORM public.refresh_party_contact_status(v_old_contact_id);
    END IF;
    RETURN;
  END IF;

  v_party_id := COALESCE(v_person_id, v_organization_id);
  IF v_party_id IS NULL THEN
    RAISE EXCEPTION 'Contact source %/% has no party', p_table, p_source_id;
  END IF;
  v_value := CASE v_kind WHEN 'email' THEN v_row->>'email'
    WHEN 'phone' THEN v_row->>'phone' END;
  v_address_1 := v_row->>'address_1';
  v_address_2 := v_row->>'address_2';
  v_city := v_row->>'city';
  v_state := v_row->>'state';
  v_postal_code := v_row->>'postal_code';
  v_country := v_row->>'country';
  v_key := CASE v_kind
    WHEN 'email' THEN NULLIF(lower(btrim(v_value)), '')
    WHEN 'phone' THEN NULLIF(public.normalize_us_phone(v_value), '')
    WHEN 'address' THEN NULLIF(public.member_address_identity_key(
      v_address_1, v_address_2, v_postal_code, v_country), '') END;

  -- Empty legacy rows remain untouched but cannot become valid contacts.
  IF (v_kind IN ('email','phone') AND NULLIF(btrim(v_value), '') IS NULL)
    OR (v_kind = 'address' AND NULLIF(btrim(v_address_1), '') IS NULL) THEN
    DELETE FROM public.party_contact_sources
    WHERE source_table = p_table AND source_id = p_source_id;
    IF v_old_contact_id IS NOT NULL THEN
      PERFORM public.refresh_party_contact_status(v_old_contact_id);
    END IF;
    RETURN;
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(
    v_party_id::text || ':' || v_kind, 190019));
  IF v_key IS NOT NULL THEN
    SELECT party_contact_id INTO v_contact_id FROM public.party_contacts c
    WHERE c.contact_kind = v_kind AND c.identity_key = v_key
      AND c.person_id IS NOT DISTINCT FROM v_person_id
      AND c.organization_id IS NOT DISTINCT FROM v_organization_id
    FOR UPDATE;
  END IF;
  IF v_contact_id IS NULL AND v_old_contact_id IS NOT NULL THEN
    SELECT party_contact_id INTO v_contact_id FROM public.party_contacts c
    WHERE c.party_contact_id = v_old_contact_id AND c.contact_kind = v_kind
      AND c.person_id IS NOT DISTINCT FROM v_person_id
      AND c.organization_id IS NOT DISTINCT FROM v_organization_id
      AND c.identity_key IS NOT DISTINCT FROM v_key
    FOR UPDATE;
  END IF;

  IF v_contact_id IS NULL THEN
    INSERT INTO public.party_contacts
      (person_id, organization_id, contact_kind, contact_value,
       address_1, address_2, city, state, postal_code, country)
    VALUES (v_person_id, v_organization_id, v_kind, v_value,
      CASE WHEN v_kind = 'address' THEN v_address_1 END,
      CASE WHEN v_kind = 'address' THEN v_address_2 END,
      CASE WHEN v_kind = 'address' THEN v_city END,
      CASE WHEN v_kind = 'address' THEN v_state END,
      CASE WHEN v_kind = 'address' THEN v_postal_code END,
      CASE WHEN v_kind = 'address' THEN v_country END)
    RETURNING party_contact_id INTO v_contact_id;
  ELSIF v_old_contact_id = v_contact_id THEN
    -- Preserve a member's display spelling when a donor source is linked.
    -- Editing an already mapped source updates the canonical presentation.
    UPDATE public.party_contacts c
    SET contact_value = v_value,
        address_1 = CASE WHEN v_kind = 'address' THEN v_address_1 END,
        address_2 = CASE WHEN v_kind = 'address' THEN v_address_2 END,
        city = CASE WHEN v_kind = 'address' THEN v_city END,
        state = CASE WHEN v_kind = 'address' THEN v_state END,
        postal_code = CASE WHEN v_kind = 'address' THEN v_postal_code END,
        country = CASE WHEN v_kind = 'address' THEN v_country END
    WHERE c.party_contact_id = v_contact_id
      AND (c.contact_value, c.address_1, c.address_2, c.city,
        c.state, c.postal_code, c.country)
        IS DISTINCT FROM (v_value,
          CASE WHEN v_kind = 'address' THEN v_address_1 END,
          CASE WHEN v_kind = 'address' THEN v_address_2 END,
          CASE WHEN v_kind = 'address' THEN v_city END,
          CASE WHEN v_kind = 'address' THEN v_state END,
          CASE WHEN v_kind = 'address' THEN v_postal_code END,
          CASE WHEN v_kind = 'address' THEN v_country END);
  END IF;

  INSERT INTO public.party_contact_sources
    (source_table, source_id, party_contact_id, source, status, is_primary,
     is_verified, address_type, notes)
  VALUES (p_table, p_source_id, v_contact_id, v_row->>'source',
    CASE WHEN v_row->>'status' = 'active' THEN 'active' ELSE 'archived' END,
    COALESCE((v_row->>'is_primary')::boolean, false),
    COALESCE((v_row->>'is_verified')::boolean, false),
    v_row->>'address_type', v_row->>'notes')
  ON CONFLICT (source_table, source_id) DO UPDATE
    SET party_contact_id = EXCLUDED.party_contact_id,
        source = EXCLUDED.source,
        status = EXCLUDED.status,
        is_primary = EXCLUDED.is_primary,
        is_verified = EXCLUDED.is_verified,
        address_type = EXCLUDED.address_type,
        notes = EXCLUDED.notes;

  PERFORM public.refresh_party_contact_status(v_contact_id);
  IF v_old_contact_id IS NOT NULL AND v_old_contact_id <> v_contact_id THEN
    PERFORM public.refresh_party_contact_status(v_old_contact_id);
  END IF;
END $_$;


--
-- Name: sync_party_contact_source_trigger(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sync_party_contact_source_trigger() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE v_id_column text; v_id uuid;
BEGIN
  v_id_column := CASE TG_TABLE_NAME
    WHEN 'member_emails' THEN 'member_email_id'
    WHEN 'member_phones' THEN 'member_phone_id'
    WHEN 'member_addresses' THEN 'member_address_id'
    WHEN 'contributor_emails' THEN 'contributor_email_id'
    WHEN 'contributor_phones' THEN 'contributor_phone_id'
    WHEN 'contributor_addresses' THEN 'contributor_address_id'
    ELSE NULL END;
  IF v_id_column IS NULL THEN RAISE EXCEPTION 'Unsupported contact trigger table'; END IF;
  v_id := ((CASE WHEN TG_OP = 'DELETE' THEN to_jsonb(OLD)
    ELSE to_jsonb(NEW) END)->>v_id_column)::uuid;
  PERFORM public.sync_party_contact_source(TG_TABLE_NAME, v_id);
  RETURN NULL;
END $$;


--
-- Name: sync_party_owner_contacts_trigger(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sync_party_owner_contacts_trigger() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE v record;
BEGIN
  IF TG_TABLE_NAME = 'members' THEN
    FOR v IN SELECT 'member_emails'::text tab, member_email_id id
      FROM public.member_emails WHERE member_id = NEW.member_id
      UNION ALL SELECT 'member_phones', member_phone_id
      FROM public.member_phones WHERE member_id = NEW.member_id
      UNION ALL SELECT 'member_addresses', member_address_id
      FROM public.member_addresses WHERE member_id = NEW.member_id
    LOOP PERFORM public.sync_party_contact_source(v.tab, v.id); END LOOP;
  ELSE
    FOR v IN SELECT 'contributor_emails'::text tab, contributor_email_id id
      FROM public.contributor_emails WHERE contributor_id = NEW.contributor_id
      UNION ALL SELECT 'contributor_phones', contributor_phone_id
      FROM public.contributor_phones WHERE contributor_id = NEW.contributor_id
      UNION ALL SELECT 'contributor_addresses', contributor_address_id
      FROM public.contributor_addresses WHERE contributor_id = NEW.contributor_id
    LOOP PERFORM public.sync_party_contact_source(v.tab, v.id); END LOOP;
  END IF;
  RETURN NULL;
END $$;


--
-- Name: trg_member_emails_listmonk_insert(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_member_emails_listmonk_insert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF COALESCE(NEW.status, 'active') = 'active'
     AND NEW.mailing_subscription_status = 'subscribed'
     AND NEW.email_normalized IS NOT NULL
     AND NEW.email_normalized <> '' THEN
    PERFORM public.enqueue_listmonk_email_sync(
      NEW.member_email_id,
      'subscribe',
      COALESCE(NEW.mailing_subscription_source, NEW.source, 'member_email_insert'),
      NULL,
      jsonb_build_object('trigger', 'member_emails_after_insert')
    );
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: unlink_contributor_from_member(uuid, uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.unlink_contributor_from_member(p_contributor_id uuid, p_actor_id uuid, p_reason text) RETURNS public.contributor_member_links
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_link public.contributor_member_links%ROWTYPE;
BEGIN
  IF p_actor_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.members m
    WHERE m.member_id = p_actor_id
      AND m.status = 'active'
      AND m.is_facilitator IS TRUE
      AND m.is_donations_reviewer IS TRUE
  ) THEN
    RAISE EXCEPTION 'An active donations reviewer is required.';
  END IF;

  IF NULLIF(btrim(p_reason), '') IS NULL THEN
    RAISE EXCEPTION 'A reason is required to end a contributor/member link.';
  END IF;

  UPDATE public.contributor_member_links cml
  SET
    status = 'ended',
    ended_at = now(),
    ended_by = p_actor_id,
    end_reason = btrim(p_reason)
  WHERE cml.contributor_id = p_contributor_id
    AND cml.status = 'active'
  RETURNING * INTO v_link;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Contributor % has no active member link.', p_contributor_id;
  END IF;

  INSERT INTO public.audit_log (actor, action, entity_type, entity_id, details)
  SELECT
    actor.email,
    'contributor.member_unlinked',
    'contributor',
    p_contributor_id::text,
    jsonb_build_object(
      'member_id', v_link.member_id,
      'actor_id', p_actor_id,
      'reason', btrim(p_reason)
    )
  FROM public.members actor
  WHERE actor.member_id = p_actor_id;

  RETURN v_link;
END;
$$;


--
-- Name: FUNCTION unlink_contributor_from_member(p_contributor_id uuid, p_actor_id uuid, p_reason text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.unlink_contributor_from_member(p_contributor_id uuid, p_actor_id uuid, p_reason text) IS 'Ends an active contributor/member link without deleting either identity or rewriting donation history.';


--
-- Name: contributor_addresses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contributor_addresses (
    contributor_address_id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    contributor_id uuid NOT NULL,
    address_type text DEFAULT 'mailing'::text NOT NULL,
    address_1 text,
    address_2 text,
    city text,
    state text,
    postal_code text,
    country text DEFAULT 'USA'::text,
    address_identity_key text GENERATED ALWAYS AS (public.member_address_identity_key(address_1, address_2, postal_code, country)) STORED,
    is_primary boolean DEFAULT false NOT NULL,
    status text DEFAULT 'active'::text NOT NULL,
    source text,
    notes text,
    archived_at timestamp with time zone,
    archived_by uuid,
    archive_reason text,
    CONSTRAINT contributor_addresses_status_check CHECK ((status = ANY (ARRAY['active'::text, 'archived'::text])))
);


--
-- Name: upsert_contributor_address(uuid, text, text, text, text, text, text, text, boolean, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.upsert_contributor_address(p_contributor_id uuid, p_address_1 text, p_address_type text DEFAULT 'mailing'::text, p_address_2 text DEFAULT NULL::text, p_city text DEFAULT NULL::text, p_state text DEFAULT NULL::text, p_postal_code text DEFAULT NULL::text, p_country text DEFAULT 'USA'::text, p_is_primary boolean DEFAULT false, p_source text DEFAULT NULL::text, p_notes text DEFAULT NULL::text) RETURNS public.contributor_addresses
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_result public.contributor_addresses%ROWTYPE;
  v_identity_key text;
BEGIN
  IF p_contributor_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.contributors c
    WHERE c.contributor_id = p_contributor_id
  ) THEN
    RAISE EXCEPTION 'A valid contributor is required.';
  END IF;

  IF NULLIF(btrim(p_address_1), '') IS NULL THEN
    RAISE EXCEPTION 'Address line 1 is required.';
  END IF;

  v_identity_key := public.member_address_identity_key(
    p_address_1,
    p_address_2,
    p_postal_code,
    p_country
  );

  IF v_identity_key IS NOT NULL THEN
    SELECT *
    INTO v_result
    FROM public.contributor_addresses ca
    WHERE ca.contributor_id = p_contributor_id
      AND ca.address_identity_key = v_identity_key
      AND ca.status = 'active'
    FOR UPDATE;
  END IF;

  IF FOUND THEN
    UPDATE public.contributor_addresses ca
    SET
      address_type = COALESCE(NULLIF(btrim(p_address_type), ''), ca.address_type),
      address_1 = COALESCE(NULLIF(btrim(p_address_1), ''), ca.address_1),
      address_2 = COALESCE(NULLIF(btrim(p_address_2), ''), ca.address_2),
      city = COALESCE(NULLIF(btrim(p_city), ''), ca.city),
      state = COALESCE(NULLIF(btrim(p_state), ''), ca.state),
      postal_code = COALESCE(NULLIF(btrim(p_postal_code), ''), ca.postal_code),
      country = COALESCE(NULLIF(btrim(p_country), ''), ca.country, 'USA'),
      is_primary = ca.is_primary OR COALESCE(p_is_primary, false),
      source = COALESCE(NULLIF(btrim(p_source), ''), ca.source),
      notes = COALESCE(ca.notes, NULLIF(btrim(p_notes), ''))
    WHERE ca.contributor_address_id = v_result.contributor_address_id
    RETURNING * INTO v_result;

    RETURN v_result;
  END IF;

  INSERT INTO public.contributor_addresses (
    contributor_id,
    address_type,
    address_1,
    address_2,
    city,
    state,
    postal_code,
    country,
    is_primary,
    source,
    notes
  )
  VALUES (
    p_contributor_id,
    COALESCE(NULLIF(btrim(p_address_type), ''), 'mailing'),
    NULLIF(btrim(p_address_1), ''),
    NULLIF(btrim(p_address_2), ''),
    NULLIF(btrim(p_city), ''),
    NULLIF(btrim(p_state), ''),
    NULLIF(btrim(p_postal_code), ''),
    COALESCE(NULLIF(btrim(p_country), ''), 'USA'),
    COALESCE(p_is_primary, false),
    NULLIF(btrim(p_source), ''),
    NULLIF(btrim(p_notes), '')
  )
  RETURNING * INTO v_result;

  RETURN v_result;
END;
$$;


--
-- Name: member_addresses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.member_addresses (
    member_address_id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    member_id uuid NOT NULL,
    address_type text DEFAULT 'home'::text NOT NULL,
    address_1 text,
    address_2 text,
    city text,
    state text,
    postal_code text,
    country text DEFAULT 'USA'::text,
    is_primary boolean DEFAULT false NOT NULL,
    source text,
    notes text,
    status text DEFAULT 'active'::text NOT NULL,
    archived_at timestamp with time zone,
    archived_by uuid,
    archive_reason text,
    address_fingerprint text GENERATED ALWAYS AS (public.member_address_fingerprint(address_1, address_2, city, state, postal_code, country)) STORED,
    address_identity_key text GENERATED ALWAYS AS (public.member_address_identity_key(address_1, address_2, postal_code, country)) STORED
);


--
-- Name: upsert_member_address(uuid, text, text, text, text, text, text, text, boolean, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.upsert_member_address(p_member_id uuid, p_address_1 text, p_address_type text DEFAULT 'home'::text, p_address_2 text DEFAULT NULL::text, p_city text DEFAULT NULL::text, p_state text DEFAULT NULL::text, p_postal_code text DEFAULT NULL::text, p_country text DEFAULT 'USA'::text, p_is_primary boolean DEFAULT false, p_source text DEFAULT NULL::text, p_notes text DEFAULT NULL::text) RETURNS public.member_addresses
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_address_1 text := NULLIF(btrim(p_address_1), '');
  v_address_2 text := NULLIF(btrim(p_address_2), '');
  v_city text := NULLIF(btrim(p_city), '');
  v_state text := NULLIF(btrim(p_state), '');
  v_postal_code text := NULLIF(btrim(p_postal_code), '');
  v_country text := COALESCE(NULLIF(btrim(p_country), ''), 'USA');
  v_address_type text := COALESCE(NULLIF(btrim(p_address_type), ''), 'home');
  v_identity_key text;
  v_result public.member_addresses%ROWTYPE;
BEGIN
  IF p_member_id IS NULL THEN
    RAISE EXCEPTION 'member_id is required to save an address.';
  END IF;

  IF v_address_1 IS NULL THEN
    RAISE EXCEPTION 'address_1 is required to save an address.';
  END IF;

  v_identity_key := public.member_address_identity_key(
    v_address_1,
    v_address_2,
    v_postal_code,
    v_country
  );

  IF v_identity_key IS NOT NULL THEN
    INSERT INTO public.member_addresses AS ma (
      member_id,
      address_type,
      address_1,
      address_2,
      city,
      state,
      postal_code,
      country,
      is_primary,
      source,
      notes
    )
    VALUES (
      p_member_id,
      v_address_type,
      v_address_1,
      v_address_2,
      v_city,
      v_state,
      v_postal_code,
      v_country,
      COALESCE(p_is_primary, false),
      NULLIF(btrim(p_source), ''),
      NULLIF(btrim(p_notes), '')
    )
    ON CONFLICT (member_id, address_identity_key)
    WHERE address_identity_key IS NOT NULL
      AND address_identity_key <> ''
      AND status = 'active'
    DO UPDATE SET
      address_1 = CASE
        WHEN COALESCE(ma.source, '') LIKE 'givebutter%'
          AND length(COALESCE(public.member_contact_normalize_text(EXCLUDED.address_1), ''))
              > length(COALESCE(public.member_contact_normalize_text(ma.address_1), ''))
          THEN EXCLUDED.address_1
        ELSE ma.address_1
      END,
      address_2 = CASE
        WHEN COALESCE(ma.source, '') LIKE 'givebutter%'
          AND length(COALESCE(public.member_contact_normalize_text(EXCLUDED.address_2), ''))
              > length(COALESCE(public.member_contact_normalize_text(ma.address_2), ''))
          THEN EXCLUDED.address_2
        ELSE ma.address_2
      END,
      city = CASE
        WHEN ma.city IS NULL THEN EXCLUDED.city
        WHEN COALESCE(ma.source, '') LIKE 'givebutter%'
          AND length(COALESCE(public.member_contact_normalize_text(EXCLUDED.city), ''))
              > length(COALESCE(public.member_contact_normalize_text(ma.city), ''))
          THEN EXCLUDED.city
        ELSE ma.city
      END,
      state = COALESCE(ma.state, EXCLUDED.state),
      postal_code = COALESCE(ma.postal_code, EXCLUDED.postal_code),
      country = COALESCE(ma.country, EXCLUDED.country),
      is_primary = ma.is_primary OR EXCLUDED.is_primary,
      notes = COALESCE(ma.notes, EXCLUDED.notes),
      updated_at = now()
    RETURNING ma.* INTO v_result;
  ELSE
    -- If the postal code is unavailable, retain the stricter v1.0.4 behavior
    -- instead of merging addresses on weak identity evidence.
    INSERT INTO public.member_addresses AS ma (
      member_id,
      address_type,
      address_1,
      address_2,
      city,
      state,
      postal_code,
      country,
      is_primary,
      source,
      notes
    )
    VALUES (
      p_member_id,
      v_address_type,
      v_address_1,
      v_address_2,
      v_city,
      v_state,
      v_postal_code,
      v_country,
      COALESCE(p_is_primary, false),
      NULLIF(btrim(p_source), ''),
      NULLIF(btrim(p_notes), '')
    )
    ON CONFLICT (member_id, address_type, address_fingerprint)
    WHERE address_fingerprint IS NOT NULL
      AND address_fingerprint <> ''
      AND status = 'active'
    DO UPDATE SET
      is_primary = ma.is_primary OR EXCLUDED.is_primary,
      notes = COALESCE(ma.notes, EXCLUDED.notes),
      updated_at = now()
    RETURNING ma.* INTO v_result;
  END IF;

  RETURN v_result;
END;
$$;


--
-- Name: FUNCTION upsert_member_address(p_member_id uuid, p_address_1 text, p_address_type text, p_address_2 text, p_city text, p_state text, p_postal_code text, p_country text, p_is_primary boolean, p_source text, p_notes text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.upsert_member_address(p_member_id uuid, p_address_1 text, p_address_type text, p_address_2 text, p_city text, p_state text, p_postal_code text, p_country text, p_is_primary boolean, p_source text, p_notes text) IS 'Creates or updates one active physical address per member identity key, preserving manual address text while allowing provider-managed rows to gain more complete address components.';


--
-- Name: validate_agreement_template_required_for(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.validate_agreement_template_required_for() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  missing text[];
BEGIN
  IF NEW.required_for IS NULL OR array_length(NEW.required_for, 1) IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT array_agg(x)
  INTO missing
  FROM unnest(NEW.required_for) AS x
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.agreement_types t
    WHERE t.type_key = x
      AND t.active = true
  );

  IF missing IS NOT NULL THEN
    RAISE EXCEPTION
      USING MESSAGE = format('agreement_templates.required_for contains unknown/inactive type(s): %s', array_to_string(missing, ', ')),
            ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: validate_contributor_member_link(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.validate_contributor_member_link() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.contributors c
    WHERE c.contributor_id = NEW.contributor_id
      AND c.contributor_type = 'individual'
      AND c.status = 'active'
  ) THEN
    RAISE EXCEPTION 'Only an active individual contributor can be linked to a member.';
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: agreement_templates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.agreement_templates (
    agreement_template_id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    name text NOT NULL,
    version text NOT NULL,
    required_for text[] NOT NULL,
    doc_url text,
    active boolean DEFAULT true NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    documenso_template_envelope_id text,
    documenso_member_recipient_id integer,
    documenso_facilitator_recipient_id integer,
    documenso_template_id integer,
    CONSTRAINT agreement_templates_documenso_facilitator_recipient_id_positive CHECK (((documenso_facilitator_recipient_id IS NULL) OR (documenso_facilitator_recipient_id > 0))),
    CONSTRAINT agreement_templates_documenso_member_recipient_id_positive CHECK (((documenso_member_recipient_id IS NULL) OR (documenso_member_recipient_id > 0))),
    CONSTRAINT agreement_templates_documenso_template_id_positive CHECK (((documenso_template_id IS NULL) OR (documenso_template_id > 0)))
);


--
-- Name: agreement_types; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.agreement_types (
    type_key text NOT NULL,
    display_name text NOT NULL,
    description text,
    sort_order integer DEFAULT 100 NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: audit_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit_log (
    audit_log_id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    actor text,
    action text NOT NULL,
    entity_type text NOT NULL,
    entity_id text NOT NULL,
    details jsonb,
    CONSTRAINT audit_log_actor_lowercase CHECK ((actor = lower(actor)))
);


--
-- Name: contributor_emails; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contributor_emails (
    contributor_email_id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    contributor_id uuid NOT NULL,
    email text NOT NULL,
    email_normalized text GENERATED ALWAYS AS (lower(btrim(email))) STORED,
    is_primary boolean DEFAULT false NOT NULL,
    is_verified boolean DEFAULT false NOT NULL,
    status text DEFAULT 'active'::text NOT NULL,
    source text,
    notes text,
    archived_at timestamp with time zone,
    archived_by uuid,
    archive_reason text,
    CONSTRAINT contributor_emails_status_check CHECK ((status = ANY (ARRAY['active'::text, 'archived'::text])))
);


--
-- Name: contributor_external_identities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contributor_external_identities (
    contributor_external_identity_id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    contributor_id uuid NOT NULL,
    provider text NOT NULL,
    provider_identity text NOT NULL,
    status text DEFAULT 'active'::text NOT NULL,
    source text,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    CONSTRAINT contributor_external_identities_status_check CHECK ((status = ANY (ARRAY['active'::text, 'archived'::text])))
);


--
-- Name: contributor_phones; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contributor_phones (
    contributor_phone_id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    contributor_id uuid NOT NULL,
    phone text NOT NULL,
    phone_normalized text GENERATED ALWAYS AS (public.normalize_us_phone(phone)) STORED,
    is_primary boolean DEFAULT false NOT NULL,
    is_verified boolean DEFAULT false NOT NULL,
    status text DEFAULT 'active'::text NOT NULL,
    source text,
    notes text,
    archived_at timestamp with time zone,
    archived_by uuid,
    archive_reason text,
    CONSTRAINT contributor_phones_status_check CHECK ((status = ANY (ARRAY['active'::text, 'archived'::text])))
);


--
-- Name: organizations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.organizations (
    organization_id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    organization_name text NOT NULL,
    CONSTRAINT organizations_name_check CHECK ((NULLIF(btrim(organization_name), ''::text) IS NOT NULL))
);


--
-- Name: TABLE organizations; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.organizations IS 'Shared organization identity; organizations cannot be members or ceremony participants.';


--
-- Name: people; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.people (
    person_id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    created_at timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    display_name text NOT NULL,
    first_name text,
    last_name text,
    date_of_birth date,
    CONSTRAINT people_name_check CHECK ((NULLIF(btrim(display_name), ''::text) IS NOT NULL))
);


--
-- Name: TABLE people; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.people IS 'Shared person identity. Membership, donations, participation, and future appointments refer to this person without creating another human identity.';


--
-- Name: contributor_profiles; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.contributor_profiles AS
 SELECT c.contributor_id,
    c.created_at,
    c.updated_at,
    c.contributor_type,
    c.status,
    c.source,
    c.notes,
    c.merged_into_contributor_id,
    c.archived_at,
    c.archived_by,
    c.archive_reason,
    c.person_id,
    c.organization_id,
        CASE
            WHEN (c.contributor_type = 'individual'::text) THEN COALESCE(NULLIF(btrim(concat_ws(' '::text, p.first_name, p.last_name)), ''::text), p.display_name)
            ELSE o.organization_name
        END AS display_name,
    p.first_name,
    p.last_name,
    o.organization_name
   FROM ((public.contributors c
     LEFT JOIN public.people p ON ((p.person_id = c.person_id)))
     LEFT JOIN public.organizations o ON ((o.organization_id = c.organization_id)));


--
-- Name: VIEW contributor_profiles; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.contributor_profiles IS 'Donation-party fields with person or organization details, without copies.';


--
-- Name: events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.events (
    event_id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    type text NOT NULL,
    name text,
    starts_at timestamp with time zone,
    ends_at timestamp with time zone,
    location text,
    notes text
);


--
-- Name: facilitator_storage_location_access; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.facilitator_storage_location_access (
    facilitator_storage_location_access_id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    facilitator_id uuid NOT NULL,
    storage_location_name text NOT NULL,
    status text DEFAULT 'active'::text NOT NULL,
    assigned_by_member_id uuid,
    notes text
);


--
-- Name: listmonk_sync_queue; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.listmonk_sync_queue (
    listmonk_sync_queue_id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    available_at timestamp with time zone DEFAULT now() NOT NULL,
    locked_at timestamp with time zone,
    processed_at timestamp with time zone,
    member_email_id uuid NOT NULL,
    email_normalized text NOT NULL,
    listmonk_list_id integer,
    event_type text NOT NULL,
    source text NOT NULL,
    actor text,
    status text DEFAULT 'pending'::text NOT NULL,
    attempts integer DEFAULT 0 NOT NULL,
    last_error text,
    request_payload jsonb,
    response_payload jsonb,
    details jsonb DEFAULT '{}'::jsonb NOT NULL,
    CONSTRAINT listmonk_sync_queue_event_type_chk CHECK ((event_type = ANY (ARRAY['subscribe'::text, 'unsubscribe'::text]))),
    CONSTRAINT listmonk_sync_queue_status_chk CHECK ((status = ANY (ARRAY['pending'::text, 'processing'::text, 'succeeded'::text, 'failed'::text, 'skipped'::text])))
);


--
-- Name: member_agreements; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.member_agreements (
    member_agreement_id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    agreement_template_id uuid,
    signed_at timestamp with time zone,
    signature_method text NOT NULL,
    evidence_url text,
    verified_by text,
    verified_at timestamp with time zone,
    status text DEFAULT 'pending'::text NOT NULL,
    facilitator_id uuid,
    member_signed_at timestamp with time zone,
    facilitator_signed_at timestamp with time zone,
    opensign_document_id text,
    evidence text,
    member_id uuid NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    documenso_document_id text,
    documenso_external_id text,
    documenso_completed_pdf_uploaded_at timestamp with time zone,
    reviewer_id uuid,
    reviewed_at timestamp with time zone,
    review_notes text,
    member_email_id uuid,
    canceled_at timestamp with time zone,
    canceled_by uuid,
    cancel_reason text,
    documenso_cancel_response jsonb,
    expired_at timestamp with time zone,
    practitioner_person_id uuid
);


--
-- Name: COLUMN member_agreements.canceled_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.member_agreements.canceled_at IS 'Timestamp when a pending Documenso agreement was canceled before signing.';


--
-- Name: COLUMN member_agreements.canceled_by; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.member_agreements.canceled_by IS 'Member/facilitator who initiated cancellation of a pending Documenso agreement.';


--
-- Name: COLUMN member_agreements.cancel_reason; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.member_agreements.cancel_reason IS 'Review/Cancel Notes supplied when canceling a pending Documenso agreement.';


--
-- Name: COLUMN member_agreements.documenso_cancel_response; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.member_agreements.documenso_cancel_response IS 'Raw/minimal response payload returned by the Documenso cancel/delete envelope API.';


--
-- Name: COLUMN member_agreements.expired_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.member_agreements.expired_at IS 'Timestamp when Documenso reported that the agreement expired before signing.';


--
-- Name: COLUMN member_agreements.practitioner_person_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.member_agreements.practitioner_person_id IS 'Canonical practitioner signer identity; facilitator_id is a nullable compatibility projection.';


--
-- Name: member_facilitators; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.member_facilitators (
    member_facilitator_id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    member_id uuid NOT NULL,
    facilitator_id uuid NOT NULL,
    assigned_by_member_id uuid,
    status text DEFAULT 'active'::text NOT NULL,
    notes text
);


--
-- Name: member_phones; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.member_phones (
    member_phone_id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    member_id uuid NOT NULL,
    phone text NOT NULL,
    is_primary boolean DEFAULT false NOT NULL,
    is_verified boolean DEFAULT false NOT NULL,
    source text,
    notes text,
    status text DEFAULT 'active'::text NOT NULL,
    archived_at timestamp with time zone,
    archived_by uuid,
    archive_reason text,
    phone_normalized text GENERATED ALWAYS AS (public.normalize_us_phone(phone)) STORED
);


--
-- Name: member_practitioner_assignments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.member_practitioner_assignments (
    member_practitioner_assignment_id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    member_id uuid NOT NULL,
    practitioner_person_id uuid NOT NULL,
    assigned_by_person_id uuid,
    status text DEFAULT 'active'::text NOT NULL,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    ended_at timestamp with time zone,
    ended_by_person_id uuid,
    end_reason text,
    CONSTRAINT member_practitioner_assignments_end_check CHECK ((((status = 'active'::text) AND (ended_at IS NULL)) OR ((status = 'inactive'::text) AND (ended_at IS NOT NULL)))),
    CONSTRAINT member_practitioner_assignments_status_check CHECK ((status = ANY (ARRAY['active'::text, 'inactive'::text])))
);


--
-- Name: TABLE member_practitioner_assignments; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.member_practitioner_assignments IS 'Canonical person-based practitioner assignment to a membership; practitioner membership is not required.';


--
-- Name: member_profiles; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.member_profiles AS
 SELECT m.member_id,
    m.created_at,
    m.updated_at,
    m.status,
    m.email,
    m.phone,
    m.notes,
    m.is_facilitator,
    m.is_document_reviewer,
    m.created_by_facilitator_id,
    m.is_donations_reviewer,
    m.person_id,
    COALESCE(NULLIF(btrim(concat_ws(' '::text, p.first_name, p.last_name)), ''::text), p.display_name) AS display_name,
    p.first_name,
    p.last_name,
    p.date_of_birth
   FROM (public.members m
     JOIN public.people p ON ((p.person_id = m.person_id)));


--
-- Name: VIEW member_profiles; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.member_profiles IS 'Membership fields with current person details, assembled without copies.';


--
-- Name: organization_terminology; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.organization_terminology (
    concept_key text NOT NULL,
    singular_label text NOT NULL,
    plural_label text NOT NULL,
    short_label text,
    is_active boolean DEFAULT true NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by text NOT NULL,
    CONSTRAINT organization_terminology_plural_label_check CHECK ((NULLIF(btrim(plural_label), ''::text) IS NOT NULL)),
    CONSTRAINT organization_terminology_plural_label_check1 CHECK ((char_length(plural_label) <= 80)),
    CONSTRAINT organization_terminology_short_label_check CHECK (((short_label IS NULL) OR (NULLIF(btrim(short_label), ''::text) IS NOT NULL))),
    CONSTRAINT organization_terminology_short_label_check1 CHECK (((short_label IS NULL) OR (char_length(short_label) <= 40))),
    CONSTRAINT organization_terminology_singular_label_check CHECK ((NULLIF(btrim(singular_label), ''::text) IS NOT NULL)),
    CONSTRAINT organization_terminology_singular_label_check1 CHECK ((char_length(singular_label) <= 80))
);


--
-- Name: TABLE organization_terminology; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.organization_terminology IS 'Configurable presentation labels for this single-organization SignatureGate deployment.';


--
-- Name: party_contact_sources; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.party_contact_sources (
    source_table text NOT NULL,
    source_id uuid NOT NULL,
    party_contact_id uuid NOT NULL,
    source text,
    status text NOT NULL,
    is_primary boolean DEFAULT false NOT NULL,
    is_verified boolean DEFAULT false NOT NULL,
    address_type text,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT party_contact_sources_source_table_check CHECK ((source_table = ANY (ARRAY['member_emails'::text, 'member_phones'::text, 'member_addresses'::text, 'contributor_emails'::text, 'contributor_phones'::text, 'contributor_addresses'::text]))),
    CONSTRAINT party_contact_sources_status_check CHECK ((status = ANY (ARRAY['active'::text, 'archived'::text])))
);


--
-- Name: TABLE party_contact_sources; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.party_contact_sources IS 'Domain preferences and original IDs. Preserve until agreement, Listmonk, Appsmith and n8n readers move.';


--
-- Name: party_contacts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.party_contacts (
    party_contact_id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    person_id uuid,
    organization_id uuid,
    contact_kind text NOT NULL,
    contact_value text,
    address_1 text,
    address_2 text,
    city text,
    state text,
    postal_code text,
    country text,
    identity_key text GENERATED ALWAYS AS (
CASE contact_kind
    WHEN 'email'::text THEN NULLIF(lower(btrim(contact_value)), ''::text)
    WHEN 'phone'::text THEN NULLIF(public.normalize_us_phone(contact_value), ''::text)
    WHEN 'address'::text THEN NULLIF(public.member_address_identity_key(address_1, address_2, postal_code, country), ''::text)
    ELSE NULL::text
END) STORED,
    is_verified boolean DEFAULT false NOT NULL,
    status text DEFAULT 'active'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT party_contacts_contact_kind_check CHECK ((contact_kind = ANY (ARRAY['email'::text, 'phone'::text, 'address'::text]))),
    CONSTRAINT party_contacts_one_owner CHECK (((person_id IS NOT NULL) <> (organization_id IS NOT NULL))),
    CONSTRAINT party_contacts_status_check CHECK ((status = ANY (ARRAY['active'::text, 'archived'::text]))),
    CONSTRAINT party_contacts_value CHECK ((((contact_kind = ANY (ARRAY['email'::text, 'phone'::text])) AND (NULLIF(btrim(contact_value), ''::text) IS NOT NULL) AND (address_1 IS NULL)) OR ((contact_kind = 'address'::text) AND (contact_value IS NULL) AND (NULLIF(btrim(address_1), ''::text) IS NOT NULL))))
);


--
-- Name: TABLE party_contacts; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.party_contacts IS 'Party-owned contacts. Shared values never imply shared identity.';


--
-- Name: person_app_accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.person_app_accounts (
    person_id uuid NOT NULL,
    email text NOT NULL,
    email_normalized text GENERATED ALWAYS AS (lower(btrim(email))) STORED,
    status text DEFAULT 'active'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT person_app_accounts_email_check CHECK ((NULLIF(btrim(email), ''::text) IS NOT NULL)),
    CONSTRAINT person_app_accounts_status_check CHECK ((status = ANY (ARRAY['active'::text, 'disabled'::text])))
);


--
-- Name: TABLE person_app_accounts; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.person_app_accounts IS 'Explicit ownership of an Appsmith sign-in email by one person; no matching by shared contact address.';


--
-- Name: person_identity_review; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.person_identity_review (
    person_identity_review_id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    person_id uuid NOT NULL,
    member_id uuid NOT NULL,
    contributor_id uuid NOT NULL,
    member_name text,
    contributor_name text,
    member_names jsonb NOT NULL,
    contributor_names jsonb NOT NULL,
    resolved_at timestamp with time zone,
    resolution_notes text
);


--
-- Name: TABLE person_identity_review; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.person_identity_review IS 'Pre-existing name differences requiring review; source values are retained.';


--
-- Name: person_roles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.person_roles (
    person_id uuid NOT NULL,
    role_key text NOT NULL,
    assigned_at timestamp with time zone DEFAULT now() NOT NULL,
    assigned_by text NOT NULL,
    CONSTRAINT person_roles_role_key_check CHECK ((role_key = ANY (ARRAY['practitioner'::text, 'document_reviewer'::text, 'donations_reviewer'::text, 'directory_manager'::text, 'minister'::text])))
);


--
-- Name: TABLE person_roles; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.person_roles IS 'Person appointments and Appsmith permissions; legacy members reviewer/facilitator flags remain transitional.';


--
-- Name: practitioner_storage_location_access; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.practitioner_storage_location_access (
    practitioner_storage_location_access_id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    practitioner_person_id uuid NOT NULL,
    storage_location_name text NOT NULL,
    status text DEFAULT 'active'::text NOT NULL,
    assigned_by_person_id uuid,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT practitioner_storage_location_acces_storage_location_name_check CHECK ((NULLIF(btrim(storage_location_name), ''::text) IS NOT NULL)),
    CONSTRAINT practitioner_storage_location_access_status_check CHECK ((status = ANY (ARRAY['active'::text, 'inactive'::text])))
);


--
-- Name: TABLE practitioner_storage_location_access; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.practitioner_storage_location_access IS 'Canonical person-based storage access for a practitioner appointment; membership is not required.';


--
-- Name: releases; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.releases (
    release_id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    released_at timestamp with time zone DEFAULT now() NOT NULL,
    member_id uuid NOT NULL,
    event_id uuid,
    mushroomprocess_product_id text NOT NULL,
    item_name text,
    quantity numeric(12,3) DEFAULT 0 NOT NULL,
    unit text DEFAULT 'g'::text NOT NULL,
    released_by text,
    notes text,
    release_type text DEFAULT 'sacrament_release'::text NOT NULL,
    member_agreement_id uuid,
    facilitator_id uuid,
    net_weight_g integer,
    strain text,
    status text DEFAULT 'issued'::text NOT NULL,
    voided_at timestamp with time zone,
    voided_by uuid,
    void_reason text,
    storage_location_name text,
    practitioner_person_id uuid,
    CONSTRAINT releases_sacrament_release_type_check CHECK ((release_type = 'sacrament_release'::text))
);


--
-- Name: COLUMN releases.release_type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.releases.release_type IS 'Compatibility discriminator. A release is a tangible sacrament transfer; new rows must use sacrament_release.';


--
-- Name: COLUMN releases.practitioner_person_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.releases.practitioner_person_id IS 'Canonical practitioner responsible for the tangible transfer; facilitator_id is a compatibility projection.';


--
-- Name: CONSTRAINT releases_sacrament_release_type_check ON releases; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON CONSTRAINT releases_sacrament_release_type_check ON public.releases IS 'Prevents membership, event participation, and other non-tangible activities from being recorded as releases.';


--
-- Name: terminology_concepts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.terminology_concepts (
    concept_key text NOT NULL,
    concept_kind text NOT NULL,
    description text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT terminology_concepts_concept_key_check CHECK ((concept_key ~ '^[a-z][a-z0-9_]*$'::text)),
    CONSTRAINT terminology_concepts_concept_kind_check CHECK ((concept_kind = ANY (ARRAY['entity'::text, 'appointment'::text, 'permission'::text, 'workflow'::text]))),
    CONSTRAINT terminology_concepts_description_check CHECK ((NULLIF(btrim(description), ''::text) IS NOT NULL))
);


--
-- Name: TABLE terminology_concepts; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.terminology_concepts IS 'Stable application concept registry. Keys are contracts and are changed only by migrations.';


--
-- Name: v_party_contacts; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_party_contacts AS
 SELECT party_contact_id,
    person_id,
    organization_id,
    contact_kind,
    contact_value,
    address_1,
    address_2,
    city,
    state,
    postal_code,
    country,
    identity_key,
    is_verified,
    status,
    created_at,
    updated_at,
    ( SELECT count(*) AS count
           FROM public.party_contact_sources s
          WHERE (s.party_contact_id = c.party_contact_id)) AS source_count
   FROM public.party_contacts c;


--
-- Name: v_person_addresses; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_person_addresses AS
 SELECT DISTINCT ON (person_id, identity_key) person_id,
    address_1,
    address_2,
    city,
    state,
    postal_code,
    country,
    address_type,
    is_primary,
    contact_source,
    contact_id
   FROM ( SELECT m.person_id,
            ma.address_1,
            ma.address_2,
            ma.city,
            ma.state,
            ma.postal_code,
            ma.country,
            ma.address_type,
            ma.is_primary,
            'member'::text AS contact_source,
            ma.member_address_id AS contact_id,
            COALESCE(NULLIF(ma.address_identity_key, ''::text), (ma.member_address_id)::text) AS identity_key,
            0 AS preference,
            ma.updated_at
           FROM (public.member_addresses ma
             JOIN public.members m ON ((m.member_id = ma.member_id)))
          WHERE (ma.status = 'active'::text)
        UNION ALL
         SELECT c.person_id,
            ca.address_1,
            ca.address_2,
            ca.city,
            ca.state,
            ca.postal_code,
            ca.country,
            ca.address_type,
            ca.is_primary,
            'contributor'::text AS text,
            ca.contributor_address_id,
            COALESCE(NULLIF(ca.address_identity_key, ''::text), (ca.contributor_address_id)::text) AS "coalesce",
            1,
            ca.updated_at
           FROM (public.contributor_addresses ca
             JOIN public.contributors c ON ((c.contributor_id = ca.contributor_id)))
          WHERE ((ca.status = 'active'::text) AND (c.person_id IS NOT NULL))) contacts
  ORDER BY person_id, identity_key, preference, updated_at DESC;


--
-- Name: v_person_emails; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_person_emails AS
 SELECT DISTINCT ON (person_id, email_normalized) person_id,
    email,
    email_normalized,
    is_primary,
    is_verified,
    contact_source,
    contact_id
   FROM ( SELECT m.person_id,
            me.email,
            me.email_normalized,
            me.is_primary,
            me.is_verified,
            'member'::text AS contact_source,
            me.member_email_id AS contact_id,
            0 AS preference,
            me.updated_at
           FROM (public.member_emails me
             JOIN public.members m ON ((m.member_id = me.member_id)))
          WHERE ((me.status = 'active'::text) AND (NULLIF(me.email_normalized, ''::text) IS NOT NULL))
        UNION ALL
         SELECT c.person_id,
            ce.email,
            ce.email_normalized,
            ce.is_primary,
            ce.is_verified,
            'contributor'::text AS text,
            ce.contributor_email_id,
            1,
            ce.updated_at
           FROM (public.contributor_emails ce
             JOIN public.contributors c ON ((c.contributor_id = ce.contributor_id)))
          WHERE ((ce.status = 'active'::text) AND (c.person_id IS NOT NULL) AND (NULLIF(ce.email_normalized, ''::text) IS NOT NULL))) contacts
  ORDER BY person_id, email_normalized, preference, updated_at DESC;


--
-- Name: v_person_phones; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_person_phones AS
 SELECT DISTINCT ON (person_id, phone_normalized) person_id,
    phone,
    phone_normalized,
    is_primary,
    is_verified,
    contact_source,
    contact_id
   FROM ( SELECT m.person_id,
            mp.phone,
            mp.phone_normalized,
            mp.is_primary,
            mp.is_verified,
            'member'::text AS contact_source,
            mp.member_phone_id AS contact_id,
            0 AS preference,
            mp.updated_at
           FROM (public.member_phones mp
             JOIN public.members m ON ((m.member_id = mp.member_id)))
          WHERE ((mp.status = 'active'::text) AND (NULLIF(mp.phone_normalized, ''::text) IS NOT NULL))
        UNION ALL
         SELECT c.person_id,
            cp.phone,
            cp.phone_normalized,
            cp.is_primary,
            cp.is_verified,
            'contributor'::text AS text,
            cp.contributor_phone_id,
            1,
            cp.updated_at
           FROM (public.contributor_phones cp
             JOIN public.contributors c ON ((c.contributor_id = cp.contributor_id)))
          WHERE ((cp.status = 'active'::text) AND (c.person_id IS NOT NULL) AND (NULLIF(cp.phone_normalized, ''::text) IS NOT NULL))) contacts
  ORDER BY person_id, phone_normalized, preference, updated_at DESC;


--
-- Name: agreement_templates agreement_templates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agreement_templates
    ADD CONSTRAINT agreement_templates_pkey PRIMARY KEY (agreement_template_id);


--
-- Name: agreement_types agreement_types_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agreement_types
    ADD CONSTRAINT agreement_types_pkey PRIMARY KEY (type_key);


--
-- Name: audit_log audit_log_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_log
    ADD CONSTRAINT audit_log_pkey PRIMARY KEY (audit_log_id);


--
-- Name: cash_deposit_batch_items cash_deposit_batch_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cash_deposit_batch_items
    ADD CONSTRAINT cash_deposit_batch_items_pkey PRIMARY KEY (deposit_batch_item_id);


--
-- Name: cash_deposit_batches cash_deposit_batches_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cash_deposit_batches
    ADD CONSTRAINT cash_deposit_batches_pkey PRIMARY KEY (deposit_batch_id);


--
-- Name: contributor_addresses contributor_addresses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contributor_addresses
    ADD CONSTRAINT contributor_addresses_pkey PRIMARY KEY (contributor_address_id);


--
-- Name: contributor_emails contributor_emails_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contributor_emails
    ADD CONSTRAINT contributor_emails_pkey PRIMARY KEY (contributor_email_id);


--
-- Name: contributor_external_identities contributor_external_identities_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contributor_external_identities
    ADD CONSTRAINT contributor_external_identities_pkey PRIMARY KEY (contributor_external_identity_id);


--
-- Name: contributor_member_links contributor_member_links_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contributor_member_links
    ADD CONSTRAINT contributor_member_links_pkey PRIMARY KEY (contributor_member_link_id);


--
-- Name: contributor_phones contributor_phones_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contributor_phones
    ADD CONSTRAINT contributor_phones_pkey PRIMARY KEY (contributor_phone_id);


--
-- Name: contributors contributors_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contributors
    ADD CONSTRAINT contributors_pkey PRIMARY KEY (contributor_id);


--
-- Name: donations donations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.donations
    ADD CONSTRAINT donations_pkey PRIMARY KEY (donation_id);


--
-- Name: events events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.events
    ADD CONSTRAINT events_pkey PRIMARY KEY (event_id);


--
-- Name: facilitator_storage_location_access facilitator_storage_location_access_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.facilitator_storage_location_access
    ADD CONSTRAINT facilitator_storage_location_access_pkey PRIMARY KEY (facilitator_storage_location_access_id);


--
-- Name: facilitator_storage_location_access facilitator_storage_location_access_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.facilitator_storage_location_access
    ADD CONSTRAINT facilitator_storage_location_access_unique UNIQUE (facilitator_id, storage_location_name);


--
-- Name: listmonk_sync_queue listmonk_sync_queue_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.listmonk_sync_queue
    ADD CONSTRAINT listmonk_sync_queue_pkey PRIMARY KEY (listmonk_sync_queue_id);


--
-- Name: member_addresses member_addresses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.member_addresses
    ADD CONSTRAINT member_addresses_pkey PRIMARY KEY (member_address_id);


--
-- Name: member_agreements member_agreements_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.member_agreements
    ADD CONSTRAINT member_agreements_pkey PRIMARY KEY (member_agreement_id);


--
-- Name: member_agreements member_agreements_status_chk; Type: CHECK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.member_agreements
    ADD CONSTRAINT member_agreements_status_chk CHECK (((status IS NULL) OR (status = ANY (ARRAY['pending_review'::text, 'pending_email_send'::text, 'pending_signature'::text, 'signed'::text, 'rejected'::text, 'revoked'::text, 'canceled'::text, 'cancelled'::text, 'expired'::text])))) NOT VALID;


--
-- Name: member_emails member_emails_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.member_emails
    ADD CONSTRAINT member_emails_pkey PRIMARY KEY (member_email_id);


--
-- Name: member_facilitators member_facilitators_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.member_facilitators
    ADD CONSTRAINT member_facilitators_pkey PRIMARY KEY (member_facilitator_id);


--
-- Name: member_facilitators member_facilitators_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.member_facilitators
    ADD CONSTRAINT member_facilitators_unique UNIQUE (member_id, facilitator_id);


--
-- Name: member_phones member_phones_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.member_phones
    ADD CONSTRAINT member_phones_pkey PRIMARY KEY (member_phone_id);


--
-- Name: member_practitioner_assignments member_practitioner_assignments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.member_practitioner_assignments
    ADD CONSTRAINT member_practitioner_assignments_pkey PRIMARY KEY (member_practitioner_assignment_id);


--
-- Name: member_practitioner_assignments member_practitioner_assignments_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.member_practitioner_assignments
    ADD CONSTRAINT member_practitioner_assignments_unique UNIQUE (member_id, practitioner_person_id);


--
-- Name: members members_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.members
    ADD CONSTRAINT members_pkey PRIMARY KEY (member_id);


--
-- Name: organization_terminology organization_terminology_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organization_terminology
    ADD CONSTRAINT organization_terminology_pkey PRIMARY KEY (concept_key);


--
-- Name: organizations organizations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organizations
    ADD CONSTRAINT organizations_pkey PRIMARY KEY (organization_id);


--
-- Name: party_contact_sources party_contact_sources_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.party_contact_sources
    ADD CONSTRAINT party_contact_sources_pkey PRIMARY KEY (source_table, source_id);


--
-- Name: party_contacts party_contacts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.party_contacts
    ADD CONSTRAINT party_contacts_pkey PRIMARY KEY (party_contact_id);


--
-- Name: people people_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.people
    ADD CONSTRAINT people_pkey PRIMARY KEY (person_id);


--
-- Name: person_app_accounts person_app_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.person_app_accounts
    ADD CONSTRAINT person_app_accounts_pkey PRIMARY KEY (person_id);


--
-- Name: person_identity_review person_identity_review_member_id_contributor_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.person_identity_review
    ADD CONSTRAINT person_identity_review_member_id_contributor_id_key UNIQUE (member_id, contributor_id);


--
-- Name: person_identity_review person_identity_review_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.person_identity_review
    ADD CONSTRAINT person_identity_review_pkey PRIMARY KEY (person_identity_review_id);


--
-- Name: person_roles person_roles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.person_roles
    ADD CONSTRAINT person_roles_pkey PRIMARY KEY (person_id, role_key);


--
-- Name: practitioner_storage_location_access practitioner_storage_location_access_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.practitioner_storage_location_access
    ADD CONSTRAINT practitioner_storage_location_access_pkey PRIMARY KEY (practitioner_storage_location_access_id);


--
-- Name: practitioner_storage_location_access practitioner_storage_location_access_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.practitioner_storage_location_access
    ADD CONSTRAINT practitioner_storage_location_access_unique UNIQUE (practitioner_person_id, storage_location_name);


--
-- Name: releases releases_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.releases
    ADD CONSTRAINT releases_pkey PRIMARY KEY (release_id);


--
-- Name: terminology_concepts terminology_concepts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.terminology_concepts
    ADD CONSTRAINT terminology_concepts_pkey PRIMARY KEY (concept_key);


--
-- Name: audit_log_actor_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX audit_log_actor_idx ON public.audit_log USING btree (actor);


--
-- Name: audit_log_created_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX audit_log_created_at_idx ON public.audit_log USING btree (created_at DESC);


--
-- Name: audit_log_entity_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX audit_log_entity_idx ON public.audit_log USING btree (entity_type, entity_id);


--
-- Name: idx_agreement_templates_documenso_envelope_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agreement_templates_documenso_envelope_id ON public.agreement_templates USING btree (documenso_template_envelope_id) WHERE ((documenso_template_envelope_id IS NOT NULL) AND (documenso_template_envelope_id <> ''::text));


--
-- Name: idx_agreement_templates_documenso_template_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agreement_templates_documenso_template_id ON public.agreement_templates USING btree (documenso_template_id) WHERE (documenso_template_id IS NOT NULL);


--
-- Name: idx_agreement_templates_required_for_gin; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agreement_templates_required_for_gin ON public.agreement_templates USING gin (required_for);


--
-- Name: idx_cash_deposit_batch_items_batch; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cash_deposit_batch_items_batch ON public.cash_deposit_batch_items USING btree (deposit_batch_id, created_at);


--
-- Name: idx_cash_deposit_batch_items_donation; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cash_deposit_batch_items_donation ON public.cash_deposit_batch_items USING btree (donation_id);


--
-- Name: idx_cash_deposit_batches_preparer; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cash_deposit_batches_preparer ON public.cash_deposit_batches USING btree (preparer_id, created_at DESC);


--
-- Name: idx_cash_deposit_batches_status_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cash_deposit_batches_status_date ON public.cash_deposit_batches USING btree (status, deposit_date DESC NULLS LAST, created_at DESC);


--
-- Name: idx_cash_deposit_batches_verifier; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cash_deposit_batches_verifier ON public.cash_deposit_batches USING btree (verifier_id, confirmed_at DESC);


--
-- Name: idx_contributor_addresses_lookup; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_contributor_addresses_lookup ON public.contributor_addresses USING btree (address_identity_key) WHERE (status = 'active'::text);


--
-- Name: idx_contributor_emails_lookup; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_contributor_emails_lookup ON public.contributor_emails USING btree (email_normalized) WHERE (status = 'active'::text);


--
-- Name: idx_contributor_member_links_member_history; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_contributor_member_links_member_history ON public.contributor_member_links USING btree (member_id, linked_at DESC);


--
-- Name: idx_contributor_phones_lookup; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_contributor_phones_lookup ON public.contributor_phones USING btree (phone_normalized) WHERE (status = 'active'::text);


--
-- Name: idx_donations_contributor_donated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_donations_contributor_donated_at ON public.donations USING btree (contributor_id, donated_at DESC NULLS LAST) WHERE (contributor_id IS NOT NULL);


--
-- Name: idx_donations_donor_kind_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_donations_donor_kind_status ON public.donations USING btree (donor_kind, status, donated_at DESC NULLS LAST);


--
-- Name: idx_donations_member_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_donations_member_date ON public.donations USING btree (member_id, donated_at DESC NULLS LAST, created_at DESC);


--
-- Name: idx_donations_pending_review; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_donations_pending_review ON public.donations USING btree (status, created_at DESC) WHERE (status = 'pending_review'::text);


--
-- Name: idx_donations_report; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_donations_report ON public.donations USING btree (donated_at, created_at, status);


--
-- Name: idx_fsl_access_facilitator_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_fsl_access_facilitator_id ON public.facilitator_storage_location_access USING btree (facilitator_id);


--
-- Name: idx_fsl_access_facilitator_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_fsl_access_facilitator_status ON public.facilitator_storage_location_access USING btree (facilitator_id, status);


--
-- Name: idx_fsl_access_location_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_fsl_access_location_status ON public.facilitator_storage_location_access USING btree (storage_location_name, status);


--
-- Name: idx_fsl_access_storage_location_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_fsl_access_storage_location_name ON public.facilitator_storage_location_access USING btree (storage_location_name);


--
-- Name: idx_listmonk_sync_queue_member_email; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_listmonk_sync_queue_member_email ON public.listmonk_sync_queue USING btree (member_email_id, created_at DESC);


--
-- Name: idx_listmonk_sync_queue_pending; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_listmonk_sync_queue_pending ON public.listmonk_sync_queue USING btree (status, available_at, created_at) WHERE (status = ANY (ARRAY['pending'::text, 'failed'::text]));


--
-- Name: idx_member_addresses_fingerprint_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_member_addresses_fingerprint_active ON public.member_addresses USING btree (address_fingerprint) WHERE ((address_fingerprint IS NOT NULL) AND (address_fingerprint <> ''::text) AND (status = 'active'::text));


--
-- Name: idx_member_addresses_identity_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_member_addresses_identity_active ON public.member_addresses USING btree (address_identity_key) WHERE ((address_identity_key IS NOT NULL) AND (address_identity_key <> ''::text) AND (status = 'active'::text));


--
-- Name: idx_member_addresses_member_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_member_addresses_member_id ON public.member_addresses USING btree (member_id);


--
-- Name: idx_member_addresses_zip; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_member_addresses_zip ON public.member_addresses USING btree (postal_code);


--
-- Name: idx_member_agreements_canceled_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_member_agreements_canceled_at ON public.member_agreements USING btree (canceled_at) WHERE (canceled_at IS NOT NULL);


--
-- Name: idx_member_agreements_documenso_expirable; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_member_agreements_documenso_expirable ON public.member_agreements USING btree (status, documenso_external_id, documenso_document_id) WHERE ((signature_method = 'documenso'::text) AND (status = ANY (ARRAY['pending_email_send'::text, 'pending_signature'::text])));


--
-- Name: idx_member_agreements_documenso_pending_cancel; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_member_agreements_documenso_pending_cancel ON public.member_agreements USING btree (member_agreement_id, documenso_document_id) WHERE ((signature_method = 'documenso'::text) AND (status = 'pending_signature'::text));


--
-- Name: idx_member_agreements_expired_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_member_agreements_expired_at ON public.member_agreements USING btree (expired_at) WHERE (expired_at IS NOT NULL);


--
-- Name: idx_member_agreements_facilitator; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_member_agreements_facilitator ON public.member_agreements USING btree (facilitator_id, created_at DESC);


--
-- Name: idx_member_agreements_member_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_member_agreements_member_status ON public.member_agreements USING btree (member_id, status);


--
-- Name: idx_member_agreements_pending_review; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_member_agreements_pending_review ON public.member_agreements USING btree (status, created_at DESC) WHERE (status = 'pending_review'::text);


--
-- Name: idx_member_agreements_signed_report; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_member_agreements_signed_report ON public.member_agreements USING btree (status, signed_at, reviewed_at, verified_at) WHERE (lower(COALESCE(status, ''::text)) = 'signed'::text);


--
-- Name: idx_member_emails_mailing_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_member_emails_mailing_status ON public.member_emails USING btree (mailing_subscription_status, listmonk_sync_status, updated_at DESC);


--
-- Name: idx_member_emails_member_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_member_emails_member_id ON public.member_emails USING btree (member_id);


--
-- Name: idx_member_facilitators_facilitator_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_member_facilitators_facilitator_id ON public.member_facilitators USING btree (facilitator_id);


--
-- Name: idx_member_facilitators_facilitator_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_member_facilitators_facilitator_status ON public.member_facilitators USING btree (facilitator_id, status);


--
-- Name: idx_member_facilitators_member_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_member_facilitators_member_id ON public.member_facilitators USING btree (member_id);


--
-- Name: idx_member_facilitators_member_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_member_facilitators_member_status ON public.member_facilitators USING btree (member_id, status);


--
-- Name: idx_member_phones_member_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_member_phones_member_id ON public.member_phones USING btree (member_id);


--
-- Name: idx_member_phones_phone_normalized_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_member_phones_phone_normalized_active ON public.member_phones USING btree (phone_normalized) WHERE ((phone_normalized IS NOT NULL) AND (phone_normalized <> ''::text) AND (status = 'active'::text));


--
-- Name: idx_members_created_by_facilitator; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_members_created_by_facilitator ON public.members USING btree (created_by_facilitator_id);


--
-- Name: idx_members_created_report; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_members_created_report ON public.members USING btree (created_at, status);


--
-- Name: idx_members_facilitator_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_members_facilitator_active ON public.members USING btree (is_facilitator, status);


--
-- Name: idx_members_is_donations_reviewer_true; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_members_is_donations_reviewer_true ON public.members USING btree (member_id) WHERE (is_donations_reviewer IS TRUE);


--
-- Name: idx_party_contact_sources_contact; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_party_contact_sources_contact ON public.party_contact_sources USING btree (party_contact_id, status);


--
-- Name: idx_party_contacts_lookup; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_party_contacts_lookup ON public.party_contacts USING btree (contact_kind, identity_key) WHERE ((status = 'active'::text) AND (contact_kind = ANY (ARRAY['email'::text, 'phone'::text])));


--
-- Name: idx_party_contacts_organization; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_party_contacts_organization ON public.party_contacts USING btree (organization_id, contact_kind);


--
-- Name: idx_party_contacts_person; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_party_contacts_person ON public.party_contacts USING btree (person_id, contact_kind);


--
-- Name: idx_releases_report; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_releases_report ON public.releases USING btree (released_at, created_at, status);


--
-- Name: idx_sacrament_releases_release_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_sacrament_releases_release_type ON public.releases USING btree (release_type);


--
-- Name: idx_sacrament_releases_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_sacrament_releases_status ON public.releases USING btree (status, created_at DESC);


--
-- Name: member_agreements_practitioner_person_created_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX member_agreements_practitioner_person_created_idx ON public.member_agreements USING btree (practitioner_person_id, created_at DESC);


--
-- Name: member_practitioner_assignments_member_status_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX member_practitioner_assignments_member_status_idx ON public.member_practitioner_assignments USING btree (member_id, status);


--
-- Name: member_practitioner_assignments_person_status_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX member_practitioner_assignments_person_status_idx ON public.member_practitioner_assignments USING btree (practitioner_person_id, status);


--
-- Name: person_roles_role_key_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX person_roles_role_key_idx ON public.person_roles USING btree (role_key, person_id);


--
-- Name: practitioner_storage_location_name_status_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX practitioner_storage_location_name_status_idx ON public.practitioner_storage_location_access USING btree (storage_location_name, status);


--
-- Name: practitioner_storage_location_person_status_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX practitioner_storage_location_person_status_idx ON public.practitioner_storage_location_access USING btree (practitioner_person_id, status);


--
-- Name: releases_practitioner_person_released_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX releases_practitioner_person_released_idx ON public.releases USING btree (practitioner_person_id, released_at DESC);


--
-- Name: sacrament_releases_member_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sacrament_releases_member_id_idx ON public.releases USING btree (member_id);


--
-- Name: sacrament_releases_member_id_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sacrament_releases_member_id_idx1 ON public.releases USING btree (member_id);


--
-- Name: sacrament_releases_member_id_idx2; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sacrament_releases_member_id_idx2 ON public.releases USING btree (member_id);


--
-- Name: sacrament_releases_member_id_idx3; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sacrament_releases_member_id_idx3 ON public.releases USING btree (member_id);


--
-- Name: sacrament_releases_member_id_idx4; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sacrament_releases_member_id_idx4 ON public.releases USING btree (member_id);


--
-- Name: sacrament_releases_member_id_idx5; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sacrament_releases_member_id_idx5 ON public.releases USING btree (member_id);


--
-- Name: sacrament_releases_member_id_idx6; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sacrament_releases_member_id_idx6 ON public.releases USING btree (member_id);


--
-- Name: sacrament_releases_mushroomprocess_product_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sacrament_releases_mushroomprocess_product_id_idx ON public.releases USING btree (mushroomprocess_product_id);


--
-- Name: sacrament_releases_mushroomprocess_product_id_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sacrament_releases_mushroomprocess_product_id_idx1 ON public.releases USING btree (mushroomprocess_product_id);


--
-- Name: sacrament_releases_mushroomprocess_product_id_idx2; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sacrament_releases_mushroomprocess_product_id_idx2 ON public.releases USING btree (mushroomprocess_product_id);


--
-- Name: sacrament_releases_mushroomprocess_product_id_idx3; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sacrament_releases_mushroomprocess_product_id_idx3 ON public.releases USING btree (mushroomprocess_product_id);


--
-- Name: sacrament_releases_mushroomprocess_product_id_idx4; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sacrament_releases_mushroomprocess_product_id_idx4 ON public.releases USING btree (mushroomprocess_product_id);


--
-- Name: sacrament_releases_mushroomprocess_product_id_idx5; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sacrament_releases_mushroomprocess_product_id_idx5 ON public.releases USING btree (mushroomprocess_product_id);


--
-- Name: sacrament_releases_mushroomprocess_product_id_idx6; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sacrament_releases_mushroomprocess_product_id_idx6 ON public.releases USING btree (mushroomprocess_product_id);


--
-- Name: uq_cash_deposit_batch_items_donation; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_cash_deposit_batch_items_donation ON public.cash_deposit_batch_items USING btree (donation_id);


--
-- Name: uq_cash_deposit_batches_slip_number; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_cash_deposit_batches_slip_number ON public.cash_deposit_batches USING btree (lower(btrim(deposit_slip_number))) WHERE ((deposit_slip_number IS NOT NULL) AND (NULLIF(btrim(deposit_slip_number), ''::text) IS NOT NULL));


--
-- Name: uq_contributor_addresses_active_identity; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_contributor_addresses_active_identity ON public.contributor_addresses USING btree (contributor_id, address_identity_key) WHERE ((status = 'active'::text) AND (address_identity_key IS NOT NULL) AND (address_identity_key <> ''::text));


--
-- Name: uq_contributor_emails_active_value; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_contributor_emails_active_value ON public.contributor_emails USING btree (contributor_id, email_normalized) WHERE ((status = 'active'::text) AND (email_normalized IS NOT NULL) AND (email_normalized <> ''::text));


--
-- Name: uq_contributor_external_identity_active; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_contributor_external_identity_active ON public.contributor_external_identities USING btree (lower(btrim(provider)), btrim(provider_identity)) WHERE (status = 'active'::text);


--
-- Name: uq_contributor_member_links_active_contributor; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_contributor_member_links_active_contributor ON public.contributor_member_links USING btree (contributor_id) WHERE (status = 'active'::text);


--
-- Name: uq_contributor_member_links_active_member; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_contributor_member_links_active_member ON public.contributor_member_links USING btree (member_id) WHERE (status = 'active'::text);


--
-- Name: uq_contributor_phones_active_value; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_contributor_phones_active_value ON public.contributor_phones USING btree (contributor_id, phone_normalized) WHERE ((status = 'active'::text) AND (phone_normalized IS NOT NULL) AND (phone_normalized <> ''::text));


--
-- Name: uq_contributors_organization; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_contributors_organization ON public.contributors USING btree (organization_id) WHERE (organization_id IS NOT NULL);


--
-- Name: uq_contributors_person; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_contributors_person ON public.contributors USING btree (person_id) WHERE (person_id IS NOT NULL);


--
-- Name: uq_donations_provider_reference; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_donations_provider_reference ON public.donations USING btree (provider, provider_reference) WHERE ((provider_reference IS NOT NULL) AND (btrim(provider_reference) <> ''::text));


--
-- Name: uq_member_addresses_active_fingerprint_per_member; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_member_addresses_active_fingerprint_per_member ON public.member_addresses USING btree (member_id, address_type, address_fingerprint) WHERE ((address_fingerprint IS NOT NULL) AND (address_fingerprint <> ''::text) AND (status = 'active'::text));


--
-- Name: uq_member_addresses_active_identity_per_member; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_member_addresses_active_identity_per_member ON public.member_addresses USING btree (member_id, address_identity_key) WHERE ((address_identity_key IS NOT NULL) AND (address_identity_key <> ''::text) AND (status = 'active'::text));


--
-- Name: uq_member_emails_email_normalized_active; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_member_emails_email_normalized_active ON public.member_emails USING btree (email_normalized) WHERE ((email_normalized IS NOT NULL) AND (email_normalized <> ''::text) AND (status = 'active'::text));


--
-- Name: uq_member_emails_one_active_primary_per_member; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_member_emails_one_active_primary_per_member ON public.member_emails USING btree (member_id) WHERE ((COALESCE(status, 'active'::text) = 'active'::text) AND (is_primary = true));


--
-- Name: uq_members_active_email_normalized; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_members_active_email_normalized ON public.members USING btree (lower(btrim(email))) WHERE ((status = 'active'::text) AND (email IS NOT NULL) AND (btrim(email) <> ''::text));


--
-- Name: INDEX uq_members_active_email_normalized; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON INDEX public.uq_members_active_email_normalized IS 'Prevents active members from sharing the same normalized compatibility email cache.';


--
-- Name: uq_members_active_person; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_members_active_person ON public.members USING btree (person_id) WHERE (status = 'active'::text);


--
-- Name: uq_members_email_lower; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_members_email_lower ON public.members USING btree (lower(btrim(email))) WHERE ((email IS NOT NULL) AND (btrim(email) <> ''::text));


--
-- Name: uq_party_contacts_organization_value; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_party_contacts_organization_value ON public.party_contacts USING btree (organization_id, contact_kind, identity_key) WHERE ((organization_id IS NOT NULL) AND (identity_key IS NOT NULL));


--
-- Name: uq_party_contacts_person_value; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_party_contacts_person_value ON public.party_contacts USING btree (person_id, contact_kind, identity_key) WHERE ((person_id IS NOT NULL) AND (identity_key IS NOT NULL));


--
-- Name: uq_person_app_accounts_email; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_person_app_accounts_email ON public.person_app_accounts USING btree (email_normalized);


--
-- Name: agreement_templates trg_agreement_templates_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_agreement_templates_updated_at BEFORE UPDATE ON public.agreement_templates FOR EACH ROW EXECUTE FUNCTION public.set_agreement_templates_updated_at();


--
-- Name: cash_deposit_batches trg_cash_deposit_batches_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_cash_deposit_batches_immutable BEFORE DELETE OR UPDATE ON public.cash_deposit_batches FOR EACH ROW EXECUTE FUNCTION public.prevent_confirmed_cash_deposit_mutation();


--
-- Name: cash_deposit_batches trg_cash_deposit_batches_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_cash_deposit_batches_updated_at BEFORE UPDATE ON public.cash_deposit_batches FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: cash_deposit_batch_items trg_cash_deposit_items_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_cash_deposit_items_immutable BEFORE DELETE OR UPDATE ON public.cash_deposit_batch_items FOR EACH ROW EXECUTE FUNCTION public.prevent_confirmed_cash_deposit_item_mutation();


--
-- Name: contributor_addresses trg_contributor_addresses_party_contact; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_contributor_addresses_party_contact AFTER INSERT OR DELETE OR UPDATE ON public.contributor_addresses FOR EACH ROW EXECUTE FUNCTION public.sync_party_contact_source_trigger();


--
-- Name: contributor_addresses trg_contributor_addresses_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_contributor_addresses_updated_at BEFORE UPDATE ON public.contributor_addresses FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: contributor_emails trg_contributor_emails_party_contact; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_contributor_emails_party_contact AFTER INSERT OR DELETE OR UPDATE ON public.contributor_emails FOR EACH ROW EXECUTE FUNCTION public.sync_party_contact_source_trigger();


--
-- Name: contributor_emails trg_contributor_emails_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_contributor_emails_updated_at BEFORE UPDATE ON public.contributor_emails FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: contributor_external_identities trg_contributor_external_identities_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_contributor_external_identities_updated_at BEFORE UPDATE ON public.contributor_external_identities FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: contributor_member_links trg_contributor_member_links_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_contributor_member_links_updated_at BEFORE UPDATE ON public.contributor_member_links FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: contributor_phones trg_contributor_phones_party_contact; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_contributor_phones_party_contact AFTER INSERT OR DELETE OR UPDATE ON public.contributor_phones FOR EACH ROW EXECUTE FUNCTION public.sync_party_contact_source_trigger();


--
-- Name: contributor_phones trg_contributor_phones_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_contributor_phones_updated_at BEFORE UPDATE ON public.contributor_phones FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: contributors trg_contributors_check_linked_person; Type: TRIGGER; Schema: public; Owner: -
--

CREATE CONSTRAINT TRIGGER trg_contributors_check_linked_person AFTER INSERT OR UPDATE OF person_id ON public.contributors DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.check_linked_person_identity();


--
-- Name: contributors trg_contributors_remap_party_contacts; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_contributors_remap_party_contacts AFTER UPDATE OF person_id, organization_id ON public.contributors FOR EACH ROW WHEN (((old.person_id IS DISTINCT FROM new.person_id) OR (old.organization_id IS DISTINCT FROM new.organization_id))) EXECUTE FUNCTION public.sync_party_owner_contacts_trigger();


--
-- Name: contributors trg_contributors_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_contributors_updated_at BEFORE UPDATE ON public.contributors FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: donations trg_donations_set_donor_kind; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_donations_set_donor_kind BEFORE INSERT OR UPDATE OF member_id, contributor_id, donor_kind, provider ON public.donations FOR EACH ROW EXECUTE FUNCTION public.donation_set_donor_kind();


--
-- Name: facilitator_storage_location_access trg_fsl_access_set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_fsl_access_set_updated_at BEFORE UPDATE ON public.facilitator_storage_location_access FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: person_roles trg_issue19_guard_practitioner_role_removal; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_issue19_guard_practitioner_role_removal BEFORE DELETE ON public.person_roles FOR EACH ROW EXECUTE FUNCTION public.issue19_guard_practitioner_role_removal();


--
-- Name: releases trg_issue19_require_active_release_member; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_issue19_require_active_release_member BEFORE INSERT OR UPDATE OF member_id ON public.releases FOR EACH ROW EXECUTE FUNCTION public.issue19_require_active_release_member();


--
-- Name: member_agreements trg_issue19_sync_agreement_practitioner_identity; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_issue19_sync_agreement_practitioner_identity BEFORE INSERT OR UPDATE OF facilitator_id, practitioner_person_id ON public.member_agreements FOR EACH ROW EXECUTE FUNCTION public.issue19_sync_agreement_practitioner_identity();


--
-- Name: member_facilitators trg_issue19_sync_legacy_member_facilitator; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_issue19_sync_legacy_member_facilitator AFTER INSERT OR DELETE OR UPDATE ON public.member_facilitators FOR EACH ROW EXECUTE FUNCTION public.issue19_sync_legacy_member_facilitator();


--
-- Name: facilitator_storage_location_access trg_issue19_sync_legacy_practitioner_storage_location; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_issue19_sync_legacy_practitioner_storage_location AFTER INSERT OR DELETE OR UPDATE ON public.facilitator_storage_location_access FOR EACH ROW EXECUTE FUNCTION public.issue19_sync_legacy_practitioner_storage_location();


--
-- Name: releases trg_issue19_sync_release_practitioner_identity; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_issue19_sync_release_practitioner_identity BEFORE INSERT OR UPDATE OF facilitator_id, practitioner_person_id ON public.releases FOR EACH ROW EXECUTE FUNCTION public.issue19_sync_release_practitioner_identity();


--
-- Name: contributor_member_links trg_links_check_linked_person; Type: TRIGGER; Schema: public; Owner: -
--

CREATE CONSTRAINT TRIGGER trg_links_check_linked_person AFTER INSERT OR UPDATE OF member_id, contributor_id, status ON public.contributor_member_links DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.check_linked_person_identity();


--
-- Name: contributor_member_links trg_links_reconcile_person; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_links_reconcile_person AFTER INSERT OR UPDATE OF member_id, contributor_id, status ON public.contributor_member_links FOR EACH ROW EXECUTE FUNCTION public.reconcile_linked_person();


--
-- Name: listmonk_sync_queue trg_listmonk_sync_queue_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_listmonk_sync_queue_updated_at BEFORE UPDATE ON public.listmonk_sync_queue FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: member_addresses trg_member_addresses_party_contact; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_member_addresses_party_contact AFTER INSERT OR DELETE OR UPDATE ON public.member_addresses FOR EACH ROW EXECUTE FUNCTION public.sync_party_contact_source_trigger();


--
-- Name: member_addresses trg_member_addresses_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_member_addresses_updated_at BEFORE UPDATE ON public.member_addresses FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: member_emails trg_member_emails_enforce_single_primary; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_member_emails_enforce_single_primary BEFORE INSERT OR UPDATE OF member_id, status, is_primary ON public.member_emails FOR EACH ROW EXECUTE FUNCTION public.member_emails_enforce_single_primary_trg();


--
-- Name: member_emails trg_member_emails_listmonk_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_member_emails_listmonk_insert AFTER INSERT ON public.member_emails FOR EACH ROW EXECUTE FUNCTION public.trg_member_emails_listmonk_insert();


--
-- Name: member_emails trg_member_emails_party_contact; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_member_emails_party_contact AFTER INSERT OR DELETE OR UPDATE ON public.member_emails FOR EACH ROW EXECUTE FUNCTION public.sync_party_contact_source_trigger();


--
-- Name: member_emails trg_member_emails_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_member_emails_updated_at BEFORE UPDATE ON public.member_emails FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: member_facilitators trg_member_facilitators_set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_member_facilitators_set_updated_at BEFORE UPDATE ON public.member_facilitators FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: member_phones trg_member_phones_party_contact; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_member_phones_party_contact AFTER INSERT OR DELETE OR UPDATE ON public.member_phones FOR EACH ROW EXECUTE FUNCTION public.sync_party_contact_source_trigger();


--
-- Name: member_phones trg_member_phones_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_member_phones_updated_at BEFORE UPDATE ON public.member_phones FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: member_practitioner_assignments trg_member_practitioner_assignments_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_member_practitioner_assignments_updated_at BEFORE UPDATE ON public.member_practitioner_assignments FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: members trg_members_check_linked_person; Type: TRIGGER; Schema: public; Owner: -
--

CREATE CONSTRAINT TRIGGER trg_members_check_linked_person AFTER INSERT OR UPDATE OF person_id ON public.members DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.check_linked_person_identity();


--
-- Name: members trg_members_remap_party_contacts; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_members_remap_party_contacts AFTER UPDATE OF person_id ON public.members FOR EACH ROW WHEN ((old.person_id IS DISTINCT FROM new.person_id)) EXECUTE FUNCTION public.sync_party_owner_contacts_trigger();


--
-- Name: members trg_members_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_members_updated_at BEFORE UPDATE ON public.members FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: organization_terminology trg_organization_terminology_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_organization_terminology_updated_at BEFORE UPDATE ON public.organization_terminology FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: organizations trg_organizations_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_organizations_updated_at BEFORE UPDATE ON public.organizations FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: party_contact_sources trg_party_contact_sources_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_party_contact_sources_updated_at BEFORE UPDATE ON public.party_contact_sources FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: party_contacts trg_party_contacts_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_party_contacts_updated_at BEFORE UPDATE ON public.party_contacts FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: people trg_people_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_people_updated_at BEFORE UPDATE ON public.people FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: practitioner_storage_location_access trg_practitioner_storage_location_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_practitioner_storage_location_updated_at BEFORE UPDATE ON public.practitioner_storage_location_access FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: agreement_templates trg_validate_agreement_template_required_for; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_validate_agreement_template_required_for BEFORE INSERT OR UPDATE OF required_for ON public.agreement_templates FOR EACH ROW EXECUTE FUNCTION public.validate_agreement_template_required_for();


--
-- Name: contributor_member_links trg_validate_contributor_member_link; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_validate_contributor_member_link BEFORE INSERT OR UPDATE OF contributor_id, member_id, status ON public.contributor_member_links FOR EACH ROW WHEN ((new.status = 'active'::text)) EXECUTE FUNCTION public.validate_contributor_member_link();


--
-- Name: cash_deposit_batch_items cash_deposit_batch_items_deposit_batch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cash_deposit_batch_items
    ADD CONSTRAINT cash_deposit_batch_items_deposit_batch_id_fkey FOREIGN KEY (deposit_batch_id) REFERENCES public.cash_deposit_batches(deposit_batch_id) ON DELETE RESTRICT;


--
-- Name: cash_deposit_batch_items cash_deposit_batch_items_donation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cash_deposit_batch_items
    ADD CONSTRAINT cash_deposit_batch_items_donation_id_fkey FOREIGN KEY (donation_id) REFERENCES public.donations(donation_id) ON DELETE RESTRICT;


--
-- Name: cash_deposit_batches cash_deposit_batches_cancelled_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cash_deposit_batches
    ADD CONSTRAINT cash_deposit_batches_cancelled_by_fkey FOREIGN KEY (cancelled_by) REFERENCES public.members(member_id);


--
-- Name: cash_deposit_batches cash_deposit_batches_preparer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cash_deposit_batches
    ADD CONSTRAINT cash_deposit_batches_preparer_id_fkey FOREIGN KEY (preparer_id) REFERENCES public.members(member_id);


--
-- Name: cash_deposit_batches cash_deposit_batches_verifier_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cash_deposit_batches
    ADD CONSTRAINT cash_deposit_batches_verifier_id_fkey FOREIGN KEY (verifier_id) REFERENCES public.members(member_id);


--
-- Name: contributor_addresses contributor_addresses_archived_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contributor_addresses
    ADD CONSTRAINT contributor_addresses_archived_by_fkey FOREIGN KEY (archived_by) REFERENCES public.members(member_id);


--
-- Name: contributor_addresses contributor_addresses_contributor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contributor_addresses
    ADD CONSTRAINT contributor_addresses_contributor_id_fkey FOREIGN KEY (contributor_id) REFERENCES public.contributors(contributor_id) ON DELETE CASCADE;


--
-- Name: contributor_emails contributor_emails_archived_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contributor_emails
    ADD CONSTRAINT contributor_emails_archived_by_fkey FOREIGN KEY (archived_by) REFERENCES public.members(member_id);


--
-- Name: contributor_emails contributor_emails_contributor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contributor_emails
    ADD CONSTRAINT contributor_emails_contributor_id_fkey FOREIGN KEY (contributor_id) REFERENCES public.contributors(contributor_id) ON DELETE CASCADE;


--
-- Name: contributor_external_identities contributor_external_identities_contributor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contributor_external_identities
    ADD CONSTRAINT contributor_external_identities_contributor_id_fkey FOREIGN KEY (contributor_id) REFERENCES public.contributors(contributor_id) ON DELETE CASCADE;


--
-- Name: contributor_member_links contributor_member_links_contributor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contributor_member_links
    ADD CONSTRAINT contributor_member_links_contributor_id_fkey FOREIGN KEY (contributor_id) REFERENCES public.contributors(contributor_id);


--
-- Name: contributor_member_links contributor_member_links_ended_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contributor_member_links
    ADD CONSTRAINT contributor_member_links_ended_by_fkey FOREIGN KEY (ended_by) REFERENCES public.members(member_id);


--
-- Name: contributor_member_links contributor_member_links_linked_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contributor_member_links
    ADD CONSTRAINT contributor_member_links_linked_by_fkey FOREIGN KEY (linked_by) REFERENCES public.members(member_id);


--
-- Name: contributor_member_links contributor_member_links_member_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contributor_member_links
    ADD CONSTRAINT contributor_member_links_member_id_fkey FOREIGN KEY (member_id) REFERENCES public.members(member_id);


--
-- Name: contributor_phones contributor_phones_archived_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contributor_phones
    ADD CONSTRAINT contributor_phones_archived_by_fkey FOREIGN KEY (archived_by) REFERENCES public.members(member_id);


--
-- Name: contributor_phones contributor_phones_contributor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contributor_phones
    ADD CONSTRAINT contributor_phones_contributor_id_fkey FOREIGN KEY (contributor_id) REFERENCES public.contributors(contributor_id) ON DELETE CASCADE;


--
-- Name: contributors contributors_archived_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contributors
    ADD CONSTRAINT contributors_archived_by_fkey FOREIGN KEY (archived_by) REFERENCES public.members(member_id);


--
-- Name: contributors contributors_merged_into_contributor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contributors
    ADD CONSTRAINT contributors_merged_into_contributor_id_fkey FOREIGN KEY (merged_into_contributor_id) REFERENCES public.contributors(contributor_id);


--
-- Name: contributors contributors_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contributors
    ADD CONSTRAINT contributors_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(organization_id);


--
-- Name: contributors contributors_person_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contributors
    ADD CONSTRAINT contributors_person_id_fkey FOREIGN KEY (person_id) REFERENCES public.people(person_id);


--
-- Name: donations donations_contributor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.donations
    ADD CONSTRAINT donations_contributor_id_fkey FOREIGN KEY (contributor_id) REFERENCES public.contributors(contributor_id);


--
-- Name: donations donations_facilitator_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.donations
    ADD CONSTRAINT donations_facilitator_id_fkey FOREIGN KEY (facilitator_id) REFERENCES public.members(member_id);


--
-- Name: donations donations_member_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.donations
    ADD CONSTRAINT donations_member_id_fkey FOREIGN KEY (member_id) REFERENCES public.members(member_id);


--
-- Name: donations donations_reviewer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.donations
    ADD CONSTRAINT donations_reviewer_id_fkey FOREIGN KEY (reviewer_id) REFERENCES public.members(member_id);


--
-- Name: facilitator_storage_location_access facilitator_storage_location_access_assigned_by_member_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.facilitator_storage_location_access
    ADD CONSTRAINT facilitator_storage_location_access_assigned_by_member_id_fkey FOREIGN KEY (assigned_by_member_id) REFERENCES public.members(member_id);


--
-- Name: facilitator_storage_location_access facilitator_storage_location_access_facilitator_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.facilitator_storage_location_access
    ADD CONSTRAINT facilitator_storage_location_access_facilitator_id_fkey FOREIGN KEY (facilitator_id) REFERENCES public.members(member_id) ON DELETE CASCADE;


--
-- Name: listmonk_sync_queue listmonk_sync_queue_member_email_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.listmonk_sync_queue
    ADD CONSTRAINT listmonk_sync_queue_member_email_id_fkey FOREIGN KEY (member_email_id) REFERENCES public.member_emails(member_email_id) ON DELETE CASCADE;


--
-- Name: member_addresses member_addresses_archived_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.member_addresses
    ADD CONSTRAINT member_addresses_archived_by_fkey FOREIGN KEY (archived_by) REFERENCES public.members(member_id);


--
-- Name: member_addresses member_addresses_member_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.member_addresses
    ADD CONSTRAINT member_addresses_member_id_fkey FOREIGN KEY (member_id) REFERENCES public.members(member_id) ON DELETE CASCADE;


--
-- Name: member_agreements member_agreements_agreement_template_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.member_agreements
    ADD CONSTRAINT member_agreements_agreement_template_id_fkey FOREIGN KEY (agreement_template_id) REFERENCES public.agreement_templates(agreement_template_id);


--
-- Name: member_agreements member_agreements_canceled_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.member_agreements
    ADD CONSTRAINT member_agreements_canceled_by_fkey FOREIGN KEY (canceled_by) REFERENCES public.members(member_id) ON DELETE SET NULL;


--
-- Name: member_agreements member_agreements_facilitator_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.member_agreements
    ADD CONSTRAINT member_agreements_facilitator_id_fkey FOREIGN KEY (facilitator_id) REFERENCES public.members(member_id);


--
-- Name: member_agreements member_agreements_member_email_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.member_agreements
    ADD CONSTRAINT member_agreements_member_email_id_fkey FOREIGN KEY (member_email_id) REFERENCES public.member_emails(member_email_id);


--
-- Name: member_agreements member_agreements_member_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.member_agreements
    ADD CONSTRAINT member_agreements_member_id_fkey FOREIGN KEY (member_id) REFERENCES public.members(member_id);


--
-- Name: member_agreements member_agreements_practitioner_person_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.member_agreements
    ADD CONSTRAINT member_agreements_practitioner_person_id_fkey FOREIGN KEY (practitioner_person_id) REFERENCES public.people(person_id);


--
-- Name: member_agreements member_agreements_reviewer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.member_agreements
    ADD CONSTRAINT member_agreements_reviewer_id_fkey FOREIGN KEY (reviewer_id) REFERENCES public.members(member_id);


--
-- Name: member_emails member_emails_archived_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.member_emails
    ADD CONSTRAINT member_emails_archived_by_fkey FOREIGN KEY (archived_by) REFERENCES public.members(member_id);


--
-- Name: member_emails member_emails_member_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.member_emails
    ADD CONSTRAINT member_emails_member_id_fkey FOREIGN KEY (member_id) REFERENCES public.members(member_id) ON DELETE CASCADE;


--
-- Name: member_emails member_emails_verified_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.member_emails
    ADD CONSTRAINT member_emails_verified_by_fkey FOREIGN KEY (verified_by) REFERENCES public.members(member_id);


--
-- Name: member_facilitators member_facilitators_assigned_by_member_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.member_facilitators
    ADD CONSTRAINT member_facilitators_assigned_by_member_id_fkey FOREIGN KEY (assigned_by_member_id) REFERENCES public.members(member_id);


--
-- Name: member_facilitators member_facilitators_facilitator_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.member_facilitators
    ADD CONSTRAINT member_facilitators_facilitator_id_fkey FOREIGN KEY (facilitator_id) REFERENCES public.members(member_id) ON DELETE CASCADE;


--
-- Name: member_facilitators member_facilitators_member_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.member_facilitators
    ADD CONSTRAINT member_facilitators_member_id_fkey FOREIGN KEY (member_id) REFERENCES public.members(member_id) ON DELETE CASCADE;


--
-- Name: member_phones member_phones_archived_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.member_phones
    ADD CONSTRAINT member_phones_archived_by_fkey FOREIGN KEY (archived_by) REFERENCES public.members(member_id);


--
-- Name: member_phones member_phones_member_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.member_phones
    ADD CONSTRAINT member_phones_member_id_fkey FOREIGN KEY (member_id) REFERENCES public.members(member_id) ON DELETE CASCADE;


--
-- Name: member_practitioner_assignments member_practitioner_assignments_assigned_by_person_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.member_practitioner_assignments
    ADD CONSTRAINT member_practitioner_assignments_assigned_by_person_id_fkey FOREIGN KEY (assigned_by_person_id) REFERENCES public.people(person_id);


--
-- Name: member_practitioner_assignments member_practitioner_assignments_ended_by_person_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.member_practitioner_assignments
    ADD CONSTRAINT member_practitioner_assignments_ended_by_person_id_fkey FOREIGN KEY (ended_by_person_id) REFERENCES public.people(person_id);


--
-- Name: member_practitioner_assignments member_practitioner_assignments_member_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.member_practitioner_assignments
    ADD CONSTRAINT member_practitioner_assignments_member_id_fkey FOREIGN KEY (member_id) REFERENCES public.members(member_id);


--
-- Name: member_practitioner_assignments member_practitioner_assignments_practitioner_person_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.member_practitioner_assignments
    ADD CONSTRAINT member_practitioner_assignments_practitioner_person_id_fkey FOREIGN KEY (practitioner_person_id) REFERENCES public.people(person_id);


--
-- Name: members members_created_by_facilitator_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.members
    ADD CONSTRAINT members_created_by_facilitator_id_fkey FOREIGN KEY (created_by_facilitator_id) REFERENCES public.members(member_id);


--
-- Name: members members_person_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.members
    ADD CONSTRAINT members_person_id_fkey FOREIGN KEY (person_id) REFERENCES public.people(person_id);


--
-- Name: organization_terminology organization_terminology_concept_key_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organization_terminology
    ADD CONSTRAINT organization_terminology_concept_key_fkey FOREIGN KEY (concept_key) REFERENCES public.terminology_concepts(concept_key);


--
-- Name: party_contact_sources party_contact_sources_party_contact_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.party_contact_sources
    ADD CONSTRAINT party_contact_sources_party_contact_id_fkey FOREIGN KEY (party_contact_id) REFERENCES public.party_contacts(party_contact_id);


--
-- Name: party_contacts party_contacts_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.party_contacts
    ADD CONSTRAINT party_contacts_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(organization_id);


--
-- Name: party_contacts party_contacts_person_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.party_contacts
    ADD CONSTRAINT party_contacts_person_id_fkey FOREIGN KEY (person_id) REFERENCES public.people(person_id);


--
-- Name: person_app_accounts person_app_accounts_person_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.person_app_accounts
    ADD CONSTRAINT person_app_accounts_person_id_fkey FOREIGN KEY (person_id) REFERENCES public.people(person_id);


--
-- Name: person_identity_review person_identity_review_contributor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.person_identity_review
    ADD CONSTRAINT person_identity_review_contributor_id_fkey FOREIGN KEY (contributor_id) REFERENCES public.contributors(contributor_id);


--
-- Name: person_identity_review person_identity_review_member_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.person_identity_review
    ADD CONSTRAINT person_identity_review_member_id_fkey FOREIGN KEY (member_id) REFERENCES public.members(member_id);


--
-- Name: person_identity_review person_identity_review_person_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.person_identity_review
    ADD CONSTRAINT person_identity_review_person_id_fkey FOREIGN KEY (person_id) REFERENCES public.people(person_id);


--
-- Name: person_roles person_roles_person_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.person_roles
    ADD CONSTRAINT person_roles_person_id_fkey FOREIGN KEY (person_id) REFERENCES public.people(person_id);


--
-- Name: practitioner_storage_location_access practitioner_storage_location_acces_practitioner_person_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.practitioner_storage_location_access
    ADD CONSTRAINT practitioner_storage_location_acces_practitioner_person_id_fkey FOREIGN KEY (practitioner_person_id) REFERENCES public.people(person_id);


--
-- Name: practitioner_storage_location_access practitioner_storage_location_access_assigned_by_person_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.practitioner_storage_location_access
    ADD CONSTRAINT practitioner_storage_location_access_assigned_by_person_id_fkey FOREIGN KEY (assigned_by_person_id) REFERENCES public.people(person_id);


--
-- Name: releases releases_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.releases
    ADD CONSTRAINT releases_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.events(event_id);


--
-- Name: releases releases_member_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.releases
    ADD CONSTRAINT releases_member_id_fkey FOREIGN KEY (member_id) REFERENCES public.members(member_id);


--
-- Name: releases releases_practitioner_person_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.releases
    ADD CONSTRAINT releases_practitioner_person_id_fkey FOREIGN KEY (practitioner_person_id) REFERENCES public.people(person_id);


--
-- Name: releases sacrament_releases_member_agreement_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.releases
    ADD CONSTRAINT sacrament_releases_member_agreement_id_fkey FOREIGN KEY (member_agreement_id) REFERENCES public.member_agreements(member_agreement_id);


--
-- Name: releases sacrament_releases_voided_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.releases
    ADD CONSTRAINT sacrament_releases_voided_by_fkey FOREIGN KEY (voided_by) REFERENCES public.members(member_id);


--
-- PostgreSQL database dump complete
--

\unrestrict NHLVQVgbba0D5IcC8UQcS0GHuAZy5P0xtUsr5yQME14holwVZ63lXkr4ez9d3Ys

-- ============================================================
-- Cash deposit management (canonical schema)
-- ============================================================

-- Canonical cash deposit management backend.
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

-- Cash donation reconciliation exceptions

CREATE TABLE IF NOT EXISTS public.cash_deposit_donation_exclusions (
  exclusion_id uuid PRIMARY KEY DEFAULT public.uuid_generate_v4(),
  donation_id uuid NOT NULL
    REFERENCES public.donations(donation_id)
    ON DELETE RESTRICT,
  excluded_at timestamptz NOT NULL DEFAULT now(),
  excluded_by uuid NOT NULL REFERENCES public.members(member_id),
  reason text NOT NULL,
  notes text,
  CONSTRAINT cash_deposit_donation_exclusions_reason_check
    CHECK (NULLIF(btrim(reason), '') IS NOT NULL)
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_cash_deposit_donation_exclusions_active
  ON public.cash_deposit_donation_exclusions (donation_id);

CREATE INDEX IF NOT EXISTS idx_cash_deposit_donation_exclusions_excluded_at
  ON public.cash_deposit_donation_exclusions (excluded_at DESC);

CREATE OR REPLACE FUNCTION public.exclude_cash_donation_from_deposit(
  p_donation_id uuid,
  p_actor_id uuid,
  p_reason text,
  p_notes text DEFAULT NULL
)
RETURNS public.cash_deposit_donation_exclusions
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_exclusion public.cash_deposit_donation_exclusions%ROWTYPE;
  v_provider text;
  v_status text;
  v_donor_kind text;
  v_amount_cents integer;
BEGIN
  PERFORM public.assert_cash_deposit_verifier(p_actor_id);

  SELECT provider, status, donor_kind, amount_cents
  INTO v_provider, v_status, v_donor_kind, v_amount_cents
  FROM public.donations
  WHERE donation_id = p_donation_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Donation % was not found.', p_donation_id;
  END IF;

  IF v_provider <> 'cash'
     OR v_status <> 'verified'
     OR v_donor_kind NOT IN ('identified', 'anonymous')
     OR v_amount_cents IS NULL
     OR v_amount_cents <= 0
  THEN
    RAISE EXCEPTION
      'Donation % is not a verified, positive cash donation eligible for reconciliation disposition.',
      p_donation_id;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.cash_deposit_batch_items i
    WHERE i.donation_id = p_donation_id AND i.removed_at IS NULL
  ) THEN
    RAISE EXCEPTION
      'Donation % is already assigned to an active deposit batch.', p_donation_id;
  END IF;

  IF NULLIF(btrim(p_reason), '') IS NULL THEN
    RAISE EXCEPTION
      'A reason is required when excluding a cash donation from deposit reconciliation.';
  END IF;

  INSERT INTO public.cash_deposit_donation_exclusions (
    donation_id, excluded_by, reason, notes
  )
  VALUES (
    p_donation_id, p_actor_id, btrim(p_reason), NULLIF(btrim(p_notes), '')
  )
  RETURNING * INTO v_exclusion;

  INSERT INTO public.audit_log (actor, action, entity_type, entity_id, details)
  VALUES (
    public.cash_deposit_actor_email(p_actor_id),
    'cash_donation.deposit_reconciliation_excluded',
    'donation',
    p_donation_id::text,
    jsonb_build_object(
      'exclusion_id', v_exclusion.exclusion_id,
      'reason', v_exclusion.reason,
      'notes', v_exclusion.notes
    )
  );

  RETURN v_exclusion;
END;
$$;

CREATE OR REPLACE FUNCTION public.prevent_excluded_cash_deposit_item()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.cash_deposit_donation_exclusions e
    WHERE e.donation_id = NEW.donation_id
  ) THEN
    RAISE EXCEPTION
      'Donation % is excluded from cash-deposit reconciliation.',
      NEW.donation_id;
  END IF;

  RETURN NEW;
END;
$;

DROP TRIGGER IF EXISTS trg_cash_deposit_items_exclusion_guard
  ON public.cash_deposit_batch_items;

CREATE TRIGGER trg_cash_deposit_items_exclusion_guard
BEFORE INSERT ON public.cash_deposit_batch_items
FOR EACH ROW
EXECUTE FUNCTION public.prevent_excluded_cash_deposit_item();

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
-- Cash deposit lifecycle refinement

-- Cash deposit batch lifecycle refinement.
--
-- Extends the operational cash-deposit workflow with:
--   draft -> prepared -> confirmed
--   draft/prepared -> cancelled
--
-- Removed batch items remain as audit history. Active membership in a batch is
-- represented by removed_at IS NULL. ERPNext synchronization remains outside
-- this migration.


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
    AND NOT EXISTS (
      SELECT 1
      FROM public.cash_deposit_donation_exclusions e
      WHERE e.donation_id = d.donation_id
    )
  ORDER BY d.donated_at NULLS LAST, d.created_at, d.donation_id;
$$;

COMMENT ON TABLE public.cash_deposit_batches IS
  'Operational physical cash-deposit batches. Lifecycle is draft -> prepared -> confirmed or cancellation; ERPNext synchronization is separate.';

COMMENT ON TABLE public.cash_deposit_batch_items IS
  'Cash donations assigned to a batch. Removed items are retained as audit history and no longer count toward the batch.';
-- Cash deposit batch tally/read surface

-- Canonical cash deposit batch tally/read surface.
-- This migration is operational only; ERPNext synchronization remains separate.

CREATE OR REPLACE VIEW public.cash_deposit_batch_tally AS
SELECT
  b.deposit_batch_id,
  b.status,
  b.created_at AS batch_created_at,
  b.updated_at AS batch_updated_at,
  b.deposit_date,
  b.deposit_slip_number,
  b.destination_bank_account,
  b.preparer_id,
  prep.email AS preparer_email,
  b.prepared_by,
  b.prepared_at,
  b.verifier_id,
  ver.email AS verifier_email,
  b.confirmed_at,
  b.cancelled_at,
  b.cancelled_by,
  b.expected_amount_cents,
  b.actual_amount_cents,
  count(i.deposit_batch_item_id) OVER (
    PARTITION BY b.deposit_batch_id
  ) AS item_count,
  COALESCE(
    sum(i.amount_cents) OVER (
      PARTITION BY b.deposit_batch_id
    ),
    0
  ) AS item_total_cents,
  i.deposit_batch_item_id,
  i.created_at AS item_created_at,
  i.donation_id,
  i.amount_cents AS item_amount_cents,
  d.donated_at,
  d.currency,
  d.donor_kind,
  d.member_id,
  d.contributor_id,
  d.notes AS donation_notes
FROM public.cash_deposit_batches b
LEFT JOIN public.cash_deposit_batch_items i
  ON i.deposit_batch_id = b.deposit_batch_id
 AND i.removed_at IS NULL
LEFT JOIN public.members prep
  ON prep.member_id = b.preparer_id
LEFT JOIN public.members ver
  ON ver.member_id = b.verifier_id
LEFT JOIN public.donations d
  ON d.donation_id = i.donation_id;

COMMENT ON VIEW public.cash_deposit_batch_tally IS
  'Authoritative active-item cash deposit batch tally for operational review and printable deposit documentation. Contributor-neutral; donor identity remains on the donation.';

-- Cash deposit batch printable accounting report

CREATE OR REPLACE VIEW public.cash_deposit_batch_print AS
SELECT
  b.deposit_batch_id,
  b.status,
  b.created_at AS batch_created_at,
  b.updated_at AS batch_updated_at,
  b.deposit_date,
  b.deposit_slip_number,
  b.destination_bank_account,
  b.preparer_id,
  prep.email AS preparer_email,
  b.prepared_by,
  b.prepared_at,
  b.verifier_id,
  ver.email AS verifier_email,
  b.confirmed_at,
  b.cancelled_at,
  b.cancelled_by,
  b.expected_amount_cents,
  b.actual_amount_cents,
  b.notes AS batch_notes,
  i.deposit_batch_item_id,
  i.created_at AS item_added_at,
  i.donation_id,
  i.amount_cents AS item_amount_cents,
  d.donated_at,
  d.currency,
  d.donor_kind,
  d.provider_reference,
  d.notes AS donation_notes,
  d.review_notes,
  cp.display_name AS donor_name,
  cp.first_name AS donor_first_name,
  cp.last_name AS donor_last_name,
  cp.organization_name AS donor_organization_name
FROM public.cash_deposit_batches b
JOIN public.cash_deposit_batch_items i
  ON i.deposit_batch_id = b.deposit_batch_id
 AND i.removed_at IS NULL
JOIN public.donations d
  ON d.donation_id = i.donation_id
LEFT JOIN public.contributor_profiles cp
  ON cp.contributor_id = d.contributor_id
LEFT JOIN public.members prep
  ON prep.member_id = b.preparer_id
LEFT JOIN public.members ver
  ON ver.member_id = b.verifier_id
WHERE b.status IN ('prepared', 'confirmed');

COMMENT ON VIEW public.cash_deposit_batch_print IS
  'Printable accounting detail for prepared or confirmed cash deposit batches. One row per active donation, with batch header fields repeated for report generation.';
