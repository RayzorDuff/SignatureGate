-- Issue #19: ending membership must not require or create contributor capacity.
-- Apply after migrations_issue_19_member_operations_read.sql; run once.
\set ON_ERROR_STOP on
BEGIN;

DO $$ BEGIN
  IF to_regprocedure('public.issue19_end_person_membership(text,uuid,text)') IS NULL
     OR to_regprocedure('public.issue19_person_member_operations_state(text,uuid)') IS NULL
     OR to_regclass('public.contributor_member_links') IS NULL THEN
    RAISE EXCEPTION 'Apply the Issue #19 membership and member-operations migrations first';
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.issue19_person_membership_state(
  p_actor_email text, p_person_id uuid
)
RETURNS TABLE (
  member_id uuid, membership_status text, membership_ended_at timestamptz,
  membership_end_reason text, can_end boolean
)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = public, pg_temp AS $$
SELECT m.member_id, m.status, m.membership_ended_at, m.membership_end_reason,
  (m.status = 'active'
    AND NOT EXISTS (SELECT 1 FROM public.person_roles r
      WHERE r.person_id=m.person_id)
    AND NOT (m.is_facilitator OR m.is_document_reviewer
      OR m.is_donations_reviewer)
    AND NOT EXISTS (SELECT 1 FROM public.member_facilitators f
      WHERE f.facilitator_id=m.member_id AND f.status='active')
    AND NOT EXISTS (SELECT 1 FROM public.member_agreements a
      WHERE a.member_id=m.member_id AND a.status IN
        ('pending_review','pending_email_send','pending_signature'))
  ) AS can_end
FROM public.members m
WHERE m.person_id=p_person_id
  AND public.issue19_has_role(p_actor_email,'directory_manager')
  AND public.issue19_has_role(p_actor_email,'document_reviewer')
ORDER BY (m.status='active') DESC, m.created_at DESC
LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.issue19_end_person_membership(
  p_actor_email text, p_person_id uuid, p_reason text
)
RETURNS uuid LANGUAGE plpgsql VOLATILE SECURITY INVOKER
SET search_path = public, pg_temp AS $$
DECLARE
  v_member public.members%ROWTYPE;
  v_contributor_id uuid;
  v_actor_member_id uuid;
  v_links_ended integer;
BEGIN
  IF NOT public.issue19_has_role(p_actor_email,'directory_manager')
     OR NOT public.issue19_has_role(p_actor_email,'document_reviewer') THEN
    RAISE EXCEPTION 'Directory manager and document reviewer permissions required';
  END IF;
  IF p_person_id IS NULL OR NULLIF(btrim(p_reason),'') IS NULL THEN
    RAISE EXCEPTION 'Select an individual and enter a reason';
  END IF;
  PERFORM 1 FROM public.people WHERE person_id=p_person_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Person not found'; END IF;
  SELECT * INTO v_member FROM public.members
  WHERE person_id=p_person_id AND status='active' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'This person has no active membership'; END IF;

  -- Contributor capacity is optional. Lock and preserve it when present, but
  -- never create one merely because membership is ending.
  SELECT c.contributor_id INTO v_contributor_id FROM public.contributors c
  WHERE c.person_id=p_person_id AND c.contributor_type='individual'
    AND c.status='active'
  ORDER BY c.created_at,c.contributor_id
  LIMIT 1 FOR UPDATE;

  IF EXISTS (SELECT 1 FROM public.person_roles r WHERE r.person_id=p_person_id)
    OR v_member.is_facilitator OR v_member.is_document_reviewer
    OR v_member.is_donations_reviewer
    OR EXISTS (SELECT 1 FROM public.member_facilitators f
      WHERE f.facilitator_id=v_member.member_id AND f.status='active') THEN
    RAISE EXCEPTION 'Reassign active facilitator work and remove appointments and permissions before ending membership';
  END IF;
  IF EXISTS (SELECT 1 FROM public.member_agreements a
    WHERE a.member_id=v_member.member_id AND a.status IN
      ('pending_review','pending_email_send','pending_signature')) THEN
    RAISE EXCEPTION 'Resolve pending membership agreements before ending membership';
  END IF;

  SELECT m.member_id INTO v_actor_member_id
  FROM public.person_app_accounts account
  JOIN public.members m ON m.person_id=account.person_id AND m.status='active'
  WHERE account.status='active'
    AND account.email_normalized=lower(btrim(p_actor_email));

  UPDATE public.contributor_member_links link SET status='ended',
    ended_at=now(), ended_by=v_actor_member_id,
    end_reason='Membership ended: ' || btrim(p_reason), updated_at=now()
  WHERE link.member_id=v_member.member_id AND link.status='active';
  GET DIAGNOSTICS v_links_ended = ROW_COUNT;

  UPDATE public.members SET status='inactive', updated_at=now(),
    membership_ended_at=now(), membership_ended_by=lower(btrim(p_actor_email)),
    membership_end_reason=btrim(p_reason)
  WHERE member_id=v_member.member_id;

  INSERT INTO public.audit_log(actor,action,entity_type,entity_id,details)
  VALUES (lower(btrim(p_actor_email)),'membership.ended_for_person',
    'member',v_member.member_id::text,
    jsonb_build_object('person_id',p_person_id,
      'contributor_id',v_contributor_id,
      'had_active_contributor',v_contributor_id IS NOT NULL,
      'reason',btrim(p_reason),'links_ended',v_links_ended));
  RETURN v_member.member_id;
END;
$$;

COMMENT ON FUNCTION public.issue19_end_person_membership(text,uuid,text) IS
  'Ends membership without creating, requiring, archiving, or otherwise changing contributor capacity; any active member/contributor link is ended.';
COMMIT;
