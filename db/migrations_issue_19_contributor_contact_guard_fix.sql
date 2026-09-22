-- Issue #19: forward repair for the cross-party contributor contact guard.
-- Apply after migrations_issue_19_contributor_contacts.sql. The original
-- migration already committed on deployments where verification exposed this.
\set ON_ERROR_STOP on
BEGIN;
DO $$ BEGIN
  IF to_regprocedure('public.issue19_add_contributor_contact(text,text,uuid,text,text,text)') IS NULL THEN
    RAISE EXCEPTION 'Apply the contributor contact migration first';
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.issue19_add_contributor_contact(
  p_actor_email text, p_party_kind text, p_party_id uuid,
  p_contact_kind text, p_contact_value text, p_reason text
)
RETURNS uuid LANGUAGE plpgsql VOLATILE SECURITY INVOKER
SET search_path = public, pg_temp AS $$
DECLARE
  v_contributor_id uuid;
  v_contact_id uuid;
  v_value text := NULLIF(btrim(p_contact_value), '');
  v_identity text;
BEGIN
  IF NOT public.issue19_has_role(p_actor_email, 'donations_reviewer') THEN
    RAISE EXCEPTION 'Donations reviewer permission required';
  END IF;
  IF p_contact_kind NOT IN ('email','phone') OR v_value IS NULL
    OR NULLIF(btrim(p_reason), '') IS NULL THEN
    RAISE EXCEPTION 'Contact type, value, and reason are required';
  END IF;
  IF p_contact_kind = 'email' THEN
    v_identity := lower(v_value);
    IF position('@' in v_identity) < 2 OR v_identity ~ '[[:space:]]' THEN
      RAISE EXCEPTION 'Enter a valid contact email';
    END IF;
  ELSE
    v_identity := NULLIF(public.normalize_us_phone(v_value), '');
    IF v_identity IS NULL OR length(v_identity) <> 10 THEN
      RAISE EXCEPTION 'Enter a ten-digit phone number';
    END IF;
  END IF;

  SELECT c.contributor_id INTO v_contributor_id
  FROM public.contributors c WHERE c.status = 'active'
    AND ((p_party_kind = 'individual' AND c.person_id = p_party_id)
      OR (p_party_kind = 'organization' AND c.organization_id = p_party_id))
  FOR UPDATE;
  IF v_contributor_id IS NULL THEN
    RAISE EXCEPTION 'Active contributor not found for this profile';
  END IF;
  LOCK TABLE public.member_emails, public.member_phones,
    public.contributor_emails, public.contributor_phones,
    public.party_contacts IN SHARE ROW EXCLUSIVE MODE;

  IF EXISTS (SELECT 1 FROM public.party_contacts pc
      WHERE pc.status = 'active' AND pc.contact_kind = p_contact_kind
        AND pc.identity_key = v_identity
        AND ((p_party_kind='individual'
            AND pc.person_id IS DISTINCT FROM p_party_id)
          OR (p_party_kind='organization'
            AND pc.organization_id IS DISTINCT FROM p_party_id)))
    OR (p_contact_kind = 'email' AND EXISTS (
      SELECT 1 FROM public.members m WHERE m.status='active'
        AND lower(btrim(m.email))=v_identity
        AND (p_party_kind <> 'individual' OR m.person_id <> p_party_id)))
    OR (p_contact_kind = 'phone' AND EXISTS (
      SELECT 1 FROM public.members m WHERE m.status='active'
        AND public.normalize_us_phone(m.phone)=v_identity
        AND (p_party_kind <> 'individual' OR m.person_id <> p_party_id))) THEN
    RAISE EXCEPTION 'Contact belongs to another party; review before sharing it';
  END IF;

  IF p_contact_kind = 'email' THEN
    IF EXISTS (SELECT 1 FROM public.contributor_emails e
      WHERE e.contributor_id=v_contributor_id AND e.status='active'
        AND e.email_normalized=v_identity) THEN
      RAISE EXCEPTION 'This contributor already has that active email';
    END IF;
    UPDATE public.contributor_emails SET is_primary=false
      WHERE contributor_id=v_contributor_id AND status='active' AND is_primary;
    INSERT INTO public.contributor_emails
      (contributor_id,email,is_primary,source)
    VALUES (v_contributor_id,v_value,true,'directory_profile')
    RETURNING contributor_email_id INTO v_contact_id;
  ELSE
    IF EXISTS (SELECT 1 FROM public.contributor_phones p
      WHERE p.contributor_id=v_contributor_id AND p.status='active'
        AND p.phone_normalized=v_identity) THEN
      RAISE EXCEPTION 'This contributor already has that active phone';
    END IF;
    UPDATE public.contributor_phones SET is_primary=false
      WHERE contributor_id=v_contributor_id AND status='active' AND is_primary;
    INSERT INTO public.contributor_phones
      (contributor_id,phone,is_primary,source)
    VALUES (v_contributor_id,v_value,true,'directory_profile')
    RETURNING contributor_phone_id INTO v_contact_id;
  END IF;
  INSERT INTO public.audit_log(actor,action,entity_type,entity_id,details)
  VALUES (lower(btrim(p_actor_email)),'contributor_contact.added',
    'contributor_contact',v_contact_id::text,
    jsonb_build_object('contributor_id',v_contributor_id,
      'contact_kind',p_contact_kind,'reason',btrim(p_reason)));
  RETURN v_contact_id;
END;
$$;
COMMIT;
