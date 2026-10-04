-- Contributor email Listmonk subscription support.
--
-- Extends the existing member-email Listmonk outbox without merging
-- contributor and membership contact records. Exactly one domain email source
-- must own each queue row.

\set ON_ERROR_STOP on
BEGIN;

ALTER TABLE public.contributor_emails
  ADD COLUMN IF NOT EXISTS mailing_subscription_status text NOT NULL DEFAULT 'not_subscribed',
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

ALTER TABLE public.contributor_emails
  DROP CONSTRAINT IF EXISTS contributor_emails_mailing_subscription_status_chk,
  DROP CONSTRAINT IF EXISTS contributor_emails_listmonk_sync_status_chk;

ALTER TABLE public.contributor_emails
  ADD CONSTRAINT contributor_emails_mailing_subscription_status_chk
    CHECK (mailing_subscription_status IN ('subscribed','not_subscribed','unsubscribed','suppressed','sync_error')),
  ADD CONSTRAINT contributor_emails_listmonk_sync_status_chk
    CHECK (listmonk_sync_status IS NULL OR listmonk_sync_status IN ('pending','synced','failed'));

ALTER TABLE public.listmonk_sync_queue
  ALTER COLUMN member_email_id DROP NOT NULL,
  ADD COLUMN IF NOT EXISTS contributor_email_id uuid;

ALTER TABLE public.listmonk_sync_queue
  DROP CONSTRAINT IF EXISTS listmonk_sync_queue_exactly_one_email_chk,
  DROP CONSTRAINT IF EXISTS listmonk_sync_queue_contributor_email_id_fkey;

ALTER TABLE public.listmonk_sync_queue
  ADD CONSTRAINT listmonk_sync_queue_exactly_one_email_chk
    CHECK ((member_email_id IS NOT NULL) <> (contributor_email_id IS NOT NULL)),
  ADD CONSTRAINT listmonk_sync_queue_contributor_email_id_fkey
    FOREIGN KEY (contributor_email_id)
    REFERENCES public.contributor_emails(contributor_email_id);

CREATE INDEX IF NOT EXISTS idx_listmonk_sync_queue_contributor_email
  ON public.listmonk_sync_queue (contributor_email_id, created_at DESC)
  WHERE contributor_email_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.enqueue_listmonk_contributor_email_sync(
  p_contributor_email_id uuid,
  p_event_type text,
  p_source text DEFAULT 'signaturegate',
  p_actor text DEFAULT NULL,
  p_details jsonb DEFAULT '{}'::jsonb
) RETURNS uuid
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  v_email public.contributor_emails%ROWTYPE;
  v_queue_id uuid;
BEGIN
  IF p_event_type NOT IN ('subscribe','unsubscribe') THEN
    RAISE EXCEPTION 'Unsupported listmonk sync event_type: %', p_event_type;
  END IF;

  SELECT * INTO v_email
  FROM public.contributor_emails
  WHERE contributor_email_id = p_contributor_email_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'contributor_email_id % not found', p_contributor_email_id;
  END IF;

  IF v_email.email_normalized IS NULL OR v_email.email_normalized = '' THEN
    RAISE EXCEPTION 'contributor_email_id % has no normalized email', p_contributor_email_id;
  END IF;

  INSERT INTO public.listmonk_sync_queue (
    contributor_email_id, email_normalized, listmonk_list_id,
    event_type, source, actor, details
  ) VALUES (
    v_email.contributor_email_id, v_email.email_normalized,
    v_email.listmonk_list_id, p_event_type,
    COALESCE(NULLIF(p_source,''),'signaturegate'),
    NULLIF(lower(btrim(p_actor)),''), COALESCE(p_details,'{}'::jsonb)
  )
  RETURNING listmonk_sync_queue_id INTO v_queue_id;

  INSERT INTO public.audit_log(actor,action,entity_type,entity_id,details)
  VALUES (
    NULLIF(lower(btrim(p_actor)),''),
    CASE p_event_type WHEN 'subscribe' THEN 'mailing.subscribe_queued'
      ELSE 'mailing.unsubscribe_queued' END,
    'contributor_email', v_email.contributor_email_id::text,
    jsonb_build_object(
      'queue_id',v_queue_id,'email',v_email.email,
      'email_normalized',v_email.email_normalized,
      'contributor_id',v_email.contributor_id,
      'source',COALESCE(NULLIF(p_source,''),'signaturegate'),
      'event_type',p_event_type,'details',COALESCE(p_details,'{}'::jsonb)
    )
  );

  UPDATE public.contributor_emails
  SET listmonk_sync_status='pending', listmonk_sync_error=NULL, updated_at=now()
  WHERE contributor_email_id=v_email.contributor_email_id;

  RETURN v_queue_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.listmonk_mark_sync_failure(
  p_queue_id uuid, p_error text, p_response jsonb DEFAULT '{}'::jsonb,
  p_retry_after interval DEFAULT '00:05:00'::interval
) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
  v_queue public.listmonk_sync_queue%ROWTYPE;
  v_final_status text;
BEGIN
  SELECT * INTO v_queue FROM public.listmonk_sync_queue
  WHERE listmonk_sync_queue_id=p_queue_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'listmonk_sync_queue_id % not found',p_queue_id; END IF;
  v_final_status:=CASE WHEN v_queue.attempts>=5 THEN 'failed' ELSE 'pending' END;
  UPDATE public.listmonk_sync_queue SET
    status=v_final_status,
    available_at=CASE WHEN v_final_status='pending' THEN now()+p_retry_after ELSE available_at END,
    locked_at=NULL,last_error=NULLIF(p_error,''),response_payload=COALESCE(p_response,'{}'::jsonb),updated_at=now()
  WHERE listmonk_sync_queue_id=p_queue_id;

  IF v_queue.member_email_id IS NOT NULL THEN
    UPDATE public.member_emails SET
      listmonk_sync_status=CASE WHEN v_final_status='failed' THEN 'failed' ELSE 'pending' END,
      listmonk_sync_error=NULLIF(p_error,''),updated_at=now()
    WHERE member_email_id=v_queue.member_email_id;
  ELSE
    UPDATE public.contributor_emails SET
      listmonk_sync_status=CASE WHEN v_final_status='failed' THEN 'failed' ELSE 'pending' END,
      listmonk_sync_error=NULLIF(p_error,''),updated_at=now()
    WHERE contributor_email_id=v_queue.contributor_email_id;
  END IF;

  INSERT INTO public.audit_log(actor,action,entity_type,entity_id,details)
  VALUES (
    v_queue.actor,'mailing.listmonk_sync_failed',
    CASE WHEN v_queue.member_email_id IS NOT NULL THEN 'member_email' ELSE 'contributor_email' END,
    COALESCE(v_queue.member_email_id,v_queue.contributor_email_id)::text,
    jsonb_build_object('queue_id',v_queue.listmonk_sync_queue_id,'event_type',v_queue.event_type,
      'source',v_queue.source,'email_normalized',v_queue.email_normalized,
      'attempts',v_queue.attempts,'final_status',v_final_status,'error',NULLIF(p_error,''),
      'response',COALESCE(p_response,'{}'::jsonb))
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.listmonk_mark_sync_success(
  p_queue_id uuid, p_listmonk_subscriber_id integer DEFAULT NULL,
  p_listmonk_subscriber_uuid uuid DEFAULT NULL,
  p_response jsonb DEFAULT '{}'::jsonb
) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE v_queue public.listmonk_sync_queue%ROWTYPE;
BEGIN
  UPDATE public.listmonk_sync_queue SET status='succeeded',processed_at=now(),locked_at=NULL,
    response_payload=COALESCE(p_response,'{}'::jsonb),last_error=NULL,updated_at=now()
  WHERE listmonk_sync_queue_id=p_queue_id RETURNING * INTO v_queue;
  IF NOT FOUND THEN RAISE EXCEPTION 'listmonk_sync_queue_id % not found',p_queue_id; END IF;

  IF v_queue.member_email_id IS NOT NULL THEN
    UPDATE public.member_emails SET
      listmonk_subscriber_id=COALESCE(p_listmonk_subscriber_id,listmonk_subscriber_id),
      listmonk_subscriber_uuid=COALESCE(p_listmonk_subscriber_uuid,listmonk_subscriber_uuid),
      listmonk_synced_at=now(),listmonk_sync_status='synced',listmonk_sync_error=NULL,updated_at=now()
    WHERE member_email_id=v_queue.member_email_id;
  ELSE
    UPDATE public.contributor_emails SET
      listmonk_subscriber_id=COALESCE(p_listmonk_subscriber_id,listmonk_subscriber_id),
      listmonk_subscriber_uuid=COALESCE(p_listmonk_subscriber_uuid,listmonk_subscriber_uuid),
      listmonk_synced_at=now(),listmonk_sync_status='synced',listmonk_sync_error=NULL,updated_at=now()
    WHERE contributor_email_id=v_queue.contributor_email_id;
  END IF;

  INSERT INTO public.audit_log(actor,action,entity_type,entity_id,details)
  VALUES (v_queue.actor,'mailing.listmonk_sync_succeeded',
    CASE WHEN v_queue.member_email_id IS NOT NULL THEN 'member_email' ELSE 'contributor_email' END,
    COALESCE(v_queue.member_email_id,v_queue.contributor_email_id)::text,
    jsonb_build_object('queue_id',v_queue.listmonk_sync_queue_id,'event_type',v_queue.event_type,
      'source',v_queue.source,'email_normalized',v_queue.email_normalized,
      'listmonk_list_id',v_queue.listmonk_list_id,'listmonk_subscriber_id',p_listmonk_subscriber_id,
      'listmonk_subscriber_uuid',p_listmonk_subscriber_uuid,'response',COALESCE(p_response,'{}'::jsonb)));
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_contributor_emails_listmonk_insert()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF COALESCE(NEW.status,'active')='active'
     AND NEW.mailing_subscription_status='subscribed'
     AND NEW.email_normalized IS NOT NULL AND NEW.email_normalized<>'' THEN
    PERFORM public.enqueue_listmonk_contributor_email_sync(
      NEW.contributor_email_id,'subscribe',
      COALESCE(NEW.mailing_subscription_source,NEW.source,'contributor_email_insert'),
      NULL,jsonb_build_object('trigger','contributor_emails_after_insert'));
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_contributor_emails_listmonk_insert ON public.contributor_emails;
CREATE TRIGGER trg_contributor_emails_listmonk_insert
AFTER INSERT ON public.contributor_emails
FOR EACH ROW EXECUTE FUNCTION public.trg_contributor_emails_listmonk_insert();

CREATE OR REPLACE FUNCTION public.listmonk_record_external_unsubscribe(
  p_email text, p_listmonk_subscriber_id integer DEFAULT NULL,
  p_listmonk_subscriber_uuid uuid DEFAULT NULL,
  p_source text DEFAULT 'listmonk_unsubscribe_poll', p_raw jsonb DEFAULT '{}'::jsonb
) RETURNS integer LANGUAGE plpgsql AS $$
DECLARE v_count integer:=0; v_member public.member_emails%ROWTYPE; v_contributor public.contributor_emails%ROWTYPE;
BEGIN
  FOR v_member IN SELECT * FROM public.member_emails
    WHERE email_normalized=lower(btrim(p_email)) AND COALESCE(status,'active')='active' LOOP
    UPDATE public.member_emails SET mailing_subscription_status='unsubscribed',
      mailing_unsubscribed_at=COALESCE(mailing_unsubscribed_at,now()),
      mailing_unsubscribe_source=COALESCE(NULLIF(p_source,''),'listmonk_unsubscribe_poll'),
      mailing_unsubscribe_reason='Unsubscribe observed in listmonk',
      listmonk_subscriber_id=COALESCE(p_listmonk_subscriber_id,listmonk_subscriber_id),
      listmonk_subscriber_uuid=COALESCE(p_listmonk_subscriber_uuid,listmonk_subscriber_uuid),
      listmonk_synced_at=now(),listmonk_sync_status='synced',listmonk_sync_error=NULL,updated_at=now()
      WHERE member_email_id=v_member.member_email_id;
    INSERT INTO public.audit_log(actor,action,entity_type,entity_id,details) VALUES
      ('listmonk','mailing.unsubscribe_observed_from_listmonk','member_email',v_member.member_email_id::text,
       jsonb_build_object('member_id',v_member.member_id,'email',v_member.email,'email_normalized',v_member.email_normalized,
         'source',COALESCE(NULLIF(p_source,''),'listmonk_unsubscribe_poll'),'listmonk_subscriber_id',p_listmonk_subscriber_id,
         'listmonk_subscriber_uuid',p_listmonk_subscriber_uuid,'raw',COALESCE(p_raw,'{}'::jsonb)));
    v_count:=v_count+1;
  END LOOP;
  FOR v_contributor IN SELECT * FROM public.contributor_emails
    WHERE email_normalized=lower(btrim(p_email)) AND COALESCE(status,'active')='active' LOOP
    UPDATE public.contributor_emails SET mailing_subscription_status='unsubscribed',
      mailing_unsubscribed_at=COALESCE(mailing_unsubscribed_at,now()),
      mailing_unsubscribe_source=COALESCE(NULLIF(p_source,''),'listmonk_unsubscribe_poll'),
      mailing_unsubscribe_reason='Unsubscribe observed in listmonk',
      listmonk_subscriber_id=COALESCE(p_listmonk_subscriber_id,listmonk_subscriber_id),
      listmonk_subscriber_uuid=COALESCE(p_listmonk_subscriber_uuid,listmonk_subscriber_uuid),
      listmonk_synced_at=now(),listmonk_sync_status='synced',listmonk_sync_error=NULL,updated_at=now()
      WHERE contributor_email_id=v_contributor.contributor_email_id;
    INSERT INTO public.audit_log(actor,action,entity_type,entity_id,details) VALUES
      ('listmonk','mailing.unsubscribe_observed_from_listmonk','contributor_email',v_contributor.contributor_email_id::text,
       jsonb_build_object('contributor_id',v_contributor.contributor_id,'email',v_contributor.email,'email_normalized',v_contributor.email_normalized,
         'source',COALESCE(NULLIF(p_source,''),'listmonk_unsubscribe_poll'),'listmonk_subscriber_id',p_listmonk_subscriber_id,
         'listmonk_subscriber_uuid',p_listmonk_subscriber_uuid,'raw',COALESCE(p_raw,'{}'::jsonb)));
    v_count:=v_count+1;
  END LOOP;
  RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.issue19_create_contributor_with_mailing(
  p_actor_email text,
  p_party_kind text,
  p_first_name text,
  p_last_name text,
  p_organization_name text,
  p_email text,
  p_phone text,
  p_reason text,
  p_subscribe_to_mailing_list boolean DEFAULT false
) RETURNS TABLE(party_kind text, party_id uuid, contributor_id uuid)
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  v_result record;
  v_email_id uuid;
BEGIN
  SELECT * INTO STRICT v_result
  FROM public.issue19_create_contributor(
    p_actor_email,p_party_kind,p_first_name,p_last_name,
    p_organization_name,p_email,p_phone,p_reason
  );

  IF COALESCE(p_subscribe_to_mailing_list,false)
     AND NULLIF(lower(btrim(p_email)),'') IS NOT NULL THEN
    UPDATE public.contributor_emails
    SET mailing_subscription_status='subscribed',
        mailing_subscription_source='intake',
        mailing_unsubscribed_at=NULL,
        mailing_unsubscribe_source=NULL,
        mailing_unsubscribe_reason=NULL,
        listmonk_sync_status='pending',
        listmonk_sync_error=NULL,
        updated_at=now()
    WHERE contributor_email_id = (
      SELECT ce.contributor_email_id
      FROM public.contributor_emails ce
      WHERE ce.contributor_id=v_result.contributor_id
        AND ce.email_normalized=lower(btrim(p_email))
        AND ce.status='active'
      ORDER BY ce.created_at DESC
      LIMIT 1
    )
    RETURNING contributor_email_id INTO v_email_id;

    IF v_email_id IS NOT NULL THEN
      PERFORM public.enqueue_listmonk_contributor_email_sync(
        v_email_id,'subscribe','intake',p_actor_email,
        jsonb_build_object('source','issue19_create_contributor_with_mailing')
      );
    END IF;
  END IF;

  party_kind:=v_result.party_kind;
  party_id:=v_result.party_id;
  contributor_id:=v_result.contributor_id;
  RETURN NEXT;
END;
$$;

COMMIT;
