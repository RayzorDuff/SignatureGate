-- Read-only end state plus rollback-only integration checks.
\set ON_ERROR_STOP on
SELECT role_key, count(*) FROM public.person_roles GROUP BY role_key ORDER BY role_key;
SELECT count(*) AS enabled_legacy_practitioners_without_role
FROM public.members m WHERE m.status = 'active' AND m.is_facilitator
  AND NOT EXISTS (SELECT 1 FROM public.person_roles r
    WHERE r.person_id = m.person_id AND r.role_key = 'practitioner');
SELECT count(*) AS enabled_legacy_reviewers_without_role
FROM public.members m WHERE m.status = 'active'
  AND ((m.is_document_reviewer AND NOT EXISTS (
    SELECT 1 FROM public.person_roles r WHERE r.person_id = m.person_id
      AND r.role_key = 'document_reviewer'))
    OR (m.is_donations_reviewer AND NOT EXISTS (
    SELECT 1 FROM public.person_roles r WHERE r.person_id = m.person_id
      AND r.role_key = 'donations_reviewer')));

BEGIN;
DO $$
DECLARE
  v_admin uuid;
  v_target uuid;
  v_changed boolean;
BEGIN
  INSERT INTO public.people(display_name) VALUES ('Issue 19 Admin Test')
    RETURNING person_id INTO v_admin;
  INSERT INTO public.people(display_name) VALUES ('Issue 19 Target Test')
    RETURNING person_id INTO v_target;
  INSERT INTO public.person_app_accounts(person_id,email)
    VALUES(v_admin,'issue19-admin-verify@example.invalid');
  INSERT INTO public.person_roles(person_id,role_key,assigned_by)
    VALUES(v_admin,'directory_manager','issue19_verify');

  IF NOT EXISTS (SELECT 1 FROM public.issue19_directory_entries(
      'issue19-admin-verify@example.invalid') d WHERE d.party_id = v_target)
  THEN RAISE EXCEPTION 'Manager cannot see an individual without membership'; END IF;

  BEGIN
    PERFORM public.issue19_set_person_role('unknown@example.invalid', v_target,
      'practitioner', true, 'Denied test');
    RAISE EXCEPTION 'Unprivileged actor changed a role';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'Directory manager permission required' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM public.issue19_set_person_role('issue19-admin-verify@example.invalid',
      v_admin, 'practitioner', true, 'Self test');
    RAISE EXCEPTION 'Manager changed their own role';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'A directory manager cannot change their own roles' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM public.issue19_set_person_role('issue19-admin-verify@example.invalid',
      v_target, 'directory_manager', true, 'Escalation test');
    RAISE EXCEPTION 'Manager granted manager role';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'A supported role, desired state, and reason are required' THEN RAISE; END IF;
  END;

  v_changed := public.issue19_set_person_role('issue19-admin-verify@example.invalid',
    v_target, 'practitioner', true, 'Test assignment');
  IF NOT v_changed OR NOT EXISTS (SELECT 1 FROM public.person_roles
    WHERE person_id = v_target AND role_key = 'practitioner')
  THEN RAISE EXCEPTION 'Practitioner assignment did not persist'; END IF;
  v_changed := public.issue19_set_person_app_account(
    'issue19-admin-verify@example.invalid',v_target,
    'issue19-target-verify@example.invalid','Test account ownership');
  IF NOT v_changed OR NOT public.issue19_has_role(
    'issue19-target-verify@example.invalid','practitioner')
  THEN RAISE EXCEPTION 'Nonmember Appsmith role not available'; END IF;
  v_changed := public.issue19_set_person_role('issue19-admin-verify@example.invalid',
    v_target, 'practitioner', false, 'Test revocation');
  IF NOT v_changed OR public.issue19_has_role(
      'issue19-target-verify@example.invalid','practitioner')
  THEN RAISE EXCEPTION 'Role revocation failed'; END IF;
  IF (SELECT count(*) FROM public.audit_log
    WHERE entity_id = v_target::text AND action = 'person_role_changed') <> 2
  THEN RAISE EXCEPTION 'Role changes were not audited'; END IF;
  RAISE NOTICE 'Person role integration checks passed; rolling back synthetic records.';
END $$;
ROLLBACK;
