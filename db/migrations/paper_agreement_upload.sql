-- Protected paper upload receipts. Requires canonical application authorization and person agreement signers.
\set ON_ERROR_STOP on
BEGIN;
CREATE TABLE IF NOT EXISTS public.paper_agreement_upload_requests (
 request_id uuid PRIMARY KEY,
 owner_email text NOT NULL,
 owner_person_id uuid NOT NULL REFERENCES public.people(person_id),
 member_id uuid NOT NULL REFERENCES public.members(member_id),
 practitioner_person_id uuid NOT NULL REFERENCES public.people(person_id),
 agreement_template_id uuid REFERENCES public.agreement_templates(agreement_template_id),
 payload_sha256 text NOT NULL,
 status text NOT NULL DEFAULT 'pending_upload' CHECK(status IN ('pending_upload','committed','cancelled')),
 member_agreement_id uuid UNIQUE REFERENCES public.member_agreements(member_agreement_id),
 evidence jsonb,
 created_at timestamptz NOT NULL DEFAULT now(),
 completed_at timestamptz
);
REVOKE ALL ON public.paper_agreement_upload_requests FROM PUBLIC;

CREATE OR REPLACE FUNCTION public.application_begin_paper_upload(p_actor_email text,p_request_id uuid,p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE actor record; participant uuid; practitioner uuid; template uuid; f jsonb; content bytea; hash text;
 existing public.paper_agreement_upload_requests%ROWTYPE; inserted boolean;
BEGIN
 SELECT * INTO actor FROM public.application_access(p_actor_email);
 participant:=NULLIF(p_payload->>'member_id','')::uuid;
 practitioner:=NULLIF(p_payload->>'practitioner_person_id','')::uuid;
 template:=NULLIF(p_payload->>'agreement_template_id','')::uuid;
 PERFORM public.application_require_permission(p_actor_email,'participant.manage',participant);
 IF p_request_id IS NULL OR actor.person_id IS NULL OR practitioner IS NULL THEN RAISE EXCEPTION 'Request, account and practitioner required'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.member_practitioner_assignments a JOIN public.person_roles r
  ON r.person_id=a.practitioner_person_id AND r.role_key='practitioner'
  WHERE a.member_id=participant AND a.practitioner_person_id=practitioner AND a.status='active') THEN
  RAISE EXCEPTION 'Assigned practitioner required'; END IF;
 IF NOT actor.is_document_reviewer AND practitioner<>actor.person_id THEN RAISE EXCEPTION 'Document Reviewer permission required to upload on behalf of another practitioner'; END IF;
 IF template IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.agreement_templates WHERE agreement_template_id=template AND active) THEN RAISE EXCEPTION 'Active template required'; END IF;
 IF jsonb_typeof(p_payload->'files') IS DISTINCT FROM 'array' OR jsonb_array_length(p_payload->'files')<>1 THEN RAISE EXCEPTION 'Exactly one paper document required'; END IF;
 f:=p_payload->'files'->0;
 IF length(COALESCE(f->>'name','')) NOT BETWEEN 1 AND 160 OR f->>'name' ~ '[[:cntrl:]/\\]' THEN RAISE EXCEPTION 'Safe document filename required'; END IF;
 IF length(COALESCE(f->>'data','')) NOT BETWEEN 12 AND 6990508 OR (f->>'data') !~ '^[A-Za-z0-9+/]+={0,2}$' OR length(f->>'data')%4<>0 THEN RAISE EXCEPTION 'Bounded base64 content required'; END IF;
 content:=decode(f->>'data','base64');
 IF octet_length(content)>5242880 OR replace(encode(content,'base64'),E'\n','')<>f->>'data' THEN RAISE EXCEPTION 'Invalid or oversized document'; END IF;
 IF ((f->>'mimeType'='application/pdf' AND substring(content FROM 1 FOR 5)=decode('255044462d','hex')) OR
  (f->>'mimeType'='image/png' AND substring(content FROM 1 FOR 8)=decode('89504e470d0a1a0a','hex')) OR
  (f->>'mimeType'='image/jpeg' AND substring(content FROM 1 FOR 3)=decode('ffd8ff','hex'))) IS NOT TRUE THEN RAISE EXCEPTION 'PDF, PNG or JPEG content required'; END IF;
 hash:=encode(sha256(convert_to(p_payload::text,'UTF8')),'hex');
 INSERT INTO public.paper_agreement_upload_requests(request_id,owner_email,owner_person_id,member_id,practitioner_person_id,agreement_template_id,payload_sha256)
 VALUES(p_request_id,lower(btrim(p_actor_email)),actor.person_id,participant,practitioner,template,hash)
 ON CONFLICT(request_id) DO NOTHING;
 inserted:=FOUND;
 SELECT * INTO STRICT existing FROM public.paper_agreement_upload_requests WHERE request_id=p_request_id FOR UPDATE;
 IF existing.owner_person_id<>actor.person_id OR existing.owner_email<>lower(btrim(p_actor_email)) OR existing.payload_sha256<>hash THEN RAISE EXCEPTION 'Paper request owner or payload conflict'; END IF;
 RETURN jsonb_build_object('request_id',p_request_id,'state',existing.status,'proceed',inserted,'member_agreement_id',existing.member_agreement_id);
END $$;

CREATE OR REPLACE FUNCTION public.application_complete_paper_upload(p_actor_email text,p_request_id uuid,p_evidence jsonb)
RETURNS jsonb LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE request public.paper_agreement_upload_requests%ROWTYPE; agreement uuid; file jsonb;
BEGIN
 SELECT * INTO STRICT request FROM public.paper_agreement_upload_requests WHERE request_id=p_request_id FOR UPDATE;
 PERFORM public.application_require_permission(p_actor_email,'participant.manage',request.member_id);
 IF request.owner_email<>lower(btrim(p_actor_email)) OR request.owner_person_id IS DISTINCT FROM (SELECT person_id FROM public.application_access(p_actor_email)) THEN RAISE EXCEPTION 'Paper request owner conflict'; END IF;
 IF request.status='committed' THEN
  IF request.evidence IS DISTINCT FROM p_evidence THEN RAISE EXCEPTION 'Paper evidence conflict'; END IF;
  RETURN jsonb_build_object('request_id',p_request_id,'state','committed','member_agreement_id',request.member_agreement_id);
 END IF;
 IF request.status<>'pending_upload' THEN RAISE EXCEPTION 'Paper upload request is cancelled'; END IF;
 IF jsonb_typeof(p_evidence) IS DISTINCT FROM 'array' OR jsonb_array_length(p_evidence)<>1 THEN RAISE EXCEPTION 'One stored evidence attachment required'; END IF;
 file:=p_evidence->0;
 IF length(COALESCE(file->>'path','')) NOT BETWEEN 2 AND 1024 OR COALESCE(file->>'path','') !~ '^[A-Za-z0-9_-][A-Za-z0-9_./-]+$' OR file->>'path' LIKE '%..%' OR file->>'path' LIKE '%//%' THEN RAISE EXCEPTION 'Storage-relative evidence path required'; END IF;
 SELECT member_agreement_id INTO STRICT agreement FROM public.issue19_create_member_agreement(p_actor_email,request.member_id,request.practitioner_person_id,request.agreement_template_id,'paper','pending_review',p_evidence,NULL);
 UPDATE public.paper_agreement_upload_requests SET status='committed',member_agreement_id=agreement,evidence=p_evidence,completed_at=now() WHERE request_id=p_request_id;
 INSERT INTO public.audit_log(actor,action,entity_type,entity_id,details)
 VALUES(lower(btrim(p_actor_email)),'member_agreement.paper_uploaded','member_agreement',agreement::text,jsonb_build_object('request_id',p_request_id,'member_id',request.member_id,'actor_person_id',request.owner_person_id));
 RETURN jsonb_build_object('request_id',p_request_id,'state','committed','member_agreement_id',agreement);
END $$;

CREATE OR REPLACE FUNCTION public.application_paper_upload_receipt(p_actor_email text,p_request_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,pg_temp AS $$
 SELECT jsonb_build_object('request_id',r.request_id,'state',r.status,'member_agreement_id',r.member_agreement_id)
 FROM public.paper_agreement_upload_requests r JOIN public.application_access(p_actor_email) a ON a.person_id=r.owner_person_id
 WHERE r.request_id=p_request_id AND r.owner_email=lower(btrim(p_actor_email)) AND public.application_member_access(p_actor_email,r.member_id,true);
$$;

CREATE OR REPLACE FUNCTION public.application_cancel_paper_upload(p_actor_email text,p_request_id uuid,p_member_id uuid,p_practitioner_id uuid,p_reason text)
RETURNS jsonb LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE actor record; request public.paper_agreement_upload_requests%ROWTYPE;
BEGIN
 PERFORM public.application_require_permission(p_actor_email,'participant.manage',p_member_id);
 SELECT * INTO actor FROM public.application_access(p_actor_email);
 IF p_request_id IS NULL OR p_practitioner_id IS NULL OR NULLIF(btrim(p_reason),'') IS NULL THEN RAISE EXCEPTION 'Request, practitioner and cancellation reason required'; END IF;
 -- A tombstone also prevents a delayed first begin call from starting storage work.
 INSERT INTO public.paper_agreement_upload_requests(request_id,owner_email,owner_person_id,member_id,practitioner_person_id,payload_sha256,status)
 VALUES(p_request_id,lower(btrim(p_actor_email)),actor.person_id,p_member_id,p_practitioner_id,'cancelled','cancelled') ON CONFLICT(request_id) DO NOTHING;
 SELECT * INTO STRICT request FROM public.paper_agreement_upload_requests WHERE request_id=p_request_id FOR UPDATE;
 IF request.owner_email<>lower(btrim(p_actor_email)) OR request.owner_person_id<>actor.person_id OR request.member_id<>p_member_id THEN RAISE EXCEPTION 'Paper request owner or Participant conflict'; END IF;
 IF request.status='committed' THEN RAISE EXCEPTION 'A committed paper agreement cannot be cancelled through upload recovery'; END IF;
 IF request.status<>'cancelled' THEN UPDATE public.paper_agreement_upload_requests SET status='cancelled' WHERE request_id=p_request_id; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.audit_log WHERE action='member_agreement.paper_upload_cancelled' AND entity_id=p_request_id::text) THEN
 INSERT INTO public.audit_log(actor,action,entity_type,entity_id,details) VALUES(lower(btrim(p_actor_email)),'member_agreement.paper_upload_cancelled','paper_upload_request',p_request_id::text,jsonb_build_object('member_id',p_member_id,'actor_person_id',actor.person_id,'reason',btrim(p_reason)));
 END IF;
 RETURN jsonb_build_object('request_id',p_request_id,'state','cancelled');
END $$;

-- Approval must follow stored paper evidence; upload alone never signs an agreement.
CREATE OR REPLACE FUNCTION public.application_review_agreement(p_actor_email text,p_agreement_id uuid,p_status text,p_reason text)
RETURNS uuid LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE a record; agreement public.member_agreements%ROWTYPE; BEGIN
 SELECT * INTO STRICT agreement FROM public.member_agreements WHERE member_agreement_id=p_agreement_id FOR UPDATE;
 PERFORM public.application_require_permission(p_actor_email,'participant.review',agreement.member_id);
 IF p_status NOT IN ('signed','rejected') OR NULLIF(btrim(p_reason),'') IS NULL THEN RAISE EXCEPTION 'Reviewed status and reason required'; END IF;
 IF agreement.signature_method='paper' AND (agreement.status<>'pending_review' OR
  jsonb_typeof(agreement.evidence::jsonb) IS DISTINCT FROM 'array' OR jsonb_array_length(agreement.evidence::jsonb)=0) THEN RAISE EXCEPTION 'Pending paper agreement with stored evidence required'; END IF;
 SELECT * INTO a FROM public.application_access(p_actor_email);
 UPDATE public.member_agreements SET status=p_status,reviewer_id=a.member_id,reviewed_at=now(),review_notes=btrim(p_reason) WHERE member_agreement_id=p_agreement_id;
 INSERT INTO public.audit_log(actor,action,entity_type,entity_id,details)
 VALUES(lower(btrim(p_actor_email)),'member_agreement.'||p_status,'member_agreement',p_agreement_id::text,jsonb_build_object('member_id',agreement.member_id,'actor_person_id',a.person_id,'reason',btrim(p_reason)));
 RETURN p_agreement_id;
END $$;
COMMIT;
