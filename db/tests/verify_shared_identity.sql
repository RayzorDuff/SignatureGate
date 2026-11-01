-- Optional read/write smoke test. Changes are always rolled back.
\set ON_ERROR_STOP on
BEGIN;

DO $$
DECLARE
  v_donor public.contributors%ROWTYPE;
  v_member public.members%ROWTYPE;
  v_member_first public.members%ROWTYPE;
  v_organization public.contributors%ROWTYPE;
  v_gift uuid;
  v_donor_person uuid;
  v_member_person uuid;
  v_organization_id uuid;
  v_auto_contributor uuid;
  v_email text := public.uuid_generate_v4()::text || '@example.invalid';
  v_count integer;
BEGIN
  -- Individual donor exists before any membership or Appsmith account.
  INSERT INTO public.people(display_name,first_name,last_name,created_at)
  VALUES ('Synthetic Donor Person','Synthetic','Donor Person',now()-interval '1 day')
  RETURNING person_id INTO v_donor_person;
  INSERT INTO public.contributors(contributor_type,person_id,source)
  VALUES ('individual',v_donor_person,'identity_test')
  RETURNING * INTO v_donor;
  IF v_donor.person_id IS DISTINCT FROM v_donor_person THEN
    RAISE EXCEPTION 'Contributor role did not retain its canonical person';
  END IF;

  INSERT INTO public.donations
    (provider, amount_cents, donor_kind, contributor_id, status)
  VALUES ('cash', 100, 'identified', v_donor.contributor_id, 'verified')
  RETURNING donation_id INTO v_gift;

  -- Exercise legacy role-link reconciliation with explicit canonical identities.
  INSERT INTO public.people(display_name,first_name,last_name)
  VALUES ('Synthetic Donor Person','Synthetic','Donor Person')
  RETURNING person_id INTO v_member_person;
  INSERT INTO public.members(person_id)
  VALUES (v_member_person) RETURNING * INTO v_member;
  INSERT INTO public.contributor_member_links (contributor_id, member_id)
  VALUES (v_donor.contributor_id, v_member.member_id);

  IF (SELECT m.person_id FROM public.members m WHERE m.member_id = v_member.member_id)
     IS DISTINCT FROM v_donor.person_id THEN
    RAISE EXCEPTION 'Existing donor person ID was replaced by membership';
  END IF;
  IF (SELECT member_id FROM public.donations WHERE donation_id = v_gift)
     IS NOT NULL THEN
    RAISE EXCEPTION 'Donation preceding membership was retagged';
  END IF;

  -- Role tables no longer own duplicated name fields. Both presentation views
  -- must reflect edits to the one canonical person, in either name component.
  UPDATE public.people SET last_name = 'Revised'
  WHERE person_id = v_donor.person_id;
  IF (SELECT last_name FROM public.member_profiles
      WHERE member_id = v_member.member_id) IS DISTINCT FROM 'Revised'
     OR (SELECT last_name FROM public.contributor_profiles
         WHERE contributor_id = v_donor.contributor_id) IS DISTINCT FROM 'Revised' THEN
    RAISE EXCEPTION 'Canonical surname was not projected to both roles';
  END IF;

  UPDATE public.people SET first_name = 'Canonical'
  WHERE person_id = v_donor.person_id;
  IF (SELECT first_name FROM public.member_profiles WHERE member_id = v_member.member_id)
      IS DISTINCT FROM 'Canonical'
     OR (SELECT first_name FROM public.contributor_profiles
         WHERE contributor_id = v_donor.contributor_id)
      IS DISTINCT FROM 'Canonical' THEN
    RAISE EXCEPTION 'Canonical given name was not projected to both roles';
  END IF;

  INSERT INTO public.member_emails (member_id, email, is_primary)
  VALUES (v_member.member_id, v_email, true);
  INSERT INTO public.contributor_emails (contributor_id, email, is_primary)
  VALUES (v_donor.contributor_id, v_email, true);
  SELECT count(*) INTO v_count
  FROM public.v_person_emails
  WHERE person_id = v_donor.person_id AND email_normalized = v_email;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'Contact view returned % rows for one shared email', v_count;
  END IF;

  -- Member-first Givebutter/cash compatibility path keeps the member person.
  INSERT INTO public.people(display_name,first_name,last_name)
  VALUES ('Synthetic Participant First','Synthetic','Participant First')
  RETURNING person_id INTO v_member_person;
  INSERT INTO public.members(person_id)
  VALUES (v_member_person) RETURNING * INTO v_member_first;
  v_auto_contributor := public.ensure_member_contributor(v_member_first.member_id);
  IF (SELECT person_id FROM public.contributors
      WHERE contributor_id = v_auto_contributor)
     IS DISTINCT FROM v_member_first.person_id THEN
    RAISE EXCEPTION 'Member-first donor creation replaced person ID';
  END IF;

  INSERT INTO public.organizations(organization_name)
  VALUES ('Synthetic Organization') RETURNING organization_id INTO v_organization_id;
  INSERT INTO public.contributors(contributor_type,organization_id,source)
  VALUES ('organization',v_organization_id,'identity_test')
  RETURNING * INTO v_organization;
  IF v_organization.organization_id IS NULL OR v_organization.person_id IS NOT NULL THEN
    RAISE EXCEPTION 'Organization received the wrong identity type';
  END IF;
  UPDATE public.organizations SET organization_name = 'Revised Organization'
  WHERE organization_id = v_organization.organization_id;
  IF (SELECT organization_name FROM public.contributor_profiles
      WHERE contributor_id = v_organization.contributor_id)
     IS DISTINCT FROM 'Revised Organization' THEN
    RAISE EXCEPTION 'Organization name was not projected to contributor';
  END IF;

  RAISE NOTICE 'Shared-identity smoke test passed; rolling back fixtures.';
END $$;

-- Force the deferred cross-table identity constraint before rolling back.
SET CONSTRAINTS ALL IMMEDIATE;
ROLLBACK;
