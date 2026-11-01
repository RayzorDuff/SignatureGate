-- Canonical provider review. Requires application_authorization.sql.
\set ON_ERROR_STOP on
BEGIN;

CREATE OR REPLACE FUNCTION public.application_provider_identity_candidates(p_actor_email text,p_donation_id uuid)
RETURNS TABLE(person_id uuid,organization_id uuid)
LANGUAGE plpgsql STABLE SET search_path=public,pg_temp AS $$
DECLARE payload jsonb; email_value text; phone_value text; provider_value text; identity_value text;
BEGIN
 PERFORM public.application_require_permission(p_actor_email,'contributions.review');
 SELECT d.provider INTO provider_value FROM public.donations d WHERE d.donation_id=p_donation_id;
 payload:=COALESCE(public.donation_provider_payload(p_donation_id),'{}'::jsonb);
 email_value:=NULLIF(lower(btrim(COALESCE(payload->>'email',payload#>>'{donor,email}',payload#>>'{supporter,email}',payload#>>'{payer,email}',payload#>>'{customer,email}'))),'');
 phone_value:=NULLIF(public.normalize_us_phone(COALESCE(payload->>'phone',payload#>>'{donor,phone}',payload#>>'{supporter,phone}',payload#>>'{payer,phone}',payload#>>'{customer,phone}')),'');
 identity_value:=NULLIF(btrim(COALESCE(payload->>'contact_id',payload#>>'{donor,id}',payload#>>'{supporter,id}',payload#>>'{customer,id}')),'');
 RETURN QUERY
 SELECT c.person_id,c.organization_id FROM public.contributors c
 JOIN public.contributor_external_identities i USING(contributor_id)
 WHERE lower(btrim(i.provider))=provider_value AND btrim(i.provider_identity)=identity_value
 UNION
 SELECT c.person_id,c.organization_id FROM public.contributors c JOIN public.contributor_emails e USING(contributor_id)
 WHERE e.email_normalized=email_value AND e.status='active'
 UNION
 SELECT c.person_id,c.organization_id FROM public.contributors c JOIN public.contributor_phones p USING(contributor_id)
 WHERE p.phone_normalized=phone_value AND p.status='active'
 UNION
 SELECT m.person_id,NULL::uuid FROM public.members m WHERE lower(btrim(m.email))=email_value OR NULLIF(public.normalize_us_phone(m.phone),'')=phone_value
 UNION
 SELECT m.person_id,NULL::uuid FROM public.members m JOIN public.member_emails e USING(member_id)
 WHERE e.email_normalized=email_value AND e.status='active'
 UNION
 SELECT m.person_id,NULL::uuid FROM public.members m JOIN public.member_phones p USING(member_id)
 WHERE p.phone_normalized=phone_value AND p.status='active';
END $$;

CREATE OR REPLACE FUNCTION public.match_contributor_identity(p_provider text,p_provider_identity text DEFAULT NULL,p_email text DEFAULT NULL,p_phone text DEFAULT NULL)
RETURNS TABLE(contributor_id uuid,member_id uuid,match_method text,match_score integer)
LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE email_value text:=NULLIF(lower(btrim(p_email)),''); phone_value text:=NULLIF(public.normalize_us_phone(p_phone),'');
 identity_value text:=NULLIF(btrim(p_provider_identity),''); chosen_id uuid; chosen_member uuid; chosen_person uuid; chosen_org uuid; chosen_method text; chosen_score integer; candidate_count integer;
BEGIN
 IF identity_value IS NOT NULL THEN
  SELECT i.contributor_id INTO chosen_id FROM public.contributor_external_identities i JOIN public.contributors c USING(contributor_id)
  WHERE lower(btrim(i.provider))=lower(btrim(p_provider)) AND btrim(i.provider_identity)=identity_value AND i.status='active' AND c.status='active';
  IF chosen_id IS NOT NULL THEN chosen_method:='provider_identity';chosen_score:=120;
  ELSIF EXISTS(SELECT 1 FROM public.contributor_external_identities i WHERE lower(btrim(i.provider))=lower(btrim(p_provider)) AND btrim(i.provider_identity)=identity_value) THEN
   RETURN; -- Historical binding requires explicit review, not a new contact fallback.
  END IF;
 END IF;
 IF chosen_id IS NULL THEN
  WITH candidates AS (
   SELECT c.person_id,c.organization_id,'contributor_email'::text method,100 score
    FROM public.contributors c JOIN public.contributor_emails e USING(contributor_id)
    WHERE c.status='active' AND e.status='active' AND e.email_normalized=email_value
   UNION ALL
   SELECT c.person_id,c.organization_id,'contributor_phone',85
    FROM public.contributors c JOIN public.contributor_phones p USING(contributor_id)
    WHERE c.status='active' AND p.status='active' AND p.phone_normalized=phone_value
   UNION ALL
   SELECT m.person_id,NULL::uuid,'member_email',95 FROM public.members m
    WHERE m.status='active' AND (lower(btrim(m.email))=email_value OR EXISTS(SELECT 1 FROM public.member_emails e WHERE e.member_id=m.member_id AND e.status='active' AND e.email_normalized=email_value))
   UNION ALL
   SELECT m.person_id,NULL::uuid,'member_phone',80 FROM public.members m
    WHERE m.status='active' AND (NULLIF(public.normalize_us_phone(m.phone),'')=phone_value OR EXISTS(SELECT 1 FROM public.member_phones p WHERE p.member_id=m.member_id AND p.status='active' AND p.phone_normalized=phone_value))
  ), parties AS (SELECT DISTINCT person_id,organization_id FROM candidates)
  SELECT (SELECT count(*) FROM parties),c.person_id,c.organization_id,c.method,c.score
  INTO candidate_count,chosen_person,chosen_org,chosen_method,chosen_score
  FROM candidates c ORDER BY c.score DESC LIMIT 1;
  IF COALESCE(candidate_count,0)<>1 THEN RETURN; END IF;
  SELECT c.contributor_id INTO chosen_id FROM public.contributors c WHERE c.status='active'
   AND ((chosen_person IS NOT NULL AND c.person_id=chosen_person) OR (chosen_org IS NOT NULL AND c.organization_id=chosen_org));
  IF chosen_id IS NULL AND chosen_person IS NOT NULL THEN
   SELECT m.member_id INTO chosen_member FROM public.members m WHERE m.person_id=chosen_person AND m.status='active' ORDER BY m.created_at DESC,m.member_id LIMIT 1;
   IF chosen_member IS NOT NULL THEN chosen_id:=public.ensure_member_contributor(chosen_member); END IF;
  END IF;
 END IF;
 IF chosen_id IS NULL THEN RETURN; END IF;
 SELECT m.member_id INTO chosen_member FROM public.members m JOIN public.contributors c ON c.person_id=m.person_id
  WHERE c.contributor_id=chosen_id AND m.status='active' ORDER BY m.created_at DESC,m.member_id LIMIT 1;
 contributor_id:=chosen_id;member_id:=chosen_member;match_method:=chosen_method;match_score:=chosen_score;RETURN NEXT;
END $$;

CREATE OR REPLACE FUNCTION public.create_contributor_from_pending_donation(p_donation_id uuid, p_reviewer_id uuid, p_contributor_type text DEFAULT 'individual'::text, p_organization_name text DEFAULT NULL::text, p_review_notes text DEFAULT NULL::text) RETURNS public.contributors
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_payload jsonb;
  v_first_name text;
  v_last_name text;
  v_email text;
  v_organization_name text;
  v_display_name text;
  v_contributor public.contributors%ROWTYPE;
  actor record;
  v_person_id uuid;
  v_organization_id uuid;
BEGIN
  SELECT * INTO actor FROM public.application_access(public.application_actor_email(p_reviewer_id));
  PERFORM public.application_require_permission(actor.email,'contributions.review');
  IF p_contributor_type NOT IN ('individual', 'organization') THEN
    RAISE EXCEPTION 'Contributor type must be individual or organization.';
  END IF;

  PERFORM 1
  FROM public.donations d
  WHERE d.donation_id = p_donation_id
    AND d.provider <> 'cash'
    AND d.donor_kind = 'unresolved'
    AND d.status = 'pending_review'
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Only an unresolved provider donation can create a contributor.';
  END IF;

  -- Serialize reviewed identity creation with contact/provider binding mutations.
  LOCK TABLE public.members,public.people,public.member_emails,public.member_phones,
    public.contributors,public.organizations,public.contributor_emails,
    public.contributor_phones,public.contributor_external_identities
    IN SHARE ROW EXCLUSIVE MODE;
  IF EXISTS(SELECT 1 FROM public.application_provider_identity_candidates(actor.email,p_donation_id)) THEN
    RAISE EXCEPTION 'Existing or ambiguous identity requires explicit existing-party resolution; no new identity was created.';
  END IF;

  v_payload := COALESCE(public.donation_provider_payload(p_donation_id), '{}'::jsonb);
  v_first_name := NULLIF(btrim(COALESCE(
    v_payload->>'first_name',
    v_payload #>> '{donor,first_name}',
    v_payload #>> '{supporter,first_name}'
  )), '');
  v_last_name := NULLIF(btrim(COALESCE(
    v_payload->>'last_name',
    v_payload #>> '{donor,last_name}',
    v_payload #>> '{supporter,last_name}'
  )), '');
  v_email := NULLIF(lower(btrim(COALESCE(
    v_payload->>'email',
    v_payload #>> '{donor,email}',
    v_payload #>> '{supporter,email}'
  ))), '');
  v_organization_name := NULLIF(btrim(COALESCE(
    p_organization_name,
    v_payload->>'organization_name',
    v_payload->>'company_name',
    v_payload->>'company',
    v_payload->>'business_name',
    v_payload #>> '{donor,company}',
    v_payload #>> '{supporter,company}'
  )), '');

  IF p_contributor_type = 'organization' AND v_organization_name IS NULL THEN
    RAISE EXCEPTION
      'The provider payload has no organization name; enter or correct it before creating an organization contributor.';
  END IF;

  v_display_name := CASE
    WHEN p_contributor_type = 'organization' THEN v_organization_name
    ELSE COALESCE(
      NULLIF(btrim(concat_ws(' ', v_first_name, v_last_name)), ''),
      v_email
    )
  END;

  IF v_display_name IS NULL THEN
    RAISE EXCEPTION 'The provider payload does not contain enough contributor identity.';
  END IF;

  IF p_contributor_type = 'individual' THEN
    INSERT INTO public.people (display_name, first_name, last_name)
    VALUES (v_display_name, v_first_name, v_last_name)
    RETURNING person_id INTO v_person_id;
  ELSE
    INSERT INTO public.organizations (organization_name)
    VALUES (v_organization_name)
    RETURNING organization_id INTO v_organization_id;
  END IF;
  INSERT INTO public.contributors
    (contributor_type, person_id, organization_id, status, source, notes)
  VALUES (p_contributor_type, v_person_id, v_organization_id, 'active',
    'givebutter_review', 'Created from pending donation ' || p_donation_id::text)
  RETURNING * INTO v_contributor;

  PERFORM public.resolve_pending_donation(
    p_donation_id,
    p_reviewer_id,
    v_contributor.contributor_id,
    p_review_notes
  );

  INSERT INTO public.audit_log(actor,action,entity_type,entity_id,details)
  VALUES(lower(btrim(actor.email)),'contributor.created_from_donation','contributor',v_contributor.contributor_id::text,
    jsonb_build_object('donation_id',p_donation_id,'contributor_type',p_contributor_type,'actor_person_id',actor.person_id));

  RETURN v_contributor;
END;
$$;

CREATE OR REPLACE FUNCTION public.resolve_pending_donation(p_donation_id uuid, p_reviewer_id uuid, p_contributor_id uuid, p_review_notes text DEFAULT NULL::text) RETURNS public.donations
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_donation public.donations%ROWTYPE;
  v_member_id uuid;
  actor record;
BEGIN
  SELECT * INTO actor FROM public.application_access(public.application_actor_email(p_reviewer_id));
  PERFORM public.application_require_permission(actor.email,'contributions.review');
  IF p_contributor_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.contributors c
    WHERE c.contributor_id = p_contributor_id
      AND c.status = 'active'
  ) THEN
    RAISE EXCEPTION 'An active contributor is required.';
  END IF;

  SELECT *
  INTO v_donation
  FROM public.donations d
  WHERE d.donation_id = p_donation_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Donation % was not found.', p_donation_id;
  END IF;

  IF v_donation.provider = 'cash'
    OR v_donation.donor_kind <> 'unresolved'
    OR v_donation.status <> 'pending_review'
  THEN
    RAISE EXCEPTION 'Only an unresolved provider donation can be assigned.';
  END IF;

  PERFORM 1 FROM public.contributors c WHERE c.contributor_id=p_contributor_id AND c.status='active' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'An active contributor is required.'; END IF;
  SELECT m.member_id INTO v_member_id FROM public.members m JOIN public.contributors c ON c.person_id=m.person_id
    WHERE c.contributor_id=p_contributor_id AND m.status='active' ORDER BY m.created_at DESC,m.member_id LIMIT 1;

  UPDATE public.donations d
  SET
    contributor_id = p_contributor_id,
    member_id = v_member_id,
    donor_kind = 'identified',
    status = 'verified',
    reviewer_id = actor.member_id,
    reviewed_at = now(),
    review_notes = NULLIF(btrim(p_review_notes), '')
  WHERE d.donation_id = p_donation_id
  RETURNING * INTO v_donation;

  IF EXISTS (
    SELECT 1 FROM public.contributor_external_identities i
    WHERE lower(btrim(i.provider))=lower(btrim(v_donation.provider))
      AND btrim(i.provider_identity)=NULLIF(btrim(COALESCE(
        public.donation_provider_payload(p_donation_id)->>'contact_id',
        public.donation_provider_payload(p_donation_id)#>>'{donor,id}',
        public.donation_provider_payload(p_donation_id)#>>'{supporter,id}',
        public.donation_provider_payload(p_donation_id)#>>'{customer,id}')),'')
      AND i.contributor_id<>p_contributor_id
  ) THEN RAISE EXCEPTION 'Provider identity already belongs to another contributor.'; END IF;

  PERFORM public.add_donation_payload_to_contributor(
    p_contributor_id,
    p_donation_id,
    v_donation.provider || '_review'
  );

  INSERT INTO public.audit_log(actor,action,entity_type,entity_id,details)
  VALUES(lower(btrim(actor.email)),'donation.contributor_resolved','donation',p_donation_id::text,
    jsonb_build_object('contributor_id',p_contributor_id,'member_id',v_member_id,'actor_person_id',actor.person_id,'review_notes',NULLIF(btrim(p_review_notes),'')));

  RETURN v_donation;
END;
$$;

CREATE OR REPLACE FUNCTION public.resolve_pending_donation_choice(p_donation_id uuid, p_reviewer_id uuid, p_choice text, p_review_notes text DEFAULT NULL::text) RETURNS public.donations
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_contributor_id uuid;
  v_kind text;
  v_donation public.donations%ROWTYPE;
BEGIN
  PERFORM public.application_require_permission(public.application_actor_email(p_reviewer_id),'contributions.review');
  IF p_choice LIKE 'contributor:%' THEN
    v_contributor_id := substring(p_choice FROM 13)::uuid;
  ELSIF p_choice LIKE 'member:%' THEN
    IF NOT EXISTS(SELECT 1 FROM public.members WHERE member_id=substring(p_choice FROM 8)::uuid AND status='active') THEN RAISE EXCEPTION 'An active Participant is required.'; END IF;
    v_contributor_id := public.ensure_member_contributor(substring(p_choice FROM 8)::uuid);
  ELSIF p_choice IN ('__new_individual__', '__new_organization__') THEN
    v_kind := CASE
      WHEN p_choice = '__new_organization__' THEN 'organization'
      ELSE 'individual'
    END;

    SELECT c.contributor_id
    INTO v_contributor_id
    FROM public.create_contributor_from_pending_donation(
      p_donation_id,
      p_reviewer_id,
      v_kind,
      NULL,
      p_review_notes
    ) c;
  ELSE
    RAISE EXCEPTION 'Unsupported contributor resolution choice.';
  END IF;

  IF p_choice IN ('__new_individual__', '__new_organization__') THEN
    SELECT * INTO v_donation
    FROM public.donations d
    WHERE d.donation_id = p_donation_id;

    RETURN v_donation;
  END IF;

  RETURN public.resolve_pending_donation(
    p_donation_id,
    p_reviewer_id,
    v_contributor_id,
    p_review_notes
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.create_member_from_pending_donation(p_donation_id uuid,p_reviewer_id uuid,p_review_notes text DEFAULT NULL)
RETURNS public.members LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE actor record; payload jsonb; contributor public.contributors%ROWTYPE; member public.members%ROWTYPE;
 first_value text; last_value text; email_value text; phone_value text; address_value jsonb; address_complete boolean; contact_count integer;
BEGIN
 SELECT * INTO actor FROM public.application_access(public.application_actor_email(p_reviewer_id));
 PERFORM public.application_require_permission(actor.email,'contributions.review');
 PERFORM public.application_require_permission(actor.email,'intake.participant');
 IF NOT actor.is_directory_manager THEN RAISE EXCEPTION 'Directory Manager permission is required for dual-capacity enrollment.'; END IF;
 payload:=COALESCE(public.donation_provider_payload(p_donation_id),'{}'::jsonb);
 first_value:=NULLIF(btrim(COALESCE(payload->>'first_name',payload#>>'{donor,first_name}',payload#>>'{supporter,first_name}')), '');
 last_value:=NULLIF(btrim(COALESCE(payload->>'last_name',payload#>>'{donor,last_name}',payload#>>'{supporter,last_name}')), '');
 email_value:=NULLIF(lower(btrim(COALESCE(payload->>'email',payload#>>'{donor,email}',payload#>>'{supporter,email}',payload#>>'{payer,email}',payload#>>'{customer,email}'))), '');
 phone_value:=NULLIF(btrim(COALESCE(payload->>'phone',payload#>>'{donor,phone}',payload#>>'{supporter,phone}',payload#>>'{payer,phone}',payload#>>'{customer,phone}')), '');
 address_value:=COALESCE(payload->'address','{}'::jsonb);
 address_complete:=NULLIF(btrim(COALESCE(address_value->>'address_1',address_value->>'line1',address_value->>'street',address_value->>'street_address')),'') IS NOT NULL
   AND NULLIF(btrim(address_value->>'city'),'') IS NOT NULL
   AND NULLIF(btrim(COALESCE(address_value->>'state',address_value->>'province')),'') IS NOT NULL
   AND NULLIF(btrim(COALESCE(address_value->>'postal_code',address_value->>'zipcode',address_value->>'zip')),'') IS NOT NULL;
 IF first_value IS NULL OR last_value IS NULL THEN RAISE EXCEPTION 'Participant first and last names are required; complete Intake before resolving this donation.'; END IF;
 IF email_value IS NOT NULL AND email_value !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' THEN RAISE EXCEPTION 'A valid contact email is required; complete Intake before resolving this donation.'; END IF;
 contact_count:=(email_value IS NOT NULL)::integer + (NULLIF(public.normalize_us_phone(phone_value),'') IS NOT NULL)::integer + address_complete::integer;
 IF contact_count<2 THEN RAISE EXCEPTION 'Two contact methods are required; complete Intake before resolving this donation.'; END IF;
 contributor:=public.create_contributor_from_pending_donation(p_donation_id,p_reviewer_id,'individual',NULL,p_review_notes);
 -- Enroll the existing newly-created human identity; never create/merge another person.
 INSERT INTO public.members(person_id,email,phone,status,is_facilitator,is_document_reviewer,is_donations_reviewer,created_by_facilitator_id)
 VALUES(contributor.person_id,email_value,phone_value,'active',false,false,false,actor.member_id) RETURNING * INTO member;
 INSERT INTO public.contributor_member_links(contributor_id,member_id,status,linked_by,link_reason)
 VALUES(contributor.contributor_id,member.member_id,'active',actor.member_id,'Explicit dual-capacity enrollment during provider review');
 INSERT INTO public.member_emails(member_id,email,is_primary,is_verified,source)
 SELECT member.member_id,e.email,e.is_primary,e.is_verified,'contributor_promotion' FROM public.contributor_emails e
 WHERE e.contributor_id=contributor.contributor_id AND e.status='active';
 INSERT INTO public.member_phones(member_id,phone,is_primary,is_verified,source)
 SELECT member.member_id,p.phone,p.is_primary,p.is_verified,'contributor_promotion' FROM public.contributor_phones p
 WHERE p.contributor_id=contributor.contributor_id AND p.status='active';
 PERFORM public.upsert_member_address(member.member_id,a.address_1,COALESCE(NULLIF(a.address_type,''),'home'),a.address_2,a.city,a.state,a.postal_code,a.country,a.is_primary,'contributor_promotion',NULL)
 FROM public.contributor_addresses a WHERE a.contributor_id=contributor.contributor_id AND a.status='active';
 UPDATE public.donations SET member_id=member.member_id WHERE donation_id=p_donation_id;
 INSERT INTO public.audit_log(actor,action,entity_type,entity_id,details)
 VALUES(lower(btrim(actor.email)),'donation.member_created','donation',p_donation_id::text,jsonb_build_object('member_id',member.member_id,'contributor_id',contributor.contributor_id,'person_id',contributor.person_id,'actor_person_id',actor.person_id));
 RETURN member;
END $$;

CREATE OR REPLACE FUNCTION public.application_resolve_provider_choice(p_actor_email text,p_donation_id uuid,p_choice text,p_review_notes text DEFAULT NULL)
RETURNS public.donations LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE actor record;
BEGIN
 PERFORM public.application_require_permission(p_actor_email,'contributions.review');
 SELECT * INTO actor FROM public.application_access(p_actor_email);
 RETURN public.resolve_pending_donation_choice(p_donation_id,actor.person_id,p_choice,p_review_notes);
END $$;

CREATE OR REPLACE FUNCTION public.application_create_participant_from_donation(p_actor_email text,p_donation_id uuid,p_review_notes text DEFAULT NULL,p_subscribe boolean DEFAULT false)
RETURNS public.members LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE actor record; member public.members%ROWTYPE;
BEGIN
 PERFORM public.application_require_permission(p_actor_email,'contributions.review');
 SELECT * INTO actor FROM public.application_access(p_actor_email);
 member:=public.create_member_from_pending_donation(p_donation_id,actor.person_id,p_review_notes);
 UPDATE public.member_emails SET mailing_subscription_status=CASE WHEN COALESCE(p_subscribe,false) THEN 'subscribed' ELSE 'not_subscribed' END,
  mailing_subscription_source='givebutter_create_member' WHERE member_id=member.member_id AND status='active';
 RETURN member;
END $$;

CREATE OR REPLACE FUNCTION public.application_reassign_donation(p_actor_email text,p_donation_id uuid,p_choice text,p_reason text)
RETURNS public.donations LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE donation public.donations%ROWTYPE; old_contributor uuid; old_member uuid; target_id uuid; target_member uuid; actor record;
BEGIN
 PERFORM public.application_require_permission(p_actor_email,'contributions.review');
 IF NULLIF(btrim(p_reason),'') IS NULL THEN RAISE EXCEPTION 'A reason is required for donation reassignment.'; END IF;
 SELECT * INTO actor FROM public.application_access(p_actor_email);
 SELECT * INTO donation FROM public.donations WHERE donation_id=p_donation_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Donation was not found.'; END IF;
 IF donation.donor_kind='unresolved' THEN RAISE EXCEPTION 'Resolve the pending provider donation before reassigning it.'; END IF;
 IF EXISTS(SELECT 1 FROM public.cash_deposit_batch_items WHERE donation_id=p_donation_id AND removed_at IS NULL) THEN
  RAISE EXCEPTION 'A donation in an active deposit batch cannot be reassigned.';
 END IF;
 IF p_choice LIKE 'contributor:%' THEN target_id:=substring(p_choice FROM 13)::uuid;
 ELSIF p_choice LIKE 'member:%' THEN
  IF NOT EXISTS(SELECT 1 FROM public.members WHERE member_id=substring(p_choice FROM 8)::uuid AND status='active') THEN RAISE EXCEPTION 'An active Participant is required.'; END IF;
  target_id:=public.ensure_member_contributor(substring(p_choice FROM 8)::uuid);
 ELSE RAISE EXCEPTION 'Select an existing active contributor or Participant.'; END IF;
 PERFORM 1 FROM public.contributors WHERE contributor_id=target_id AND status='active' FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'An active contributor is required.'; END IF;
 IF target_id IS NOT DISTINCT FROM donation.contributor_id THEN RAISE EXCEPTION 'Donation is already assigned to this contributor.'; END IF;
 SELECT m.member_id INTO target_member FROM public.members m JOIN public.contributors c ON c.person_id=m.person_id
 WHERE c.contributor_id=target_id AND m.status='active' ORDER BY m.created_at DESC,m.member_id LIMIT 1;
 old_contributor:=donation.contributor_id;old_member:=donation.member_id;
 UPDATE public.donations SET contributor_id=target_id,member_id=target_member,donor_kind='identified'
 WHERE donation_id=p_donation_id RETURNING * INTO donation;
 INSERT INTO public.audit_log(actor,action,entity_type,entity_id,details)
 VALUES(lower(btrim(actor.email)),'donation.reassigned','donation',p_donation_id::text,jsonb_build_object('from_contributor_id',old_contributor,'from_member_id',old_member,
  'to_contributor_id',target_id,'to_member_id',target_member,'reason',btrim(p_reason),'actor_person_id',actor.person_id));
 -- A single-transaction correction does not move provider bindings or merge identities.
 RETURN donation;
END $$;

COMMIT;
