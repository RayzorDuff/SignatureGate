-- Rollback-only checks for Issue #20 deployment terminology.
\set ON_ERROR_STOP on
BEGIN;
DO $$
DECLARE
  v_manager_person uuid;
  v_outsider_person uuid;
  v_practitioner_person uuid;
  v_denied boolean := false;
  v_unknown_denied boolean := false;
BEGIN
  IF NOT EXISTS (
      SELECT 1 FROM public.issue20_organization_terminology()
      WHERE concept_key='practitioner'
        AND singular_label='Spiritual Practitioner'
        AND plural_label='Spiritual Practitioners' AND is_active)
    OR NOT EXISTS (
      SELECT 1 FROM public.issue20_organization_terminology()
      WHERE concept_key='facilitator' AND singular_label='Facilitator'
        AND NOT is_active)
  THEN
    RAISE EXCEPTION 'Rooted Psyche practitioner/facilitator defaults are incorrect';
  END IF;

  INSERT INTO public.people(display_name)
    VALUES ('Issue 20 Terminology Manager')
    RETURNING person_id INTO v_manager_person;
  INSERT INTO public.person_app_accounts(person_id,email)
    VALUES (v_manager_person,'issue20-terminology-manager@example.invalid');
  INSERT INTO public.person_roles(person_id,role_key,assigned_by)
    VALUES (v_manager_person,'directory_manager','issue20_verify');

  INSERT INTO public.people(display_name)
    VALUES ('Issue 20 Terminology Outsider')
    RETURNING person_id INTO v_outsider_person;
  INSERT INTO public.person_app_accounts(person_id,email)
    VALUES (v_outsider_person,'issue20-terminology-outsider@example.invalid');

  INSERT INTO public.people(display_name)
    VALUES ('Issue 20 Stable Practitioner')
    RETURNING person_id INTO v_practitioner_person;
  INSERT INTO public.person_roles(person_id,role_key,assigned_by)
    VALUES (v_practitioner_person,'practitioner','issue20_verify');

  BEGIN
    PERFORM public.issue20_set_organization_terminology(
      'issue20-terminology-outsider@example.invalid','practitioner',
      'Facilitator','Facilitators',NULL,true,'Unauthorized test');
  EXCEPTION WHEN OTHERS THEN
    v_denied := position('Directory manager permission required' in SQLERRM)>0;
  END;
  IF NOT v_denied THEN
    RAISE EXCEPTION 'Non-manager changed organization terminology';
  END IF;

  PERFORM public.issue20_set_organization_terminology(
    'issue20-terminology-manager@example.invalid','practitioner',
    'Facilitator','Facilitators','Guide',true,
    'Alternate deployment terminology test');
  IF NOT EXISTS (
      SELECT 1 FROM public.issue20_organization_terminology()
      WHERE concept_key='practitioner' AND singular_label='Facilitator'
        AND plural_label='Facilitators' AND short_label='Guide')
    OR NOT EXISTS (
      SELECT 1 FROM public.person_roles
      WHERE person_id=v_practitioner_person AND role_key='practitioner')
  THEN
    RAISE EXCEPTION 'Display terminology changed stable practitioner identity';
  END IF;

  -- A future regulated facilitator can coexist with the current practitioner
  -- concept. Enabling its terminology does not create or grant that role.
  PERFORM public.issue20_set_organization_terminology(
    'issue20-terminology-manager@example.invalid','facilitator',
    'DORA Facilitator','DORA Facilitators','Facilitator',true,
    'Future distinct-role coexistence test');
  IF (SELECT count(*) FROM public.issue20_organization_terminology()
      WHERE concept_key IN ('practitioner','facilitator') AND is_active)<>2
    OR (SELECT count(*) FROM public.terminology_concepts
      WHERE concept_key IN ('practitioner','facilitator'))<>2
  THEN
    RAISE EXCEPTION 'Practitioner and facilitator concepts cannot coexist';
  END IF;
  IF EXISTS (SELECT 1 FROM public.person_roles
      WHERE person_id=v_practitioner_person AND role_key='facilitator') THEN
    RAISE EXCEPTION 'Enabling terminology implicitly granted a facilitator role';
  END IF;

  IF public.issue20_set_organization_terminology(
      'issue20-terminology-manager@example.invalid','facilitator',
      'DORA Facilitator','DORA Facilitators','Facilitator',true,
      'No-op test') THEN
    RAISE EXCEPTION 'Unchanged terminology was reported as changed';
  END IF;

  BEGIN
    PERFORM public.issue20_set_organization_terminology(
      'issue20-terminology-manager@example.invalid','invented_role',
      'Invented','Invented',NULL,true,'Unknown concept test');
  EXCEPTION WHEN OTHERS THEN
    v_unknown_denied := position('Unknown terminology concept' in SQLERRM)>0;
  END;
  IF NOT v_unknown_denied THEN
    RAISE EXCEPTION 'Operator created an unregistered domain concept';
  END IF;

  IF (SELECT count(*) FROM public.audit_log
      WHERE actor='issue20-terminology-manager@example.invalid'
        AND action='organization_terminology.changed'
        AND entity_id IN ('practitioner','facilitator'))<>2
  THEN
    RAISE EXCEPTION 'Terminology audit trail is incomplete';
  END IF;

  RAISE NOTICE 'Organization terminology checks passed; rolling back synthetic changes.';
END $$;
ROLLBACK;
