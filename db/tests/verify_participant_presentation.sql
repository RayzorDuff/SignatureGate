-- Rollback-only presentation checks; labels must never confer capacities or permissions.
\set ON_ERROR_STOP on
BEGIN;
DO $test$
DECLARE manager uuid; outsider uuid; before_roles bigint; before_members bigint; before_contributors bigint;
 before_agreements bigint; denied boolean:=false; changed boolean; before_audits bigint;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.issue20_organization_terminology() WHERE concept_key='member'
   AND singular_label='Participant' AND plural_label='Participants' AND is_active) THEN
  RAISE EXCEPTION 'Participant enrollment presentation must be adopted before this verification';
 END IF;
 INSERT INTO public.people(display_name) VALUES('Synthetic Presentation Manager') RETURNING person_id INTO manager;
 INSERT INTO public.person_app_accounts(person_id,email) VALUES(manager,'synthetic-presentation-manager@example.invalid');
 INSERT INTO public.person_roles(person_id,role_key,assigned_by) VALUES(manager,'directory_manager','synthetic');
 INSERT INTO public.people(display_name) VALUES('Synthetic Presentation Outsider') RETURNING person_id INTO outsider;
 INSERT INTO public.person_app_accounts(person_id,email) VALUES(outsider,'synthetic-presentation-outsider@example.invalid');
 SELECT count(*) INTO before_roles FROM public.person_roles;
 SELECT count(*) INTO before_members FROM public.members;
 SELECT count(*) INTO before_contributors FROM public.contributors;
 SELECT count(*) INTO before_agreements FROM public.member_agreements;
 SELECT count(*) INTO before_audits FROM public.audit_log WHERE actor='synthetic-presentation-manager@example.invalid';
 BEGIN
  PERFORM public.issue20_set_organization_terminology('synthetic-presentation-outsider@example.invalid','member','Attendee','Attendees',NULL,true,'Synthetic denial');
 EXCEPTION WHEN OTHERS THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'Non-manager changed labels'; END IF;
 changed:=public.issue20_set_organization_terminology('synthetic-presentation-manager@example.invalid','member','Attendee','Attendees',NULL,true,'Synthetic alternate presentation');
 IF NOT changed THEN RAISE EXCEPTION 'Alternate Participant label did not change'; END IF;
 changed:=public.issue20_set_organization_terminology('synthetic-presentation-manager@example.invalid','member','Attendee','Attendees',NULL,true,'Synthetic no-op');
 IF changed THEN RAISE EXCEPTION 'Repeated labels must report no change'; END IF;
 PERFORM public.issue20_set_organization_terminology('synthetic-presentation-manager@example.invalid','practitioner','Guide','Guides',NULL,true,'Synthetic alternate presentation');
 IF NOT EXISTS(SELECT 1 FROM public.issue20_organization_terminology() WHERE concept_key='member' AND singular_label='Attendee')
  OR NOT EXISTS(SELECT 1 FROM public.issue20_organization_terminology() WHERE concept_key='practitioner' AND singular_label='Guide') THEN
  RAISE EXCEPTION 'Alternate labels are not returned by the canonical reader';
 END IF;
 IF (SELECT count(*) FROM public.person_roles)<>before_roles OR (SELECT count(*) FROM public.members)<>before_members
  OR (SELECT count(*) FROM public.contributors)<>before_contributors OR (SELECT count(*) FROM public.member_agreements)<>before_agreements THEN
  RAISE EXCEPTION 'Presentation changed permissions, capacities or agreements';
 END IF;
 IF (SELECT count(*) FROM public.audit_log WHERE actor='synthetic-presentation-manager@example.invalid')<>before_audits+2 THEN
  RAISE EXCEPTION 'Label audit/no-op behavior is incorrect';
 END IF;
 RAISE NOTICE 'Participant presentation, alternate labels, authority, no-op and domain invariants passed; rolling back synthetic changes.';
END;
$test$;
ROLLBACK;
