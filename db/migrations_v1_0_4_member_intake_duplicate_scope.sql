-- Member Intake duplicate hardening and concurrency guard.
--
-- The Appsmith intake flow performs a global duplicate lookup even when the
-- current facilitator cannot browse the matching member. This migration adds
-- a serialized database creation function and an active-email uniqueness guard
-- so the final insert cannot race the client-side duplicate check.

BEGIN;

DO $$
DECLARE
  duplicate_summary text;
BEGIN
  SELECT string_agg(format('%s (%s active members)', email_normalized, duplicate_count), ', ')
  INTO duplicate_summary
  FROM (
    SELECT
      lower(btrim(email)) AS email_normalized,
      count(*) AS duplicate_count
    FROM public.members
    WHERE status = 'active'
      AND email IS NOT NULL
      AND btrim(email) <> ''
    GROUP BY lower(btrim(email))
    HAVING count(*) > 1
    ORDER BY lower(btrim(email))
    LIMIT 10
  ) duplicates;

  IF duplicate_summary IS NOT NULL THEN
    RAISE EXCEPTION
      'Cannot add active-member email uniqueness until duplicate active members.email values are resolved: %',
      duplicate_summary;
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_members_active_email_normalized
  ON public.members (lower(btrim(email)))
  WHERE status = 'active'
    AND email IS NOT NULL
    AND btrim(email) <> '';

COMMENT ON INDEX public.uq_members_active_email_normalized IS
  'Prevents active members from sharing the same normalized compatibility email cache.';

CREATE OR REPLACE FUNCTION public.create_member_from_intake(
  p_first_name text,
  p_last_name text,
  p_email text DEFAULT NULL,
  p_phone text DEFAULT NULL,
  p_date_of_birth date DEFAULT NULL,
  p_notes text DEFAULT NULL,
  p_is_facilitator boolean DEFAULT false,
  p_created_by_facilitator_id uuid DEFAULT NULL
)
RETURNS TABLE (
  member_id uuid,
  duplicate_blocked boolean
)
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_first_name text := NULLIF(btrim(p_first_name), '');
  v_last_name text := NULLIF(btrim(p_last_name), '');
  v_email text := NULLIF(lower(btrim(p_email)), '');
  v_phone text := NULLIF(btrim(p_phone), '');
  v_member_id uuid;
BEGIN
  IF v_first_name IS NULL OR v_last_name IS NULL THEN
    RAISE EXCEPTION 'First and last name are required.';
  END IF;

  -- Intake volume is low. Serializing the short duplicate-check/insert section
  -- closes the race for both email and exact name+date-of-birth hard matches
  -- without imposing a uniqueness rule that would reject legitimate twins.
  LOCK TABLE public.members IN SHARE ROW EXCLUSIVE MODE;

  IF (
    v_email IS NOT NULL
    AND (
      EXISTS (
        SELECT 1
        FROM public.members m
        WHERE m.status = 'active'
          AND lower(btrim(m.email)) = v_email
      )
      OR EXISTS (
        SELECT 1
        FROM public.member_emails me
        JOIN public.members m ON m.member_id = me.member_id
        WHERE me.email_normalized = v_email
          AND COALESCE(me.status, 'active') = 'active'
          AND m.status = 'active'
      )
    )
  ) OR (
    p_date_of_birth IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM public.members m
      WHERE m.status = 'active'
        AND lower(btrim(m.first_name)) = lower(v_first_name)
        AND lower(btrim(m.last_name)) = lower(v_last_name)
        AND m.date_of_birth = p_date_of_birth
    )
  ) THEN
    member_id := NULL;
    duplicate_blocked := TRUE;
    RETURN NEXT;
    RETURN;
  END IF;

  BEGIN
    INSERT INTO public.members AS m (
      first_name,
      last_name,
      email,
      phone,
      date_of_birth,
      notes,
      is_facilitator,
      created_by_facilitator_id
    )
    VALUES (
      v_first_name,
      v_last_name,
      v_email,
      v_phone,
      p_date_of_birth,
      NULLIF(btrim(p_notes), ''),
      COALESCE(p_is_facilitator, false),
      p_created_by_facilitator_id
    )
    RETURNING m.member_id INTO v_member_id;
  EXCEPTION
    WHEN unique_violation THEN
      member_id := NULL;
      duplicate_blocked := TRUE;
      RETURN NEXT;
      RETURN;
  END;

  member_id := v_member_id;
  duplicate_blocked := FALSE;
  RETURN NEXT;
END;
$$;

COMMENT ON FUNCTION public.create_member_from_intake(text, text, text, text, date, text, boolean, uuid) IS
  'Serializes Member Intake hard-duplicate detection and member creation; returns duplicate_blocked instead of exposing another member record.';

COMMIT;
