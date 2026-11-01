-- Optional private Google Drive evidence; preserves existing NocoDB references and request receipts.
\set ON_ERROR_STOP on
BEGIN;
ALTER TABLE public.paper_agreement_upload_requests ADD COLUMN IF NOT EXISTS storage_provider text NOT NULL DEFAULT 'nocodb';
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='public.paper_agreement_upload_requests'::regclass AND conname='paper_upload_storage_provider_check') THEN
  ALTER TABLE public.paper_agreement_upload_requests ADD CONSTRAINT paper_upload_storage_provider_check CHECK(storage_provider IN ('nocodb','google_drive'));
 END IF;
END $$;
CREATE OR REPLACE FUNCTION public.application_begin_paper_upload(p_actor_email text,p_request_id uuid,p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE actor record; participant uuid; practitioner uuid; template uuid; f jsonb; content bytea; hash text; provider text;
 existing public.paper_agreement_upload_requests%ROWTYPE; inserted boolean;
BEGIN
 provider:=COALESCE(NULLIF(p_payload->>'storage_provider',''),'nocodb');
 IF provider NOT IN ('nocodb','google_drive') THEN RAISE EXCEPTION 'Unsupported paper storage provider'; END IF;
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
 INSERT INTO public.paper_agreement_upload_requests(request_id,owner_email,owner_person_id,member_id,practitioner_person_id,agreement_template_id,payload_sha256,storage_provider)
 VALUES(p_request_id,lower(btrim(p_actor_email)),actor.person_id,participant,practitioner,template,hash,provider)
 ON CONFLICT(request_id) DO NOTHING;
 inserted:=FOUND;
 SELECT * INTO STRICT existing FROM public.paper_agreement_upload_requests WHERE request_id=p_request_id FOR UPDATE;
 IF existing.owner_person_id<>actor.person_id OR existing.owner_email<>lower(btrim(p_actor_email)) OR existing.payload_sha256<>hash THEN RAISE EXCEPTION 'Paper request owner or payload conflict'; END IF;
 RETURN jsonb_build_object('request_id',p_request_id,'state',existing.status,'proceed',inserted,'storage_provider',existing.storage_provider,'member_agreement_id',existing.member_agreement_id);
END $$;

CREATE OR REPLACE FUNCTION public.application_complete_paper_upload(p_actor_email text,p_request_id uuid,p_evidence jsonb)
RETURNS jsonb LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE request public.paper_agreement_upload_requests%ROWTYPE; agreement uuid; file jsonb; provider text;
BEGIN
 SELECT * INTO STRICT request FROM public.paper_agreement_upload_requests WHERE request_id=p_request_id FOR UPDATE;
 PERFORM public.application_require_permission(p_actor_email,'participant.manage',request.member_id);
 IF request.owner_email<>lower(btrim(p_actor_email)) OR request.owner_person_id IS DISTINCT FROM (SELECT person_id FROM public.application_access(p_actor_email)) THEN RAISE EXCEPTION 'Paper request owner conflict'; END IF;
 IF request.status='committed' THEN
  IF request.evidence IS DISTINCT FROM p_evidence THEN RAISE EXCEPTION 'Paper evidence conflict'; END IF;
  RETURN jsonb_build_object('request_id',p_request_id,'state','committed','member_agreement_id',request.member_agreement_id,'storage_provider',request.storage_provider);
 END IF;
 IF request.status<>'pending_upload' THEN RAISE EXCEPTION 'Paper upload request is cancelled'; END IF;
 IF jsonb_typeof(p_evidence) IS DISTINCT FROM 'array' OR jsonb_array_length(p_evidence)<>1 THEN RAISE EXCEPTION 'One stored evidence attachment required'; END IF;
 file:=p_evidence->0;
 provider:=COALESCE(NULLIF(file->>'storage_provider',''),'nocodb');
 IF provider<>request.storage_provider THEN RAISE EXCEPTION 'Evidence storage provider differs from reserved request'; END IF;
 IF provider='google_drive' THEN
  IF length(COALESCE(file->>'drive_file_id','')) NOT BETWEEN 10 AND 200 OR (file->>'drive_file_id') !~ '^[A-Za-z0-9_-]+$'
    OR file->>'web_url' IS DISTINCT FROM ('https://drive.google.com/file/d/'||(file->>'drive_file_id')||'/view')
    OR file ? 'path' OR file ? 'signedPath' THEN RAISE EXCEPTION 'Canonical private Google Drive evidence reference required'; END IF;
 ELSIF provider='nocodb' THEN
  IF length(COALESCE(file->>'path','')) NOT BETWEEN 2 AND 1024 OR COALESCE(file->>'path','') !~ '^[A-Za-z0-9_-][A-Za-z0-9_./-]+$' OR file->>'path' LIKE '%..%' OR file->>'path' LIKE '%//%'
    OR file ? 'drive_file_id' THEN RAISE EXCEPTION 'Storage-relative NocoDB evidence path required'; END IF;
 ELSE RAISE EXCEPTION 'Unsupported paper evidence storage provider';
 END IF;
 SELECT member_agreement_id INTO STRICT agreement FROM public.issue19_create_member_agreement(p_actor_email,request.member_id,request.practitioner_person_id,request.agreement_template_id,'paper','pending_review',p_evidence,NULL);
 UPDATE public.paper_agreement_upload_requests SET status='committed',member_agreement_id=agreement,evidence=p_evidence,completed_at=now() WHERE request_id=p_request_id;
 INSERT INTO public.audit_log(actor,action,entity_type,entity_id,details)
 VALUES(lower(btrim(p_actor_email)),'member_agreement.paper_uploaded','member_agreement',agreement::text,jsonb_build_object('request_id',p_request_id,'member_id',request.member_id,'actor_person_id',request.owner_person_id,'storage_provider',request.storage_provider));
 RETURN jsonb_build_object('request_id',p_request_id,'state','committed','member_agreement_id',agreement,'storage_provider',request.storage_provider);
END $$;

COMMIT;
