-- Allow a document reviewer to create a member agreement on behalf of the
-- practitioner assigned to that member. Practitioners retain the existing
-- restriction that they may act only for practitioners visible to them.
CREATE OR REPLACE FUNCTION public.issue19_create_member_agreement(
  p_actor_email text,
  p_member_id uuid,
  p_practitioner_person_id uuid,
  p_agreement_template_id uuid,
  p_signature_method text,
  p_status text,
  p_evidence jsonb DEFAULT '[]'::jsonb,
  p_member_email_id uuid DEFAULT NULL::uuid
) RETURNS TABLE(
  member_agreement_id uuid,
  practitioner_person_id uuid,
  facilitator_id uuid
)
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_actor record;
  v_legacy_member_id uuid;
  v_agreement_id uuid;
  v_method text := lower(NULLIF(btrim(p_signature_method),''));
  v_status text := lower(NULLIF(btrim(p_status),''));
BEGIN
  SELECT * INTO v_actor
  FROM public.issue19_current_release_actor(p_actor_email);

  IF v_actor.person_id IS NULL
     OR (NOT v_actor.is_practitioner AND NOT v_actor.is_document_reviewer) THEN
    RAISE EXCEPTION
      'Practitioner appointment or document reviewer permission required to create a member agreement';
  END IF;

  IF p_member_id IS NULL OR p_practitioner_person_id IS NULL
     OR v_method IS NULL OR v_status IS NULL THEN
    RAISE EXCEPTION 'Member, practitioner, signature method, and status are required';
  END IF;

  IF NOT EXISTS (
      SELECT 1 FROM public.members
      WHERE member_id=p_member_id AND status='active') THEN
    RAISE EXCEPTION 'An active membership is required for a member agreement';
  END IF;

  IF NOT EXISTS (
      SELECT 1
      FROM public.issue19_release_practitioners(
        p_actor_email,p_member_id) available
      WHERE available.practitioner_person_id=p_practitioner_person_id)
     AND NOT (
       v_actor.is_document_reviewer
       AND EXISTS (
         SELECT 1
         FROM public.member_practitioner_assignments assignment
         JOIN public.person_roles role
           ON role.person_id=assignment.practitioner_person_id
          AND role.role_key='practitioner'
         WHERE assignment.member_id=p_member_id
           AND assignment.practitioner_person_id=p_practitioner_person_id
           AND assignment.status='active'
       )
     ) THEN
    RAISE EXCEPTION 'Selected practitioner is not available for this member';
  END IF;

  IF (v_method='documenso' AND v_status<>'pending_email_send')
     OR (v_method='paper' AND v_status<>'pending_review')
     OR v_method NOT IN ('documenso','paper') THEN
    RAISE EXCEPTION 'Unsupported agreement signature method/status transition';
  END IF;

  IF v_method='documenso' AND p_agreement_template_id IS NULL THEN
    RAISE EXCEPTION 'A template is required for a Documenso agreement';
  END IF;

  IF p_agreement_template_id IS NOT NULL AND NOT EXISTS (
      SELECT 1 FROM public.agreement_templates
      WHERE agreement_template_id=p_agreement_template_id AND active) THEN
    RAISE EXCEPTION 'Selected agreement template is not active';
  END IF;

  IF p_member_email_id IS NOT NULL AND NOT EXISTS (
      SELECT 1 FROM public.member_emails
      WHERE member_email_id=p_member_email_id
        AND member_id=p_member_id
        AND COALESCE(status,'active')='active') THEN
    RAISE EXCEPTION 'Selected member email is not active for this member';
  END IF;

  SELECT member_id INTO v_legacy_member_id
  FROM public.members
  WHERE person_id=p_practitioner_person_id
  ORDER BY (status='active') DESC,created_at DESC
  LIMIT 1;

  INSERT INTO public.member_agreements(
    member_id,practitioner_person_id,facilitator_id,
    agreement_template_id,signature_method,status,evidence,member_email_id)
  VALUES (
    p_member_id,p_practitioner_person_id,v_legacy_member_id,
    p_agreement_template_id,v_method,v_status,
    COALESCE(p_evidence,'[]'::jsonb),p_member_email_id)
  RETURNING public.member_agreements.member_agreement_id
    INTO v_agreement_id;

  INSERT INTO public.audit_log(
    actor,action,entity_type,entity_id,details)
  VALUES (
    lower(btrim(p_actor_email)),
    'member_agreement.practitioner_attributed',
    'member_agreement',
    v_agreement_id::text,
    jsonb_build_object(
      'member_id',p_member_id,
      'practitioner_person_id',p_practitioner_person_id,
      'legacy_facilitator_member_id',v_legacy_member_id,
      'agreement_template_id',p_agreement_template_id,
      'signature_method',v_method,
      'status',v_status));

  RETURN QUERY
  SELECT v_agreement_id,p_practitioner_person_id,v_legacy_member_id;
END;
$$;
