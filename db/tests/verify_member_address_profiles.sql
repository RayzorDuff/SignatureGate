-- Rollback-only checks for Individual Profile membership address maintenance.
\set ON_ERROR_STOP on
BEGIN;
DO $$
DECLARE
  v_reviewer_person uuid;
  v_outsider_person uuid;
  v_target_person uuid;
  v_target_member uuid;
  v_contributor_id uuid;
  v_home uuid;
  v_unit uuid;
  v_contributor_address uuid;
BEGIN
  INSERT INTO public.people(display_name) VALUES ('Issue 19 Address Reviewer')
    RETURNING person_id INTO v_reviewer_person;
  INSERT INTO public.person_app_accounts(person_id,email)
    VALUES (v_reviewer_person,'issue19-member-address-reviewer@example.invalid');
  INSERT INTO public.person_roles(person_id,role_key,assigned_by)
    VALUES (v_reviewer_person,'document_reviewer','issue19_verify');

  INSERT INTO public.people(display_name) VALUES ('Issue 19 Address Outsider')
    RETURNING person_id INTO v_outsider_person;
  INSERT INTO public.person_app_accounts(person_id,email)
    VALUES (v_outsider_person,'issue19-member-address-outsider@example.invalid');
  INSERT INTO public.person_roles(person_id,role_key,assigned_by)
    VALUES (v_outsider_person,'donations_reviewer','issue19_verify');

  INSERT INTO public.people(display_name) VALUES ('Issue 19 Address Target')
    RETURNING person_id INTO v_target_person;
  INSERT INTO public.members(person_id) VALUES (v_target_person)
    RETURNING member_id INTO v_target_member;
  INSERT INTO public.contributors(contributor_type,person_id)
    VALUES ('individual',v_target_person)
    RETURNING contributor_id INTO v_contributor_id;

  BEGIN
    PERFORM public.issue19_add_membership_address(
      'issue19-member-address-outsider@example.invalid',v_target_person,
      '715 N 7th Ct',NULL,'Johnstown','CO','80534','USA','Unauthorized test');
    RAISE EXCEPTION 'Donations-only reviewer modified membership addresses';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'Document reviewer permission required' THEN RAISE; END IF;
  END;

  v_home := public.issue19_add_membership_address(
    'issue19-member-address-reviewer@example.invalid',v_target_person,
    '715 North 7th Court',NULL,'Johnstown','CO','80534','USA',
    'Verified membership address');
  BEGIN
    PERFORM public.issue19_add_membership_address(
      'issue19-member-address-reviewer@example.invalid',v_target_person,
      '715 N 7th Ct',NULL,'Another City','Colorado','80534','United States',
      'Duplicate alias test');
    RAISE EXCEPTION 'Duplicate membership physical address was created';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'This membership already has this active physical address'
    THEN RAISE; END IF;
  END;
  v_unit := public.issue19_add_membership_address(
    'issue19-member-address-reviewer@example.invalid',v_target_person,
    '715 N 7th Ct','Apt 2','Johnstown','CO','80534','USA',
    'Separate membership apartment');

  IF (SELECT count(*) FROM public.issue19_person_membership_addresses(
      'issue19-member-address-reviewer@example.invalid',v_target_person)) <> 2
    OR EXISTS (SELECT 1 FROM public.issue19_person_membership_addresses(
      'issue19-member-address-outsider@example.invalid',v_target_person))
    OR NOT EXISTS (SELECT 1 FROM public.party_contacts contact
      JOIN public.party_contact_sources source
        ON source.party_contact_id=contact.party_contact_id
      WHERE contact.person_id=v_target_person AND contact.contact_kind='address'
        AND contact.identity_key=public.member_address_identity_key(
          '715 N 7th Ct','Apt 2','80534','USA')
        AND source.source_table='member_addresses'
        AND source.source_id=v_unit AND source.status='active')
    OR EXISTS (SELECT 1 FROM public.contributor_addresses
      WHERE contributor_id=v_contributor_id) THEN
    RAISE EXCEPTION 'Membership address ownership, visibility, or contact sync failed';
  END IF;

  INSERT INTO public.contributor_addresses(
    contributor_id,address_type,address_1,address_2,city,state,
    postal_code,country,is_primary,source,notes)
  VALUES (v_contributor_id,'mailing','215 E Oak St','Apt 1','Fort Collins',
    'CO','80524','USA',true,'issue19_verify','Independent contributor address')
  RETURNING contributor_address_id INTO v_contributor_address;
  BEGIN
    PERFORM public.issue19_add_membership_address(
      'issue19-member-address-reviewer@example.invalid',v_target_person,
      '215 East Oak Street','Unit 1','Fort Collins','Colorado','80524',
      'United States','Implicit sharing test');
    RAISE EXCEPTION 'Contributor address was implicitly copied into membership';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'This is an existing contributor address; use the reviewed cross-role assignment control'
    THEN RAISE; END IF;
  END;

  PERFORM public.issue19_archive_membership_address(
    'issue19-member-address-reviewer@example.invalid',v_target_person,
    v_home,'No longer used for membership');
  IF NOT EXISTS (SELECT 1 FROM public.member_addresses
      WHERE member_address_id=v_home AND status='archived'
        AND NOT is_primary AND archive_reason='No longer used for membership')
    OR NOT EXISTS (SELECT 1 FROM public.member_addresses
      WHERE member_address_id=v_unit AND status='active' AND is_primary)
    OR NOT EXISTS (SELECT 1 FROM public.contributor_addresses
      WHERE contributor_address_id=v_contributor_address AND status='active')
    OR (SELECT count(*) FROM public.audit_log
      WHERE entity_id IN (v_home::text,v_unit::text)
        AND action IN ('membership_address.added','membership_address.archived')) <> 3 THEN
    RAISE EXCEPTION 'Membership address archive, promotion, independence, or audit failed';
  END IF;

  UPDATE public.members SET status='inactive' WHERE member_id=v_target_member;
  IF NOT EXISTS (SELECT 1 FROM public.issue19_person_membership_addresses(
      'issue19-member-address-reviewer@example.invalid',v_target_person)
      WHERE address_id=v_unit) THEN
    RAISE EXCEPTION 'Former-member address history disappeared';
  END IF;
  BEGIN
    PERFORM public.issue19_add_membership_address(
      'issue19-member-address-reviewer@example.invalid',v_target_person,
      '100 Main St',NULL,'Johnstown','CO','80534','USA',
      'Inactive membership test');
    RAISE EXCEPTION 'Inactive membership accepted a new address';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'An active membership and document reviewer access are required'
    THEN RAISE; END IF;
  END;

  RAISE NOTICE 'Individual Profile membership address checks passed; rolling back synthetic records.';
END $$;
ROLLBACK;
