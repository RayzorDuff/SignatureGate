-- One-time, operator-selected directory manager. Requires -v admin_email=...
-- Inspect the account owner before invoking; do not choose by shared contact.
\set ON_ERROR_STOP on
\if :{?admin_email}
\else
  \echo 'Provide -v admin_email=the-exact-Appsmith-sign-in-address'
  \quit 1
\endif
BEGIN;
SELECT set_config('issue19.bootstrap_email', lower(btrim(:'admin_email')), true);
LOCK TABLE public.person_roles IN SHARE ROW EXCLUSIVE MODE;
DO $$
DECLARE v_person_id uuid;
BEGIN
  IF EXISTS (SELECT 1 FROM public.person_roles
             WHERE role_key = 'directory_manager') THEN
    RAISE EXCEPTION 'A directory manager already exists; bootstrap may only run once';
  END IF;
  SELECT account.person_id INTO STRICT v_person_id
  FROM public.person_app_accounts account
  WHERE account.email_normalized = current_setting('issue19.bootstrap_email')
    AND account.status = 'active';
  INSERT INTO public.person_roles(person_id,role_key,assigned_by)
  VALUES (v_person_id,'directory_manager','database_admin');
  INSERT INTO public.audit_log(actor,action,entity_type,entity_id,details)
  VALUES ('database_admin','directory_manager_bootstrapped','person',
          v_person_id::text,
          jsonb_build_object('email',current_setting('issue19.bootstrap_email')));
END $$;
COMMIT;
