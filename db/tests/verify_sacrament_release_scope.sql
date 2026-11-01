BEGIN;

DO $$
DECLARE
  v_default text;
  v_constraint_exists boolean;
  v_member_id uuid;
  v_person_id uuid;
  v_blocked boolean := false;
  v_constraint_name text;
BEGIN
  SELECT column_default
  INTO v_default
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND table_name = 'releases'
    AND column_name = 'release_type';

  IF v_default IS NULL OR v_default NOT LIKE '%sacrament_release%' THEN
    RAISE EXCEPTION 'releases.release_type does not default to sacrament_release';
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.releases'::regclass
      AND conname = 'releases_sacrament_release_type_check'
      AND contype = 'c'
  )
  INTO v_constraint_exists;

  IF NOT v_constraint_exists THEN
    RAISE EXCEPTION 'Sacrament-only release constraint is missing';
  END IF;

  -- Always exercise rejection on fresh canonical databases; no installed
  -- Participant or historical release data is required.
  INSERT INTO public.people(display_name) VALUES ('Synthetic Release Scope')
  RETURNING person_id INTO v_person_id;
  INSERT INTO public.members(person_id) VALUES (v_person_id)
  RETURNING member_id INTO v_member_id;

  BEGIN
    INSERT INTO public.releases (
      member_id,
      mushroomprocess_product_id,
      item_name,
      quantity,
      unit,
      release_type,
      notes
    )
    VALUES (
      v_member_id,
      'issue19-non-sacrament-release-check',
      'Issue 19 verification only',
      1,
      'unit',
      'membership',
      'This insert must be rejected and is rolled back.'
    );
  EXCEPTION
    WHEN check_violation THEN
      GET STACKED DIAGNOSTICS v_constraint_name = CONSTRAINT_NAME;
      IF v_constraint_name <> 'releases_sacrament_release_type_check' THEN
        RAISE;
      END IF;
      v_blocked := true;
  END;

  IF NOT v_blocked THEN
    RAISE EXCEPTION 'A membership value was accepted as a release type';
  END IF;

  RAISE NOTICE 'Sacrament-release scope checks passed; rolling back verification work.';
END;
$$;

SELECT
  release_type,
  count(*) AS historical_rows
FROM public.releases
WHERE release_type IS DISTINCT FROM 'sacrament_release'
GROUP BY release_type
ORDER BY release_type;

SET CONSTRAINTS ALL IMMEDIATE;
ROLLBACK;
