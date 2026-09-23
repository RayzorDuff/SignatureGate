-- Issue #19: manage membership-purpose email and phone records from the
-- canonical Individual Profile. Member and contributor contact records remain
-- independent; sharing a person contact across capacities is always explicit.
-- Apply after migrations_issue_19_membership_contributor_independence.sql.
\set ON_ERROR_STOP on
BEGIN;

DO $$ BEGIN
  IF to_regprocedure('public.issue19_person_member_operations_state(text,uuid)') IS NULL
     OR to_regclass('public.party_contact_sources') IS NULL
     OR to_regclass('public.member_emails') IS NULL
     OR to_regclass('public.member_phones') IS NULL THEN
    RAISE EXCEPTION 'Apply the Issue #19 member-operations and party-contact migrations first';
  END IF;
END $$;

CREATE FUNCTION public.issue19_person_membership_contacts(
  p_actor_email text, p_person_id uuid
)
RETURNS TABLE (
  contact_id uuid,
  contact_kind text,
  contact_value text,
  is_primary boolean,
  is_verified boolean,
  mailing_subscription_status text,
  created_at timestamptz
)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = public, pg_temp AS $$
SELECT email.member_email_id, 'email'::text, email.email,
  email.is_primary, email.is_verified,
  email.mailing_subscription_status, email.created_at
FROM public.issue19_person_member_operations_state(
  p_actor_email,p_person_id) state
JOIN public.member_emails email ON email.member_id=state.member_id
WHERE state.can_view AND email.status='active'
UNION ALL
SELECT phone.member_phone_id, 'phone'::text, phone.phone,
  phone.is_primary, phone.is_verified, NULL::text, phone.created_at
FROM public.issue19_person_member_operations_state(
  p_actor_email,p_person_id) state
JOIN public.member_phones phone ON phone.member_id=state.member_id
WHERE state.can_view AND phone.status='active';
$$;

CREATE FUNCTION public.issue19_add_membership_contact(
  p_actor_email text, p_person_id uuid, p_contact_kind text,
  p_contact_value text, p_reason text
)
RETURNS uuid LANGUAGE plpgsql VOLATILE SECURITY INVOKER
SET search_path = public, pg_temp AS $$
DECLARE
  v_member_id uuid;
  v_contact_id uuid;
  v_value text := NULLIF(btrim(p_contact_value),'');
  v_identity text;
  v_primary boolean;
BEGIN
  IF NOT public.issue19_has_role(p_actor_email,'document_reviewer') THEN
    RAISE EXCEPTION 'Document reviewer permission required';
  END IF;
  IF p_person_id IS NULL OR p_contact_kind NOT IN ('email','phone')
     OR v_value IS NULL OR NULLIF(btrim(p_reason),'') IS NULL THEN
    RAISE EXCEPTION 'Contact type, value, and reason are required';
  END IF;
  IF p_contact_kind='email' THEN
    v_identity := lower(v_value);
    IF position('@' in v_identity) < 2 OR v_identity ~ '[[:space:]]' THEN
      RAISE EXCEPTION 'Enter a valid contact email';
    END IF;
  ELSE
    v_identity := NULLIF(public.normalize_us_phone(v_value),'');
    IF v_identity IS NULL OR length(v_identity) <> 10 THEN
      RAISE EXCEPTION 'Enter a ten-digit phone number';
    END IF;
  END IF;

  SELECT state.member_id INTO v_member_id
  FROM public.issue19_person_member_operations_state(
    p_actor_email,p_person_id) state
  WHERE state.can_manage AND state.membership_status='active';
  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'An active membership and document reviewer access are required';
  END IF;

  LOCK TABLE public.member_emails, public.member_phones,
    public.contributor_emails, public.contributor_phones,
    public.party_contacts IN SHARE ROW EXCLUSIVE MODE;

  -- A contact owned by another person cannot be reassigned by this shortcut.
  -- A contact on this same person's contributor capacity is allowed only via
  -- the explicit reviewed cross-role assignment function, not this add path.
  IF EXISTS (SELECT 1 FROM public.party_contacts contact
      WHERE contact.status='active'
        AND contact.contact_kind=p_contact_kind
        AND contact.identity_key=v_identity
        AND contact.person_id IS DISTINCT FROM p_person_id) THEN
    RAISE EXCEPTION 'Contact belongs to another party; review before sharing it';
  END IF;
  IF EXISTS (SELECT 1 FROM public.party_contacts contact
      JOIN public.party_contact_sources source
        ON source.party_contact_id=contact.party_contact_id
      WHERE contact.status='active' AND contact.person_id=p_person_id
        AND contact.contact_kind=p_contact_kind
        AND contact.identity_key=v_identity
        AND source.status='active'
        AND source.source_table IN ('contributor_emails','contributor_phones')) THEN
    RAISE EXCEPTION 'This is an existing contributor contact; use the reviewed cross-role assignment control';
  END IF;

  IF p_contact_kind='email' THEN
    IF EXISTS (SELECT 1 FROM public.member_emails email
      WHERE email.status='active' AND email.email_normalized=v_identity) THEN
      RAISE EXCEPTION 'This email is already assigned to an active membership';
    END IF;
    SELECT NOT EXISTS (SELECT 1 FROM public.member_emails email
      WHERE email.member_id=v_member_id AND email.status='active'
        AND email.is_primary) INTO v_primary;
    INSERT INTO public.member_emails(
      member_id,email,is_primary,mailing_subscription_status,
      mailing_subscription_source,source,notes)
    VALUES (v_member_id,v_value,v_primary,'not_subscribed',
      'issue19_individual_profile','issue19_individual_profile',btrim(p_reason))
    RETURNING member_email_id INTO v_contact_id;
  ELSE
    IF EXISTS (SELECT 1 FROM public.member_phones phone
      WHERE phone.status='active' AND phone.phone_normalized=v_identity) THEN
      RAISE EXCEPTION 'This phone is already assigned to an active membership';
    END IF;
    SELECT NOT EXISTS (SELECT 1 FROM public.member_phones phone
      WHERE phone.member_id=v_member_id AND phone.status='active'
        AND phone.is_primary) INTO v_primary;
    INSERT INTO public.member_phones(member_id,phone,is_primary,source,notes)
    VALUES (v_member_id,v_value,v_primary,
      'issue19_individual_profile',btrim(p_reason))
    RETURNING member_phone_id INTO v_contact_id;
  END IF;

  INSERT INTO public.audit_log(actor,action,entity_type,entity_id,details)
  VALUES (lower(btrim(p_actor_email)),'membership_contact.added',
    'membership_contact',v_contact_id::text,
    jsonb_build_object('person_id',p_person_id,'member_id',v_member_id,
      'contact_kind',p_contact_kind,'reason',btrim(p_reason)));
  RETURN v_contact_id;
END;
$$;

CREATE FUNCTION public.issue19_archive_membership_contact(
  p_actor_email text, p_person_id uuid, p_contact_kind text,
  p_contact_id uuid, p_reason text
)
RETURNS boolean LANGUAGE plpgsql VOLATILE SECURITY INVOKER
SET search_path = public, pg_temp AS $$
DECLARE
  v_member_id uuid;
  v_actor_member_id uuid;
  v_was_primary boolean;
BEGIN
  IF NOT public.issue19_has_role(p_actor_email,'document_reviewer') THEN
    RAISE EXCEPTION 'Document reviewer permission required';
  END IF;
  IF p_person_id IS NULL OR p_contact_kind NOT IN ('email','phone')
     OR p_contact_id IS NULL OR NULLIF(btrim(p_reason),'') IS NULL THEN
    RAISE EXCEPTION 'Select a contact and enter a reason';
  END IF;
  SELECT state.member_id INTO v_member_id
  FROM public.issue19_person_member_operations_state(
    p_actor_email,p_person_id) state
  WHERE state.can_manage AND state.membership_status='active';
  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'An active membership and document reviewer access are required';
  END IF;
  SELECT member.member_id INTO v_actor_member_id
  FROM public.person_app_accounts account
  JOIN public.members member
    ON member.person_id=account.person_id AND member.status='active'
  WHERE account.status='active'
    AND account.email_normalized=lower(btrim(p_actor_email));

  IF p_contact_kind='email' THEN
    SELECT email.is_primary INTO v_was_primary
    FROM public.member_emails email
    WHERE email.member_email_id=p_contact_id
      AND email.member_id=v_member_id AND email.status='active' FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Active membership email not found';
    END IF;
    UPDATE public.member_emails SET status='archived',is_primary=false,
      archived_at=now(),archived_by=v_actor_member_id,
      archive_reason=btrim(p_reason),
      notes=concat_ws(E'\n',NULLIF(notes,''),btrim(p_reason))
    WHERE member_email_id=p_contact_id;
    IF v_was_primary THEN
      UPDATE public.member_emails email SET is_primary=true
      WHERE email.member_email_id=(SELECT candidate.member_email_id
        FROM public.member_emails candidate
        WHERE candidate.member_id=v_member_id AND candidate.status='active'
        ORDER BY candidate.created_at,candidate.member_email_id LIMIT 1);
    END IF;
  ELSE
    SELECT phone.is_primary INTO v_was_primary
    FROM public.member_phones phone
    WHERE phone.member_phone_id=p_contact_id
      AND phone.member_id=v_member_id AND phone.status='active' FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Active membership phone not found';
    END IF;
    UPDATE public.member_phones SET status='archived',is_primary=false,
      archived_at=now(),archived_by=v_actor_member_id,
      archive_reason=btrim(p_reason),
      notes=concat_ws(E'\n',NULLIF(notes,''),btrim(p_reason))
    WHERE member_phone_id=p_contact_id;
    IF v_was_primary THEN
      UPDATE public.member_phones phone SET is_primary=true
      WHERE phone.member_phone_id=(SELECT candidate.member_phone_id
        FROM public.member_phones candidate
        WHERE candidate.member_id=v_member_id AND candidate.status='active'
        ORDER BY candidate.created_at,candidate.member_phone_id LIMIT 1);
    END IF;
  END IF;

  INSERT INTO public.audit_log(actor,action,entity_type,entity_id,details)
  VALUES (lower(btrim(p_actor_email)),'membership_contact.archived',
    'membership_contact',p_contact_id::text,
    jsonb_build_object('person_id',p_person_id,'member_id',v_member_id,
      'contact_kind',p_contact_kind,'reason',btrim(p_reason)));
  RETURN true;
END;
$$;

COMMENT ON FUNCTION public.issue19_person_membership_contacts(text,uuid) IS
  'Returns active membership-purpose email and phone records without exposing contributor contact rows.';
COMMENT ON FUNCTION public.issue19_add_membership_contact(text,uuid,text,text,text) IS
  'Adds a membership-purpose email or phone; contributor contacts require the separate reviewed assignment workflow.';
COMMENT ON FUNCTION public.issue19_archive_membership_contact(text,uuid,text,uuid,text) IS
  'Archives one membership-purpose contact while retaining canonical and contributor history.';
COMMIT;
