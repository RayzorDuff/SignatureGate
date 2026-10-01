-- Rollback-only verification for Issue #19 contributor address editing.
\set ON_ERROR_STOP on
BEGIN;
DO $$
DECLARE
  v_actor uuid;
  v_person record;
  v_company record;
  v_home uuid;
  v_unit uuid;
  v_company_address uuid;
BEGIN
  INSERT INTO public.people(display_name) VALUES ('Address Reviewer Test')
    RETURNING person_id INTO v_actor;
  INSERT INTO public.person_app_accounts(person_id,email)
    VALUES (v_actor,'issue19-address-reviewer@example.invalid');
  INSERT INTO public.person_roles(person_id,role_key,assigned_by)
    VALUES (v_actor,'donations_reviewer','issue19_test');
  SELECT * INTO STRICT v_person FROM public.issue19_create_contributor(
    'issue19-address-reviewer@example.invalid','individual',
    'Address','Donor',NULL,NULL,NULL,'Address test');
  SELECT * INTO STRICT v_company FROM public.issue19_create_contributor(
    'issue19-address-reviewer@example.invalid','organization',
    NULL,NULL,'Address Test Company',NULL,NULL,'Address test');
  BEGIN
    PERFORM public.issue19_add_contributor_address(
      'unauthorized@example.invalid','individual',v_person.party_id,
      '715 N 7th Ct',NULL,'Johnstown','CO','80534','USA','Unauthorized test');
    RAISE EXCEPTION 'Unprivileged actor added an address';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'Donations reviewer permission required' THEN RAISE; END IF;
  END;
  v_home := public.issue19_add_contributor_address(
    'issue19-address-reviewer@example.invalid','individual',v_person.party_id,
    '715 North 7th Court',NULL,'Johnstown','CO','80534','USA','Donor address');
  BEGIN
    PERFORM public.issue19_add_contributor_address(
      'issue19-address-reviewer@example.invalid','individual',v_person.party_id,
      '715 N 7th Ct',NULL,'Another City','Colorado','80534','USA','Alias test');
    RAISE EXCEPTION 'Duplicate physical address created';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'This contributor already has this active physical address'
    THEN RAISE; END IF;
  END;
  v_unit := public.issue19_add_contributor_address(
    'issue19-address-reviewer@example.invalid','individual',v_person.party_id,
    '715 N 7th Ct','Apt 2','Johnstown','CO','80534','USA','Separate apartment');
  v_company_address := public.issue19_add_contributor_address(
    'issue19-address-reviewer@example.invalid','organization',v_company.party_id,
    '715 N 7th Ct',NULL,'Johnstown','CO','80534','USA','Shared building');
  IF (SELECT count(*) FROM public.issue19_contributor_addresses(
      'issue19-address-reviewer@example.invalid','individual',v_person.party_id)) <> 2
     OR EXISTS (SELECT 1 FROM public.issue19_contributor_addresses(
       'unauthorized@example.invalid','individual',v_person.party_id))
     OR NOT EXISTS (SELECT 1 FROM public.party_contacts
       WHERE person_id=v_person.party_id AND contact_kind='address'
         AND identity_key=public.member_address_identity_key(
           '715 N 7th Ct','Apt 2','80534','USA') AND status='active')
     OR NOT EXISTS (SELECT 1 FROM public.party_contacts
       WHERE organization_id=v_company.party_id AND contact_kind='address'
         AND identity_key=public.member_address_identity_key(
           '715 N 7th Ct',NULL,'80534','USA') AND status='active')
  THEN RAISE EXCEPTION 'Address ownership, unit identity, or contact sync failed'; END IF;
  BEGIN
    PERFORM public.issue19_archive_contributor_address(
      'issue19-address-reviewer@example.invalid','organization',
      v_company.party_id,v_home,'Wrong party');
    RAISE EXCEPTION 'Another party archived the address';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'Active address not found for this contributor' THEN RAISE; END IF;
  END;
  PERFORM public.issue19_archive_contributor_address(
    'issue19-address-reviewer@example.invalid','individual',
    v_person.party_id,v_home,'Corrected mailing address');
  IF NOT EXISTS (SELECT 1 FROM public.contributor_addresses
      WHERE contributor_address_id=v_unit AND status='active' AND is_primary)
    OR NOT EXISTS (SELECT 1 FROM public.contributor_addresses
      WHERE contributor_address_id=v_home AND status='archived' AND NOT is_primary)
    OR EXISTS (SELECT 1 FROM public.party_contacts pc
      WHERE pc.person_id=v_person.party_id AND pc.contact_kind='address'
        AND pc.identity_key=public.member_address_identity_key(
          '715 N 7th Ct',NULL,'80534','USA') AND pc.status='active')
    OR NOT EXISTS (SELECT 1 FROM public.contributor_addresses
      WHERE contributor_address_id=v_company_address AND status='active')
    OR (SELECT count(*) FROM public.audit_log
      WHERE entity_id IN (v_home::text,v_unit::text,v_company_address::text)
        AND action LIKE 'contributor_address.%') <> 4
  THEN RAISE EXCEPTION 'Address archive, primary promotion or audit failed'; END IF;
  RAISE NOTICE 'Contributor address checks passed; rolling back synthetic records.';
END $$;
ROLLBACK;
