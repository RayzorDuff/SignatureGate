-- Rollback-only checks for Individual Profile membership-operation reads.
\set ON_ERROR_STOP on
BEGIN;
DO $$
DECLARE
  v_reviewer_person uuid;
  v_practitioner_person uuid;
  v_outsider_person uuid;
  v_target_person uuid;
  v_practitioner_member uuid;
  v_target_member uuid;
  v_assignment uuid;
BEGIN
  INSERT INTO public.people(display_name) VALUES ('Issue 19 Agreement Reviewer')
    RETURNING person_id INTO v_reviewer_person;
  INSERT INTO public.person_app_accounts(person_id,email)
    VALUES (v_reviewer_person,'issue19-operations-reviewer@example.invalid');
  INSERT INTO public.person_roles(person_id,role_key,assigned_by)
    VALUES (v_reviewer_person,'document_reviewer','issue19_verify');

  INSERT INTO public.people(display_name) VALUES ('Issue 19 Assigned Practitioner')
    RETURNING person_id INTO v_practitioner_person;
  INSERT INTO public.members(person_id,email,is_facilitator)
    VALUES (v_practitioner_person,'issue19-assigned-practitioner@example.invalid',true)
    RETURNING member_id INTO v_practitioner_member;
  INSERT INTO public.person_app_accounts(person_id,email)
    VALUES (v_practitioner_person,'issue19-assigned-practitioner@example.invalid');

  INSERT INTO public.people(display_name) VALUES ('Issue 19 Operations Outsider')
    RETURNING person_id INTO v_outsider_person;
  INSERT INTO public.person_app_accounts(person_id,email)
    VALUES (v_outsider_person,'issue19-operations-outsider@example.invalid');
  INSERT INTO public.person_roles(person_id,role_key,assigned_by)
    VALUES (v_outsider_person,'donations_reviewer','issue19_verify');

  INSERT INTO public.people(display_name) VALUES ('Issue 19 Agreement Target')
    RETURNING person_id INTO v_target_person;
  INSERT INTO public.members(person_id) VALUES (v_target_person)
    RETURNING member_id INTO v_target_member;
  INSERT INTO public.member_agreements(
    member_id,facilitator_id,signature_method,status,review_notes)
  VALUES (v_target_member,v_practitioner_member,'paper','pending_review',
    'Synthetic agreement for rollback-only verification');
  INSERT INTO public.member_facilitators(
    member_id,facilitator_id,assigned_by_member_id,status,notes)
  VALUES (v_target_member,v_practitioner_member,v_practitioner_member,
    'active','Synthetic assignment for rollback-only verification')
  RETURNING member_facilitator_id INTO v_assignment;

  IF NOT EXISTS (SELECT 1
      FROM public.issue19_person_member_operations_state(
        'issue19-operations-reviewer@example.invalid',v_target_person)
      WHERE member_id=v_target_member AND can_view AND can_manage)
    OR NOT EXISTS (SELECT 1
      FROM public.issue19_person_member_agreements(
        'issue19-operations-reviewer@example.invalid',v_target_person)
      WHERE member_id=v_target_member AND agreement_status='pending_review')
  THEN RAISE EXCEPTION 'Document reviewer cannot read member operations'; END IF;

  IF NOT EXISTS (SELECT 1
      FROM public.issue19_person_member_operations_state(
        'issue19-assigned-practitioner@example.invalid',v_target_person)
      WHERE member_id=v_target_member AND can_view AND NOT can_manage)
    OR NOT EXISTS (SELECT 1
      FROM public.issue19_person_practitioner_assignments(
        'issue19-assigned-practitioner@example.invalid',v_target_person)
      WHERE member_facilitator_id=v_assignment
        AND practitioner_person_id=v_practitioner_person)
  THEN RAISE EXCEPTION 'Assigned practitioner cannot read member operations'; END IF;

  IF EXISTS (SELECT 1
      FROM public.issue19_person_member_agreements(
        'issue19-operations-outsider@example.invalid',v_target_person))
    OR EXISTS (SELECT 1
      FROM public.issue19_person_practitioner_assignments(
        'issue19-operations-outsider@example.invalid',v_target_person))
  THEN RAISE EXCEPTION 'Donations-only reviewer crossed into member operations'; END IF;

  UPDATE public.member_facilitators SET status='inactive'
  WHERE member_facilitator_id=v_assignment;
  IF EXISTS (SELECT 1
      FROM public.issue19_person_member_agreements(
        'issue19-assigned-practitioner@example.invalid',v_target_person))
  THEN RAISE EXCEPTION 'Inactive practitioner assignment retained access'; END IF;

  UPDATE public.members SET status='inactive' WHERE member_id=v_target_member;
  IF NOT EXISTS (SELECT 1
      FROM public.issue19_person_member_agreements(
        'issue19-operations-reviewer@example.invalid',v_target_person)
      WHERE membership_status='inactive')
  THEN RAISE EXCEPTION 'Ended membership agreement history disappeared'; END IF;

  RAISE NOTICE 'Individual Profile member-operation read checks passed; rolling back synthetic records.';
END $$;
ROLLBACK;
