-- Subscribes existing SignatureGate email addresses
-- Apply after migrations_listmonk_mailing_list.sql.

BEGIN;

INSERT INTO public.listmonk_sync_queue (
  event_type,
  member_email_id,
  email_normalized,
  listmonk_list_id,
  source,
  details
)
SELECT
  'subscribe',
  me.member_email_id,
  me.email_normalized,
  COALESCE(me.listmonk_list_id, 1),
  'backfill_existing_member_emails',
  jsonb_build_object(
    'member_id', me.member_id,
    'email', me.email,
    'email_normalized', me.email_normalized,
    'backfill', true
  )
FROM public.member_emails me
WHERE me.email_normalized IS NOT NULL
  AND COALESCE(me.status, 'active') = 'active'
  AND COALESCE(me.mailing_subscription_status, 'subscribed') <> 'unsubscribed'
  AND NOT EXISTS (
    SELECT 1
    FROM public.listmonk_sync_queue q
    WHERE q.member_email_id = me.member_email_id
      AND q.event_type = 'subscribe'
      AND q.status IN ('pending', 'processing', 'synced')
  );

COMMIT;
