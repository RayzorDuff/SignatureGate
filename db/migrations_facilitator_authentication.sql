ALTER TABLE public.members
  ADD COLUMN IF NOT EXISTS created_by_facilitator_id uuid NULL REFERENCES public.members(member_id);

CREATE INDEX IF NOT EXISTS idx_members_created_by_facilitator
  ON public.members(created_by_facilitator_id);

