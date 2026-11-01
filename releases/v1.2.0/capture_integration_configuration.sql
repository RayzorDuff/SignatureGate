-- Read-only configuration evidence: no person/contact/donation records.
\set ON_ERROR_STOP on
BEGIN READ ONLY;
SET LOCAL statement_timeout = '30s';
SELECT jsonb_build_object('database', current_database(), 'captured_at', transaction_timestamp());
-- Dynamic SELECT permits older deployments to report missing objects/fields.
SELECT CASE WHEN to_regclass('public.agreement_templates') IS NULL THEN
  'SELECT jsonb_build_object(''section'',''agreement_templates'',''status'',''missing'');'
ELSE $sql$
  SELECT jsonb_build_object('section', 'agreement_templates', 'rows', COALESCE(jsonb_agg(
    jsonb_build_object('agreement_template_id', to_jsonb(t)->'agreement_template_id',
      'name', to_jsonb(t)->'name', 'version', to_jsonb(t)->'version',
      'active', to_jsonb(t)->'active', 'required_for', to_jsonb(t)->'required_for',
      'documenso_template_id', to_jsonb(t)->'documenso_template_id',
      'documenso_template_envelope_id', to_jsonb(t)->'documenso_template_envelope_id',
      'documenso_member_recipient_id', to_jsonb(t)->'documenso_member_recipient_id',
      'documenso_facilitator_recipient_id', to_jsonb(t)->'documenso_facilitator_recipient_id')
    ORDER BY to_jsonb(t)->>'name', to_jsonb(t)->>'version'), '[]'::jsonb))
  FROM public.agreement_templates t;
$sql$ END
\gexec
SELECT jsonb_build_object('section', 'mailing_column_defaults', 'rows', COALESCE(jsonb_agg(
  jsonb_build_object('table', c.relname, 'column', a.attname,
    'default', pg_get_expr(d.adbin, d.adrelid)) ORDER BY c.relname, a.attname), '[]'::jsonb))
FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid
JOIN pg_namespace n ON n.oid=c.relnamespace
LEFT JOIN pg_attrdef d ON d.adrelid=c.oid AND d.adnum=a.attnum
WHERE n.nspname='public' AND c.relname IN ('member_emails','contributor_emails')
  AND a.attname IN ('listmonk_list_id','mailing_subscription_status') AND NOT a.attisdropped;
ROLLBACK;
