-- Synthetic rollback-only checks; never run on production.
\set ON_ERROR_STOP on
BEGIN;
CREATE FUNCTION pg_temp.intake_actor(label text,roles text[]) RETURNS uuid
LANGUAGE plpgsql AS $$ DECLARE id uuid; BEGIN
 INSERT INTO public.people(display_name,first_name,last_name) VALUES('Synthetic Atomic '||label,'Synthetic',label) RETURNING person_id INTO id;
 INSERT INTO public.person_app_accounts(person_id,email) VALUES(id,'atomic-'||label||'@example.invalid');
 INSERT INTO public.person_roles(person_id,role_key,assigned_by) SELECT id,r,'synthetic_atomic_test' FROM unnest(roles) r;
 RETURN id;
END $$;
CREATE FUNCTION pg_temp.intake_counts() RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE t text; n bigint; result jsonb:='{}'; BEGIN
 FOREACH t IN ARRAY ARRAY['people','organizations','members','contributors','member_emails','member_phones','member_addresses',
  'contributor_emails','contributor_phones','contributor_addresses','party_contacts','party_contact_sources','contributor_member_links',
  'member_practitioner_assignments','member_agreements','listmonk_sync_queue','audit_log','application_intake_requests'] LOOP
  EXECUTE format('SELECT count(*) FROM public.%I',t) INTO n;result:=result||jsonb_build_object(t,n);
 END LOOP;RETURN result;END $$;
CREATE FUNCTION pg_temp.intake_reject_insert() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
 IF current_setting('signaturegate.test_intake_fail_table',true)=TG_TABLE_NAME THEN RAISE EXCEPTION 'Synthetic atomic insert failure'; END IF;
 IF TG_TABLE_NAME='audit_log' THEN
  IF current_setting('signaturegate.test_intake_fail_table',true)='final_audit' AND NEW.action='intake.completed' THEN RAISE EXCEPTION 'Synthetic final audit failure'; END IF;
 END IF;
 IF TG_TABLE_NAME='listmonk_sync_queue' THEN
  IF current_setting('signaturegate.test_intake_fail_table',true)='contributor_queue' AND NEW.contributor_email_id IS NOT NULL THEN RAISE EXCEPTION 'Synthetic atomic insert failure'; END IF;
 END IF;
 RETURN NEW;END $$;
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['members','member_emails','member_phones','member_addresses','contributors','contributor_emails',
  'contributor_phones','contributor_addresses','contributor_member_links','member_practitioner_assignments','member_agreements',
  'listmonk_sync_queue','audit_log'] LOOP
  EXECUTE format('CREATE TRIGGER atomic_intake_fault BEFORE INSERT ON public.%I FOR EACH ROW EXECUTE FUNCTION pg_temp.intake_reject_insert()',t);
 END LOOP;
END $$;
DO $$
DECLARE admin uuid; doc uuid; donations uuid; outsider uuid; practitioner uuid; template uuid; req uuid; other_req uuid;
 payload jsonb; baseline jsonb; receipt jsonb; again jsonb; kind text; contacts text; member_opt boolean; contributor_opt boolean;
 count_cases integer:=0; fault_cases integer:=0; counter integer:=0; deferred_cases integer:=0; t text; failure boolean; invalid jsonb;
BEGIN
 admin:=pg_temp.intake_actor('admin',ARRAY['directory_manager','document_reviewer','donations_reviewer']);
 doc:=pg_temp.intake_actor('doc',ARRAY['document_reviewer']);donations:=pg_temp.intake_actor('donations',ARRAY['donations_reviewer']);
 outsider:=pg_temp.intake_actor('outsider',ARRAY[]::text[]);practitioner:=pg_temp.intake_actor('practitioner',ARRAY['practitioner']);
 INSERT INTO public.agreement_types(type_key,display_name) VALUES('synthetic_atomic','Synthetic Atomic');
 INSERT INTO public.agreement_templates(name,version,required_for) VALUES('Synthetic Atomic','synthetic',ARRAY['synthetic_atomic']) RETURNING agreement_template_id INTO template;
 FOREACH kind IN ARRAY ARRAY['participant','dual','individual','organization'] LOOP
  FOREACH contacts IN ARRAY CASE WHEN kind IN ('participant','dual') THEN ARRAY['email_phone','email_address'] ELSE ARRAY['email_phone','email_address','phone_address'] END LOOP
   FOREACH member_opt IN ARRAY ARRAY[false,true] LOOP
    FOREACH contributor_opt IN ARRAY CASE WHEN kind='dual' THEN ARRAY[false,true] ELSE ARRAY[member_opt] END LOOP
     counter:=counter+1;req:=public.uuid_generate_v4();
     payload:=jsonb_build_object('kind',CASE WHEN kind='organization' THEN 'organization' ELSE 'individual' END,
      'participant',kind IN ('participant','dual'),'contributor',kind<>'participant','first_name','Synthetic','last_name','Atomic'||counter,
      'company_name','Synthetic Atomic Company '||counter,'date_of_birth',CASE WHEN kind='organization' THEN '' ELSE '1990-01-01' END,
      'email',CASE WHEN contacts LIKE 'email%' THEN 'synthetic-atomic-'||counter||'@example.invalid' ELSE '' END,
      'phone',CASE WHEN contacts LIKE '%phone' OR contacts LIKE 'phone%' THEN '555020'||lpad(counter::text,4,'0') ELSE '' END,
      'address',CASE WHEN contacts LIKE '%address' THEN 'Synthetic Street' ELSE '' END,
      'city',CASE WHEN contacts LIKE '%address' THEN 'Synthetic City' ELSE '' END,
      'state',CASE WHEN contacts LIKE '%address' THEN 'CO' ELSE '' END,'postal_code',CASE WHEN contacts LIKE '%address' THEN '00000' ELSE '' END,
      'notes','Synthetic identity notes','reason','Synthetic enrollment','participant_subscribe',member_opt,'contributor_subscribe',contributor_opt,
      'agreement_delivery','Digital','agreement_type','synthetic_atomic','agreement_template_id',template,'practitioner_person_id',practitioner);
     receipt:=public.application_submit_intake(CASE kind WHEN 'participant' THEN 'atomic-doc@example.invalid' WHEN 'dual' THEN 'atomic-admin@example.invalid' ELSE 'atomic-donations@example.invalid' END,req,payload);
     IF receipt->>'state'<>'committed' OR receipt->>'request_id'<>req::text THEN RAISE EXCEPTION 'Missing committed receipt'; END IF;
     baseline:=pg_temp.intake_counts();
     again:=public.application_submit_intake(CASE kind WHEN 'participant' THEN 'atomic-doc@example.invalid' WHEN 'dual' THEN 'atomic-admin@example.invalid' ELSE 'atomic-donations@example.invalid' END,req,payload);
     IF again<>receipt OR baseline<>pg_temp.intake_counts() THEN RAISE EXCEPTION 'Replay changed identities, audits or mailing queues'; END IF;
     IF public.application_intake_status(CASE kind WHEN 'participant' THEN 'atomic-doc@example.invalid' WHEN 'dual' THEN 'atomic-admin@example.invalid' ELSE 'atomic-donations@example.invalid' END,req)<>receipt THEN RAISE EXCEPTION 'Owner receipt recovery failed'; END IF;
     IF public.application_intake_status('atomic-admin@example.invalid',req) IS NOT NULL AND kind<>'dual' THEN RAISE EXCEPTION 'Another reviewer saw a receipt'; END IF;
     IF kind<>'organization' AND NOT EXISTS(SELECT 1 FROM public.people WHERE person_id=(receipt->>'person_id')::uuid AND notes='Synthetic identity notes' AND date_of_birth='1990-01-01') THEN RAISE EXCEPTION 'Individual notes/DOB lost'; END IF;
     IF kind IN ('participant','dual') THEN
      IF NOT EXISTS(SELECT 1 FROM public.member_agreements WHERE member_agreement_id=(receipt->>'agreement_id')::uuid AND status='pending_email_send') THEN RAISE EXCEPTION 'Pending agreement missing'; END IF;
      IF NOT EXISTS(SELECT 1 FROM public.member_emails WHERE member_id=(receipt->>'member_id')::uuid AND (mailing_subscription_status='subscribed')=member_opt) THEN RAISE EXCEPTION 'Participant consent lost'; END IF;
     END IF;
     IF kind<>'participant' AND contacts LIKE 'email%' AND NOT EXISTS(SELECT 1 FROM public.contributor_emails WHERE contributor_id=(receipt->>'contributor_id')::uuid AND (mailing_subscription_status='subscribed')=contributor_opt) THEN RAISE EXCEPTION 'Contributor consent lost'; END IF;
     IF kind='dual' AND (NOT EXISTS(SELECT 1 FROM public.members m JOIN public.contributors c USING(person_id) WHERE m.member_id=(receipt->>'member_id')::uuid AND c.contributor_id=(receipt->>'contributor_id')::uuid) OR NOT EXISTS(SELECT 1 FROM public.contributor_member_links WHERE contributor_id=(receipt->>'contributor_id')::uuid)) THEN RAISE EXCEPTION 'Dual identity/link split'; END IF;
     count_cases:=count_cases+1;
    END LOOP;
   END LOOP;
  END LOOP;
 END LOOP;
 IF count_cases<>24 THEN RAISE EXCEPTION 'Enrollment matrix incomplete: %',count_cases; END IF;
 -- Explicitly deferred agreements retain all enrollment/contact/assignment gates.
 FOREACH kind IN ARRAY ARRAY['participant','dual'] LOOP
  FOREACH contacts IN ARRAY ARRAY['email_phone','email_address','phone_address'] LOOP
   FOREACH member_opt IN ARRAY ARRAY[false,true] LOOP
    FOREACH contributor_opt IN ARRAY CASE WHEN kind='dual' THEN ARRAY[false,true] ELSE ARRAY[member_opt] END LOOP
     counter:=counter+1;req:=public.uuid_generate_v4();
     payload:=payload||jsonb_build_object('kind','individual','participant',true,'contributor',kind='dual',
      'last_name','Deferred'||counter,'agreement_delivery','Later','agreement_type','',
      'agreement_template_id','stale-hidden-value-is-ignored',
      'email',CASE WHEN contacts LIKE 'email%' THEN 'synthetic-deferred-'||counter||'@example.invalid' ELSE '' END,
      'phone',CASE WHEN contacts LIKE '%phone' OR contacts LIKE 'phone%' THEN '555040'||lpad(counter::text,4,'0') ELSE '' END,
      'address',CASE WHEN contacts LIKE '%address' THEN 'Synthetic Street' ELSE '' END,
      'city',CASE WHEN contacts LIKE '%address' THEN 'Synthetic City' ELSE '' END,
      'state',CASE WHEN contacts LIKE '%address' THEN 'CO' ELSE '' END,
      'postal_code',CASE WHEN contacts LIKE '%address' THEN '00000' ELSE '' END,
      'participant_subscribe',member_opt,'contributor_subscribe',contributor_opt);
     receipt:=public.application_submit_intake('atomic-admin@example.invalid',req,payload);
     IF receipt->>'agreement_id' IS NOT NULL OR receipt->>'agreement_deferred'<>'true' THEN RAISE EXCEPTION 'Deferred receipt created an agreement';END IF;
     IF NOT EXISTS(SELECT 1 FROM public.member_practitioner_assignments WHERE member_id=(receipt->>'member_id')::uuid AND practitioner_person_id=practitioner AND status='active') THEN RAISE EXCEPTION 'Deferred assignment lost';END IF;
     IF EXISTS(SELECT 1 FROM public.member_agreements WHERE member_id=(receipt->>'member_id')::uuid) OR EXISTS(SELECT 1 FROM public.issue19_sacrament_release_agreement((receipt->>'member_id')::uuid)) THEN RAISE EXCEPTION 'Deferred enrollment gained agreement/release eligibility';END IF;
     IF contacts='phone_address' AND (EXISTS(SELECT 1 FROM public.member_emails WHERE member_id=(receipt->>'member_id')::uuid) OR EXISTS(SELECT 1 FROM public.contributor_emails WHERE contributor_id=(receipt->>'contributor_id')::uuid)) THEN RAISE EXCEPTION 'Deferred enrollment invented email';END IF;
     baseline:=pg_temp.intake_counts();
     IF public.application_submit_intake('atomic-admin@example.invalid',req,payload)<>receipt OR baseline<>pg_temp.intake_counts() THEN RAISE EXCEPTION 'Deferred replay changed saved state';END IF;
     deferred_cases:=deferred_cases+1;
    END LOOP;
   END LOOP;
  END LOOP;
 END LOOP;
 IF deferred_cases<>18 THEN RAISE EXCEPTION 'Deferred matrix incomplete: %',deferred_cases;END IF;
 -- Fault cases use Digital dual-capacity intake and unique synthetic contacts.
 FOREACH t IN ARRAY ARRAY['members','member_emails','member_phones','member_addresses','contributors','contributor_emails',
  'contributor_phones','contributor_addresses','contributor_member_links','member_practitioner_assignments','member_agreements',
  'listmonk_sync_queue','contributor_queue','final_audit'] LOOP
  counter:=counter+1;req:=public.uuid_generate_v4();payload:=payload||jsonb_build_object('kind','individual','participant',true,'contributor',true,
   'agreement_delivery','Digital','agreement_type','synthetic_atomic','agreement_template_id',template,
   'first_name','Synthetic','last_name','AtomicFault'||counter,'date_of_birth','','email','synthetic-fault-'||counter||'@example.invalid','phone','555030'||lpad(counter::text,4,'0'),
   'address','Synthetic Fault Street','city','Synthetic City','state','CO','postal_code','00000','participant_subscribe',true,'contributor_subscribe',true);
  baseline:=pg_temp.intake_counts();failure:=false;PERFORM set_config('signaturegate.test_intake_fail_table',t,true);
  BEGIN PERFORM public.application_submit_intake('atomic-admin@example.invalid',req,payload);
  EXCEPTION WHEN raise_exception THEN failure:=SQLERRM IN ('Synthetic atomic insert failure','Synthetic final audit failure'); END;
  PERFORM set_config('signaturegate.test_intake_fail_table','',true);
  IF NOT failure OR baseline<>pg_temp.intake_counts() THEN RAISE EXCEPTION 'Failed rollback boundary: %',t; END IF;
  receipt:=public.application_submit_intake('atomic-admin@example.invalid',req,payload);
  IF receipt->>'state'<>'committed' THEN RAISE EXCEPTION 'Failed request could not be safely retried'; END IF;
  fault_cases:=fault_cases+1;
 END LOOP;
 baseline:=pg_temp.intake_counts();
 FOR invalid IN SELECT value FROM jsonb_array_elements(jsonb_build_array(
  jsonb_build_object('change','{"participant":"true"}'::jsonb,'message','Enrollment and mailing choices must be explicit booleans'),
  jsonb_build_object('change','{"contributor_subscribe":null}'::jsonb,'message','Enrollment and mailing choices must be explicit booleans'),
  jsonb_build_object('change','{"email":12}'::jsonb,'message','Intake text fields must be strings'),
  jsonb_build_object('change','{"unrecognized":"value"}'::jsonb,'message','Unknown Intake field'),
  jsonb_build_object('change','{"kind":"organization"}'::jsonb,'message','Choose individual capacities or company Contributor intake'),
  jsonb_build_object('change','{"first_name":""}'::jsonb,'message','Individual first/last name or company name required'),
  jsonb_build_object('change','{"email":"invalid"}'::jsonb,'message','Valid email required'),
  jsonb_build_object('change','{"phone":"123"}'::jsonb,'message','Valid US phone required'),
  jsonb_build_object('change','{"postal_code":""}'::jsonb,'message','Complete mailing address required'),
  jsonb_build_object('change','{"phone":"","address":"","city":"","state":"","postal_code":""}'::jsonb,'message','At least two contact methods required'),
  jsonb_build_object('change','{"reason":""}'::jsonb,'message','Contributor enrollment reason required'),
  jsonb_build_object('change','{"agreement_delivery":"Paper"}'::jsonb,'message','Choose Digital or create agreement Later; paper remains blocked'),
  jsonb_build_object('change','{"agreement_type":"not_active"}'::jsonb,'message','Active matching agreement type and template required'),
  jsonb_build_object('change','{"practitioner_person_id":""}'::jsonb,'message','Participant practitioner assignment required')
 )) LOOP
  failure:=false;
  BEGIN PERFORM public.application_submit_intake('atomic-admin@example.invalid',public.uuid_generate_v4(),payload||(invalid->'change'));
  EXCEPTION WHEN raise_exception THEN failure:=SQLERRM=invalid->>'message';END;
  IF NOT failure OR baseline<>pg_temp.intake_counts() THEN RAISE EXCEPTION 'Input validation/rollback failed: %',invalid->>'message';END IF;
 END LOOP;
 baseline:=pg_temp.intake_counts();failure:=false;
 BEGIN PERFORM public.application_submit_intake('atomic-admin@example.invalid',req,payload||'{"notes":"Changed payload"}');EXCEPTION WHEN raise_exception THEN failure:=SQLERRM LIKE 'Request key unavailable%';END;
 IF NOT failure OR baseline<>pg_temp.intake_counts() THEN RAISE EXCEPTION 'Changed-payload replay accepted';END IF;
 failure:=false;BEGIN PERFORM public.application_submit_intake('atomic-donations@example.invalid',req,payload||'{"participant":false}');EXCEPTION WHEN raise_exception THEN failure:=SQLERRM LIKE 'Request key unavailable%';END;
 IF NOT failure OR baseline<>pg_temp.intake_counts() THEN RAISE EXCEPTION 'Other-owner replay accepted';END IF;
 -- Null/unknown request is never an authority bypass.
 IF public.application_intake_status('atomic-admin@example.invalid',public.uuid_generate_v4()) IS NOT NULL THEN RAISE EXCEPTION 'Unknown receipt returned data';END IF;
 FOREACH kind IN ARRAY ARRAY['outsider','practitioner','doc','donations'] LOOP
  failure:=false;BEGIN PERFORM public.application_submit_intake('atomic-'||kind||'@example.invalid',public.uuid_generate_v4(),payload);EXCEPTION WHEN raise_exception THEN failure:=true;END;
  IF NOT failure OR baseline<>pg_temp.intake_counts() THEN RAISE EXCEPTION 'Dual role denial failed: %',kind;END IF;
 END LOOP;
 UPDATE public.person_app_accounts SET status='disabled' WHERE person_id=admin;
 failure:=false;BEGIN PERFORM public.application_intake_status('atomic-admin@example.invalid',req);EXCEPTION WHEN raise_exception THEN failure:=true;END;
 IF NOT failure THEN RAISE EXCEPTION 'Disabled receipt owner retained access';END IF;
 RAISE NOTICE 'Atomic Intake passed: % Digital/Contributor, % deferred enrollment/replay cases and % rollback/retry boundaries.',count_cases,deferred_cases,fault_cases;
END $$;
ROLLBACK;
