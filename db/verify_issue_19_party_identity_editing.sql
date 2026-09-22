-- Rollback-only checks for canonical party identity editing.
\set ON_ERROR_STOP on
BEGIN;
DO $$
DECLARE
  v_manager uuid; v_denied uuid; v_person uuid; v_organization uuid;
  v_member uuid; v_contributor uuid; v_org_contributor uuid; v_donation uuid;
  v_person_version text; v_org_version text;
BEGIN
  INSERT INTO public.people(display_name) VALUES ('Identity Edit Manager')
    RETURNING person_id INTO v_manager;
  INSERT INTO public.person_app_accounts(person_id,email)
    VALUES (v_manager,'issue19-identity-manager@example.invalid');
  INSERT INTO public.person_roles(person_id,role_key,assigned_by)
    VALUES (v_manager,'directory_manager','issue19_test');

  INSERT INTO public.people(display_name) VALUES ('Identity Edit Denied')
    RETURNING person_id INTO v_denied;
  INSERT INTO public.person_app_accounts(person_id,email)
    VALUES (v_denied,'issue19-identity-denied@example.invalid');

  INSERT INTO public.people(display_name,first_name,last_name,date_of_birth)
    VALUES ('Original Person','Original','Person','1980-01-02')
    RETURNING person_id INTO v_person;
  INSERT INTO public.members(person_id) VALUES (v_person) RETURNING member_id INTO v_member;
  INSERT INTO public.contributors(contributor_type,person_id,source)
    VALUES ('individual',v_person,'issue19_test') RETURNING contributor_id INTO v_contributor;
  INSERT INTO public.contributor_member_links(contributor_id,member_id,link_reason)
    VALUES (v_contributor,v_member,'issue19_test');
  INSERT INTO public.donations(contributor_id,member_id,donor_kind,provider,
    provider_reference,amount_cents,status)
    VALUES (v_contributor,v_member,'identified','cash','issue19-identity-edit',1500,'verified')
    RETURNING donation_id INTO v_donation;
  SELECT identity_version INTO v_person_version
  FROM public.issue19_party_identity_state(
    'issue19-identity-manager@example.invalid','individual',v_person);

  IF NOT EXISTS (SELECT 1 FROM public.issue19_party_identity_state(
       'issue19-identity-manager@example.invalid','individual',v_person)
       WHERE display_name='Original Person' AND can_edit)
    OR EXISTS (SELECT 1 FROM public.issue19_party_identity_state(
       'issue19-identity-denied@example.invalid','individual',v_person)) THEN
    RAISE EXCEPTION 'Canonical identity state permission check failed';
  END IF;

  BEGIN
    PERFORM public.issue19_update_person_identity(
      'issue19-identity-denied@example.invalid',v_person,'Denied Change',
      'Denied','Change','1981-01-02',v_person_version,'Denied test');
    RAISE EXCEPTION 'Unauthorized actor updated person identity';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'Directory manager permission required' THEN RAISE; END IF;
  END;

  PERFORM public.issue19_update_person_identity(
    'issue19-identity-manager@example.invalid',v_person,'Corrected Person',
    'Corrected','Person','1981-02-03',v_person_version,'Corrected legal identity');

  IF NOT EXISTS (SELECT 1 FROM public.people WHERE person_id=v_person
       AND display_name='Corrected Person' AND first_name='Corrected'
       AND last_name='Person' AND date_of_birth='1981-02-03')
    OR NOT EXISTS (SELECT 1 FROM public.member_profiles
       WHERE member_id=v_member AND first_name='Corrected' AND last_name='Person')
    OR NOT EXISTS (SELECT 1 FROM public.contributor_profiles
       WHERE contributor_id=v_contributor AND display_name='Corrected Person')
    OR NOT EXISTS (SELECT 1 FROM public.donations
       WHERE donation_id=v_donation AND contributor_id=v_contributor AND member_id=v_member)
    OR NOT EXISTS (SELECT 1 FROM public.audit_log
       WHERE action='person.identity_updated' AND entity_id=v_person::text
         AND details->>'member_id'=v_member::text
         AND details->>'contributor_id'=v_contributor::text
         AND details->'previous'->>'display_name'='Original Person'
         AND details->'current'->>'display_name'='Corrected Person') THEN
    RAISE EXCEPTION 'Person identity update did not preserve its domain records or audit details';
  END IF;

  BEGIN
    PERFORM public.issue19_update_person_identity(
      'issue19-identity-manager@example.invalid',v_person,'Stale Change',
      'Stale','Change',NULL,v_person_version,'Stale test');
    RAISE EXCEPTION 'Stale person identity update was accepted';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM NOT LIKE 'This identity changed after the profile loaded%' THEN RAISE; END IF;
  END;

  INSERT INTO public.organizations(organization_name)
    VALUES ('Original Organization')
    RETURNING organization_id INTO v_organization;
  INSERT INTO public.contributors(contributor_type,organization_id,source)
    VALUES ('organization',v_organization,'issue19_test')
    RETURNING contributor_id INTO v_org_contributor;
  SELECT identity_version INTO v_org_version
  FROM public.issue19_party_identity_state(
    'issue19-identity-manager@example.invalid','organization',v_organization);
  PERFORM public.issue19_update_organization_identity(
    'issue19-identity-manager@example.invalid',v_organization,
    'Corrected Organization',v_org_version,'Corrected legal name');

  IF NOT EXISTS (SELECT 1 FROM public.organizations
       WHERE organization_id=v_organization
         AND organization_name='Corrected Organization')
    OR NOT EXISTS (SELECT 1 FROM public.contributor_profiles
       WHERE contributor_id=v_org_contributor
         AND organization_name='Corrected Organization')
    OR NOT EXISTS (SELECT 1 FROM public.audit_log
       WHERE action='organization.identity_updated'
         AND entity_id=v_organization::text
         AND details->>'contributor_id'=v_org_contributor::text
         AND details->'previous'->>'organization_name'='Original Organization'
         AND details->'current'->>'organization_name'='Corrected Organization') THEN
    RAISE EXCEPTION 'Organization identity update or audit detail failed';
  END IF;

  RAISE NOTICE 'Canonical party identity editing checks passed; rolling back synthetic records.';
END $$;
ROLLBACK;
