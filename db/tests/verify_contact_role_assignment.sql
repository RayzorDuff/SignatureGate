-- Rollback-only checks for sharing an existing person's contact between
-- membership and contributor capacities. Apply after contact-role migration.
\set ON_ERROR_STOP on
BEGIN;
DO $$
DECLARE
  v_actor uuid;
  v_person uuid;
  v_other_person uuid;
  v_member uuid;
  v_contributor uuid;
  v_other_member uuid;
  v_other_contributor uuid;
  v_foreign_phone uuid;
  v_foreign_email uuid;
  v_me uuid; v_mp uuid; v_ma uuid;
  v_ce uuid; v_cp uuid; v_ca uuid;
  v_new_member_email uuid;
  v_new_donor_email uuid;
  v_new_donor_address uuid;
BEGIN
  INSERT INTO public.people(display_name) VALUES ('Capacity Contact Reviewer')
    RETURNING person_id INTO v_actor;
  INSERT INTO public.person_app_accounts(person_id,email)
    VALUES (v_actor,'issue19-capacity-reviewer@example.invalid');
  INSERT INTO public.person_roles(person_id,role_key,assigned_by)
    VALUES (v_actor,'directory_manager','issue19_test'),
      (v_actor,'document_reviewer','issue19_test'),
      (v_actor,'donations_reviewer','issue19_test');
  INSERT INTO public.people(display_name,first_name,last_name)
    VALUES ('Capacity Contact Person','Capacity','Person')
    RETURNING person_id INTO v_person;
  INSERT INTO public.members(person_id) VALUES (v_person)
    RETURNING member_id INTO v_member;
  INSERT INTO public.contributors(contributor_type,person_id,source)
    VALUES ('individual',v_person,'issue19_test')
    RETURNING contributor_id INTO v_contributor;
  INSERT INTO public.member_emails(member_id,email,is_primary,is_verified,source)
    VALUES (v_member,'issue19-member-capacity@example.invalid',true,true,'issue19_test')
    RETURNING member_email_id INTO v_me;
  INSERT INTO public.member_phones(member_id,phone,is_primary,source)
    VALUES (v_member,'970-555-0182',true,'issue19_test')
    RETURNING member_phone_id INTO v_mp;
  INSERT INTO public.member_addresses(member_id,address_1,address_2,city,
    state,postal_code,country,is_primary,source)
    VALUES (v_member,'215 E Oak St','Apt 1','Fort Collins',
      'CO','80524','USA',true,'issue19_test')
    RETURNING member_address_id INTO v_ma;
  INSERT INTO public.contributor_emails(contributor_id,email,is_primary,source)
    VALUES (v_contributor,'issue19-donor-capacity@example.invalid',true,'issue19_test')
    RETURNING contributor_email_id INTO v_ce;
  INSERT INTO public.contributor_phones(contributor_id,phone,is_primary,source)
    VALUES (v_contributor,'970-555-0192',true,'issue19_test')
    RETURNING contributor_phone_id INTO v_cp;
  INSERT INTO public.contributor_addresses(contributor_id,address_1,address_2,
    city,state,postal_code,country,is_primary,source)
    VALUES (v_contributor,'215 E Oak St','Apt 2','Fort Collins',
      'CO','80524','USA',true,'issue19_test')
    RETURNING contributor_address_id INTO v_ca;

  IF (SELECT count(*) FROM public.issue19_reusable_person_contacts(
    'issue19-capacity-reviewer@example.invalid',v_person)) <> 6
    OR EXISTS (SELECT 1 FROM public.issue19_reusable_person_contacts(
      'unknown@example.invalid',v_person)) THEN
    RAISE EXCEPTION 'Only authorized cross-role contacts should be selectable';
  END IF;
  BEGIN
    PERFORM public.issue19_assign_person_contact_role(
      'unknown@example.invalid',v_person,'member_emails',v_me,'Denied test');
    RAISE EXCEPTION 'Unauthorized actor shared a contact';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'Directory manager and both reviewer permissions required'
    THEN RAISE; END IF;
  END;
  INSERT INTO public.people(display_name) VALUES ('Unrelated Contact Person')
    RETURNING person_id INTO v_other_person;
  INSERT INTO public.members(person_id) VALUES (v_other_person)
    RETURNING member_id INTO v_other_member;
  INSERT INTO public.member_emails(member_id,email,source)
    VALUES (v_other_member,'issue19-foreign-capacity@example.invalid','issue19_test')
    RETURNING member_email_id INTO v_foreign_email;
  BEGIN
    PERFORM public.issue19_assign_person_contact_role(
      'issue19-capacity-reviewer@example.invalid',v_person,
      'member_emails',v_foreign_email,'Wrong person test');
    RAISE EXCEPTION 'A foreign contact was shared';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'Active contact does not belong to this person and capacity'
    THEN RAISE; END IF;
  END;
  INSERT INTO public.contributors(contributor_type,person_id,source)
    VALUES ('individual',v_other_person,'issue19_test')
    RETURNING contributor_id INTO v_other_contributor;
  INSERT INTO public.contributor_phones(contributor_id,phone,source)
    VALUES (v_other_contributor,'970-555-0182','issue19_test')
    RETURNING contributor_phone_id INTO v_foreign_phone;
  BEGIN
    PERFORM public.issue19_assign_person_contact_role(
      'issue19-capacity-reviewer@example.invalid',v_person,
      'member_phones',v_mp,'Shared-phone test');
    RAISE EXCEPTION 'A shared cross-party phone was assigned without review';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'Contact belongs to another party; review before sharing it'
    THEN RAISE; END IF;
  END;
  UPDATE public.contributor_phones SET status='archived',is_primary=false
  WHERE contributor_phone_id=v_foreign_phone;

  v_new_donor_email := public.issue19_assign_person_contact_role(
    'issue19-capacity-reviewer@example.invalid',v_person,'member_emails',v_me,
    'Use member email for donation receipts');
  PERFORM public.issue19_assign_person_contact_role(
    'issue19-capacity-reviewer@example.invalid',v_person,'member_phones',v_mp,
    'Use member phone for donations');
  v_new_donor_address := public.issue19_assign_person_contact_role(
    'issue19-capacity-reviewer@example.invalid',v_person,'member_addresses',v_ma,
    'Use member address for donation mail');
  v_new_member_email := public.issue19_assign_person_contact_role(
    'issue19-capacity-reviewer@example.invalid',v_person,'contributor_emails',v_ce,
    'Use donor email for membership communication');
  PERFORM public.issue19_assign_person_contact_role(
    'issue19-capacity-reviewer@example.invalid',v_person,'contributor_phones',v_cp,
    'Use donor phone for membership');
  PERFORM public.issue19_assign_person_contact_role(
    'issue19-capacity-reviewer@example.invalid',v_person,'contributor_addresses',v_ca,
    'Use donor address for membership');

  IF (SELECT count(*) FROM public.issue19_reusable_person_contacts(
      'issue19-capacity-reviewer@example.invalid',v_person)) <> 0
    OR NOT EXISTS (SELECT 1 FROM public.member_emails
      WHERE member_email_id=v_new_member_email AND status='active'
        AND is_verified=false AND is_primary=false
        AND mailing_subscription_status='not_subscribed')
    OR EXISTS (SELECT 1 FROM public.listmonk_sync_queue
      WHERE member_email_id=v_new_member_email)
    OR NOT EXISTS (SELECT 1 FROM public.contributor_emails
      WHERE contributor_email_id=v_new_donor_email
        AND NOT is_primary AND NOT is_verified)
    OR NOT EXISTS (SELECT 1 FROM public.contributor_addresses
      WHERE contributor_address_id=v_new_donor_address
        AND address_2='Apt 1' AND NOT is_primary)
    OR (SELECT count(*) FROM public.party_contact_sources target
      JOIN public.party_contact_sources source
        ON source.party_contact_id=target.party_contact_id
      WHERE target.source_table LIKE 'contributor_%'
        AND source.source_table LIKE 'member_%'
        AND target.status='active' AND source.status='active'
        AND target.source_id IN (v_new_donor_email,v_new_donor_address)) <> 2
    OR (SELECT count(*) FROM public.audit_log
      WHERE action='person_contact.capacity_assigned'
        AND details->>'person_id'=v_person::text) <> 6 THEN
    RAISE EXCEPTION 'Capacity assignment lost identity, consent, or audit data';
  END IF;
  BEGIN
    PERFORM public.issue19_assign_person_contact_role(
      'issue19-capacity-reviewer@example.invalid',v_person,'member_emails',v_me,
      'Duplicate test');
    RAISE EXCEPTION 'Duplicate capacity assignment was allowed';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'Contact is already assigned to the other capacity'
    THEN RAISE; END IF;
  END;
  RAISE NOTICE 'Cross-role contact assignment checks passed; rolling back synthetic records.';
END $$;
ROLLBACK;
