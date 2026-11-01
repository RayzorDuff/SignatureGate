\set ON_ERROR_STOP on
BEGIN;
-- Organization contributor contact reassignment, preserving contact ID and Listmonk state.
CREATE OR REPLACE FUNCTION public.issue19_reassign_organization_contact(
  p_actor_email text, p_source_organization_id uuid, p_contact_kind text,
  p_contact_id uuid, p_target_organization_id uuid, p_reason text
) RETURNS boolean
LANGUAGE plpgsql
SET search_path TO public, pg_temp
AS $$
DECLARE
  v_source uuid;
  v_target uuid;
  v_table text;
  v_contact public.party_contacts%ROWTYPE;
  v_mapping public.party_contact_sources%ROWTYPE;
  v_primary boolean;
  v_identity text;
BEGIN
  IF NOT public.issue19_has_role(p_actor_email, 'donations_reviewer') THEN
    RAISE EXCEPTION 'Donations reviewer permission required';
  END IF;
  IF p_source_organization_id IS NULL OR p_target_organization_id IS NULL
     OR p_source_organization_id = p_target_organization_id
     OR p_contact_id IS NULL OR p_contact_kind NOT IN ('email','phone','address')
     OR NULLIF(btrim(p_reason),'') IS NULL THEN
    RAISE EXCEPTION 'Different source and target organizations, contact and reason are required';
  END IF;
  SELECT contributor_id INTO v_source FROM public.contributors
    WHERE organization_id=p_source_organization_id AND contributor_type='organization' AND status='active' FOR UPDATE;
  SELECT contributor_id INTO v_target FROM public.contributors
    WHERE organization_id=p_target_organization_id AND contributor_type='organization' AND status='active' FOR UPDATE;
  IF v_source IS NULL OR v_target IS NULL THEN
    RAISE EXCEPTION 'Source and target must be active organization contributors';
  END IF;
  v_table := CASE p_contact_kind WHEN 'email' THEN 'contributor_emails'
    WHEN 'phone' THEN 'contributor_phones' ELSE 'contributor_addresses' END;
  SELECT ps.* INTO v_mapping FROM public.party_contact_sources ps
    WHERE ps.source_table=v_table AND ps.source_id=p_contact_id AND ps.status='active' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Active canonical contact source mapping not found'; END IF;
  SELECT pc.* INTO v_contact FROM public.party_contacts pc
    WHERE pc.party_contact_id=v_mapping.party_contact_id AND pc.status='active'
      AND pc.organization_id=p_source_organization_id
      AND pc.contact_kind=p_contact_kind FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Canonical contact does not belong to source organization'; END IF;
  v_identity := v_contact.identity_key;
  -- Check genuine destination collisions BEFORE firing contributor source triggers.
  -- Otherwise the synchronization trigger creates a new canonical destination
  -- contact and the later duplicate check rejects the reassignment itself.
  IF EXISTS (
    SELECT 1 FROM public.party_contacts pc
    WHERE pc.organization_id=p_target_organization_id
      AND pc.status='active'
      AND pc.contact_kind=p_contact_kind
      AND pc.identity_key=v_identity
      AND pc.party_contact_id<>v_mapping.party_contact_id
  ) THEN
    RAISE EXCEPTION 'Target already has canonical contact with same identity';
  END IF;

  -- Pre-transfer ownership so the domain UPDATE trigger reuses the existing
  -- canonical contact rather than creating a second one at the destination.
  UPDATE public.party_contacts
  SET organization_id=p_target_organization_id,updated_at=now()
  WHERE party_contact_id=v_mapping.party_contact_id;

  IF p_contact_kind='email' THEN
    SELECT is_primary INTO v_primary FROM public.contributor_emails
      WHERE contributor_email_id=p_contact_id AND contributor_id=v_source AND status='active' FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Email no longer belongs to source contributor'; END IF;
    IF EXISTS (SELECT 1 FROM public.contributor_emails WHERE contributor_id=v_target AND status='active'
       AND email_normalized=v_identity) THEN RAISE EXCEPTION 'Target already has this email'; END IF;
    UPDATE public.contributor_emails SET contributor_id=v_target,is_primary=false,updated_at=now(),
      notes=concat_ws(E'\n',NULLIF(notes,''),'Reassigned from organization '||p_source_organization_id||': '||btrim(p_reason))
      WHERE contributor_email_id=p_contact_id;
  ELSIF p_contact_kind='phone' THEN
    SELECT is_primary INTO v_primary FROM public.contributor_phones
      WHERE contributor_phone_id=p_contact_id AND contributor_id=v_source AND status='active' FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Phone no longer belongs to source contributor'; END IF;
    IF EXISTS (SELECT 1 FROM public.contributor_phones WHERE contributor_id=v_target AND status='active'
       AND phone_normalized=v_identity) THEN RAISE EXCEPTION 'Target already has this phone'; END IF;
    UPDATE public.contributor_phones SET contributor_id=v_target,is_primary=false,updated_at=now(),
      notes=concat_ws(E'\n',NULLIF(notes,''),'Reassigned from organization '||p_source_organization_id||': '||btrim(p_reason))
      WHERE contributor_phone_id=p_contact_id;
  ELSE
    SELECT is_primary INTO v_primary FROM public.contributor_addresses
      WHERE contributor_address_id=p_contact_id AND contributor_id=v_source AND status='active' FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Address no longer belongs to source contributor'; END IF;
    IF EXISTS (SELECT 1 FROM public.contributor_addresses WHERE contributor_id=v_target AND status='active'
       AND address_identity_key=v_identity) THEN RAISE EXCEPTION 'Target already has this address'; END IF;
    UPDATE public.contributor_addresses SET contributor_id=v_target,is_primary=false,updated_at=now(),
      notes=concat_ws(E'\n',NULLIF(notes,''),'Reassigned from organization '||p_source_organization_id||': '||btrim(p_reason))
      WHERE contributor_address_id=p_contact_id;
  END IF;
  -- The source trigger has now refreshed this same canonical mapping.
  UPDATE public.party_contact_sources SET is_primary=false,updated_at=now()
    WHERE source_table=v_table AND source_id=p_contact_id;
  INSERT INTO public.audit_log(actor,action,entity_type,entity_id,details)
  VALUES (lower(btrim(p_actor_email)),'organization_contact.reassigned',
    'party_contact',v_mapping.party_contact_id::text,
    jsonb_build_object('source_organization_id',p_source_organization_id,
      'target_organization_id',p_target_organization_id,
      'contact_kind',p_contact_kind,'contact_id',p_contact_id,
      'reason',btrim(p_reason),'was_primary',COALESCE(v_primary,false)));
  RETURN true;
END;
$$;

COMMIT;
