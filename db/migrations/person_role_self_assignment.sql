-- Allow directory managers to administer their own operational roles.
--
-- This is an explicit forward deployment migration because the canonical
-- schema currently contains the self-role restriction. Apply to test first,
-- verify, then apply the same migration to production during the reviewed
-- production database deployment.
\set ON_ERROR_STOP on
BEGIN;

DO $$
BEGIN
  IF to_regprocedure('public.issue19_set_person_role(text,uuid,text,boolean,text)') IS NULL THEN
    RAISE EXCEPTION 'issue19_set_person_role() is not installed';
  END IF;
  IF to_regclass('public.person_roles') IS NULL
     OR to_regclass('public.person_app_accounts') IS NULL THEN
    RAISE EXCEPTION 'Issue #19 person role tables are not installed';
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.issue19_set_person_role(
  p_actor_email text,
  p_person_id uuid,
  p_role_key text,
  p_enabled boolean,
  p_reason text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_changed boolean := false;
BEGIN
  IF NOT public.issue19_has_role(p_actor_email, 'directory_manager') THEN
    RAISE EXCEPTION 'Directory manager permission required';
  END IF;

  IF p_role_key NOT IN ('practitioner', 'document_reviewer', 'donations_reviewer')
     OR p_enabled IS NULL
     OR NULLIF(btrim(p_reason), '') IS NULL
  THEN
    RAISE EXCEPTION 'A supported role, desired state, and reason are required';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.people WHERE person_id = p_person_id
  ) THEN
    RAISE EXCEPTION 'Person not found';
  END IF;

  -- Directory-manager authority is intentionally not delegated through this
  -- function: directory_manager is an operator-level role and is only
  -- established through the explicit bootstrap/administration path.
  -- Operational roles, including donations_reviewer, may be self-assigned.
  IF p_enabled THEN
    INSERT INTO public.person_roles(person_id, role_key, assigned_by)
    VALUES (p_person_id, p_role_key, lower(btrim(p_actor_email)))
    ON CONFLICT DO NOTHING;
  ELSE
    DELETE FROM public.person_roles
    WHERE person_id = p_person_id AND role_key = p_role_key;
  END IF;
  v_changed := FOUND;

  -- A member's existing workflows still read these flags. In particular,
  -- do not imply practitioner status when granting a reviewer permission.
  UPDATE public.members m SET
    is_facilitator = CASE WHEN p_role_key = 'practitioner' THEN p_enabled
      ELSE m.is_facilitator END,
    is_document_reviewer = CASE WHEN p_role_key = 'document_reviewer'
      THEN p_enabled ELSE m.is_document_reviewer END,
    is_donations_reviewer = CASE WHEN p_role_key = 'donations_reviewer'
      THEN p_enabled ELSE m.is_donations_reviewer END,
    updated_at = now()
  WHERE m.person_id = p_person_id AND m.status = 'active'
    AND ((p_role_key = 'practitioner' AND m.is_facilitator IS DISTINCT FROM p_enabled)
      OR (p_role_key = 'document_reviewer' AND m.is_document_reviewer IS DISTINCT FROM p_enabled)
      OR (p_role_key = 'donations_reviewer' AND m.is_donations_reviewer IS DISTINCT FROM p_enabled));
  v_changed := v_changed OR FOUND;

  IF v_changed THEN
    INSERT INTO public.audit_log(actor, action, entity_type, entity_id, details)
    VALUES (lower(btrim(p_actor_email)), 'person_role_changed', 'person',
      p_person_id::text,
      jsonb_build_object('role', p_role_key, 'enabled', p_enabled,
                         'reason', btrim(p_reason)));
  END IF;

  RETURN v_changed;
END;
$$;

COMMIT;

-- Production deployment note:
-- This migration must also be applied to the production SignatureGate
-- PostgreSQL database after test verification. Do not replace production
-- with db/schema.sql as an in-place upgrade.
