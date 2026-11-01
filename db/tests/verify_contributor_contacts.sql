-- Rollback-only tests for contributor contact edits on both profile types.
\set ON_ERROR_STOP on
BEGIN;
DO $$
DECLARE
  v_actor uuid;
  v_individual record;
  v_other record;
  v_company record;
  v_first_email uuid;
  v_second_email uuid;
  v_company_phone uuid;
BEGIN
  INSERT INTO public.people(display_name)
    VALUES ('Contact Reviewer Test') RETURNING person_id INTO v_actor;
  INSERT INTO public.person_app_accounts(person_id,email)
    VALUES (v_actor,'issue19-contact-reviewer@example.invalid');
  INSERT INTO public.person_roles(person_id,role_key,assigned_by)
    VALUES (v_actor,'donations_reviewer','issue19_test');
  SELECT * INTO STRICT v_individual FROM public.issue19_create_contributor(
    'issue19-contact-reviewer@example.invalid','individual',
    'Contact','Target',NULL,NULL,NULL,'Contact integration test');
  SELECT * INTO STRICT v_company FROM public.issue19_create_contributor(
    'issue19-contact-reviewer@example.invalid','organization',
    NULL,NULL,'Test Contact Company',NULL,NULL,'Contact integration test');
  SELECT * INTO STRICT v_other FROM public.issue19_create_contributor(
    'issue19-contact-reviewer@example.invalid','individual',
    'Another','Party',NULL,NULL,NULL,'Contact ownership test');

  BEGIN
    PERFORM public.issue19_add_contributor_contact('unknown@example.invalid',
      'individual',v_individual.party_id,'email',
      'issue19-test-first@example.invalid','Denied test');
    RAISE EXCEPTION 'An unprivileged actor added a contact';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'Donations reviewer permission required' THEN RAISE; END IF;
  END;

  v_first_email := public.issue19_add_contributor_contact(
    'issue19-contact-reviewer@example.invalid','individual',
    v_individual.party_id,'email','issue19-test-first@example.invalid',
    'Initial donor email');
  v_second_email := public.issue19_add_contributor_contact(
    'issue19-contact-reviewer@example.invalid','individual',
    v_individual.party_id,'email','issue19-test-second@example.invalid',
    'New primary donor email');
  BEGIN
    PERFORM public.issue19_add_contributor_contact(
      'issue19-contact-reviewer@example.invalid','individual',
      v_other.party_id,'email','issue19-test-first@example.invalid',
      'Cross-person contact test');
    RAISE EXCEPTION 'Another individual reused the contact without review';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'Contact belongs to another party; review before sharing it'
    THEN RAISE; END IF;
  END;
  IF NOT EXISTS (SELECT 1 FROM public.contributor_emails
      WHERE contributor_email_id=v_second_email AND is_primary)
    OR NOT EXISTS (SELECT 1 FROM public.party_contacts
      WHERE person_id=v_individual.party_id AND contact_kind='email'
        AND identity_key='issue19-test-second@example.invalid'
        AND status='active') THEN
    RAISE EXCEPTION 'Email primary and party contact synchronization failed';
  END IF;

  BEGIN
    PERFORM public.issue19_add_contributor_contact(
      'issue19-contact-reviewer@example.invalid','organization',
      v_company.party_id,'email','issue19-test-first@example.invalid',
      'Shared contact test');
    RAISE EXCEPTION 'A different party reused the contact without review';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'Contact belongs to another party; review before sharing it'
    THEN RAISE; END IF;
  END;

  v_company_phone := public.issue19_add_contributor_contact(
    'issue19-contact-reviewer@example.invalid','organization',
    v_company.party_id,'phone','970-555-0134','Company donor phone');
  IF NOT EXISTS (SELECT 1 FROM public.party_contacts
      WHERE organization_id=v_company.party_id AND contact_kind='phone'
        AND identity_key='9705550134' AND status='active') THEN
    RAISE EXCEPTION 'Company phone not owned by organization';
  END IF;
  BEGIN
    PERFORM public.issue19_archive_contributor_contact(
      'issue19-contact-reviewer@example.invalid','organization',
      v_company.party_id,'email',v_second_email,'Cross-party test');
    RAISE EXCEPTION 'A different party archived the individual contact';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'Active email not found for this contributor' THEN RAISE; END IF;
  END;

  PERFORM public.issue19_archive_contributor_contact(
    'issue19-contact-reviewer@example.invalid','individual',
    v_individual.party_id,'email',v_second_email,'Replace wrong donor email');
  IF NOT EXISTS (SELECT 1 FROM public.contributor_emails
      WHERE contributor_email_id=v_first_email AND is_primary AND status='active')
    OR EXISTS (SELECT 1 FROM public.party_contacts
      WHERE person_id=v_individual.party_id AND contact_kind='email'
        AND identity_key='issue19-test-second@example.invalid'
        AND status='active')
    OR EXISTS (SELECT 1 FROM public.issue19_contributor_contacts(
      'issue19-contact-reviewer@example.invalid','individual',v_individual.party_id)
      WHERE contact_id=v_second_email) THEN
    RAISE EXCEPTION 'Archive did not promote prior contact or hide old value';
  END IF;
  IF (SELECT count(*) FROM public.audit_log WHERE entity_id IN
    (v_first_email::text,v_second_email::text,v_company_phone::text)
    AND action LIKE 'contributor_contact.%') <> 4 THEN
    RAISE EXCEPTION 'Contributor contact audit entries missing';
  END IF;
  RAISE NOTICE 'Contributor contact checks passed; rolling back synthetic records.';
END $$;
ROLLBACK;
