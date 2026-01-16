-- Adds helper indexes for audit_log and (optionally) tighter constraints.

-- Index for most common queries: newest-first lookups
CREATE INDEX IF NOT EXISTS audit_log_created_at_idx
  ON public.audit_log (created_at DESC);

-- Index for filtering by entity
CREATE INDEX IF NOT EXISTS audit_log_entity_idx
  ON public.audit_log (entity_type, entity_id);

-- Index for filtering by actor
CREATE INDEX IF NOT EXISTS audit_log_actor_idx
  ON public.audit_log (actor);

-- Optional: enforce lowercasing of actor emails (commented out)
UPDATE public.audit_log SET actor = lower(actor) WHERE actor IS NOT NULL;
ALTER TABLE public.audit_log
  ADD CONSTRAINT audit_log_actor_lowercase CHECK (actor = lower(actor));

