-- Atomic new-party Intake and owner-scoped durable receipts. No HTTP is performed.
\set ON_ERROR_STOP on
BEGIN;
CREATE TABLE IF NOT EXISTS public.application_intake_requests (
  request_id uuid PRIMARY KEY,
  actor_person_id uuid NOT NULL REFERENCES public.people(person_id),
  payload_sha256 text NOT NULL CHECK (length(payload_sha256)=64),
  participant_enrolled boolean NOT NULL,
  contributor_enrolled boolean NOT NULL,
  result jsonb,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  completed_at timestamptz,
  CHECK ((result IS NULL) = (completed_at IS NULL))
);
REVOKE ALL ON public.application_intake_requests FROM PUBLIC;
COMMENT ON TABLE public.application_intake_requests IS
  'Private atomic Intake receipts: salted payload fingerprint and technical IDs only. Never stores form values or external delivery responses. Same key and owner replay one committed result.';

CREATE OR REPLACE FUNCTION public.application_intake_authority(
 p_actor_email text,p_participant boolean,p_contributor boolean)
RETURNS uuid LANGUAGE plpgsql SET search_path=public,pg_temp AS $intake$
DECLARE actor record;
BEGIN
 SELECT * INTO actor FROM public.application_access(p_actor_email);
 IF actor.person_id IS NULL OR NOT (COALESCE(p_participant,false) OR COALESCE(p_contributor,false)) THEN
  RAISE EXCEPTION 'Active reviewer account and enrollment capacity required';
 END IF;
 IF COALESCE(p_participant,false) THEN PERFORM public.application_require_permission(p_actor_email,'intake.participant'); END IF;
 IF COALESCE(p_contributor,false) THEN PERFORM public.application_require_permission(p_actor_email,'intake.contributor'); END IF;
 IF p_participant AND p_contributor AND NOT actor.is_directory_manager THEN
  RAISE EXCEPTION 'Dual-capacity intake requires Directory Manager and both reviewer permissions';
 END IF;
 RETURN actor.person_id;
END;
$intake$;

CREATE OR REPLACE FUNCTION public.application_intake_status(p_actor_email text,p_request_id uuid)
RETURNS jsonb LANGUAGE plpgsql SET search_path=public,pg_temp AS $intake$
DECLARE actor uuid; receipt public.application_intake_requests%ROWTYPE;
BEGIN
 PERFORM public.application_require_permission(p_actor_email,'intake');
 SELECT person_id INTO actor FROM public.application_access(p_actor_email);
 SELECT * INTO receipt FROM public.application_intake_requests
  WHERE request_id=p_request_id AND actor_person_id=actor AND result IS NOT NULL;
 IF NOT FOUND THEN RETURN NULL; END IF;
 PERFORM public.application_intake_authority(p_actor_email,receipt.participant_enrolled,receipt.contributor_enrolled);
 RETURN receipt.result;
END;
$intake$;

CREATE OR REPLACE FUNCTION public.application_submit_intake(p_actor_email text,p_request_id uuid,p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SET search_path=public,pg_temp AS $intake$
DECLARE
 actor uuid; prior public.application_intake_requests%ROWTYPE; fingerprint text; v_result jsonb;
 member_enabled boolean; contributor_enabled boolean; member_subscribe boolean; contributor_subscribe boolean;
 kind text; first_name text; last_name text; company_name text; email text; phone text; dob date;
 address text; city text; state text; postal text; notes text; reason text; field text;
 practitioner uuid; template uuid; agreement_type text; participant uuid; person uuid; organization uuid;
 contributor uuid; email_id uuid; phone_id uuid; address_id uuid; agreement uuid; created record;
BEGIN
 IF p_request_id IS NULL OR jsonb_typeof(p_payload) IS DISTINCT FROM 'object' THEN
  RAISE EXCEPTION 'Request key and Intake object required';
 END IF;
 IF EXISTS (SELECT 1 FROM jsonb_object_keys(p_payload) k WHERE k NOT IN (
  'kind','participant','contributor','first_name','last_name','company_name','email','phone','date_of_birth',
  'address','city','state','postal_code','notes','reason','participant_subscribe','contributor_subscribe',
  'agreement_delivery','agreement_type','agreement_template_id','practitioner_person_id')) THEN
  RAISE EXCEPTION 'Unknown Intake field';
 END IF;
 FOREACH field IN ARRAY ARRAY['participant','contributor','participant_subscribe','contributor_subscribe'] LOOP
  IF p_payload ? field AND jsonb_typeof(p_payload->field) IS DISTINCT FROM 'boolean' THEN
   RAISE EXCEPTION 'Enrollment and mailing choices must be explicit booleans';
  END IF;
 END LOOP;
 FOR field IN SELECT jsonb_object_keys(p_payload) LOOP
  IF field NOT IN ('participant','contributor','participant_subscribe','contributor_subscribe')
   AND jsonb_typeof(p_payload->field) NOT IN ('string','null') THEN RAISE EXCEPTION 'Intake text fields must be strings'; END IF;
 END LOOP;
 member_enabled:=COALESCE((p_payload->>'participant')::boolean,false);
 contributor_enabled:=COALESCE((p_payload->>'contributor')::boolean,false);
 actor:=public.application_intake_authority(p_actor_email,member_enabled,contributor_enabled);
 member_subscribe:=COALESCE((p_payload->>'participant_subscribe')::boolean,false);
 contributor_subscribe:=COALESCE((p_payload->>'contributor_subscribe')::boolean,false);
 fingerprint:=encode(sha256(convert_to(p_request_id::text||':'||p_payload::text,'UTF8')),'hex');
 -- A competing same-key INSERT waits for the first transaction. On a committed
 -- match return its receipt; on rollback this call can perform the one creation.
 INSERT INTO public.application_intake_requests(request_id,actor_person_id,payload_sha256,participant_enrolled,contributor_enrolled)
 VALUES(p_request_id,actor,fingerprint,member_enabled,contributor_enabled) ON CONFLICT(request_id) DO NOTHING;
 SELECT * INTO STRICT prior FROM public.application_intake_requests WHERE request_id=p_request_id FOR UPDATE;
 IF prior.actor_person_id<>actor OR prior.payload_sha256<>fingerprint THEN
  RAISE EXCEPTION 'Request key unavailable for this owner or payload';
 END IF;
 IF prior.result IS NOT NULL THEN RETURN prior.result; END IF;
 kind:=p_payload->>'kind';first_name:=NULLIF(btrim(p_payload->>'first_name'),'');last_name:=NULLIF(btrim(p_payload->>'last_name'),'');
 company_name:=NULLIF(btrim(p_payload->>'company_name'),'');email:=NULLIF(lower(btrim(p_payload->>'email')),'');phone:=NULLIF(btrim(p_payload->>'phone'),'');
 notes:=NULLIF(btrim(p_payload->>'notes'),'');reason:=NULLIF(btrim(p_payload->>'reason'),'');
 address:=NULLIF(btrim(p_payload->>'address'),'');city:=NULLIF(btrim(p_payload->>'city'),'');
 state:=NULLIF(btrim(p_payload->>'state'),'');postal:=NULLIF(btrim(p_payload->>'postal_code'),'');
 IF kind IS NULL OR kind NOT IN ('individual','organization') OR (kind='organization' AND member_enabled) THEN
  RAISE EXCEPTION 'Choose individual capacities or company Contributor intake';
 END IF;
 IF (kind='individual' AND (first_name IS NULL OR last_name IS NULL)) OR (kind='organization' AND company_name IS NULL) THEN
  RAISE EXCEPTION 'Individual first/last name or company name required';
 END IF;
 IF email IS NOT NULL AND email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' THEN RAISE EXCEPTION 'Valid email required'; END IF;
 IF phone IS NOT NULL AND COALESCE(length(public.normalize_us_phone(phone)),0)<>10 THEN RAISE EXCEPTION 'Valid US phone required'; END IF;
 IF num_nonnulls(address,city,state,postal) NOT IN (0,4) THEN RAISE EXCEPTION 'Complete mailing address required'; END IF;
 IF (email IS NOT NULL)::integer+(phone IS NOT NULL)::integer+(address IS NOT NULL)::integer<2 THEN
  RAISE EXCEPTION 'At least two contact methods required';
 END IF;
 IF contributor_enabled AND reason IS NULL THEN RAISE EXCEPTION 'Contributor enrollment reason required'; END IF;
 IF kind='individual' THEN dob:=NULLIF(p_payload->>'date_of_birth','')::date;
 ELSIF NULLIF(p_payload->>'date_of_birth','') IS NOT NULL THEN RAISE EXCEPTION 'Date of birth is an individual field'; END IF;
 IF member_enabled THEN
  IF p_payload->>'agreement_delivery' IS DISTINCT FROM 'Digital' THEN RAISE EXCEPTION 'Only validated digital Intake is enabled; paper remains blocked'; END IF;
  practitioner:=NULLIF(p_payload->>'practitioner_person_id','')::uuid;
  template:=NULLIF(p_payload->>'agreement_template_id','')::uuid;agreement_type:=NULLIF(btrim(p_payload->>'agreement_type'),'');
  IF email IS NULL OR practitioner IS NULL OR template IS NULL OR agreement_type IS NULL THEN RAISE EXCEPTION 'Digital agreement email, practitioner, type and template required'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.agreement_templates t JOIN public.agreement_types a
   ON a.type_key=agreement_type AND a.active WHERE t.agreement_template_id=template AND t.active AND agreement_type=ANY(t.required_for)) THEN
   RAISE EXCEPTION 'Active matching agreement type and template required';
  END IF;
 END IF;
 IF member_enabled THEN
  -- Shared contact matches require an existing-profile workflow, not a new identity.
  LOCK TABLE public.members,public.people,public.member_emails,public.member_phones,
   public.party_contacts IN SHARE ROW EXCLUSIVE MODE;
  IF EXISTS(SELECT 1 FROM public.party_contacts c WHERE c.status='active' AND
    ((email IS NOT NULL AND c.contact_kind='email' AND c.identity_key=email) OR
     (phone IS NOT NULL AND c.contact_kind='phone' AND c.identity_key=public.normalize_us_phone(phone)))) THEN
   RAISE EXCEPTION 'Contact already in use; review Directory before creating another identity';
  END IF;
  SELECT * INTO STRICT created FROM public.application_create_participant(p_actor_email,first_name,last_name,email,phone,dob);
  IF created.duplicate_blocked OR created.member_id IS NULL THEN RAISE EXCEPTION 'Duplicate Participant; review Directory before continuing'; END IF;
  participant:=created.member_id;
  SELECT person_id INTO STRICT person FROM public.members WHERE member_id=participant;
  IF notes IS NOT NULL THEN PERFORM public.issue19_set_party_notes(p_actor_email,'individual',person,notes,'Initial Intake'); END IF;
  IF email IS NOT NULL THEN
   INSERT INTO public.member_emails(member_id,email,is_primary,is_verified,source,notes,mailing_subscription_status,mailing_subscription_source)
    VALUES(participant,email,true,false,'intake','Created from Intake',CASE WHEN member_subscribe THEN 'subscribed' ELSE 'not_subscribed' END,'intake')
    RETURNING member_email_id INTO email_id;
  END IF;
  IF phone IS NOT NULL THEN
   INSERT INTO public.member_phones(member_id,phone,is_primary,is_verified,source,notes)
    VALUES(participant,phone,true,false,'intake','Created from Intake') RETURNING member_phone_id INTO phone_id;
  END IF;
  IF address IS NOT NULL THEN address_id:=public.issue19_add_membership_address(p_actor_email,person,address,NULL,city,state,postal,'USA','Initial Intake'); END IF;
  PERFORM public.issue19_assign_member_practitioner(p_actor_email,person,practitioner,NULL,'Initial Participant enrollment');
  IF contributor_enabled THEN
   contributor:=public.issue19_enable_person_contributor(p_actor_email,person,reason);
   IF email IS NOT NULL THEN PERFORM public.issue19_add_contributor_email_with_mailing(p_actor_email,'individual',person,email,reason,contributor_subscribe); END IF;
   IF phone_id IS NOT NULL THEN PERFORM public.issue19_assign_person_contact_role(p_actor_email,person,'member_phones',phone_id,reason); END IF;
   IF address_id IS NOT NULL THEN PERFORM public.issue19_assign_person_contact_role(p_actor_email,person,'member_addresses',address_id,reason); END IF;
   PERFORM public.application_link_capacities(p_actor_email,contributor,participant,reason);
  END IF;
  SELECT member_agreement_id INTO STRICT agreement FROM public.issue19_create_member_agreement(
   p_actor_email,participant,practitioner,template,'documenso','pending_email_send','[]'::jsonb,email_id);
 ELSE
  SELECT * INTO STRICT created FROM public.issue19_create_contributor_with_mailing(p_actor_email,kind,first_name,last_name,company_name,email,phone,reason,contributor_subscribe);
  contributor:=created.contributor_id;
  IF kind='individual' THEN
   person:=created.party_id;
   IF dob IS NOT NULL THEN UPDATE public.people SET date_of_birth=dob WHERE person_id=person; END IF;
  ELSE organization:=created.party_id; END IF;
  IF notes IS NOT NULL THEN PERFORM public.issue19_set_party_notes(p_actor_email,kind,created.party_id,notes,'Initial Intake'); END IF;
  IF address IS NOT NULL THEN PERFORM public.issue19_add_contributor_address(p_actor_email,kind,created.party_id,address,NULL,city,state,postal,'USA',reason); END IF;
 END IF;
 v_result:=jsonb_build_object('request_id',p_request_id,'state','committed','member_id',participant,'person_id',person,
  'organization_id',organization,'contributor_id',contributor,'agreement_id',agreement,
  'participant_enrolled',member_enabled,'contributor_enrolled',contributor_enabled);
 INSERT INTO public.audit_log(actor,action,entity_type,entity_id,details)
 VALUES(lower(btrim(p_actor_email)),'intake.completed',kind,COALESCE(participant,contributor)::text,
  v_result||jsonb_build_object('actor_person_id',actor,'page','Intake'));
 UPDATE public.application_intake_requests SET result=v_result,completed_at=clock_timestamp() WHERE request_id=p_request_id;
 RETURN v_result;
END;
$intake$;
COMMENT ON FUNCTION public.application_submit_intake(text,uuid,jsonb) IS
 'One atomic new-party Intake transaction, including mailing queue/audit and pending digital agreement. Same owner/key/payload replays the committed technical receipt. No external delivery is performed.';
COMMIT;
