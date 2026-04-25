BEGIN;

CREATE TABLE IF NOT EXISTS public.facilitator_storage_location_access (
  facilitator_storage_location_access_id uuid PRIMARY KEY DEFAULT public.uuid_generate_v4(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  facilitator_id uuid NOT NULL
    REFERENCES public.members(member_id)
    ON DELETE CASCADE,

  storage_location_name text NOT NULL,
  status text NOT NULL DEFAULT 'active',
  assigned_by_member_id uuid NULL
    REFERENCES public.members(member_id),
  notes text NULL,

  CONSTRAINT facilitator_storage_location_access_unique
    UNIQUE (facilitator_id, storage_location_name)
);

CREATE INDEX IF NOT EXISTS idx_fsl_access_facilitator_id
  ON public.facilitator_storage_location_access(facilitator_id);

CREATE INDEX IF NOT EXISTS idx_fsl_access_storage_location_name
  ON public.facilitator_storage_location_access(storage_location_name);

CREATE INDEX IF NOT EXISTS idx_fsl_access_facilitator_status
  ON public.facilitator_storage_location_access(facilitator_id, status);

CREATE INDEX IF NOT EXISTS idx_fsl_access_location_status
  ON public.facilitator_storage_location_access(storage_location_name, status);

-- Optional trigger if your DB already has public.set_updated_at()
DROP TRIGGER IF EXISTS trg_fsl_access_set_updated_at
  ON public.facilitator_storage_location_access;

CREATE TRIGGER trg_fsl_access_set_updated_at
BEFORE UPDATE ON public.facilitator_storage_location_access
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

INSERT INTO public.facilitator_storage_location_access (
  facilitator_id,
  storage_location_name,
  assigned_by_member_id,
  status,
  notes
)
SELECT
  m.member_id,
  trim(m.first_name || ' ' || m.last_name) AS storage_location_name,
  m.member_id,
  'active',
  'Backfilled from legacy facilitator-name location model'
FROM public.members m
WHERE m.is_facilitator = true
  AND m.status = 'active'
ON CONFLICT (facilitator_id, storage_location_name) DO NOTHING;

ALTER TABLE public.releases
ADD COLUMN IF NOT EXISTS storage_location_name text NULL;

COMMIT;
