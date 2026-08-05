-- Prevent Members - Intake from creating a second active member when an
-- exact normalized phone number already belongs to an active member.
--
-- Shared phone numbers remain representable in the contact model, but Intake
-- requires reviewer intervention instead of creating a probable duplicate.

BEGIN;

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
  v_phone_normalized text :=
    NULLIF(public.normalize_us_phone(p_phone), '');
  v_member_id uuid;
BEGIN
  IF v_first_name IS NULL OR v_last_name IS NULL THEN
    RAISE EXCEPTION 'First and last name are required.';
  END IF;

  -- Intake volume is low. Serialize the duplicate-check/insert section across
  -- the member and contact tables so a concurrent member or contact insert
  -- cannot race the final exact-email or exact-phone check.
  LOCK TABLE
    public.members,
    public.member_emails,
    public.member_phones
  IN SHARE ROW EXCLUSIVE MODE;

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
        JOIN public.members m
          ON m.member_id = me.member_id
        WHERE me.email_normalized = v_email
          AND COALESCE(me.status, 'active') = 'active'
          AND m.status = 'active'
      )
    )
  )
  OR (
    v_phone_normalized IS NOT NULL
    AND (
      EXISTS (
        SELECT 1
        FROM public.member_phones mp
        JOIN public.members m
          ON m.member_id = mp.member_id
        WHERE mp.phone_normalized = v_phone_normalized
          AND COALESCE(mp.status, 'active') = 'active'
          AND m.status = 'active'
      )
      OR EXISTS (
        SELECT 1
        FROM public.members m
        WHERE m.status = 'active'
          AND public.normalize_us_phone(m.phone) =
              v_phone_normalized
      )
    )
  )
  OR (
    p_date_of_birth IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM public.members m
      WHERE m.status = 'active'
        AND lower(btrim(m.first_name)) =
            lower(v_first_name)
        AND lower(btrim(m.last_name)) =
            lower(v_last_name)
        AND m.date_of_birth = p_date_of_birth
    )
  )
  THEN
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

COMMENT ON FUNCTION public.create_member_from_intake(
  text,
  text,
  text,
  text,
  date,
  text,
  boolean,
  uuid
) IS
  'Serializes Intake duplicate detection and creation; blocks exact active email, exact active phone, and exact name-plus-date-of-birth matches without exposing the matching member.';

COMMIT;
