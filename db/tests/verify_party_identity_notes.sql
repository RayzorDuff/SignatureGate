-- Synthetic fixtures only; no operational notes or identifying values are printed.
\set ON_ERROR_STOP on
BEGIN;
DO $verify$
DECLARE
  v_actor uuid;
  v_target uuid;
  v_existing uuid;
  v_cleared uuid;
  v_blank uuid;
  v_org uuid;
  v_member uuid;
  v_second uuid;
  v_already uuid;
  v_clear_member uuid;
  v_blank_member uuid;
  v_email text := 'notes-verify-' || public.uuid_generate_v4()::text || '@example.invalid';
  v_practitioner text := 'notes-practitioner-' || public.uuid_generate_v4()::text || '@example.invalid';
  v_practitioner_id uuid;
  v_original text;
  v_before integer;
  v_count integer;
BEGIN
  IF to_regprocedure('public.backfill_member_identity_notes()') IS NULL THEN
    RAISE EXCEPTION 'Historical note provenance API missing';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc p, LATERAL aclexplode(COALESCE(p.proacl,acldefault('f',p.proowner))) acl
    WHERE p.oid='public.backfill_member_identity_notes()'::regprocedure AND acl.grantee=0 AND acl.privilege_type='EXECUTE') THEN
    RAISE EXCEPTION 'Historical import is executable by PUBLIC';
  END IF;
  INSERT INTO public.people(display_name) VALUES ('Synthetic notes actor') RETURNING person_id INTO v_actor;
  INSERT INTO public.people(display_name) VALUES ('Synthetic notes practitioner') RETURNING person_id INTO v_practitioner_id;
  INSERT INTO public.person_app_accounts(person_id,email) VALUES(v_actor,v_email),(v_practitioner_id,v_practitioner);
  INSERT INTO public.person_roles(person_id,role_key,assigned_by) VALUES
    (v_actor,'directory_manager','synthetic-test'),(v_practitioner_id,'practitioner','synthetic-test');
  INSERT INTO public.people(display_name,notes) VALUES ('Synthetic note target','Existing identity text') RETURNING person_id INTO v_target;
  INSERT INTO public.people(display_name) VALUES ('Synthetic previously imported target') RETURNING person_id INTO v_existing;
  INSERT INTO public.people(display_name) VALUES ('Synthetic cleared target') RETURNING person_id INTO v_cleared;
  INSERT INTO public.people(display_name) VALUES ('Synthetic blank source target') RETURNING person_id INTO v_blank;
  INSERT INTO public.organizations(organization_name) VALUES ('Synthetic notes organization') RETURNING organization_id INTO v_org;
  INSERT INTO public.contributors(contributor_type,organization_id,source) VALUES ('organization',v_org,'synthetic-test');
  INSERT INTO public.members(person_id,notes) VALUES(v_target,' Historical text ') RETURNING member_id INTO v_member;
  INSERT INTO public.members(person_id,notes,status) VALUES(v_target,'Second historical text','inactive') RETURNING member_id INTO v_second;
  INSERT INTO public.members(person_id,notes) VALUES(v_existing,'Already imported') RETURNING member_id INTO v_already;
  UPDATE public.people SET notes='Member '||v_already::text||': Already imported' WHERE person_id=v_existing;
  INSERT INTO public.members(person_id,notes) VALUES(v_cleared,'Must remain in source only') RETURNING member_id INTO v_clear_member;
  INSERT INTO public.members(person_id,notes) VALUES(v_blank,'  ') RETURNING member_id INTO v_blank_member;
  PERFORM public.issue19_set_party_notes(v_email,'individual',v_cleared,'Temporary canonical text','Synthetic add');
  PERFORM public.issue19_set_party_notes(v_email,'individual',v_cleared,NULL,'Synthetic clear');

  PERFORM public.backfill_member_identity_notes();
  SELECT notes INTO v_original FROM public.people WHERE person_id=v_target;
  IF position('Existing identity text' IN v_original)<>1
    OR position('Member '||v_member::text||': Historical text' IN v_original)=0
    OR position('Member '||v_second::text||': Second historical text' IN v_original)=0 THEN
    RAISE EXCEPTION 'Historical import lost existing or multiple-membership notes';
  END IF;
  IF (SELECT notes FROM public.people WHERE person_id=v_existing) IS DISTINCT FROM 'Member '||v_already::text||': Already imported'
    OR (SELECT outcome FROM public.member_identity_note_backfill WHERE member_id=v_already)<>'already_present' THEN
    RAISE EXCEPTION 'Earlier aggregate import was duplicated';
  END IF;
  IF (SELECT notes FROM public.people WHERE person_id=v_cleared) IS NOT NULL
    OR (SELECT outcome FROM public.member_identity_note_backfill WHERE member_id=v_clear_member)<>'preserved_edit'
    OR (SELECT outcome FROM public.member_identity_note_backfill WHERE member_id=v_blank_member)<>'blank' THEN
    RAISE EXCEPTION 'Edited/cleared identity or blank source was not preserved';
  END IF;
  IF (SELECT notes FROM public.members WHERE member_id=v_member)<>' Historical text ' THEN
    RAISE EXCEPTION 'Historical source was modified';
  END IF;
  UPDATE public.members SET notes='Changed historical text' WHERE member_id=v_member;
  UPDATE public.members SET notes='Late legacy write' WHERE member_id=v_blank_member;
  v_count := public.backfill_member_identity_notes();
  IF v_count<>0 OR (SELECT notes FROM public.people WHERE person_id=v_target) IS DISTINCT FROM v_original
    OR (SELECT notes FROM public.people WHERE person_id=v_blank) IS NOT NULL THEN
    RAISE EXCEPTION 'Rerun copied changed or previously blank historical sources';
  END IF;

  -- Nonmember canonical roles can edit; practitioner-only and unknown accounts cannot.
  SELECT count(*) INTO v_before FROM public.audit_log WHERE entity_id=v_target::text AND action='party.notes_updated';
  PERFORM public.issue19_set_party_notes(v_email,'individual',v_target,' Replacement text ','Synthetic edit');
  PERFORM public.issue19_set_party_notes(v_email,'individual',v_target,'Replacement text','Synthetic no-op');
  IF (SELECT notes FROM public.issue19_party_notes(v_email,'individual',v_target))<>'Replacement text'
    OR (SELECT count(*) FROM public.audit_log WHERE entity_id=v_target::text AND action='party.notes_updated')<>v_before+1 THEN
    RAISE EXCEPTION 'Note normalization, read or no-op audit behavior failed';
  END IF;
  PERFORM public.issue19_set_party_notes(v_email,'organization',v_org,'Organization text','Synthetic add');
  IF (SELECT notes FROM public.issue19_party_notes(v_email,'organization',v_org))<>'Organization text' THEN
    RAISE EXCEPTION 'Organization notes unavailable';
  END IF;
  BEGIN
    PERFORM public.issue19_set_party_notes(v_email,'individual',v_target,'Denied',' ');
    RAISE EXCEPTION 'Blank reason accepted';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM<>'A reason for changing notes is required' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM public.issue19_set_party_notes(v_practitioner,'individual',v_target,'Denied','Synthetic denial');
    RAISE EXCEPTION 'Practitioner-only note edit accepted';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM<>'Not authorized to edit identity notes' THEN RAISE; END IF;
  END;
  IF EXISTS(SELECT 1 FROM public.issue19_party_notes(v_practitioner,'individual',v_target)) THEN
    RAISE EXCEPTION 'Practitioner-only account read private notes';
  END IF;
  BEGIN
    PERFORM public.issue19_set_party_notes('unknown@example.invalid','organization',v_org,'Denied','Synthetic denial');
    RAISE EXCEPTION 'Unknown account edit accepted';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM<>'Not authorized to edit identity notes' THEN RAISE; END IF;
  END;
  -- Verify each reviewer separately, independent of membership and other roles.
  DELETE FROM public.person_roles WHERE person_id=v_actor;
  INSERT INTO public.person_roles(person_id,role_key,assigned_by) VALUES(v_actor,'document_reviewer','synthetic-test');
  PERFORM public.issue19_set_party_notes(v_email,'individual',v_target,NULL,'Synthetic clear');
  DELETE FROM public.person_roles WHERE person_id=v_actor;
  INSERT INTO public.person_roles(person_id,role_key,assigned_by) VALUES(v_actor,'donations_reviewer','synthetic-test');
  PERFORM public.issue19_set_party_notes(v_email,'organization',v_org,' ','Synthetic clear');
  PERFORM public.backfill_member_identity_notes();
  IF (SELECT notes FROM public.people WHERE person_id=v_target) IS NOT NULL
    OR (SELECT notes FROM public.organizations WHERE organization_id=v_org) IS NOT NULL THEN
    RAISE EXCEPTION 'Clear was lost after rerun';
  END IF;
  IF EXISTS(SELECT 1 FROM public.members WHERE person_id=v_actor) THEN
    RAISE EXCEPTION 'Reviewer test unexpectedly depended on membership';
  END IF;
  UPDATE public.person_app_accounts SET status='disabled' WHERE person_id=v_actor;
  IF EXISTS(SELECT 1 FROM public.issue19_party_notes(v_email,'organization',v_org)) THEN
    RAISE EXCEPTION 'Disabled account read private notes';
  END IF;
  RAISE NOTICE 'Identity notes behavior, canonical permissions and historical rerun checks passed; fixtures will roll back.';
END;
$verify$;

CREATE FUNCTION pg_temp.reject_note_audit() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.action='party.notes_updated' AND NEW.details->>'reason'='Synthetic audit failure' THEN
    RAISE EXCEPTION 'Synthetic audit failure' USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER verify_notes_audit_failure BEFORE INSERT ON public.audit_log
  FOR EACH ROW EXECUTE FUNCTION pg_temp.reject_note_audit();
DO $verify$
DECLARE v_actor uuid; v_target uuid; v_email text := 'notes-audit-'||public.uuid_generate_v4()::text||'@example.invalid';
BEGIN
  INSERT INTO public.people(display_name) VALUES('Synthetic audit actor') RETURNING person_id INTO v_actor;
  INSERT INTO public.people(display_name,notes) VALUES('Synthetic audit target','Original') RETURNING person_id INTO v_target;
  INSERT INTO public.person_app_accounts(person_id,email) VALUES(v_actor,v_email);
  INSERT INTO public.person_roles(person_id,role_key,assigned_by) VALUES(v_actor,'directory_manager','synthetic-test');
  BEGIN
    PERFORM public.issue19_set_party_notes(v_email,'individual',v_target,'Should roll back','Synthetic audit failure');
    RAISE EXCEPTION 'Unaudited note edit succeeded';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  IF (SELECT notes FROM public.people WHERE person_id=v_target)<>'Original' THEN
    RAISE EXCEPTION 'Unaudited note edit survived';
  END IF;
END;
$verify$;
-- Provenance failure also rolls the import back; no partially imported identity.
CREATE FUNCTION pg_temp.reject_note_provenance() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.outcome='imported' THEN
    RAISE EXCEPTION 'Synthetic provenance failure' USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER verify_notes_provenance_failure BEFORE INSERT ON public.member_identity_note_backfill
  FOR EACH ROW EXECUTE FUNCTION pg_temp.reject_note_provenance();
DO $verify$
DECLARE v_person uuid; v_member uuid;
BEGIN
  INSERT INTO public.people(display_name,notes) VALUES('Synthetic import rollback target','Original') RETURNING person_id INTO v_person;
  INSERT INTO public.members(person_id,notes) VALUES(v_person,'Historical') RETURNING member_id INTO v_member;
  BEGIN
    PERFORM public.backfill_member_identity_notes();
    RAISE EXCEPTION 'Provenance failure accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  IF (SELECT notes FROM public.people WHERE person_id=v_person)<>'Original'
    OR EXISTS(SELECT 1 FROM public.member_identity_note_backfill WHERE member_id=v_member) THEN
    RAISE EXCEPTION 'Partial import survived failed provenance write';
  END IF;
END;
$verify$;
ROLLBACK;
