-- Add Documenso integration fields.
-- This migration is additive and safe to run once.

ALTER TABLE public.agreement_templates
  ADD COLUMN IF NOT EXISTS updated_at timestamp with time zone DEFAULT now() NOT NULL,
  ADD COLUMN IF NOT EXISTS documenso_template_envelope_id text,
  ADD COLUMN IF NOT EXISTS documenso_member_recipient_id integer,
  ADD COLUMN IF NOT EXISTS documenso_facilitator_recipient_id integer;

ALTER TABLE public.member_agreements
  ADD COLUMN IF NOT EXISTS updated_at timestamp with time zone DEFAULT now() NOT NULL,
  ADD COLUMN IF NOT EXISTS documenso_document_id text,
  ADD COLUMN IF NOT EXISTS documenso_external_id text;

-- Seed current Documenso template + recipient IDs for the active sacrament release template.
-- Template envelope: envelope_hyneotebbuzwfzly
-- Recipients: 5=Member, 6=Facilitator
UPDATE public.agreement_templates
SET
  documenso_template_envelope_id = 'envelope_hyneotebbuzwfzly',
  documenso_member_recipient_id = 5,
  documenso_facilitator_recipient_id = 6,
  updated_at = now()
WHERE active = true
  AND 'sacrament_release' = ANY(required_for)
  AND (documenso_template_envelope_id IS NULL OR documenso_template_envelope_id = '');
