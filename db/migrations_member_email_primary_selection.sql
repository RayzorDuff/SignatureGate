-- SignatureGate issue #6
-- Ensure a member has at most one active primary email, provide a safe setter
-- for Appsmith, and keep primary-email inserts/updates from violating the
-- uniqueness rule.

BEGIN;

-- Existing data may contain more than one active primary email per member.
-- Keep one deterministic winner per member before adding the partial unique
-- index: verified primary first, then newest verified timestamp, then newest
-- row creation/update, then UUID as a final stable tie-breaker.
WITH ranked AS (
  SELECT
    member_email_id,
    member_id,
    row_number() OVER (
      PARTITION BY member_id
      ORDER BY
        COALESCE(is_verified, false) DESC,
        verified_at DESC NULLS LAST,
        updated_at DESC NULLS LAST,
        created_at DESC NULLS LAST,
        member_email_id DESC
    ) AS rn
  FROM public.member_emails
  WHERE COALESCE(status, 'active') = 'active'
    AND COALESCE(is_primary, false) = true
)
UPDATE public.member_emails me
SET
  is_primary = false,
  updated_at = now(),
  notes = COALESCE(me.notes, '') || CASE
    WHEN COALESCE(me.notes, '') = '' THEN '' ELSE E'\n'
  END || 'Primary flag cleared by issue #6 one-primary-email migration.'
FROM ranked r
WHERE me.member_email_id = r.member_email_id
  AND r.rn > 1;

-- If a member has active email rows but no active primary after the cleanup,
-- promote the best active row. This keeps primary email fallback predictable.
WITH candidates AS (
  SELECT
    me.member_email_id,
    row_number() OVER (
      PARTITION BY me.member_id
      ORDER BY
        COALESCE(me.is_verified, false) DESC,
        me.verified_at DESC NULLS LAST,
        me.updated_at DESC NULLS LAST,
        me.created_at DESC NULLS LAST,
        me.member_email_id DESC
    ) AS rn
  FROM public.member_emails me
  WHERE COALESCE(me.status, 'active') = 'active'
    AND NOT EXISTS (
      SELECT 1
      FROM public.member_emails p
      WHERE p.member_id = me.member_id
        AND COALESCE(p.status, 'active') = 'active'
        AND COALESCE(p.is_primary, false) = true
    )
)
UPDATE public.member_emails me
SET
  is_primary = true,
  updated_at = now(),
  notes = COALESCE(me.notes, '') || CASE
    WHEN COALESCE(me.notes, '') = '' THEN '' ELSE E'\n'
  END || 'Primary flag set by issue #6 one-primary-email migration.'
FROM candidates c
WHERE me.member_email_id = c.member_email_id
  AND c.rn = 1;

-- Remove prior attempts at this constraint if present. They are recreated below
-- after data has been normalized. The dynamic block is intentionally narrow:
-- it only drops UNIQUE indexes on public.member_emails whose definitions include
-- member_id, is_primary, and the active status predicate.
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT schemaname, indexname
    FROM pg_indexes
    WHERE schemaname = 'public'
      AND tablename = 'member_emails'
      AND indexdef ILIKE 'CREATE UNIQUE INDEX%'
      AND indexdef ILIKE '%member_id%'
      AND indexdef ILIKE '%is_primary%'
      AND indexdef ILIKE '%status%'
  LOOP
    EXECUTE format('DROP INDEX IF EXISTS %I.%I', r.schemaname, r.indexname);
  END LOOP;
END $$;

DROP INDEX IF EXISTS public.uq_member_emails_one_active_primary_per_member;
DROP INDEX IF EXISTS public.member_emails_one_active_primary_idx;
DROP INDEX IF EXISTS public.idx_member_emails_one_primary_active;

CREATE UNIQUE INDEX uq_member_emails_one_active_primary_per_member
ON public.member_emails (member_id)
WHERE COALESCE(status, 'active') = 'active'
  AND is_primary = true;

CREATE OR REPLACE FUNCTION public.member_email_set_primary(
  p_member_email_id uuid,
  p_actor_member_id uuid DEFAULT NULL
)
RETURNS public.member_emails
LANGUAGE plpgsql
AS $$
DECLARE
  v_row public.member_emails;
BEGIN
  SELECT *
  INTO v_row
  FROM public.member_emails
  WHERE member_email_id = p_member_email_id
    AND COALESCE(status, 'active') = 'active';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Active member_email_id % not found', p_member_email_id
      USING ERRCODE = 'no_data_found';
  END IF;

  UPDATE public.member_emails
  SET
    is_primary = false,
    updated_at = now()
  WHERE member_id = v_row.member_id
    AND member_email_id <> p_member_email_id
    AND COALESCE(status, 'active') = 'active'
    AND COALESCE(is_primary, false) = true;

  UPDATE public.member_emails
  SET
    is_primary = true,
    updated_at = now(),
    verified_by = COALESCE(verified_by, p_actor_member_id)
  WHERE member_email_id = p_member_email_id
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

-- Keep inserts/updates safe when Appsmith adds an email with is_primary=true or
-- edits an existing email into primary. The trigger demotes sibling active
-- primary emails before the unique index is checked.
CREATE OR REPLACE FUNCTION public.member_emails_enforce_single_primary_trg()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF COALESCE(NEW.status, 'active') = 'active'
     AND COALESCE(NEW.is_primary, false) = true THEN
    UPDATE public.member_emails
    SET
      is_primary = false,
      updated_at = now()
    WHERE member_id = NEW.member_id
      AND member_email_id <> NEW.member_email_id
      AND COALESCE(status, 'active') = 'active'
      AND COALESCE(is_primary, false) = true;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_member_emails_enforce_single_primary ON public.member_emails;
CREATE TRIGGER trg_member_emails_enforce_single_primary
BEFORE INSERT OR UPDATE OF member_id, status, is_primary
ON public.member_emails
FOR EACH ROW
EXECUTE FUNCTION public.member_emails_enforce_single_primary_trg();

COMMIT;
