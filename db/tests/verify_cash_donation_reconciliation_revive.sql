-- Rollback-only artificial fixtures. No operational identities or financial values.
\set ON_ERROR_STOP on
BEGIN;

DO $$
DECLARE
  reviewer_person uuid := public.uuid_generate_v4();
  other_person uuid := public.uuid_generate_v4();
  actor_id uuid;
  v_donation uuid := public.uuid_generate_v4();
  overlap_id uuid := public.uuid_generate_v4();
  pending_id uuid := public.uuid_generate_v4();
  batch public.cash_deposit_batches%ROWTYPE;
  exclusion public.cash_deposit_donation_exclusions%ROWTYPE;
  revived public.cash_deposit_donation_exclusions%ROWTYPE;
  details jsonb;
  cash_before bigint;
  donation_before jsonb;
  reason text;
BEGIN
  INSERT INTO public.people(person_id,display_name) VALUES
    (reviewer_person,'Synthetic revival reviewer'), (other_person,'Synthetic revival denied');
  INSERT INTO public.person_app_accounts(person_id,email) VALUES
    (reviewer_person,'revival-reviewer@example.invalid'),(other_person,'revival-denied@example.invalid');
  INSERT INTO public.person_roles(person_id,role_key,assigned_by) VALUES
    (reviewer_person,'donations_reviewer','synthetic'),(other_person,'document_reviewer','synthetic');
  actor_id := public.application_cash_actor_id('revival-reviewer@example.invalid');
  INSERT INTO public.donations(donation_id,donor_kind,provider,amount_cents,currency,donated_at,status) VALUES
    (v_donation,'anonymous','cash',137,'USD',now(),'verified'),
    (overlap_id,'anonymous','cash',211,'USD',now(),'verified'),
    (pending_id,'anonymous','cash',53,'USD',now(),'pending_review');
  SELECT to_jsonb(d) INTO donation_before FROM public.donations d WHERE d.donation_id=v_donation;
  SELECT COALESCE(sum(d.amount_cents),0) INTO cash_before FROM public.cash_on_hand_donations() d;
  exclusion := public.exclude_cash_donation_from_deposit(v_donation,actor_id,'Synthetic exclusion','Synthetic original note');

  FOREACH reason IN ARRAY ARRAY[NULL::text,'','   '] LOOP
    BEGIN
      PERFORM public.revive_cash_donation_from_deposit(v_donation,actor_id,reason);
      RAISE EXCEPTION 'Expected blank revival reason denial';
    EXCEPTION WHEN raise_exception THEN
      IF SQLERRM NOT LIKE 'A reason is required when reviving%' THEN RAISE; END IF;
    END;
  END LOOP;
  BEGIN
    PERFORM public.revive_cash_donation_from_deposit(v_donation,actor_id);
    RAISE EXCEPTION 'Expected legacy reasonless revival denial';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM NOT LIKE 'A reason is required when reviving%' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM public.revive_cash_donation_from_deposit(v_donation,other_person,'Synthetic unauthorized attempt');
    RAISE EXCEPTION 'Expected reviewer denial';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM NOT LIKE 'Permission denied%' THEN RAISE; END IF;
  END;
  IF NOT EXISTS(SELECT 1 FROM public.cash_deposit_donation_exclusions e WHERE e.exclusion_id=exclusion.exclusion_id)
     OR EXISTS(SELECT 1 FROM public.audit_log a WHERE a.entity_id=v_donation::text AND a.action='cash_donation.deposit_reconciliation_revived')
  THEN RAISE EXCEPTION 'Denied revival changed exclusion or audit'; END IF;

  revived := public.revive_cash_donation_from_deposit(v_donation,actor_id,'  Synthetic recovered cash  ','  Synthetic revival note  ');
  IF revived.exclusion_id IS DISTINCT FROM exclusion.exclusion_id
     OR EXISTS(SELECT 1 FROM public.cash_deposit_donation_exclusions e WHERE e.donation_id=v_donation)
     OR (SELECT COALESCE(sum(d.amount_cents),0) FROM public.cash_on_hand_donations() d) IS DISTINCT FROM cash_before
     OR (SELECT to_jsonb(d) FROM public.donations d WHERE d.donation_id=v_donation) IS DISTINCT FROM donation_before
  THEN RAISE EXCEPTION 'Revival changed history or restored incorrect cash total'; END IF;
  SELECT a.details INTO details FROM public.audit_log a WHERE a.entity_id=v_donation::text
    AND a.action='cash_donation.deposit_reconciliation_revived';
  IF details->>'reason' IS DISTINCT FROM 'Synthetic exclusion'
     OR details->>'notes' IS DISTINCT FROM 'Synthetic original note'
     OR details->>'revival_reason' IS DISTINCT FROM 'Synthetic recovered cash'
     OR details->>'revival_notes' IS DISTINCT FROM 'Synthetic revival note'
     OR details->>'exclusion_id' IS DISTINCT FROM exclusion.exclusion_id::text
     OR (SELECT count(*) FROM public.audit_log a WHERE a.entity_id=v_donation::text
           AND a.action='cash_donation.deposit_reconciliation_revived') <> 1
  THEN RAISE EXCEPTION 'Revival audit lost original/new rationale or duplicated'; END IF;
  BEGIN
    PERFORM public.revive_cash_donation_from_deposit(v_donation,actor_id,'Synthetic repeated attempt');
    RAISE EXCEPTION 'Expected repeat denial';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM NOT LIKE 'Donation % is not currently excluded%' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM public.revive_cash_donation_from_deposit(public.uuid_generate_v4(),actor_id,'Synthetic missing');
    RAISE EXCEPTION 'Expected missing donation denial';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM NOT LIKE 'Donation % was not found%' THEN RAISE; END IF;
  END;
  INSERT INTO public.cash_deposit_donation_exclusions(donation_id,excluded_by,reason)
    VALUES(pending_id,actor_id,'Synthetic pending fixture');
  BEGIN
    PERFORM public.revive_cash_donation_from_deposit(pending_id,actor_id,'Synthetic invalid status');
    RAISE EXCEPTION 'Expected pending donation denial';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM NOT LIKE 'Donation % is not a verified%' THEN RAISE; END IF;
  END;
  batch := public.create_cash_deposit_batch(actor_id,CURRENT_DATE,NULL,'Synthetic overlap fixture');
  PERFORM public.add_cash_deposit_item(batch.deposit_batch_id,overlap_id,actor_id);
  -- Artificial inconsistent overlap proves the guard preserves active composition.
  INSERT INTO public.cash_deposit_donation_exclusions(donation_id,excluded_by,reason)
    VALUES(overlap_id,actor_id,'Synthetic overlap fixture');
  BEGIN
    PERFORM public.revive_cash_donation_from_deposit(overlap_id,actor_id,'Synthetic active batch');
    RAISE EXCEPTION 'Expected active batch denial';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM NOT LIKE 'Donation % is already assigned%' THEN RAISE; END IF;
  END;
  IF NOT EXISTS(SELECT 1 FROM public.cash_deposit_donation_exclusions e WHERE e.donation_id=overlap_id)
     OR NOT EXISTS(SELECT 1 FROM public.cash_deposit_batch_items i WHERE i.donation_id=overlap_id AND i.removed_at IS NULL)
  THEN RAISE EXCEPTION 'Denied overlap revival altered composition'; END IF;
END;
$$;

CREATE FUNCTION public.synthetic_revival_audit_failure() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.action='cash_donation.deposit_reconciliation_revived' THEN
    RAISE EXCEPTION 'Synthetic revival audit failure';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER synthetic_revival_audit_failure BEFORE INSERT ON public.audit_log
  FOR EACH ROW EXECUTE FUNCTION public.synthetic_revival_audit_failure();
DO $$
DECLARE
  actor_id uuid := public.application_cash_actor_id('revival-reviewer@example.invalid');
  v_donation uuid := public.uuid_generate_v4();
  exclusion public.cash_deposit_donation_exclusions%ROWTYPE;
BEGIN
  INSERT INTO public.donations(donation_id,donor_kind,provider,amount_cents,currency,donated_at,status)
    VALUES(v_donation,'anonymous','cash',89,'USD',now(),'verified');
  exclusion := public.exclude_cash_donation_from_deposit(v_donation,actor_id,'Synthetic audit rollback');
  BEGIN
    PERFORM public.revive_cash_donation_from_deposit(v_donation,actor_id,'Synthetic attempted recovery');
    RAISE EXCEPTION 'Expected audit failure';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'Synthetic revival audit failure' THEN RAISE; END IF;
  END;
  IF NOT EXISTS(SELECT 1 FROM public.cash_deposit_donation_exclusions e WHERE e.exclusion_id=exclusion.exclusion_id)
     OR EXISTS(SELECT 1 FROM public.cash_on_hand_donations() d WHERE d.donation_id=v_donation)
  THEN RAISE EXCEPTION 'Audit failure did not roll back revival'; END IF;
END;
$$;
ROLLBACK;
