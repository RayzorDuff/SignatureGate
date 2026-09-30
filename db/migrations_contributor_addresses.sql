-- Issue #19: manage individual and organization contributor mailing addresses.
-- Legacy contributor address writes continue to project into party_contacts.
-- Apply after migrations_issue_19_end_membership.sql.
\set ON_ERROR_STOP on
BEGIN;

DO $$ BEGIN
  IF to_regprocedure('public.issue19_contributor_contacts(text,text,uuid)') IS NULL
     OR to_regprocedure('public.member_address_identity_key(text,text,text,text)') IS NULL
     OR to_regclass('public.party_contacts') IS NULL THEN
    RAISE EXCEPTION 'Apply Issue #19 contributor contacts and address identity migrations first';
  END IF;
END $$;

CREATE FUNCTION public.issue19_contributor_addresses(
  p_actor_email text, p_party_kind text, p_party_id uuid
)
RETURNS TABLE (
  address_id uuid, address_type text, address_1 text, address_2 text,
  city text, state text, postal_code text, country text, is_primary boolean
)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = public, pg_temp AS $$
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

CREATE FUNCTION public.issue19_add_contributor_address(
  p_actor_email text, p_party_kind text, p_party_id uuid,
  p_address_1 text, p_address_2 text, p_city text, p_state text,
  p_postal_code text, p_country text, p_reason text
)
RETURNS uuid LANGUAGE plpgsql VOLATILE SECURITY INVOKER
SET search_path = public, pg_temp AS $$
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

CREATE FUNCTION public.issue19_archive_contributor_address(
  p_actor_email text, p_party_kind text, p_party_id uuid,
  p_address_id uuid, p_reason text
)
RETURNS boolean LANGUAGE plpgsql VOLATILE SECURITY INVOKER
SET search_path = public, pg_temp AS $$
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
COMMIT;
