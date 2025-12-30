-- SignatureGate baseline schema (PostgreSQL)
-- Keep this small and evolvable: use UUID PKs, immutable audit log, and soft references to external systems.

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Members
CREATE TABLE IF NOT EXISTS members (
  member_id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  status text NOT NULL DEFAULT 'active', -- active|inactive|banned|deceased
  first_name text,
  last_name text,
  email text,
  phone text,
  date_of_birth date,
  notes text
);

-- Agreement templates (versioned)
CREATE TABLE IF NOT EXISTS agreement_templates (
  agreement_template_id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  created_at timestamptz NOT NULL DEFAULT now(),
  name text NOT NULL,                 -- e.g. "Member Acknowledgment & Liability Release"
  version text NOT NULL,              -- e.g. "2025-12-01"
  required_for text[] NOT NULL,       -- e.g. {"membership","sacrament_release"} or {"retreat","sweat_lodge"}
  doc_url text,                       -- link to canonical PDF or OpenSign template URL
  active boolean NOT NULL DEFAULT true
);

-- Executed agreements (signed by member; paper or OpenSign)
CREATE TABLE IF NOT EXISTS member_agreements (
  member_agreement_id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  created_at timestamptz NOT NULL DEFAULT now(),
  member_id uuid NOT NULL REFERENCES members(member_id),
  agreement_template_id uuid NOT NULL REFERENCES agreement_templates(agreement_template_id),
  signed_at timestamptz,              -- when signature captured
  signature_method text NOT NULL,     -- paper|opensign|other
  evidence_url text,                  -- link to scanned pdf, OpenSign doc, etc.
  verified_by text,                   -- operator/facilitator name
  verified_at timestamptz,
  status text NOT NULL DEFAULT 'pending' -- pending|signed|rejected|revoked
);

-- Events: ceremonies, retreats, sweat lodges, etc.
CREATE TABLE IF NOT EXISTS events (
  event_id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  created_at timestamptz NOT NULL DEFAULT now(),
  type text NOT NULL,                 -- ceremony|retreat|sweat_lodge|integration_circle|other
  name text,
  starts_at timestamptz,
  ends_at timestamptz,
  location text,
  notes text
);

-- Sacrament releases (distribution log)
CREATE TABLE IF NOT EXISTS sacrament_releases (
  sacrament_release_id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  created_at timestamptz NOT NULL DEFAULT now(),
  released_at timestamptz NOT NULL DEFAULT now(),
  member_id uuid NOT NULL REFERENCES members(member_id),
  event_id uuid REFERENCES events(event_id),

  -- Interop: link back to MushroomProcess
  mushroomprocess_product_id text NOT NULL,      -- maps to MushroomProcess products.product_id
  item_name text,                            -- human label at time of release
  quantity numeric(12,3) NOT NULL DEFAULT 0,
  unit text NOT NULL DEFAULT 'g',

  released_by text,                          -- facilitator/operator
  notes text
);

-- Donations (voluntary contributions)
CREATE TABLE IF NOT EXISTS donations (
  donation_id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  created_at timestamptz NOT NULL DEFAULT now(),
  member_id uuid REFERENCES members(member_id),
  provider text NOT NULL,                    -- cash|givebutter|other
  provider_reference text,                   -- Givebutter donation id, etc.
  amount_cents integer,
  currency text DEFAULT 'USD',
  donated_at timestamptz,
  notes text
);

-- Immutable audit log (generic)
CREATE TABLE IF NOT EXISTS audit_log (
  audit_log_id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  created_at timestamptz NOT NULL DEFAULT now(),
  actor text,
  action text NOT NULL,
  entity_type text NOT NULL,
  entity_id text NOT NULL,
  details jsonb
);

-- Trigger to keep updated_at fresh
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_members_updated_at ON members;
CREATE TRIGGER trg_members_updated_at
BEFORE UPDATE ON members
FOR EACH ROW EXECUTE FUNCTION set_updated_at();
