-- Audited Agreement Type creation for canonical document reviewers.
\set ON_ERROR_STOP on
BEGIN;

CREATE OR REPLACE FUNCTION public.create_agreement_type(
  p_actor_email text,
  p_type_key text,
  p_display_name text,
  p_sort_order integer DEFAULT 100,
  p_active boolean DEFAULT true,
  p_description text DEFAULT NULL
) RETURNS public.agreement_types
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $agreement_type$
DECLARE
  v_key text := lower(btrim(p_type_key));
  v_name text := NULLIF(btrim(p_display_name), '');
  v_actor text := lower(btrim(p_actor_email));
  v_actor_person uuid;
  v_created public.agreement_types;
BEGIN
  IF NOT public.issue19_has_role(v_actor, 'document_reviewer') THEN
    RAISE EXCEPTION 'Document reviewer permission required' USING ERRCODE = '42501';
  END IF;
  IF v_key IS NULL OR v_key !~ '^[a-z][a-z0-9_]{0,63}$' THEN
    RAISE EXCEPTION 'Type key must start with a letter and contain only lowercase letters, digits or underscores (maximum 64 characters)'
      USING ERRCODE = '22023';
  END IF;
  IF v_name IS NULL THEN
    RAISE EXCEPTION 'Display name is required' USING ERRCODE = '22023';
  END IF;
  IF p_sort_order IS NULL OR p_active IS NULL THEN
    RAISE EXCEPTION 'Sort order and active state are required' USING ERRCODE = '22023';
  END IF;
  IF EXISTS (SELECT 1 FROM public.agreement_types t WHERE lower(btrim(t.type_key)) = v_key) THEN
    RAISE EXCEPTION 'Agreement Type key already exists: %', v_key USING ERRCODE = '23505';
  END IF;
  SELECT a.person_id INTO v_actor_person
    FROM public.person_app_accounts a
    WHERE a.email_normalized = v_actor AND a.status = 'active';
  BEGIN
    INSERT INTO public.agreement_types(type_key, display_name, description, sort_order, active)
    VALUES(v_key, v_name, NULLIF(btrim(p_description), ''), p_sort_order, p_active)
    RETURNING * INTO v_created;
  EXCEPTION WHEN unique_violation THEN
    -- The primary key also prevents competing creators from using the same key.
    RAISE EXCEPTION 'Agreement Type key already exists: %', v_key USING ERRCODE = '23505';
  END;
  INSERT INTO public.audit_log(actor, action, entity_type, entity_id, details)
  VALUES(v_actor, 'agreement_type.created', 'agreement_type', v_key,
    jsonb_build_object('actor_person_id', v_actor_person,
      'type_key', v_created.type_key, 'display_name', v_created.display_name,
      'description', v_created.description, 'sort_order', v_created.sort_order,
      'active', v_created.active));
  RETURN v_created;
END;
$agreement_type$;

COMMENT ON FUNCTION public.create_agreement_type(text, text, text, integer, boolean, text) IS
  'Creates and audits an Agreement Type atomically; requires a canonical document reviewer account, independent of membership.';
COMMIT;
