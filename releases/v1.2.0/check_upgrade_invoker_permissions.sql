-- PRIVATE, read-only. Supply actual saved Appsmith/n8n database principals:
-- psql -X -qAt -v app_role=... -v workflow_role=... -f this-file.sql
-- Reports effective rights, never grants them. Review least privilege separately.
\set ON_ERROR_STOP on
BEGIN READ ONLY;
WITH principals(name) AS (VALUES (:'app_role'),(:'workflow_role'))
SELECT jsonb_build_object('principal',p.name,'exists',r.oid IS NOT NULL,
 'superuser',r.rolsuper,'bypass_rls',r.rolbypassrls,'login',r.rolcanlogin,
 'schema_usage',CASE WHEN r.oid IS NOT NULL THEN has_schema_privilege(r.oid,'public','USAGE') END)
FROM principals p LEFT JOIN pg_roles r ON r.rolname=p.name;
WITH principals(name) AS (VALUES (:'app_role'),(:'workflow_role'))
SELECT jsonb_build_object('principal',p.name,'table',c.relname,
 'select',has_table_privilege(r.oid,c.oid,'SELECT'),
 'insert',has_table_privilege(r.oid,c.oid,'INSERT'),
 'update',has_table_privilege(r.oid,c.oid,'UPDATE'),
 'owner',pg_get_userbyid(c.relowner))
FROM principals p JOIN pg_roles r ON r.rolname=p.name
CROSS JOIN pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='public' AND c.relname IN
 ('application_intake_requests','paper_agreement_upload_requests',
  'application_actor_references','organization_contact_people','member_identity_note_backfill')
ORDER BY p.name,c.relname;
WITH principals(name) AS (VALUES (:'app_role'),(:'workflow_role'))
SELECT jsonb_build_object('principal',p.name,'function',f.oid::regprocedure::text,
 'execute',has_function_privilege(r.oid,f.oid,'EXECUTE'),
 'owner',pg_get_userbyid(f.proowner),'security_definer',f.prosecdef)
FROM principals p JOIN pg_roles r ON r.rolname=p.name
CROSS JOIN pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace
WHERE n.nspname='public' AND (f.proname LIKE 'application_%'
 OR f.proname='backfill_member_identity_notes') ORDER BY p.name,f.oid::regprocedure::text;
ROLLBACK;
