-- SignatureGate v1.1.0: strengthen member-address identity and upserts.
--
-- Follow-up for Issue #10. The v1.0.4 fingerprint includes address type, city,
-- and state. That allows a second active row when provider data changes only
-- those attributes (for example Colorado vs CO, or Fort vs Fort Collins).
--
-- This migration adds a stronger physical-address identity key based on:
--   normalized address line 1 + normalized unit + postal code + country
-- and centralizes every Appsmith/n8n address write in upsert_member_address().

\set ON_ERROR_STOP on

BEGIN;

CREATE OR REPLACE FUNCTION public.member_address_normalize_street(p_text text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  WITH normalized AS (
    SELECT COALESCE(public.member_contact_normalize_text(p_text), '') AS value
  )
  SELECT NULLIF(
    btrim(
      regexp_replace(
        regexp_replace(
          regexp_replace(
            regexp_replace(
              regexp_replace(
                regexp_replace(
                  regexp_replace(
                    regexp_replace(
                      regexp_replace(
                        regexp_replace(
                          regexp_replace(
                            regexp_replace(
                              regexp_replace(
                                regexp_replace(
                                  regexp_replace(
                                    regexp_replace(value, '(^| )north( |$)', '\1n\2', 'g'),
                                    '(^| )south( |$)', '\1s\2', 'g'
                                  ),
                                  '(^| )east( |$)', '\1e\2', 'g'
                                ),
                                '(^| )west( |$)', '\1w\2', 'g'
                              ),
                              '(^| )street( |$)', '\1st\2', 'g'
                            ),
                            '(^| )avenue( |$)', '\1ave\2', 'g'
                          ),
                          '(^| )road( |$)', '\1rd\2', 'g'
                        ),
                        '(^| )drive( |$)', '\1dr\2', 'g'
                      ),
                      '(^| )court( |$)', '\1ct\2', 'g'
                    ),
                    '(^| )lane( |$)', '\1ln\2', 'g'
                  ),
                  '(^| )boulevard( |$)', '\1blvd\2', 'g'
                ),
                '(^| )parkway( |$)', '\1pkwy\2', 'g'
              ),
              '(^| )place( |$)', '\1pl\2', 'g'
            ),
            '(^| )terrace( |$)', '\1ter\2', 'g'
          ),
          '(^| )trail( |$)', '\1trl\2', 'g'
        ),
        '(^| )highway( |$)', '\1hwy\2', 'g'
      )
    ),
    ''
  )
  FROM normalized;
$$;

CREATE OR REPLACE FUNCTION public.member_address_normalize_unit(p_text text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  WITH normalized AS (
    SELECT COALESCE(public.member_contact_normalize_text(p_text), '') AS value
  )
  SELECT NULLIF(
    regexp_replace(
      value,
      '^(apartment|apt|unit|suite|ste) ',
      '',
      'g'
    ),
    ''
  )
  FROM normalized;
$$;

CREATE OR REPLACE FUNCTION public.member_address_normalize_country(p_text text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE COALESCE(
    public.member_contact_normalize_text(NULLIF(p_text, '')),
    'usa'
  )
    WHEN 'us' THEN 'us'
    WHEN 'usa' THEN 'us'
    WHEN 'united states' THEN 'us'
    WHEN 'united states of america' THEN 'us'
    WHEN 'ca' THEN 'ca'
    WHEN 'canada' THEN 'ca'
    ELSE COALESCE(
      public.member_contact_normalize_text(NULLIF(p_text, '')),
      'us'
    )
  END;
$$;

CREATE OR REPLACE FUNCTION public.member_address_identity_postal(
  p_postal_code text,
  p_country text
)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  WITH normalized AS (
    SELECT
      public.member_contact_normalize_postal_code(p_postal_code) AS postal,
      public.member_address_normalize_country(p_country) AS country
  )
  SELECT CASE
    WHEN postal IS NULL THEN NULL
    WHEN country = 'us' AND postal ~ '^[0-9]{5}([0-9]{4})?$'
      THEN left(postal, 5)
    ELSE postal
  END
  FROM normalized;
$$;

CREATE OR REPLACE FUNCTION public.member_address_identity_key(
  p_address_1 text,
  p_address_2 text,
  p_postal_code text,
  p_country text
)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  WITH parts AS (
    SELECT
      public.member_address_normalize_street(p_address_1) AS address_1,
      public.member_address_normalize_unit(p_address_2) AS address_2,
      public.member_address_identity_postal(
        p_postal_code,
        p_country
      ) AS postal_code,
      public.member_address_normalize_country(p_country) AS country
  )
  SELECT CASE
    WHEN address_1 IS NULL OR postal_code IS NULL THEN NULL
    ELSE concat_ws(
      '|',
      address_1,
      COALESCE(address_2, ''),
      postal_code,
      country
    )
  END
  FROM parts;
$$;

DO $$
BEGIN
    IF public.member_address_identity_key(
        '215 E Oak St.', 'Apt. 1', '80524', 'USA'
    ) IS DISTINCT FROM public.member_address_identity_key(
        '215 East Oak Street', 'Unit 1', '80524-1234', 'United States'
    ) THEN
        RAISE EXCEPTION 'member_address_identity_key failed the equivalent-address self-check';
    END IF;

    IF public.member_address_identity_key(
        '215 E Oak St.', 'Apt. 1', '80524', 'USA'
    ) IS NOT DISTINCT FROM public.member_address_identity_key(
        '215 E Oak St.', 'Apt. 2', '80524', 'USA'
    ) THEN
        RAISE EXCEPTION 'member_address_identity_key failed the distinct-unit self-check';
    END IF;

    IF public.member_address_identity_key(
        '215 E Oak St.', 'Apt. 1', NULL, 'USA'
    ) IS NOT NULL THEN
        RAISE EXCEPTION 'member_address_identity_key must be NULL without a postal code';
    END IF;
END;
$$;

ALTER TABLE public.member_addresses
  ADD COLUMN IF NOT EXISTS address_identity_key text
  GENERATED ALWAYS AS (
    public.member_address_identity_key(
      address_1,
      address_2,
      postal_code,
      country
    )
  ) STORED;

-- Archive any remaining active rows that map to the same physical address.
-- Prefer primary rows, then manual rows, then the oldest surviving record.
WITH ranked AS (
  SELECT
    ma.member_address_id,
    row_number() OVER (
      PARTITION BY ma.member_id, ma.address_identity_key
      ORDER BY
        COALESCE(ma.is_primary, false) DESC,
        CASE WHEN ma.source = 'manual' THEN 0 ELSE 1 END,
        ma.created_at ASC,
        ma.member_address_id ASC
    ) AS rn
  FROM public.member_addresses ma
  WHERE ma.address_identity_key IS NOT NULL
    AND ma.address_identity_key <> ''
    AND COALESCE(ma.status, 'active') = 'active'
)
UPDATE public.member_addresses ma
SET
  status = 'archived',
  is_primary = false,
  archived_at = COALESCE(ma.archived_at, now()),
  archive_reason = COALESCE(
    ma.archive_reason,
    'Archived duplicate physical address during v1.1.0 identity hardening'
  ),
  notes = CASE
    WHEN position(
      'Archived duplicate physical address during v1.1.0 identity hardening.'
      IN COALESCE(ma.notes, '')
    ) > 0 THEN ma.notes
    ELSE
      COALESCE(ma.notes, '') ||
      CASE WHEN COALESCE(ma.notes, '') = '' THEN '' ELSE E'\n' END ||
      'Archived duplicate physical address during v1.1.0 identity hardening.'
  END,
  updated_at = now()
FROM ranked r
WHERE ma.member_address_id = r.member_address_id
  AND r.rn > 1;

DROP INDEX IF EXISTS public.uq_member_addresses_active_identity_per_member;
CREATE UNIQUE INDEX uq_member_addresses_active_identity_per_member
  ON public.member_addresses (member_id, address_identity_key)
  WHERE address_identity_key IS NOT NULL
    AND address_identity_key <> ''
    AND status = 'active';

CREATE INDEX IF NOT EXISTS idx_member_addresses_identity_active
  ON public.member_addresses (address_identity_key)
  WHERE address_identity_key IS NOT NULL
    AND address_identity_key <> ''
    AND status = 'active';

CREATE OR REPLACE FUNCTION public.upsert_member_address(
  p_member_id uuid,
  p_address_1 text,
  p_address_type text DEFAULT 'home',
  p_address_2 text DEFAULT NULL,
  p_city text DEFAULT NULL,
  p_state text DEFAULT NULL,
  p_postal_code text DEFAULT NULL,
  p_country text DEFAULT 'USA',
  p_is_primary boolean DEFAULT false,
  p_source text DEFAULT NULL,
  p_notes text DEFAULT NULL
)
RETURNS public.member_addresses
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_address_1 text := NULLIF(btrim(p_address_1), '');
  v_address_2 text := NULLIF(btrim(p_address_2), '');
  v_city text := NULLIF(btrim(p_city), '');
  v_state text := NULLIF(btrim(p_state), '');
  v_postal_code text := NULLIF(btrim(p_postal_code), '');
  v_country text := COALESCE(NULLIF(btrim(p_country), ''), 'USA');
  v_address_type text := COALESCE(NULLIF(btrim(p_address_type), ''), 'home');
  v_identity_key text;
  v_result public.member_addresses%ROWTYPE;
BEGIN
  IF p_member_id IS NULL THEN
    RAISE EXCEPTION 'member_id is required to save an address.';
  END IF;

  IF v_address_1 IS NULL THEN
    RAISE EXCEPTION 'address_1 is required to save an address.';
  END IF;

  v_identity_key := public.member_address_identity_key(
    v_address_1,
    v_address_2,
    v_postal_code,
    v_country
  );

  IF v_identity_key IS NOT NULL THEN
    INSERT INTO public.member_addresses AS ma (
      member_id,
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
      p_member_id,
      v_address_type,
      v_address_1,
      v_address_2,
      v_city,
      v_state,
      v_postal_code,
      v_country,
      COALESCE(p_is_primary, false),
      NULLIF(btrim(p_source), ''),
      NULLIF(btrim(p_notes), '')
    )
    ON CONFLICT (member_id, address_identity_key)
    WHERE address_identity_key IS NOT NULL
      AND address_identity_key <> ''
      AND status = 'active'
    DO UPDATE SET
      address_1 = CASE
        WHEN COALESCE(ma.source, '') LIKE 'givebutter%'
          AND length(COALESCE(public.member_contact_normalize_text(EXCLUDED.address_1), ''))
              > length(COALESCE(public.member_contact_normalize_text(ma.address_1), ''))
          THEN EXCLUDED.address_1
        ELSE ma.address_1
      END,
      address_2 = CASE
        WHEN COALESCE(ma.source, '') LIKE 'givebutter%'
          AND length(COALESCE(public.member_contact_normalize_text(EXCLUDED.address_2), ''))
              > length(COALESCE(public.member_contact_normalize_text(ma.address_2), ''))
          THEN EXCLUDED.address_2
        ELSE ma.address_2
      END,
      city = CASE
        WHEN ma.city IS NULL THEN EXCLUDED.city
        WHEN COALESCE(ma.source, '') LIKE 'givebutter%'
          AND length(COALESCE(public.member_contact_normalize_text(EXCLUDED.city), ''))
              > length(COALESCE(public.member_contact_normalize_text(ma.city), ''))
          THEN EXCLUDED.city
        ELSE ma.city
      END,
      state = COALESCE(ma.state, EXCLUDED.state),
      postal_code = COALESCE(ma.postal_code, EXCLUDED.postal_code),
      country = COALESCE(ma.country, EXCLUDED.country),
      is_primary = ma.is_primary OR EXCLUDED.is_primary,
      notes = COALESCE(ma.notes, EXCLUDED.notes),
      updated_at = now()
    RETURNING ma.* INTO v_result;
  ELSE
    -- If the postal code is unavailable, retain the stricter v1.0.4 behavior
    -- instead of merging addresses on weak identity evidence.
    INSERT INTO public.member_addresses AS ma (
      member_id,
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
      p_member_id,
      v_address_type,
      v_address_1,
      v_address_2,
      v_city,
      v_state,
      v_postal_code,
      v_country,
      COALESCE(p_is_primary, false),
      NULLIF(btrim(p_source), ''),
      NULLIF(btrim(p_notes), '')
    )
    ON CONFLICT (member_id, address_type, address_fingerprint)
    WHERE address_fingerprint IS NOT NULL
      AND address_fingerprint <> ''
      AND status = 'active'
    DO UPDATE SET
      is_primary = ma.is_primary OR EXCLUDED.is_primary,
      notes = COALESCE(ma.notes, EXCLUDED.notes),
      updated_at = now()
    RETURNING ma.* INTO v_result;
  END IF;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.member_address_identity_key(
  text,
  text,
  text,
  text
) IS
  'Returns a stable physical-address identity key using normalized street, unit, postal code, and country; city, state, and address type are intentionally excluded.';

COMMENT ON FUNCTION public.upsert_member_address(
  uuid,
  text,
  text,
  text,
  text,
  text,
  text,
  text,
  boolean,
  text,
  text
) IS
  'Creates or updates one active physical address per member identity key, preserving manual address text while allowing provider-managed rows to gain more complete address components.';

COMMIT;
