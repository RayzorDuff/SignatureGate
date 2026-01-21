BEGIN;

-- 1) Canonical list of allowed agreement/release types
CREATE TABLE IF NOT EXISTS public.agreement_types (
	  type_key    text PRIMARY KEY,          -- e.g. 'sacrament_release'
	  display_name text NOT NULL,             -- e.g. 'Sacrament Release'
	  description  text,
	  sort_order   integer NOT NULL DEFAULT 100,
	  active       boolean NOT NULL DEFAULT true,
	  created_at   timestamptz NOT NULL DEFAULT now(),
	  updated_at   timestamptz NOT NULL DEFAULT now()
	);

	-- seed (idempotent)
INSERT INTO public.agreement_types (type_key, display_name, description, sort_order, active)
VALUES
  ('sacrament_release', 'Sacrament Release', 'Sacrament release / product release agreement', 10, true),
  ('sweat_lodge',       'Sweat Lodge',       'Sweat lodge participation agreement',           20, true),
  ('retreat',           'Retreat',           'Retreat participation agreement',               30, true),
  ('membership',        'Membership',        'Membership agreement',                          40, true)
ON CONFLICT (type_key) DO UPDATE
SET display_name = EXCLUDED.display_name,
    description  = EXCLUDED.description,
    sort_order   = EXCLUDED.sort_order,
    active       = EXCLUDED.active,
    updated_at   = now();

-- 2) Validate agreement_templates.required_for[] entries are known types
CREATE OR REPLACE FUNCTION public.validate_agreement_template_required_for()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  missing text[];
BEGIN
  IF NEW.required_for IS NULL OR array_length(NEW.required_for, 1) IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT array_agg(x)
  INTO missing
  FROM unnest(NEW.required_for) AS x
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.agreement_types t
    WHERE t.type_key = x
      AND t.active = true
  );

  IF missing IS NOT NULL THEN
    RAISE EXCEPTION
      USING MESSAGE = format('agreement_templates.required_for contains unknown/inactive type(s): %s', array_to_string(missing, ', ')),
            ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_agreement_template_required_for ON public.agreement_templates;

CREATE TRIGGER trg_validate_agreement_template_required_for
BEFORE INSERT OR UPDATE OF required_for
ON public.agreement_templates
FOR EACH ROW
EXECUTE FUNCTION public.validate_agreement_template_required_for();

COMMIT;

