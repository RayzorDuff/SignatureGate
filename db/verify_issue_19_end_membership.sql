-- Rollback-only integration checks. Run after the end-membership migration.
\set ON_ERROR_STOP on
BEGIN;
DO $$
DECLARE
  v_actor uuid;
  v_person uuid;
  v_member uuid;
  v_contributor uuid;
  v_donation uuid;
  v_later_donation uuid;
  v_agreement uuid;
  v_other uuid;
BEGIN
  INSERT INTO public.people(display_name) VALUES ('Membership End Reviewer')
    RETURNING person_id INTO v_actor;
  INSERT INTO public.person_app_accounts(person_id,email)
    VALUES (v_actor,'issue19-end-reviewer@example.invalid');
  INSERT INTO public.person_roles(person_id,role_key,assigned_by)
    VALUES (v_actor,'directory_manager','issue19_test'),
      (v_actor,'document_reviewer','issue19_test'),
      (v_actor,'donations_reviewer','issue19_test');

  INSERT INTO public.people(display_name,first_name,last_name)
    VALUES ('Former Member','Former','Member') RETURNING person_id INTO v_person;
  v_member := public.issue19_enable_person_membership(
    'issue19-end-reviewer@example.invalid',v_person,'Former','Member','Test start');
  BEGIN
    PERFORM public.issue19_end_person_membership(
      'issue19-end-reviewer@example.invalid',v_person,'Missing contributor');
    RAISE EXCEPTION 'Membership ended without a contributor';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'Enable this individual as a contributor before ending membership'
    THEN RAISE; END IF;
  END;
  v_contributor := public.issue19_enable_person_contributor(
    'issue19-end-reviewer@example.invalid',v_person,'Test contributor');
  -- Existing member/contributor links may also have been created by other
  -- paths. This one proves that the link is closed and donations are retained.
  INSERT INTO public.contributor_member_links
    (contributor_id,member_id,status,link_reason)
    VALUES (v_contributor,v_member,'active','End-membership integration test');
  INSERT INTO public.donations(contributor_id,donor_kind,provider,amount_cents,status)
    VALUES (v_contributor,'identified','cash',500,'pending_review')
    RETURNING donation_id INTO v_donation;
  INSERT INTO public.member_agreements(member_id,signature_method,status)
    VALUES (v_member,'paper','pending_review') RETURNING member_agreement_id INTO v_agreement;
  BEGIN
    PERFORM public.issue19_end_person_membership(
      'issue19-end-reviewer@example.invalid',v_person,'Pending document');
    RAISE EXCEPTION 'Membership ended with pending agreement';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'Resolve pending membership agreements before ending membership'
    THEN RAISE; END IF;
  END;
  UPDATE public.member_agreements SET status='signed' WHERE member_agreement_id=v_agreement;
  INSERT INTO public.person_roles(person_id,role_key,assigned_by)
    VALUES (v_person,'practitioner','issue19_test');
  BEGIN
    PERFORM public.issue19_end_person_membership(
      'issue19-end-reviewer@example.invalid',v_person,'Still practitioner');
    RAISE EXCEPTION 'Membership ended with active appointment';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'Reassign active facilitator work and remove appointments and permissions before ending membership'
    THEN RAISE; END IF;
  END;
  DELETE FROM public.person_roles WHERE person_id=v_person;
  INSERT INTO public.people(display_name) VALUES ('Test Facilitator')
    RETURNING person_id INTO v_other;
  INSERT INTO public.members(person_id) VALUES (v_other) RETURNING member_id INTO v_other;
  INSERT INTO public.member_facilitators(member_id,facilitator_id,status)
    VALUES (v_other,v_member,'active');
  BEGIN
    PERFORM public.issue19_end_person_membership(
      'issue19-end-reviewer@example.invalid',v_person,'Assigned facilitator');
    RAISE EXCEPTION 'Membership ended with active facilitator assignment';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'Reassign active facilitator work and remove appointments and permissions before ending membership'
    THEN RAISE; END IF;
  END;
  UPDATE public.member_facilitators SET status='inactive' WHERE facilitator_id=v_member;
  BEGIN
    PERFORM public.issue19_end_person_membership(
      'unknown@example.invalid',v_person,'Unauthorized');
    RAISE EXCEPTION 'Unprivileged actor ended membership';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'Directory manager and document reviewer permissions required'
    THEN RAISE; END IF;
  END;
  IF NOT (SELECT can_end FROM public.issue19_person_membership_state(
      'issue19-end-reviewer@example.invalid',v_person)) THEN
    RAISE EXCEPTION 'Eligible member was not presented as eligible';
  END IF;
  PERFORM public.issue19_end_person_membership(
    'issue19-end-reviewer@example.invalid',v_person,'Requested conversion');
  INSERT INTO public.donations(contributor_id,donor_kind,provider,amount_cents,status)
    VALUES (v_contributor,'identified','cash',300,'pending_review')
    RETURNING donation_id INTO v_later_donation;
  IF NOT EXISTS (SELECT 1 FROM public.members
      WHERE member_id=v_member AND status='inactive' AND person_id=v_person
        AND membership_ended_at IS NOT NULL
        AND membership_end_reason='Requested conversion')
    OR NOT EXISTS (SELECT 1 FROM public.contributor_member_links
      WHERE member_id=v_member AND contributor_id=v_contributor
        AND status='ended' AND ended_at IS NOT NULL)
    OR NOT EXISTS (SELECT 1 FROM public.contributors
      WHERE contributor_id=v_contributor AND person_id=v_person AND status='active')
    OR NOT EXISTS (SELECT 1 FROM public.donations
      WHERE donation_id=v_donation AND contributor_id=v_contributor
        AND member_id=v_member AND donor_kind='identified')
    OR NOT EXISTS (SELECT 1 FROM public.donations
      WHERE donation_id=v_later_donation AND contributor_id=v_contributor
        AND member_id IS NULL AND donor_kind='identified')
    OR NOT EXISTS (SELECT 1 FROM public.member_agreements
      WHERE member_agreement_id=v_agreement AND member_id=v_member AND status='signed')
    OR NOT EXISTS (SELECT 1 FROM public.audit_log
      WHERE action='membership.ended_for_person' AND entity_id=v_member::text)
    OR NOT EXISTS (SELECT 1 FROM public.issue19_directory_entries(
      'issue19-end-reviewer@example.invalid')
      WHERE party_id=v_person AND member_id IS NULL
        AND contributor_id=v_contributor)
  THEN RAISE EXCEPTION 'Membership closure lost contributor or history'; END IF;
  IF (SELECT membership_status FROM public.issue19_person_membership_state(
      'issue19-end-reviewer@example.invalid',v_person)) <> 'inactive'
    OR EXISTS (SELECT 1 FROM public.issue19_person_membership_state(
      'unknown@example.invalid',v_person))
  THEN RAISE EXCEPTION 'Membership history is not scoped correctly'; END IF;
  BEGIN
    INSERT INTO public.releases(member_id,mushroomprocess_product_id)
    VALUES (v_member,'issue19-end-membership-test');
    RAISE EXCEPTION 'Release created for inactive membership';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'An active membership is required for a new release'
    THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM public.issue19_enable_person_membership(
      'issue19-end-reviewer@example.invalid',v_person,'Former','Member',
      'Should not create a second member');
    RAISE EXCEPTION 'Ended member was re-enrolled with a second ID';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'This person already has a membership record; review its status'
    THEN RAISE; END IF;
  END;
  RAISE NOTICE 'End-membership checks passed; rolling back synthetic records.';
END $$;
ROLLBACK;
