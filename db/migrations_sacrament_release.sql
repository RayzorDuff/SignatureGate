ALTER TABLE sacrament_releases
  ADD COLUMN IF NOT EXISTS mushroomprocess_product_id text,
  ADD COLUMN IF NOT EXISTS facilitator_id uuid,
  ADD COLUMN IF NOT EXISTS net_weight_g integer,
  ADD COLUMN IF NOT EXISTS strain text;

CREATE INDEX ON sacrament_releases (mushroomprocess_product_id);
CREATE INDEX ON sacrament_releases (member_id);

-- On sacrament_releases (or better: rename to releases later)
ALTER TABLE sacrament_releases
  ADD COLUMN IF NOT EXISTS release_type text NOT NULL DEFAULT 'sacrament_release',
  ADD COLUMN IF NOT EXISTS member_agreement_id uuid NULL REFERENCES member_agreements(member_agreement_id);

CREATE INDEX IF NOT EXISTS idx_sacrament_releases_release_type ON sacrament_releases(release_type);
CREATE INDEX IF NOT EXISTS idx_member_agreements_member_status ON member_agreements(member_id, status);
