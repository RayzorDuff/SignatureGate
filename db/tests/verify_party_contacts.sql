-- Integration checks using synthetic parties; every write is rolled back.
\set ON_ERROR_STOP on
BEGIN;
DO $$
DECLARE
  v_person uuid;
  v_other_person uuid;
  v_new_person uuid;
  v_member uuid;
  v_contributor uuid;
  v_other_contributor uuid;
  v_organization uuid;
  v_org_contributor uuid;
  v_member_email uuid;
  v_contributor_email uuid;
  v_other_email uuid;
  v_member_contact uuid;
  v_org_contact uuid;
  v_address uuid;
BEGIN
  INSERT INTO public.people(display_name,first_name,last_name)
    VALUES ('Contact Test A','Contact','Test A') RETURNING person_id INTO v_person;
  INSERT INTO public.people(display_name,first_name,last_name)
    VALUES ('Contact Test B','Contact','Test B') RETURNING person_id INTO v_other_person;
  INSERT INTO public.people(display_name,first_name,last_name)
    VALUES ('Contact Test C','Contact','Test C') RETURNING person_id INTO v_new_person;
  INSERT INTO public.organizations(organization_name)
    VALUES ('Contact Test Company') RETURNING organization_id INTO v_organization;

  INSERT INTO public.members(person_id) VALUES (v_person) RETURNING member_id INTO v_member;
  INSERT INTO public.contributors(contributor_type,person_id,source)
    VALUES ('individual',v_person,'contact_test')
    RETURNING contributor_id INTO v_contributor;
  INSERT INTO public.contributors(contributor_type,person_id,source)
    VALUES ('individual',v_other_person,'contact_test')
    RETURNING contributor_id INTO v_other_contributor;
  INSERT INTO public.contributors(contributor_type,organization_id,source)
    VALUES ('organization',v_organization,'contact_test')
    RETURNING contributor_id INTO v_org_contributor;

  INSERT INTO public.member_emails(member_id,email,is_primary)
    VALUES (v_member,'contact-test-19@example.invalid',true)
    RETURNING member_email_id INTO v_member_email;
  INSERT INTO public.contributor_emails(contributor_id,email,is_primary)
    VALUES (v_contributor,'CONTACT-TEST-19@example.invalid',true)
    RETURNING contributor_email_id INTO v_contributor_email;
  INSERT INTO public.contributor_emails(contributor_id,email,is_primary)
    VALUES (v_other_contributor,'contact-test-19@example.invalid',true)
    RETURNING contributor_email_id INTO v_other_email;
  SELECT party_contact_id INTO v_member_contact
    FROM public.party_contact_sources
    WHERE source_table='member_emails' AND source_id=v_member_email;
  IF v_member_contact IS NULL OR
    (SELECT party_contact_id FROM public.party_contact_sources
      WHERE source_table='contributor_emails' AND source_id=v_contributor_email)
      IS DISTINCT FROM v_member_contact OR
    (SELECT party_contact_id FROM public.party_contact_sources
      WHERE source_table='contributor_emails' AND source_id=v_other_email)
      IS NOT DISTINCT FROM v_member_contact
  THEN RAISE EXCEPTION 'Same-person deduplication or distinct-owner isolation failed';
  END IF;

  INSERT INTO public.contributor_emails(contributor_id,email)
    VALUES (v_org_contributor,'contact-test-19@example.invalid');
  SELECT c.party_contact_id INTO v_org_contact
  FROM public.party_contacts c
  WHERE c.organization_id=v_organization AND c.contact_kind='email';
  IF v_org_contact IS NULL OR v_org_contact=v_member_contact
  THEN RAISE EXCEPTION 'Organization contact merged with an individual'; END IF;

  INSERT INTO public.contributor_addresses(contributor_id,address_1,city,state,postal_code)
    VALUES (v_contributor,'909 Contact Ct','Test Town','CO','80534')
    RETURNING contributor_address_id INTO v_address;
  INSERT INTO public.contributor_addresses(contributor_id,address_1,city,state,postal_code)
    VALUES (v_other_contributor,'909 Contact Court','Test Town','CO','80534');
  IF (SELECT count(*) FROM public.party_contacts
      WHERE contact_kind='address' AND address_1 LIKE '909 Contact%') <> 2
  THEN RAISE EXCEPTION 'Shared household address merged two people'; END IF;

  UPDATE public.member_emails SET status='archived'
    WHERE member_email_id=v_member_email;
  IF (SELECT status FROM public.party_contacts WHERE party_contact_id=v_member_contact)
    <> 'active' THEN RAISE EXCEPTION 'Archiving a member source hid an active donor source'; END IF;
  UPDATE public.contributor_emails SET status='archived'
    WHERE contributor_email_id=v_contributor_email;
  IF (SELECT status FROM public.party_contacts WHERE party_contact_id=v_member_contact)
    <> 'archived' THEN RAISE EXCEPTION 'Contact with no active source stayed active'; END IF;

  UPDATE public.contributor_emails
  SET email='contact-test-19-new@example.invalid',status='active'
  WHERE contributor_email_id=v_contributor_email;
  IF (SELECT c.identity_key FROM public.party_contact_sources s
      JOIN public.party_contacts c USING (party_contact_id)
      WHERE s.source_table='contributor_emails' AND s.source_id=v_contributor_email)
      <> 'contact-test-19-new@example.invalid'
  THEN RAISE EXCEPTION 'Editing a source did not update its canonical contact'; END IF;

  UPDATE public.members SET person_id=v_new_person WHERE member_id=v_member;
  IF (SELECT c.person_id FROM public.party_contact_sources s
      JOIN public.party_contacts c USING (party_contact_id)
      WHERE s.source_table='member_emails' AND s.source_id=v_member_email)
      IS DISTINCT FROM v_new_person
  THEN RAISE EXCEPTION 'Person reconciliation did not remap member contact'; END IF;
  IF EXISTS (SELECT 1 FROM public.party_contact_sources s
    JOIN public.party_contacts c USING (party_contact_id)
    WHERE s.source_table='contributor_addresses' AND s.source_id=v_address
      AND c.person_id IS DISTINCT FROM v_person)
  THEN RAISE EXCEPTION 'Donor address owner changed without a link'; END IF;

  RAISE NOTICE 'Party contact integration checks passed; rolling back test records.';
END $$;
SET CONSTRAINTS ALL IMMEDIATE;
ROLLBACK;
