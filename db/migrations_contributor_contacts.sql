-- Issue #19: edit contributor-purpose email and phone contacts from the new
-- person/company profiles. Legacy rows remain the write-through sources for
-- party_contacts and provider matching. Apply after directory intake.
\set ON_ERROR_STOP on
BEGIN;

DO $$ BEGIN
  IF to_regprocedure('public.issue19_create_contributor(text,text,text,text,text,text,text,text)') IS NULL
    OR to_regclass('public.party_contact_sources') IS NULL THEN
    RAISE EXCEPTION 'Apply the Issue #19 directory intake and contacts foundation first';
  END IF;
END $$;

CREATE FUNCTION public.issue19_contributor_contacts(
  p_actor_email text, p_party_kind text, p_party_id uuid
)
RETURNS TABLE (
  contact_id uuid, contact_kind text, contact_value text,
  is_primary boolean, is_verified boolean
)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = public, pg_temp AS $$
WITH owned AS (
  SELECT c.contributor_id
  FROM public.contributors c
  WHERE c.status = 'active'
    AND ((p_party_kind = 'individual' AND c.person_id = p_party_id)
      OR (p_party_kind = 'organization' AND c.organization_id = p_party_id))
    AND public.issue19_has_role(p_actor_email, 'donations_reviewer')
)
SELECT e.contributor_email_id, 'email'::text, e.email,
  e.is_primary, e.is_verified
FROM owned JOIN public.contributor_emails e USING (contributor_id)
WHERE e.status = 'active'
UNION ALL
SELECT p.contributor_phone_id, 'phone'::text, p.phone,
  p.is_primary, p.is_verified
FROM owned JOIN public.contributor_phones p USING (contributor_id)
WHERE p.status = 'active';
$$;

CREATE FUNCTION public.issue19_add_contributor_contact(
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

CREATE FUNCTION public.issue19_archive_contributor_contact(
  p_actor_email text, p_party_kind text, p_party_id uuid,
  p_contact_kind text, p_contact_id uuid, p_reason text
)
RETURNS boolean LANGUAGE plpgsql VOLATILE SECURITY INVOKER
SET search_path = public, pg_temp AS $$
DECLARE
  v_contributor_id uuid;
  v_archived_by uuid;
  v_was_primary boolean;
BEGIN
  IF NOT public.issue19_has_role(p_actor_email, 'donations_reviewer') THEN
    RAISE EXCEPTION 'Donations reviewer permission required';
  END IF;
  IF p_contact_kind NOT IN ('email','phone') OR p_contact_id IS NULL
    OR NULLIF(btrim(p_reason), '') IS NULL THEN
    RAISE EXCEPTION 'Select a contact and enter a reason';
  END IF;
  SELECT c.contributor_id INTO v_contributor_id FROM public.contributors c
  WHERE c.status='active'
    AND ((p_party_kind='individual' AND c.person_id=p_party_id)
      OR (p_party_kind='organization' AND c.organization_id=p_party_id))
  FOR UPDATE;
  IF v_contributor_id IS NULL THEN
    RAISE EXCEPTION 'Active contributor not found for this profile';
  END IF;
  SELECT m.member_id INTO v_archived_by
  FROM public.person_app_accounts a
  JOIN public.members m ON m.person_id=a.person_id AND m.status='active'
  WHERE a.status='active'
    AND a.email_normalized=lower(btrim(p_actor_email));

  IF p_contact_kind='email' THEN
    SELECT e.is_primary INTO v_was_primary FROM public.contributor_emails e
    WHERE e.contributor_email_id=p_contact_id
      AND e.contributor_id=v_contributor_id AND e.status='active' FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Active email not found for this contributor'; END IF;
    UPDATE public.contributor_emails SET status='archived',is_primary=false,
      archived_at=now(),archived_by=v_archived_by,archive_reason=btrim(p_reason)
    WHERE contributor_email_id=p_contact_id;
    IF v_was_primary THEN
      UPDATE public.contributor_emails e SET is_primary=true
      WHERE e.contributor_email_id=(SELECT e2.contributor_email_id
        FROM public.contributor_emails e2
        WHERE e2.contributor_id=v_contributor_id AND e2.status='active'
        ORDER BY e2.created_at,e2.contributor_email_id LIMIT 1);
    END IF;
  ELSE
    SELECT p.is_primary INTO v_was_primary FROM public.contributor_phones p
    WHERE p.contributor_phone_id=p_contact_id
      AND p.contributor_id=v_contributor_id AND p.status='active' FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Active phone not found for this contributor'; END IF;
    UPDATE public.contributor_phones SET status='archived',is_primary=false,
      archived_at=now(),archived_by=v_archived_by,archive_reason=btrim(p_reason)
    WHERE contributor_phone_id=p_contact_id;
    IF v_was_primary THEN
      UPDATE public.contributor_phones p SET is_primary=true
      WHERE p.contributor_phone_id=(SELECT p2.contributor_phone_id
        FROM public.contributor_phones p2
        WHERE p2.contributor_id=v_contributor_id AND p2.status='active'
        ORDER BY p2.created_at,p2.contributor_phone_id LIMIT 1);
    END IF;
  END IF;
  INSERT INTO public.audit_log(actor,action,entity_type,entity_id,details)
  VALUES (lower(btrim(p_actor_email)),'contributor_contact.archived',
    'contributor_contact',p_contact_id::text,
    jsonb_build_object('contributor_id',v_contributor_id,
      'contact_kind',p_contact_kind,'reason',btrim(p_reason)));
  RETURN true;
END;
$$;
COMMIT;
