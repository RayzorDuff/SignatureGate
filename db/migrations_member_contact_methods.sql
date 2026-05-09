-- Allow multiple emails, phone, or address per member

BEGIN;

CREATE OR REPLACE FUNCTION public.normalize_us_phone(p_phone text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN p_phone IS NULL THEN NULL
    WHEN length(regexp_replace(p_phone, '\D', '', 'g')) = 11
      AND left(regexp_replace(p_phone, '\D', '', 'g'), 1) = '1'
      THEN right(regexp_replace(p_phone, '\D', '', 'g'), 10)
    ELSE regexp_replace(p_phone, '\D', '', 'g')
  END;
$$;

CREATE TABLE IF NOT EXISTS public.member_emails (
  member_email_id uuid PRIMARY KEY DEFAULT public.uuid_generate_v4(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  member_id uuid NOT NULL REFERENCES public.members(member_id) ON DELETE CASCADE,
  email text NOT NULL,
  email_normalized text GENERATED ALWAYS AS (lower(btrim(email))) STORED,
  is_primary boolean NOT NULL DEFAULT false,
  is_verified boolean NOT NULL DEFAULT false,
  source text,
  notes text,
  UNIQUE (email_normalized)
);

CREATE TABLE IF NOT EXISTS public.member_phones (
  member_phone_id uuid PRIMARY KEY DEFAULT public.uuid_generate_v4(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  member_id uuid NOT NULL REFERENCES public.members(member_id) ON DELETE CASCADE,
  phone text NOT NULL,
  phone_normalized text GENERATED ALWAYS AS (regexp_replace(coalesce(phone, ''), '\D', '', 'g')) STORED,
  is_primary boolean NOT NULL DEFAULT false,
  is_verified boolean NOT NULL DEFAULT false,
  source text,
  notes text,
  UNIQUE (phone_normalized)
);

CREATE TABLE IF NOT EXISTS public.member_addresses (
  member_address_id uuid PRIMARY KEY DEFAULT public.uuid_generate_v4(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  member_id uuid NOT NULL REFERENCES public.members(member_id) ON DELETE CASCADE,
  address_type text NOT NULL DEFAULT 'home',
  address_1 text,
  address_2 text,
  city text,
  state text,
  postal_code text,
  country text DEFAULT 'USA',
  is_primary boolean NOT NULL DEFAULT false,
  source text,
  notes text
);

ALTER TABLE public.member_emails
  ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'active',
  ADD COLUMN IF NOT EXISTS archived_at timestamptz,
  ADD COLUMN IF NOT EXISTS archived_by uuid REFERENCES public.members(member_id),
  ADD COLUMN IF NOT EXISTS archive_reason text,
  ADD COLUMN IF NOT EXISTS verified_at timestamptz,
  ADD COLUMN IF NOT EXISTS verified_by uuid REFERENCES public.members(member_id),
  ADD COLUMN IF NOT EXISTS verification_source text,
  ADD COLUMN IF NOT EXISTS verification_notes text;

ALTER TABLE public.member_phones
  DROP COLUMN IF EXISTS phone_normalized;

ALTER TABLE public.member_phones
  ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'active',
  ADD COLUMN IF NOT EXISTS archived_at timestamptz,
  ADD COLUMN IF NOT EXISTS archived_by uuid REFERENCES public.members(member_id),
  ADD COLUMN IF NOT EXISTS archive_reason text,
  ADD COLUMN phone_normalized text
  GENERATED ALWAYS AS (public.normalize_us_phone(phone)) STORED;

ALTER TABLE public.member_addresses
  ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'active',
  ADD COLUMN IF NOT EXISTS archived_at timestamptz,
  ADD COLUMN IF NOT EXISTS archived_by uuid REFERENCES public.members(member_id),
  ADD COLUMN IF NOT EXISTS archive_reason text;

ALTER TABLE public.member_agreements
  ADD COLUMN IF NOT EXISTS member_email_id uuid REFERENCES public.member_emails(member_email_id);

WITH ranked AS (
  SELECT
    member_phone_id,
    member_id,
    phone,
    phone_normalized,
    is_primary,
    created_at,
    row_number() OVER (
      PARTITION BY phone_normalized
      ORDER BY
        is_primary DESC,
        created_at ASC,
        member_phone_id ASC
    ) AS rn
  FROM public.member_phones
  WHERE status = 'active'
    AND phone_normalized IS NOT NULL
    AND phone_normalized <> ''
)
UPDATE public.member_phones mp
SET
  status = 'archived',
  archived_at = now(),
  archive_reason = 'Archived duplicate phone during phone normalization migration',
  updated_at = now()
FROM ranked r
WHERE mp.member_phone_id = r.member_phone_id
  AND r.rn > 1;

CREATE UNIQUE INDEX IF NOT EXISTS uq_member_phones_phone_normalized
  ON public.member_phones(phone_normalized)
  WHERE phone_normalized IS NOT NULL
    AND phone_normalized <> ''
    AND status = 'active';

CREATE INDEX IF NOT EXISTS idx_member_emails_member_id
  ON public.member_emails(member_id);

CREATE INDEX IF NOT EXISTS idx_member_phones_member_id
  ON public.member_phones(member_id);

CREATE INDEX IF NOT EXISTS idx_member_addresses_member_id
  ON public.member_addresses(member_id);

CREATE INDEX IF NOT EXISTS idx_member_addresses_zip
  ON public.member_addresses(postal_code);

DROP TRIGGER IF EXISTS trg_member_emails_updated_at ON public.member_emails;
CREATE TRIGGER trg_member_emails_updated_at
BEFORE UPDATE ON public.member_emails
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_member_phones_updated_at ON public.member_phones;
CREATE TRIGGER trg_member_phones_updated_at
BEFORE UPDATE ON public.member_phones
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_member_addresses_updated_at ON public.member_addresses;
CREATE TRIGGER trg_member_addresses_updated_at
BEFORE UPDATE ON public.member_addresses
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Backfill from existing members.
INSERT INTO public.member_emails (member_id, email, is_primary, source)
SELECT member_id, email, true, 'members.email'
FROM public.members
WHERE email IS NOT NULL
  AND btrim(email) <> ''
ON CONFLICT (email_normalized)
WHERE email_normalized IS NOT NULL
  AND email_normalized <> ''
  AND status = 'active'
DO NOTHING;

INSERT INTO public.member_phones (member_id, phone, is_primary, source)
SELECT member_id, phone, true, 'members.phone'
FROM public.members
WHERE phone IS NOT NULL
  AND btrim(phone) <> ''
ON CONFLICT (phone_normalized)
WHERE phone_normalized IS NOT NULL
  AND phone_normalized <> ''
  AND status = 'active'
DO NOTHING;

COMMIT;
