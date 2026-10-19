-- Artificial no-email fixtures only; every change rolls back.
\set ON_ERROR_STOP on
BEGIN;
CREATE FUNCTION pg_temp.paper_denied(statement text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN BEGIN EXECUTE statement; EXCEPTION WHEN OTHERS THEN RETURN; END; RAISE EXCEPTION 'Expected denial did not occur'; END $$;
DO $$
DECLARE participant uuid; member uuid; practitioner uuid; other_practitioner uuid; reviewer uuid; outsider uuid; request uuid:=public.uuid_generate_v4();
 payload jsonb; receipt jsonb; evidence jsonb:='[{"path":"nc/uploads/synthetic-paper.pdf","title":"synthetic-paper.pdf"}]'; agreement uuid; before_count integer; failed boolean;
BEGIN
 INSERT INTO public.people(display_name) VALUES('Synthetic Paper Participant') RETURNING person_id INTO participant;
 INSERT INTO public.members(person_id) VALUES(participant) RETURNING member_id INTO member;
 INSERT INTO public.person_app_accounts(person_id,email) VALUES(participant,'paper-self@example.invalid');
 INSERT INTO public.people(display_name) VALUES('Synthetic Paper Practitioner') RETURNING person_id INTO practitioner;
 INSERT INTO public.person_app_accounts(person_id,email) VALUES(practitioner,'paper-practitioner@example.invalid');
 INSERT INTO public.person_roles(person_id,role_key,assigned_by) VALUES(practitioner,'practitioner','synthetic');
 INSERT INTO public.member_practitioner_assignments(member_id,practitioner_person_id) VALUES(member,practitioner);
 INSERT INTO public.people(display_name) VALUES('Synthetic Paper Reviewer') RETURNING person_id INTO reviewer;
 INSERT INTO public.person_app_accounts(person_id,email) VALUES(reviewer,'paper-reviewer@example.invalid');
 INSERT INTO public.person_roles(person_id,role_key,assigned_by) VALUES(reviewer,'document_reviewer','synthetic');
 INSERT INTO public.people(display_name) VALUES('Synthetic Paper Outsider') RETURNING person_id INTO outsider;
 INSERT INTO public.person_app_accounts(person_id,email) VALUES(outsider,'paper-outsider@example.invalid');
 INSERT INTO public.person_roles(person_id,role_key,assigned_by) VALUES(outsider,'practitioner','synthetic');
 payload:=jsonb_build_object('member_id',member,'practitioner_person_id',practitioner,'agreement_template_id','',
 'files',jsonb_build_array(jsonb_build_object('name','synthetic-paper.pdf','mimeType','application/pdf','data',replace(encode(convert_to('%PDF-1.4 synthetic paper','UTF8'),'base64'),E'\n',''))));
 PERFORM pg_temp.paper_denied(format('SELECT public.application_begin_paper_upload(%L,%L,%L::jsonb)','paper-self@example.invalid',request,payload));
 PERFORM pg_temp.paper_denied(format('SELECT public.application_begin_paper_upload(%L,%L,%L::jsonb)','paper-outsider@example.invalid',request,payload));
 PERFORM pg_temp.paper_denied(format('SELECT public.application_begin_paper_upload(%L,%L,%L::jsonb)','unlinked@example.invalid',request,payload));
 FOR before_count IN 1..6 LOOP
  receipt:=CASE before_count
   WHEN 1 THEN jsonb_set(payload,'{files}','[]')
   WHEN 2 THEN jsonb_set(payload,'{files,0,mimeType}','"text/html"')
   WHEN 3 THEN jsonb_set(payload,'{files,0,data}','"not-base64"')
   WHEN 4 THEN jsonb_set(payload,'{files,0,name}','"../synthetic.pdf"')
   WHEN 5 THEN jsonb_set(payload,'{files,0,data}',to_jsonb(repeat('A',6990512)))
   ELSE jsonb_set(payload,'{practitioner_person_id}',to_jsonb(outsider::text)) END;
  PERFORM pg_temp.paper_denied(format('SELECT public.application_begin_paper_upload(%L,%L,%L::jsonb)','paper-reviewer@example.invalid',request,receipt));
 END LOOP;
 IF EXISTS(SELECT 1 FROM public.paper_agreement_upload_requests WHERE request_id=request) THEN RAISE EXCEPTION 'Invalid upload reserved a request'; END IF;
 receipt:=public.application_begin_paper_upload('paper-practitioner@example.invalid',request,payload);
 IF receipt->>'state'<>'pending_upload' OR receipt->>'proceed'<>'true' THEN RAISE EXCEPTION 'Assigned practitioner could not reserve upload'; END IF;
 receipt:=public.application_begin_paper_upload('paper-practitioner@example.invalid',request,payload);
 IF receipt->>'proceed'<>'false' THEN RAISE EXCEPTION 'Duplicate request allowed another storage upload'; END IF;
 PERFORM pg_temp.paper_denied(format('SELECT public.application_begin_paper_upload(%L,%L,%L::jsonb)','paper-reviewer@example.invalid',request,payload));
 PERFORM pg_temp.paper_denied(format('SELECT public.application_begin_paper_upload(%L,%L,%L::jsonb)','paper-practitioner@example.invalid',request,jsonb_set(payload,'{files,0,name}','"other.pdf"')));
 IF public.application_paper_upload_receipt('paper-reviewer@example.invalid',request) IS NOT NULL THEN RAISE EXCEPTION 'Another owner can read receipt'; END IF;
 FOR before_count IN 1..3 LOOP
  receipt:=CASE before_count WHEN 1 THEN '[]'::jsonb WHEN 2 THEN '[{"path":"https://outside.example.invalid/file.pdf"}]'::jsonb ELSE '[{"path":"nc/../secret"}]'::jsonb END;
  PERFORM pg_temp.paper_denied(format('SELECT public.application_complete_paper_upload(%L,%L,%L::jsonb)','paper-practitioner@example.invalid',request,receipt));
 END LOOP;
 receipt:=public.application_complete_paper_upload('paper-practitioner@example.invalid',request,evidence);agreement:=(receipt->>'member_agreement_id')::uuid;
 IF receipt->>'state'<>'committed' OR NOT EXISTS(SELECT 1 FROM public.member_agreements ma WHERE ma.member_agreement_id=agreement AND ma.signature_method='paper' AND ma.status='pending_review' AND ma.member_email_id IS NULL AND jsonb_array_length(ma.evidence::jsonb)=1) THEN RAISE EXCEPTION 'Paper save requires email or bypasses review'; END IF;
 IF EXISTS(SELECT 1 FROM public.member_emails WHERE member_id=member) THEN RAISE EXCEPTION 'Paper path invented an email'; END IF;
 IF public.application_complete_paper_upload('paper-practitioner@example.invalid',request,evidence) IS DISTINCT FROM receipt THEN RAISE EXCEPTION 'Lost response replay changed receipt'; END IF;
 IF (SELECT count(*) FROM public.audit_log WHERE action='member_agreement.paper_uploaded' AND entity_id=agreement::text)<>1 THEN RAISE EXCEPTION 'Paper upload audit is not singular'; END IF;
 PERFORM pg_temp.paper_denied(format('SELECT public.application_complete_paper_upload(%L,%L,%L::jsonb)','paper-reviewer@example.invalid',request,evidence));
 PERFORM pg_temp.paper_denied(format('SELECT public.application_review_agreement(%L,%L,%L,%L)','paper-practitioner@example.invalid',agreement,'signed','Synthetic denied review'));
 PERFORM pg_temp.paper_denied(format('SELECT public.application_review_agreement(%L,%L,%L,%L)','paper-reviewer@example.invalid',agreement,'signed',' '));
 PERFORM public.application_review_agreement('paper-reviewer@example.invalid',agreement,'signed','Synthetic paper reviewed');
 IF (SELECT status FROM public.member_agreements WHERE member_agreement_id=agreement)<>'signed' THEN RAISE EXCEPTION 'Reviewer approval failed'; END IF;
 PERFORM pg_temp.paper_denied(format('SELECT public.application_review_agreement(%L,%L,%L,%L)','paper-reviewer@example.invalid',agreement,'rejected','Synthetic repeated review'));
 SELECT member_agreement_id INTO agreement FROM public.issue19_create_member_agreement('paper-reviewer@example.invalid',member,practitioner,NULL,'paper','pending_review','[]',NULL);
 PERFORM pg_temp.paper_denied(format('SELECT public.application_review_agreement(%L,%L,%L,%L)','paper-reviewer@example.invalid',agreement,'signed','Synthetic no evidence'));
END $$;
DO $$
DECLARE member uuid; practitioner uuid; request uuid:=public.uuid_generate_v4(); payload jsonb;
BEGIN
 SELECT m.member_id INTO member FROM public.members m JOIN public.person_app_accounts a USING(person_id) WHERE a.email='paper-self@example.invalid';
 SELECT person_id INTO practitioner FROM public.person_app_accounts WHERE email='paper-practitioner@example.invalid';
 payload:=jsonb_build_object('member_id',member,'practitioner_person_id',practitioner,'files',jsonb_build_array(jsonb_build_object('name','synthetic.pdf','mimeType','application/pdf','data','JVBERi0xLjQgc3ludGhldGlj')));
 PERFORM pg_temp.paper_denied(format('SELECT public.application_cancel_paper_upload(%L,%L,%L,%L,%L)','paper-self@example.invalid',request,member,practitioner,'Synthetic denied cancellation'));
 PERFORM public.application_cancel_paper_upload('paper-practitioner@example.invalid',request,member,practitioner,'Synthetic uncertain upload cancelled');
 PERFORM pg_temp.paper_denied(format('SELECT public.application_begin_paper_upload(%L,%L,%L::jsonb)','paper-practitioner@example.invalid',request,payload));
 PERFORM pg_temp.paper_denied(format('SELECT public.application_complete_paper_upload(%L,%L,%L::jsonb)','paper-practitioner@example.invalid',request,'[{"path":"nc/uploads/late.pdf"}]'));
 IF public.application_paper_upload_receipt('paper-practitioner@example.invalid',request)->>'state'<>'cancelled' THEN RAISE EXCEPTION 'Cancellation tombstone missing'; END IF;
END $$;
CREATE FUNCTION pg_temp.paper_audit_failure() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN IF NEW.action='member_agreement.paper_uploaded' THEN RAISE EXCEPTION 'Synthetic audit fault'; END IF; RETURN NEW; END $$;
CREATE TRIGGER paper_audit_failure BEFORE INSERT ON public.audit_log FOR EACH ROW EXECUTE FUNCTION pg_temp.paper_audit_failure();
DO $$
DECLARE member uuid; practitioner uuid; request uuid:=public.uuid_generate_v4(); payload jsonb; before_count integer; failed boolean:=false;
BEGIN
 SELECT m.member_id INTO member FROM public.members m JOIN public.person_app_accounts a USING(person_id) WHERE a.email='paper-self@example.invalid';
 SELECT person_id INTO practitioner FROM public.person_app_accounts WHERE email='paper-practitioner@example.invalid';
 payload:=jsonb_build_object('member_id',member,'practitioner_person_id',practitioner,'files',jsonb_build_array(jsonb_build_object('name','synthetic.pdf','mimeType','application/pdf','data','JVBERi0xLjQgc3ludGhldGlj')));
 PERFORM public.application_begin_paper_upload('paper-reviewer@example.invalid',request,payload);
 SELECT count(*) INTO before_count FROM public.member_agreements;
 BEGIN PERFORM public.application_complete_paper_upload('paper-reviewer@example.invalid',request,'[{"path":"nc/uploads/audit-fault.pdf"}]'); EXCEPTION WHEN OTHERS THEN failed:=true; END;
 IF NOT failed OR (SELECT count(*) FROM public.member_agreements)<>before_count OR (SELECT status FROM public.paper_agreement_upload_requests WHERE request_id=request)<>'pending_upload' THEN RAISE EXCEPTION 'Completion/audit fault did not roll back atomically'; END IF;
END $$;
ROLLBACK;
