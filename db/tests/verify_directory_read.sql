-- Rollback-only access and directory checks with synthetic records.
\set ON_ERROR_STOP on
BEGIN;
DO $$
DECLARE
  v_doc_actor uuid;
  v_donor_actor uuid;
  v_member_person uuid;
  v_member uuid;
  v_donor_person uuid;
  v_donor uuid;
  v_organization uuid;
  v_company uuid;
BEGIN
  INSERT INTO public.people(display_name) VALUES ('Directory Doc Actor')
    RETURNING person_id INTO v_doc_actor;
  INSERT INTO public.people(display_name) VALUES ('Directory Donor Actor')
    RETURNING person_id INTO v_donor_actor;
  INSERT INTO public.members(person_id,email,is_facilitator,is_document_reviewer)
    VALUES (v_doc_actor,'issue19-doc-actor@example.invalid',true,true);
  INSERT INTO public.members(person_id,email,is_facilitator,is_donations_reviewer)
    VALUES (v_donor_actor,'issue19-donor-actor@example.invalid',true,true);

  INSERT INTO public.people(display_name) VALUES ('Directory Member Target')
    RETURNING person_id INTO v_member_person;
  INSERT INTO public.members(person_id) VALUES (v_member_person)
    RETURNING member_id INTO v_member;
  INSERT INTO public.member_emails(member_id,email)
    VALUES (v_member,'issue19-member-contact@example.invalid');
  INSERT INTO public.contributors(contributor_type,person_id,source)
    VALUES ('individual',v_member_person,'directory_test');
  INSERT INTO public.contributor_emails(contributor_id,email)
    SELECT contributor_id,'issue19-donor-contact@example.invalid'
    FROM public.contributors WHERE person_id=v_member_person;

  INSERT INTO public.people(display_name) VALUES ('Directory Donor Only')
    RETURNING person_id INTO v_donor_person;
  INSERT INTO public.contributors(contributor_type,person_id,source)
    VALUES ('individual',v_donor_person,'directory_test')
    RETURNING contributor_id INTO v_donor;
  INSERT INTO public.organizations(organization_name) VALUES ('Directory Company')
    RETURNING organization_id INTO v_organization;
  INSERT INTO public.contributors(contributor_type,organization_id,source)
    VALUES ('organization',v_organization,'directory_test')
    RETURNING contributor_id INTO v_company;

  IF NOT EXISTS (SELECT 1 FROM public.issue19_directory_entries(
      'issue19-doc-actor@example.invalid') d
    WHERE d.party_id=v_member_person AND d.member_id=v_member
      AND d.contributor_id IS NULL)
    OR EXISTS (SELECT 1 FROM public.issue19_directory_entries(
      'issue19-doc-actor@example.invalid') d
    WHERE d.party_id IN (v_donor_person,v_organization))
  THEN RAISE EXCEPTION 'Document reviewer directory scope failed'; END IF;

  IF NOT EXISTS (SELECT 1 FROM public.issue19_directory_entries(
      'issue19-donor-actor@example.invalid') d
    WHERE d.party_id=v_member_person AND d.member_id IS NULL
      AND d.contributor_id IS NOT NULL)
    OR NOT EXISTS (SELECT 1 FROM public.issue19_directory_entries(
      'issue19-donor-actor@example.invalid') d
    WHERE d.party_id=v_organization AND d.party_kind='organization')
  THEN RAISE EXCEPTION 'Donations reviewer directory scope failed'; END IF;

  IF EXISTS (SELECT 1 FROM public.issue19_directory_contacts(
      'issue19-doc-actor@example.invalid','individual',v_member_person) c
      WHERE c.contact_detail='issue19-donor-contact@example.invalid')
    OR EXISTS (SELECT 1 FROM public.issue19_directory_contacts(
      'issue19-donor-actor@example.invalid','individual',v_member_person) c
      WHERE c.contact_detail='issue19-member-contact@example.invalid')
  THEN RAISE EXCEPTION 'Contact scope crossed membership and donation roles'; END IF;

  IF EXISTS (SELECT 1 FROM public.issue19_directory_entries(
      'unknown-issue19@example.invalid'))
    OR EXISTS (SELECT 1 FROM public.issue19_directory_contacts(
      'unknown-issue19@example.invalid','organization',v_organization))
  THEN RAISE EXCEPTION 'Unknown actor could read directory'; END IF;

  RAISE NOTICE 'Directory scope checks passed; rolling back synthetic records.';
END $$;
SET CONSTRAINTS ALL IMMEDIATE;
ROLLBACK;
