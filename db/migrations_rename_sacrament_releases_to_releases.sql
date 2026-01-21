-- Rename sacrament_releases -> releases (and primary key column) to align with SPEC.md
-- Safe to run once; wrapped in conditional checks.

BEGIN;

	-- 1) Rename table
DO $$
	BEGIN
		  IF EXISTS (
			    SELECT 1
			    FROM information_schema.tables
			    WHERE table_schema = 'public' AND table_name = 'sacrament_releases'
			  ) THEN
			    ALTER TABLE public.sacrament_releases RENAME TO releases;
			  END IF;
		END $$;

		-- 2) Rename primary key column
DO $$
	BEGIN
		  IF EXISTS (
			    SELECT 1
			    FROM information_schema.columns
			    WHERE table_schema='public' AND table_name='releases' AND column_name='sacrament_release_id'
			  ) THEN
			    ALTER TABLE public.releases RENAME COLUMN sacrament_release_id TO release_id;
			  END IF;
		END $$;

		-- 3) Rename constraints (best-effort; constraint names vary per environment)
DO $$
	DECLARE
	  c text;
	BEGIN
		  -- primary key
  SELECT conname INTO c
  FROM pg_constraint
  WHERE conrelid = 'public.releases'::regclass AND contype='p'
  LIMIT 1;

  IF c IS NOT NULL AND c <> 'releases_pkey' THEN
	    EXECUTE format('ALTER TABLE public.releases RENAME CONSTRAINT %I TO releases_pkey', c);
	  END IF;

	  -- member fk
  SELECT conname INTO c
  FROM pg_constraint
  WHERE conrelid = 'public.releases'::regclass AND contype='f'
    AND pg_get_constraintdef(oid) LIKE '%(member_id)%'
  LIMIT 1;

  IF c IS NOT NULL AND c <> 'releases_member_id_fkey' THEN
	    EXECUTE format('ALTER TABLE public.releases RENAME CONSTRAINT %I TO releases_member_id_fkey', c);
	  END IF;

	  -- event fk
  SELECT conname INTO c
  FROM pg_constraint
  WHERE conrelid = 'public.releases'::regclass AND contype='f'
    AND pg_get_constraintdef(oid) LIKE '%(event_id)%'
  LIMIT 1;

  IF c IS NOT NULL AND c <> 'releases_event_id_fkey' THEN
	    EXECUTE format('ALTER TABLE public.releases RENAME CONSTRAINT %I TO releases_event_id_fkey', c);
	  END IF;
END $$;

COMMIT;

