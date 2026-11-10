-- PRIVATE JSONL. Run psql -X -qAt -v ON_ERROR_STOP=1 before/after on the SAME
-- isolated restore. IDs/digests/role names are operational evidence: never commit.
-- No writes, grants, role changes or record text. Requires a role that can read
-- every public table; a permission error must stop capture, not become a pass.
\set ON_ERROR_STOP on
BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL statement_timeout = '120s';
SELECT jsonb_build_object('kind','capture','database',current_database(),
 'role',current_user,'server',current_setting('server_version'),
 'at',transaction_timestamp());
SELECT jsonb_build_object('kind','role','name',rolname,'superuser',rolsuper,
 'inherit',rolinherit,'create_role',rolcreaterole,'create_db',rolcreatedb,
 'login',rolcanlogin,'replication',rolreplication,'bypass_rls',rolbypassrls)
FROM pg_roles WHERE rolname !~ '^pg_' ORDER BY rolname;
SELECT jsonb_build_object('kind','membership','role',r.rolname,'member',m.rolname,
 'admin',a.admin_option) FROM pg_auth_members a
JOIN pg_roles r ON r.oid=a.roleid JOIN pg_roles m ON m.oid=a.member
ORDER BY r.rolname,m.rolname;
SELECT jsonb_build_object('kind','schema','name',nspname,
 'owner',pg_get_userbyid(nspowner),'acl',nspacl::text)
FROM pg_namespace WHERE nspname='public';
SELECT jsonb_build_object('kind','relation','name',n.nspname||'.'||c.relname,
 'type',c.relkind,'owner',pg_get_userbyid(c.relowner),'acl',c.relacl::text,
 'rls',c.relrowsecurity,'force_rls',c.relforcerowsecurity)
FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='public' AND c.relkind IN ('r','p','v','m','S') ORDER BY c.relname;
SELECT jsonb_build_object('kind','routine','name',p.oid::regprocedure::text,
 'owner',pg_get_userbyid(p.proowner),'acl',p.proacl::text,
 'security_definer',p.prosecdef,'config',p.proconfig,
 'returns',pg_get_function_result(p.oid))
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.prokind IN ('f','p') ORDER BY p.oid::regprocedure::text;
SELECT jsonb_build_object('kind','default_acl','name',pg_get_userbyid(defaclrole)||':'||
 COALESCE(n.nspname,'*')||':'||defaclobjtype,'acl',defaclacl::text)
FROM pg_default_acl d LEFT JOIN pg_namespace n ON n.oid=d.defaclnamespace
ORDER BY defaclrole,defaclnamespace,defaclobjtype;
-- Compare full historical row contents, not counts alone. Only people.notes
-- and its update timestamp have an intended backfill mutation. All other
-- existing columns, relationships and audit rows remain in the digest.
-- Projection is deliberately narrow; verify imported notes separately below.
SELECT format($query$
 SELECT jsonb_build_object('kind','history','name',%L,'count',count(*),
 'sha256_unavailable_md5',md5(COALESCE(string_agg(row_hash,'' ORDER BY row_hash),'')))
 FROM (SELECT md5((to_jsonb(t) - %s)::text) AS row_hash FROM %I.%I t) rows;
$query$,n.nspname||'.'||c.relname,
 CASE WHEN c.relname='people' THEN 'ARRAY[''notes'',''updated_at'']::text[]'
 WHEN c.relname='organizations' THEN 'ARRAY[''notes'']::text[]'
 ELSE 'ARRAY[]::text[]' END,n.nspname,c.relname)
FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='public' AND c.relkind IN ('r','p') ORDER BY c.relname
\gexec
-- No output of note text. This proves retained source/provenance/chunks only;
-- privately review preserved_edit decisions and preexisting canonical notes.
SELECT CASE WHEN to_regclass('public.member_identity_note_backfill') IS NOT NULL THEN $query$
 SELECT jsonb_build_object('kind','backfill','name','member_identity_note_backfill',
 'missing_members', (SELECT count(*) FROM public.members m WHERE NOT EXISTS
  (SELECT 1 FROM public.member_identity_note_backfill b WHERE b.member_id=m.member_id)),
 'bad_relationships',(SELECT count(*) FROM public.member_identity_note_backfill b
  LEFT JOIN public.members m ON m.member_id=b.member_id
  WHERE m.member_id IS NULL OR m.person_id IS DISTINCT FROM b.person_id),
 'missing_imported_chunks',(SELECT count(*) FROM public.member_identity_note_backfill b
  JOIN public.members m USING(member_id) JOIN public.people p ON p.person_id=b.person_id
  WHERE b.outcome IN ('imported','already_present') AND
   position('Member '||m.member_id::text||': '||btrim(m.notes) IN COALESCE(p.notes,''))=0),
 'preserved_edit_count',(SELECT count(*) FROM public.member_identity_note_backfill WHERE outcome='preserved_edit'));
$query$ ELSE 'SELECT jsonb_build_object(''kind'',''backfill'',''name'',''not_installed'');' END
\gexec
SELECT jsonb_build_object('kind','constraint','name',c.conrelid::regclass::text||'.'||c.conname,
 'validated',c.convalidated,'definition',md5(pg_get_constraintdef(c.oid)))
FROM pg_constraint c JOIN pg_namespace n ON n.oid=c.connamespace
WHERE n.nspname='public' ORDER BY c.conrelid::regclass::text,c.conname;
ROLLBACK;
