-- Issue #19: assign a person's existing email, phone or physical address to
-- the other capacity. Preserve the source row, its history, and the one
-- person-owned party_contact. Apply after contributor addresses migration.
\set ON_ERROR_STOP on
BEGIN;
DO $$ BEGIN
  IF to_regprocedure('public.issue19_contributor_addresses(text,text,uuid)') IS NULL
     OR to_regclass('public.party_contact_sources') IS NULL
     OR to_regclass('public.listmonk_sync_queue') IS NULL
     OR to_regclass('public.person_roles') IS NULL THEN
    RAISE EXCEPTION 'Apply the Issue #19 contributor address, role, and member mailing-list migrations first';
  END IF;
END $$;

CREATE FUNCTION public.issue19_reusable_person_contacts(
  p_actor_email text, p_person_id uuid
)
RETURNS TABLE (source_table text, source_id uuid, contact_kind text,
  contact_detail text, target_role text)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = public, pg_temp AS $$
SELECT ps.source_table,ps.source_id,pc.contact_kind,
  CASE WHEN pc.contact_kind='address' THEN concat_ws(', ',
    NULLIF(concat_ws(' ',pc.address_1,pc.address_2),''),pc.city,
    pc.state,pc.postal_code,pc.country) ELSE pc.contact_value END,
  CASE WHEN ps.source_table LIKE 'member_%' THEN 'contributions'::text
    ELSE 'membership'::text END
FROM public.members m
JOIN public.contributors c ON c.person_id=m.person_id
  AND c.contributor_type='individual' AND c.status='active'
JOIN public.party_contacts pc ON pc.person_id=m.person_id
  AND pc.status='active' AND pc.identity_key IS NOT NULL
JOIN public.party_contact_sources ps ON ps.party_contact_id=pc.party_contact_id
  AND ps.status='active'
WHERE m.person_id=p_person_id AND m.status='active'
  AND (pc.contact_kind <> 'phone' OR length(pc.identity_key)=10)
  AND ps.source_table IN ('member_emails','member_phones','member_addresses',
    'contributor_emails','contributor_phones','contributor_addresses')
  AND public.issue19_has_role(p_actor_email,'directory_manager')
  AND public.issue19_has_role(p_actor_email,'document_reviewer')
  AND public.issue19_has_role(p_actor_email,'donations_reviewer')
  AND NOT EXISTS (SELECT 1 FROM public.party_contact_sources target
    WHERE target.party_contact_id=pc.party_contact_id
      AND target.status='active'
      AND target.source_table=CASE ps.source_table
        WHEN 'member_emails' THEN 'contributor_emails'
        WHEN 'member_phones' THEN 'contributor_phones'
        WHEN 'member_addresses' THEN 'contributor_addresses'
        WHEN 'contributor_emails' THEN 'member_emails'
        WHEN 'contributor_phones' THEN 'member_phones'
        WHEN 'contributor_addresses' THEN 'member_addresses' END)
ORDER BY pc.contact_kind,ps.source_table,ps.is_primary DESC,pc.created_at;
$$;

CREATE FUNCTION public.issue19_assign_person_contact_role(
  p_actor_email text,p_person_id uuid,p_source_table text,
  p_source_id uuid,p_reason text
)
RETURNS uuid LANGUAGE plpgsql VOLATILE SECURITY INVOKER
SET search_path = public, pg_temp AS $$
DECLARE
  v_member_id uuid;
  v_contributor_id uuid;
  v_source jsonb;
  v_kind text;
  v_target_table text;
  v_identity text;
  v_party_contact_id uuid;
  v_target_id uuid;
  v_primary boolean;
BEGIN
  IF NOT public.issue19_has_role(p_actor_email,'directory_manager')
    OR NOT public.issue19_has_role(p_actor_email,'document_reviewer')
    OR NOT public.issue19_has_role(p_actor_email,'donations_reviewer') THEN
    RAISE EXCEPTION 'Directory manager and both reviewer permissions required';
  END IF;
  IF p_person_id IS NULL OR p_source_id IS NULL
     OR NULLIF(btrim(p_reason),'') IS NULL THEN
    RAISE EXCEPTION 'Select a contact and enter a reason';
  END IF;
  v_kind := CASE p_source_table
    WHEN 'member_emails' THEN 'email' WHEN 'contributor_emails' THEN 'email'
    WHEN 'member_phones' THEN 'phone' WHEN 'contributor_phones' THEN 'phone'
    WHEN 'member_addresses' THEN 'address'
    WHEN 'contributor_addresses' THEN 'address' END;
  IF v_kind IS NULL THEN RAISE EXCEPTION 'Unsupported contact source'; END IF;
  v_target_table := CASE p_source_table
    WHEN 'member_emails' THEN 'contributor_emails'
    WHEN 'member_phones' THEN 'contributor_phones'
    WHEN 'member_addresses' THEN 'contributor_addresses'
    WHEN 'contributor_emails' THEN 'member_emails'
    WHEN 'contributor_phones' THEN 'member_phones'
    WHEN 'contributor_addresses' THEN 'member_addresses' END;
  SELECT m.member_id,c.contributor_id INTO v_member_id,v_contributor_id
  FROM public.members m JOIN public.contributors c ON c.person_id=m.person_id
    AND c.contributor_type='individual' AND c.status='active'
  WHERE m.person_id=p_person_id AND m.status='active'
  FOR UPDATE OF m,c;
  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'An active membership and individual contributor are required';
  END IF;

  -- Lock each real source row and check its owner. Client-supplied IDs never
  -- authorize reading another person's contact or an archived source.
  CASE p_source_table
    WHEN 'member_emails' THEN
      SELECT to_jsonb(x) INTO v_source FROM public.member_emails x
      WHERE x.member_email_id=p_source_id AND x.member_id=v_member_id
        AND x.status='active' FOR SHARE;
    WHEN 'member_phones' THEN
      SELECT to_jsonb(x) INTO v_source FROM public.member_phones x
      WHERE x.member_phone_id=p_source_id AND x.member_id=v_member_id
        AND x.status='active' FOR SHARE;
    WHEN 'member_addresses' THEN
      SELECT to_jsonb(x) INTO v_source FROM public.member_addresses x
      WHERE x.member_address_id=p_source_id AND x.member_id=v_member_id
        AND x.status='active' FOR SHARE;
    WHEN 'contributor_emails' THEN
      SELECT to_jsonb(x) INTO v_source FROM public.contributor_emails x
      WHERE x.contributor_email_id=p_source_id AND x.contributor_id=v_contributor_id
        AND x.status='active' FOR SHARE;
    WHEN 'contributor_phones' THEN
      SELECT to_jsonb(x) INTO v_source FROM public.contributor_phones x
      WHERE x.contributor_phone_id=p_source_id AND x.contributor_id=v_contributor_id
        AND x.status='active' FOR SHARE;
    WHEN 'contributor_addresses' THEN
      SELECT to_jsonb(x) INTO v_source FROM public.contributor_addresses x
      WHERE x.contributor_address_id=p_source_id AND x.contributor_id=v_contributor_id
        AND x.status='active' FOR SHARE;
  END CASE;
  IF v_source IS NULL THEN
    RAISE EXCEPTION 'Active contact does not belong to this person and capacity';
  END IF;
  v_identity := CASE v_kind
    WHEN 'email' THEN NULLIF(lower(btrim(v_source->>'email')),'')
    WHEN 'phone' THEN NULLIF(public.normalize_us_phone(v_source->>'phone'),'')
    ELSE public.member_address_identity_key(v_source->>'address_1',
      v_source->>'address_2',v_source->>'postal_code',v_source->>'country') END;
  IF v_identity IS NULL THEN
    RAISE EXCEPTION 'Complete the source contact before assigning it to another capacity';
  END IF;
  IF v_kind='phone' AND length(v_identity)<>10 THEN
    RAISE EXCEPTION 'A ten-digit phone number is required';
  END IF;
  SELECT pc.party_contact_id INTO v_party_contact_id
  FROM public.party_contact_sources ps
  JOIN public.party_contacts pc ON pc.party_contact_id=ps.party_contact_id
  WHERE ps.source_table=p_source_table AND ps.source_id=p_source_id
    AND ps.status='active' AND pc.status='active'
    AND pc.person_id=p_person_id AND pc.contact_kind=v_kind
    AND pc.identity_key=v_identity;
  IF v_party_contact_id IS NULL THEN
    RAISE EXCEPTION 'Contact mapping needs review before capacity assignment';
  END IF;
  IF v_kind IN ('email','phone') AND EXISTS (
    SELECT 1 FROM public.party_contacts pc
    WHERE pc.status='active' AND pc.contact_kind=v_kind
      AND pc.identity_key=v_identity
      AND pc.person_id IS DISTINCT FROM p_person_id) THEN
    RAISE EXCEPTION 'Contact belongs to another party; review before sharing it';
  END IF;
  IF EXISTS (SELECT 1 FROM public.party_contact_sources ps
    WHERE ps.party_contact_id=v_party_contact_id
      AND ps.source_table=v_target_table AND ps.status='active') THEN
    RAISE EXCEPTION 'Contact is already assigned to the other capacity';
  END IF;
  IF v_target_table='member_emails' AND EXISTS (
    SELECT 1 FROM public.member_emails e WHERE e.status='active'
      AND e.email_normalized=v_identity AND e.member_id<>v_member_id) THEN
    RAISE EXCEPTION 'Email already belongs to a different active member';
  END IF;

  IF v_target_table='contributor_emails' THEN
    SELECT NOT EXISTS (SELECT 1 FROM public.contributor_emails e WHERE
      e.contributor_id=v_contributor_id AND e.status='active' AND e.is_primary)
      INTO v_primary;
    INSERT INTO public.contributor_emails
      (contributor_id,email,is_primary,source,notes)
    VALUES (v_contributor_id,v_source->>'email',v_primary,
      'issue19_capacity_assignment',btrim(p_reason))
    RETURNING contributor_email_id INTO v_target_id;
  ELSIF v_target_table='contributor_phones' THEN
    SELECT NOT EXISTS (SELECT 1 FROM public.contributor_phones x WHERE
      x.contributor_id=v_contributor_id AND x.status='active' AND x.is_primary)
      INTO v_primary;
    INSERT INTO public.contributor_phones
      (contributor_id,phone,is_primary,source,notes)
    VALUES (v_contributor_id,v_source->>'phone',v_primary,
      'issue19_capacity_assignment',btrim(p_reason))
    RETURNING contributor_phone_id INTO v_target_id;
  ELSIF v_target_table='contributor_addresses' THEN
    SELECT NOT EXISTS (SELECT 1 FROM public.contributor_addresses x WHERE
      x.contributor_id=v_contributor_id AND x.status='active' AND x.is_primary)
      INTO v_primary;
    INSERT INTO public.contributor_addresses
      (contributor_id,address_type,address_1,address_2,city,state,
       postal_code,country,is_primary,source,notes)
    VALUES (v_contributor_id,COALESCE(v_source->>'address_type','mailing'),
      v_source->>'address_1',v_source->>'address_2',v_source->>'city',
      v_source->>'state',v_source->>'postal_code',v_source->>'country',
      v_primary,'issue19_capacity_assignment',btrim(p_reason))
    RETURNING contributor_address_id INTO v_target_id;
  ELSIF v_target_table='member_emails' THEN
    SELECT NOT EXISTS (SELECT 1 FROM public.member_emails e WHERE
      e.member_id=v_member_id AND e.status='active' AND e.is_primary)
      INTO v_primary;
    -- Never turn donation contact reuse into mailing-list consent.
    INSERT INTO public.member_emails
      (member_id,email,is_primary,mailing_subscription_status,
       mailing_subscription_source,source,notes)
    VALUES (v_member_id,v_source->>'email',v_primary,'not_subscribed',
      'issue19_capacity_assignment','issue19_capacity_assignment',btrim(p_reason))
    RETURNING member_email_id INTO v_target_id;
  ELSIF v_target_table='member_phones' THEN
    SELECT NOT EXISTS (SELECT 1 FROM public.member_phones x WHERE
      x.member_id=v_member_id AND x.status='active' AND x.is_primary)
      INTO v_primary;
    INSERT INTO public.member_phones
      (member_id,phone,is_primary,source,notes)
    VALUES (v_member_id,v_source->>'phone',v_primary,
      'issue19_capacity_assignment',btrim(p_reason))
    RETURNING member_phone_id INTO v_target_id;
  ELSE
    SELECT NOT EXISTS (SELECT 1 FROM public.member_addresses x WHERE
      x.member_id=v_member_id AND x.status='active' AND x.is_primary)
      INTO v_primary;
    INSERT INTO public.member_addresses
      (member_id,address_type,address_1,address_2,city,state,
       postal_code,country,is_primary,source,notes)
    VALUES (v_member_id,COALESCE(v_source->>'address_type','mailing'),
      v_source->>'address_1',v_source->>'address_2',v_source->>'city',
      v_source->>'state',v_source->>'postal_code',v_source->>'country',
      v_primary,'issue19_capacity_assignment',btrim(p_reason))
    RETURNING member_address_id INTO v_target_id;
  END IF;
  -- The existing triggers should map both role records to one person contact.
  IF NOT EXISTS (SELECT 1 FROM public.party_contact_sources ps
    WHERE ps.source_table=v_target_table AND ps.source_id=v_target_id
      AND ps.party_contact_id=v_party_contact_id AND ps.status='active') THEN
    RAISE EXCEPTION 'Capacity assignment did not preserve the person contact mapping';
  END IF;
  INSERT INTO public.audit_log(actor,action,entity_type,entity_id,details)
  VALUES (lower(btrim(p_actor_email)),'person_contact.capacity_assigned',
    'person_contact',v_party_contact_id::text,
    jsonb_build_object('person_id',p_person_id,'source_table',p_source_table,
      'source_id',p_source_id,'target_table',v_target_table,
      'target_id',v_target_id,'reason',btrim(p_reason)));
  RETURN v_target_id;
END;
$$;
COMMIT;
