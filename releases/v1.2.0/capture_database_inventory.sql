-- v1.2.0 Phase 1: read-only structural inventory. No application records,
-- bank identifiers, credentials, note text, or donor contact data are exported.
-- Run separately against signaturegate and signaturegate_test using psql -X -qAt.
\set ON_ERROR_STOP on
BEGIN READ ONLY;
SET LOCAL statement_timeout = '30s';
SELECT jsonb_pretty(jsonb_build_object(
  'database', current_database(),
  'server_version', current_setting('server_version'),
  'captured_at', transaction_timestamp(),
  'extensions', COALESCE((
    SELECT jsonb_agg(jsonb_build_object('name', extname, 'version', extversion) ORDER BY extname)
    FROM pg_extension
  ), '[]'::jsonb),
  'relations', COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'name', c.relname, 'kind', c.relkind,
      'row_security', c.relrowsecurity, 'force_row_security', c.relforcerowsecurity,
      'estimated_rows', c.reltuples,
      'grants', COALESCE(to_jsonb(c.relacl), '[]'::jsonb)
    ) ORDER BY c.relname)
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p', 'v', 'm', 'S')
  ), '[]'::jsonb),
  'columns', COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'table', c.relname, 'name', a.attname, 'position', a.attnum,
      'type', format_type(a.atttypid, a.atttypmod), 'not_null', a.attnotnull,
      'identity', a.attidentity, 'generated', a.attgenerated,
      'default_hash', CASE WHEN d.oid IS NULL THEN NULL ELSE md5(pg_get_expr(d.adbin, d.adrelid)) END
    ) ORDER BY c.relname, a.attnum)
    FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    LEFT JOIN pg_attrdef d ON d.adrelid = c.oid AND d.adnum = a.attnum
    WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p', 'v', 'm')
      AND a.attnum > 0 AND NOT a.attisdropped
  ), '[]'::jsonb),
  'functions', COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'name', p.proname, 'arguments', pg_get_function_identity_arguments(p.oid),
      'returns', pg_get_function_result(p.oid), 'kind', p.prokind,
      'language', l.lanname, 'security_definer', p.prosecdef,
      'configuration_hash', md5(p.proconfig::text), 'grants', to_jsonb(p.proacl),
      'definition_hash', md5(pg_get_functiondef(p.oid))
    ) ORDER BY p.proname, pg_get_function_identity_arguments(p.oid))
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    JOIN pg_language l ON l.oid = p.prolang
    WHERE n.nspname = 'public' AND p.prokind IN ('f', 'p')
  ), '[]'::jsonb),
  'views', COALESCE((
    SELECT jsonb_agg(jsonb_build_object('name', c.relname,
      'definition_hash', md5(pg_get_viewdef(c.oid, true))) ORDER BY c.relname)
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind IN ('v', 'm')
  ), '[]'::jsonb),
  'constraints', COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'table', c.relname, 'name', k.conname, 'type', k.contype,
      'validated', k.convalidated, 'deferrable', k.condeferrable,
      'definition_hash', md5(pg_get_constraintdef(k.oid, true))
    ) ORDER BY c.relname, k.conname)
    FROM pg_constraint k JOIN pg_class c ON c.oid = k.conrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'public'
  ), '[]'::jsonb),
  'triggers', COALESCE((
    SELECT jsonb_agg(jsonb_build_object('table', c.relname, 'name', t.tgname,
      'enabled', t.tgenabled, 'definition_hash', md5(pg_get_triggerdef(t.oid, true)))
      ORDER BY c.relname, t.tgname)
    FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND NOT t.tgisinternal
  ), '[]'::jsonb),
  'indexes', COALESCE((
    SELECT jsonb_agg(jsonb_build_object('table', c.relname, 'name', idx.relname,
      'valid', i.indisvalid, 'unique', i.indisunique,
      'definition_hash', md5(pg_get_indexdef(i.indexrelid))) ORDER BY c.relname, idx.relname)
    FROM pg_index i JOIN pg_class c ON c.oid = i.indrelid
    JOIN pg_class idx ON idx.oid = i.indexrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'public'
  ), '[]'::jsonb),
  'row_policies', COALESCE((
    SELECT jsonb_agg(jsonb_build_object('table', tablename, 'name', policyname,
      'roles', to_jsonb(roles), 'command', cmd,
      'using_hash', md5(qual), 'check_hash', md5(with_check)) ORDER BY tablename, policyname)
    FROM pg_policies WHERE schemaname = 'public'
  ), '[]'::jsonb)
));
ROLLBACK;
