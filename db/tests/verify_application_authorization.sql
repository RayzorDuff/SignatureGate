-- Artificial fixtures only; no operational rows are printed or retained.
\set ON_ERROR_STOP on
BEGIN;
CREATE FUNCTION pg_temp.auth_actor(p_label text,p_roles text[],p_participant boolean DEFAULT false)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE id uuid; BEGIN
 INSERT INTO public.people(display_name,first_name,last_name) VALUES('Synthetic Auth '||p_label,'Synthetic',p_label) RETURNING person_id INTO id;
 INSERT INTO public.person_app_accounts(person_id,email) VALUES(id,'auth-'||p_label||'@example.invalid');
 IF p_participant THEN INSERT INTO public.members(person_id,email,is_facilitator,is_document_reviewer,is_donations_reviewer)
 VALUES(id,'auth-'||p_label||'@example.invalid',true,true,true); END IF;
 INSERT INTO public.person_roles(person_id,role_key,assigned_by) SELECT id,role,'synthetic_authorization_test' FROM unnest(p_roles) role;
 RETURN id;
END $$;
DO $$
DECLARE participant uuid; target uuid; outsider uuid; doc uuid; donor uuid; practitioner uuid; manager uuid;
 member uuid; other_member uuid; a record; donation public.donations%ROWTYPE; batch public.cash_deposit_batches%ROWTYPE;
 before_count integer; denied boolean; actor uuid; company uuid; company_contributor uuid;
BEGIN
 participant:=pg_temp.auth_actor('participant',ARRAY[]::text[],true);
 doc:=pg_temp.auth_actor('documents',ARRAY['document_reviewer']);
 donor:=pg_temp.auth_actor('donations',ARRAY['donations_reviewer']);
 practitioner:=pg_temp.auth_actor('practitioner',ARRAY['practitioner']);
 manager:=pg_temp.auth_actor('manager',ARRAY['directory_manager']);
 outsider:=pg_temp.auth_actor('outsider',ARRAY[]::text[]);
 SELECT member_id INTO member FROM public.members WHERE person_id=participant;
 INSERT INTO public.people(display_name) VALUES('Synthetic Unassigned Identity') RETURNING person_id INTO target;
 INSERT INTO public.members(person_id) VALUES(target) RETURNING member_id INTO other_member;
 SELECT * INTO a FROM public.application_access('auth-participant@example.invalid');
 IF NOT a.can_member_functions OR a.can_intake OR a.can_cash_deposits OR a.can_contributor_functions OR a.can_release OR a.is_document_reviewer OR a.is_donations_reviewer
 THEN RAISE EXCEPTION 'Participant capacity/legacy flags granted staff permission'; END IF;
 IF NOT public.application_member_access(a.email,member,false) OR public.application_member_access(a.email,member,true) OR public.application_member_access(a.email,other_member,false)
 THEN RAISE EXCEPTION 'Participant self-only read scope failed'; END IF;
 IF public.can_view_donation_financials(member) THEN RAISE EXCEPTION 'Legacy flags exposed financial data'; END IF;
 SELECT * INTO a FROM public.application_access('auth-documents@example.invalid');
 IF a.member_id IS NOT NULL OR NOT a.can_intake OR NOT a.can_member_functions OR NOT a.can_practitioner_admin OR a.can_release OR a.can_cash_deposits THEN RAISE EXCEPTION 'Canonical document reviewer boundary failed'; END IF;
 IF NOT public.application_member_access(a.email,other_member,true) THEN RAISE EXCEPTION 'Document reviewer cannot reach Participant'; END IF;
 SELECT * INTO a FROM public.application_access('auth-donations@example.invalid');
 IF a.member_id IS NOT NULL OR NOT a.can_cash_deposits OR a.can_member_functions OR a.can_release THEN RAISE EXCEPTION 'Canonical Donations Reviewer boundary failed'; END IF;
 SELECT * INTO a FROM public.application_access('auth-manager@example.invalid');
 IF a.can_intake OR a.can_cash_deposits OR a.can_release OR a.can_practitioner_admin THEN RAISE EXCEPTION 'Directory permission implies an operational role'; END IF;
 SELECT * INTO a FROM public.application_access('auth-practitioner@example.invalid');
 IF NOT a.can_release OR a.can_intake OR a.can_cash_deposits OR public.application_member_access(a.email,member,true) THEN RAISE EXCEPTION 'Unassigned practitioner scope failed'; END IF;
 INSERT INTO public.member_practitioner_assignments(member_id,practitioner_person_id) VALUES(member,practitioner);
 IF NOT public.application_member_access(a.email,member,true) OR public.application_member_access(a.email,other_member,true) THEN RAISE EXCEPTION 'Canonical practitioner assignment scope failed'; END IF;
 SELECT count(*) INTO before_count FROM public.members;
 denied:=false;
 BEGIN PERFORM public.application_create_participant('auth-participant@example.invalid','Synthetic','Denied','denied@example.invalid',NULL,NULL);
 EXCEPTION WHEN raise_exception THEN denied:=true; END;
 IF NOT denied OR (SELECT count(*) FROM public.members)<>before_count THEN RAISE EXCEPTION 'Unauthorized Intake changed membership'; END IF;
 SELECT * INTO a FROM public.application_create_participant('auth-documents@example.invalid','Synthetic','Enrollment',NULL,'5550109001',NULL);
 IF a.member_id IS NULL THEN RAISE EXCEPTION 'Nonmember Document Reviewer Intake failed'; END IF;
 SELECT * INTO donation FROM public.application_record_cash('auth-documents@example.invalid','__anonymous__',true,100,now(),'Synthetic anonymous');
 IF donation.status<>'pending_review' OR donation.donor_kind<>'anonymous' OR donation.facilitator_id IS NOT NULL THEN RAISE EXCEPTION 'Nonmember document reviewer anonymous cash failed'; END IF;
 IF (SELECT count(*) FROM public.audit_log WHERE action='donation.cash.created' AND entity_id=donation.donation_id::text)<>1 THEN RAISE EXCEPTION 'Cash audit not singular'; END IF;
 denied:=false;
 BEGIN PERFORM public.application_review_donation('auth-documents@example.invalid',donation.donation_id,'verified','Synthetic denial');
 EXCEPTION WHEN raise_exception THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Document Reviewer verified a financial donation'; END IF;
 SELECT * INTO donation FROM public.application_review_donation('auth-donations@example.invalid',donation.donation_id,'verified','Synthetic review');
 IF donation.status<>'verified' THEN RAISE EXCEPTION 'Canonical nonmember financial review failed'; END IF;
 denied:=false;
 BEGIN PERFORM public.application_record_cash('auth-participant@example.invalid','__anonymous__',true,100,now(),NULL);
 EXCEPTION WHEN raise_exception THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Participant recorded cash'; END IF;
 denied:=false;
 BEGIN PERFORM public.application_record_cash('auth-practitioner@example.invalid','__anonymous__',true,100,now(),NULL);
 EXCEPTION WHEN raise_exception THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Practitioner recorded anonymous cash'; END IF;
 denied:=false;
 BEGIN PERFORM public.application_record_cash('auth-practitioner@example.invalid','member:'||other_member::text,false,100,now(),NULL);
 EXCEPTION WHEN raise_exception THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Practitioner recorded unassigned cash'; END IF;
 PERFORM public.application_record_cash('auth-practitioner@example.invalid','member:'||member::text,false,100,now(),'Synthetic assigned cash');
 INSERT INTO public.organizations(organization_name) VALUES('Synthetic Authorization Company') RETURNING organization_id INTO company;
 INSERT INTO public.contributors(contributor_type,organization_id) VALUES('organization',company) RETURNING contributor_id INTO company_contributor;
 denied:=false;
 BEGIN PERFORM public.application_record_cash('auth-documents@example.invalid','contributor:'||company_contributor::text,false,100,now(),NULL);
 EXCEPTION WHEN raise_exception THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Document reviewer reached company contribution scope'; END IF;
 PERFORM public.application_record_cash('auth-donations@example.invalid','contributor:'||company_contributor::text,false,100,now(),'Synthetic company cash');
 actor:=public.application_cash_actor_id('auth-donations@example.invalid');
 SELECT * INTO batch FROM public.create_cash_deposit_batch(actor,CURRENT_DATE,NULL,'Synthetic canonical actor');
 PERFORM public.add_cash_deposit_item(batch.deposit_batch_id,donation.donation_id,actor);
 SELECT * INTO batch FROM public.prepare_cash_deposit_batch(batch.deposit_batch_id,actor,CURRENT_DATE,'SYNTHETIC-SLIP','Synthetic destination',NULL);
 SELECT * INTO batch FROM public.confirm_cash_deposit_batch(batch.deposit_batch_id,actor,100,CURRENT_DATE,'SYNTHETIC-SLIP',NULL);
 IF batch.status<>'confirmed' OR batch.preparer_id<>donor OR batch.verifier_id<>donor THEN RAISE EXCEPTION 'Canonical nonmember deposit lifecycle failed'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.cash_deposit_batch_tally WHERE deposit_batch_id=batch.deposit_batch_id AND preparer_email='auth-donations@example.invalid')
 OR NOT EXISTS(SELECT 1 FROM public.cash_deposit_batch_print WHERE deposit_batch_id=batch.deposit_batch_id AND verifier_email='auth-donations@example.invalid') THEN RAISE EXCEPTION 'Canonical actor missing from tally/print'; END IF;
 denied:=false;
 BEGIN UPDATE public.cash_deposit_batches SET deposit_date=CURRENT_DATE-1 WHERE deposit_batch_id=batch.deposit_batch_id;
 EXCEPTION WHEN raise_exception THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Confirmed batch became mutable'; END IF;
 PERFORM public.correct_confirmed_cash_deposit_date(batch.deposit_batch_id,actor,CURRENT_DATE-1,'Synthetic date correction');
 UPDATE public.person_app_accounts SET status='disabled' WHERE person_id=donor;
 IF EXISTS(SELECT 1 FROM public.application_access('auth-donations@example.invalid')) OR public.can_view_donation_financials(actor) THEN RAISE EXCEPTION 'Disabled actor retained authority'; END IF;
 RAISE NOTICE 'Canonical role, self/assignment scope, Intake/cash denial, nonmember cash lifecycle and correction checks passed.';
END $$;
CREATE FUNCTION pg_temp.reject_cash_audit() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
 IF NEW.action='donation.cash.created' THEN RAISE EXCEPTION 'Synthetic audit failure'; END IF; RETURN NEW;
END $$;
CREATE TRIGGER application_authorization_audit_failure BEFORE INSERT ON public.audit_log FOR EACH ROW EXECUTE FUNCTION pg_temp.reject_cash_audit();
DO $$ DECLARE before_count integer; denied boolean:=false; BEGIN
 SELECT count(*) INTO before_count FROM public.donations;
 BEGIN PERFORM public.application_record_cash('auth-documents@example.invalid','__anonymous__',true,100,now(),NULL);
 EXCEPTION WHEN raise_exception THEN denied:=SQLERRM='Synthetic audit failure'; END;
 IF NOT denied OR (SELECT count(*) FROM public.donations)<>before_count THEN RAISE EXCEPTION 'Cash/audit failure not atomic'; END IF;
END $$;
ROLLBACK;
