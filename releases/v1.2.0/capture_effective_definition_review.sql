-- PRIVATE evidence: effective definitions can contain operational literals.
-- Never commit this output. This query reads catalogs only, not application rows.
\set ON_ERROR_STOP on
BEGIN READ ONLY;
SELECT jsonb_build_object(
  'database_name',current_database(),
  'postgres_version',current_setting('server_version'),
  'captured_at',clock_timestamp(),
  'functions',COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'signature',p.oid::regprocedure::text,
      'definition',pg_get_functiondef(p.oid),
      'owner',pg_get_userbyid(p.proowner),
      'acl',p.proacl::text) ORDER BY p.oid::regprocedure::text)
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.prokind='f' AND p.proname IN (
      'exclude_cash_donation_from_deposit','issue19_create_member_agreement',
      'issue19_set_person_role','prevent_confirmed_cash_deposit_mutation',
      'revive_cash_donation_from_deposit','issue19_party_notes',
      'issue19_set_party_notes','issue19_reassign_organization_contact',
      'create_agreement_type')
  ),'[]'::jsonb),
  'views',COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'name',c.relname,'definition',pg_get_viewdef(c.oid,true),
      'owner',pg_get_userbyid(c.relowner),'acl',c.relacl::text) ORDER BY c.relname)
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='public' AND c.relkind='v'
      AND c.relname IN ('v_person_addresses','v_person_emails','v_person_phones')
  ),'[]'::jsonb)
);
ROLLBACK;
