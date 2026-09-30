-- Issue #19: signed sacrament agreements remain valid across template
-- versions. A template's active flag controls new issuance, not whether an
-- agreement already signed from that template authorizes a release.
-- Apply after migrations_issue_19_sacrament_release_scope.sql.
\set ON_ERROR_STOP on
BEGIN;

DO $$ BEGIN
  IF to_regclass('public.member_agreements') IS NULL
     OR to_regclass('public.agreement_templates') IS NULL THEN
    RAISE EXCEPTION 'Apply the agreement and sacrament-release migrations first';
  END IF;
END $$;

CREATE FUNCTION public.issue19_sacrament_release_agreement(p_member_id uuid)
RETURNS TABLE (
  member_agreement_id uuid,
  agreement_template_id uuid,
  signed_at timestamptz,
  template_name text,
  template_version text,
  template_active boolean,
  agreement_status text,
  signature_method text,
  eligibility_basis text
)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = public, pg_temp AS $$
SELECT agreement.member_agreement_id,
  agreement.agreement_template_id,
  agreement.signed_at,
  COALESCE(template.name,'Paper Agreement - No Template'),
  template.version,
  template.active,
  agreement.status,
  agreement.signature_method,
  CASE WHEN template.agreement_template_id IS NULL
    THEN 'reviewed_manual_agreement'
    ELSE 'signed_sacrament_template' END
FROM public.member_agreements agreement
LEFT JOIN public.agreement_templates template
  ON template.agreement_template_id=agreement.agreement_template_id
WHERE agreement.member_id=p_member_id
  AND lower(COALESCE(agreement.status,'')) IN
    ('signed','complete','completed')
  AND (
    'sacrament_release'=ANY(COALESCE(template.required_for,ARRAY[]::text[]))
    OR (agreement.agreement_template_id IS NULL
      AND lower(COALESCE(agreement.signature_method,'')) IN ('paper','manual'))
  )
ORDER BY agreement.signed_at DESC NULLS LAST,
  agreement.updated_at DESC,
  agreement.created_at DESC,
  agreement.member_agreement_id
LIMIT 1;
$$;

COMMENT ON FUNCTION public.issue19_sacrament_release_agreement(uuid) IS
  'Returns the newest signed agreement authorizing sacrament release. Template version and active status do not invalidate a previously signed agreement; active only controls new template selection.';

COMMIT;
