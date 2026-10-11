-- Rollback-only behavioral checks. Run on a disposable/test database only.
\set ON_ERROR_STOP on
BEGIN;
DO $verify$
DECLARE
  v_reviewer uuid;
  v_other uuid;
  v_created public.agreement_types;
  v_bad_key text;
  v_actor text;
BEGIN
  INSERT INTO public.people(display_name) VALUES('Agreement Type Nonmember Reviewer')
    RETURNING person_id INTO v_reviewer;
  INSERT INTO public.person_app_accounts(person_id,email)
    VALUES(v_reviewer,'agreement-type-reviewer@example.invalid');
  INSERT INTO public.person_roles(person_id,role_key,assigned_by)
    VALUES(v_reviewer,'document_reviewer','verify');
  INSERT INTO public.people(display_name) VALUES('Agreement Type Unauthorized Actor')
    RETURNING person_id INTO v_other;
  INSERT INTO public.person_app_accounts(person_id,email)
    VALUES(v_other,'agreement-type-other@example.invalid');
  INSERT INTO public.person_roles(person_id,role_key,assigned_by)
    VALUES(v_other,'practitioner','verify'),(v_other,'donations_reviewer','verify');

  -- Bootstrap from an empty type table; rollback preserves the original rows.
  DELETE FROM public.agreement_types;
  v_created := public.create_agreement_type(' Agreement-Type-Reviewer@Example.Invalid ',
    '  Ceremony_Test  ', ' Ceremony Test ', 17, true, ' Optional description ');
  IF v_created.type_key <> 'ceremony_test' OR v_created.display_name <> 'Ceremony Test'
    OR v_created.sort_order <> 17 OR NOT v_created.active
    OR v_created.description <> 'Optional description' THEN
    RAISE EXCEPTION 'Agreement Type fields were not preserved/normalized';
  END IF;
  IF EXISTS(SELECT 1 FROM public.members WHERE person_id=v_reviewer) THEN
    RAISE EXCEPTION 'Agreement Type administration created membership';
  END IF;
  IF (SELECT count(*) FROM public.audit_log WHERE action='agreement_type.created'
    AND entity_id='ceremony_test' AND actor='agreement-type-reviewer@example.invalid'
    AND details->>'actor_person_id'=v_reviewer::text) <> 1 THEN
    RAISE EXCEPTION 'Agreement Type creation was not audited exactly once';
  END IF;
  BEGIN
    PERFORM public.create_agreement_type('agreement-type-reviewer@example.invalid',
      ' CEREMONY_TEST ', 'Duplicate');
    RAISE EXCEPTION 'Duplicate key accepted';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;
  IF (SELECT count(*) FROM public.audit_log WHERE action='agreement_type.created'
    AND entity_id='ceremony_test') <> 1 THEN
    RAISE EXCEPTION 'Rejected duplicate created an audit entry';
  END IF;
  FOREACH v_actor IN ARRAY ARRAY['agreement-type-other@example.invalid','unknown@example.invalid'] LOOP
    BEGIN
      PERFORM public.create_agreement_type(v_actor,'denied_test','Denied');
      RAISE EXCEPTION 'Unauthorized type creation accepted';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
  END LOOP;
  UPDATE public.person_app_accounts SET status='disabled' WHERE person_id=v_reviewer;
  BEGIN
    PERFORM public.create_agreement_type('agreement-type-reviewer@example.invalid','disabled_test','Denied');
    RAISE EXCEPTION 'Disabled account accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  UPDATE public.person_app_accounts SET status='active' WHERE person_id=v_reviewer;

  FOREACH v_bad_key IN ARRAY ARRAY['',NULL,'9invalid','has space','bad-key',repeat('a',65)] LOOP
    BEGIN
      PERFORM public.create_agreement_type('agreement-type-reviewer@example.invalid',v_bad_key,'Invalid');
      RAISE EXCEPTION 'Invalid key accepted';
    EXCEPTION WHEN invalid_parameter_value THEN NULL;
    END;
  END LOOP;
  BEGIN
    PERFORM public.create_agreement_type('agreement-type-reviewer@example.invalid','blank_name','  ');
    RAISE EXCEPTION 'Blank display name accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;
  BEGIN
    PERFORM public.create_agreement_type('agreement-type-reviewer@example.invalid','null_sort','Null',NULL);
    RAISE EXCEPTION 'Null sort order accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;
  BEGIN
    PERFORM public.create_agreement_type('agreement-type-reviewer@example.invalid','null_active','Null',100,NULL);
    RAISE EXCEPTION 'Null active state accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;
  v_created := public.create_agreement_type('agreement-type-reviewer@example.invalid','inactive_test','Inactive',-5,false);
  IF v_created.active OR v_created.sort_order <> -5 OR v_created.description IS NOT NULL THEN
    RAISE EXCEPTION 'Inactive type/default description were not preserved';
  END IF;
  IF (SELECT count(*) FROM public.agreement_types) <> 2 THEN
    RAISE EXCEPTION 'Rejected creations changed the type table';
  END IF;
END;
$verify$;

-- An audit failure must roll back the type insert, not leave an unaudited row.
CREATE FUNCTION pg_temp.fail_type_audit() RETURNS trigger LANGUAGE plpgsql AS $audit$
BEGIN
  IF NEW.action='agreement_type.created' AND NEW.entity_id='audit_failure_test' THEN
    RAISE EXCEPTION 'Synthetic audit failure' USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END;
$audit$;
CREATE TRIGGER verify_type_audit_failure BEFORE INSERT ON public.audit_log
  FOR EACH ROW EXECUTE FUNCTION pg_temp.fail_type_audit();
DO $verify$
BEGIN
  BEGIN
    PERFORM public.create_agreement_type('agreement-type-reviewer@example.invalid','audit_failure_test','Audit failure');
    RAISE EXCEPTION 'Audit failure accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  IF EXISTS(SELECT 1 FROM public.agreement_types WHERE type_key='audit_failure_test') THEN
    RAISE EXCEPTION 'Unaudited type survived failed creation';
  END IF;
END;
$verify$;
ROLLBACK;
