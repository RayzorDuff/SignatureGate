-- Rollback-only checks for canonical practitioner agreement attribution.
\set ON_ERROR_STOP on
BEGIN;
DO $$
DECLARE
  v_reviewer uuid;
  v_practitioner uuid;
  v_member_practitioner uuid;
  v_member_practitioner_member uuid;
  v_target uuid;
  v_target_member uuid;
  v_template uuid;
  v_agreement uuid;
  v_legacy_agreement uuid;
  v_denied boolean := false;
BEGIN
  INSERT INTO public.people(display_name)
    VALUES ('Issue 19 Agreement Reviewer') RETURNING person_id INTO v_reviewer;
  INSERT INTO public.person_app_accounts(person_id,email)
    VALUES (v_reviewer,'issue19-agreement-reviewer@example.invalid');
  INSERT INTO public.person_roles(person_id,role_key,assigned_by) VALUES
    (v_reviewer,'practitioner','issue19_verify'),
    (v_reviewer,'document_reviewer','issue19_verify');

  INSERT INTO public.people(display_name)
    VALUES ('Issue 19 Nonmember Agreement Practitioner')
    RETURNING person_id INTO v_practitioner;
  INSERT INTO public.person_roles(person_id,role_key,assigned_by)
    VALUES (v_practitioner,'practitioner','issue19_verify');

  INSERT INTO public.people(display_name)
    VALUES ('Issue 19 Agreement Target') RETURNING person_id INTO v_target;
  INSERT INTO public.members(person_id)
    VALUES (v_target) RETURNING member_id INTO v_target_member;
  INSERT INTO public.member_practitioner_assignments(
    member_id,practitioner_person_id,assigned_by_person_id)
  VALUES (v_target_member,v_practitioner,v_reviewer);

  INSERT INTO public.agreement_templates(name,version,required_for,active)
  VALUES ('Issue 19 Agreement Signer Test','1',ARRAY['sacrament_release'],true)
  RETURNING agreement_template_id INTO v_template;

  SELECT result.member_agreement_id INTO v_agreement
  FROM public.issue19_create_member_agreement(
    'issue19-agreement-reviewer@example.invalid',v_target_member,
    v_practitioner,v_template,'documenso','pending_email_send','[]'::jsonb,
    NULL) result;
  IF NOT EXISTS (SELECT 1 FROM public.member_agreements agreement
      WHERE agreement.member_agreement_id=v_agreement
        AND agreement.practitioner_person_id=v_practitioner
        AND agreement.facilitator_id IS NULL) THEN
    RAISE EXCEPTION 'Nonmember practitioner agreement attribution failed';
  END IF;

  INSERT INTO public.people(display_name)
    VALUES ('Issue 19 Member Agreement Practitioner')
    RETURNING person_id INTO v_member_practitioner;
  INSERT INTO public.members(person_id,is_facilitator)
    VALUES (v_member_practitioner,true)
    RETURNING member_id INTO v_member_practitioner_member;
  INSERT INTO public.person_roles(person_id,role_key,assigned_by)
    VALUES (v_member_practitioner,'practitioner','issue19_verify');
  INSERT INTO public.member_agreements(
    member_id,facilitator_id,agreement_template_id,
    signature_method,status,evidence)
  VALUES (v_target_member,v_member_practitioner_member,v_template,
    'paper','pending_review','[]'::jsonb)
  RETURNING member_agreement_id INTO v_legacy_agreement;
  IF NOT EXISTS (SELECT 1 FROM public.member_agreements
      WHERE member_agreement_id=v_legacy_agreement
        AND practitioner_person_id=v_member_practitioner) THEN
    RAISE EXCEPTION 'Legacy agreement write did not synchronize to person identity';
  END IF;

  BEGIN
    PERFORM * FROM public.issue19_create_member_agreement(
      'issue19-agreement-reviewer@example.invalid',v_target_member,
      v_member_practitioner,v_template,'documenso','pending_email_send',
      '[]'::jsonb,NULL);
  EXCEPTION WHEN OTHERS THEN
    v_denied := position('not available' in SQLERRM)>0;
  END;
  IF NOT v_denied THEN
    RAISE EXCEPTION 'Unassigned practitioner created a member agreement';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.audit_log
      WHERE action='member_agreement.practitioner_attributed'
        AND entity_id=v_agreement::text
        AND details->>'practitioner_person_id'=v_practitioner::text) THEN
    RAISE EXCEPTION 'Canonical agreement attribution audit is missing';
  END IF;

  RAISE NOTICE 'Canonical practitioner agreement checks passed; rolling back synthetic records.';
END $$;
ROLLBACK;
