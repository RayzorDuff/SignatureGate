-- One-time, operator-selected directory manager for a new deployment.
-- Requires -v admin_email=..., -v admin_first_name=..., and -v admin_last_name=...
-- The supplied email must be the exact Appsmith sign-in address.
\set ON_ERROR_STOP on
\if :{?admin_email}
\else
  \echo 'Provide -v admin_email=the-exact-Appsmith-sign-in-address'
  \quit 1
\endif
\if :{?admin_first_name}
\else
  \echo 'Provide -v admin_first_name=the-person-first-name'
  \quit 1
\endif
\if :{?admin_last_name}
\else
  \echo 'Provide -v admin_last_name=the-person-last-name'
  \quit 1
\endif

BEGIN;
SELECT set_config('directory.bootstrap_email', lower(btrim(:'admin_email')), true);
LOCK TABLE
  public.person_roles,
  public.person_app_accounts,
  public.members,
  public.people
IN SHARE ROW EXCLUSIVE MODE;

DO $$
DECLARE
  v_email text := current_setting('directory.bootstrap_email');
  v_first_name text := NULLIF(btrim(:'admin_first_name'), '');
  v_last_name text := NULLIF(btrim(:'admin_last_name'), '');
  v_person_id uuid;
  v_member_id uuid;
  v_account_person_id uuid;
  v_duplicate_blocked boolean;
BEGIN
  IF v_first_name IS NULL OR v_last_name IS NULL THEN
    RAISE EXCEPTION 'Directory manager first and last name are required.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.person_roles
    WHERE role_key = 'directory_manager'
  ) THEN
    RAISE EXCEPTION
      'A directory manager already exists; bootstrap may only run once';
  END IF;

  SELECT account.person_id
  INTO v_account_person_id
  FROM public.person_app_accounts account
  WHERE account.email_normalized = v_email;

  IF v_account_person_id IS NOT NULL THEN
    SELECT m.member_id, m.person_id
    INTO v_member_id, v_person_id
    FROM public.members m
    WHERE m.person_id = v_account_person_id
      AND m.status = 'active'
    ORDER BY m.created_at
    LIMIT 1;

    IF v_person_id IS NULL THEN
      RAISE EXCEPTION
        'Application account % is not linked to an active member.',
        v_email;
    END IF;

    UPDATE public.members
    SET
      status = 'active',
      is_facilitator = true,
      updated_at = now()
    WHERE member_id = v_member_id;
  ELSE
    SELECT m.member_id, m.person_id
    INTO v_member_id, v_person_id
    FROM public.members m
    WHERE m.status = 'active'
      AND lower(btrim(m.email)) = v_email
    ORDER BY m.created_at
    LIMIT 1;

    IF v_person_id IS NULL THEN
      SELECT x.member_id, x.duplicate_blocked
      INTO v_member_id, v_duplicate_blocked
      FROM public.create_member_from_intake(
        p_first_name => v_first_name,
        p_last_name => v_last_name,
        p_email => v_email,
        p_phone => NULL,
        p_date_of_birth => NULL,
        p_notes => 'Initial directory manager bootstrap',
        p_is_facilitator => true,
        p_created_by_facilitator_id => NULL
      ) x;

      IF COALESCE(v_duplicate_blocked, false) OR v_member_id IS NULL THEN
        RAISE EXCEPTION
          'Directory manager identity creation was blocked by an existing member identity.';
      END IF;

      SELECT m.person_id
      INTO v_person_id
      FROM public.members m
      WHERE m.member_id = v_member_id;
    ELSE
      UPDATE public.members
      SET
        status = 'active',
        is_facilitator = true,
        updated_at = now()
      WHERE member_id = v_member_id;
    END IF;

    INSERT INTO public.person_app_accounts (
      person_id,
      email,
      status
    )
    VALUES (
      v_person_id,
      v_email,
      'active'
    );
  END IF;

  INSERT INTO public.person_roles (
    person_id,
    role_key,
    assigned_by
  )
  VALUES (
    v_person_id,
    'directory_manager',
    'database_admin'
  );

  INSERT INTO public.audit_log (
    actor,
    action,
    entity_type,
    entity_id,
    details
  )
  VALUES (
    'database_admin',
    'directory_manager_bootstrapped',
    'person',
    v_person_id::text,
    jsonb_build_object(
      'email', v_email,
      'member_id', v_member_id,
      'is_facilitator', true
    )
  );
END $$;
COMMIT;
