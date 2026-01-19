-- SignatureGate migration: add "void" (undo) support for releases
--
-- Rationale:
-- We should not DELETE release rows (auditability). Instead we mark them voided
-- and, if needed, revert upstream inventory location (Airtable) via n8n.
--
-- Fields added are generic enough to support future non-sacrament release types.

BEGIN;

	ALTER TABLE public.sacrament_releases
	  ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'issued',
	  ADD COLUMN IF NOT EXISTS voided_at timestamptz,
	  ADD COLUMN IF NOT EXISTS voided_by uuid REFERENCES public.members(member_id),
	  ADD COLUMN IF NOT EXISTS void_reason text;

	-- status values:
--   issued | voided

CREATE INDEX IF NOT EXISTS idx_sacrament_releases_status
  ON public.sacrament_releases (status, created_at DESC);

COMMIT;

