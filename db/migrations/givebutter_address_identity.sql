-- Keep incomplete Givebutter addresses in the source payload until they can be reviewed.
CREATE OR REPLACE FUNCTION public.add_donation_payload_to_contributor(p_contributor_id uuid, p_donation_id uuid, p_source text DEFAULT 'givebutter_review'::text) RETURNS void
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_payload jsonb := COALESCE(public.donation_provider_payload(p_donation_id), '{}'::jsonb);
  v_email text;
  v_phone text;
  v_address jsonb;
  v_address_1 text;
  v_address_2 text;
  v_postal_code text;
  v_country text;
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
  v_address_1 := NULLIF(btrim(COALESCE(
    v_address->>'address_1', v_address->>'line1',
    v_address->>'street', v_address->>'street_address'
  )), '');
  v_address_2 := COALESCE(v_address->>'address_2', v_address->>'line2', v_address->>'suite');
  v_postal_code := COALESCE(v_address->>'zipcode', v_address->>'postal_code', v_address->>'zip');
  v_country := COALESCE(NULLIF(v_address->>'country', ''), 'USA');

  -- Preserve incomplete Givebutter addresses in the donation payload. Without
  -- a physical address key, replay cannot safely identify a matching row.
  IF v_address_1 IS NOT NULL AND (
    v_provider IS DISTINCT FROM 'givebutter'
    OR public.member_address_identity_key(v_address_1, v_address_2, v_postal_code, v_country) IS NOT NULL
  ) THEN
    IF v_provider = 'givebutter' THEN
      -- Concurrent reviews for the same Contributor must see prior writes.
      PERFORM 1 FROM public.contributors
      WHERE contributor_id = p_contributor_id FOR NO KEY UPDATE;
    END IF;
    PERFORM public.upsert_contributor_address(
      p_contributor_id => p_contributor_id,
      p_address_1 => v_address_1,
      p_address_type => 'mailing',
      p_address_2 => v_address_2,
      p_city => v_address->>'city',
      p_state => COALESCE(v_address->>'state', v_address->>'province'),
      p_postal_code => v_postal_code,
      p_country => v_country,
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
