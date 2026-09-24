-- Issues #19/#20: canonical person identity for agreement practitioners.
-- Apply after migrations_issue_19_person_release_operations.sql; run once.
\set ON_ERROR_STOP on
BEGIN;

DO $$ BEGIN
  IF to_regclass('public.member_agreements') IS NULL
     OR to_regclass('public.member_practitioner_assignments') IS NULL
     OR to_regprocedure('public.issue19_release_practitioners(text,uuid)') IS NULL THEN
    RAISE EXCEPTION 'Apply the Issue #19 person practitioner and release-operation migrations first';
  END IF;
END $$;

LOCK TABLE public.member_agreements IN SHARE ROW EXCLUSIVE MODE;

ALTER TABLE public.member_agreements
  ADD COLUMN practitioner_person_id uuid;
ALTER TABLE public.member_agreements
  ADD CONSTRAINT member_agreements_practitioner_person_id_fkey
  FOREIGN KEY (practitioner_person_id) REFERENCES public.people(person_id);
CREATE INDEX member_agreements_practitioner_person_created_idx
  ON public.member_agreements(practitioner_person_id,created_at DESC);

UPDATE public.member_agreements agreement
SET practitioner_person_id=member.person_id
FROM public.members member
WHERE member.member_id=agreement.facilitator_id
  AND agreement.practitioner_person_id IS NULL;

-- Keep older agreement writers and reports usable during the page migration.
-- The person is authoritative; facilitator_id is a nullable member projection.
CREATE FUNCTION public.issue19_sync_agreement_practitioner_identity()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER
SET search_path = public, pg_temp AS $$
DECLARE
  v_member_person_id uuid;
  v_legacy_member_id uuid;
BEGIN
  IF NEW.facilitator_id IS NOT NULL THEN
    SELECT person_id INTO v_member_person_id FROM public.members
    WHERE member_id=NEW.facilitator_id;
    IF v_member_person_id IS NULL THEN
      RAISE EXCEPTION 'Agreement facilitator member does not resolve to a person';
    END IF;
    IF NEW.practitioner_person_id IS NULL THEN
      NEW.practitioner_person_id := v_member_person_id;
    ELSIF NEW.practitioner_person_id IS DISTINCT FROM v_member_person_id THEN
      RAISE EXCEPTION 'Agreement practitioner person and legacy facilitator member identify different people';
    END IF;
  ELSIF NEW.practitioner_person_id IS NOT NULL THEN
    SELECT member_id INTO v_legacy_member_id FROM public.members
    WHERE person_id=NEW.practitioner_person_id
    ORDER BY (status='active') DESC,created_at DESC LIMIT 1;
    NEW.facilitator_id := v_legacy_member_id;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_issue19_sync_agreement_practitioner_identity
BEFORE INSERT OR UPDATE OF facilitator_id,practitioner_person_id
ON public.member_agreements
FOR EACH ROW EXECUTE FUNCTION
  public.issue19_sync_agreement_practitioner_identity();

CREATE FUNCTION public.issue19_create_member_agreement(
  p_actor_email text,p_member_id uuid,p_practitioner_person_id uuid,
  p_agreement_template_id uuid,p_signature_method text,p_status text,
  p_evidence jsonb DEFAULT '[]'::jsonb,p_member_email_id uuid DEFAULT NULL
)
RETURNS TABLE (
  member_agreement_id uuid,practitioner_person_id uuid,facilitator_id uuid
)
LANGUAGE plpgsql VOLATILE SECURITY INVOKER
SET search_path = public, pg_temp AS $$
DECLARE
  v_actor record;
  v_legacy_member_id uuid;
  v_agreement_id uuid;
  v_method text := lower(NULLIF(btrim(p_signature_method),''));
  v_status text := lower(NULLIF(btrim(p_status),''));
BEGIN
  SELECT * INTO v_actor FROM public.issue19_current_release_actor(p_actor_email);
  IF v_actor.person_id IS NULL OR NOT v_actor.is_practitioner THEN
    RAISE EXCEPTION 'Practitioner appointment required to create a member agreement';
  END IF;
  IF p_member_id IS NULL OR p_practitioner_person_id IS NULL
     OR v_method IS NULL OR v_status IS NULL THEN
    RAISE EXCEPTION 'Member, practitioner, signature method, and status are required';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.members
      WHERE member_id=p_member_id AND status='active') THEN
    RAISE EXCEPTION 'An active membership is required for a member agreement';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.issue19_release_practitioners(
      p_actor_email,p_member_id) available
      WHERE available.practitioner_person_id=p_practitioner_person_id) THEN
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
      WHERE member_email_id=p_member_email_id AND member_id=p_member_id
        AND COALESCE(status,'active')='active') THEN
    RAISE EXCEPTION 'Selected member email is not active for this member';
  END IF;

  SELECT member_id INTO v_legacy_member_id FROM public.members
  WHERE person_id=p_practitioner_person_id
  ORDER BY (status='active') DESC,created_at DESC LIMIT 1;

  INSERT INTO public.member_agreements(
    member_id,practitioner_person_id,facilitator_id,
    agreement_template_id,signature_method,status,evidence,member_email_id)
  VALUES (p_member_id,p_practitioner_person_id,v_legacy_member_id,
    p_agreement_template_id,v_method,v_status,
    COALESCE(p_evidence,'[]'::jsonb),p_member_email_id)
  RETURNING public.member_agreements.member_agreement_id
    INTO v_agreement_id;

  INSERT INTO public.audit_log(actor,action,entity_type,entity_id,details)
  VALUES (lower(btrim(p_actor_email)),
    'member_agreement.practitioner_attributed','member_agreement',
    v_agreement_id::text,jsonb_build_object(
      'member_id',p_member_id,
      'practitioner_person_id',p_practitioner_person_id,
      'legacy_facilitator_member_id',v_legacy_member_id,
      'agreement_template_id',p_agreement_template_id,
      'signature_method',v_method,'status',v_status));

  RETURN QUERY SELECT v_agreement_id,p_practitioner_person_id,
    v_legacy_member_id;
END;
$$;

COMMENT ON COLUMN public.member_agreements.practitioner_person_id IS
  'Canonical practitioner signer identity; facilitator_id is a nullable compatibility projection.';
COMMENT ON FUNCTION public.issue19_create_member_agreement(text,uuid,uuid,uuid,text,text,jsonb,uuid) IS
  'Creates a guarded member agreement using the assigned canonical practitioner person.';
COMMIT;
