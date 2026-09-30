-- Rollback-only checks for contributor archive/reactivation.
\set ON_ERROR_STOP on
BEGIN;
DO $$
DECLARE
  v_actor uuid; v_denied uuid; v_person uuid; v_org uuid;
  v_member uuid; v_contributor uuid; v_org_contributor uuid;
  v_donation uuid; v_email uuid; v_external uuid; v_link uuid;
BEGIN
  INSERT INTO public.people(display_name) VALUES ('Contributor Status Manager')
    RETURNING person_id INTO v_actor;
  INSERT INTO public.person_app_accounts(person_id,email)
    VALUES (v_actor,'issue19-status-manager@example.invalid');
  INSERT INTO public.person_roles(person_id,role_key,assigned_by)
    VALUES (v_actor,'directory_manager','issue19_test'),
      (v_actor,'donations_reviewer','issue19_test');

  INSERT INTO public.people(display_name) VALUES ('Contributor Status Denied')
    RETURNING person_id INTO v_denied;
  INSERT INTO public.person_app_accounts(person_id,email)
    VALUES (v_denied,'issue19-status-denied@example.invalid');

  INSERT INTO public.people(display_name,first_name,last_name)
    VALUES ('Contributor Status Person','Contributor','Status')
    RETURNING person_id INTO v_person;
  INSERT INTO public.members(person_id) VALUES (v_person) RETURNING member_id INTO v_member;
  INSERT INTO public.contributors(contributor_type,person_id,source)
    VALUES ('individual',v_person,'issue19_test') RETURNING contributor_id INTO v_contributor;
  INSERT INTO public.contributor_member_links(contributor_id,member_id,link_reason)
    VALUES (v_contributor,v_member,'issue19_test') RETURNING contributor_member_link_id INTO v_link;
  INSERT INTO public.contributor_emails(contributor_id,email,is_primary,source)
    VALUES (v_contributor,'issue19-status-person@example.invalid',true,'issue19_test')
    RETURNING contributor_email_id INTO v_email;
  INSERT INTO public.contributor_external_identities
    (contributor_id,provider,provider_identity,source)
    VALUES (v_contributor,'givebutter','issue19-status-person','issue19_test')
    RETURNING contributor_external_identity_id INTO v_external;
  INSERT INTO public.donations(contributor_id,donor_kind,provider,
    provider_reference,amount_cents,status)
    VALUES (v_contributor,'identified','givebutter','issue19-status-donation',2500,'verified')
    RETURNING donation_id INTO v_donation;

  BEGIN
    PERFORM public.issue19_set_contributor_status(
      'issue19-status-denied@example.invalid','individual',v_person,'archived','Denied test');
    RAISE EXCEPTION 'Unauthorized actor archived contributor';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'Directory manager and donations reviewer permissions required'
    THEN RAISE; END IF;
  END;

  PERFORM public.issue19_set_contributor_status(
    'issue19-status-manager@example.invalid','individual',v_person,'archived','No longer accepting contributions');
  IF NOT EXISTS (SELECT 1 FROM public.contributors
       WHERE contributor_id=v_contributor AND status='archived'
         AND archived_at IS NOT NULL AND archive_reason='No longer accepting contributions')
    OR NOT EXISTS (SELECT 1 FROM public.issue19_directory_entries(
       'issue19-status-manager@example.invalid')
       WHERE party_kind='individual' AND party_id=v_person
         AND contributor_id=v_contributor AND contributor_status='archived')
    OR EXISTS (SELECT 1 FROM public.issue19_directory_entries(
       'issue19-status-denied@example.invalid')
       WHERE party_kind='individual' AND party_id=v_person AND contributor_id IS NOT NULL)
    OR NOT EXISTS (SELECT 1 FROM public.issue19_contributor_status_state(
       'issue19-status-manager@example.invalid','individual',v_person)
       WHERE current_status='archived' AND can_reactivate AND NOT can_archive)
    OR NOT EXISTS (SELECT 1 FROM public.issue19_contribution_history(
       'issue19-status-manager@example.invalid','individual',v_person)
       WHERE donation_id=v_donation) THEN
    RAISE EXCEPTION 'Archived contributor is not safely manageable or historically visible';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.contributor_emails
       WHERE contributor_email_id=v_email AND status='active')
    OR NOT EXISTS (SELECT 1 FROM public.contributor_external_identities
       WHERE contributor_external_identity_id=v_external AND status='active')
    OR NOT EXISTS (SELECT 1 FROM public.donations WHERE donation_id=v_donation)
    OR NOT EXISTS (SELECT 1 FROM public.contributor_member_links
       WHERE contributor_member_link_id=v_link AND status='active') THEN
    RAISE EXCEPTION 'Contributor archive changed related history';
  END IF;

  PERFORM public.issue19_set_contributor_status(
    'issue19-status-manager@example.invalid','individual',v_person,'active','Resuming contributions');
  IF NOT EXISTS (SELECT 1 FROM public.contributors
       WHERE contributor_id=v_contributor AND status='active'
         AND archived_at IS NULL AND archived_by IS NULL AND archive_reason IS NULL)
    OR (SELECT count(*) FROM public.audit_log
       WHERE entity_type='contributor' AND entity_id=v_contributor::text
         AND action IN ('contributor.archived','contributor.reactivated'))<>2 THEN
    RAISE EXCEPTION 'Contributor reactivation or auditing failed';
  END IF;

  INSERT INTO public.organizations(organization_name)
    VALUES ('Contributor Status Company') RETURNING organization_id INTO v_org;
  INSERT INTO public.contributors(contributor_type,organization_id,source)
    VALUES ('organization',v_org,'issue19_test') RETURNING contributor_id INTO v_org_contributor;
  PERFORM public.issue19_set_contributor_status(
    'issue19-status-manager@example.invalid','organization',v_org,'archived','Company inactive');
  IF NOT EXISTS (SELECT 1 FROM public.issue19_directory_entries(
       'issue19-status-manager@example.invalid')
       WHERE party_kind='organization' AND party_id=v_org
         AND contributor_status='archived') THEN
    RAISE EXCEPTION 'Archived organization disappeared from manager Directory';
  END IF;
  PERFORM public.issue19_set_contributor_status(
    'issue19-status-manager@example.invalid','organization',v_org,'active','Company resumed');

  RAISE NOTICE 'Contributor status lifecycle checks passed; rolling back synthetic records.';
END $$;
ROLLBACK;
