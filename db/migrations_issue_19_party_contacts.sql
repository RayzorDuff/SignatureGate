-- Issue #19 contact foundation. Apply once after canonical_people.sql.
-- Legacy contact rows stay in place for agreement and mailing-list foreign
-- keys; every current and future write synchronizes to party contacts.
\set ON_ERROR_STOP on
BEGIN;

DO $$
BEGIN
  IF to_regclass('public.member_profiles') IS NULL
    OR to_regclass('public.contributor_profiles') IS NULL
    OR to_regclass('public.member_emails') IS NULL
    OR to_regclass('public.contributor_addresses') IS NULL
  THEN RAISE EXCEPTION 'Apply canonical people and contributor migrations first';
  END IF;
END $$;

LOCK TABLE public.people, public.organizations, public.members,
  public.contributors, public.member_emails, public.member_phones,
  public.member_addresses, public.contributor_emails,
  public.contributor_phones, public.contributor_addresses
  IN SHARE ROW EXCLUSIVE MODE;

-- A shared contact never implies that two parties are the same person.
CREATE TABLE public.party_contacts (
  party_contact_id uuid PRIMARY KEY DEFAULT public.uuid_generate_v4(),
  person_id uuid REFERENCES public.people(person_id),
  organization_id uuid REFERENCES public.organizations(organization_id),
  contact_kind text NOT NULL CHECK (contact_kind IN ('email', 'phone', 'address')),
  contact_value text,
  address_1 text,
  address_2 text,
  city text,
  state text,
  postal_code text,
  country text,
  identity_key text GENERATED ALWAYS AS (
    CASE contact_kind
      WHEN 'email' THEN NULLIF(lower(btrim(contact_value)), '')
      WHEN 'phone' THEN NULLIF(public.normalize_us_phone(contact_value), '')
      WHEN 'address' THEN NULLIF(public.member_address_identity_key(
        address_1, address_2, postal_code, country), '')
    END
  ) STORED,
  is_verified boolean NOT NULL DEFAULT false,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'archived')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT party_contacts_one_owner CHECK
    ((person_id IS NOT NULL) <> (organization_id IS NOT NULL)),
  CONSTRAINT party_contacts_value CHECK (
    (contact_kind IN ('email', 'phone')
      AND NULLIF(btrim(contact_value), '') IS NOT NULL AND address_1 IS NULL)
    OR (contact_kind = 'address' AND contact_value IS NULL
      AND NULLIF(btrim(address_1), '') IS NOT NULL)
  )
);
CREATE UNIQUE INDEX uq_party_contacts_person_value
  ON public.party_contacts(person_id, contact_kind, identity_key)
  WHERE person_id IS NOT NULL AND identity_key IS NOT NULL;
CREATE UNIQUE INDEX uq_party_contacts_organization_value
  ON public.party_contacts(organization_id, contact_kind, identity_key)
  WHERE organization_id IS NOT NULL AND identity_key IS NOT NULL;
CREATE INDEX idx_party_contacts_person ON public.party_contacts(person_id, contact_kind);
CREATE INDEX idx_party_contacts_organization ON public.party_contacts(organization_id, contact_kind);
CREATE INDEX idx_party_contacts_lookup ON public.party_contacts(contact_kind, identity_key)
  WHERE status = 'active' AND contact_kind IN ('email','phone');
CREATE TRIGGER trg_party_contacts_updated_at BEFORE UPDATE ON public.party_contacts
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Multiple legacy records can express different uses of the same contact.
-- Source IDs and primary/verification flags remain available for Documenso,
-- Listmonk, and domain-specific email/address selection.
CREATE TABLE public.party_contact_sources (
  source_table text NOT NULL CHECK (source_table IN (
    'member_emails', 'member_phones', 'member_addresses',
    'contributor_emails', 'contributor_phones', 'contributor_addresses')),
  source_id uuid NOT NULL,
  party_contact_id uuid NOT NULL REFERENCES public.party_contacts(party_contact_id),
  source text,
  status text NOT NULL CHECK (status IN ('active','archived')),
  is_primary boolean NOT NULL DEFAULT false,
  is_verified boolean NOT NULL DEFAULT false,
  address_type text,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (source_table, source_id)
);
CREATE INDEX idx_party_contact_sources_contact
  ON public.party_contact_sources(party_contact_id, status);
CREATE TRIGGER trg_party_contact_sources_updated_at
  BEFORE UPDATE ON public.party_contact_sources FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

CREATE FUNCTION public.refresh_party_contact_status(p_contact_id uuid)
RETURNS void LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
DECLARE v_active boolean; v_verified boolean;
BEGIN
  SELECT COALESCE(bool_or(status = 'active'), false),
    COALESCE(bool_or(status = 'active' AND is_verified), false)
  INTO v_active, v_verified FROM public.party_contact_sources
  WHERE party_contact_id = p_contact_id;
  UPDATE public.party_contacts c
  SET status = CASE WHEN v_active THEN 'active' ELSE 'archived' END,
      is_verified = v_verified
  WHERE c.party_contact_id = p_contact_id
    AND (c.status, c.is_verified) IS DISTINCT FROM
      (CASE WHEN v_active THEN 'active' ELSE 'archived' END, v_verified);
END $$;

-- Reuse the importer for backfill and all subsequent Appsmith/n8n writes.
-- The owner always comes from the member or contributor foreign key.
CREATE FUNCTION public.sync_party_contact_source(p_table text, p_source_id uuid)
RETURNS void LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
DECLARE
  v_id_column text;
  v_row jsonb;
  v_person_id uuid;
  v_organization_id uuid;
  v_party_id uuid;
  v_kind text;
  v_value text;
  v_address_1 text;
  v_address_2 text;
  v_city text;
  v_state text;
  v_postal_code text;
  v_country text;
  v_key text;
  v_contact_id uuid;
  v_old_contact_id uuid;
BEGIN
  IF p_source_id IS NULL THEN RAISE EXCEPTION 'A contact source ID is required'; END IF;
  CASE p_table
    WHEN 'member_emails' THEN v_id_column := 'member_email_id'; v_kind := 'email';
    WHEN 'member_phones' THEN v_id_column := 'member_phone_id'; v_kind := 'phone';
    WHEN 'member_addresses' THEN v_id_column := 'member_address_id'; v_kind := 'address';
    WHEN 'contributor_emails' THEN v_id_column := 'contributor_email_id'; v_kind := 'email';
    WHEN 'contributor_phones' THEN v_id_column := 'contributor_phone_id'; v_kind := 'phone';
    WHEN 'contributor_addresses' THEN v_id_column := 'contributor_address_id'; v_kind := 'address';
    ELSE RAISE EXCEPTION 'Unsupported contact source table %', p_table;
  END CASE;

  SELECT party_contact_id INTO v_old_contact_id FROM public.party_contact_sources
  WHERE source_table = p_table AND source_id = p_source_id;
  IF left(p_table, 7) = 'member_' THEN
    EXECUTE format('SELECT to_jsonb(t), m.person_id, NULL::uuid
      FROM public.%I t JOIN public.members m ON m.member_id = t.member_id
      WHERE t.%I = $1', p_table, v_id_column)
      INTO v_row, v_person_id, v_organization_id USING p_source_id;
  ELSE
    EXECUTE format('SELECT to_jsonb(t), c.person_id, c.organization_id
      FROM public.%I t JOIN public.contributors c
      ON c.contributor_id = t.contributor_id WHERE t.%I = $1',
      p_table, v_id_column)
      INTO v_row, v_person_id, v_organization_id USING p_source_id;
  END IF;

  IF v_row IS NULL THEN
    DELETE FROM public.party_contact_sources
    WHERE source_table = p_table AND source_id = p_source_id;
    IF v_old_contact_id IS NOT NULL THEN
      PERFORM public.refresh_party_contact_status(v_old_contact_id);
    END IF;
    RETURN;
  END IF;

  v_party_id := COALESCE(v_person_id, v_organization_id);
  IF v_party_id IS NULL THEN
    RAISE EXCEPTION 'Contact source %/% has no party', p_table, p_source_id;
  END IF;
  v_value := CASE v_kind WHEN 'email' THEN v_row->>'email'
    WHEN 'phone' THEN v_row->>'phone' END;
  v_address_1 := v_row->>'address_1';
  v_address_2 := v_row->>'address_2';
  v_city := v_row->>'city';
  v_state := v_row->>'state';
  v_postal_code := v_row->>'postal_code';
  v_country := v_row->>'country';
  v_key := CASE v_kind
    WHEN 'email' THEN NULLIF(lower(btrim(v_value)), '')
    WHEN 'phone' THEN NULLIF(public.normalize_us_phone(v_value), '')
    WHEN 'address' THEN NULLIF(public.member_address_identity_key(
      v_address_1, v_address_2, v_postal_code, v_country), '') END;

  -- Empty legacy rows remain untouched but cannot become valid contacts.
  IF (v_kind IN ('email','phone') AND NULLIF(btrim(v_value), '') IS NULL)
    OR (v_kind = 'address' AND NULLIF(btrim(v_address_1), '') IS NULL) THEN
    DELETE FROM public.party_contact_sources
    WHERE source_table = p_table AND source_id = p_source_id;
    IF v_old_contact_id IS NOT NULL THEN
      PERFORM public.refresh_party_contact_status(v_old_contact_id);
    END IF;
    RETURN;
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(
    v_party_id::text || ':' || v_kind, 190019));
  IF v_key IS NOT NULL THEN
    SELECT party_contact_id INTO v_contact_id FROM public.party_contacts c
    WHERE c.contact_kind = v_kind AND c.identity_key = v_key
      AND c.person_id IS NOT DISTINCT FROM v_person_id
      AND c.organization_id IS NOT DISTINCT FROM v_organization_id
    FOR UPDATE;
  END IF;
  IF v_contact_id IS NULL AND v_old_contact_id IS NOT NULL THEN
    SELECT party_contact_id INTO v_contact_id FROM public.party_contacts c
    WHERE c.party_contact_id = v_old_contact_id AND c.contact_kind = v_kind
      AND c.person_id IS NOT DISTINCT FROM v_person_id
      AND c.organization_id IS NOT DISTINCT FROM v_organization_id
      AND c.identity_key IS NOT DISTINCT FROM v_key
    FOR UPDATE;
  END IF;

  IF v_contact_id IS NULL THEN
    INSERT INTO public.party_contacts
      (person_id, organization_id, contact_kind, contact_value,
       address_1, address_2, city, state, postal_code, country)
    VALUES (v_person_id, v_organization_id, v_kind, v_value,
      CASE WHEN v_kind = 'address' THEN v_address_1 END,
      CASE WHEN v_kind = 'address' THEN v_address_2 END,
      CASE WHEN v_kind = 'address' THEN v_city END,
      CASE WHEN v_kind = 'address' THEN v_state END,
      CASE WHEN v_kind = 'address' THEN v_postal_code END,
      CASE WHEN v_kind = 'address' THEN v_country END)
    RETURNING party_contact_id INTO v_contact_id;
  ELSIF v_old_contact_id = v_contact_id THEN
    -- Preserve a member's display spelling when a donor source is linked.
    -- Editing an already mapped source updates the canonical presentation.
    UPDATE public.party_contacts c
    SET contact_value = v_value,
        address_1 = CASE WHEN v_kind = 'address' THEN v_address_1 END,
        address_2 = CASE WHEN v_kind = 'address' THEN v_address_2 END,
        city = CASE WHEN v_kind = 'address' THEN v_city END,
        state = CASE WHEN v_kind = 'address' THEN v_state END,
        postal_code = CASE WHEN v_kind = 'address' THEN v_postal_code END,
        country = CASE WHEN v_kind = 'address' THEN v_country END
    WHERE c.party_contact_id = v_contact_id
      AND (c.contact_value, c.address_1, c.address_2, c.city,
        c.state, c.postal_code, c.country)
        IS DISTINCT FROM (v_value,
          CASE WHEN v_kind = 'address' THEN v_address_1 END,
          CASE WHEN v_kind = 'address' THEN v_address_2 END,
          CASE WHEN v_kind = 'address' THEN v_city END,
          CASE WHEN v_kind = 'address' THEN v_state END,
          CASE WHEN v_kind = 'address' THEN v_postal_code END,
          CASE WHEN v_kind = 'address' THEN v_country END);
  END IF;

  INSERT INTO public.party_contact_sources
    (source_table, source_id, party_contact_id, source, status, is_primary,
     is_verified, address_type, notes)
  VALUES (p_table, p_source_id, v_contact_id, v_row->>'source',
    CASE WHEN v_row->>'status' = 'active' THEN 'active' ELSE 'archived' END,
    COALESCE((v_row->>'is_primary')::boolean, false),
    COALESCE((v_row->>'is_verified')::boolean, false),
    v_row->>'address_type', v_row->>'notes')
  ON CONFLICT (source_table, source_id) DO UPDATE
    SET party_contact_id = EXCLUDED.party_contact_id,
        source = EXCLUDED.source,
        status = EXCLUDED.status,
        is_primary = EXCLUDED.is_primary,
        is_verified = EXCLUDED.is_verified,
        address_type = EXCLUDED.address_type,
        notes = EXCLUDED.notes;

  PERFORM public.refresh_party_contact_status(v_contact_id);
  IF v_old_contact_id IS NOT NULL AND v_old_contact_id <> v_contact_id THEN
    PERFORM public.refresh_party_contact_status(v_old_contact_id);
  END IF;
END $$;

CREATE FUNCTION public.sync_party_contact_source_trigger()
RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
DECLARE v_id_column text; v_id uuid;
BEGIN
  v_id_column := CASE TG_TABLE_NAME
    WHEN 'member_emails' THEN 'member_email_id'
    WHEN 'member_phones' THEN 'member_phone_id'
    WHEN 'member_addresses' THEN 'member_address_id'
    WHEN 'contributor_emails' THEN 'contributor_email_id'
    WHEN 'contributor_phones' THEN 'contributor_phone_id'
    WHEN 'contributor_addresses' THEN 'contributor_address_id'
    ELSE NULL END;
  IF v_id_column IS NULL THEN RAISE EXCEPTION 'Unsupported contact trigger table'; END IF;
  v_id := ((CASE WHEN TG_OP = 'DELETE' THEN to_jsonb(OLD)
    ELSE to_jsonb(NEW) END)->>v_id_column)::uuid;
  PERFORM public.sync_party_contact_source(TG_TABLE_NAME, v_id);
  RETURN NULL;
END $$;

CREATE TRIGGER trg_member_emails_party_contact
  AFTER INSERT OR UPDATE OR DELETE ON public.member_emails
  FOR EACH ROW EXECUTE FUNCTION public.sync_party_contact_source_trigger();
CREATE TRIGGER trg_member_phones_party_contact
  AFTER INSERT OR UPDATE OR DELETE ON public.member_phones
  FOR EACH ROW EXECUTE FUNCTION public.sync_party_contact_source_trigger();
CREATE TRIGGER trg_member_addresses_party_contact
  AFTER INSERT OR UPDATE OR DELETE ON public.member_addresses
  FOR EACH ROW EXECUTE FUNCTION public.sync_party_contact_source_trigger();
CREATE TRIGGER trg_contributor_emails_party_contact
  AFTER INSERT OR UPDATE OR DELETE ON public.contributor_emails
  FOR EACH ROW EXECUTE FUNCTION public.sync_party_contact_source_trigger();
CREATE TRIGGER trg_contributor_phones_party_contact
  AFTER INSERT OR UPDATE OR DELETE ON public.contributor_phones
  FOR EACH ROW EXECUTE FUNCTION public.sync_party_contact_source_trigger();
CREATE TRIGGER trg_contributor_addresses_party_contact
  AFTER INSERT OR UPDATE OR DELETE ON public.contributor_addresses
  FOR EACH ROW EXECUTE FUNCTION public.sync_party_contact_source_trigger();

-- Link reconciliation can replace the temporary member person's ID with the
-- donor person's ID. Remap that member's contact sources at the same time.
CREATE FUNCTION public.sync_party_owner_contacts_trigger()
RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
DECLARE v record;
BEGIN
  IF TG_TABLE_NAME = 'members' THEN
    FOR v IN SELECT 'member_emails'::text tab, member_email_id id
      FROM public.member_emails WHERE member_id = NEW.member_id
      UNION ALL SELECT 'member_phones', member_phone_id
      FROM public.member_phones WHERE member_id = NEW.member_id
      UNION ALL SELECT 'member_addresses', member_address_id
      FROM public.member_addresses WHERE member_id = NEW.member_id
    LOOP PERFORM public.sync_party_contact_source(v.tab, v.id); END LOOP;
  ELSE
    FOR v IN SELECT 'contributor_emails'::text tab, contributor_email_id id
      FROM public.contributor_emails WHERE contributor_id = NEW.contributor_id
      UNION ALL SELECT 'contributor_phones', contributor_phone_id
      FROM public.contributor_phones WHERE contributor_id = NEW.contributor_id
      UNION ALL SELECT 'contributor_addresses', contributor_address_id
      FROM public.contributor_addresses WHERE contributor_id = NEW.contributor_id
    LOOP PERFORM public.sync_party_contact_source(v.tab, v.id); END LOOP;
  END IF;
  RETURN NULL;
END $$;
CREATE TRIGGER trg_members_remap_party_contacts
  AFTER UPDATE OF person_id ON public.members
  FOR EACH ROW WHEN (OLD.person_id IS DISTINCT FROM NEW.person_id)
  EXECUTE FUNCTION public.sync_party_owner_contacts_trigger();
CREATE TRIGGER trg_contributors_remap_party_contacts
  AFTER UPDATE OF person_id, organization_id ON public.contributors
  FOR EACH ROW WHEN (OLD.person_id IS DISTINCT FROM NEW.person_id
    OR OLD.organization_id IS DISTINCT FROM NEW.organization_id)
  EXECUTE FUNCTION public.sync_party_owner_contacts_trigger();

-- The first active member source wins the contact's display formatting.
DO $$
DECLARE v record;
BEGIN
  FOR v IN
    SELECT source_table, source_id FROM (
      SELECT 'member_emails'::text source_table, member_email_id source_id,
        created_at, status FROM public.member_emails
      UNION ALL SELECT 'member_phones', member_phone_id, created_at, status
        FROM public.member_phones
      UNION ALL SELECT 'member_addresses', member_address_id, created_at, status
        FROM public.member_addresses
      UNION ALL SELECT 'contributor_emails', contributor_email_id, created_at, status
        FROM public.contributor_emails
      UNION ALL SELECT 'contributor_phones', contributor_phone_id, created_at, status
        FROM public.contributor_phones
      UNION ALL SELECT 'contributor_addresses', contributor_address_id, created_at, status
        FROM public.contributor_addresses
    ) s
    ORDER BY CASE WHEN status = 'active' THEN 0 ELSE 1 END,
      CASE WHEN source_table LIKE 'member_%' THEN 0 ELSE 1 END,
      created_at, source_id
  LOOP
    PERFORM public.sync_party_contact_source(v.source_table, v.source_id);
  END LOOP;
END $$;

CREATE VIEW public.v_party_contacts AS
SELECT c.party_contact_id, c.person_id, c.organization_id,
  c.contact_kind, c.contact_value, c.address_1, c.address_2, c.city,
  c.state, c.postal_code, c.country, c.identity_key, c.is_verified, c.status,
  c.created_at, c.updated_at,
  (SELECT count(*) FROM public.party_contact_sources s
    WHERE s.party_contact_id = c.party_contact_id) AS source_count
FROM public.party_contacts c;

COMMENT ON TABLE public.party_contacts IS
  'Party-owned contacts. Shared values never imply shared identity.';
COMMENT ON TABLE public.party_contact_sources IS
  'Domain preferences and original IDs. Preserve until agreement, Listmonk, Appsmith and n8n readers move.';

DO $$
DECLARE v_sources bigint; v_mapped bigint;
BEGIN
  SELECT (SELECT count(*) FROM public.member_emails WHERE NULLIF(btrim(email), '') IS NOT NULL)
    + (SELECT count(*) FROM public.member_phones WHERE NULLIF(btrim(phone), '') IS NOT NULL)
    + (SELECT count(*) FROM public.member_addresses WHERE NULLIF(btrim(address_1), '') IS NOT NULL)
    + (SELECT count(*) FROM public.contributor_emails WHERE NULLIF(btrim(email), '') IS NOT NULL)
    + (SELECT count(*) FROM public.contributor_phones WHERE NULLIF(btrim(phone), '') IS NOT NULL)
    + (SELECT count(*) FROM public.contributor_addresses WHERE NULLIF(btrim(address_1), '') IS NOT NULL)
    INTO v_sources;
  SELECT count(*) INTO v_mapped FROM public.party_contact_sources;
  IF v_mapped <> v_sources THEN
    RAISE EXCEPTION 'Contact backfill incomplete: % source rows, % mappings',
      v_sources, v_mapped;
  END IF;
END $$;

COMMIT;
SELECT contact_kind, status, count(*) FROM public.party_contacts
GROUP BY contact_kind, status ORDER BY contact_kind, status;
