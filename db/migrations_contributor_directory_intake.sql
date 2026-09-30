-- Issue #19: create standalone individual/company contributors from Directory
-- and enable the contributor role for a selected, existing person.
-- Apply after migrations_issue_19_person_roles.sql; run once.
\set ON_ERROR_STOP on
BEGIN;

DO $$ BEGIN
  IF to_regprocedure('public.issue19_has_role(text,text)') IS NULL
    OR to_regclass('public.party_contacts') IS NULL
    OR to_regclass('public.person_app_accounts') IS NULL THEN
    RAISE EXCEPTION 'Apply the Issue #19 contacts and person roles migrations first';
  END IF;
END $$;

CREATE FUNCTION public.issue19_create_contributor(
  p_actor_email text, p_party_kind text, p_first_name text,
  p_last_name text, p_organization_name text, p_email text,
  p_phone text, p_reason text
)
RETURNS TABLE (party_kind text, party_id uuid, contributor_id uuid)
LANGUAGE plpgsql VOLATILE SECURITY INVOKER
SET search_path = public, pg_temp AS $$
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

CREATE FUNCTION public.issue19_enable_person_contributor(
  p_actor_email text, p_person_id uuid, p_reason text
)
RETURNS uuid LANGUAGE plpgsql VOLATILE SECURITY INVOKER
SET search_path = public, pg_temp AS $$
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
COMMIT;
