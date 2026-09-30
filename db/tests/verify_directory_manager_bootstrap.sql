-- Rollback-only checks for the initial directory-manager bootstrap data model.
\set ON_ERROR_STOP on
BEGIN;

DO $$
DECLARE
  v_member_id uuid;
  v_person_id uuid;
  v_account_email text := 'bootstrap-test@example.invalid';
  v_role_count integer;
BEGIN
  SELECT x.member_id
  INTO v_member_id
  FROM public.create_member_from_intake(
    p_first_name => 'Bootstrap',
    p_last_name => 'Test',
    p_email => v_account_email,
    p_phone => NULL,
    p_date_of_birth => NULL,
    p_notes => 'directory manager bootstrap test',
    p_is_facilitator => true,
    p_created_by_facilitator_id => NULL
  ) x
  WHERE x.duplicate_blocked IS FALSE;

  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'Bootstrap member creation was unexpectedly blocked.';
  END IF;

  SELECT m.person_id
  INTO v_person_id
  FROM public.members m
  WHERE m.member_id = v_member_id;

  INSERT INTO public.person_app_accounts (person_id, email, status)
  VALUES (v_person_id, v_account_email, 'active');

  INSERT INTO public.person_roles (person_id, role_key, assigned_by)
  VALUES (v_person_id, 'directory_manager', 'database_admin');

  IF NOT EXISTS (
    SELECT 1
    FROM public.members
    WHERE member_id = v_member_id
      AND status = 'active'
      AND is_facilitator IS TRUE
  ) THEN
    RAISE EXCEPTION 'Bootstrap member is not an active facilitator.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.person_app_accounts
    WHERE person_id = v_person_id
      AND email_normalized = v_account_email
      AND status = 'active'
  ) THEN
    RAISE EXCEPTION 'Bootstrap application account was not created correctly.';
  END IF;

  SELECT count(*)
  INTO v_role_count
  FROM public.person_roles
  WHERE person_id = v_person_id
    AND role_key = 'directory_manager';

  IF v_role_count <> 1 THEN
    RAISE EXCEPTION 'Bootstrap directory-manager role was not created exactly once.';
  END IF;

  RAISE NOTICE 'Directory-manager bootstrap model checks passed; rolling back synthetic records.';
END $$;

ROLLBACK;
