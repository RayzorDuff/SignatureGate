-- Issue #19: reassign a canonical person's contact from one individual to another.
-- Reassignment moves the existing membership/contributor source row. It does not
-- copy the contact and does not merge the two people.
-- Apply after the Issue #19 party-contact foundation and member/contributor
-- contact migrations.
\set ON_ERROR_STOP on
BEGIN;

DO $$ BEGIN
  IF to_regclass('public.party_contact_sources') IS NULL
     OR to_regclass('public.member_emails') IS NULL
     OR to_regclass('public.member_phones') IS NULL
     OR to_regclass('public.member_addresses') IS NULL
     OR to_regclass('public.contributor_emails') IS NULL
     OR to_regclass('public.contributor_phones') IS NULL
     OR to_regclass('public.contributor_addresses') IS NULL
     OR to_regprocedure('public.issue19_has_role(text,text)') IS NULL THEN
    RAISE EXCEPTION 'Apply the Issue #19 contact, directory, member-role, and contributor-contact migrations first';
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.issue19_reassign_person_contact(
  p_actor_email text,
  p_source_person_id uuid,
  p_capacity text,
  p_contact_kind text,
  p_contact_id uuid,
  p_target_person_id uuid,
  p_reason text
)
RETURNS boolean
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = public, pg_temp AS $$
DECLARE
  v_source_table text;
  v_target_id uuid;
  v_source_owner_id uuid;
  v_target_owner_id uuid;
  v_source_contact_id uuid;
  v_party_contact_id uuid;
  v_identity text;
  v_was_primary boolean;
  v_contact_detail text;
BEGIN
  IF p_source_person_id IS NULL OR p_target_person_id IS NULL
     OR p_source_person_id = p_target_person_id THEN
    RAISE EXCEPTION 'A different target individual is required';
  END IF;
  IF p_capacity NOT IN ('member','contributor')
     OR p_contact_kind NOT IN ('email','phone','address')
     OR p_contact_id IS NULL
     OR NULLIF(btrim(p_reason),'') IS NULL THEN
    RAISE EXCEPTION 'Capacity, contact, target, and reason are required';
  END IF;

  IF p_capacity = 'member' THEN
    IF NOT public.issue19_has_role(p_actor_email,'document_reviewer') THEN
      RAISE EXCEPTION 'Document reviewer permission required';
    END IF;
    v_source_table := CASE p_contact_kind
      WHEN 'email' THEN 'member_emails'
      WHEN 'phone' THEN 'member_phones'
      ELSE 'member_addresses' END;
  ELSE
    IF NOT public.issue19_has_role(p_actor_email,'donations_reviewer') THEN
      RAISE EXCEPTION 'Donations reviewer permission required';
    END IF;
    v_source_table := CASE p_contact_kind
      WHEN 'email' THEN 'contributor_emails'
      WHEN 'phone' THEN 'contributor_phones'
      ELSE 'contributor_addresses' END;
  END IF;

  IF p_capacity = 'member' THEN
    SELECT m.member_id INTO v_source_owner_id
    FROM public.members m
    WHERE m.person_id = p_source_person_id AND m.status = 'active'
    FOR UPDATE;
    IF v_source_owner_id IS NULL THEN
      RAISE EXCEPTION 'Active membership not found for source individual';
    END IF;

    SELECT m.member_id INTO v_target_owner_id
    FROM public.members m
    JOIN public.people p ON p.person_id = m.person_id
    WHERE m.person_id = p_target_person_id AND m.status = 'active'
    FOR UPDATE;
    IF v_target_owner_id IS NULL THEN
      RAISE EXCEPTION 'Active membership not found for target individual';
    END IF;
  ELSE
    SELECT c.contributor_id INTO v_source_owner_id
    FROM public.contributors c
    WHERE c.person_id = p_source_person_id
      AND c.contributor_type = 'individual'
      AND c.status = 'active'
    FOR UPDATE;
    IF v_source_owner_id IS NULL THEN
      RAISE EXCEPTION 'Active individual contributor not found for source individual';
    END IF;

    SELECT c.contributor_id INTO v_target_owner_id
    FROM public.contributors c
    WHERE c.person_id = p_target_person_id
      AND c.contributor_type = 'individual'
      AND c.status = 'active'
    FOR UPDATE;
    IF v_target_owner_id IS NULL THEN
      RAISE EXCEPTION 'Active individual contributor not found for target individual';
    END IF;
  END IF;

  IF p_capacity = 'member' THEN
    IF p_contact_kind = 'email' THEN
      SELECT e.is_primary, e.email, e.email_normalized, e.member_email_id
      INTO v_was_primary, v_contact_detail, v_identity, v_source_contact_id
      FROM public.member_emails e
      WHERE e.member_email_id = p_contact_id
        AND e.member_id = v_source_owner_id
        AND e.status = 'active'
      FOR UPDATE;
    ELSIF p_contact_kind = 'phone' THEN
      SELECT p.is_primary, p.phone, p.phone_normalized, p.member_phone_id
      INTO v_was_primary, v_contact_detail, v_identity, v_source_contact_id
      FROM public.member_phones p
      WHERE p.member_phone_id = p_contact_id
        AND p.member_id = v_source_owner_id
        AND p.status = 'active'
      FOR UPDATE;
    ELSE
      SELECT a.is_primary,
        concat_ws(', ', a.address_1, a.address_2, a.city, a.state,
          a.postal_code, a.country),
        public.member_address_identity_key(
          a.address_1,a.address_2,a.postal_code,a.country),
        a.member_address_id
      INTO v_was_primary, v_contact_detail, v_identity, v_source_contact_id
      FROM public.member_addresses a
      WHERE a.member_address_id = p_contact_id
        AND a.member_id = v_source_owner_id
        AND a.status = 'active'
      FOR UPDATE;
    END IF;
  ELSE
    IF p_contact_kind = 'email' THEN
      SELECT e.is_primary, e.email, e.email_normalized, e.contributor_email_id
      INTO v_was_primary, v_contact_detail, v_identity, v_source_contact_id
      FROM public.contributor_emails e
      WHERE e.contributor_email_id = p_contact_id
        AND e.contributor_id = v_source_owner_id
        AND e.status = 'active'
      FOR UPDATE;
    ELSIF p_contact_kind = 'phone' THEN
      SELECT p.is_primary, p.phone, p.phone_normalized, p.contributor_phone_id
      INTO v_was_primary, v_contact_detail, v_identity, v_source_contact_id
      FROM public.contributor_phones p
      WHERE p.contributor_phone_id = p_contact_id
        AND p.contributor_id = v_source_owner_id
        AND p.status = 'active'
      FOR UPDATE;
    ELSE
      SELECT a.is_primary,
        concat_ws(', ', a.address_1, a.address_2, a.city, a.state,
          a.postal_code, a.country),
        public.member_address_identity_key(
          a.address_1,a.address_2,a.postal_code,a.country),
        a.contributor_address_id
      INTO v_was_primary, v_contact_detail, v_identity, v_source_contact_id
      FROM public.contributor_addresses a
      WHERE a.contributor_address_id = p_contact_id
        AND a.contributor_id = v_source_owner_id
        AND a.status = 'active'
      FOR UPDATE;
    END IF;
  END IF;

  IF v_contact_detail IS NULL OR v_identity IS NULL THEN
    RAISE EXCEPTION 'Active contact does not belong to the selected source individual';
  END IF;

  SELECT ps.party_contact_id INTO v_party_contact_id
  FROM public.party_contact_sources ps
  JOIN public.party_contacts pc ON pc.party_contact_id = ps.party_contact_id
  WHERE ps.source_table = v_source_table
    AND ps.source_id = p_contact_id
    AND ps.status = 'active'
    AND pc.status = 'active'
    AND pc.person_id = p_source_person_id
    AND pc.contact_kind = p_contact_kind
    AND pc.identity_key = v_identity
  FOR UPDATE;
  IF v_party_contact_id IS NULL THEN
    RAISE EXCEPTION 'Contact mapping needs review before reassignment';
  END IF;

  IF p_capacity = 'member' THEN
    IF p_contact_kind = 'email' AND EXISTS (
      SELECT 1 FROM public.member_emails e
      WHERE e.member_id = v_target_owner_id AND e.status = 'active'
        AND e.email_normalized = v_identity AND e.member_email_id <> p_contact_id) THEN
      RAISE EXCEPTION 'Target membership already has this email';
    ELSIF p_contact_kind = 'phone' AND EXISTS (
      SELECT 1 FROM public.member_phones x
      WHERE x.member_id = v_target_owner_id AND x.status = 'active'
        AND x.phone_normalized = v_identity AND x.member_phone_id <> p_contact_id) THEN
      RAISE EXCEPTION 'Target membership already has this phone';
    ELSIF p_contact_kind = 'address' AND EXISTS (
      SELECT 1 FROM public.member_addresses x
      WHERE x.member_id = v_target_owner_id AND x.status = 'active'
        AND public.member_address_identity_key(
          x.address_1,x.address_2,x.postal_code,x.country) = v_identity
        AND x.member_address_id <> p_contact_id) THEN
      RAISE EXCEPTION 'Target membership already has this address';
    END IF;
  ELSE
    IF p_contact_kind = 'email' AND EXISTS (
      SELECT 1 FROM public.contributor_emails e
      WHERE e.contributor_id = v_target_owner_id AND e.status = 'active'
        AND e.email_normalized = v_identity AND e.contributor_email_id <> p_contact_id) THEN
      RAISE EXCEPTION 'Target contributor already has this email';
    ELSIF p_contact_kind = 'phone' AND EXISTS (
      SELECT 1 FROM public.contributor_phones x
      WHERE x.contributor_id = v_target_owner_id AND x.status = 'active'
        AND x.phone_normalized = v_identity AND x.contributor_phone_id <> p_contact_id) THEN
      RAISE EXCEPTION 'Target contributor already has this phone';
    ELSIF p_contact_kind = 'address' AND EXISTS (
      SELECT 1 FROM public.contributor_addresses x
      WHERE x.contributor_id = v_target_owner_id AND x.status = 'active'
        AND x.address_identity_key = v_identity
        AND x.contributor_address_id <> p_contact_id) THEN
      RAISE EXCEPTION 'Target contributor already has this address';
    END IF;
  END IF;

  IF p_capacity = 'member' THEN
    IF p_contact_kind = 'email' THEN
      UPDATE public.member_emails
      SET member_id = v_target_owner_id,
          is_primary = false,
          updated_at = now(),
          notes = concat_ws(E'\n',NULLIF(notes,''),'Reassigned from individual ' ||
            p_source_person_id::text || ': ' || btrim(p_reason))
      WHERE member_email_id = p_contact_id;
    ELSIF p_contact_kind = 'phone' THEN
      UPDATE public.member_phones
      SET member_id = v_target_owner_id,
          is_primary = false,
          updated_at = now(),
          notes = concat_ws(E'\n',NULLIF(notes,''),'Reassigned from individual ' ||
            p_source_person_id::text || ': ' || btrim(p_reason))
      WHERE member_phone_id = p_contact_id;
    ELSE
      UPDATE public.member_addresses
      SET member_id = v_target_owner_id,
          is_primary = false,
          updated_at = now(),
          notes = concat_ws(E'\n',NULLIF(notes,''),'Reassigned from individual ' ||
            p_source_person_id::text || ': ' || btrim(p_reason))
      WHERE member_address_id = p_contact_id;
    END IF;
  ELSE
    IF p_contact_kind = 'email' THEN
      UPDATE public.contributor_emails
      SET contributor_id = v_target_owner_id,
          is_primary = false,
          updated_at = now(),
          notes = concat_ws(E'\n',NULLIF(notes,''),'Reassigned from individual ' ||
            p_source_person_id::text || ': ' || btrim(p_reason))
      WHERE contributor_email_id = p_contact_id;
    ELSIF p_contact_kind = 'phone' THEN
      UPDATE public.contributor_phones
      SET contributor_id = v_target_owner_id,
          is_primary = false,
          updated_at = now(),
          notes = concat_ws(E'\n',NULLIF(notes,''),'Reassigned from individual ' ||
            p_source_person_id::text || ': ' || btrim(p_reason))
      WHERE contributor_phone_id = p_contact_id;
    ELSE
      UPDATE public.contributor_addresses
      SET contributor_id = v_target_owner_id,
          is_primary = false,
          updated_at = now(),
          notes = concat_ws(E'\n',NULLIF(notes,''),'Reassigned from individual ' ||
            p_source_person_id::text || ': ' || btrim(p_reason))
      WHERE contributor_address_id = p_contact_id;
    END IF;
  END IF;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Contact reassignment did not update the source row';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.party_contact_sources ps
    JOIN public.party_contacts pc ON pc.party_contact_id = ps.party_contact_id
    WHERE ps.source_table = v_source_table
      AND ps.source_id = p_contact_id
      AND ps.status = 'active'
      AND pc.status = 'active'
      AND pc.person_id = p_target_person_id
      AND pc.contact_kind = p_contact_kind
      AND pc.identity_key = v_identity
  ) THEN
    RAISE EXCEPTION 'Contact reassignment did not preserve canonical person ownership';
  END IF;

  INSERT INTO public.audit_log(actor,action,entity_type,entity_id,details)
  VALUES
    (lower(btrim(p_actor_email)),
     'person_contact.reassigned',
     'person_contact',
     v_party_contact_id::text,
     jsonb_build_object(
       'source_person_id',p_source_person_id,
       'target_person_id',p_target_person_id,
       'capacity',p_capacity,
       'contact_kind',p_contact_kind,
       'contact_id',p_contact_id,
       'reason',btrim(p_reason),
       'was_primary',COALESCE(v_was_primary,false),
       'contact_detail',v_contact_detail
     ));

  RETURN true;
END;
$$;

COMMENT ON FUNCTION public.issue19_reassign_person_contact(
  text,uuid,text,text,uuid,uuid,text
) IS
  'Moves one active membership- or contributor-purpose contact from one individual to another while preserving its source ID, canonical party-contact mapping, history, and audit trail.';

COMMIT;
