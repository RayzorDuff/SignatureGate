-- Rollback-only checks for canonical practitioner release operations.
\set ON_ERROR_STOP on
BEGIN;
DO $$
DECLARE
  v_reviewer uuid;
  v_outsider uuid;
  v_practitioner uuid;
  v_member_practitioner uuid;
  v_member_practitioner_member uuid;
  v_target uuid;
  v_target_member uuid;
  v_assignment uuid;
  v_access uuid;
  v_release uuid;
  v_denied boolean := false;
  v_location_denied boolean := false;
BEGIN
  INSERT INTO public.people(display_name)
    VALUES ('Issue 19 Release Reviewer') RETURNING person_id INTO v_reviewer;
  INSERT INTO public.person_app_accounts(person_id,email)
    VALUES (v_reviewer,'issue19-release-reviewer@example.invalid');
  INSERT INTO public.person_roles(person_id,role_key,assigned_by) VALUES
    (v_reviewer,'practitioner','issue19_verify'),
    (v_reviewer,'document_reviewer','issue19_verify');

  INSERT INTO public.people(display_name)
    VALUES ('Issue 19 Release Outsider') RETURNING person_id INTO v_outsider;
  INSERT INTO public.person_app_accounts(person_id,email)
    VALUES (v_outsider,'issue19-release-outsider@example.invalid');

  INSERT INTO public.people(display_name)
    VALUES ('Issue 19 Nonmember Practitioner')
    RETURNING person_id INTO v_practitioner;
  INSERT INTO public.person_roles(person_id,role_key,assigned_by)
    VALUES (v_practitioner,'practitioner','issue19_verify');

  INSERT INTO public.people(display_name)
    VALUES ('Issue 19 Release Target') RETURNING person_id INTO v_target;
  INSERT INTO public.members(person_id)
    VALUES (v_target) RETURNING member_id INTO v_target_member;
  INSERT INTO public.member_practitioner_assignments(
    member_id,practitioner_person_id,assigned_by_person_id)
  VALUES (v_target_member,v_practitioner,v_reviewer)
  RETURNING member_practitioner_assignment_id INTO v_assignment;

  SELECT public.issue19_set_practitioner_storage_location(
    'issue19-release-reviewer@example.invalid',v_practitioner,
    'Issue 19 Test Vault',true,'Nonmember access','Verification grant')
  INTO v_access;
  IF EXISTS (SELECT 1 FROM public.facilitator_storage_location_access
      WHERE facilitator_storage_location_access_id=v_access) THEN
    RAISE EXCEPTION 'Nonmember practitioner unexpectedly required a legacy storage row';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.issue19_release_storage_locations(
      'issue19-release-reviewer@example.invalid',v_target_member,
      v_practitioner) WHERE storage_location_name='Issue 19 Test Vault') THEN
    RAISE EXCEPTION 'Reviewer cannot see canonical practitioner storage access';
  END IF;

  BEGIN
    PERFORM * FROM public.issue19_record_sacrament_release(
      'issue19-release-outsider@example.invalid',v_target_member,
      v_practitioner,NULL,'ISSUE19-OUTSIDER','Denied',1,'g',1,
      'test','Issue 19 Test Vault','Denied','Denied');
  EXCEPTION WHEN OTHERS THEN
    v_denied := position('Practitioner appointment required' in SQLERRM)>0;
  END;
  IF NOT v_denied THEN RAISE EXCEPTION 'Non-practitioner recorded a release'; END IF;

  SELECT result.release_id INTO v_release
  FROM public.issue19_record_sacrament_release(
    'issue19-release-reviewer@example.invalid',v_target_member,
    v_practitioner,NULL,'ISSUE19-RELEASE','Verification sacrament',1,'g',1,
    'test','Issue 19 Test Vault','Verification','Reviewer override') result;
  IF NOT EXISTS (SELECT 1 FROM public.releases release
      WHERE release.release_id=v_release
        AND release.practitioner_person_id=v_practitioner
        AND release.facilitator_id IS NULL
        AND release.release_type='sacrament_release') THEN
    RAISE EXCEPTION 'Canonical nonmember release attribution failed';
  END IF;

  BEGIN
    PERFORM * FROM public.issue19_record_sacrament_release(
      'issue19-release-reviewer@example.invalid',v_target_member,
      v_practitioner,NULL,'ISSUE19-LOCATION','Denied location',1,'g',1,
      'test','Different Vault','Denied','Reviewer override');
  EXCEPTION WHEN OTHERS THEN
    v_location_denied := position('does not have access' in SQLERRM)>0;
  END;
  IF NOT v_location_denied THEN
    RAISE EXCEPTION 'Release used an unauthorized storage location';
  END IF;

  INSERT INTO public.people(display_name)
    VALUES ('Issue 19 Member Practitioner')
    RETURNING person_id INTO v_member_practitioner;
  INSERT INTO public.members(person_id,is_facilitator)
    VALUES (v_member_practitioner,true)
    RETURNING member_id INTO v_member_practitioner_member;
  INSERT INTO public.person_roles(person_id,role_key,assigned_by)
    VALUES (v_member_practitioner,'practitioner','issue19_verify');
  INSERT INTO public.facilitator_storage_location_access(
    facilitator_id,storage_location_name,assigned_by_member_id)
  VALUES (v_member_practitioner_member,'Legacy Test Vault',
    v_member_practitioner_member);
  IF NOT EXISTS (SELECT 1
      FROM public.practitioner_storage_location_access
      WHERE practitioner_person_id=v_member_practitioner
        AND storage_location_name='Legacy Test Vault' AND status='active') THEN
    RAISE EXCEPTION 'Legacy storage write did not synchronize to person access';
  END IF;

  BEGIN
    DELETE FROM public.person_roles
    WHERE person_id=v_practitioner AND role_key='practitioner';
  EXCEPTION WHEN OTHERS THEN
    IF position('storage access' in SQLERRM)=0 THEN RAISE; END IF;
  END;
  IF NOT EXISTS (SELECT 1 FROM public.person_roles
      WHERE person_id=v_practitioner AND role_key='practitioner') THEN
    RAISE EXCEPTION 'Active operational access did not guard role removal';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.audit_log
      WHERE action='release.issued' AND entity_id=v_release::text
        AND details->>'practitioner_person_id'=v_practitioner::text)
    OR NOT EXISTS (SELECT 1 FROM public.audit_log
      WHERE action='practitioner_storage_location.assigned'
        AND entity_id=v_access::text) THEN
    RAISE EXCEPTION 'Canonical release/storage audit trail is incomplete';
  END IF;

  RAISE NOTICE 'Canonical practitioner release checks passed; rolling back synthetic records.';
END $$;
ROLLBACK;
