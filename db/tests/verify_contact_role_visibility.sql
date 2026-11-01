-- Rollback-only regression checks. Run after contact_role_visibility migration.
\set ON_ERROR_STOP on
BEGIN;
DO $$
DECLARE
  v_actor uuid; v_person uuid; v_member uuid; v_contributor uuid;
  v_email uuid; v_target uuid; v_contact uuid;
BEGIN
  INSERT INTO public.people(display_name) VALUES ('Contact Visibility Reviewer')
    RETURNING person_id INTO v_actor;
  INSERT INTO public.person_app_accounts(person_id,email)
    VALUES (v_actor,'issue19-visibility-reviewer@example.invalid');
  INSERT INTO public.person_roles(person_id,role_key,assigned_by)
    VALUES (v_actor,'directory_manager','issue19_test'),
      (v_actor,'document_reviewer','issue19_test'),
      (v_actor,'donations_reviewer','issue19_test');
  INSERT INTO public.people(display_name,first_name,last_name)
    VALUES ('Contact Visibility Person','Contact','Visibility')
    RETURNING person_id INTO v_person;
  INSERT INTO public.members(person_id) VALUES (v_person)
    RETURNING member_id INTO v_member;
  INSERT INTO public.member_emails(member_id,email,is_primary,source)
    VALUES (v_member,'issue19-visibility-person@example.invalid',true,'issue19_test')
    RETURNING member_email_id INTO v_email;
  IF NOT EXISTS (SELECT 1 FROM public.issue19_reusable_person_contacts(
       'issue19-visibility-reviewer@example.invalid',v_person)
       WHERE source_table='member_emails' AND source_id=v_email)
    OR EXISTS (SELECT 1 FROM public.issue19_former_member_contacts(
       'issue19-visibility-reviewer@example.invalid',v_person)) THEN
    RAISE EXCEPTION 'Member-only contacts must be listed before contributor enrollment';
  END IF;
  BEGIN
    PERFORM public.issue19_assign_person_contact_role(
      'issue19-visibility-reviewer@example.invalid',v_person,
      'member_emails',v_email,'Premature assignment test');
    RAISE EXCEPTION 'Assignment succeeded without an active destination';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'Enable this person as a contributor before assigning this contact'
    THEN RAISE; END IF;
  END;
  v_contributor := public.issue19_enable_person_contributor(
    'issue19-visibility-reviewer@example.invalid',v_person,'Review donor enrollment');
  PERFORM public.issue19_end_person_membership(
    'issue19-visibility-reviewer@example.invalid',v_person,
    'Continue as a contributor');
  IF NOT EXISTS (SELECT 1 FROM public.issue19_former_member_contacts(
       'issue19-visibility-reviewer@example.invalid',v_person)
       WHERE contact_kind='email' AND purpose='former membership'
         AND contact_detail='issue19-visibility-person@example.invalid')
    OR NOT EXISTS (SELECT 1 FROM public.issue19_reusable_person_contacts(
       'issue19-visibility-reviewer@example.invalid',v_person)
       WHERE source_table='member_emails' AND source_id=v_email)
    OR EXISTS (SELECT 1 FROM public.issue19_former_member_contacts(
       'unknown@example.invalid',v_person)) THEN
    RAISE EXCEPTION 'Ended-membership contacts are missing or exposed to unauthorized actors';
  END IF;
  v_target := public.issue19_assign_person_contact_role(
    'issue19-visibility-reviewer@example.invalid',v_person,
    'member_emails',v_email,'Keep the same email for donor receipts');
  SELECT ps.party_contact_id INTO v_contact FROM public.party_contact_sources ps
  WHERE ps.source_table='member_emails' AND ps.source_id=v_email;
  IF NOT EXISTS (SELECT 1 FROM public.contributor_emails
       WHERE contributor_email_id=v_target AND contributor_id=v_contributor
         AND status='active')
    OR NOT EXISTS (SELECT 1 FROM public.member_emails
       WHERE member_email_id=v_email AND member_id=v_member AND status='active')
    OR NOT EXISTS (SELECT 1 FROM public.party_contact_sources
       WHERE source_table='contributor_emails' AND source_id=v_target
         AND party_contact_id=v_contact AND status='active')
    OR NOT EXISTS (SELECT 1 FROM public.issue19_former_member_contacts(
       'issue19-visibility-reviewer@example.invalid',v_person)
       WHERE contact_kind='email')
    OR EXISTS (SELECT 1 FROM public.issue19_reusable_person_contacts(
       'issue19-visibility-reviewer@example.invalid',v_person)
       WHERE source_table='member_emails' AND source_id=v_email) THEN
    RAISE EXCEPTION 'Former-member reuse did not preserve both sources and history';
  END IF;
  BEGIN
    PERFORM public.issue19_assign_person_contact_role(
      'issue19-visibility-reviewer@example.invalid',v_person,
      'contributor_emails',v_target,'Inactive membership target test');
    RAISE EXCEPTION 'Assignment to ended membership succeeded';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'An active membership is required to assign a membership contact'
    THEN RAISE; END IF;
  END;
  RAISE NOTICE 'Former-member contact visibility and reuse checks passed; rolling back synthetic records.';
END $$;
ROLLBACK;
