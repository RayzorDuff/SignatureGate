-- Rollback-only synthetic company-contact relationship checks.
\set ON_ERROR_STOP on
BEGIN;
CREATE FUNCTION pg_temp.expect_company_denial(command text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 BEGIN EXECUTE command;
 EXCEPTION WHEN OTHERS THEN RETURN;
 END;
 RAISE EXCEPTION 'Expected company-contact operation to fail';
END $$;
DO $$
DECLARE manager uuid; reviewer uuid; outsider uuid; disabled uuid; legacy uuid;
 company uuid; second_company uuid; first_person uuid; second_person uuid; private_person uuid;
 link public.organization_contact_people; second_link public.organization_contact_people; later public.organization_contact_people;
 old_audits bigint; role_count bigint; member_count bigint; contributor_count bigint; contact_count bigint;
BEGIN
 INSERT INTO public.people(display_name) VALUES('Synthetic Company Contact Manager') RETURNING person_id INTO manager;
 INSERT INTO public.people(display_name) VALUES('Synthetic Company Contact Reviewer') RETURNING person_id INTO reviewer;
 INSERT INTO public.people(display_name) VALUES('Synthetic Company Contact Outsider') RETURNING person_id INTO outsider;
 INSERT INTO public.people(display_name) VALUES('Synthetic Company Contact Disabled') RETURNING person_id INTO disabled;
 INSERT INTO public.people(display_name) VALUES('Synthetic Company Contact Legacy') RETURNING person_id INTO legacy;
 INSERT INTO public.person_app_accounts(person_id,email,status) VALUES
 (manager,'Company-Manager@example.invalid','active'),(reviewer,'company-reviewer@example.invalid','active'),
 (outsider,'company-outsider@example.invalid','active'),(disabled,'company-disabled@example.invalid','disabled'),
 (legacy,'company-legacy@example.invalid','active');
 INSERT INTO public.person_roles(person_id,role_key,assigned_by) VALUES
 (manager,'directory_manager','synthetic'),(reviewer,'donations_reviewer','synthetic'),
 (disabled,'directory_manager','synthetic'),(outsider,'document_reviewer','synthetic');
 INSERT INTO public.members(person_id,status,is_document_reviewer,is_donations_reviewer)
 VALUES(legacy,'active',true,true);
 INSERT INTO public.organizations(organization_name) VALUES('Synthetic Contact Company') RETURNING organization_id INTO company;
 INSERT INTO public.organizations(organization_name) VALUES('Synthetic Second Contact Company') RETURNING organization_id INTO second_company;
 INSERT INTO public.contributors(contributor_type,organization_id) VALUES('organization',company),('organization',second_company);
 INSERT INTO public.people(display_name) VALUES('Synthetic Shared Company Contact') RETURNING person_id INTO first_person;
 INSERT INTO public.people(display_name) VALUES('Synthetic Second Company Contact') RETURNING person_id INTO second_person;
 INSERT INTO public.people(display_name) VALUES('Synthetic Restricted Company Contact') RETURNING person_id INTO private_person;
 INSERT INTO public.contributors(contributor_type,person_id) VALUES('individual',first_person),('individual',second_person);
 SELECT count(*) INTO role_count FROM public.person_roles;
 SELECT count(*) INTO member_count FROM public.members;
 SELECT count(*) INTO contributor_count FROM public.contributors;
 SELECT count(*) INTO contact_count FROM public.party_contacts;
 IF NOT EXISTS(SELECT 1 FROM public.application_company_contact_candidates('company-reviewer@example.invalid',company) WHERE person_id=first_person)
 OR EXISTS(SELECT 1 FROM public.application_company_contact_candidates('company-reviewer@example.invalid',company) WHERE person_id=private_person)
 THEN RAISE EXCEPTION 'Contact candidates ignore individual directory scope'; END IF;
 PERFORM pg_temp.expect_company_denial(format('SELECT public.application_set_company_contact_person(%L,%L,%L,true,NULL,%L)','company-outsider@example.invalid',company,first_person,'Synthetic denied'));
 PERFORM pg_temp.expect_company_denial(format('SELECT public.application_set_company_contact_person(%L,%L,%L,true,NULL,%L)','company-disabled@example.invalid',company,first_person,'Synthetic denied'));
 PERFORM pg_temp.expect_company_denial(format('SELECT public.application_set_company_contact_person(%L,%L,%L,true,NULL,%L)','company-legacy@example.invalid',company,first_person,'Synthetic denied'));
 PERFORM pg_temp.expect_company_denial(format('SELECT public.application_set_company_contact_person(%L,%L,%L,true,NULL,%L)','company-reviewer@example.invalid',company,private_person,'Synthetic restricted'));
 PERFORM pg_temp.expect_company_denial(format('SELECT public.application_set_company_contact_person(%L,%L,%L,true,NULL,%L)','company-reviewer@example.invalid',company,first_person,'  '));
 link:=public.application_set_company_contact_person('company-reviewer@example.invalid',company,first_person,true,NULL,'Synthetic first contact');
 UPDATE public.organization_contact_people SET updated_at='2000-01-01 00:00:00.123456+00'
  WHERE organization_contact_person_id=link.organization_contact_person_id;
 SELECT * INTO link FROM public.organization_contact_people WHERE organization_contact_person_id=link.organization_contact_person_id;
 IF NOT EXISTS(SELECT 1 FROM public.application_company_contact_people('company-reviewer@example.invalid',company)
   WHERE updated_at LIKE '%123456%') THEN RAISE EXCEPTION 'Relationship version lost microsecond precision'; END IF;
 second_link:=public.application_set_company_contact_person('company-reviewer@example.invalid',company,second_person,true,NULL,'Synthetic second contact');
 PERFORM public.application_set_company_contact_person('company-manager@example.invalid',second_company,first_person,true,NULL,'Synthetic shared contact');
 -- A contact can be an identity without either capacity; only a manager sees the unscoped identity.
 PERFORM public.application_set_company_contact_person('company-manager@example.invalid',second_company,private_person,true,NULL,'Synthetic standalone contact');
 IF (SELECT count(*) FROM public.application_company_contact_people('company-reviewer@example.invalid',company) WHERE status='active')<>2
 OR (SELECT count(*) FROM public.organization_contact_people WHERE person_id=first_person)<>2
 THEN RAISE EXCEPTION 'Multiple contacts / shared contact relationship failed'; END IF;
 IF EXISTS(SELECT 1 FROM public.application_company_contact_people('company-outsider@example.invalid',company))
 OR EXISTS(SELECT 1 FROM public.application_company_contact_candidates('company-disabled@example.invalid',company))
 OR EXISTS(SELECT 1 FROM public.application_company_contact_people('company-legacy@example.invalid',company))
 THEN RAISE EXCEPTION 'Unauthorized contact-person read'; END IF;
 IF EXISTS(SELECT 1 FROM public.application_company_contact_candidates('company-reviewer@example.invalid',company) WHERE person_id=first_person)
 THEN RAISE EXCEPTION 'Already linked person remains an add candidate'; END IF;
 PERFORM pg_temp.expect_company_denial(format('SELECT public.application_set_company_contact_person(%L,%L,%L,true,NULL,%L)','company-reviewer@example.invalid',company,first_person,'Synthetic duplicate'));
 PERFORM pg_temp.expect_company_denial(format('SELECT public.application_set_company_contact_person(%L,%L,%L,false,NULL,%L)','company-reviewer@example.invalid',company,first_person,'Synthetic missing version'));
 later:=public.application_set_company_contact_person('company-reviewer@example.invalid',company,first_person,false,link.updated_at,'Synthetic archive');
 IF later.organization_contact_person_id<>link.organization_contact_person_id OR later.status<>'archived'
 THEN RAISE EXCEPTION 'Archive lost stable relationship identity'; END IF;
 PERFORM pg_temp.expect_company_denial(format('SELECT public.application_set_company_contact_person(%L,%L,%L,true,%L,%L)','company-reviewer@example.invalid',company,first_person,link.updated_at,'Synthetic stale reopen'));
 later:=public.application_set_company_contact_person('company-reviewer@example.invalid',company,first_person,true,later.updated_at,'Synthetic restore');
 IF later.organization_contact_person_id<>link.organization_contact_person_id OR later.status<>'active'
 THEN RAISE EXCEPTION 'Reactivation did not retain identity'; END IF;
 IF (SELECT count(*) FROM public.person_roles)<>role_count OR (SELECT count(*) FROM public.members)<>member_count
 OR (SELECT count(*) FROM public.contributors)<>contributor_count OR (SELECT count(*) FROM public.party_contacts)<>contact_count
 THEN RAISE EXCEPTION 'Relationship implicitly changed capacity, permissions or contact/consent'; END IF;
 IF EXISTS(SELECT 1 FROM public.issue19_directory_entries('company-outsider@example.invalid') WHERE party_id=company)
 THEN RAISE EXCEPTION 'Relationship granted company directory access'; END IF;
 IF (SELECT count(*) FROM public.audit_log WHERE action='organization_contact_person.changed' AND entity_id IN(company::text,second_company::text))<>6
 OR NOT EXISTS(SELECT 1 FROM public.audit_log WHERE action='organization_contact_person.changed'
   AND actor='company-manager@example.invalid' AND details->>'actor_person_id'=manager::text)
 THEN RAISE EXCEPTION 'Canonical audit count or normalized actor incorrect'; END IF;
 UPDATE public.contributors SET status='archived' WHERE organization_id=company;
 PERFORM pg_temp.expect_company_denial(format('SELECT public.application_set_company_contact_person(%L,%L,%L,false,%L,%L)','company-reviewer@example.invalid',company,first_person,later.updated_at,'Synthetic archived company'));
 IF EXISTS(SELECT 1 FROM public.application_company_contact_people('company-reviewer@example.invalid',company)) THEN RAISE EXCEPTION 'Archived company scope broadened'; END IF;
 UPDATE public.contributors SET status='active' WHERE organization_id=company;
 SELECT count(*) INTO old_audits FROM public.audit_log;
 CREATE FUNCTION pg_temp.reject_company_audit() RETURNS trigger LANGUAGE plpgsql AS $fail$
 BEGIN IF NEW.action='organization_contact_person.changed' THEN RAISE EXCEPTION 'Synthetic audit failure'; END IF; RETURN NEW; END $fail$;
 CREATE TRIGGER synthetic_company_audit_failure BEFORE INSERT ON public.audit_log FOR EACH ROW EXECUTE FUNCTION pg_temp.reject_company_audit();
 PERFORM pg_temp.expect_company_denial(format('SELECT public.application_set_company_contact_person(%L,%L,%L,false,%L,%L)','company-reviewer@example.invalid',company,first_person,later.updated_at,'Synthetic audit rollback'));
 PERFORM pg_temp.expect_company_denial(format('SELECT public.application_set_company_contact_person(%L,%L,%L,true,NULL,%L)','company-manager@example.invalid',company,private_person,'Synthetic create rollback'));
 IF NOT EXISTS(SELECT 1 FROM public.organization_contact_people WHERE organization_contact_person_id=link.organization_contact_person_id AND status='active' AND updated_at=later.updated_at)
 OR EXISTS(SELECT 1 FROM public.organization_contact_people WHERE organization_id=company AND person_id=private_person)
 OR (SELECT count(*) FROM public.audit_log)<>old_audits THEN RAISE EXCEPTION 'Audit failure did not roll back relationship write'; END IF;
 DROP TRIGGER synthetic_company_audit_failure ON public.audit_log;
END $$;
SET CONSTRAINTS ALL IMMEDIATE;
ROLLBACK;
