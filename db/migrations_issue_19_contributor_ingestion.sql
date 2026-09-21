-- SignatureGate Issue #19, Phase 2: contributor-first provider ingestion.
--
-- Apply after db/migrations_issue_19_contributor_identity.sql and before
-- activating the matching Givebutter n8n workflow.

\set ON_ERROR_STOP on

BEGIN;

DO $$
DECLARE
  v_duplicates text;
BEGIN
  IF to_regclass('public.contributors') IS NULL
    OR to_regprocedure('public.ensure_member_contributor(uuid)') IS NULL
  THEN
    RAISE EXCEPTION
      'Issue #19 Phase 2 requires db/migrations_issue_19_contributor_identity.sql.';
  END IF;

  SELECT string_agg(format('%s/%s (%s rows)', provider, provider_reference, row_count), ', ')
  INTO v_duplicates
  FROM (
    SELECT provider, provider_reference, count(*) AS row_count
    FROM public.donations
    WHERE NULLIF(btrim(provider_reference), '') IS NOT NULL
    GROUP BY provider, provider_reference
    HAVING count(*) > 1
    ORDER BY provider, provider_reference
    LIMIT 10
  ) duplicate_refs;

  IF v_duplicates IS NOT NULL THEN
    RAISE EXCEPTION
      'Cannot add provider transaction idempotency until duplicate donation references are resolved: %',
      v_duplicates;
  END IF;
END;
$$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_donations_provider_reference
  ON public.donations (provider, provider_reference)
  WHERE provider_reference IS NOT NULL
    AND btrim(provider_reference) <> '';

CREATE OR REPLACE FUNCTION public.match_contributor_identity(
  p_provider text,
  p_provider_identity text DEFAULT NULL,
  p_email text DEFAULT NULL,
  p_phone text DEFAULT NULL
)
RETURNS TABLE (
  contributor_id uuid,
  member_id uuid,
  match_method text,
  match_score integer
)
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = public, pg_temp
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

CREATE OR REPLACE FUNCTION public.ingest_provider_donation(
  p_provider text,
  p_provider_reference text,
  p_amount_cents integer,
  p_currency text,
  p_donated_at timestamptz,
  p_notes text,
  p_raw jsonb,
  p_email text DEFAULT NULL,
  p_phone text DEFAULT NULL,
  p_provider_identity text DEFAULT NULL
)
RETURNS TABLE (
  donation_id uuid,
  contributor_id uuid,
  member_id uuid,
  donor_kind text,
  status text,
  match_method text,
  match_score integer,
  inserted boolean
)
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = public, pg_temp
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

COMMENT ON FUNCTION public.match_contributor_identity(text, text, text, text) IS
  'Matches provider identity, unique contributor email/phone, then unique member contact fallback in descending confidence order.';
COMMENT ON FUNCTION public.ingest_provider_donation(text, text, integer, text, timestamptz, text, jsonb, text, text, text) IS
  'Idempotently records a provider donation using contributor-first matching and preserves the raw payload for review.';

COMMIT;

-- Verification: duplicate provider references must remain impossible.
SELECT provider, provider_reference, count(*)
FROM public.donations
WHERE NULLIF(btrim(provider_reference), '') IS NOT NULL
GROUP BY provider, provider_reference
HAVING count(*) > 1;
