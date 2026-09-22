-- Issue #19: enable membership on an existing person without duplicating the
-- person or automatically reclassifying past contributor donations.
-- Apply after migrations_issue_19_contributor_contact_guard_fix.sql.
\set ON_ERROR_STOP on
BEGIN;

DO $$ BEGIN
  IF to_regprocedure('public.issue19_has_role(text,text)') IS NULL
    OR to_regclass('public.people') IS NULL
    OR to_regclass('public.contributor_member_links') IS NULL THEN
    RAISE EXCEPTION 'Apply the Issue #19 identity and person-role migrations first';
  END IF;
END $$;

CREATE FUNCTION public.issue19_enable_person_membership(
  p_actor_email text, p_person_id uuid, p_first_name text,
  p_last_name text, p_reason text
)
RETURNS uuid LANGUAGE plpgsql VOLATILE SECURITY INVOKER
SET search_path = public, pg_temp AS $$
DECLARE
  v_member_id uuid;
  v_contributor_id uuid;
  v_actor_member_id uuid;
  v_person public.people%ROWTYPE;
  v_first_name text := NULLIF(btrim(p_first_name), '');
  v_last_name text := NULLIF(btrim(p_last_name), '');
  v_completed_name boolean := false;
BEGIN
  IF NOT public.issue19_has_role(p_actor_email, 'document_reviewer')
     OR NOT public.issue19_has_role(p_actor_email, 'directory_manager') THEN
    RAISE EXCEPTION 'Directory manager and document reviewer permissions required';
  END IF;
  IF p_person_id IS NULL OR NULLIF(btrim(p_reason), '') IS NULL THEN
    RAISE EXCEPTION 'Select an individual and enter a reason';
  END IF;

  SELECT * INTO v_person FROM public.people
  WHERE person_id=p_person_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Person not found'; END IF;
  IF v_first_name IS NULL OR v_last_name IS NULL THEN
    RAISE EXCEPTION 'Reviewed first and last name are required for membership';
  END IF;
  -- An archived membership has its own agreements/history. Do not create a
  -- second member ID for that person or silently reactivate the old record.
  IF EXISTS (SELECT 1 FROM public.members WHERE person_id=p_person_id) THEN
    RAISE EXCEPTION 'This person already has a membership record; review its status';
  END IF;
  IF (NULLIF(btrim(v_person.first_name),'') IS NOT NULL
      AND v_person.first_name IS DISTINCT FROM v_first_name)
    OR (NULLIF(btrim(v_person.last_name),'') IS NOT NULL
      AND v_person.last_name IS DISTINCT FROM v_last_name) THEN
    RAISE EXCEPTION 'The supplied name differs from this person; review identity separately';
  END IF;
  v_completed_name := NULLIF(btrim(v_person.first_name),'') IS NULL
    OR NULLIF(btrim(v_person.last_name),'') IS NULL;
  IF v_completed_name THEN
    UPDATE public.people SET first_name=v_first_name,last_name=v_last_name,
      display_name=concat_ws(' ',v_first_name,v_last_name),updated_at=now()
    WHERE person_id=p_person_id;
  END IF;
  SELECT m.member_id INTO v_actor_member_id
  FROM public.person_app_accounts a JOIN public.members m
    ON m.person_id=a.person_id AND m.status='active'
  WHERE a.status='active'
    AND a.email_normalized=lower(btrim(p_actor_email));
  INSERT INTO public.members(person_id,notes)
  VALUES (p_person_id,'Created from existing person for Issue #19: ' || btrim(p_reason))
  RETURNING member_id INTO v_member_id;

  -- Link an existing individual contributor for identity compatibility.
  -- Its historical donations remain contributor-owned with their original
  -- member_id values; membership does not rewrite donor history.
  SELECT c.contributor_id INTO v_contributor_id
  FROM public.contributors c
  WHERE c.person_id=p_person_id AND c.status='active';
  IF v_contributor_id IS NOT NULL THEN
    INSERT INTO public.contributor_member_links
      (contributor_id,member_id,status,linked_by,link_reason)
    VALUES (v_contributor_id,v_member_id,'active',v_actor_member_id,
      'Membership enabled for existing person: ' || btrim(p_reason));
  END IF;
  INSERT INTO public.audit_log(actor,action,entity_type,entity_id,details)
  VALUES (lower(btrim(p_actor_email)),'membership.enabled_for_person',
    'member',v_member_id::text,
    jsonb_build_object('person_id',p_person_id,
      'contributor_id',v_contributor_id,'reason',btrim(p_reason),
      'completed_name',v_completed_name,
      'previous_display_name',CASE WHEN v_completed_name
        THEN v_person.display_name ELSE NULL END));
  RETURN v_member_id;
END;
$$;
COMMIT;
