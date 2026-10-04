-- Rollback-only checks for document-reviewer creation of
-- practitioner-attributed member agreements.
\set ON_ERROR_STOP on
BEGIN;
DO $$
DECLARE
  v_reviewer_person uuid;
  v_reviewer_member uuid;
  v_practitioner_person uuid;
  v_target_person uuid;
  v_target_member uuid;
  v_unassigned_practitioner uuid;
  v_assignment uuid;
  v_reviewer_agreement uuid;
  v_practitioner_agreement uuid;
  v_denied boolean := false;
  v_unassigned_denied boolean := false;
BEGIN
  INSERT INTO public.people(display_name)
    VALUES ('Issue 19 Agreement Reviewer')
    RETURNING person_id INTO v_reviewer_person;
  INSERT INTO public.person_app_accounts(person_id,email)
    VALUES (v_reviewer_person,'issue19-agreement-reviewer@example.invalid');
  INSERT INTO public.person_roles(person_id,role_key,assigned_by)
    VALUES (v_reviewer_person,'document_reviewer','issue19_verify');

  INSERT INTO public.members(person_id)
    VALUES (v_reviewer_person)
    RETURNING member_id INTO v_reviewer_member;

  INSERT INTO public.people(display_name)
    VALUES ('Issue 19 Agreement Practitioner')
    RETURNING person_id INTO v_practitioner_person;
  INSERT INTO public.person_app_accounts(person_id,email)
    VALUES (v_practitioner_person,'issue19-agreement-practitioner@example.invalid');
  INSERT INTO public.person_roles(person_id,role_key,assigned_by)
    VALUES (v_practitioner_person,'practitioner','issue19_verify');

  INSERT INTO public.people(display_name)
    VALUES ('Issue 19 Agreement Target')
    RETURNING person_id INTO v_target_person;
  INSERT INTO public.members(person_id)
    VALUES (v_target_person)
    RETURNING member_id INTO v_target_member;

  INSERT INTO public.people(display_name)
    VALUES ('Issue 19 Unassigned Practitioner')
    RETURNING person_id INTO v_unassigned_practitioner;
  INSERT INTO public.person_app_accounts(person_id,email)
    VALUES (v_unassigned_practitioner,'issue19-agreement-unassigned@example.invalid');
  INSERT INTO public.person_roles(person_id,role_key,assigned_by)
    VALUES (v_unassigned_practitioner,'practitioner','issue19_verify');

  SELECT public.issue19_assign_member_practitioner(
    'issue19-agreement-reviewer@example.invalid',
    v_target_person,
    v_practitioner_person,
    'Agreement test',
    'Assign practitioner for agreement verification')
  INTO v_assignment;

  IF NOT EXISTS (
      SELECT 1
      FROM public.member_practitioner_assignments
      WHERE member_practitioner_assignment_id=v_assignment
        AND member_id=v_target_member
        AND practitioner_person_id=v_practitioner_person
        AND status='active') THEN
    RAISE EXCEPTION 'Test practitioner assignment was not created';
  END IF;

  SELECT member_agreement_id
  INTO v_reviewer_agreement
  FROM public.issue19_create_member_agreement(
    'issue19-agreement-reviewer@example.invalid',
    v_target_member,
    v_practitioner_person,
    NULL,
    'paper',
    'pending_review',
    '[]'::jsonb,
    NULL);

  IF NOT EXISTS (
      SELECT 1
      FROM public.member_agreements
      WHERE member_agreement_id=v_reviewer_agreement
        AND member_id=v_target_member
        AND practitioner_person_id=v_practitioner_person
        AND signature_method='paper'
        AND status='pending_review') THEN
    RAISE EXCEPTION 'Document reviewer could not create practitioner-attributed agreement';
  END IF;

  BEGIN
    PERFORM public.issue19_create_member_agreement(
      'issue19-agreement-unassigned@example.invalid',
      v_target_member,
      v_practitioner_person,
      NULL,
      'paper',
      'pending_review',
      '[]'::jsonb,
      NULL);
  EXCEPTION WHEN OTHERS THEN
    v_denied := position(
      'Practitioner appointment or document reviewer permission required'
      IN SQLERRM) > 0;
  END;

  IF NOT v_denied THEN
    RAISE EXCEPTION 'Unprivileged actor created a member agreement';
  END IF;

  BEGIN
    PERFORM public.issue19_create_member_agreement(
      'issue19-agreement-reviewer@example.invalid',
      v_target_member,
      v_unassigned_practitioner,
      NULL,
      'paper',
      'pending_review',
      '[]'::jsonb,
      NULL);
  EXCEPTION WHEN OTHERS THEN
    v_unassigned_denied := position(
      'Selected practitioner is not available for this member'
      IN SQLERRM) > 0;
  END;

  IF NOT v_unassigned_denied THEN
    RAISE EXCEPTION 'Document reviewer attributed agreement to an unassigned practitioner';
  END IF;

  SELECT member_agreement_id
  INTO v_practitioner_agreement
  FROM public.issue19_create_member_agreement(
    'issue19-agreement-practitioner@example.invalid',
    v_target_member,
    v_practitioner_person,
    NULL,
    'paper',
    'pending_review',
    '[]'::jsonb,
    NULL);

  IF NOT EXISTS (
      SELECT 1
      FROM public.member_agreements
      WHERE member_agreement_id=v_practitioner_agreement
        AND member_id=v_target_member
        AND practitioner_person_id=v_practitioner_person) THEN
    RAISE EXCEPTION 'Assigned practitioner could not create the member agreement';
  END IF;

  IF NOT EXISTS (
      SELECT 1
      FROM public.audit_log
      WHERE entity_type='member_agreement'
        AND entity_id IN (
          v_reviewer_agreement::text,
          v_practitioner_agreement::text)
        AND action='member_agreement.practitioner_attributed'
        AND actor IN (
          'issue19-agreement-reviewer@example.invalid',
          'issue19-agreement-practitioner@example.invalid')) THEN
    RAISE EXCEPTION 'Agreement creation audit trail is incomplete';
  END IF;

  RAISE NOTICE 'Document-reviewer agreement-on-behalf checks passed; rolling back synthetic records.';
END $$;
ROLLBACK;
