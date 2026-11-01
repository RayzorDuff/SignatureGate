-- Live integration checks with synthetic records; all writes roll back.
\set ON_ERROR_STOP on
BEGIN;

DO $$
DECLARE
  v_person uuid;
  v_member_person uuid;
  v_member uuid;
  v_contributor uuid;
  v_organization uuid;
  v_org_contributor uuid;
  v_donation uuid;
  v_other_member uuid;
  v_other_person uuid;
  v_other_contributor uuid;
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND (
        (table_name = 'members' AND column_name IN
          ('first_name', 'last_name', 'date_of_birth'))
        OR
        (table_name = 'contributors' AND column_name IN
          ('display_name', 'first_name', 'last_name', 'organization_name'))
      )
  ) THEN RAISE EXCEPTION 'Old identity columns are still stored on role tables'; END IF;

  INSERT INTO public.people (display_name, first_name, last_name)
  VALUES ('Sample Contributor', 'Sample', 'Contributor')
  RETURNING person_id INTO v_person;
  INSERT INTO public.contributors (contributor_type, person_id, source)
  VALUES ('individual', v_person, 'identity_test')
  RETURNING contributor_id INTO v_contributor;
  INSERT INTO public.donations
    (provider, amount_cents, donor_kind, contributor_id, status)
  VALUES ('cash', 100, 'identified', v_contributor, 'verified')
  RETURNING donation_id INTO v_donation;

  SELECT x.member_id INTO v_member
  FROM public.create_member_from_intake(
    'Sample', 'Contributor', NULL, NULL, NULL, 'identity test', false, NULL
  ) x WHERE x.duplicate_blocked IS FALSE;
  IF v_member IS NULL THEN RAISE EXCEPTION 'Member intake was blocked'; END IF;
  SELECT person_id INTO v_member_person
  FROM public.members WHERE member_id = v_member;
  INSERT INTO public.contributor_member_links (contributor_id, member_id)
  VALUES (v_contributor, v_member);
  IF (SELECT person_id FROM public.members WHERE member_id = v_member)
      IS DISTINCT FROM v_person
     OR (SELECT member_id FROM public.donations WHERE donation_id = v_donation)
      IS NOT NULL
  THEN RAISE EXCEPTION 'Link changed person ID or earlier donation history'; END IF;
  IF EXISTS (SELECT 1 FROM public.people WHERE person_id = v_member_person)
  THEN RAISE EXCEPTION 'Discarded intake person remains as a duplicate'; END IF;

  UPDATE public.people
  SET first_name = 'Updated', last_name = 'Identity',
      display_name = 'Updated Identity', date_of_birth = DATE '1990-01-01'
  WHERE person_id = v_person;
  IF (SELECT first_name FROM public.member_profiles WHERE member_id = v_member)
      IS DISTINCT FROM 'Updated'
    OR (SELECT date_of_birth FROM public.member_profiles WHERE member_id = v_member)
      IS DISTINCT FROM DATE '1990-01-01'
    OR (SELECT display_name FROM public.contributor_profiles
        WHERE contributor_id = v_contributor)
      IS DISTINCT FROM 'Updated Identity'
  THEN RAISE EXCEPTION 'Profiles do not read from the same person'; END IF;

  SELECT x.member_id INTO v_other_member
  FROM public.create_member_from_intake(
    'Member', 'First', NULL, NULL, NULL, 'identity test', false, NULL
  ) x WHERE x.duplicate_blocked IS FALSE;
  IF v_other_member IS NULL THEN RAISE EXCEPTION 'Member-first intake failed'; END IF;
  SELECT person_id INTO v_other_person FROM public.members
  WHERE member_id = v_other_member;
  v_other_contributor := public.ensure_member_contributor(v_other_member);
  IF (SELECT person_id FROM public.contributors
      WHERE contributor_id = v_other_contributor) IS DISTINCT FROM v_other_person
  THEN RAISE EXCEPTION 'Member-first donation created another person'; END IF;

  INSERT INTO public.organizations (organization_name)
  VALUES ('Sample Organization') RETURNING organization_id INTO v_organization;
  INSERT INTO public.contributors
    (contributor_type, organization_id, source)
  VALUES ('organization', v_organization, 'identity_test')
  RETURNING contributor_id INTO v_org_contributor;
  UPDATE public.organizations SET organization_name = 'Updated Organization'
  WHERE organization_id = v_organization;
  IF (SELECT display_name FROM public.contributor_profiles
      WHERE contributor_id = v_org_contributor) IS DISTINCT FROM 'Updated Organization'
  THEN RAISE EXCEPTION 'Organization donor profile did not reflect rename'; END IF;

  RAISE NOTICE 'Canonical identity checks passed; rolling back synthetic records.';
END $$;

SET CONSTRAINTS ALL IMMEDIATE;
ROLLBACK;
