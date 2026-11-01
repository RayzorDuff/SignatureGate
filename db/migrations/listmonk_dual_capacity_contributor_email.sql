--
-- Preserve independent Contributor mailing identity when an Individual is
-- enrolled in both Member and Contributor capacities.
--
-- The Member email and Contributor email remain separate domain records.
-- Contributor opt-in is applied only to the Contributor email and queues
-- only a contributor Listmonk event.
--

\set ON_ERROR_STOP on
BEGIN;

CREATE OR REPLACE FUNCTION public.issue19_add_contributor_email_with_mailing(
  p_actor_email text,
  p_party_kind text,
  p_party_id uuid,
  p_email text,
  p_reason text,
  p_subscribe_to_mailing_list boolean DEFAULT false
) RETURNS uuid
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  v_email_id uuid;
BEGIN
  v_email_id := public.issue19_add_contributor_contact(
    p_actor_email,
    p_party_kind,
    p_party_id,
    'email',
    p_email,
    p_reason
  );

  UPDATE public.contributor_emails
  SET mailing_subscription_status =
        CASE WHEN COALESCE(p_subscribe_to_mailing_list,false)
             THEN 'subscribed'
             ELSE 'not_subscribed'
        END,
      mailing_subscription_source = 'intake',
      mailing_unsubscribed_at = NULL,
      mailing_unsubscribe_source = NULL,
      mailing_unsubscribe_reason = NULL,
      listmonk_sync_status =
        CASE WHEN COALESCE(p_subscribe_to_mailing_list,false)
             THEN 'pending'
             ELSE NULL
        END,
      listmonk_sync_error = NULL,
      updated_at = now()
  WHERE contributor_email_id = v_email_id;

  IF COALESCE(p_subscribe_to_mailing_list,false) THEN
    PERFORM public.enqueue_listmonk_contributor_email_sync(
      v_email_id,
      'subscribe',
      'intake',
      p_actor_email,
      jsonb_build_object(
        'source','issue19_add_contributor_email_with_mailing',
        'capacity','contributor',
        'dual_capacity',true
      )
    );
  END IF;

  RETURN v_email_id;
END;
$$;

COMMIT;
