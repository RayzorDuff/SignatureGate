-- Rollback-only checks for contributor history on individual/company profiles.
\set ON_ERROR_STOP on
BEGIN;
DO $$
DECLARE
  v_actor uuid; v_denied_actor uuid;
  v_person uuid; v_organization uuid;
  v_person_contributor uuid; v_org_contributor uuid;
  v_person_donation uuid; v_org_donation uuid;
BEGIN
  INSERT INTO public.people(display_name) VALUES ('Profile History Reviewer')
    RETURNING person_id INTO v_actor;
  INSERT INTO public.person_app_accounts(person_id,email)
    VALUES (v_actor,'issue19-profile-history@example.invalid');
  INSERT INTO public.person_roles(person_id,role_key,assigned_by)
    VALUES (v_actor,'donations_reviewer','issue19_test');

  INSERT INTO public.people(display_name) VALUES ('Profile History Denied')
    RETURNING person_id INTO v_denied_actor;
  INSERT INTO public.person_app_accounts(person_id,email)
    VALUES (v_denied_actor,'issue19-profile-history-denied@example.invalid');
  INSERT INTO public.person_roles(person_id,role_key,assigned_by)
    VALUES (v_denied_actor,'document_reviewer','issue19_test');

  INSERT INTO public.people(display_name,first_name,last_name)
    VALUES ('Profile History Person','Profile','Person')
    RETURNING person_id INTO v_person;
  INSERT INTO public.contributors(contributor_type,person_id,source)
    VALUES ('individual',v_person,'issue19_test')
    RETURNING contributor_id INTO v_person_contributor;
  INSERT INTO public.donations(contributor_id,donor_kind,provider,
    provider_reference,amount_cents,currency,status,donated_at)
    VALUES (v_person_contributor,'identified','givebutter',
      'issue19-profile-history-person',12345,'USD','verified',now()-interval '1 day')
    RETURNING donation_id INTO v_person_donation;
  INSERT INTO public.contributor_external_identities
    (contributor_id,provider,provider_identity,source)
    VALUES (v_person_contributor,'givebutter',
      'issue19-profile-history-person','issue19_test');

  INSERT INTO public.organizations(organization_name)
    VALUES ('Profile History Company') RETURNING organization_id INTO v_organization;
  INSERT INTO public.contributors(contributor_type,organization_id,source)
    VALUES ('organization',v_organization,'issue19_test')
    RETURNING contributor_id INTO v_org_contributor;
  INSERT INTO public.donations(contributor_id,donor_kind,provider,
    provider_reference,amount_cents,currency,status,donated_at)
    VALUES (v_org_contributor,'identified','cash',
      'issue19-profile-history-company',50000,'USD','verified',now())
    RETURNING donation_id INTO v_org_donation;
  INSERT INTO public.contributor_external_identities
    (contributor_id,provider,provider_identity,source)
    VALUES (v_org_contributor,'givebutter',
      'issue19-profile-history-company','issue19_test');

  IF NOT EXISTS (SELECT 1 FROM public.issue19_contribution_history(
       'issue19-profile-history@example.invalid','individual',v_person)
       WHERE donation_id=v_person_donation AND amount_cents=12345
         AND provider='givebutter' AND status='verified')
    OR NOT EXISTS (SELECT 1 FROM public.issue19_contributor_provider_identities(
       'issue19-profile-history@example.invalid','individual',v_person)
       WHERE provider='givebutter'
         AND provider_identity='issue19-profile-history-person')
    OR NOT EXISTS (SELECT 1 FROM public.issue19_contribution_history(
       'issue19-profile-history@example.invalid','organization',v_organization)
       WHERE donation_id=v_org_donation AND amount_cents=50000)
    OR NOT EXISTS (SELECT 1 FROM public.issue19_contributor_provider_identities(
       'issue19-profile-history@example.invalid','organization',v_organization)
       WHERE provider_identity='issue19-profile-history-company') THEN
    RAISE EXCEPTION 'Authorized profile history omitted contributor data';
  END IF;

  IF EXISTS (SELECT 1 FROM public.issue19_contribution_history(
       'issue19-profile-history-denied@example.invalid','individual',v_person))
    OR EXISTS (SELECT 1 FROM public.issue19_contributor_provider_identities(
       'issue19-profile-history-denied@example.invalid','organization',v_organization))
    OR EXISTS (SELECT 1 FROM public.issue19_contribution_history(
       'issue19-profile-history@example.invalid','individual',v_organization))
    OR EXISTS (SELECT 1 FROM public.issue19_contributor_provider_identities(
       'issue19-profile-history@example.invalid','organization',v_person)) THEN
    RAISE EXCEPTION 'Profile history escaped actor or party-kind scope';
  END IF;

  IF (SELECT count(*) FROM public.donations
      WHERE donation_id IN (v_person_donation,v_org_donation))<>2 THEN
    RAISE EXCEPTION 'Read projections modified donation history';
  END IF;
  RAISE NOTICE 'Contributor profile history checks passed; rolling back synthetic records.';
END $$;
ROLLBACK;
