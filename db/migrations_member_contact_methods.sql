-- Allow multiple emails, phone, or address per member

BEGIN;

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
  ADD COLUMN IF NOT EXISTS archive_reason text;

ALTER TABLE public.member_phones
  ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'active',
  ADD COLUMN IF NOT EXISTS archived_at timestamptz,
  ADD COLUMN IF NOT EXISTS archived_by uuid REFERENCES public.members(member_id),
  ADD COLUMN IF NOT EXISTS archive_reason text;

ALTER TABLE public.member_addresses
  ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'active',
  ADD COLUMN IF NOT EXISTS archived_at timestamptz,
  ADD COLUMN IF NOT EXISTS archived_by uuid REFERENCES public.members(member_id),
  ADD COLUMN IF NOT EXISTS archive_reason text;

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
WHERE email IS NOT NULL AND btrim(email) <> ''
ON CONFLICT (email_normalized) DO NOTHING;

INSERT INTO public.member_phones (member_id, phone, is_primary, source)
SELECT member_id, phone, true, 'members.phone'
FROM public.members
WHERE phone IS NOT NULL AND btrim(phone) <> ''
ON CONFLICT (phone_normalized) DO NOTHING;

COMMIT;
