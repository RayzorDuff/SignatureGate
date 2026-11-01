-- Rollback-only checks for Individual Profile membership contact maintenance.
\set ON_ERROR_STOP on
BEGIN;
DO $$
DECLARE
  v_reviewer_person uuid;
  v_outsider_person uuid;
  v_target_person uuid;
  v_target_member uuid;
  v_contributor_id uuid;
  v_email uuid;
  v_phone uuid;
  v_shared_email uuid;
BEGIN
  INSERT INTO public.people(display_name) VALUES ('Issue 19 Contact Reviewer')
    RETURNING person_id INTO v_reviewer_person;
  INSERT INTO public.person_app_accounts(person_id,email)
    VALUES (v_reviewer_person,'issue19-member-contact-reviewer@example.invalid');
  INSERT INTO public.person_roles(person_id,role_key,assigned_by)
    VALUES (v_reviewer_person,'document_reviewer','issue19_verify');

  INSERT INTO public.people(display_name) VALUES ('Issue 19 Contact Outsider')
    RETURNING person_id INTO v_outsider_person;
  INSERT INTO public.person_app_accounts(person_id,email)
    VALUES (v_outsider_person,'issue19-member-contact-outsider@example.invalid');
  INSERT INTO public.person_roles(person_id,role_key,assigned_by)
    VALUES (v_outsider_person,'donations_reviewer','issue19_verify');

  INSERT INTO public.people(display_name) VALUES ('Issue 19 Contact Target')
    RETURNING person_id INTO v_target_person;
  INSERT INTO public.members(person_id) VALUES (v_target_person)
    RETURNING member_id INTO v_target_member;
  -- Contributor identity fields are canonical in people; contributors stores
  -- only the independent contribution capacity after canonical_people.sql.
  INSERT INTO public.contributors(contributor_type,person_id)
    VALUES ('individual',v_target_person)
    RETURNING contributor_id INTO v_contributor_id;

  BEGIN
    PERFORM public.issue19_add_membership_contact(
      'issue19-member-contact-outsider@example.invalid',v_target_person,
      'email','issue19-target@example.invalid','Unauthorized test');
    RAISE EXCEPTION 'Donations-only reviewer modified membership contacts';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'Document reviewer permission required' THEN RAISE; END IF;
  END;

  v_email := public.issue19_add_membership_contact(
    'issue19-member-contact-reviewer@example.invalid',v_target_person,
    'email','issue19-target@example.invalid','Verified membership email');
  v_phone := public.issue19_add_membership_contact(
    'issue19-member-contact-reviewer@example.invalid',v_target_person,
    'phone','(970) 555-0199','Verified membership phone');
  IF NOT EXISTS (SELECT 1 FROM public.member_emails
      WHERE member_email_id=v_email AND member_id=v_target_member
        AND mailing_subscription_status='not_subscribed'
        AND source='issue19_individual_profile')
    OR NOT EXISTS (SELECT 1 FROM public.member_phones
      WHERE member_phone_id=v_phone AND member_id=v_target_member
        AND phone_normalized='9705550199')
    OR (SELECT count(*) FROM public.issue19_person_membership_contacts(
      'issue19-member-contact-reviewer@example.invalid',v_target_person)) <> 2
    OR EXISTS (SELECT 1 FROM public.contributor_emails
      WHERE contributor_id=v_contributor_id)
    OR EXISTS (SELECT 1 FROM public.contributor_phones
      WHERE contributor_id=v_contributor_id) THEN
    RAISE EXCEPTION 'Membership contact write crossed capacity boundaries';
  END IF;
  IF EXISTS (SELECT 1 FROM public.issue19_person_membership_contacts(
      'issue19-member-contact-outsider@example.invalid',v_target_person)) THEN
    RAISE EXCEPTION 'Donations-only reviewer read membership contacts';
  END IF;

  INSERT INTO public.contributor_emails(
    contributor_id,email,is_primary,source)
  VALUES (v_contributor_id,'issue19-shared@example.invalid',true,'issue19_verify')
  RETURNING contributor_email_id INTO v_shared_email;
  BEGIN
    PERFORM public.issue19_add_membership_contact(
      'issue19-member-contact-reviewer@example.invalid',v_target_person,
      'email','issue19-shared@example.invalid','Implicit sharing test');
    RAISE EXCEPTION 'Contributor contact was implicitly copied into membership';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'This is an existing contributor contact; use the reviewed cross-role assignment control'
    THEN RAISE; END IF;
  END;

  PERFORM public.issue19_archive_membership_contact(
    'issue19-member-contact-reviewer@example.invalid',v_target_person,
    'email',v_email,'No longer used for membership');
  IF NOT EXISTS (SELECT 1 FROM public.member_emails
      WHERE member_email_id=v_email AND status='archived'
        AND archive_reason='No longer used for membership')
    OR NOT EXISTS (SELECT 1 FROM public.contributor_emails
      WHERE contributor_email_id=v_shared_email AND status='active')
    OR (SELECT count(*) FROM public.audit_log
      WHERE entity_id IN (v_email::text,v_phone::text)
        AND action IN ('membership_contact.added','membership_contact.archived')) <> 3 THEN
    RAISE EXCEPTION 'Membership contact archive or audit check failed';
  END IF;

  UPDATE public.members SET status='inactive' WHERE member_id=v_target_member;
  IF NOT EXISTS (SELECT 1 FROM public.issue19_person_membership_contacts(
      'issue19-member-contact-reviewer@example.invalid',v_target_person)
      WHERE contact_id=v_phone) THEN
    RAISE EXCEPTION 'Former-member contact history disappeared';
  END IF;
  BEGIN
    PERFORM public.issue19_add_membership_contact(
      'issue19-member-contact-reviewer@example.invalid',v_target_person,
      'phone','9705550188','Inactive membership test');
    RAISE EXCEPTION 'Inactive membership accepted a new contact';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'An active membership and document reviewer access are required'
    THEN RAISE; END IF;
  END;

  RAISE NOTICE 'Individual Profile membership contact checks passed; rolling back synthetic records.';
END $$;
ROLLBACK;
