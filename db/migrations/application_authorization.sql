-- Canonical account authorization. No role is inferred or granted from legacy flags.
\set ON_ERROR_STOP on
BEGIN;

CREATE OR REPLACE FUNCTION public.application_access(p_actor_email text)
RETURNS TABLE(person_id uuid,member_id uuid,email text,first_name text,last_name text,
 is_document_reviewer boolean,is_donations_reviewer boolean,is_practitioner boolean,
 is_directory_manager boolean,can_intake boolean,can_cash_deposits boolean,
 can_contributor_functions boolean,can_member_functions boolean,
 can_practitioner_admin boolean,can_release boolean)
LANGUAGE sql STABLE SET search_path=public,pg_temp AS $$
SELECT a.person_id,m.member_id,a.email,p.first_name,p.last_name,
 public.issue19_has_role(p_actor_email,'document_reviewer'),
 public.issue19_has_role(p_actor_email,'donations_reviewer'),
 public.issue19_has_role(p_actor_email,'practitioner'),
 public.issue19_has_role(p_actor_email,'directory_manager'),
 public.issue19_has_role(p_actor_email,'document_reviewer') OR public.issue19_has_role(p_actor_email,'donations_reviewer'),
 public.issue19_has_role(p_actor_email,'donations_reviewer'),
 public.issue19_has_role(p_actor_email,'document_reviewer') OR public.issue19_has_role(p_actor_email,'donations_reviewer') OR public.issue19_has_role(p_actor_email,'practitioner'),
 m.member_id IS NOT NULL OR public.issue19_has_role(p_actor_email,'document_reviewer') OR public.issue19_has_role(p_actor_email,'practitioner'),
 public.issue19_has_role(p_actor_email,'document_reviewer'),
 public.issue19_has_role(p_actor_email,'practitioner')
FROM public.person_app_accounts a JOIN public.people p USING(person_id)
LEFT JOIN LATERAL (SELECT member_id FROM public.members
 WHERE person_id=a.person_id AND status='active' ORDER BY created_at DESC,member_id LIMIT 1) m ON true
WHERE a.email_normalized=lower(btrim(p_actor_email)) AND a.status='active';
$$;

CREATE OR REPLACE FUNCTION public.application_member_access(p_actor_email text,p_member_id uuid,p_write boolean DEFAULT false)
RETURNS boolean LANGUAGE sql STABLE SET search_path=public,pg_temp AS $$
SELECT EXISTS(SELECT 1 FROM public.application_access(p_actor_email) a
 JOIN public.members m ON m.member_id=p_member_id AND m.status='active'
 WHERE a.is_document_reviewer OR
 (a.is_practitioner AND EXISTS(SELECT 1 FROM public.member_practitioner_assignments assignment
  WHERE assignment.member_id=m.member_id AND assignment.practitioner_person_id=a.person_id AND assignment.status='active'))
 OR (NOT p_write AND m.person_id=a.person_id));
$$;

CREATE OR REPLACE FUNCTION public.application_require_permission(p_actor_email text,p_permission text,p_member_id uuid DEFAULT NULL)
RETURNS boolean LANGUAGE plpgsql VOLATILE SET search_path=public,pg_temp AS $$
DECLARE a record; allowed boolean;
BEGIN
 SELECT * INTO a FROM public.application_access(p_actor_email);
 IF a.person_id IS NULL THEN RAISE EXCEPTION 'Active canonical application account required'; END IF;
 allowed:=CASE p_permission
  WHEN 'intake' THEN a.can_intake
  WHEN 'intake.participant' THEN a.is_document_reviewer
  WHEN 'intake.contributor' THEN a.is_donations_reviewer
  WHEN 'participant.read' THEN public.application_member_access(p_actor_email,p_member_id,false)
  WHEN 'participant.manage' THEN public.application_member_access(p_actor_email,p_member_id,true)
  WHEN 'participant.review' THEN a.is_document_reviewer AND public.application_member_access(p_actor_email,p_member_id,true)
  WHEN 'practitioners.manage' THEN a.can_practitioner_admin
  WHEN 'contributions.read' THEN a.can_contributor_functions
  WHEN 'contributions.review' THEN a.is_donations_reviewer
  WHEN 'cash_deposits' THEN a.can_cash_deposits
  WHEN 'release' THEN a.can_release
  ELSE false END;
 IF NOT COALESCE(allowed,false) THEN RAISE EXCEPTION 'Permission denied: %',p_permission; END IF;
 RETURN true;
END;
$$;

-- Stable legacy actor UUIDs remain valid references; new staff need no Participant record.
CREATE TABLE IF NOT EXISTS public.application_actor_references(
 actor_id uuid PRIMARY KEY,person_id uuid NOT NULL REFERENCES public.people(person_id));
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM public.members m JOIN public.people p ON p.person_id=m.member_id
  WHERE m.person_id<>p.person_id) THEN RAISE EXCEPTION 'Conflicting legacy/canonical actor UUID'; END IF;
END $$;
INSERT INTO public.application_actor_references SELECT member_id,person_id FROM public.members ON CONFLICT DO NOTHING;
CREATE OR REPLACE FUNCTION public.sync_application_actor_reference()
RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE prior_person uuid; BEGIN
 IF TG_OP='UPDATE' THEN prior_person:=OLD.person_id; END IF;
 IF EXISTS(SELECT 1 FROM public.application_actor_references WHERE actor_id=NEW.member_id AND person_id<>NEW.person_id AND person_id IS DISTINCT FROM prior_person) THEN RAISE EXCEPTION 'Conflicting actor identity reference'; END IF;
 INSERT INTO public.application_actor_references(actor_id,person_id) VALUES(NEW.member_id,NEW.person_id)
 ON CONFLICT(actor_id) DO UPDATE SET person_id=EXCLUDED.person_id;
 RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_members_actor_reference ON public.members;
CREATE TRIGGER trg_members_actor_reference AFTER INSERT OR UPDATE OF person_id ON public.members
 FOR EACH ROW EXECUTE FUNCTION public.sync_application_actor_reference();
DO $$ DECLARE c record; definition text; BEGIN
 FOR c IN SELECT con.oid,con.conname,t.relname FROM pg_constraint con
  JOIN pg_class t ON t.oid=con.conrelid JOIN pg_namespace n ON n.oid=t.relnamespace
  WHERE n.nspname='public' AND t.relname IN ('cash_deposit_batches','cash_deposit_batch_items','cash_deposit_donation_exclusions')
   AND con.contype='f' AND con.confrelid='public.members'::regclass
 LOOP
  definition:=regexp_replace(pg_get_constraintdef(c.oid),'REFERENCES (public\.)?members\(member_id\)',
   'REFERENCES public.application_actor_references(actor_id)');
  IF definition=pg_get_constraintdef(c.oid) THEN RAISE EXCEPTION 'Unsupported actor reference constraint'; END IF;
  EXECUTE format('ALTER TABLE public.%I DROP CONSTRAINT %I',c.relname,c.conname);
  EXECUTE format('ALTER TABLE public.%I ADD CONSTRAINT %I %s',c.relname,c.conname,definition);
 END LOOP;
END $$;

CREATE OR REPLACE FUNCTION public.application_actor_email(p_actor_id uuid)
RETURNS text LANGUAGE sql STABLE SET search_path=public,pg_temp AS $$
WITH identities AS (
 SELECT person_id FROM public.application_actor_references WHERE actor_id=p_actor_id
 UNION SELECT person_id FROM public.members WHERE member_id=p_actor_id
 UNION SELECT person_id FROM public.people WHERE person_id=p_actor_id
)
SELECT a.email FROM public.person_app_accounts a JOIN identities i USING(person_id)
 WHERE a.status='active' AND (SELECT count(*) FROM identities)=1
 ORDER BY a.created_at,a.email LIMIT 1;
$$;
CREATE OR REPLACE FUNCTION public.application_cash_actor_id(p_actor_email text)
RETURNS uuid LANGUAGE plpgsql VOLATILE SET search_path=public,pg_temp AS $$
DECLARE id uuid; BEGIN
 PERFORM public.application_require_permission(p_actor_email,'cash_deposits');
 SELECT person_id INTO STRICT id FROM public.application_access(p_actor_email);
 INSERT INTO public.application_actor_references VALUES(id,id) ON CONFLICT DO NOTHING;
 RETURN id;
END $$;
CREATE OR REPLACE FUNCTION public.can_view_donation_financials(p_member_id uuid)
RETURNS boolean LANGUAGE sql STABLE SET search_path=public,pg_temp AS $$
SELECT public.issue19_has_role(public.application_actor_email(p_member_id),'donations_reviewer');
$$;
CREATE OR REPLACE FUNCTION public.cash_deposit_actor_email(p_member_id uuid)
RETURNS text LANGUAGE sql STABLE SET search_path=public,pg_temp AS $$
SELECT COALESCE(public.application_actor_email(p_member_id),p_member_id::text);
$$;
CREATE OR REPLACE FUNCTION public.assert_cash_deposit_preparer(p_member_id uuid)
RETURNS void LANGUAGE plpgsql STABLE SET search_path=public,pg_temp AS $$
BEGIN IF NOT public.can_view_donation_financials(p_member_id) THEN
 RAISE EXCEPTION 'An active donations reviewer is required as cash-deposit verifier.'; END IF; END $$;
CREATE OR REPLACE FUNCTION public.assert_cash_deposit_verifier(p_member_id uuid)
RETURNS void LANGUAGE plpgsql STABLE SET search_path=public,pg_temp AS $$
BEGIN IF NOT public.can_view_donation_financials(p_member_id) THEN
 RAISE EXCEPTION 'An active donations reviewer is required as cash-deposit verifier.'; END IF; END $$;

CREATE OR REPLACE VIEW public.application_actor_profiles AS
SELECT r.actor_id AS member_id,p.person_id,p.first_name,p.last_name,
 COALESCE(a.email,m.email) AS email
FROM public.application_actor_references r JOIN public.people p ON p.person_id=r.person_id
LEFT JOIN LATERAL(SELECT email FROM public.person_app_accounts WHERE person_id=r.person_id
 ORDER BY (status='active') DESC,created_at DESC,email LIMIT 1) a ON true
LEFT JOIN public.members m ON m.member_id=r.actor_id;

CREATE OR REPLACE FUNCTION public.application_create_participant(p_actor_email text,p_first_name text,p_last_name text,
 p_email text,p_phone text,p_date_of_birth date DEFAULT NULL)
RETURNS TABLE(member_id uuid,duplicate_blocked boolean)
LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE a record; r record; BEGIN
 PERFORM public.application_require_permission(p_actor_email,'intake.participant');
 SELECT * INTO a FROM public.application_access(p_actor_email);
 SELECT * INTO r FROM public.create_member_from_intake(p_first_name,p_last_name,p_email,p_phone,p_date_of_birth,NULL,false,a.member_id);
 IF r.member_id IS NOT NULL THEN
  INSERT INTO public.audit_log(actor,action,entity_type,entity_id,details)
  VALUES(lower(btrim(p_actor_email)),'member.created','member',r.member_id::text,jsonb_build_object('actor_person_id',a.person_id));
 END IF;
 RETURN QUERY SELECT r.member_id,r.duplicate_blocked;
END $$;

CREATE OR REPLACE FUNCTION public.application_record_cash(p_actor_email text,p_choice text,p_is_anonymous boolean,
 p_amount_cents integer,p_donated_at timestamptz,p_notes text)
RETURNS public.donations LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE a record; c record; participant uuid; contributor uuid; result public.donations%ROWTYPE;
BEGIN
 SELECT * INTO a FROM public.application_access(p_actor_email);
 IF a.person_id IS NULL OR NOT a.can_contributor_functions THEN RAISE EXCEPTION 'Cash entry requires reviewer or assigned practitioner permission'; END IF;
 IF p_amount_cents IS NULL OR p_amount_cents<=0 THEN RAISE EXCEPTION 'Positive cash amount required'; END IF;
 IF COALESCE(p_is_anonymous,false) THEN
  IF p_choice IS DISTINCT FROM '__anonymous__' OR NOT(a.is_document_reviewer OR a.is_donations_reviewer) THEN RAISE EXCEPTION 'Anonymous cash requires reviewer permission and explicit anonymous selection'; END IF;
 ELSIF p_choice LIKE 'member:%' THEN
  participant:=substring(p_choice FROM 8)::uuid;
  IF NOT a.is_donations_reviewer AND NOT public.application_member_access(p_actor_email,participant,true) THEN RAISE EXCEPTION 'Participant outside permitted cash-entry scope'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.members WHERE member_id=participant AND status='active') THEN RAISE EXCEPTION 'Active Participant required'; END IF;
  contributor:=public.ensure_member_contributor(participant);
 ELSIF p_choice LIKE 'contributor:%' THEN
  contributor:=substring(p_choice FROM 13)::uuid;
  SELECT * INTO c FROM public.contributors WHERE contributor_id=contributor AND status='active';
  IF NOT FOUND THEN RAISE EXCEPTION 'Active Contributor required'; END IF;
  SELECT member_id INTO participant FROM public.members WHERE person_id=c.person_id AND status='active' ORDER BY created_at DESC LIMIT 1;
  IF NOT a.is_donations_reviewer AND NOT public.application_member_access(p_actor_email,participant,true) THEN RAISE EXCEPTION 'Contributor outside permitted cash-entry scope'; END IF;
 ELSE RAISE EXCEPTION 'Select an existing Contributor, Participant, or Anonymous'; END IF;
 INSERT INTO public.donations(contributor_id,member_id,donor_kind,provider,amount_cents,currency,donated_at,notes,status,facilitator_id)
 VALUES(contributor,participant,CASE WHEN COALESCE(p_is_anonymous,false) THEN 'anonymous' ELSE 'identified' END,
  'cash',p_amount_cents,'USD',COALESCE(p_donated_at,now()),NULLIF(btrim(p_notes),''),'pending_review',a.member_id)
 RETURNING * INTO result;
 INSERT INTO public.audit_log(actor,action,entity_type,entity_id,details)
 VALUES(lower(btrim(p_actor_email)),'donation.cash.created','donation',result.donation_id::text,
  jsonb_build_object('actor_person_id',a.person_id,'member_id',participant,'contributor_id',contributor,'donor_kind',result.donor_kind));
 RETURN result;
END $$;

-- Legacy cash entry contracts delegate to the same canonical policy.
CREATE OR REPLACE FUNCTION public.record_cash_donation_identity(p_choice text,p_is_anonymous boolean,p_amount_cents integer,p_donated_at timestamptz,p_notes text,p_facilitator_id uuid)
RETURNS public.donations LANGUAGE plpgsql SET search_path=public,pg_temp AS $$ BEGIN
 RETURN public.application_record_cash(public.application_actor_email(p_facilitator_id),p_choice,p_is_anonymous,p_amount_cents,p_donated_at,p_notes);
END $$;
CREATE OR REPLACE FUNCTION public.record_cash_donation_for_contributor(p_contributor_id uuid,p_is_anonymous boolean,p_amount_cents integer,p_donated_at timestamptz,p_notes text,p_facilitator_id uuid)
RETURNS public.donations LANGUAGE plpgsql SET search_path=public,pg_temp AS $$ BEGIN
 RETURN public.application_record_cash(public.application_actor_email(p_facilitator_id),
 CASE WHEN p_is_anonymous THEN '__anonymous__' ELSE 'contributor:'||p_contributor_id::text END,p_is_anonymous,p_amount_cents,p_donated_at,p_notes);
END $$;
CREATE OR REPLACE FUNCTION public.record_cash_donation(p_member_id uuid,p_is_anonymous boolean,p_amount_cents integer,p_donated_at timestamptz,p_notes text,p_facilitator_id uuid)
RETURNS public.donations LANGUAGE plpgsql SET search_path=public,pg_temp AS $$ BEGIN
 RETURN public.application_record_cash(public.application_actor_email(p_facilitator_id),
 CASE WHEN p_is_anonymous THEN '__anonymous__' ELSE 'member:'||p_member_id::text END,p_is_anonymous,p_amount_cents,p_donated_at,p_notes);
END $$;

CREATE OR REPLACE VIEW public.cash_deposit_batch_tally AS
SELECT
  b.deposit_batch_id,
  b.status,
  b.created_at AS batch_created_at,
  b.updated_at AS batch_updated_at,
  b.deposit_date,
  b.deposit_slip_number,
  b.destination_bank_account,
  b.preparer_id,
  prep.email AS preparer_email,
  b.prepared_by,
  b.prepared_at,
  b.verifier_id,
  ver.email AS verifier_email,
  b.confirmed_at,
  b.cancelled_at,
  b.cancelled_by,
  b.expected_amount_cents,
  b.actual_amount_cents,
  count(i.deposit_batch_item_id) OVER (
    PARTITION BY b.deposit_batch_id
  ) AS item_count,
  COALESCE(
    sum(i.amount_cents) OVER (
      PARTITION BY b.deposit_batch_id
    ),
    0
  ) AS item_total_cents,
  i.deposit_batch_item_id,
  i.created_at AS item_created_at,
  i.donation_id,
  i.amount_cents AS item_amount_cents,
  d.donated_at,
  d.currency,
  d.donor_kind,
  d.member_id,
  d.contributor_id,
  d.notes AS donation_notes
FROM public.cash_deposit_batches b
LEFT JOIN public.cash_deposit_batch_items i
  ON i.deposit_batch_id = b.deposit_batch_id
 AND i.removed_at IS NULL
LEFT JOIN public.application_actor_profiles prep
  ON prep.member_id = b.preparer_id
LEFT JOIN public.application_actor_profiles ver
  ON ver.member_id = b.verifier_id
LEFT JOIN public.donations d
  ON d.donation_id = i.donation_id;

CREATE OR REPLACE VIEW public.cash_deposit_batch_print AS
SELECT
  b.deposit_batch_id,
  b.status,
  b.created_at AS batch_created_at,
  b.updated_at AS batch_updated_at,
  b.deposit_date,
  b.deposit_slip_number,
  b.destination_bank_account,
  b.preparer_id,
  prep.email AS preparer_email,
  b.prepared_by,
  b.prepared_at,
  b.verifier_id,
  ver.email AS verifier_email,
  b.confirmed_at,
  b.cancelled_at,
  b.cancelled_by,
  b.expected_amount_cents,
  b.actual_amount_cents,
  b.notes AS batch_notes,
  i.deposit_batch_item_id,
  i.created_at AS item_added_at,
  i.donation_id,
  i.amount_cents AS item_amount_cents,
  d.donated_at,
  d.currency,
  d.donor_kind,
  d.provider_reference,
  d.notes AS donation_notes,
  d.review_notes,
  cp.display_name AS donor_name,
  cp.first_name AS donor_first_name,
  cp.last_name AS donor_last_name,
  cp.organization_name AS donor_organization_name
FROM public.cash_deposit_batches b
JOIN public.cash_deposit_batch_items i
  ON i.deposit_batch_id = b.deposit_batch_id
 AND i.removed_at IS NULL
JOIN public.donations d
  ON d.donation_id = i.donation_id
LEFT JOIN public.contributor_profiles cp
  ON cp.contributor_id = d.contributor_id
LEFT JOIN public.application_actor_profiles prep
  ON prep.member_id = b.preparer_id
LEFT JOIN public.application_actor_profiles ver
  ON ver.member_id = b.verifier_id
WHERE b.status IN ('prepared', 'confirmed');

CREATE OR REPLACE FUNCTION public.application_review_donation(p_actor_email text,p_donation_id uuid,p_new_status text,p_review_notes text DEFAULT NULL::text) RETURNS public.donations
    LANGUAGE plpgsql
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_donation public.donations%ROWTYPE;
  p_reviewer_id uuid;
BEGIN
  PERFORM public.application_require_permission(p_actor_email,'contributions.review');
  SELECT member_id INTO p_reviewer_id FROM public.application_access(p_actor_email);

  SELECT * INTO v_donation
  FROM public.donations d
  WHERE d.donation_id = p_donation_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Donation % was not found.', p_donation_id;
  END IF;

  IF v_donation.status <> 'pending_review' THEN
    RAISE EXCEPTION 'Donation % is %, not pending_review.', p_donation_id, v_donation.status;
  END IF;

  IF v_donation.provider = 'cash' THEN
    IF v_donation.donor_kind NOT IN ('identified', 'anonymous') THEN
      RAISE EXCEPTION 'Cash donation % has invalid donor identity.', p_donation_id;
    END IF;
    IF v_donation.amount_cents IS NULL OR v_donation.amount_cents <= 0 THEN
      RAISE EXCEPTION 'Cash donation % must have a positive amount.', p_donation_id;
    END IF;
    IF p_new_status IS NULL OR p_new_status NOT IN ('verified', 'rejected') THEN
      RAISE EXCEPTION 'Cash review status must be verified or rejected.';
    END IF;
  ELSE
    IF v_donation.donor_kind <> 'unresolved'
      OR v_donation.contributor_id IS NOT NULL
      OR v_donation.member_id IS NOT NULL
      OR p_new_status IS DISTINCT FROM 'ignored'
    THEN
      RAISE EXCEPTION 'Only unresolved provider donations may be ignored through this action.';
    END IF;
  END IF;

  UPDATE public.donations
  SET
    status = p_new_status,
    reviewer_id = p_reviewer_id,
    reviewed_at = now(),
    review_notes = NULLIF(btrim(p_review_notes), '')
  WHERE donation_id = p_donation_id
  RETURNING * INTO v_donation;

  INSERT INTO public.audit_log(actor,action,entity_type,entity_id,details)
  VALUES(lower(btrim(p_actor_email)),'donation.'||p_new_status,'donation',p_donation_id::text,
   jsonb_build_object('actor_person_id',(SELECT person_id FROM public.application_access(p_actor_email)),'status',p_new_status));
  RETURN v_donation;
END;
$$;
CREATE OR REPLACE FUNCTION public.review_pending_donation(p_donation_id uuid,p_reviewer_id uuid,p_new_status text,p_review_notes text DEFAULT NULL)
RETURNS public.donations LANGUAGE plpgsql SET search_path=public,pg_temp AS $$ BEGIN
 RETURN public.application_review_donation(public.application_actor_email(p_reviewer_id),p_donation_id,p_new_status,p_review_notes);
END $$;

CREATE OR REPLACE FUNCTION public.application_link_capacities(p_actor_email text,p_contributor_id uuid,p_member_id uuid,p_reason text)
RETURNS uuid LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE a record; id uuid; BEGIN
 SELECT * INTO a FROM public.application_access(p_actor_email);
 IF NOT(a.is_document_reviewer AND a.is_donations_reviewer AND a.is_directory_manager) THEN RAISE EXCEPTION 'Capacity linking requires all three administration permissions'; END IF;
 IF NULLIF(btrim(p_reason),'') IS NULL OR NOT EXISTS(SELECT 1 FROM public.contributors c JOIN public.members m ON m.person_id=c.person_id
  WHERE c.contributor_id=p_contributor_id AND m.member_id=p_member_id AND c.status='active' AND m.status='active') THEN RAISE EXCEPTION 'Same canonical identity, active capacities and reason required'; END IF;
 SELECT contributor_member_link_id INTO id FROM public.contributor_member_links WHERE contributor_id=p_contributor_id AND member_id=p_member_id AND status='active';
 IF id IS NOT NULL THEN RETURN id; END IF;
 INSERT INTO public.contributor_member_links(contributor_id,member_id,linked_by,link_reason)
 VALUES(p_contributor_id,p_member_id,a.member_id,btrim(p_reason)) RETURNING contributor_member_link_id INTO id;
 INSERT INTO public.audit_log(actor,action,entity_type,entity_id,details)
 VALUES(lower(btrim(p_actor_email)),'contributor.member_linked','contributor_member_link',id::text,jsonb_build_object('actor_person_id',a.person_id,'reason',btrim(p_reason)));
 RETURN id;
END $$;

CREATE OR REPLACE FUNCTION public.application_review_agreement(p_actor_email text,p_agreement_id uuid,p_status text,p_reason text)
RETURNS uuid LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE a record; participant uuid; BEGIN
 SELECT member_id INTO participant FROM public.member_agreements WHERE member_agreement_id=p_agreement_id FOR UPDATE;
 PERFORM public.application_require_permission(p_actor_email,'participant.review',participant);
 IF p_status NOT IN ('signed','rejected') OR NULLIF(btrim(p_reason),'') IS NULL THEN RAISE EXCEPTION 'Reviewed status and reason required'; END IF;
 SELECT * INTO a FROM public.application_access(p_actor_email);
 UPDATE public.member_agreements SET status=p_status,reviewer_id=a.member_id,reviewed_at=now(),review_notes=btrim(p_reason) WHERE member_agreement_id=p_agreement_id;
 INSERT INTO public.audit_log(actor,action,entity_type,entity_id,details)
 VALUES(lower(btrim(p_actor_email)),'member_agreement.'||p_status,'member_agreement',p_agreement_id::text,jsonb_build_object('member_id',participant,'actor_person_id',a.person_id,'reason',btrim(p_reason)));
 RETURN p_agreement_id;
END $$;
COMMIT;
