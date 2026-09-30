-- Issue #19: manage membership-purpose mailing addresses from the canonical
-- Individual Profile. Membership and contributor address records remain
-- independent; sharing one physical address across capacities is explicit.
-- Apply after migrations_issue_19_member_contact_profiles.sql.
\set ON_ERROR_STOP on
BEGIN;

DO $$ BEGIN
  IF to_regprocedure('public.issue19_person_member_operations_state(text,uuid)') IS NULL
     OR to_regprocedure('public.upsert_member_address(uuid,text,text,text,text,text,text,text,boolean,text,text)') IS NULL
     OR to_regclass('public.party_contact_sources') IS NULL
     OR to_regclass('public.member_addresses') IS NULL THEN
    RAISE EXCEPTION 'Apply the Issue #19 member-contact, party-contact, and address-identity migrations first';
  END IF;
END $$;

CREATE FUNCTION public.issue19_person_membership_addresses(
  p_actor_email text, p_person_id uuid
)
RETURNS TABLE (
  address_id uuid,
  address_type text,
  address_1 text,
  address_2 text,
  city text,
  state text,
  postal_code text,
  country text,
  is_primary boolean,
  created_at timestamptz
)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = public, pg_temp AS $$
SELECT address.member_address_id,address.address_type,address.address_1,
  address.address_2,address.city,address.state,address.postal_code,
  address.country,address.is_primary,address.created_at
FROM public.issue19_person_member_operations_state(
  p_actor_email,p_person_id) state
JOIN public.member_addresses address ON address.member_id=state.member_id
WHERE state.can_view AND address.status='active'
ORDER BY address.is_primary DESC,address.created_at,address.member_address_id;
$$;

CREATE FUNCTION public.issue19_add_membership_address(
  p_actor_email text, p_person_id uuid,
  p_address_1 text, p_address_2 text, p_city text, p_state text,
  p_postal_code text, p_country text, p_reason text
)
RETURNS uuid LANGUAGE plpgsql VOLATILE SECURITY INVOKER
SET search_path = public, pg_temp AS $$
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

CREATE FUNCTION public.issue19_archive_membership_address(
  p_actor_email text, p_person_id uuid, p_address_id uuid, p_reason text
)
RETURNS boolean LANGUAGE plpgsql VOLATILE SECURITY INVOKER
SET search_path = public, pg_temp AS $$
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

COMMENT ON FUNCTION public.issue19_person_membership_addresses(text,uuid) IS
  'Returns active membership-purpose mailing addresses without exposing contributor address rows.';
COMMENT ON FUNCTION public.issue19_add_membership_address(text,uuid,text,text,text,text,text,text,text) IS
  'Adds an audited membership-purpose address; contributor addresses require their own write or reviewed capacity assignment.';
COMMENT ON FUNCTION public.issue19_archive_membership_address(text,uuid,uuid,text) IS
  'Archives one membership-purpose address while retaining canonical and contributor history.';
COMMIT;
