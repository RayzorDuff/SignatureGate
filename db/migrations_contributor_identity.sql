-- SignatureGate Issue #19: contributor identity independent of membership.
--
-- This migration is Phase 1 of Issue #19. It introduces a contributor domain
-- for individual and organization donors, links individuals to members without
-- making membership the donation identity, and moves donations to the donor
-- states identified/anonymous/unresolved.
--
-- Deployment prerequisite:
--   db/migrations_issue_17_anonymous_cash_donations.sql

\set ON_ERROR_STOP on

BEGIN;

LOCK TABLE public.donations IN SHARE ROW EXCLUSIVE MODE;

DO $$
BEGIN
  IF to_regclass('public.member_emails') IS NULL
    OR to_regclass('public.member_phones') IS NULL
    OR to_regclass('public.member_addresses') IS NULL
    OR to_regprocedure('public.member_address_identity_key(text,text,text,text)') IS NULL
  THEN
    RAISE EXCEPTION
      'Issue #19 requires the member contact and v1.1.0 address identity migrations.';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'donations'
      AND column_name = 'donor_kind'
  ) THEN
    RAISE EXCEPTION
      'Issue #19 requires db/migrations_issue_17_anonymous_cash_donations.sql.';
  END IF;
END;
$$;

CREATE TABLE IF NOT EXISTS public.contributors (
  contributor_id uuid PRIMARY KEY DEFAULT public.uuid_generate_v4(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  contributor_type text NOT NULL,
  display_name text NOT NULL,
  first_name text,
  last_name text,
  organization_name text,
  status text NOT NULL DEFAULT 'active',
  source text,
  notes text,
  merged_into_contributor_id uuid REFERENCES public.contributors(contributor_id),
  archived_at timestamptz,
  archived_by uuid REFERENCES public.members(member_id),
  archive_reason text,
  CONSTRAINT contributors_type_check
    CHECK (contributor_type IN ('individual', 'organization')),
  CONSTRAINT contributors_status_check
    CHECK (status IN ('active', 'archived', 'merged')),
  CONSTRAINT contributors_name_check
    CHECK (
      (contributor_type = 'individual'
        AND NULLIF(btrim(COALESCE(display_name, '')), '') IS NOT NULL)
      OR
      (contributor_type = 'organization'
        AND NULLIF(btrim(COALESCE(organization_name, '')), '') IS NOT NULL)
    ),
  CONSTRAINT contributors_merge_check
    CHECK (
      (status = 'merged' AND merged_into_contributor_id IS NOT NULL)
      OR
      (status <> 'merged' AND merged_into_contributor_id IS NULL)
    ),
  CONSTRAINT contributors_not_self_merged_check
    CHECK (merged_into_contributor_id IS NULL OR merged_into_contributor_id <> contributor_id)
);

CREATE TABLE IF NOT EXISTS public.contributor_member_links (
  contributor_member_link_id uuid PRIMARY KEY DEFAULT public.uuid_generate_v4(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  contributor_id uuid NOT NULL REFERENCES public.contributors(contributor_id),
  member_id uuid NOT NULL REFERENCES public.members(member_id),
  status text NOT NULL DEFAULT 'active',
  linked_at timestamptz NOT NULL DEFAULT now(),
  linked_by uuid REFERENCES public.members(member_id),
  ended_at timestamptz,
  ended_by uuid REFERENCES public.members(member_id),
  link_reason text,
  end_reason text,
  CONSTRAINT contributor_member_links_status_check
    CHECK (status IN ('active', 'ended')),
  CONSTRAINT contributor_member_links_end_check
    CHECK (
      (status = 'active' AND ended_at IS NULL)
      OR
      (status = 'ended' AND ended_at IS NOT NULL)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_contributor_member_links_active_contributor
  ON public.contributor_member_links (contributor_id)
  WHERE status = 'active';

CREATE UNIQUE INDEX IF NOT EXISTS uq_contributor_member_links_active_member
  ON public.contributor_member_links (member_id)
  WHERE status = 'active';

CREATE INDEX IF NOT EXISTS idx_contributor_member_links_member_history
  ON public.contributor_member_links (member_id, linked_at DESC);

CREATE TABLE IF NOT EXISTS public.contributor_emails (
  contributor_email_id uuid PRIMARY KEY DEFAULT public.uuid_generate_v4(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  contributor_id uuid NOT NULL REFERENCES public.contributors(contributor_id) ON DELETE CASCADE,
  email text NOT NULL,
  email_normalized text GENERATED ALWAYS AS (lower(btrim(email))) STORED,
  is_primary boolean NOT NULL DEFAULT false,
  is_verified boolean NOT NULL DEFAULT false,
  status text NOT NULL DEFAULT 'active',
  source text,
  notes text,
  archived_at timestamptz,
  archived_by uuid REFERENCES public.members(member_id),
  archive_reason text,
  CONSTRAINT contributor_emails_status_check
    CHECK (status IN ('active', 'archived'))
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_contributor_emails_active_value
  ON public.contributor_emails (contributor_id, email_normalized)
  WHERE status = 'active'
    AND email_normalized IS NOT NULL
    AND email_normalized <> '';

CREATE INDEX IF NOT EXISTS idx_contributor_emails_lookup
  ON public.contributor_emails (email_normalized)
  WHERE status = 'active';

CREATE TABLE IF NOT EXISTS public.contributor_phones (
  contributor_phone_id uuid PRIMARY KEY DEFAULT public.uuid_generate_v4(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  contributor_id uuid NOT NULL REFERENCES public.contributors(contributor_id) ON DELETE CASCADE,
  phone text NOT NULL,
  phone_normalized text GENERATED ALWAYS AS (public.normalize_us_phone(phone)) STORED,
  is_primary boolean NOT NULL DEFAULT false,
  is_verified boolean NOT NULL DEFAULT false,
  status text NOT NULL DEFAULT 'active',
  source text,
  notes text,
  archived_at timestamptz,
  archived_by uuid REFERENCES public.members(member_id),
  archive_reason text,
  CONSTRAINT contributor_phones_status_check
    CHECK (status IN ('active', 'archived'))
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_contributor_phones_active_value
  ON public.contributor_phones (contributor_id, phone_normalized)
  WHERE status = 'active'
    AND phone_normalized IS NOT NULL
    AND phone_normalized <> '';

CREATE INDEX IF NOT EXISTS idx_contributor_phones_lookup
  ON public.contributor_phones (phone_normalized)
  WHERE status = 'active';

CREATE TABLE IF NOT EXISTS public.contributor_addresses (
  contributor_address_id uuid PRIMARY KEY DEFAULT public.uuid_generate_v4(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  contributor_id uuid NOT NULL REFERENCES public.contributors(contributor_id) ON DELETE CASCADE,
  address_type text NOT NULL DEFAULT 'mailing',
  address_1 text,
  address_2 text,
  city text,
  state text,
  postal_code text,
  country text DEFAULT 'USA',
  address_identity_key text GENERATED ALWAYS AS (
    public.member_address_identity_key(address_1, address_2, postal_code, country)
  ) STORED,
  is_primary boolean NOT NULL DEFAULT false,
  status text NOT NULL DEFAULT 'active',
  source text,
  notes text,
  archived_at timestamptz,
  archived_by uuid REFERENCES public.members(member_id),
  archive_reason text,
  CONSTRAINT contributor_addresses_status_check
    CHECK (status IN ('active', 'archived'))
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_contributor_addresses_active_identity
  ON public.contributor_addresses (contributor_id, address_identity_key)
  WHERE status = 'active'
    AND address_identity_key IS NOT NULL
    AND address_identity_key <> '';

CREATE INDEX IF NOT EXISTS idx_contributor_addresses_lookup
  ON public.contributor_addresses (address_identity_key)
  WHERE status = 'active';

CREATE TABLE IF NOT EXISTS public.contributor_external_identities (
  contributor_external_identity_id uuid PRIMARY KEY DEFAULT public.uuid_generate_v4(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  contributor_id uuid NOT NULL REFERENCES public.contributors(contributor_id) ON DELETE CASCADE,
  provider text NOT NULL,
  provider_identity text NOT NULL,
  status text NOT NULL DEFAULT 'active',
  source text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  CONSTRAINT contributor_external_identities_status_check
    CHECK (status IN ('active', 'archived'))
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_contributor_external_identity_active
  ON public.contributor_external_identities (lower(btrim(provider)), btrim(provider_identity))
  WHERE status = 'active';

DROP TRIGGER IF EXISTS trg_contributors_updated_at ON public.contributors;
CREATE TRIGGER trg_contributors_updated_at
BEFORE UPDATE ON public.contributors
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_contributor_member_links_updated_at ON public.contributor_member_links;
CREATE TRIGGER trg_contributor_member_links_updated_at
BEFORE UPDATE ON public.contributor_member_links
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_contributor_emails_updated_at ON public.contributor_emails;
CREATE TRIGGER trg_contributor_emails_updated_at
BEFORE UPDATE ON public.contributor_emails
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_contributor_phones_updated_at ON public.contributor_phones;
CREATE TRIGGER trg_contributor_phones_updated_at
BEFORE UPDATE ON public.contributor_phones
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_contributor_addresses_updated_at ON public.contributor_addresses;
CREATE TRIGGER trg_contributor_addresses_updated_at
BEFORE UPDATE ON public.contributor_addresses
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_contributor_external_identities_updated_at
  ON public.contributor_external_identities;
CREATE TRIGGER trg_contributor_external_identities_updated_at
BEFORE UPDATE ON public.contributor_external_identities
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE OR REPLACE FUNCTION public.validate_contributor_member_link()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.contributors c
    WHERE c.contributor_id = NEW.contributor_id
      AND c.contributor_type = 'individual'
      AND c.status = 'active'
  ) THEN
    RAISE EXCEPTION 'Only an active individual contributor can be linked to a member.';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_contributor_member_link
  ON public.contributor_member_links;
CREATE TRIGGER trg_validate_contributor_member_link
BEFORE INSERT OR UPDATE OF contributor_id, member_id, status
ON public.contributor_member_links
FOR EACH ROW
WHEN (NEW.status = 'active')
EXECUTE FUNCTION public.validate_contributor_member_link();

CREATE OR REPLACE FUNCTION public.ensure_member_contributor(p_member_id uuid)
RETURNS uuid
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_contributor_id uuid;
  v_member public.members%ROWTYPE;
BEGIN
  IF p_member_id IS NULL THEN
    RAISE EXCEPTION 'A member is required.';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(p_member_id::text, 190019));

  SELECT cml.contributor_id
  INTO v_contributor_id
  FROM public.contributor_member_links cml
  JOIN public.contributors c ON c.contributor_id = cml.contributor_id
  JOIN public.members m ON m.member_id = cml.member_id
  WHERE cml.member_id = p_member_id
    AND (
      (cml.status = 'active' AND c.status = 'active')
      OR
      (m.status <> 'active' AND cml.status = 'ended' AND c.status = 'archived')
    )
  ORDER BY CASE WHEN cml.status = 'active' THEN 0 ELSE 1 END, cml.linked_at DESC
  LIMIT 1;

  IF v_contributor_id IS NOT NULL THEN
    RETURN v_contributor_id;
  END IF;

  SELECT *
  INTO v_member
  FROM public.members m
  WHERE m.member_id = p_member_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Member % was not found.', p_member_id;
  END IF;

  INSERT INTO public.contributors (
    contributor_type,
    display_name,
    first_name,
    last_name,
    status,
    source,
    notes
  )
  VALUES (
    'individual',
    COALESCE(
      NULLIF(btrim(concat_ws(' ', v_member.first_name, v_member.last_name)), ''),
      NULLIF(lower(btrim(v_member.email)), ''),
      'Member ' || p_member_id::text
    ),
    NULLIF(btrim(v_member.first_name), ''),
    NULLIF(btrim(v_member.last_name), ''),
    CASE WHEN v_member.status = 'active' THEN 'active' ELSE 'archived' END,
    'member_backfill',
    'Created from member identity for Issue #19'
  )
  RETURNING contributor_id INTO v_contributor_id;

  -- Historical donations can reference inactive members. Their contributor is
  -- retained as archived but still receives a historical ended link.
  IF v_member.status = 'active' THEN
    INSERT INTO public.contributor_member_links (
      contributor_id,
      member_id,
      status,
      link_reason
    )
    VALUES (
      v_contributor_id,
      p_member_id,
      'active',
      'Member contributor backfill for Issue #19'
    );
  ELSE
    INSERT INTO public.contributor_member_links (
      contributor_id,
      member_id,
      status,
      link_reason,
      ended_at,
      end_reason
    )
    VALUES (
      v_contributor_id,
      p_member_id,
      'ended',
      'Member contributor backfill for Issue #19',
      now(),
      'Member was not active when contributor identity was created'
    );
  END IF;

  INSERT INTO public.contributor_emails (
    contributor_id, email, is_primary, is_verified, source, notes
  )
  SELECT
    v_contributor_id,
    me.email,
    me.is_primary,
    me.is_verified,
    'member_backfill',
    'Copied from member email for Issue #19'
  FROM public.member_emails me
  WHERE me.member_id = p_member_id
    AND me.status = 'active'
    AND NULLIF(btrim(me.email), '') IS NOT NULL
  ON CONFLICT (contributor_id, email_normalized)
  WHERE status = 'active'
    AND email_normalized IS NOT NULL
    AND email_normalized <> ''
  DO NOTHING;

  IF NOT EXISTS (
    SELECT 1 FROM public.contributor_emails ce
    WHERE ce.contributor_id = v_contributor_id
      AND ce.status = 'active'
  ) AND NULLIF(btrim(v_member.email), '') IS NOT NULL THEN
    INSERT INTO public.contributor_emails (
      contributor_id, email, is_primary, source, notes
    )
    VALUES (
      v_contributor_id,
      v_member.email,
      true,
      'members.email',
      'Copied from member compatibility email for Issue #19'
    )
    ON CONFLICT (contributor_id, email_normalized)
    WHERE status = 'active'
      AND email_normalized IS NOT NULL
      AND email_normalized <> ''
    DO NOTHING;
  END IF;

  INSERT INTO public.contributor_phones (
    contributor_id, phone, is_primary, is_verified, source, notes
  )
  SELECT
    v_contributor_id,
    mp.phone,
    mp.is_primary,
    mp.is_verified,
    'member_backfill',
    'Copied from member phone for Issue #19'
  FROM public.member_phones mp
  WHERE mp.member_id = p_member_id
    AND mp.status = 'active'
    AND NULLIF(public.normalize_us_phone(mp.phone), '') IS NOT NULL
  ON CONFLICT (contributor_id, phone_normalized)
  WHERE status = 'active'
    AND phone_normalized IS NOT NULL
    AND phone_normalized <> ''
  DO NOTHING;

  IF NOT EXISTS (
    SELECT 1 FROM public.contributor_phones cp
    WHERE cp.contributor_id = v_contributor_id
      AND cp.status = 'active'
  ) AND NULLIF(public.normalize_us_phone(v_member.phone), '') IS NOT NULL THEN
    INSERT INTO public.contributor_phones (
      contributor_id, phone, is_primary, source, notes
    )
    VALUES (
      v_contributor_id,
      v_member.phone,
      true,
      'members.phone',
      'Copied from member compatibility phone for Issue #19'
    )
    ON CONFLICT (contributor_id, phone_normalized)
    WHERE status = 'active'
      AND phone_normalized IS NOT NULL
      AND phone_normalized <> ''
    DO NOTHING;
  END IF;

  INSERT INTO public.contributor_addresses (
    contributor_id,
    address_type,
    address_1,
    address_2,
    city,
    state,
    postal_code,
    country,
    is_primary,
    source,
    notes
  )
  SELECT
    v_contributor_id,
    ma.address_type,
    ma.address_1,
    ma.address_2,
    ma.city,
    ma.state,
    ma.postal_code,
    ma.country,
    ma.is_primary,
    'member_backfill',
    'Copied from member address for Issue #19'
  FROM public.member_addresses ma
  WHERE ma.member_id = p_member_id
    AND ma.status = 'active'
  ON CONFLICT (contributor_id, address_identity_key)
  WHERE status = 'active'
    AND address_identity_key IS NOT NULL
    AND address_identity_key <> ''
  DO NOTHING;

  RETURN v_contributor_id;
END;
$$;

-- Backfill a contributor only for members already represented in donations.
-- Contributors for other members are created lazily on their first donation.
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT DISTINCT d.member_id
    FROM public.donations d
    WHERE d.member_id IS NOT NULL
    ORDER BY d.member_id
  LOOP
    PERFORM public.ensure_member_contributor(r.member_id);
  END LOOP;
END;
$$;

ALTER TABLE public.donations
  ADD COLUMN IF NOT EXISTS contributor_id uuid;

-- Remove the Issue #17 checks before translating member -> identified. The
-- replacement checks are installed immediately after the data rewrite.
ALTER TABLE public.donations
  DROP CONSTRAINT IF EXISTS donations_donor_kind_check,
  DROP CONSTRAINT IF EXISTS donations_donor_identity_check,
  DROP CONSTRAINT IF EXISTS donations_donor_kind_provider_check;

UPDATE public.donations d
SET contributor_id = cml.contributor_id
FROM public.contributor_member_links cml
WHERE d.member_id = cml.member_id
  AND d.contributor_id IS NULL
  AND cml.status IN ('active', 'ended');

UPDATE public.donations
SET donor_kind = 'identified'
WHERE donor_kind = 'member';

ALTER TABLE public.donations
  DROP CONSTRAINT IF EXISTS donations_contributor_id_fkey,
  ADD CONSTRAINT donations_contributor_id_fkey
    FOREIGN KEY (contributor_id)
    REFERENCES public.contributors(contributor_id);

ALTER TABLE public.donations
  ADD CONSTRAINT donations_donor_kind_check
    CHECK (donor_kind IN ('identified', 'anonymous', 'unresolved')),
  ADD CONSTRAINT donations_donor_identity_check
    CHECK (
      (donor_kind = 'identified' AND contributor_id IS NOT NULL)
      OR
      (donor_kind IN ('anonymous', 'unresolved')
        AND contributor_id IS NULL
        AND member_id IS NULL)
    ),
  ADD CONSTRAINT donations_donor_kind_provider_check
    CHECK (
      (donor_kind <> 'anonymous' OR provider = 'cash')
      AND
      (donor_kind <> 'unresolved' OR provider <> 'cash')
    );

CREATE INDEX IF NOT EXISTS idx_donations_contributor_donated_at
  ON public.donations (contributor_id, donated_at DESC NULLS LAST)
  WHERE contributor_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.donation_set_donor_kind()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_linked_member_id uuid;
BEGIN
  -- Temporary compatibility for an Appsmith or n8n deployment that is still
  -- sending the Issue #17 value during a staggered rollout.
  IF NEW.donor_kind = 'member' THEN
    NEW.donor_kind := 'identified';
  END IF;

  IF NEW.contributor_id IS NULL AND NEW.member_id IS NOT NULL THEN
    NEW.contributor_id := public.ensure_member_contributor(NEW.member_id);
    NEW.donor_kind := 'identified';
  END IF;

  IF NEW.contributor_id IS NOT NULL THEN
    SELECT cml.member_id
    INTO v_linked_member_id
    FROM public.contributor_member_links cml
    WHERE cml.contributor_id = NEW.contributor_id
      AND cml.status = 'active'
    LIMIT 1;

    IF NEW.member_id IS NULL THEN
      NEW.member_id := v_linked_member_id;
    ELSIF v_linked_member_id IS NULL OR NEW.member_id <> v_linked_member_id THEN
      RAISE EXCEPTION
        'Donation member % is not the active member linked to contributor %.',
        NEW.member_id,
        NEW.contributor_id;
    END IF;

    NEW.donor_kind := 'identified';
  ELSIF NEW.donor_kind IS NULL THEN
    NEW.donor_kind := CASE
      WHEN NEW.provider = 'cash' THEN NULL
      ELSE 'unresolved'
    END;
  END IF;

  IF NEW.provider = 'cash' AND NEW.donor_kind IS NULL THEN
    RAISE EXCEPTION
      'Cash donations require an identified contributor or explicit anonymous identity.';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_donations_set_donor_kind ON public.donations;
CREATE TRIGGER trg_donations_set_donor_kind
BEFORE INSERT OR UPDATE OF member_id, contributor_id, donor_kind, provider
ON public.donations
FOR EACH ROW
EXECUTE FUNCTION public.donation_set_donor_kind();

CREATE OR REPLACE FUNCTION public.upsert_contributor_address(
  p_contributor_id uuid,
  p_address_1 text,
  p_address_type text DEFAULT 'mailing',
  p_address_2 text DEFAULT NULL,
  p_city text DEFAULT NULL,
  p_state text DEFAULT NULL,
  p_postal_code text DEFAULT NULL,
  p_country text DEFAULT 'USA',
  p_is_primary boolean DEFAULT false,
  p_source text DEFAULT NULL,
  p_notes text DEFAULT NULL
)
RETURNS public.contributor_addresses
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_result public.contributor_addresses%ROWTYPE;
  v_identity_key text;
BEGIN
  IF p_contributor_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.contributors c
    WHERE c.contributor_id = p_contributor_id
  ) THEN
    RAISE EXCEPTION 'A valid contributor is required.';
  END IF;

  IF NULLIF(btrim(p_address_1), '') IS NULL THEN
    RAISE EXCEPTION 'Address line 1 is required.';
  END IF;

  v_identity_key := public.member_address_identity_key(
    p_address_1,
    p_address_2,
    p_postal_code,
    p_country
  );

  IF v_identity_key IS NOT NULL THEN
    SELECT *
    INTO v_result
    FROM public.contributor_addresses ca
    WHERE ca.contributor_id = p_contributor_id
      AND ca.address_identity_key = v_identity_key
      AND ca.status = 'active'
    FOR UPDATE;
  END IF;

  IF FOUND THEN
    UPDATE public.contributor_addresses ca
    SET
      address_type = COALESCE(NULLIF(btrim(p_address_type), ''), ca.address_type),
      address_1 = COALESCE(NULLIF(btrim(p_address_1), ''), ca.address_1),
      address_2 = COALESCE(NULLIF(btrim(p_address_2), ''), ca.address_2),
      city = COALESCE(NULLIF(btrim(p_city), ''), ca.city),
      state = COALESCE(NULLIF(btrim(p_state), ''), ca.state),
      postal_code = COALESCE(NULLIF(btrim(p_postal_code), ''), ca.postal_code),
      country = COALESCE(NULLIF(btrim(p_country), ''), ca.country, 'USA'),
      is_primary = ca.is_primary OR COALESCE(p_is_primary, false),
      source = COALESCE(NULLIF(btrim(p_source), ''), ca.source),
      notes = COALESCE(ca.notes, NULLIF(btrim(p_notes), ''))
    WHERE ca.contributor_address_id = v_result.contributor_address_id
    RETURNING * INTO v_result;

    RETURN v_result;
  END IF;

  INSERT INTO public.contributor_addresses (
    contributor_id,
    address_type,
    address_1,
    address_2,
    city,
    state,
    postal_code,
    country,
    is_primary,
    source,
    notes
  )
  VALUES (
    p_contributor_id,
    COALESCE(NULLIF(btrim(p_address_type), ''), 'mailing'),
    NULLIF(btrim(p_address_1), ''),
    NULLIF(btrim(p_address_2), ''),
    NULLIF(btrim(p_city), ''),
    NULLIF(btrim(p_state), ''),
    NULLIF(btrim(p_postal_code), ''),
    COALESCE(NULLIF(btrim(p_country), ''), 'USA'),
    COALESCE(p_is_primary, false),
    NULLIF(btrim(p_source), ''),
    NULLIF(btrim(p_notes), '')
  )
  RETURNING * INTO v_result;

  RETURN v_result;
END;
$$;

CREATE OR REPLACE FUNCTION public.donation_provider_payload(p_donation_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
  SELECT COALESCE(
    al.details->'raw'->'data',
    al.details->'raw'->'payload',
    al.details->'raw'->'transaction',
    al.details->'raw',
    '{}'::jsonb
  )
  FROM public.audit_log al
  WHERE al.entity_type = 'donation'
    AND al.entity_id = p_donation_id::text
    AND al.details ? 'raw'
  ORDER BY al.created_at DESC, al.audit_log_id DESC
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.add_provider_identity_to_contributor(
  p_contributor_id uuid,
  p_provider text,
  p_provider_identity text,
  p_source text DEFAULT NULL,
  p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS void
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NULLIF(btrim(p_provider_identity), '') IS NULL THEN
    RETURN;
  END IF;

  INSERT INTO public.contributor_external_identities (
    contributor_id,
    provider,
    provider_identity,
    source,
    metadata
  )
  VALUES (
    p_contributor_id,
    lower(btrim(p_provider)),
    btrim(p_provider_identity),
    NULLIF(btrim(p_source), ''),
    COALESCE(p_metadata, '{}'::jsonb)
  )
  ON CONFLICT (lower(btrim(provider)), btrim(provider_identity))
  WHERE status = 'active'
  DO UPDATE SET
    metadata = public.contributor_external_identities.metadata || EXCLUDED.metadata,
    source = COALESCE(EXCLUDED.source, public.contributor_external_identities.source);

  IF EXISTS (
    SELECT 1
    FROM public.contributor_external_identities cei
    WHERE lower(btrim(cei.provider)) = lower(btrim(p_provider))
      AND btrim(cei.provider_identity) = btrim(p_provider_identity)
      AND cei.status = 'active'
      AND cei.contributor_id <> p_contributor_id
  ) THEN
    RAISE EXCEPTION 'Provider identity already belongs to another contributor.';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.add_donation_payload_to_contributor(
  p_contributor_id uuid,
  p_donation_id uuid,
  p_source text DEFAULT 'givebutter_review'
)
RETURNS void
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_payload jsonb := COALESCE(public.donation_provider_payload(p_donation_id), '{}'::jsonb);
  v_email text;
  v_phone text;
  v_address jsonb;
  v_provider text;
  v_provider_identity text;
BEGIN
  SELECT d.provider INTO v_provider
  FROM public.donations d
  WHERE d.donation_id = p_donation_id;

  v_email := NULLIF(lower(btrim(COALESCE(
    v_payload->>'email',
    v_payload #>> '{donor,email}',
    v_payload #>> '{supporter,email}',
    v_payload #>> '{payer,email}',
    v_payload #>> '{customer,email}'
  ))), '');

  v_phone := NULLIF(btrim(COALESCE(
    v_payload->>'phone',
    v_payload #>> '{donor,phone}',
    v_payload #>> '{supporter,phone}',
    v_payload #>> '{payer,phone}',
    v_payload #>> '{customer,phone}'
  )), '');

  v_provider_identity := NULLIF(btrim(COALESCE(
    v_payload->>'contact_id',
    v_payload #>> '{donor,id}',
    v_payload #>> '{supporter,id}',
    v_payload #>> '{customer,id}'
  )), '');

  IF v_email IS NOT NULL THEN
    INSERT INTO public.contributor_emails (
      contributor_id, email, is_primary, source, notes
    )
    VALUES (
      p_contributor_id, v_email, true, p_source,
      'Added from donation ' || p_donation_id::text
    )
    ON CONFLICT (contributor_id, email_normalized)
    WHERE status = 'active'
      AND email_normalized IS NOT NULL
      AND email_normalized <> ''
    DO NOTHING;
  END IF;

  IF NULLIF(public.normalize_us_phone(v_phone), '') IS NOT NULL THEN
    INSERT INTO public.contributor_phones (
      contributor_id, phone, is_primary, source, notes
    )
    VALUES (
      p_contributor_id, v_phone, true, p_source,
      'Added from donation ' || p_donation_id::text
    )
    ON CONFLICT (contributor_id, phone_normalized)
    WHERE status = 'active'
      AND phone_normalized IS NOT NULL
      AND phone_normalized <> ''
    DO NOTHING;
  END IF;

  v_address := COALESCE(v_payload->'address', '{}'::jsonb);
  IF NULLIF(btrim(COALESCE(
    v_address->>'address_1',
    v_address->>'line1',
    v_address->>'street',
    v_address->>'street_address'
  )), '') IS NOT NULL THEN
    PERFORM public.upsert_contributor_address(
      p_contributor_id => p_contributor_id,
      p_address_1 => COALESCE(
        v_address->>'address_1',
        v_address->>'line1',
        v_address->>'street',
        v_address->>'street_address'
      ),
      p_address_type => 'mailing',
      p_address_2 => COALESCE(
        v_address->>'address_2',
        v_address->>'line2',
        v_address->>'suite'
      ),
      p_city => v_address->>'city',
      p_state => COALESCE(v_address->>'state', v_address->>'province'),
      p_postal_code => COALESCE(
        v_address->>'zipcode',
        v_address->>'postal_code',
        v_address->>'zip'
      ),
      p_country => COALESCE(NULLIF(v_address->>'country', ''), 'USA'),
      p_is_primary => true,
      p_source => p_source,
      p_notes => 'Added from donation ' || p_donation_id::text
    );
  END IF;

  PERFORM public.add_provider_identity_to_contributor(
    p_contributor_id,
    v_provider,
    v_provider_identity,
    p_source,
    jsonb_build_object('donation_id', p_donation_id)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.resolve_pending_donation(
  p_donation_id uuid,
  p_reviewer_id uuid,
  p_contributor_id uuid,
  p_review_notes text DEFAULT NULL
)
RETURNS public.donations
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_donation public.donations%ROWTYPE;
  v_member_id uuid;
BEGIN
  IF p_reviewer_id IS NULL OR NOT EXISTS (
    SELECT 1
    FROM public.members m
    WHERE m.member_id = p_reviewer_id
      AND m.status = 'active'
      AND m.is_facilitator IS TRUE
      AND m.is_donations_reviewer IS TRUE
  ) THEN
    RAISE EXCEPTION 'An active donations reviewer is required.';
  END IF;

  IF p_contributor_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.contributors c
    WHERE c.contributor_id = p_contributor_id
      AND c.status = 'active'
  ) THEN
    RAISE EXCEPTION 'An active contributor is required.';
  END IF;

  SELECT *
  INTO v_donation
  FROM public.donations d
  WHERE d.donation_id = p_donation_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Donation % was not found.', p_donation_id;
  END IF;

  IF v_donation.provider = 'cash'
    OR v_donation.donor_kind <> 'unresolved'
    OR v_donation.status <> 'pending_review'
  THEN
    RAISE EXCEPTION 'Only an unresolved provider donation can be assigned.';
  END IF;

  SELECT cml.member_id
  INTO v_member_id
  FROM public.contributor_member_links cml
  WHERE cml.contributor_id = p_contributor_id
    AND cml.status = 'active'
  LIMIT 1;

  UPDATE public.donations d
  SET
    contributor_id = p_contributor_id,
    member_id = v_member_id,
    donor_kind = 'identified',
    status = 'verified',
    reviewer_id = p_reviewer_id,
    reviewed_at = now(),
    review_notes = NULLIF(btrim(p_review_notes), '')
  WHERE d.donation_id = p_donation_id
  RETURNING * INTO v_donation;

  PERFORM public.add_donation_payload_to_contributor(
    p_contributor_id,
    p_donation_id,
    v_donation.provider || '_review'
  );

  INSERT INTO public.audit_log (actor, action, entity_type, entity_id, details)
  SELECT
    reviewer.email,
    'donation.contributor_resolved',
    'donation',
    p_donation_id::text,
    jsonb_build_object(
      'contributor_id', p_contributor_id,
      'member_id', v_member_id,
      'reviewer_id', p_reviewer_id,
      'review_notes', NULLIF(btrim(p_review_notes), '')
    )
  FROM public.members reviewer
  WHERE reviewer.member_id = p_reviewer_id;

  RETURN v_donation;
END;
$$;

CREATE OR REPLACE FUNCTION public.resolve_pending_donation_choice(
  p_donation_id uuid,
  p_reviewer_id uuid,
  p_choice text,
  p_review_notes text DEFAULT NULL
)
RETURNS public.donations
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_contributor_id uuid;
  v_kind text;
  v_donation public.donations%ROWTYPE;
BEGIN
  IF p_choice LIKE 'contributor:%' THEN
    v_contributor_id := substring(p_choice FROM 13)::uuid;
  ELSIF p_choice LIKE 'member:%' THEN
    v_contributor_id := public.ensure_member_contributor(substring(p_choice FROM 8)::uuid);
  ELSIF p_choice IN ('__new_individual__', '__new_organization__') THEN
    v_kind := CASE
      WHEN p_choice = '__new_organization__' THEN 'organization'
      ELSE 'individual'
    END;

    SELECT c.contributor_id
    INTO v_contributor_id
    FROM public.create_contributor_from_pending_donation(
      p_donation_id,
      p_reviewer_id,
      v_kind,
      NULL,
      p_review_notes
    ) c;
  ELSE
    RAISE EXCEPTION 'Unsupported contributor resolution choice.';
  END IF;

  IF p_choice IN ('__new_individual__', '__new_organization__') THEN
    SELECT * INTO v_donation
    FROM public.donations d
    WHERE d.donation_id = p_donation_id;

    RETURN v_donation;
  END IF;

  RETURN public.resolve_pending_donation(
    p_donation_id,
    p_reviewer_id,
    v_contributor_id,
    p_review_notes
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.create_contributor_from_pending_donation(
  p_donation_id uuid,
  p_reviewer_id uuid,
  p_contributor_type text DEFAULT 'individual',
  p_organization_name text DEFAULT NULL,
  p_review_notes text DEFAULT NULL
)
RETURNS public.contributors
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_payload jsonb;
  v_first_name text;
  v_last_name text;
  v_email text;
  v_organization_name text;
  v_display_name text;
  v_contributor public.contributors%ROWTYPE;
BEGIN
  IF p_reviewer_id IS NULL OR NOT EXISTS (
    SELECT 1
    FROM public.members m
    WHERE m.member_id = p_reviewer_id
      AND m.status = 'active'
      AND m.is_facilitator IS TRUE
      AND m.is_donations_reviewer IS TRUE
  ) THEN
    RAISE EXCEPTION 'An active donations reviewer is required.';
  END IF;

  IF p_contributor_type NOT IN ('individual', 'organization') THEN
    RAISE EXCEPTION 'Contributor type must be individual or organization.';
  END IF;

  PERFORM 1
  FROM public.donations d
  WHERE d.donation_id = p_donation_id
    AND d.provider <> 'cash'
    AND d.donor_kind = 'unresolved'
    AND d.status = 'pending_review'
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Only an unresolved provider donation can create a contributor.';
  END IF;

  v_payload := COALESCE(public.donation_provider_payload(p_donation_id), '{}'::jsonb);
  v_first_name := NULLIF(btrim(COALESCE(
    v_payload->>'first_name',
    v_payload #>> '{donor,first_name}',
    v_payload #>> '{supporter,first_name}'
  )), '');
  v_last_name := NULLIF(btrim(COALESCE(
    v_payload->>'last_name',
    v_payload #>> '{donor,last_name}',
    v_payload #>> '{supporter,last_name}'
  )), '');
  v_email := NULLIF(lower(btrim(COALESCE(
    v_payload->>'email',
    v_payload #>> '{donor,email}',
    v_payload #>> '{supporter,email}'
  ))), '');
  v_organization_name := NULLIF(btrim(COALESCE(
    p_organization_name,
    v_payload->>'organization_name',
    v_payload->>'company_name',
    v_payload->>'company',
    v_payload->>'business_name',
    v_payload #>> '{donor,company}',
    v_payload #>> '{supporter,company}'
  )), '');

  IF p_contributor_type = 'organization' AND v_organization_name IS NULL THEN
    RAISE EXCEPTION
      'The provider payload has no organization name; enter or correct it before creating an organization contributor.';
  END IF;

  v_display_name := CASE
    WHEN p_contributor_type = 'organization' THEN v_organization_name
    ELSE COALESCE(
      NULLIF(btrim(concat_ws(' ', v_first_name, v_last_name)), ''),
      v_email
    )
  END;

  IF v_display_name IS NULL THEN
    RAISE EXCEPTION 'The provider payload does not contain enough contributor identity.';
  END IF;

  INSERT INTO public.contributors (
    contributor_type,
    display_name,
    first_name,
    last_name,
    organization_name,
    status,
    source,
    notes
  )
  VALUES (
    p_contributor_type,
    v_display_name,
    CASE WHEN p_contributor_type = 'individual' THEN v_first_name END,
    CASE WHEN p_contributor_type = 'individual' THEN v_last_name END,
    CASE WHEN p_contributor_type = 'organization' THEN v_organization_name END,
    'active',
    'givebutter_review',
    'Created from pending donation ' || p_donation_id::text
  )
  RETURNING * INTO v_contributor;

  PERFORM public.resolve_pending_donation(
    p_donation_id,
    p_reviewer_id,
    v_contributor.contributor_id,
    p_review_notes
  );

  INSERT INTO public.audit_log (actor, action, entity_type, entity_id, details)
  SELECT
    reviewer.email,
    'contributor.created_from_donation',
    'contributor',
    v_contributor.contributor_id::text,
    jsonb_build_object(
      'donation_id', p_donation_id,
      'contributor_type', p_contributor_type,
      'reviewer_id', p_reviewer_id
    )
  FROM public.members reviewer
  WHERE reviewer.member_id = p_reviewer_id;

  RETURN v_contributor;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_member_from_pending_donation(
  p_donation_id uuid,
  p_reviewer_id uuid,
  p_review_notes text DEFAULT NULL
)
RETURNS public.members
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_payload jsonb;
  v_contributor public.contributors%ROWTYPE;
  v_member public.members%ROWTYPE;
  v_member_id uuid;
  v_duplicate_blocked boolean;
BEGIN
  SELECT *
  INTO v_contributor
  FROM public.create_contributor_from_pending_donation(
    p_donation_id,
    p_reviewer_id,
    'individual',
    NULL,
    p_review_notes
  );

  v_payload := COALESCE(public.donation_provider_payload(p_donation_id), '{}'::jsonb);

  SELECT created.member_id, created.duplicate_blocked
  INTO v_member_id, v_duplicate_blocked
  FROM public.create_member_from_intake(
    p_first_name => v_contributor.first_name,
    p_last_name => v_contributor.last_name,
    p_email => COALESCE(
      v_payload->>'email',
      v_payload #>> '{donor,email}',
      v_payload #>> '{supporter,email}'
    ),
    p_phone => COALESCE(
      v_payload->>'phone',
      v_payload #>> '{donor,phone}',
      v_payload #>> '{supporter,phone}'
    ),
    p_date_of_birth => NULL,
    p_notes => 'Created from pending donation ' || p_donation_id::text,
    p_is_facilitator => false,
    p_created_by_facilitator_id => p_reviewer_id
  ) created;

  IF COALESCE(v_duplicate_blocked, false) OR v_member_id IS NULL THEN
    RAISE EXCEPTION
      'Member creation was blocked by an existing identity. Resolve the donation to the existing member/contributor instead.';
  END IF;

  PERFORM public.link_contributor_to_member(
    v_contributor.contributor_id,
    v_member_id,
    p_reviewer_id,
    'Member created from pending donation ' || p_donation_id::text
  );

  INSERT INTO public.member_emails (
    member_id,
    email,
    is_primary,
    is_verified,
    source,
    notes
  )
  SELECT
    v_member_id,
    ce.email,
    ce.is_primary,
    ce.is_verified,
    'contributor_promotion',
    'Copied from contributor ' || v_contributor.contributor_id::text
  FROM public.contributor_emails ce
  WHERE ce.contributor_id = v_contributor.contributor_id
    AND ce.status = 'active'
  ON CONFLICT (email_normalized)
  WHERE email_normalized IS NOT NULL
    AND email_normalized <> ''
    AND status = 'active'
  DO NOTHING;

  INSERT INTO public.member_phones (
    member_id,
    phone,
    is_primary,
    is_verified,
    source,
    notes
  )
  SELECT
    v_member_id,
    cp.phone,
    cp.is_primary,
    cp.is_verified,
    'contributor_promotion',
    'Copied from contributor ' || v_contributor.contributor_id::text
  FROM public.contributor_phones cp
  WHERE cp.contributor_id = v_contributor.contributor_id
    AND cp.status = 'active'
    AND NOT EXISTS (
      SELECT 1
      FROM public.member_phones mp
      WHERE mp.member_id = v_member_id
        AND mp.phone_normalized = cp.phone_normalized
        AND mp.status = 'active'
    );

  PERFORM public.upsert_member_address(
    p_member_id => v_member_id,
    p_address_1 => ca.address_1,
    p_address_type => COALESCE(NULLIF(ca.address_type, ''), 'home'),
    p_address_2 => ca.address_2,
    p_city => ca.city,
    p_state => ca.state,
    p_postal_code => ca.postal_code,
    p_country => ca.country,
    p_is_primary => ca.is_primary,
    p_source => 'contributor_promotion',
    p_notes => 'Copied from contributor ' || v_contributor.contributor_id::text
  )
  FROM public.contributor_addresses ca
  WHERE ca.contributor_id = v_contributor.contributor_id
    AND ca.status = 'active'
    AND NULLIF(btrim(ca.address_1), '') IS NOT NULL;

  SELECT * INTO v_member
  FROM public.members m
  WHERE m.member_id = v_member_id;

  RETURN v_member;
END;
$$;

CREATE OR REPLACE FUNCTION public.link_contributor_to_member(
  p_contributor_id uuid,
  p_member_id uuid,
  p_actor_id uuid,
  p_reason text DEFAULT NULL
)
RETURNS public.contributor_member_links
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_link public.contributor_member_links%ROWTYPE;
BEGIN
  IF p_actor_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.members m
    WHERE m.member_id = p_actor_id
      AND m.status = 'active'
      AND m.is_facilitator IS TRUE
      AND m.is_donations_reviewer IS TRUE
  ) THEN
    RAISE EXCEPTION 'An active donations reviewer is required.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.members m
    WHERE m.member_id = p_member_id AND m.status = 'active'
  ) THEN
    RAISE EXCEPTION 'The selected member is not active.';
  END IF;

  INSERT INTO public.contributor_member_links (
    contributor_id,
    member_id,
    status,
    linked_by,
    link_reason
  )
  VALUES (
    p_contributor_id,
    p_member_id,
    'active',
    p_actor_id,
    NULLIF(btrim(p_reason), '')
  )
  RETURNING * INTO v_link;

  UPDATE public.donations d
  SET member_id = p_member_id
  WHERE d.contributor_id = p_contributor_id
    AND d.donor_kind = 'identified'
    AND d.member_id IS NULL;

  INSERT INTO public.audit_log (actor, action, entity_type, entity_id, details)
  SELECT
    actor.email,
    'contributor.member_linked',
    'contributor',
    p_contributor_id::text,
    jsonb_build_object(
      'member_id', p_member_id,
      'actor_id', p_actor_id,
      'reason', NULLIF(btrim(p_reason), '')
    )
  FROM public.members actor
  WHERE actor.member_id = p_actor_id;

  RETURN v_link;
END;
$$;

CREATE OR REPLACE FUNCTION public.unlink_contributor_from_member(
  p_contributor_id uuid,
  p_actor_id uuid,
  p_reason text
)
RETURNS public.contributor_member_links
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_link public.contributor_member_links%ROWTYPE;
BEGIN
  IF p_actor_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.members m
    WHERE m.member_id = p_actor_id
      AND m.status = 'active'
      AND m.is_facilitator IS TRUE
      AND m.is_donations_reviewer IS TRUE
  ) THEN
    RAISE EXCEPTION 'An active donations reviewer is required.';
  END IF;

  IF NULLIF(btrim(p_reason), '') IS NULL THEN
    RAISE EXCEPTION 'A reason is required to end a contributor/member link.';
  END IF;

  UPDATE public.contributor_member_links cml
  SET
    status = 'ended',
    ended_at = now(),
    ended_by = p_actor_id,
    end_reason = btrim(p_reason)
  WHERE cml.contributor_id = p_contributor_id
    AND cml.status = 'active'
  RETURNING * INTO v_link;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Contributor % has no active member link.', p_contributor_id;
  END IF;

  INSERT INTO public.audit_log (actor, action, entity_type, entity_id, details)
  SELECT
    actor.email,
    'contributor.member_unlinked',
    'contributor',
    p_contributor_id::text,
    jsonb_build_object(
      'member_id', v_link.member_id,
      'actor_id', p_actor_id,
      'reason', btrim(p_reason)
    )
  FROM public.members actor
  WHERE actor.member_id = p_actor_id;

  RETURN v_link;
END;
$$;

CREATE OR REPLACE FUNCTION public.record_cash_donation_for_contributor(
  p_contributor_id uuid,
  p_is_anonymous boolean,
  p_amount_cents integer,
  p_donated_at timestamptz,
  p_notes text,
  p_facilitator_id uuid
)
RETURNS public.donations
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_result public.donations%ROWTYPE;
  v_member_id uuid;
BEGIN
  IF p_facilitator_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.members m
    WHERE m.member_id = p_facilitator_id
      AND m.status = 'active'
      AND m.is_facilitator IS TRUE
  ) THEN
    RAISE EXCEPTION 'An active facilitator is required to record a cash donation.';
  END IF;

  IF p_amount_cents IS NULL OR p_amount_cents <= 0 THEN
    RAISE EXCEPTION 'Cash donation amount must be positive.';
  END IF;

  IF COALESCE(p_is_anonymous, false) THEN
    IF p_contributor_id IS NOT NULL THEN
      RAISE EXCEPTION 'Anonymous cash donations cannot reference a contributor.';
    END IF;
  ELSIF p_contributor_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.contributors c
    WHERE c.contributor_id = p_contributor_id
      AND c.status = 'active'
  ) THEN
    RAISE EXCEPTION 'An active contributor is required unless cash is explicitly anonymous.';
  END IF;

  IF p_contributor_id IS NOT NULL THEN
    SELECT cml.member_id INTO v_member_id
    FROM public.contributor_member_links cml
    WHERE cml.contributor_id = p_contributor_id
      AND cml.status = 'active'
    LIMIT 1;
  END IF;

  INSERT INTO public.donations (
    contributor_id,
    member_id,
    donor_kind,
    provider,
    amount_cents,
    currency,
    donated_at,
    notes,
    status,
    facilitator_id
  )
  VALUES (
    CASE WHEN COALESCE(p_is_anonymous, false) THEN NULL ELSE p_contributor_id END,
    CASE WHEN COALESCE(p_is_anonymous, false) THEN NULL ELSE v_member_id END,
    CASE WHEN COALESCE(p_is_anonymous, false) THEN 'anonymous' ELSE 'identified' END,
    'cash',
    p_amount_cents,
    'USD',
    COALESCE(p_donated_at, now()),
    NULLIF(btrim(p_notes), ''),
    'pending_review',
    p_facilitator_id
  )
  RETURNING * INTO v_result;

  RETURN v_result;
END;
$$;

-- Keep the Issue #17 member-based function available during staggered UI
-- deployment. It now creates/uses the member's contributor identity.
CREATE OR REPLACE FUNCTION public.record_cash_donation(
  p_member_id uuid,
  p_is_anonymous boolean,
  p_amount_cents integer,
  p_donated_at timestamptz,
  p_notes text,
  p_facilitator_id uuid
)
RETURNS public.donations
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
BEGIN
  RETURN public.record_cash_donation_for_contributor(
    CASE
      WHEN COALESCE(p_is_anonymous, false) THEN NULL
      ELSE public.ensure_member_contributor(p_member_id)
    END,
    p_is_anonymous,
    p_amount_cents,
    p_donated_at,
    p_notes,
    p_facilitator_id
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.record_cash_donation_identity(
  p_choice text,
  p_is_anonymous boolean,
  p_amount_cents integer,
  p_donated_at timestamptz,
  p_notes text,
  p_facilitator_id uuid
)
RETURNS public.donations
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_contributor_id uuid;
BEGIN
  IF COALESCE(p_is_anonymous, false) OR p_choice = '__anonymous__' THEN
    RETURN public.record_cash_donation_for_contributor(
      NULL, true, p_amount_cents, p_donated_at, p_notes, p_facilitator_id
    );
  ELSIF p_choice LIKE 'contributor:%' THEN
    v_contributor_id := substring(p_choice FROM 13)::uuid;
  ELSIF p_choice LIKE 'member:%' THEN
    v_contributor_id := public.ensure_member_contributor(substring(p_choice FROM 8)::uuid);
  ELSE
    RAISE EXCEPTION 'Select an existing contributor, member, or Anonymous cash donor.';
  END IF;

  RETURN public.record_cash_donation_for_contributor(
    v_contributor_id,
    false,
    p_amount_cents,
    p_donated_at,
    p_notes,
    p_facilitator_id
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.review_pending_donation(
  p_donation_id uuid,
  p_reviewer_id uuid,
  p_new_status text,
  p_review_notes text DEFAULT NULL
)
RETURNS public.donations
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_donation public.donations%ROWTYPE;
BEGIN
  IF p_reviewer_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.members m
    WHERE m.member_id = p_reviewer_id
      AND m.status = 'active'
      AND m.is_facilitator IS TRUE
      AND m.is_donations_reviewer IS TRUE
  ) THEN
    RAISE EXCEPTION 'An active donations reviewer is required.';
  END IF;

  SELECT * INTO v_donation
  FROM public.donations d
  WHERE d.donation_id = p_donation_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Donation % was not found.', p_donation_id;
  END IF;

  IF v_donation.status <> 'pending_review' THEN
    RAISE EXCEPTION 'Donation % is %, not pending_review.', p_donation_id, v_donation.status;
  END IF;

  IF v_donation.provider = 'cash' THEN
    IF v_donation.donor_kind NOT IN ('identified', 'anonymous') THEN
      RAISE EXCEPTION 'Cash donation % has invalid donor identity.', p_donation_id;
    END IF;
    IF v_donation.amount_cents IS NULL OR v_donation.amount_cents <= 0 THEN
      RAISE EXCEPTION 'Cash donation % must have a positive amount.', p_donation_id;
    END IF;
    IF p_new_status IS NULL OR p_new_status NOT IN ('verified', 'rejected') THEN
      RAISE EXCEPTION 'Cash review status must be verified or rejected.';
    END IF;
  ELSE
    IF v_donation.donor_kind <> 'unresolved'
      OR v_donation.contributor_id IS NOT NULL
      OR v_donation.member_id IS NOT NULL
      OR p_new_status IS DISTINCT FROM 'ignored'
    THEN
      RAISE EXCEPTION 'Only unresolved provider donations may be ignored through this action.';
    END IF;
  END IF;

  UPDATE public.donations
  SET
    status = p_new_status,
    reviewer_id = p_reviewer_id,
    reviewed_at = now(),
    review_notes = NULLIF(btrim(p_review_notes), '')
  WHERE donation_id = p_donation_id
  RETURNING * INTO v_donation;

  RETURN v_donation;
END;
$$;

COMMENT ON TABLE public.contributors IS
  'Donation contributor identities independent of membership; may be individuals or organizations.';
COMMENT ON TABLE public.contributor_member_links IS
  'Auditable history connecting an individual contributor to a member without merging either record.';
COMMENT ON COLUMN public.donations.contributor_id IS
  'Identified contributor for the donation. Membership remains optional and is retained in member_id only as a compatibility projection.';
COMMENT ON COLUMN public.donations.donor_kind IS
  'Donation identity state: identified contributor, deliberately anonymous cash, or unresolved provider import.';
COMMENT ON FUNCTION public.ensure_member_contributor(uuid) IS
  'Returns the active contributor linked to a member or creates one with copied active contact data.';
COMMENT ON FUNCTION public.resolve_pending_donation(uuid, uuid, uuid, text) IS
  'Assigns an unresolved provider donation to an existing contributor and records reviewer audit data.';
COMMENT ON FUNCTION public.link_contributor_to_member(uuid, uuid, uuid, text) IS
  'Links an individual contributor to an active member while preserving both records and link history.';
COMMENT ON FUNCTION public.unlink_contributor_from_member(uuid, uuid, text) IS
  'Ends an active contributor/member link without deleting either identity or rewriting donation history.';

COMMIT;

-- Deployment verification: every query below must return zero rows.
SELECT donation_id, member_id, contributor_id, donor_kind, provider
FROM public.donations
WHERE (donor_kind = 'identified' AND contributor_id IS NULL)
   OR (donor_kind IN ('anonymous', 'unresolved') AND contributor_id IS NOT NULL)
   OR (donor_kind IN ('anonymous', 'unresolved') AND member_id IS NOT NULL)
   OR (donor_kind = 'anonymous' AND provider <> 'cash')
   OR (donor_kind = 'unresolved' AND provider = 'cash');

SELECT d.donation_id, d.member_id, d.contributor_id
FROM public.donations d
JOIN public.contributor_member_links cml
  ON cml.contributor_id = d.contributor_id
 AND cml.status = 'active'
WHERE d.member_id IS DISTINCT FROM cml.member_id;

SELECT contributor_id, count(*)
FROM public.contributor_member_links
WHERE status = 'active'
GROUP BY contributor_id
HAVING count(*) > 1;

SELECT member_id, count(*)
FROM public.contributor_member_links
WHERE status = 'active'
GROUP BY member_id
HAVING count(*) > 1;
