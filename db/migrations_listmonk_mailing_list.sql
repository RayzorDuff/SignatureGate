-- Adds SignatureGate -> listmonk mailing-list sync state and queue.
-- Apply after migrations_member_contact_methods.sql.

BEGIN;

ALTER TABLE public.member_emails
  ADD COLUMN IF NOT EXISTS mailing_subscription_status text NOT NULL DEFAULT 'subscribed',
  ADD COLUMN IF NOT EXISTS mailing_subscription_source text,
  ADD COLUMN IF NOT EXISTS mailing_unsubscribed_at timestamptz,
  ADD COLUMN IF NOT EXISTS mailing_unsubscribe_source text,
  ADD COLUMN IF NOT EXISTS mailing_unsubscribe_reason text,
  ADD COLUMN IF NOT EXISTS listmonk_list_id integer,
  ADD COLUMN IF NOT EXISTS listmonk_subscriber_id integer,
  ADD COLUMN IF NOT EXISTS listmonk_subscriber_uuid uuid,
  ADD COLUMN IF NOT EXISTS listmonk_synced_at timestamptz,
  ADD COLUMN IF NOT EXISTS listmonk_sync_status text,
  ADD COLUMN IF NOT EXISTS listmonk_sync_error text;

ALTER TABLE public.member_emails
  DROP CONSTRAINT IF EXISTS member_emails_mailing_subscription_status_chk;
ALTER TABLE public.member_emails
  ADD CONSTRAINT member_emails_mailing_subscription_status_chk
  CHECK (mailing_subscription_status IN ('subscribed', 'not_subscribed', 'unsubscribed', 'suppressed', 'sync_error'));

ALTER TABLE public.member_emails
  DROP CONSTRAINT IF EXISTS member_emails_listmonk_sync_status_chk;
ALTER TABLE public.member_emails
  ADD CONSTRAINT member_emails_listmonk_sync_status_chk
  CHECK (listmonk_sync_status IS NULL OR listmonk_sync_status IN ('pending', 'synced', 'failed'));

CREATE TABLE IF NOT EXISTS public.listmonk_sync_queue (
  listmonk_sync_queue_id uuid PRIMARY KEY DEFAULT public.uuid_generate_v4(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  available_at timestamptz NOT NULL DEFAULT now(),
  locked_at timestamptz,
  processed_at timestamptz,
  member_email_id uuid NOT NULL REFERENCES public.member_emails(member_email_id) ON DELETE CASCADE,
  email_normalized text NOT NULL,
  listmonk_list_id integer,
  event_type text NOT NULL,
  source text NOT NULL,
  actor text,
  status text NOT NULL DEFAULT 'pending',
  attempts integer NOT NULL DEFAULT 0,
  last_error text,
  request_payload jsonb,
  response_payload jsonb,
  details jsonb NOT NULL DEFAULT '{}'::jsonb
);

ALTER TABLE public.listmonk_sync_queue
  DROP CONSTRAINT IF EXISTS listmonk_sync_queue_event_type_chk;
ALTER TABLE public.listmonk_sync_queue
  ADD CONSTRAINT listmonk_sync_queue_event_type_chk
  CHECK (event_type IN ('subscribe', 'unsubscribe'));

ALTER TABLE public.listmonk_sync_queue
  DROP CONSTRAINT IF EXISTS listmonk_sync_queue_status_chk;
ALTER TABLE public.listmonk_sync_queue
  ADD CONSTRAINT listmonk_sync_queue_status_chk
  CHECK (status IN ('pending', 'processing', 'succeeded', 'failed', 'skipped'));

DROP TRIGGER IF EXISTS trg_listmonk_sync_queue_updated_at ON public.listmonk_sync_queue;
CREATE TRIGGER trg_listmonk_sync_queue_updated_at
BEFORE UPDATE ON public.listmonk_sync_queue
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE INDEX IF NOT EXISTS idx_listmonk_sync_queue_pending
  ON public.listmonk_sync_queue (status, available_at, created_at)
  WHERE status IN ('pending', 'failed');

CREATE INDEX IF NOT EXISTS idx_listmonk_sync_queue_member_email
  ON public.listmonk_sync_queue (member_email_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_member_emails_mailing_status
  ON public.member_emails (mailing_subscription_status, listmonk_sync_status, updated_at DESC);

CREATE OR REPLACE FUNCTION public.enqueue_listmonk_email_sync(
  p_member_email_id uuid,
  p_event_type text,
  p_source text DEFAULT 'signaturegate',
  p_actor text DEFAULT NULL,
  p_details jsonb DEFAULT '{}'::jsonb
)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
  v_email public.member_emails%ROWTYPE;
  v_queue_id uuid;
  v_action text;
BEGIN
  IF p_event_type NOT IN ('subscribe', 'unsubscribe') THEN
    RAISE EXCEPTION 'Unsupported listmonk sync event_type: %', p_event_type;
  END IF;

  SELECT * INTO v_email
  FROM public.member_emails
  WHERE member_email_id = p_member_email_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'member_email_id % not found', p_member_email_id;
  END IF;

  IF v_email.email_normalized IS NULL OR v_email.email_normalized = '' THEN
    RAISE EXCEPTION 'member_email_id % has no normalized email', p_member_email_id;
  END IF;

  INSERT INTO public.listmonk_sync_queue (
    member_email_id,
    email_normalized,
    listmonk_list_id,
    event_type,
    source,
    actor,
    details
  ) VALUES (
    v_email.member_email_id,
    v_email.email_normalized,
    v_email.listmonk_list_id,
    p_event_type,
    COALESCE(NULLIF(p_source, ''), 'signaturegate'),
    NULLIF(lower(btrim(p_actor)), ''),
    COALESCE(p_details, '{}'::jsonb)
  )
  RETURNING listmonk_sync_queue_id INTO v_queue_id;

  v_action := CASE p_event_type
    WHEN 'subscribe' THEN 'mailing.subscribe_queued'
    ELSE 'mailing.unsubscribe_queued'
  END;

  INSERT INTO public.audit_log (actor, action, entity_type, entity_id, details)
  VALUES (
    NULLIF(lower(btrim(p_actor)), ''),
    v_action,
    'member_email',
    v_email.member_email_id::text,
    jsonb_build_object(
      'queue_id', v_queue_id,
      'email', v_email.email,
      'email_normalized', v_email.email_normalized,
      'member_id', v_email.member_id,
      'source', COALESCE(NULLIF(p_source, ''), 'signaturegate'),
      'event_type', p_event_type,
      'details', COALESCE(p_details, '{}'::jsonb)
    )
  );

  UPDATE public.member_emails
  SET listmonk_sync_status = 'pending',
      listmonk_sync_error = NULL,
      updated_at = now()
  WHERE member_email_id = v_email.member_email_id;

  RETURN v_queue_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_member_emails_listmonk_insert()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF COALESCE(NEW.status, 'active') = 'active'
     AND NEW.mailing_subscription_status = 'subscribed'
     AND NEW.email_normalized IS NOT NULL
     AND NEW.email_normalized <> '' THEN
    PERFORM public.enqueue_listmonk_email_sync(
      NEW.member_email_id,
      'subscribe',
      COALESCE(NEW.mailing_subscription_source, NEW.source, 'member_email_insert'),
      NULL,
      jsonb_build_object('trigger', 'member_emails_after_insert')
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_member_emails_listmonk_insert ON public.member_emails;
CREATE TRIGGER trg_member_emails_listmonk_insert
AFTER INSERT ON public.member_emails
FOR EACH ROW EXECUTE FUNCTION public.trg_member_emails_listmonk_insert();

CREATE OR REPLACE FUNCTION public.member_email_request_mailing_unsubscribe(
  p_member_email_id uuid,
  p_actor text DEFAULT NULL,
  p_source text DEFAULT 'signaturegate_interface',
  p_reason text DEFAULT NULL,
  p_raw jsonb DEFAULT '{}'::jsonb,
  p_enqueue_listmonk boolean DEFAULT true
)
RETURNS public.member_emails
LANGUAGE plpgsql
AS $$
DECLARE
  v_email public.member_emails%ROWTYPE;
BEGIN
  UPDATE public.member_emails
  SET mailing_subscription_status = 'unsubscribed',
      mailing_unsubscribed_at = COALESCE(mailing_unsubscribed_at, now()),
      mailing_unsubscribe_source = COALESCE(NULLIF(p_source, ''), 'signaturegate_interface'),
      mailing_unsubscribe_reason = NULLIF(p_reason, ''),
      listmonk_sync_status = CASE WHEN p_enqueue_listmonk THEN 'pending' ELSE 'synced' END,
      listmonk_sync_error = NULL,
      updated_at = now()
  WHERE member_email_id = p_member_email_id
  RETURNING * INTO v_email;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'member_email_id % not found', p_member_email_id;
  END IF;

  INSERT INTO public.audit_log (actor, action, entity_type, entity_id, details)
  VALUES (
    NULLIF(lower(btrim(p_actor)), ''),
    'mailing.unsubscribe_recorded',
    'member_email',
    v_email.member_email_id::text,
    jsonb_build_object(
      'member_id', v_email.member_id,
      'email', v_email.email,
      'email_normalized', v_email.email_normalized,
      'source', COALESCE(NULLIF(p_source, ''), 'signaturegate_interface'),
      'reason', NULLIF(p_reason, ''),
      'enqueue_listmonk', p_enqueue_listmonk,
      'raw', COALESCE(p_raw, '{}'::jsonb)
    )
  );

  IF p_enqueue_listmonk THEN
    PERFORM public.enqueue_listmonk_email_sync(
      v_email.member_email_id,
      'unsubscribe',
      COALESCE(NULLIF(p_source, ''), 'signaturegate_interface'),
      p_actor,
      jsonb_build_object('reason', NULLIF(p_reason, ''), 'raw', COALESCE(p_raw, '{}'::jsonb))
    );
  END IF;

  RETURN v_email;
END;
$$;

CREATE OR REPLACE FUNCTION public.listmonk_mark_sync_success(
  p_queue_id uuid,
  p_listmonk_subscriber_id integer DEFAULT NULL,
  p_listmonk_subscriber_uuid uuid DEFAULT NULL,
  p_response jsonb DEFAULT '{}'::jsonb
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_queue public.listmonk_sync_queue%ROWTYPE;
BEGIN
  UPDATE public.listmonk_sync_queue
  SET status = 'succeeded',
      processed_at = now(),
      locked_at = NULL,
      response_payload = COALESCE(p_response, '{}'::jsonb),
      last_error = NULL,
      updated_at = now()
  WHERE listmonk_sync_queue_id = p_queue_id
  RETURNING * INTO v_queue;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'listmonk_sync_queue_id % not found', p_queue_id;
  END IF;

  UPDATE public.member_emails
  SET listmonk_subscriber_id = COALESCE(p_listmonk_subscriber_id, listmonk_subscriber_id),
      listmonk_subscriber_uuid = COALESCE(p_listmonk_subscriber_uuid, listmonk_subscriber_uuid),
      listmonk_synced_at = now(),
      listmonk_sync_status = 'synced',
      listmonk_sync_error = NULL,
      updated_at = now()
  WHERE member_email_id = v_queue.member_email_id;

  INSERT INTO public.audit_log (actor, action, entity_type, entity_id, details)
  VALUES (
    v_queue.actor,
    'mailing.listmonk_sync_succeeded',
    'member_email',
    v_queue.member_email_id::text,
    jsonb_build_object(
      'queue_id', v_queue.listmonk_sync_queue_id,
      'event_type', v_queue.event_type,
      'source', v_queue.source,
      'email_normalized', v_queue.email_normalized,
      'listmonk_list_id', v_queue.listmonk_list_id,
      'listmonk_subscriber_id', p_listmonk_subscriber_id,
      'listmonk_subscriber_uuid', p_listmonk_subscriber_uuid,
      'response', COALESCE(p_response, '{}'::jsonb)
    )
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.listmonk_mark_sync_failure(
  p_queue_id uuid,
  p_error text,
  p_response jsonb DEFAULT '{}'::jsonb,
  p_retry_after interval DEFAULT interval '5 minutes'
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_queue public.listmonk_sync_queue%ROWTYPE;
  v_final_status text;
BEGIN
  SELECT * INTO v_queue
  FROM public.listmonk_sync_queue
  WHERE listmonk_sync_queue_id = p_queue_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'listmonk_sync_queue_id % not found', p_queue_id;
  END IF;

  v_final_status := CASE WHEN v_queue.attempts >= 5 THEN 'failed' ELSE 'pending' END;

  UPDATE public.listmonk_sync_queue
  SET status = v_final_status,
      available_at = CASE WHEN v_final_status = 'pending' THEN now() + p_retry_after ELSE available_at END,
      locked_at = NULL,
      last_error = NULLIF(p_error, ''),
      response_payload = COALESCE(p_response, '{}'::jsonb),
      updated_at = now()
  WHERE listmonk_sync_queue_id = p_queue_id;

  UPDATE public.member_emails
  SET listmonk_sync_status = CASE WHEN v_final_status = 'failed' THEN 'failed' ELSE 'pending' END,
      listmonk_sync_error = NULLIF(p_error, ''),
      updated_at = now()
  WHERE member_email_id = v_queue.member_email_id;

  INSERT INTO public.audit_log (actor, action, entity_type, entity_id, details)
  VALUES (
    v_queue.actor,
    'mailing.listmonk_sync_failed',
    'member_email',
    v_queue.member_email_id::text,
    jsonb_build_object(
      'queue_id', v_queue.listmonk_sync_queue_id,
      'event_type', v_queue.event_type,
      'source', v_queue.source,
      'email_normalized', v_queue.email_normalized,
      'attempts', v_queue.attempts,
      'final_status', v_final_status,
      'error', NULLIF(p_error, ''),
      'response', COALESCE(p_response, '{}'::jsonb)
    )
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.listmonk_record_external_unsubscribe(
  p_email text,
  p_listmonk_subscriber_id integer DEFAULT NULL,
  p_listmonk_subscriber_uuid uuid DEFAULT NULL,
  p_source text DEFAULT 'listmonk_unsubscribe_poll',
  p_raw jsonb DEFAULT '{}'::jsonb
)
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
  v_count integer := 0;
  v_row public.member_emails%ROWTYPE;
BEGIN
  FOR v_row IN
    SELECT *
    FROM public.member_emails
    WHERE email_normalized = lower(btrim(p_email))
      AND COALESCE(status, 'active') = 'active'
  LOOP
    UPDATE public.member_emails
    SET mailing_subscription_status = 'unsubscribed',
        mailing_unsubscribed_at = COALESCE(mailing_unsubscribed_at, now()),
        mailing_unsubscribe_source = COALESCE(NULLIF(p_source, ''), 'listmonk_unsubscribe_poll'),
        mailing_unsubscribe_reason = 'Unsubscribe observed in listmonk',
        listmonk_subscriber_id = COALESCE(p_listmonk_subscriber_id, listmonk_subscriber_id),
        listmonk_subscriber_uuid = COALESCE(p_listmonk_subscriber_uuid, listmonk_subscriber_uuid),
        listmonk_synced_at = now(),
        listmonk_sync_status = 'synced',
        listmonk_sync_error = NULL,
        updated_at = now()
    WHERE member_email_id = v_row.member_email_id;

    INSERT INTO public.audit_log (actor, action, entity_type, entity_id, details)
    VALUES (
      'listmonk',
      'mailing.unsubscribe_observed_from_listmonk',
      'member_email',
      v_row.member_email_id::text,
      jsonb_build_object(
        'member_id', v_row.member_id,
        'email', v_row.email,
        'email_normalized', v_row.email_normalized,
        'source', COALESCE(NULLIF(p_source, ''), 'listmonk_unsubscribe_poll'),
        'listmonk_subscriber_id', p_listmonk_subscriber_id,
        'listmonk_subscriber_uuid', p_listmonk_subscriber_uuid,
        'raw', COALESCE(p_raw, '{}'::jsonb)
      )
    );

    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

COMMIT;
