-- Issue #19: expose membership agreement and practitioner-assignment context
-- on the canonical Individual Profile without duplicating write workflows.
-- Apply after migrations_issue_19_sacrament_release_scope.sql; run once.
\set ON_ERROR_STOP on
BEGIN;

DO $$ BEGIN
  IF to_regprocedure('public.issue19_has_role(text,text)') IS NULL
     OR to_regclass('public.member_agreements') IS NULL
     OR to_regclass('public.member_facilitators') IS NULL
     OR to_regclass('public.person_app_accounts') IS NULL THEN
    RAISE EXCEPTION 'Apply the Issue #19 identity, role, and release-scope migrations first';
  END IF;
END $$;

CREATE FUNCTION public.issue19_person_member_operations_state(
  p_actor_email text, p_person_id uuid
)
RETURNS TABLE (
  member_id uuid,
  membership_status text,
  can_view boolean,
  can_manage boolean
)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = public, pg_temp AS $$
WITH actor AS (
  SELECT account.person_id,
    (SELECT m.member_id FROM public.members m
      WHERE m.person_id=account.person_id AND m.status='active'
      ORDER BY m.created_at DESC LIMIT 1) AS actor_member_id,
    public.issue19_has_role(p_actor_email,'document_reviewer') AS can_review
  FROM public.person_app_accounts account
  WHERE account.status='active'
    AND account.email_normalized=lower(btrim(p_actor_email))
), target AS (
  SELECT m.member_id,m.status
  FROM public.members m
  WHERE m.person_id=p_person_id
  ORDER BY (m.status='active') DESC,m.created_at DESC
  LIMIT 1
)
SELECT target.member_id,target.status,
  (actor.can_review OR EXISTS (
    SELECT 1 FROM public.member_facilitators assignment
    WHERE assignment.member_id=target.member_id
      AND assignment.facilitator_id=actor.actor_member_id
      AND assignment.status='active')) AS can_view,
  actor.can_review AS can_manage
FROM target CROSS JOIN actor;
$$;

CREATE FUNCTION public.issue19_person_member_agreements(
  p_actor_email text, p_person_id uuid
)
RETURNS TABLE (
  member_id uuid,
  membership_status text,
  member_agreement_id uuid,
  created_at timestamptz,
  template_name text,
  agreement_scope text,
  agreement_status text,
  signature_method text,
  member_signed_at timestamptz,
  practitioner_signed_at timestamptz,
  evidence_attached boolean,
  review_notes text
)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = public, pg_temp AS $$
SELECT state.member_id,state.membership_status,
  agreement.member_agreement_id,agreement.created_at,
  COALESCE(template.name,'Paper agreement - no template'),
  COALESCE(array_to_string(template.required_for,', '),''),
  agreement.status,agreement.signature_method,
  agreement.member_signed_at,agreement.facilitator_signed_at,
  agreement.evidence IS NOT NULL
    AND btrim(agreement.evidence::text) NOT IN ('','null','[]'),
  agreement.review_notes
FROM public.issue19_person_member_operations_state(
  p_actor_email,p_person_id) state
JOIN public.member_agreements agreement ON agreement.member_id=state.member_id
LEFT JOIN public.agreement_templates template
  ON template.agreement_template_id=agreement.agreement_template_id
WHERE state.can_view
ORDER BY agreement.created_at DESC,agreement.member_agreement_id;
$$;

CREATE FUNCTION public.issue19_person_practitioner_assignments(
  p_actor_email text, p_person_id uuid
)
RETURNS TABLE (
  member_id uuid,
  membership_status text,
  member_facilitator_id uuid,
  practitioner_person_id uuid,
  practitioner_name text,
  practitioner_email text,
  assignment_status text,
  assigned_at timestamptz,
  updated_at timestamptz,
  notes text
)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = public, pg_temp AS $$
SELECT state.member_id,state.membership_status,
  assignment.member_facilitator_id,practitioner.person_id,
  practitioner.display_name,
  COALESCE(account.email,facilitator.email),
  assignment.status,assignment.created_at,assignment.updated_at,assignment.notes
FROM public.issue19_person_member_operations_state(
  p_actor_email,p_person_id) state
JOIN public.member_facilitators assignment
  ON assignment.member_id=state.member_id
JOIN public.members facilitator
  ON facilitator.member_id=assignment.facilitator_id
JOIN public.people practitioner
  ON practitioner.person_id=facilitator.person_id
LEFT JOIN public.person_app_accounts account
  ON account.person_id=practitioner.person_id AND account.status='active'
WHERE state.can_view
ORDER BY (assignment.status='active') DESC,
  practitioner.display_name,assignment.created_at;
$$;

COMMENT ON FUNCTION public.issue19_person_member_operations_state(text,uuid) IS
  'Returns the latest membership and legacy-equivalent operations access for an Individual Profile.';
COMMENT ON FUNCTION public.issue19_person_member_agreements(text,uuid) IS
  'Returns agreement history only to a document reviewer or practitioner actively assigned to the member.';
COMMENT ON FUNCTION public.issue19_person_practitioner_assignments(text,uuid) IS
  'Returns practitioner assignment history under the same member-operations access rule.';
COMMIT;
