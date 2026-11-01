-- Synthetic provider references only. No Google/NocoDB calls; every fixture rolls back.
\set ON_ERROR_STOP on
BEGIN;
CREATE FUNCTION pg_temp.storage_denied(statement text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN BEGIN EXECUTE statement; EXCEPTION WHEN OTHERS THEN RETURN; END; RAISE EXCEPTION 'Expected storage denial did not occur'; END $$;
DO $$
DECLARE person uuid; member uuid; practitioner uuid; reviewer uuid; payload jsonb; receipt jsonb; request uuid; agreement uuid;
 expected_evidence jsonb; prior_hash text; before_count integer;
BEGIN
 INSERT INTO public.people(display_name) VALUES('Synthetic Storage Participant') RETURNING person_id INTO person;
 INSERT INTO public.members(person_id) VALUES(person) RETURNING member_id INTO member;
 INSERT INTO public.person_app_accounts(person_id,email) VALUES(person,'storage-participant@example.invalid');
 INSERT INTO public.people(display_name) VALUES('Synthetic Storage Practitioner') RETURNING person_id INTO practitioner;
 INSERT INTO public.person_app_accounts(person_id,email) VALUES(practitioner,'storage-practitioner@example.invalid');
 INSERT INTO public.person_roles(person_id,role_key,assigned_by) VALUES(practitioner,'practitioner','synthetic');
 INSERT INTO public.member_practitioner_assignments(member_id,practitioner_person_id) VALUES(member,practitioner);
 INSERT INTO public.people(display_name) VALUES('Synthetic Storage Reviewer') RETURNING person_id INTO reviewer;
 INSERT INTO public.person_app_accounts(person_id,email) VALUES(reviewer,'storage-reviewer@example.invalid');
 INSERT INTO public.person_roles(person_id,role_key,assigned_by) VALUES(reviewer,'document_reviewer','synthetic');
 payload:=jsonb_build_object('member_id',member,'practitioner_person_id',practitioner,'files',jsonb_build_array(jsonb_build_object('name','synthetic.pdf','mimeType','application/pdf','data','JVBERi0xLjQgc3ludGhldGlj')));
 -- Older requests do not carry a provider. Preserve their fingerprint and NocoDB evidence.
 request:=public.uuid_generate_v4();receipt:=public.application_begin_paper_upload('storage-reviewer@example.invalid',request,payload);
 SELECT payload_sha256 INTO prior_hash FROM public.paper_agreement_upload_requests WHERE request_id=request;
 IF prior_hash<>encode(sha256(convert_to(payload::text,'UTF8')),'hex') OR (SELECT storage_provider FROM public.paper_agreement_upload_requests WHERE request_id=request)<>'nocodb' THEN RAISE EXCEPTION 'Legacy request fingerprint/provider changed'; END IF;
 receipt:=public.application_complete_paper_upload('storage-reviewer@example.invalid',request,'[{"path":"nc/uploads/legacy-synthetic.pdf"}]');
 agreement:=(receipt->>'member_agreement_id')::uuid;
 IF (SELECT evidence::jsonb FROM public.member_agreements WHERE member_agreement_id=agreement)<>'[{"path":"nc/uploads/legacy-synthetic.pdf"}]'::jsonb THEN RAISE EXCEPTION 'Legacy evidence rewritten'; END IF;
 -- Drive provider is part of the request identity; another provider cannot complete/replay it.
 request:=public.uuid_generate_v4();payload:=payload||'{"storage_provider":"google_drive"}'::jsonb;
 receipt:=public.application_begin_paper_upload('storage-practitioner@example.invalid',request,payload);
 IF receipt->>'storage_provider'<>'google_drive' OR receipt->>'proceed'<>'true' THEN RAISE EXCEPTION 'Drive request could not be reserved'; END IF;
 receipt:=public.application_begin_paper_upload('storage-practitioner@example.invalid',request,payload);
 IF receipt->>'proceed'<>'false' THEN RAISE EXCEPTION 'Drive reservation was duplicated'; END IF;
 PERFORM pg_temp.storage_denied(format('SELECT public.application_begin_paper_upload(%L,%L,%L::jsonb)','storage-practitioner@example.invalid',request,payload||'{"storage_provider":"nocodb"}'::jsonb));
 PERFORM pg_temp.storage_denied(format('SELECT public.application_begin_paper_upload(%L,%L,%L::jsonb)','storage-reviewer@example.invalid',public.uuid_generate_v4(),payload||'{"storage_provider":"arbitrary"}'::jsonb));
 PERFORM pg_temp.storage_denied(format('SELECT public.application_begin_paper_upload(%L,%L,%L::jsonb)','storage-participant@example.invalid',public.uuid_generate_v4(),payload));
 expected_evidence:='[{"storage_provider":"google_drive","drive_file_id":"synthetic_drive_file_01","web_url":"https://drive.google.com/file/d/synthetic_drive_file_01/view","title":"synthetic.pdf"}]'::jsonb;
 PERFORM pg_temp.storage_denied(format('SELECT public.application_complete_paper_upload(%L,%L,%L::jsonb)','storage-practitioner@example.invalid',request,'[{"path":"nc/uploads/wrong-provider.pdf"}]'));
 PERFORM pg_temp.storage_denied(format('SELECT public.application_complete_paper_upload(%L,%L,%L::jsonb)','storage-practitioner@example.invalid',request,jsonb_set(expected_evidence,'{0,web_url}','"https://outside.example.invalid/file"')));
 PERFORM pg_temp.storage_denied(format('SELECT public.application_complete_paper_upload(%L,%L,%L::jsonb)','storage-practitioner@example.invalid',request,jsonb_set(expected_evidence,'{0,drive_file_id}','"bad/id"')));
 PERFORM pg_temp.storage_denied(format('SELECT public.application_complete_paper_upload(%L,%L,%L::jsonb)','storage-practitioner@example.invalid',request,jsonb_set(expected_evidence,'{0,path}','"nc/uploads/ambiguous.pdf"')));
 receipt:=public.application_complete_paper_upload('storage-practitioner@example.invalid',request,expected_evidence);agreement:=(receipt->>'member_agreement_id')::uuid;
 IF public.application_complete_paper_upload('storage-practitioner@example.invalid',request,expected_evidence) IS DISTINCT FROM receipt THEN RAISE EXCEPTION 'Drive completion replay changed agreement'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.member_agreements ma WHERE ma.member_agreement_id=agreement AND ma.signature_method='paper' AND ma.status='pending_review' AND ma.evidence::jsonb=expected_evidence AND ma.member_email_id IS NULL) THEN RAISE EXCEPTION 'Drive evidence not saved independently of email/review'; END IF;
 IF (SELECT count(*) FROM public.audit_log WHERE action='member_agreement.paper_uploaded' AND entity_id=agreement::text AND details->>'storage_provider'='google_drive')<>1 THEN RAISE EXCEPTION 'Drive upload audit not singular'; END IF;
 PERFORM public.application_review_agreement('storage-reviewer@example.invalid',agreement,'signed','Synthetic Drive paper inspected');
 SELECT count(*) INTO before_count FROM public.member_agreements;
 request:=public.uuid_generate_v4();PERFORM public.application_begin_paper_upload('storage-practitioner@example.invalid',request,payload);
 PERFORM public.application_cancel_paper_upload('storage-practitioner@example.invalid',request,member,practitioner,'Synthetic cancelled Drive request');
 PERFORM pg_temp.storage_denied(format('SELECT public.application_complete_paper_upload(%L,%L,%L::jsonb)','storage-practitioner@example.invalid',request,expected_evidence));
 IF (SELECT count(*) FROM public.member_agreements)<>before_count THEN RAISE EXCEPTION 'Cancelled Drive upload created an agreement'; END IF;
END $$;
ROLLBACK;
