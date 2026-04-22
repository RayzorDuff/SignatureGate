BEGIN;

-- 1) Table to control which facilitators may manage which members
CREATE TABLE IF NOT EXISTS public.member_facilitators (
  member_facilitator_id uuid PRIMARY KEY DEFAULT public.uuid_generate_v4(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  member_id uuid NOT NULL REFERENCES public.members(member_id) ON DELETE CASCADE,
  facilitator_id uuid NOT NULL REFERENCES public.members(member_id) ON DELETE CASCADE,

  assigned_by_member_id uuid NULL REFERENCES public.members(member_id),
  status text NOT NULL DEFAULT 'active',
  notes text NULL,

  CONSTRAINT member_facilitators_unique UNIQUE (member_id, facilitator_id)
);

CREATE INDEX IF NOT EXISTS idx_member_facilitators_member_id
  ON public.member_facilitators(member_id);

CREATE INDEX IF NOT EXISTS idx_member_facilitators_facilitator_id
  ON public.member_facilitators(facilitator_id);

CREATE INDEX IF NOT EXISTS idx_member_facilitators_member_status
  ON public.member_facilitators(member_id, status);

CREATE INDEX IF NOT EXISTS idx_member_facilitators_facilitator_status
  ON public.member_facilitators(facilitator_id, status);

DROP TRIGGER IF EXISTS trg_member_facilitators_set_updated_at ON public.member_facilitators;
CREATE TRIGGER trg_member_facilitators_set_updated_at
BEFORE UPDATE ON public.member_facilitators
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

-- 2) Backfill assignments from older single-facilitator-era relationships

-- from members.created_by_facilitator_id if present in the live DB
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'members'
      AND column_name = 'created_by_facilitator_id'
  ) THEN
    EXECUTE $sql$
      INSERT INTO public.member_facilitators (
        member_id,
        facilitator_id,
        assigned_by_member_id,
        status,
        notes
      )
      SELECT DISTINCT
        m.member_id,
        m.created_by_facilitator_id,
        m.created_by_facilitator_id,
        'active',
        'Backfilled from members.created_by_facilitator_id'
      FROM public.members m
      WHERE m.created_by_facilitator_id IS NOT NULL
      ON CONFLICT (member_id, facilitator_id) DO NOTHING
    $sql$;
  END IF;
END $$;

-- from agreements
INSERT INTO public.member_facilitators (
  member_id,
  facilitator_id,
  assigned_by_member_id,
  status,
  notes
)
SELECT DISTINCT
  ma.member_id,
  ma.facilitator_id,
  ma.facilitator_id,
  'active',
  'Backfilled from member_agreements.facilitator_id'
FROM public.member_agreements ma
WHERE ma.member_id IS NOT NULL
  AND ma.facilitator_id IS NOT NULL
ON CONFLICT (member_id, facilitator_id) DO NOTHING;

-- from releases, only if facilitator_id exists in current live releases table
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'releases'
      AND column_name = 'facilitator_id'
  ) THEN
    EXECUTE $sql$
      INSERT INTO public.member_facilitators (
        member_id,
        facilitator_id,
        assigned_by_member_id,
        status,
        notes
      )
      SELECT DISTINCT
        r.member_id,
        r.facilitator_id,
        r.facilitator_id,
        'active',
        'Backfilled from releases.facilitator_id'
      FROM public.releases r
      WHERE r.member_id IS NOT NULL
        AND r.facilitator_id IS NOT NULL
      ON CONFLICT (member_id, facilitator_id) DO NOTHING
    $sql$;
  END IF;
END $$;

-- from donations, only if facilitator_id exists in current live donations table
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'donations'
      AND column_name = 'facilitator_id'
  ) THEN
    EXECUTE $sql$
      INSERT INTO public.member_facilitators (
        member_id,
        facilitator_id,
        assigned_by_member_id,
        status,
        notes
      )
      SELECT DISTINCT
        d.member_id,
        d.facilitator_id,
        d.facilitator_id,
        'active',
        'Backfilled from donations.facilitator_id'
      FROM public.donations d
      WHERE d.member_id IS NOT NULL
        AND d.facilitator_id IS NOT NULL
      ON CONFLICT (member_id, facilitator_id) DO NOTHING
    $sql$;
  END IF;
END $$;

COMMIT;
