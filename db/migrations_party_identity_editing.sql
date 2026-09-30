-- Issue #19: audited canonical person and organization identity maintenance.
-- Apply after migrations_issue_19_contributor_status.sql.
\set ON_ERROR_STOP on
BEGIN;

DO $$ BEGIN
  IF to_regprocedure('public.issue19_directory_entries(text)') IS NULL
     OR to_regprocedure('public.issue19_has_role(text,text)') IS NULL
     OR to_regprocedure('public.issue19_set_contributor_status(text,text,uuid,text,text)') IS NULL
     OR to_regclass('public.people') IS NULL
     OR to_regclass('public.organizations') IS NULL THEN
    RAISE EXCEPTION 'Apply the Issue #19 directory, role, and contributor-status migrations first';
  END IF;
END $$;

CREATE FUNCTION public.issue19_party_identity_state(
  p_actor_email text,p_party_kind text,p_party_id uuid
)
RETURNS TABLE (
  party_kind text,
  party_id uuid,
  display_name text,
  first_name text,
  last_name text,
  date_of_birth date,
  identity_version text,
  can_edit boolean
)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = public, pg_temp AS $$
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

CREATE FUNCTION public.issue19_update_person_identity(
  p_actor_email text,
  p_person_id uuid,
  p_display_name text,
  p_first_name text,
  p_last_name text,
  p_date_of_birth date,
  p_expected_version text,
  p_reason text
)
RETURNS uuid LANGUAGE plpgsql VOLATILE SECURITY INVOKER
SET search_path = public, pg_temp AS $$
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

CREATE FUNCTION public.issue19_update_organization_identity(
  p_actor_email text,
  p_organization_id uuid,
  p_organization_name text,
  p_expected_version text,
  p_reason text
)
RETURNS uuid LANGUAGE plpgsql VOLATILE SECURITY INVOKER
SET search_path = public, pg_temp AS $$
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

COMMENT ON FUNCTION public.issue19_party_identity_state(text,text,uuid) IS
  'Returns canonical identity fields only to a directory manager who can reach the profile.';
COMMENT ON FUNCTION public.issue19_update_person_identity(text,uuid,text,text,text,date,text,text) IS
  'Updates canonical person identity with optimistic concurrency and old/new audit details.';
COMMENT ON FUNCTION public.issue19_update_organization_identity(text,uuid,text,text,text) IS
  'Updates canonical organization identity with optimistic concurrency and old/new audit details.';
COMMIT;
