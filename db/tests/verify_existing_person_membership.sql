-- Rollback-only checks for adding a membership to an existing person.
\set ON_ERROR_STOP on
BEGIN;
DO $$
DECLARE
  v_actor uuid;
  v_donor record;
  v_unready uuid;
  v_member_id uuid;
  v_donation_id uuid;
BEGIN
  INSERT INTO public.people(display_name) VALUES ('Membership Test Reviewer')
    RETURNING person_id INTO v_actor;
  INSERT INTO public.person_app_accounts(person_id,email)
    VALUES (v_actor,'issue19-membership-reviewer@example.invalid');
  INSERT INTO public.person_roles(person_id,role_key,assigned_by)
    VALUES (v_actor,'document_reviewer','issue19_test'),
      (v_actor,'directory_manager','issue19_test'),
      (v_actor,'donations_reviewer','issue19_test');
  SELECT * INTO STRICT v_donor FROM public.issue19_create_contributor(
    'issue19-membership-reviewer@example.invalid','individual',
    'Donor','Member',NULL,NULL,NULL,'Membership integration test');
  INSERT INTO public.donations(contributor_id,donor_kind,provider,amount_cents,status)
  VALUES (v_donor.contributor_id,'identified','cash',1000,'pending_review')
  RETURNING donation_id INTO v_donation_id;
  INSERT INTO public.people(display_name) VALUES ('Incomplete Person')
    RETURNING person_id INTO v_unready;

  BEGIN
    PERFORM public.issue19_enable_person_membership(
      'unknown@example.invalid',v_donor.party_id,'Donor','Member','Unauthorized test');
    RAISE EXCEPTION 'Unprivileged actor enabled membership';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'Directory manager and document reviewer permissions required'
    THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM public.issue19_enable_person_membership(
      'issue19-membership-reviewer@example.invalid',v_unready,NULL,NULL,
      'Incomplete test');
    RAISE EXCEPTION 'Incomplete person was enrolled';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'Reviewed first and last name are required for membership'
    THEN RAISE; END IF;
  END;

  v_member_id := public.issue19_enable_person_membership(
    'issue19-membership-reviewer@example.invalid',v_donor.party_id,
    'Donor','Member',
    'Reviewed identity for membership');
  IF NOT EXISTS (SELECT 1 FROM public.members
      WHERE member_id=v_member_id AND person_id=v_donor.party_id
        AND status='active' AND NOT is_facilitator)
    OR NOT EXISTS (SELECT 1 FROM public.contributor_member_links
      WHERE member_id=v_member_id
        AND contributor_id=v_donor.contributor_id AND status='active')
    OR EXISTS (SELECT 1 FROM public.member_emails
      WHERE member_id=v_member_id)
    OR EXISTS (SELECT 1 FROM public.member_agreements
      WHERE member_id=v_member_id)
    OR NOT EXISTS (SELECT 1 FROM public.donations
      WHERE donation_id=v_donation_id AND contributor_id=v_donor.contributor_id
        AND member_id IS NULL AND donor_kind='identified')
    OR NOT EXISTS (SELECT 1 FROM public.audit_log
      WHERE entity_id=v_member_id::text
        AND action='membership.enabled_for_person') THEN
    RAISE EXCEPTION 'Existing-person membership, link or audit check failed';
  END IF;
  IF (SELECT count(*) FROM public.people WHERE person_id=v_donor.party_id) <> 1
  THEN RAISE EXCEPTION 'Membership created another person'; END IF;
  BEGIN
    PERFORM public.issue19_enable_person_membership(
      'issue19-membership-reviewer@example.invalid',v_donor.party_id,
      'Donor','Member',
      'Duplicate test');
    RAISE EXCEPTION 'Second membership record created';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'This person already has a membership record; review its status'
    THEN RAISE; END IF;
  END;
  v_member_id := public.issue19_enable_person_membership(
    'issue19-membership-reviewer@example.invalid',v_unready,
    'Incomplete','Person','Completed the reviewed person name');
  IF NOT EXISTS (SELECT 1 FROM public.people
      WHERE person_id=v_unready AND first_name='Incomplete'
        AND last_name='Person' AND display_name='Incomplete Person')
    OR NOT EXISTS (SELECT 1 FROM public.members
      WHERE person_id=v_unready AND member_id=v_member_id)
    OR EXISTS (SELECT 1 FROM public.contributors WHERE person_id=v_unready)
  THEN RAISE EXCEPTION 'Incomplete person identity was not completed safely'; END IF;
  RAISE NOTICE 'Existing-person membership checks passed; rolling back synthetic records.';
END $$;
ROLLBACK;
