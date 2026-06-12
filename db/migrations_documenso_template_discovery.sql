-- SignatureGate: Documenso template discovery and agreement template creation support.
-- Safe/idempotent migration for issue: create templates from Appsmith using Documenso template metadata.

BEGIN;

ALTER TABLE public.agreement_templates
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS documenso_template_id integer,
  ADD COLUMN IF NOT EXISTS documenso_template_envelope_id text,
  ADD COLUMN IF NOT EXISTS documenso_member_recipient_id integer,
  ADD COLUMN IF NOT EXISTS documenso_facilitator_recipient_id integer;

-- Keep updated_at current for direct table writes as well as Appsmith writes.
CREATE OR REPLACE FUNCTION public.set_agreement_templates_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_agreement_templates_updated_at ON public.agreement_templates;
CREATE TRIGGER trg_agreement_templates_updated_at
BEFORE UPDATE ON public.agreement_templates
FOR EACH ROW
EXECUTE FUNCTION public.set_agreement_templates_updated_at();

-- Basic data-shape protections. These allow NULLs because paper-only templates may exist.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'agreement_templates_documenso_template_id_positive'
      AND conrelid = 'public.agreement_templates'::regclass
  ) THEN
    ALTER TABLE public.agreement_templates
      ADD CONSTRAINT agreement_templates_documenso_template_id_positive
      CHECK (documenso_template_id IS NULL OR documenso_template_id > 0);
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'agreement_templates_documenso_member_recipient_id_positive'
      AND conrelid = 'public.agreement_templates'::regclass
  ) THEN
    ALTER TABLE public.agreement_templates
      ADD CONSTRAINT agreement_templates_documenso_member_recipient_id_positive
      CHECK (documenso_member_recipient_id IS NULL OR documenso_member_recipient_id > 0);
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'agreement_templates_documenso_facilitator_recipient_id_positive'
      AND conrelid = 'public.agreement_templates'::regclass
  ) THEN
    ALTER TABLE public.agreement_templates
      ADD CONSTRAINT agreement_templates_documenso_facilitator_recipient_id_positive
      CHECK (documenso_facilitator_recipient_id IS NULL OR documenso_facilitator_recipient_id > 0);
  END IF;
END;
$$;

CREATE INDEX IF NOT EXISTS idx_agreement_templates_required_for_gin
  ON public.agreement_templates USING gin (required_for);

CREATE INDEX IF NOT EXISTS idx_agreement_templates_documenso_template_id
  ON public.agreement_templates (documenso_template_id)
  WHERE documenso_template_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_agreement_templates_documenso_envelope_id
  ON public.agreement_templates (documenso_template_envelope_id)
  WHERE documenso_template_envelope_id IS NOT NULL
    AND documenso_template_envelope_id <> '';

COMMIT;
