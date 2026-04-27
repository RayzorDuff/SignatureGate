ALTER TABLE sacrament_releases
  ADD COLUMN IF NOT EXISTS mushroomprocess_product_id text,
  ADD COLUMN IF NOT EXISTS facilitator_id uuid REFERENCES members(member_id),
  ADD COLUMN IF NOT EXISTS net_weight_g integer,
  ADD COLUMN IF NOT EXISTS strain text,
  ADD COLUMN IF NOT EXISTS storage_location_name text,
  ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'issued',
  ADD COLUMN IF NOT EXISTS voided_at timestamptz,
  ADD COLUMN IF NOT EXISTS voided_by uuid REFERENCES members(member_id),
  ADD COLUMN IF NOT EXISTS void_reason text;

CREATE INDEX IF NOT EXISTS idx_sacrament_releases_product_id ON sacrament_releases (mushroomprocess_product_id);
CREATE INDEX IF NOT EXISTS idx_sacrament_releases_member_id ON sacrament_releases (member_id);
CREATE INDEX IF NOT EXISTS idx_sacrament_releases_status ON sacrament_releases (status);

-- On sacrament_releases (or better: rename to releases later)
ALTER TABLE sacrament_releases
  ADD COLUMN IF NOT EXISTS release_type text NOT NULL DEFAULT 'sacrament_release',
  ADD COLUMN IF NOT EXISTS member_agreement_id uuid NULL REFERENCES member_agreements(member_agreement_id);

-- Reviewer override support: releases may be assigned before the release agreement is signed.
ALTER TABLE sacrament_releases
  ALTER COLUMN member_agreement_id DROP NOT NULL;

CREATE INDEX IF NOT EXISTS idx_sacrament_releases_release_type ON sacrament_releases(release_type);
CREATE INDEX IF NOT EXISTS idx_member_agreements_member_status ON member_agreements(member_id, status);
