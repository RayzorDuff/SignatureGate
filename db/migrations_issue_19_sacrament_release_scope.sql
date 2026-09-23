BEGIN;

DO $$
BEGIN
  IF to_regclass('public.releases') IS NULL THEN
    RAISE EXCEPTION 'public.releases does not exist; apply the release-table rename migration first';
  END IF;
END;
$$;

LOCK TABLE public.releases IN SHARE ROW EXCLUSIVE MODE;

ALTER TABLE public.releases
  ALTER COLUMN release_type SET DEFAULT 'sacrament_release';

-- Blank values were never meaningful transaction types. Preserve any named
-- historical values for explicit review rather than guessing what they meant.
UPDATE public.releases
SET release_type = 'sacrament_release'
WHERE NULLIF(btrim(release_type), '') IS NULL;

ALTER TABLE public.releases
  DROP CONSTRAINT IF EXISTS releases_sacrament_release_type_check;

-- NOT VALID permits deployment when a historical installation contains a
-- legacy membership/event value, while still rejecting every new invalid row.
ALTER TABLE public.releases
  ADD CONSTRAINT releases_sacrament_release_type_check
  CHECK (release_type = 'sacrament_release')
  NOT VALID;

DO $$
DECLARE
  v_legacy_count bigint;
BEGIN
  SELECT count(*)
  INTO v_legacy_count
  FROM public.releases
  WHERE release_type IS DISTINCT FROM 'sacrament_release';

  IF v_legacy_count = 0 THEN
    ALTER TABLE public.releases
      VALIDATE CONSTRAINT releases_sacrament_release_type_check;
  ELSE
    RAISE NOTICE
      '% historical release row(s) use a non-sacrament type. New invalid rows are blocked; review the historical rows before validating the constraint.',
      v_legacy_count;
  END IF;
END;
$$;

COMMENT ON COLUMN public.releases.release_type IS
  'Compatibility discriminator. A release is a tangible sacrament transfer; new rows must use sacrament_release.';

COMMENT ON CONSTRAINT releases_sacrament_release_type_check ON public.releases IS
  'Prevents membership, event participation, and other non-tangible activities from being recorded as releases.';

COMMIT;
