-- Regression checks for contributor email Listmonk subscription support.
\set ON_ERROR_STOP on
BEGIN;
DO $$
DECLARE
  v_actor_person uuid;
  v_actor_email text := 'listmonk-test-actor@example.invalid';
  v_contributor_id uuid;
  v_party_id uuid;
  v_email_id uuid;
  v_queue_id uuid;
  v_optout_id uuid;
  v_member_id uuid;
  v_member_email_id uuid;
BEGIN
  INSERT INTO public.people(display_name)
    VALUES ('Listmonk Test Reviewer')
    RETURNING person_id INTO v_actor_person;
  INSERT INTO public.person_app_accounts(person_id,email)
    VALUES (v_actor_person,v_actor_email);
  INSERT INTO public.person_roles(person_id,role_key,assigned_by)
    VALUES (v_actor_person,'donations_reviewer','listmonk_test');

  SELECT party_id, contributor_id INTO v_party_id, v_contributor_id
  FROM public.issue19_create_contributor_with_mailing(
    v_actor_email,'organization',NULL,NULL,'Listmonk Test Company',
    'listmonk-contributor@example.invalid',NULL,'Listmonk contributor opt-in test',true
  );

  SELECT contributor_email_id INTO v_email_id
  FROM public.contributor_emails
  WHERE contributor_id=v_contributor_id
    AND email_normalized='listmonk-contributor@example.invalid'
    AND status='active';

  IF v_email_id IS NULL THEN
    RAISE EXCEPTION 'Contributor email was not created';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.contributor_emails
    WHERE contributor_email_id=v_email_id
      AND mailing_subscription_status='subscribed'
      AND mailing_subscription_source='intake'
  ) THEN
    RAISE EXCEPTION 'Contributor mailing preference was not recorded';
  END IF;

  SELECT listmonk_sync_queue_id INTO v_queue_id
  FROM public.listmonk_sync_queue
  WHERE contributor_email_id=v_email_id AND event_type='subscribe'
  ORDER BY created_at DESC LIMIT 1;
  IF v_queue_id IS NULL THEN
    RAISE EXCEPTION 'Contributor subscription did not enqueue';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.listmonk_sync_queue
    WHERE listmonk_sync_queue_id=v_queue_id AND member_email_id IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'Contributor queue row incorrectly references member email';
  END IF;

  PERFORM public.listmonk_mark_sync_success(
    v_queue_id,12345,NULL,'{"test":true}'::jsonb
  );
  IF NOT EXISTS (
    SELECT 1 FROM public.contributor_emails
    WHERE contributor_email_id=v_email_id
      AND listmonk_sync_status='synced'
      AND listmonk_subscriber_id=12345
  ) THEN
    RAISE EXCEPTION 'Contributor sync success did not update contributor email';
  END IF;

  UPDATE public.listmonk_sync_queue
  SET attempts=5, status='processing'
  WHERE listmonk_sync_queue_id=v_queue_id;
  PERFORM public.listmonk_mark_sync_failure(
    v_queue_id,'synthetic failure','{"test":true}'::jsonb
  );
  IF NOT EXISTS (
    SELECT 1 FROM public.contributor_emails
    WHERE contributor_email_id=v_email_id
      AND listmonk_sync_status='failed'
      AND listmonk_sync_error='synthetic failure'
  ) THEN
    RAISE EXCEPTION 'Contributor sync failure did not update contributor email';
  END IF;

  SELECT contributor_id INTO v_contributor_id
  FROM public.issue19_create_contributor_with_mailing(
    v_actor_email,'individual','Opt','Out',NULL,
    'listmonk-optout@example.invalid',NULL,'Listmonk opt-out test',false
  );
  SELECT contributor_email_id INTO v_optout_id
  FROM public.contributor_emails
  WHERE contributor_id=v_contributor_id
    AND email_normalized='listmonk-optout@example.invalid'
    AND status='active';

  IF NOT EXISTS (
    SELECT 1 FROM public.contributor_emails
    WHERE contributor_email_id=v_optout_id
      AND mailing_subscription_status='not_subscribed'
  ) THEN
    RAISE EXCEPTION 'Contributor opt-out was not recorded';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.listmonk_sync_queue
    WHERE contributor_email_id=v_optout_id
  ) THEN
    RAISE EXCEPTION 'Not-subscribed contributor email was queued';
  END IF;

  INSERT INTO public.members(person_id,email,notes)
    VALUES (v_actor_person,'listmonk-member@example.invalid','synthetic test member')
    RETURNING member_id INTO v_member_id;
  INSERT INTO public.member_emails(
    member_id,email,is_primary,source,mailing_subscription_status
  ) VALUES (
    v_member_id,'listmonk-member-contact@example.invalid',true,
    'listmonk_test','subscribed'
  ) RETURNING member_email_id INTO v_member_email_id;

  IF NOT EXISTS (
    SELECT 1 FROM public.listmonk_sync_queue q
    WHERE q.member_email_id=v_member_email_id
      AND q.contributor_email_id IS NULL
      AND q.event_type='subscribe'
  ) THEN
    RAISE EXCEPTION 'Existing member Listmonk queue behavior regressed';
  END IF;

  BEGIN
    INSERT INTO public.listmonk_sync_queue(
      member_email_id,contributor_email_id,email_normalized,event_type,source
    ) VALUES (v_member_email_id,v_optout_id,'invalid-both@example.invalid','subscribe','test');
    RAISE EXCEPTION 'Queue allowed both member and contributor email IDs';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO public.listmonk_sync_queue(
      member_email_id,contributor_email_id,email_normalized,event_type,source
    ) VALUES (NULL,NULL,'invalid-neither@example.invalid','subscribe','test');
    RAISE EXCEPTION 'Queue allowed neither member nor contributor email ID';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  PERFORM public.listmonk_record_external_unsubscribe(
    'listmonk-contributor@example.invalid',12345,NULL,'listmonk_test','{"test":true}'::jsonb
  );
  IF NOT EXISTS (
    SELECT 1 FROM public.contributor_emails
    WHERE contributor_email_id=v_email_id
      AND mailing_subscription_status='unsubscribed'
      AND listmonk_subscriber_id=12345
  ) THEN
    RAISE EXCEPTION 'Contributor external unsubscribe was not reflected';
  END IF;

  RAISE NOTICE 'Contributor Listmonk checks passed; rolling back synthetic records.';
END $$;
ROLLBACK;
