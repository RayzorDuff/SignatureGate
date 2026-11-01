-- Issue #19 verification: person contact reassignment.
\set ON_ERROR_STOP on

SELECT to_regprocedure(
  'public.issue19_reassign_person_contact(text,uuid,text,text,uuid,uuid,text)'
) AS reassign_function;

SELECT tg.tgname, c.relname AS source_table
FROM pg_trigger tg
JOIN pg_class c ON c.oid = tg.tgrelid
WHERE tg.tgname IN (
  'trg_member_emails_party_contact',
  'trg_member_phones_party_contact',
  'trg_member_addresses_party_contact',
  'trg_contributor_emails_party_contact',
  'trg_contributor_phones_party_contact',
  'trg_contributor_addresses_party_contact'
)
ORDER BY c.relname;

DO $$
BEGIN
  IF to_regprocedure(
    'public.issue19_reassign_person_contact(text,uuid,text,text,uuid,uuid,text)'
  ) IS NULL THEN
    RAISE EXCEPTION 'Issue #19 person contact reassignment function is missing';
  END IF;

  IF (
    SELECT count(*)
    FROM pg_trigger tg
    JOIN pg_class c ON c.oid = tg.tgrelid
    WHERE tg.tgname IN (
      'trg_member_emails_party_contact',
      'trg_member_phones_party_contact',
      'trg_member_addresses_party_contact',
      'trg_contributor_emails_party_contact',
      'trg_contributor_phones_party_contact',
      'trg_contributor_addresses_party_contact'
    )
  ) <> 6 THEN
    RAISE EXCEPTION 'Expected all six party-contact source synchronization triggers';
  END IF;
END $$;


BEGIN;
DO $test$
DECLARE
  reviewer uuid;
  outsider uuid;
  source_person uuid;
  target_person uuid;
  source_member uuid;
  target_member uuid;
  source_contributor uuid;
  email_id uuid;
  phone_id uuid;
  address_id uuid;
  shared_contact uuid;
  kind text;
  contact_id uuid;
  source_relation text;
  moved_owner uuid;
BEGIN
  INSERT INTO public.people(display_name) VALUES ('Synthetic Contact Reviewer') RETURNING person_id INTO reviewer;
  INSERT INTO public.people(display_name) VALUES ('Synthetic Contact Outsider') RETURNING person_id INTO outsider;
  INSERT INTO public.person_app_accounts(person_id,email) VALUES
    (reviewer,'archived-contact-reviewer@example.invalid'),
    (outsider,'archived-contact-outsider@example.invalid');
  INSERT INTO public.person_roles(person_id,role_key,assigned_by) VALUES
    (reviewer,'document_reviewer','synthetic_test'),
    (outsider,'donations_reviewer','synthetic_test');
  INSERT INTO public.people(display_name) VALUES ('Synthetic Former Participant') RETURNING person_id INTO source_person;
  INSERT INTO public.people(display_name) VALUES ('Synthetic Target Participant') RETURNING person_id INTO target_person;
  INSERT INTO public.members(person_id) VALUES (source_person) RETURNING member_id INTO source_member;
  INSERT INTO public.members(person_id) VALUES (target_person) RETURNING member_id INTO target_member;
  INSERT INTO public.contributors(contributor_type,person_id) VALUES ('individual',source_person) RETURNING contributor_id INTO source_contributor;
  INSERT INTO public.member_emails(member_id,email,is_primary) VALUES
    (source_member,'synthetic-reassigned@example.invalid',true) RETURNING member_email_id INTO email_id;
  INSERT INTO public.contributor_emails(contributor_id,email) VALUES
    (source_contributor,'synthetic-reassigned@example.invalid');
  SELECT party_contact_id INTO STRICT shared_contact FROM public.party_contact_sources
    WHERE source_table='member_emails' AND source_id=email_id;
  INSERT INTO public.member_phones(member_id,phone,is_primary) VALUES
    (source_member,'5550100141',true) RETURNING member_phone_id INTO phone_id;
  INSERT INTO public.member_addresses(member_id,address_1,city,state,postal_code,is_primary) VALUES
    (source_member,'100 Synthetic Street','Synthetic Town','CO','00000',true) RETURNING member_address_id INTO address_id;
  UPDATE public.members SET status='inactive' WHERE member_id=source_member;

  -- A former enrollment must not require reactivation just to correct ownership.
  BEGIN
    PERFORM public.issue19_reassign_person_contact('archived-contact-outsider@example.invalid',source_person,
      'member','email',email_id,target_person,'Denied cross-capacity attempt');
    RAISE EXCEPTION 'Donations-only reviewer moved a Participant contact';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'Document reviewer permission required' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM public.issue19_reassign_person_contact('archived-contact-reviewer@example.invalid',source_person,
      'member','email',email_id,target_person,' ');
    RAISE EXCEPTION 'Reassignment without a reason succeeded';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'Capacity, contact, target, and reason are required' THEN RAISE; END IF;
  END;
  UPDATE public.person_app_accounts SET status='disabled' WHERE person_id=reviewer;
  BEGIN
    PERFORM public.issue19_reassign_person_contact('archived-contact-reviewer@example.invalid',source_person,
      'member','email',email_id,target_person,'Denied disabled account');
    RAISE EXCEPTION 'Disabled reviewer account moved a contact';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'Document reviewer permission required' THEN RAISE; END IF;
  END;
  UPDATE public.person_app_accounts SET status='active' WHERE person_id=reviewer;
  BEGIN
    PERFORM public.issue19_reassign_person_contact('archived-contact-reviewer@example.invalid',source_person,
      NULL,'email',email_id,target_person,'Denied missing capacity');
    RAISE EXCEPTION 'Missing contact capacity was accepted';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'Capacity, contact, target, and reason are required' THEN RAISE; END IF;
  END;
  UPDATE public.members SET status='inactive' WHERE member_id=target_member;
  BEGIN
    PERFORM public.issue19_reassign_person_contact('archived-contact-reviewer@example.invalid',source_person,
      'member','email',email_id,target_person,'Denied inactive target');
    RAISE EXCEPTION 'Inactive target accepted a moved contact';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'Active membership not found for target individual' THEN RAISE; END IF;
  END;
  UPDATE public.members SET status='active' WHERE member_id=target_member;

  FOR kind,contact_id,source_relation IN
    SELECT 'email',email_id,'member_emails' UNION ALL
    SELECT 'phone',phone_id,'member_phones' UNION ALL
    SELECT 'address',address_id,'member_addresses'
  LOOP
    IF NOT public.issue19_reassign_person_contact('archived-contact-reviewer@example.invalid',source_person,
        'member',kind,contact_id,target_person,'Correct synthetic contact ownership') THEN
      RAISE EXCEPTION 'Former Participant contact did not move: %',kind;
    END IF;
    SELECT pc.person_id INTO STRICT moved_owner
      FROM public.party_contact_sources ps JOIN public.party_contacts pc USING(party_contact_id)
      WHERE ps.source_table=source_relation AND ps.source_id=contact_id AND ps.status='active'
        AND pc.status='active' AND pc.contact_kind=kind AND NOT ps.is_primary;
    IF moved_owner IS DISTINCT FROM target_person THEN
      RAISE EXCEPTION 'Canonical ownership/primary handling failed: %',kind;
    END IF;
    BEGIN
      PERFORM public.issue19_reassign_person_contact('archived-contact-reviewer@example.invalid',source_person,
        'member',kind,contact_id,target_person,'Stale source retry');
      RAISE EXCEPTION 'Stale source reassigned a contact twice: %',kind;
    EXCEPTION WHEN raise_exception THEN
      IF SQLERRM <> 'Active contact does not belong to the selected source individual' THEN RAISE; END IF;
    END;
  END LOOP;
  IF NOT EXISTS (SELECT 1 FROM public.member_emails WHERE member_email_id=email_id AND member_id=target_member)
     OR NOT EXISTS (SELECT 1 FROM public.member_phones WHERE member_phone_id=phone_id AND member_id=target_member)
     OR NOT EXISTS (SELECT 1 FROM public.member_addresses WHERE member_address_id=address_id AND member_id=target_member) THEN
    RAISE EXCEPTION 'Domain contact IDs or ownership changed unexpectedly';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.party_contacts WHERE party_contact_id=shared_contact AND person_id=source_person AND status='active')
     OR NOT EXISTS (SELECT 1 FROM public.contributor_emails WHERE contributor_id=source_contributor AND email='synthetic-reassigned@example.invalid' AND status='active') THEN
    RAISE EXCEPTION 'Moving Participant purpose changed retained Contributor purpose';
  END IF;
  IF (SELECT status FROM public.members WHERE member_id=source_member) <> 'inactive' THEN
    RAISE EXCEPTION 'Contact correction reactivated the former Participant';
  END IF;
  IF (SELECT count(*) FROM public.audit_log WHERE action='person_contact.reassigned'
      AND actor='archived-contact-reviewer@example.invalid'
      AND details->>'source_person_id'=source_person::text
      AND details->>'target_person_id'=target_person::text) <> 3 THEN
    RAISE EXCEPTION 'Contact moves were not audited exactly once';
  END IF;
END $test$;
SET CONSTRAINTS ALL IMMEDIATE;
ROLLBACK;

SELECT 'Person contact reassignment metadata and behavior checks passed; fixtures rolled back.' AS status;
