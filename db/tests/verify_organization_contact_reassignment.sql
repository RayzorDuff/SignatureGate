-- Rollback-only integration checks for organization contributor contact reassignment.
\set ON_ERROR_STOP on
BEGIN;

DO $test$
DECLARE
  v_actor text := 'org-contact-reassignment-test@example.invalid';
  v_actor_id uuid;
  v_source record;
  v_target record;
  v_email uuid;
  v_phone uuid;
  v_address uuid;
  v_contact_id uuid;
  v_kind text;
  v_source_table text;
  v_canonical_before uuid;
  v_canonical_after uuid;
BEGIN
  IF to_regprocedure('public.issue19_reassign_organization_contact(text,uuid,text,uuid,uuid,text)') IS NULL THEN
    RAISE EXCEPTION 'Organization contact reassignment function is missing';
  END IF;

  INSERT INTO public.people(display_name) VALUES ('Organization Contact Test Reviewer')
    RETURNING person_id INTO v_actor_id;
  INSERT INTO public.person_app_accounts(person_id,email) VALUES (v_actor_id,v_actor);
  INSERT INTO public.person_roles(person_id,role_key,assigned_by)
    VALUES (v_actor_id,'donations_reviewer','integration_test');

  SELECT * INTO STRICT v_source FROM public.issue19_create_contributor(
    v_actor,'organization',NULL,NULL,'Reassignment Test Source Organization',
    NULL,NULL,'Test source');
  SELECT * INTO STRICT v_target FROM public.issue19_create_contributor(
    v_actor,'organization',NULL,NULL,'Reassignment Test Target Organization',
    NULL,NULL,'Test target');

  v_email := public.issue19_add_contributor_contact(v_actor,'organization',
    v_source.party_id,'email','organization-move-test@example.invalid','Test email');
  v_phone := public.issue19_add_contributor_contact(v_actor,'organization',
    v_source.party_id,'phone','970-555-0137','Test phone');
  v_address := public.issue19_add_contributor_address(v_actor,'organization',
    v_source.party_id,'100 Test Street',NULL,'Loveland','CO','80537','USA','Test address');

  -- Reject unauthorized reassignment before touching any contact.
  BEGIN
    PERFORM public.issue19_reassign_organization_contact(
      'unprivileged@example.invalid',v_source.party_id,'email',v_email,
      v_target.party_id,'Unauthorized attempt');
    RAISE EXCEPTION 'Unprivileged organization reassignment succeeded';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'Donations reviewer permission required' THEN RAISE; END IF;
  END;

  -- Every contact type must move both its domain record and canonical owner.
  FOR v_kind,v_contact_id,v_source_table IN
    SELECT 'email'::text,v_email,'contributor_emails'::text
    UNION ALL SELECT 'phone',v_phone,'contributor_phones'
    UNION ALL SELECT 'address',v_address,'contributor_addresses'
  LOOP
    SELECT pcs.party_contact_id INTO STRICT v_canonical_before
    FROM public.party_contact_sources pcs
    WHERE pcs.source_table=v_source_table AND pcs.source_id=v_contact_id
      AND pcs.status='active';

    IF NOT public.issue19_reassign_organization_contact(
      v_actor,v_source.party_id,v_kind,v_contact_id,v_target.party_id,
      'Correct organization contact ownership') THEN
      RAISE EXCEPTION 'Reassignment returned false for %',v_kind;
    END IF;

    SELECT pcs.party_contact_id INTO STRICT v_canonical_after
    FROM public.party_contact_sources pcs
    WHERE pcs.source_table=v_source_table AND pcs.source_id=v_contact_id
      AND pcs.status='active';
    IF v_canonical_after IS DISTINCT FROM v_canonical_before THEN
      RAISE EXCEPTION 'Canonical contact ID changed during % reassignment',v_kind;
    END IF;
    IF (SELECT count(*) FROM public.party_contacts pc
        WHERE pc.organization_id=v_target.party_id AND pc.status='active'
          AND pc.contact_kind=v_kind
          AND pc.identity_key=(
            SELECT identity_key FROM public.party_contacts
            WHERE party_contact_id=v_canonical_after
          )) <> 1 THEN
      RAISE EXCEPTION 'Canonical contact was duplicated during % reassignment',v_kind;
    END IF;

    IF NOT EXISTS (
      SELECT 1 FROM public.party_contact_sources pcs
      JOIN public.party_contacts pc ON pc.party_contact_id=pcs.party_contact_id
      WHERE pcs.source_table=v_source_table AND pcs.source_id=v_contact_id
        AND pcs.status='active' AND pc.status='active'
        AND pc.organization_id=v_target.party_id
        AND pc.contact_kind=v_kind AND pcs.is_primary=false
    ) THEN
      RAISE EXCEPTION 'Canonical owner/source mapping not updated for %',v_kind;
    END IF;

    IF v_kind='email' AND NOT EXISTS (
      SELECT 1 FROM public.contributor_emails
      WHERE contributor_email_id=v_contact_id AND contributor_id=v_target.contributor_id
        AND is_primary=false AND status='active'
    ) THEN RAISE EXCEPTION 'Email domain ownership not updated'; END IF;

    IF v_kind='phone' AND NOT EXISTS (
      SELECT 1 FROM public.contributor_phones
      WHERE contributor_phone_id=v_contact_id AND contributor_id=v_target.contributor_id
        AND is_primary=false AND status='active'
    ) THEN RAISE EXCEPTION 'Phone domain ownership not updated'; END IF;

    IF v_kind='address' AND NOT EXISTS (
      SELECT 1 FROM public.contributor_addresses
      WHERE contributor_address_id=v_contact_id AND contributor_id=v_target.contributor_id
        AND is_primary=false AND status='active'
    ) THEN RAISE EXCEPTION 'Address domain ownership not updated'; END IF;

    BEGIN
      PERFORM public.issue19_reassign_organization_contact(
        v_actor,v_source.party_id,v_kind,v_contact_id,v_target.party_id,'Repeat move');
      RAISE EXCEPTION 'Already-moved % was reassigned from old source',v_kind;
    EXCEPTION WHEN raise_exception THEN
      IF SQLERRM <> 'Canonical contact does not belong to source organization' THEN RAISE; END IF;
    END;
  END LOOP;

  IF (SELECT count(*) FROM public.audit_log
      WHERE action='organization_contact.reassigned'
        AND entity_type='party_contact'
        AND details->>'source_organization_id'=v_source.party_id::text
        AND details->>'target_organization_id'=v_target.party_id::text) <> 3 THEN
    RAISE EXCEPTION 'Expected three audited organization contact reassignments';
  END IF;

  RAISE NOTICE 'Organization contact reassignment checks passed; rolling back fixtures.';
END $test$;

ROLLBACK;
