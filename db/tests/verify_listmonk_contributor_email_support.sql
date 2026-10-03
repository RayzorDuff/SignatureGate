-- Regression checks for contributor email Listmonk subscription support.
\set ON_ERROR_STOP on
BEGIN;
DO $$
DECLARE
  v_person uuid;
  v_contributor uuid;
  v_email uuid;
  v_queue uuid;
  v_member_email uuid;
BEGIN
  INSERT INTO public.people(display_name) VALUES ('Listmonk Contributor Test') RETURNING person_id INTO v_person;
  INSERT INTO public.contributors(contributor_type,person_id,source,notes)
    VALUES ('individual',v_person,'listmonk_test','synthetic test contributor')
    RETURNING contributor_id INTO v_contributor;

  INSERT INTO public.contributor_emails(contributor_id,email,is_primary,source,mailing_subscription_status,mailing_subscription_source)
    VALUES (v_contributor,'listmonk-contributor@example.invalid',true,'listmonk_test','subscribed','listmonk_test')
    RETURNING contributor_email_id INTO v_email;

  SELECT listmonk_sync_queue_id INTO v_queue
  FROM public.listmonk_sync_queue
  WHERE contributor_email_id=v_email AND event_type='subscribe'
  ORDER BY created_at DESC LIMIT 1;
  IF v_queue IS NULL THEN RAISE EXCEPTION 'Contributor subscription did not enqueue'; END IF;
  IF EXISTS (SELECT 1 FROM public.listmonk_sync_queue WHERE listmonk_sync_queue_id=v_queue AND member_email_id IS NOT NULL)
    THEN RAISE EXCEPTION 'Contributor queue row incorrectly references member email'; END IF;

  PERFORM public.listmonk_mark_sync_success(v_queue,12345,NULL,'{"test":true}'::jsonb);
  IF NOT EXISTS (SELECT 1 FROM public.contributor_emails WHERE contributor_email_id=v_email AND listmonk_sync_status='synced' AND listmonk_subscriber_id=12345)
    THEN RAISE EXCEPTION 'Contributor sync success did not update contributor email'; END IF;

  INSERT INTO public.contributor_emails(contributor_id,email,is_primary,source,mailing_subscription_status)
    VALUES (v_contributor,'listmonk-optout@example.invalid',false,'listmonk_test','not_subscribed')
    RETURNING contributor_email_id INTO v_email;
  IF EXISTS (SELECT 1 FROM public.listmonk_sync_queue WHERE contributor_email_id=v_email)
    THEN RAISE EXCEPTION 'Not-subscribed contributor email was queued'; END IF;

  INSERT INTO public.members(person_id,email,source,notes) VALUES (v_person,'listmonk-member@example.invalid','listmonk_test','synthetic test member') RETURNING member_id INTO v_member_email;
  INSERT INTO public.member_emails(member_id,email,is_primary,source,mailing_subscription_status)
    SELECT v_member_email,'listmonk-member-contact@example.invalid',true,'listmonk_test','subscribed';
  IF NOT EXISTS (SELECT 1 FROM public.listmonk_sync_queue q JOIN public.member_emails me ON me.member_email_id=q.member_email_id WHERE me.email='listmonk-member-contact@example.invalid' AND q.contributor_email_id IS NULL)
    THEN RAISE EXCEPTION 'Existing member Listmonk queue behavior regressed'; END IF;

  RAISE NOTICE 'Contributor Listmonk checks passed; rolling back synthetic records.';
END $$;
ROLLBACK;
