-- Artificial identities, contacts and amounts only. All fixtures roll back.
\set ON_ERROR_STOP on
BEGIN;
CREATE FUNCTION pg_temp.provider_denial(command text, message_pattern text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN EXECUTE command;
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE message_pattern THEN RETURN; END IF;
    RAISE;
  END;
  RAISE EXCEPTION 'Expected provider administration denial was not observed';
END $$;
CREATE FUNCTION pg_temp.provider_fixture(payload jsonb) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE id uuid;
BEGIN
 INSERT INTO public.donations(provider,provider_reference,donor_kind,status,amount_cents,currency)
 VALUES('givebutter','synthetic-'||public.uuid_generate_v4(),'unresolved','pending_review',137,'USD') RETURNING donation_id INTO id;
 INSERT INTO public.audit_log(action,entity_type,entity_id,details)
 VALUES('synthetic.provider_payload','donation',id::text,jsonb_build_object('raw',payload));
 RETURN id;
END $$;
DO $$
DECLARE
 v_don uuid; v_combined uuid; v_denied uuid; v_member uuid; v_member_person uuid;
 v_a public.contributors%ROWTYPE; v_b public.contributors%ROWTYPE;
 v_gift uuid; v_gift2 uuid; v_result public.donations%ROWTYPE; v_enrolled public.members%ROWTYPE;
 v_count integer; v_raw jsonb; v_identity text; v_cash uuid; v_batch public.cash_deposit_batches%ROWTYPE; v_actor uuid;
BEGIN
 INSERT INTO public.people(display_name) VALUES('Synthetic canonical provider reviewer') RETURNING person_id INTO v_don;
 INSERT INTO public.people(display_name) VALUES('Synthetic combined provider reviewer') RETURNING person_id INTO v_combined;
 INSERT INTO public.people(display_name) VALUES('Synthetic stale legacy reviewer') RETURNING person_id INTO v_denied;
 INSERT INTO public.person_app_accounts(person_id,email) VALUES
  (v_don,'provider-reviewer@example.invalid'),(v_combined,'Provider-Combined@EXAMPLE.INVALID'),(v_denied,'provider-denied@example.invalid');
 INSERT INTO public.person_roles(person_id,role_key,assigned_by) VALUES
  (v_don,'donations_reviewer','synthetic'),(v_combined,'donations_reviewer','synthetic'),
  (v_combined,'document_reviewer','synthetic'),(v_combined,'directory_manager','synthetic');
 INSERT INTO public.members(person_id,email,is_facilitator,is_document_reviewer,is_donations_reviewer)
 VALUES(v_denied,'provider-denied@example.invalid',true,true,true);
 INSERT INTO public.people(display_name,first_name,last_name) VALUES('Synthetic Participant','Synthetic','Participant') RETURNING person_id INTO v_member_person;
 INSERT INTO public.members(person_id,email) VALUES(v_member_person,'provider-participant@example.invalid') RETURNING member_id INTO v_member;

 v_gift:=pg_temp.provider_fixture('{"first_name":"Synthetic","last_name":"Individual","email":"provider-new@example.invalid","contact_id":101}'::jsonb);
 PERFORM pg_temp.provider_denial(format('SELECT public.application_resolve_provider_choice(%L,%L,%L)',
  'provider-denied@example.invalid',v_gift,'member:'||v_member),'Permission denied%');
 IF EXISTS(SELECT 1 FROM public.contributors WHERE person_id=v_member_person) THEN RAISE EXCEPTION 'Denied resolution created a capacity'; END IF;
 IF (SELECT member_id FROM public.match_contributor_identity('givebutter',NULL,'provider-participant@example.invalid',NULL))<>v_member
  OR (SELECT person_id FROM public.contributors WHERE person_id=v_member_person)<>v_member_person
 THEN RAISE EXCEPTION 'Unique Participant fallback replaced the person identity'; END IF;
 v_result:=public.application_resolve_provider_choice('provider-reviewer@example.invalid',v_gift,'__new_individual__','Synthetic review');
 SELECT * INTO v_a FROM public.contributors WHERE contributor_id=v_result.contributor_id;
 IF v_result.status<>'verified' OR v_result.member_id IS NOT NULL OR v_result.reviewer_id IS NOT NULL
  OR v_a.person_id IS NULL OR v_a.organization_id IS NOT NULL
  OR EXISTS(SELECT 1 FROM public.members WHERE person_id=v_don OR person_id=v_a.person_id)
  OR NOT EXISTS(SELECT 1 FROM public.contributor_external_identities WHERE contributor_id=v_a.contributor_id AND provider_identity='101')
  OR (SELECT count(*) FROM public.audit_log WHERE entity_id=v_gift::text AND action='donation.contributor_resolved')<>1
 THEN RAISE EXCEPTION 'Canonical nonmember resolution lost identity, review or audit'; END IF;
 PERFORM pg_temp.provider_denial(format('SELECT public.application_resolve_provider_choice(%L,%L,%L)',
  'provider-reviewer@example.invalid',v_gift,'contributor:'||v_a.contributor_id),'Only an unresolved%');

 v_gift2:=pg_temp.provider_fixture('{"organization_name":"Synthetic Organization","email":"provider-org@example.invalid","contact_id":"org-synthetic"}'::jsonb);
 v_result:=public.application_resolve_provider_choice('provider-reviewer@example.invalid',v_gift2,'__new_organization__');
 SELECT * INTO v_b FROM public.contributors WHERE contributor_id=v_result.contributor_id;
 IF v_b.organization_id IS NULL OR v_b.person_id IS NOT NULL OR v_result.member_id IS NOT NULL THEN RAISE EXCEPTION 'Company became a person or Participant'; END IF;

 -- Known provider IDs prevent new duplicate parties, even with different contacts.
 v_gift2:=pg_temp.provider_fixture('{"first_name":"Synthetic","last_name":"Duplicate","email":"provider-other@example.invalid","contact_id":101}'::jsonb);
 SELECT count(*) INTO v_count FROM public.people;
 PERFORM pg_temp.provider_denial(format('SELECT public.application_resolve_provider_choice(%L,%L,%L)',
  'provider-reviewer@example.invalid',v_gift2,'__new_individual__'),'Existing or ambiguous identity%');
 IF (SELECT count(*) FROM public.people)<>v_count THEN RAISE EXCEPTION 'Duplicate creation left a person'; END IF;
 PERFORM pg_temp.provider_denial(format('SELECT public.application_resolve_provider_choice(%L,%L,%L)',
  'provider-reviewer@example.invalid',v_gift2,'contributor:'||v_b.contributor_id),'Provider identity already belongs%');
 IF (SELECT status FROM public.donations WHERE donation_id=v_gift2)<>'pending_review'
  OR EXISTS(SELECT 1 FROM public.contributor_emails WHERE contributor_id=v_b.contributor_id AND email='provider-other@example.invalid')
 THEN RAISE EXCEPTION 'Conflicting resolution was not atomic'; END IF;
 v_result:=public.application_resolve_provider_choice('provider-reviewer@example.invalid',v_gift2,'contributor:'||v_a.contributor_id);

 -- Shared contacts remain ambiguous until an explicit existing-party choice.
 INSERT INTO public.contributor_emails(contributor_id,email) VALUES(v_a.contributor_id,'provider-shared@example.invalid'),(v_b.contributor_id,'provider-shared@example.invalid');
 INSERT INTO public.contributor_phones(contributor_id,phone) VALUES(v_b.contributor_id,'5550109499');
 IF EXISTS(SELECT 1 FROM public.match_contributor_identity('givebutter',NULL,'provider-shared@example.invalid','5550109499'))
  OR EXISTS(SELECT 1 FROM public.match_contributor_identity('givebutter',NULL,'provider-new@example.invalid','5550109499'))
 THEN RAISE EXCEPTION 'Ambiguous or contradictory contacts automatically matched'; END IF;
 IF (SELECT contributor_id FROM public.match_contributor_identity('givebutter','101','provider-shared@example.invalid','5550109499'))<>v_a.contributor_id
 THEN RAISE EXCEPTION 'Established provider binding lost matching priority'; END IF;
 UPDATE public.contributor_external_identities SET status='archived' WHERE provider='givebutter' AND provider_identity='101';
 IF EXISTS(SELECT 1 FROM public.match_contributor_identity('givebutter','101','provider-org@example.invalid',NULL)) THEN RAISE EXCEPTION 'Archived provider binding fell through to another party'; END IF;
 v_gift2:=pg_temp.provider_fixture('{"first_name":"Synthetic","last_name":"Archived Conflict","email":"provider-archived-conflict@example.invalid","contact_id":101}'::jsonb);
 PERFORM pg_temp.provider_denial(format('SELECT public.application_resolve_provider_choice(%L,%L,%L)',
  'provider-reviewer@example.invalid',v_gift2,'contributor:'||v_b.contributor_id),'Provider identity already belongs%');
 UPDATE public.contributor_external_identities SET status='active' WHERE provider='givebutter' AND provider_identity='101';
 v_gift2:=pg_temp.provider_fixture('{"first_name":"Synthetic","last_name":"Shared","email":"provider-shared@example.invalid"}'::jsonb);
 PERFORM pg_temp.provider_denial(format('SELECT public.application_resolve_provider_choice(%L,%L,%L)',
  'provider-reviewer@example.invalid',v_gift2,'__new_individual__'),'Existing or ambiguous identity%');
 IF (SELECT donor_kind FROM public.donations WHERE donation_id=v_gift2)<>'unresolved' THEN RAISE EXCEPTION 'Ambiguous identity auto-resolved'; END IF;
 v_result:=public.application_resolve_provider_choice('provider-reviewer@example.invalid',v_gift2,'contributor:'||v_b.contributor_id,'Synthetic disambiguation');

 v_gift2:=pg_temp.provider_fixture('{"first_name":"Synthetic","last_name":"Existing Participant","contact_id":"member-synthetic"}'::jsonb);
 v_result:=public.application_resolve_provider_choice('provider-reviewer@example.invalid',v_gift2,'member:'||v_member);
 IF v_result.member_id<>v_member OR (SELECT person_id FROM public.contributors WHERE contributor_id=v_result.contributor_id)<>v_member_person THEN RAISE EXCEPTION 'Participant choice replaced canonical identity'; END IF;

 v_gift2:=pg_temp.provider_fixture('{"first_name":"Synthetic","last_name":"Enrollment","email":"provider-enroll@example.invalid","phone":"5550109411","contact_id":"enroll-synthetic"}'::jsonb);
 PERFORM pg_temp.provider_denial(format('SELECT public.application_create_participant_from_donation(%L,%L)',
  'provider-reviewer@example.invalid',v_gift2),'Permission denied%');
 DELETE FROM public.person_roles WHERE person_id=v_combined AND role_key='directory_manager';
 PERFORM pg_temp.provider_denial(format('SELECT public.application_create_participant_from_donation(%L,%L)',
  'Provider-Combined@EXAMPLE.INVALID',v_gift2),'Directory Manager permission%');
 INSERT INTO public.person_roles(person_id,role_key,assigned_by) VALUES(v_combined,'directory_manager','synthetic');
 SELECT count(*) INTO v_count FROM public.people;
 v_enrolled:=public.application_create_participant_from_donation('Provider-Combined@EXAMPLE.INVALID',v_gift2,'Synthetic enrollment',true);
 SELECT * INTO v_result FROM public.donations WHERE donation_id=v_gift2;
 IF (SELECT count(*) FROM public.people)<>v_count+1 OR v_result.member_id<>v_enrolled.member_id
  OR (SELECT person_id FROM public.contributors WHERE contributor_id=v_result.contributor_id)<>v_enrolled.person_id
  OR EXISTS(SELECT 1 FROM public.person_roles WHERE person_id=v_enrolled.person_id)
  OR NOT EXISTS(SELECT 1 FROM public.member_emails WHERE member_id=v_enrolled.member_id AND mailing_subscription_status='subscribed')
  OR EXISTS(SELECT 1 FROM public.contributor_emails WHERE contributor_id=v_result.contributor_id AND mailing_subscription_status='subscribed')
 THEN RAISE EXCEPTION 'Dual enrollment duplicated identity, granted roles or coupled mailing consent'; END IF;
 v_gift2:=pg_temp.provider_fixture('{"first_name":"Synthetic","last_name":"Incomplete","email":"provider-incomplete@example.invalid"}'::jsonb);
 PERFORM pg_temp.provider_denial(format('SELECT public.application_create_participant_from_donation(%L,%L)',
  'Provider-Combined@EXAMPLE.INVALID',v_gift2),'Two contact methods%');
 IF (SELECT status FROM public.donations WHERE donation_id=v_gift2)<>'pending_review' THEN RAISE EXCEPTION 'Incomplete enrollment resolved donation'; END IF;

 -- Attribution correction changes no financial/provider/review fields or bindings.
 SELECT to_jsonb(d)-'contributor_id'-'member_id'-'donor_kind'-'updated_at' INTO v_raw FROM public.donations d WHERE d.donation_id=v_gift;
 PERFORM pg_temp.provider_denial(format('SELECT public.application_reassign_donation(%L,%L,%L,%L)',
  'provider-denied@example.invalid',v_gift,'contributor:'||v_b.contributor_id,'Synthetic'),'Permission denied%');
 PERFORM pg_temp.provider_denial(format('SELECT public.application_reassign_donation(%L,%L,%L,%L)',
  'provider-reviewer@example.invalid',v_gift,'contributor:'||v_b.contributor_id,'   '),'A reason is required%');
 v_result:=public.application_reassign_donation('provider-reviewer@example.invalid',v_gift,'contributor:'||v_b.contributor_id,'Synthetic attribution correction');
 IF (SELECT to_jsonb(d)-'contributor_id'-'member_id'-'donor_kind'-'updated_at' FROM public.donations d WHERE d.donation_id=v_gift) IS DISTINCT FROM v_raw
  OR (SELECT contributor_id FROM public.contributor_external_identities WHERE provider='givebutter' AND provider_identity='101')<>v_a.contributor_id
  OR NOT EXISTS(SELECT 1 FROM public.audit_log WHERE entity_id=v_gift::text AND action='donation.reassigned' AND details->>'from_contributor_id'=v_a.contributor_id::text AND details->>'reason'='Synthetic attribution correction')
 THEN RAISE EXCEPTION 'Reassignment changed protected history or lost audit'; END IF;
 v_actor:=public.application_cash_actor_id('provider-reviewer@example.invalid');
 INSERT INTO public.donations(provider,donor_kind,status,amount_cents) VALUES('cash','anonymous','verified',211) RETURNING donation_id INTO v_cash;
 v_batch:=public.create_cash_deposit_batch(v_actor,CURRENT_DATE,NULL,'Synthetic protected attribution');
 PERFORM public.add_cash_deposit_item(v_batch.deposit_batch_id,v_cash,v_actor);
 PERFORM pg_temp.provider_denial(format('SELECT public.application_reassign_donation(%L,%L,%L,%L)',
  'provider-reviewer@example.invalid',v_cash,'contributor:'||v_b.contributor_id,'Synthetic'),'A donation in an active deposit batch%');
END $$;
CREATE FUNCTION pg_temp.fail_provider_audit() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF NEW.action IN ('donation.contributor_resolved','donation.reassigned') THEN RAISE EXCEPTION 'Synthetic provider audit failure'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER synthetic_provider_audit_failure BEFORE INSERT ON public.audit_log FOR EACH ROW EXECUTE FUNCTION pg_temp.fail_provider_audit();
DO $$
DECLARE v_id uuid;v_count integer;v_party uuid;
BEGIN
 v_id:=pg_temp.provider_fixture('{"first_name":"Synthetic","last_name":"Rollback","email":"provider-rollback@example.invalid","contact_id":"rollback-synthetic"}'::jsonb);
 SELECT count(*) INTO v_count FROM public.people;
 PERFORM pg_temp.provider_denial(format('SELECT public.application_resolve_provider_choice(%L,%L,%L)',
  'provider-reviewer@example.invalid',v_id,'__new_individual__'),'Synthetic provider audit failure');
 IF (SELECT count(*) FROM public.people)<>v_count OR (SELECT status FROM public.donations WHERE donation_id=v_id)<>'pending_review'
  OR EXISTS(SELECT 1 FROM public.contributor_external_identities WHERE provider_identity='rollback-synthetic')
 THEN RAISE EXCEPTION 'Audit failure did not roll back identity and review'; END IF;
 SELECT contributor_id INTO v_party FROM public.contributor_external_identities WHERE provider_identity='org-synthetic';
 SELECT donation_id INTO v_id FROM public.donations WHERE contributor_id=v_party LIMIT 1;
 PERFORM pg_temp.provider_denial(format('SELECT public.application_reassign_donation(%L,%L,%L,%L)',
  'provider-reviewer@example.invalid',v_id,'member:'||(SELECT member_id FROM public.members WHERE email='provider-participant@example.invalid'),'Synthetic correction'),'Synthetic provider audit failure');
 IF (SELECT contributor_id FROM public.donations WHERE donation_id=v_id)<>v_party THEN RAISE EXCEPTION 'Audit failure did not roll back attribution'; END IF;
END $$;
SET CONSTRAINTS ALL IMMEDIATE;
ROLLBACK;
