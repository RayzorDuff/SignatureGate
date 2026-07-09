-- SignatureGate v1.0.4: member identity/contact hardening.
--
-- Addresses #10 and #14:
-- - archive active contact rows that belong to inactive members so email/phone
--   identifiers can be reassigned intentionally;
-- - replace global email uniqueness with active-email uniqueness;
-- - stop enforcing globally unique phone numbers so shared/legacy phones can be
--   warnings instead of hard identity conflicts;
-- - add normalized address fingerprints and prevent duplicate active addresses
--   for the same member while still allowing different members at the same
--   household address.

BEGIN;

CREATE OR REPLACE FUNCTION public.member_contact_normalize_text(p_text text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT NULLIF(
    btrim(
      regexp_replace(
        regexp_replace(lower(COALESCE(p_text, '')), '[^a-z0-9]+', ' ', 'g'),
        '\s+',
        ' ',
        'g'
      )
    ),
    ''
  );
$$;

CREATE OR REPLACE FUNCTION public.member_contact_normalize_postal_code(p_text text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT NULLIF(upper(regexp_replace(COALESCE(p_text, ''), '[^a-z0-9]+', '', 'gi')), '');
$$;

CREATE OR REPLACE FUNCTION public.member_address_fingerprint(
  p_address_1 text,
  p_address_2 text,
  p_city text,
  p_state text,
  p_postal_code text,
  p_country text
)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT NULLIF(
    concat_ws('|',
      COALESCE(public.member_contact_normalize_text(p_address_1), ''),
      COALESCE(public.member_contact_normalize_text(p_address_2), ''),
      COALESCE(public.member_contact_normalize_text(p_city), ''),
      COALESCE(public.member_contact_normalize_text(p_state), ''),
      COALESCE(public.member_contact_normalize_postal_code(p_postal_code), ''),
      COALESCE(public.member_contact_normalize_text(COALESCE(NULLIF(p_country, ''), 'USA')), '')
    ),
    '|||||'
  );
$$;

ALTER TABLE public.member_addresses
  ADD COLUMN IF NOT EXISTS address_fingerprint text
  GENERATED ALWAYS AS (
    public.member_address_fingerprint(address_1, address_2, city, state, postal_code, country)
  ) STORED;

-- Contact rows attached to inactive/archived members should not reserve those
-- email addresses or phone numbers forever. Keep history, but archive the
-- contact-method row so the value can be used on the active person.
UPDATE public.member_emails me
SET
  status = 'archived',
  archived_at = COALESCE(me.archived_at, now()),
  archive_reason = COALESCE(me.archive_reason, 'Archived because owning member is not active'),
  updated_at = now()
FROM public.members m
WHERE m.member_id = me.member_id
  AND COALESCE(m.status, 'active') <> 'active'
  AND COALESCE(me.status, 'active') = 'active';

UPDATE public.member_phones mp
SET
  status = 'archived',
  archived_at = COALESCE(mp.archived_at, now()),
  archive_reason = COALESCE(mp.archive_reason, 'Archived because owning member is not active'),
  updated_at = now()
FROM public.members m
WHERE m.member_id = mp.member_id
  AND COALESCE(m.status, 'active') <> 'active'
  AND COALESCE(mp.status, 'active') = 'active';

UPDATE public.member_addresses ma
SET
  status = 'archived',
  archived_at = COALESCE(ma.archived_at, now()),
  archive_reason = COALESCE(ma.archive_reason, 'Archived because owning member is not active'),
  updated_at = now()
FROM public.members m
WHERE m.member_id = ma.member_id
  AND COALESCE(m.status, 'active') <> 'active'
  AND COALESCE(ma.status, 'active') = 'active';

-- Before replacing broad unique constraints, collapse duplicate active emails
-- deterministically. This should be rare; the notes preserve what happened.
WITH ranked AS (
  SELECT
    me.member_email_id,
    row_number() OVER (
      PARTITION BY me.email_normalized
      ORDER BY
        COALESCE(me.is_primary, false) DESC,
        COALESCE(me.is_verified, false) DESC,
        me.verified_at DESC NULLS LAST,
        me.updated_at DESC NULLS LAST,
        me.created_at ASC,
        me.member_email_id ASC
    ) AS rn
  FROM public.member_emails me
  JOIN public.members m ON m.member_id = me.member_id
  WHERE me.email_normalized IS NOT NULL
    AND me.email_normalized <> ''
    AND COALESCE(me.status, 'active') = 'active'
    AND COALESCE(m.status, 'active') = 'active'
)
UPDATE public.member_emails me
SET
  status = 'archived',
  is_primary = false,
  archived_at = COALESCE(me.archived_at, now()),
  archive_reason = COALESCE(me.archive_reason, 'Archived duplicate active email during v1.0.4 identity hardening'),
  updated_at = now(),
  notes = COALESCE(me.notes, '') || CASE WHEN COALESCE(me.notes, '') = '' THEN '' ELSE E'\n' END ||
          'Archived duplicate active email during v1.0.4 identity hardening.'
FROM ranked r
WHERE me.member_email_id = r.member_email_id
  AND r.rn > 1;

-- A member should not need two active copies of the same normalized phone.
-- Shared phones across different members are allowed after this migration.
WITH ranked AS (
  SELECT
    mp.member_phone_id,
    row_number() OVER (
      PARTITION BY mp.member_id, mp.phone_normalized
      ORDER BY
        COALESCE(mp.is_primary, false) DESC,
        COALESCE(mp.is_verified, false) DESC,
        mp.updated_at DESC NULLS LAST,
        mp.created_at ASC,
        mp.member_phone_id ASC
    ) AS rn
  FROM public.member_phones mp
  JOIN public.members m ON m.member_id = mp.member_id
  WHERE mp.phone_normalized IS NOT NULL
    AND mp.phone_normalized <> ''
    AND COALESCE(mp.status, 'active') = 'active'
    AND COALESCE(m.status, 'active') = 'active'
)
UPDATE public.member_phones mp
SET
  status = 'archived',
  is_primary = false,
  archived_at = COALESCE(mp.archived_at, now()),
  archive_reason = COALESCE(mp.archive_reason, 'Archived duplicate phone for same member during v1.0.4 identity hardening'),
  updated_at = now(),
  notes = COALESCE(mp.notes, '') || CASE WHEN COALESCE(mp.notes, '') = '' THEN '' ELSE E'\n' END ||
          'Archived duplicate phone for same member during v1.0.4 identity hardening.'
FROM ranked r
WHERE mp.member_phone_id = r.member_phone_id
  AND r.rn > 1;

-- Collapse duplicate active addresses for the same member/address type/fingerprint.
WITH ranked AS (
  SELECT
    ma.member_address_id,
    row_number() OVER (
      PARTITION BY ma.member_id, COALESCE(ma.address_type, 'home'), ma.address_fingerprint
      ORDER BY
        COALESCE(ma.is_primary, false) DESC,
        ma.updated_at DESC NULLS LAST,
        ma.created_at ASC,
        ma.member_address_id ASC
    ) AS rn
  FROM public.member_addresses ma
  JOIN public.members m ON m.member_id = ma.member_id
  WHERE ma.address_fingerprint IS NOT NULL
    AND ma.address_fingerprint <> ''
    AND COALESCE(ma.status, 'active') = 'active'
    AND COALESCE(m.status, 'active') = 'active'
)
UPDATE public.member_addresses ma
SET
  status = 'archived',
  is_primary = false,
  archived_at = COALESCE(ma.archived_at, now()),
  archive_reason = COALESCE(ma.archive_reason, 'Archived duplicate active address during v1.0.4 identity hardening'),
  updated_at = now(),
  notes = COALESCE(ma.notes, '') || CASE WHEN COALESCE(ma.notes, '') = '' THEN '' ELSE E'\n' END ||
          'Archived duplicate active address during v1.0.4 identity hardening.'
FROM ranked r
WHERE ma.member_address_id = r.member_address_id
  AND r.rn > 1;

-- Remove old global unique constraints/indexes that prevent reusing contacts
-- once the owning member/contact row has been archived.
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT c.conname
    FROM pg_constraint c
    JOIN pg_class t ON t.oid = c.conrelid
    JOIN pg_namespace n ON n.oid = t.relnamespace
    WHERE n.nspname = 'public'
      AND t.relname = 'member_emails'
      AND c.contype = 'u'
      AND pg_get_constraintdef(c.oid) ILIKE '%email_normalized%'
  LOOP
    EXECUTE format('ALTER TABLE public.member_emails DROP CONSTRAINT %I', r.conname);
  END LOOP;

  FOR r IN
    SELECT indexname
    FROM pg_indexes
    WHERE schemaname = 'public'
      AND tablename = 'member_emails'
      AND indexdef ILIKE 'CREATE UNIQUE INDEX%'
      AND indexdef ILIKE '%email_normalized%'
  LOOP
    EXECUTE format('DROP INDEX IF EXISTS public.%I', r.indexname);
  END LOOP;

  FOR r IN
    SELECT c.conname
    FROM pg_constraint c
    JOIN pg_class t ON t.oid = c.conrelid
    JOIN pg_namespace n ON n.oid = t.relnamespace
    WHERE n.nspname = 'public'
      AND t.relname = 'member_phones'
      AND c.contype = 'u'
      AND pg_get_constraintdef(c.oid) ILIKE '%phone_normalized%'
  LOOP
    EXECUTE format('ALTER TABLE public.member_phones DROP CONSTRAINT %I', r.conname);
  END LOOP;

  FOR r IN
    SELECT indexname
    FROM pg_indexes
    WHERE schemaname = 'public'
      AND tablename = 'member_phones'
      AND indexdef ILIKE 'CREATE UNIQUE INDEX%'
      AND indexdef ILIKE '%phone_normalized%'
  LOOP
    EXECUTE format('DROP INDEX IF EXISTS public.%I', r.indexname);
  END LOOP;
END $$;

DROP INDEX IF EXISTS public.uq_member_emails_email_normalized_active;
CREATE UNIQUE INDEX uq_member_emails_email_normalized_active
  ON public.member_emails (email_normalized)
  WHERE email_normalized IS NOT NULL
    AND email_normalized <> ''
    AND status = 'active';

CREATE INDEX IF NOT EXISTS idx_member_phones_phone_normalized_active
  ON public.member_phones (phone_normalized)
  WHERE phone_normalized IS NOT NULL
    AND phone_normalized <> ''
    AND status = 'active';

DROP INDEX IF EXISTS public.uq_member_addresses_active_fingerprint_per_member;
CREATE UNIQUE INDEX uq_member_addresses_active_fingerprint_per_member
  ON public.member_addresses (member_id, address_type, address_fingerprint)
  WHERE address_fingerprint IS NOT NULL
    AND address_fingerprint <> ''
    AND status = 'active';

CREATE INDEX IF NOT EXISTS idx_member_addresses_fingerprint_active
  ON public.member_addresses (address_fingerprint)
  WHERE address_fingerprint IS NOT NULL
    AND address_fingerprint <> ''
    AND status = 'active';

COMMIT;
