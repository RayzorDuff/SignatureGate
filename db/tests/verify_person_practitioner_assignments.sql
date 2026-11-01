-- Rollback-only checks for canonical person-based practitioner assignments.
\set ON_ERROR_STOP on
BEGIN;
DO $$
DECLARE
  v_reviewer_person uuid;
  v_outsider_person uuid;
  v_target_person uuid;
  v_target_member uuid;
  v_nonmember_practitioner uuid;
  v_member_practitioner uuid;
  v_member_practitioner_member uuid;
  v_nonmember_assignment uuid;
  v_member_assignment uuid;
  v_denied boolean := false;
  v_role_removal_denied boolean := false;
BEGIN
  INSERT INTO public.people(display_name)
    VALUES ('Issue 19 Assignment Reviewer')
    RETURNING person_id INTO v_reviewer_person;
  INSERT INTO public.person_app_accounts(person_id,email)
    VALUES (v_reviewer_person,'issue19-assignment-reviewer@example.invalid');
  INSERT INTO public.person_roles(person_id,role_key,assigned_by)
    VALUES (v_reviewer_person,'document_reviewer','issue19_verify');

  INSERT INTO public.people(display_name)
    VALUES ('Issue 19 Assignment Outsider')
    RETURNING person_id INTO v_outsider_person;
  INSERT INTO public.person_app_accounts(person_id,email)
    VALUES (v_outsider_person,'issue19-assignment-outsider@example.invalid');
  INSERT INTO public.person_roles(person_id,role_key,assigned_by)
    VALUES (v_outsider_person,'donations_reviewer','issue19_verify');

  INSERT INTO public.people(display_name)
    VALUES ('Issue 19 Assignment Target')
    RETURNING person_id INTO v_target_person;
  INSERT INTO public.members(person_id)
    VALUES (v_target_person) RETURNING member_id INTO v_target_member;

  INSERT INTO public.people(display_name)
    VALUES ('Issue 19 Nonmember Practitioner')
    RETURNING person_id INTO v_nonmember_practitioner;
  INSERT INTO public.person_app_accounts(person_id,email)
    VALUES (v_nonmember_practitioner,
      'issue19-nonmember-practitioner@example.invalid');
  INSERT INTO public.person_roles(person_id,role_key,assigned_by)
    VALUES (v_nonmember_practitioner,'practitioner','issue19_verify');

  INSERT INTO public.people(display_name)
    VALUES ('Issue 19 Member Practitioner')
    RETURNING person_id INTO v_member_practitioner;
  INSERT INTO public.members(person_id,is_facilitator)
    VALUES (v_member_practitioner,true)
    RETURNING member_id INTO v_member_practitioner_member;
  INSERT INTO public.person_roles(person_id,role_key,assigned_by)
    VALUES (v_member_practitioner,'practitioner','issue19_verify');

  IF NOT EXISTS (SELECT 1
      FROM public.issue19_available_member_practitioners(
        'issue19-assignment-reviewer@example.invalid',v_target_person)
      WHERE practitioner_person_id=v_nonmember_practitioner
        AND NOT has_active_membership)
    OR NOT EXISTS (SELECT 1
      FROM public.issue19_available_member_practitioners(
        'issue19-assignment-reviewer@example.invalid',v_target_person)
      WHERE practitioner_person_id=v_member_practitioner
        AND has_active_membership)
  THEN RAISE EXCEPTION 'Available practitioners did not preserve membership independence';
  END IF;

  BEGIN
    PERFORM public.issue19_assign_member_practitioner(
      'issue19-assignment-outsider@example.invalid',v_target_person,
      v_nonmember_practitioner,NULL,'Unauthorized test');
  EXCEPTION WHEN OTHERS THEN
    v_denied := position('Document reviewer permission required' in SQLERRM)>0;
  END;
  IF NOT v_denied THEN
    RAISE EXCEPTION 'Donations reviewer assigned a practitioner';
  END IF;

  SELECT public.issue19_assign_member_practitioner(
    'issue19-assignment-reviewer@example.invalid',v_target_person,
    v_nonmember_practitioner,'Nonmember assignment','Verification assignment')
  INTO v_nonmember_assignment;
  IF EXISTS (SELECT 1 FROM public.member_facilitators legacy
      JOIN public.members practitioner
        ON practitioner.member_id=legacy.facilitator_id
      WHERE legacy.member_id=v_target_member
        AND practitioner.person_id=v_nonmember_practitioner) THEN
    RAISE EXCEPTION 'Nonmember practitioner unexpectedly required a legacy member row';
  END IF;
  IF NOT EXISTS (SELECT 1
      FROM public.issue19_person_member_operations_state(
        'issue19-nonmember-practitioner@example.invalid',v_target_person)
      WHERE member_id=v_target_member AND can_view AND NOT can_manage)
    OR NOT EXISTS (SELECT 1
      FROM public.issue19_person_practitioner_assignments(
        'issue19-nonmember-practitioner@example.invalid',v_target_person)
      WHERE member_practitioner_assignment_id=v_nonmember_assignment
        AND practitioner_person_id=v_nonmember_practitioner
        AND assignment_status='active')
    OR NOT EXISTS (SELECT 1 FROM public.issue19_directory_entries(
        'issue19-nonmember-practitioner@example.invalid')
      WHERE party_kind='individual' AND party_id=v_target_person
        AND member_id=v_target_member AND can_view_membership)
  THEN RAISE EXCEPTION 'Nonmember practitioner did not receive assigned member scope';
  END IF;

  BEGIN
    DELETE FROM public.person_roles
    WHERE person_id=v_nonmember_practitioner AND role_key='practitioner';
  EXCEPTION WHEN OTHERS THEN
    v_role_removal_denied := position(
      'End active practitioner assignments' in SQLERRM)>0;
  END;
  IF NOT v_role_removal_denied THEN
    RAISE EXCEPTION 'Active assignment did not guard practitioner appointment removal';
  END IF;

  SELECT public.issue19_assign_member_practitioner(
    'issue19-assignment-reviewer@example.invalid',v_target_person,
    v_member_practitioner,'Legacy projection','Verification assignment')
  INTO v_member_assignment;
  IF NOT EXISTS (SELECT 1 FROM public.member_facilitators
      WHERE member_id=v_target_member
        AND facilitator_id=v_member_practitioner_member
        AND status='active') THEN
    RAISE EXCEPTION 'Member practitioner legacy projection was not created';
  END IF;

  PERFORM public.issue19_end_member_practitioner(
    'issue19-assignment-reviewer@example.invalid',v_target_person,
    v_member_assignment,'Verification end');
  IF EXISTS (SELECT 1 FROM public.member_facilitators
      WHERE member_id=v_target_member
        AND facilitator_id=v_member_practitioner_member
        AND status='active')
    OR NOT EXISTS (SELECT 1 FROM public.member_practitioner_assignments
      WHERE member_practitioner_assignment_id=v_member_assignment
        AND status='inactive' AND end_reason='Verification end') THEN
    RAISE EXCEPTION 'Ending the canonical assignment did not retain synchronized history';
  END IF;

  PERFORM public.issue19_end_member_practitioner(
    'issue19-assignment-reviewer@example.invalid',v_target_person,
    v_nonmember_assignment,'Verification end');
  IF EXISTS (SELECT 1
      FROM public.issue19_person_member_operations_state(
        'issue19-nonmember-practitioner@example.invalid',v_target_person)
      WHERE can_view) THEN
    RAISE EXCEPTION 'Ended nonmember practitioner retained member access';
  END IF;
  DELETE FROM public.person_roles
  WHERE person_id=v_nonmember_practitioner AND role_key='practitioner';
  IF EXISTS (SELECT 1 FROM public.person_roles
      WHERE person_id=v_nonmember_practitioner AND role_key='practitioner') THEN
    RAISE EXCEPTION 'Ended assignment still blocked practitioner appointment removal';
  END IF;

  IF (SELECT count(*) FROM public.audit_log
      WHERE entity_type='member_practitioner_assignment'
        AND entity_id IN (v_nonmember_assignment::text,v_member_assignment::text)
        AND action IN ('member_practitioner.assigned','member_practitioner.ended'))<>4
  THEN RAISE EXCEPTION 'Practitioner assignment audit trail is incomplete';
  END IF;
  IF EXISTS (SELECT 1 FROM public.contributors
      WHERE person_id IN (v_nonmember_practitioner,v_member_practitioner)) THEN
    RAISE EXCEPTION 'Practitioner assignment created contributor capacity';
  END IF;

  RAISE NOTICE 'Person-based practitioner assignment checks passed; rolling back synthetic records.';
END $$;
ROLLBACK;
