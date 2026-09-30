-- Rollback-only contributor intake integration check.
\set ON_ERROR_STOP on
BEGIN;
DO $$
DECLARE
  v_actor uuid;
  v_existing uuid;
  v_individual record;
  v_company record;
  v_linked uuid;
BEGIN
  INSERT INTO public.people(display_name) VALUES ('Directory Intake Reviewer')
    RETURNING person_id INTO v_actor;
  INSERT INTO public.people(display_name) VALUES ('Directory Existing Person')
    RETURNING person_id INTO v_existing;
  INSERT INTO public.person_app_accounts(person_id,email)
  VALUES (v_actor,'issue19-directory-intake@example.invalid');
  INSERT INTO public.person_roles(person_id,role_key,assigned_by)
  VALUES (v_actor,'donations_reviewer','issue19_test'),
    (v_actor,'directory_manager','issue19_test');

  BEGIN
    PERFORM public.issue19_create_contributor('unknown@example.invalid',
      'individual','Test','Donor',null,null,null,'Unauthorized test');
    RAISE EXCEPTION 'Unprivileged contributor creation succeeded';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'Donations reviewer permission required' THEN RAISE; END IF;
  END;

  BEGIN
    PERFORM public.issue19_create_contributor(
      'issue19-directory-intake@example.invalid','individual',
      'Invalid','Phone',null,null,'no digits','Phone validation test');
    RAISE EXCEPTION 'Invalid phone number was accepted';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'Enter a ten-digit phone number' THEN RAISE; END IF;
  END;

  SELECT * INTO STRICT v_individual FROM public.issue19_create_contributor(
    'issue19-directory-intake@example.invalid','individual',
    'New','Donor',null,'issue19-new-donor@example.invalid',
    '970-555-0199','Test individual donation identity');
  IF v_individual.party_kind <> 'individual'
    OR NOT EXISTS (SELECT 1 FROM public.contributor_profiles c
      JOIN public.people p USING(person_id)
      WHERE c.contributor_id=v_individual.contributor_id
        AND p.first_name='New' AND p.last_name='Donor')
    OR NOT EXISTS (SELECT 1 FROM public.party_contacts pc
      WHERE pc.person_id=v_individual.party_id
        AND pc.contact_kind='email'
        AND pc.identity_key='issue19-new-donor@example.invalid') THEN
    RAISE EXCEPTION 'Standalone individual or contact synchronization failed';
  END IF;

  BEGIN
    PERFORM public.issue19_create_contributor(
      'issue19-directory-intake@example.invalid','individual',
      'Duplicate','Donor',null,'issue19-new-donor@example.invalid',
      null,'Duplicate check');
    RAISE EXCEPTION 'Duplicate contact created another person';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'Contact is already in use; review the Directory before creating a new identity'
    THEN RAISE; END IF;
  END;

  SELECT * INTO STRICT v_company FROM public.issue19_create_contributor(
    'issue19-directory-intake@example.invalid','organization',
    null,null,'Directory Example Co',null,null,'Test company donation identity');
  IF v_company.party_kind <> 'organization'
    OR NOT EXISTS (SELECT 1 FROM public.contributor_profiles c
      WHERE c.contributor_id=v_company.contributor_id
        AND c.organization_name='Directory Example Co')
    OR NOT EXISTS (SELECT 1 FROM public.issue19_directory_entries(
      'issue19-directory-intake@example.invalid') d
      WHERE d.party_id=v_company.party_id) THEN
    RAISE EXCEPTION 'Standalone company creation or directory visibility failed';
  END IF;

  v_linked := public.issue19_enable_person_contributor(
    'issue19-directory-intake@example.invalid',v_existing,
    'Test converting an existing individual');
  IF NOT EXISTS (SELECT 1 FROM public.contributors
    WHERE contributor_id=v_linked AND person_id=v_existing)
    OR NOT EXISTS (SELECT 1 FROM public.audit_log
      WHERE entity_id=v_linked::text AND action='contributor.enabled_for_person') THEN
    RAISE EXCEPTION 'Existing person conversion was not audited';
  END IF;
  IF EXISTS (SELECT 1 FROM public.members WHERE person_id IN
    (v_existing,v_individual.party_id)) THEN
    RAISE EXCEPTION 'Contributor intake created a membership';
  END IF;
  RAISE NOTICE 'Directory contributor intake checks passed; rolling back synthetic records.';
END $$;
ROLLBACK;
