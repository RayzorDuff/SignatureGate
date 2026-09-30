-- Issue #19: shared identities beneath the existing member and donor APIs.
-- Apply once after BOTH Issue #19 migrations. Keep the current Appsmith and
-- Givebutter exports until their person-aware replacements are ready.
\set ON_ERROR_STOP on

BEGIN;

DO $$
BEGIN
  IF to_regclass('public.contributors') IS NULL
     OR to_regclass('public.contributor_member_links') IS NULL
     OR to_regprocedure('public.ensure_member_contributor(uuid)') IS NULL
     OR to_regprocedure('public.match_contributor_identity(text,text,text,text)') IS NULL
  THEN
    RAISE EXCEPTION 'Apply both Issue #19 migrations before shared identity.';
  END IF;
END $$;

LOCK TABLE public.members, public.contributors,
  public.contributor_member_links IN SHARE ROW EXCLUSIVE MODE;

-- A person exists whether or not they are a member, donor, or Appsmith user.
-- Existing member UUIDs seed person UUIDs; all future identities are generated.
CREATE TABLE public.people (
  person_id uuid PRIMARY KEY DEFAULT public.uuid_generate_v4(),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  display_name text NOT NULL,
  first_name text,
  last_name text,
  date_of_birth date,
  CONSTRAINT people_name_check CHECK (NULLIF(btrim(display_name), '') IS NOT NULL)
);

CREATE TABLE public.organizations (
  organization_id uuid PRIMARY KEY DEFAULT public.uuid_generate_v4(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  organization_name text NOT NULL,
  CONSTRAINT organizations_name_check
    CHECK (NULLIF(btrim(organization_name), '') IS NOT NULL)
);

ALTER TABLE public.members ADD COLUMN person_id uuid;
ALTER TABLE public.contributors
  ADD COLUMN person_id uuid,
  ADD COLUMN organization_id uuid;

-- Historical links must be unambiguous before we make them identity mappings.
-- Stop for manual review rather than merging people on the strength of contact
-- details or guessing which of several historical member records represents one.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.contributor_member_links cml
    JOIN public.contributors c USING (contributor_id)
    WHERE c.contributor_type <> 'individual'
  ) OR EXISTS (
    SELECT 1 FROM public.contributor_member_links
    GROUP BY contributor_id HAVING count(DISTINCT member_id) > 1
  ) OR EXISTS (
    SELECT 1 FROM public.contributor_member_links
    GROUP BY member_id HAVING count(DISTINCT contributor_id) > 1
  ) THEN
    RAISE EXCEPTION 'Ambiguous contributor/member history; review links before migration.';
  END IF;
END $$;

INSERT INTO public.people (person_id, display_name, first_name, last_name, date_of_birth)
SELECT m.member_id,
  COALESCE(NULLIF(btrim(concat_ws(' ', m.first_name, m.last_name)), ''),
           NULLIF(btrim(m.email), ''), 'Member ' || m.member_id::text),
  m.first_name, m.last_name, m.date_of_birth
FROM public.members m;

UPDATE public.members SET person_id = member_id;

UPDATE public.contributors c
SET person_id = m.person_id
FROM public.contributor_member_links cml
JOIN public.members m ON m.member_id = cml.member_id
WHERE c.contributor_id = cml.contributor_id
  AND c.contributor_type = 'individual';

-- Unlinked individuals receive their own person identity; never coalesce by
-- email, phone, name, or address (those may belong to a household/company).
DO $$
DECLARE
  v_contributor record;
  v_person_id uuid;
BEGIN
  FOR v_contributor IN
    SELECT contributor_id, display_name, first_name, last_name
    FROM public.contributors
    WHERE contributor_type = 'individual' AND person_id IS NULL
    ORDER BY contributor_id
  LOOP
    INSERT INTO public.people (display_name, first_name, last_name)
    VALUES (v_contributor.display_name,
            v_contributor.first_name, v_contributor.last_name)
    RETURNING person_id INTO v_person_id;
    UPDATE public.contributors
    SET person_id = v_person_id
    WHERE contributor_id = v_contributor.contributor_id;
  END LOOP;
END $$;

INSERT INTO public.organizations (organization_id, organization_name)
SELECT contributor_id, organization_name
FROM public.contributors
WHERE contributor_type = 'organization';

UPDATE public.contributors
SET organization_id = contributor_id
WHERE contributor_type = 'organization';

ALTER TABLE public.members
  ALTER COLUMN person_id SET NOT NULL,
  ADD CONSTRAINT members_person_id_fkey
    FOREIGN KEY (person_id) REFERENCES public.people(person_id);
ALTER TABLE public.contributors
  ADD CONSTRAINT contributors_person_id_fkey
    FOREIGN KEY (person_id) REFERENCES public.people(person_id),
  ADD CONSTRAINT contributors_organization_id_fkey
    FOREIGN KEY (organization_id) REFERENCES public.organizations(organization_id),
  ADD CONSTRAINT contributors_party_identity_check CHECK (
    (contributor_type = 'individual' AND person_id IS NOT NULL AND organization_id IS NULL)
    OR
    (contributor_type = 'organization' AND organization_id IS NOT NULL AND person_id IS NULL)
  );

CREATE UNIQUE INDEX uq_members_active_person
  ON public.members(person_id) WHERE status = 'active';
CREATE UNIQUE INDEX uq_contributors_person
  ON public.contributors(person_id) WHERE person_id IS NOT NULL;
CREATE UNIQUE INDEX uq_contributors_organization
  ON public.contributors(organization_id) WHERE organization_id IS NOT NULL;

-- Preserve pre-existing differences for explicit review. Members take priority
-- for their own identity; no historical donation or contact row is rewritten.
CREATE TABLE public.person_identity_review (
  person_identity_review_id uuid PRIMARY KEY DEFAULT public.uuid_generate_v4(),
  created_at timestamptz NOT NULL DEFAULT now(),
  person_id uuid NOT NULL REFERENCES public.people(person_id),
  member_id uuid NOT NULL REFERENCES public.members(member_id),
  contributor_id uuid NOT NULL REFERENCES public.contributors(contributor_id),
  member_name text,
  contributor_name text,
  member_names jsonb NOT NULL,
  contributor_names jsonb NOT NULL,
  resolved_at timestamptz,
  resolution_notes text,
  UNIQUE (member_id, contributor_id)
);

INSERT INTO public.person_identity_review
  (person_id, member_id, contributor_id, member_name, contributor_name,
   member_names, contributor_names)
SELECT m.person_id, m.member_id, c.contributor_id,
  p.display_name, c.display_name,
  jsonb_build_object('first_name', m.first_name, 'last_name', m.last_name),
  jsonb_build_object('first_name', c.first_name, 'last_name', c.last_name)
FROM public.members m
JOIN public.people p ON p.person_id = m.person_id
JOIN public.contributor_member_links cml ON cml.member_id = m.member_id
JOIN public.contributors c ON c.contributor_id = cml.contributor_id
WHERE (m.first_name, m.last_name, lower(btrim(p.display_name)))
  IS DISTINCT FROM
  (c.first_name, c.last_name, lower(btrim(c.display_name)))
ON CONFLICT (member_id, contributor_id) DO NOTHING;

-- If an older member record lacks a name, retain the individual's known donor
-- name rather than replacing it with an email or a generated member label.
UPDATE public.people p
SET first_name = COALESCE(m.first_name, c.first_name),
    last_name = COALESCE(m.last_name, c.last_name),
    display_name = COALESCE(
      NULLIF(btrim(concat_ws(' ',
        COALESCE(m.first_name, c.first_name),
        COALESCE(m.last_name, c.last_name))), ''),
      NULLIF(btrim(c.display_name), ''), p.display_name)
FROM public.members m
JOIN public.contributor_member_links cml ON cml.member_id = m.member_id
JOIN public.contributors c ON c.contributor_id = cml.contributor_id
WHERE p.person_id = m.person_id
  AND (m.first_name IS NULL OR m.last_name IS NULL);

UPDATE public.members m
SET first_name = p.first_name, last_name = p.last_name
FROM public.people p
WHERE m.person_id = p.person_id
  AND (m.first_name, m.last_name) IS DISTINCT FROM (p.first_name, p.last_name);

-- Replace only the individual contributor's copied names. Donor-only people
-- already carry their contributor names; organization identities remain separate.
UPDATE public.contributors c
SET first_name = p.first_name,
    last_name = p.last_name,
    display_name = p.display_name
FROM public.people p
WHERE c.person_id = p.person_id
  AND (c.first_name, c.last_name, c.display_name)
      IS DISTINCT FROM (p.first_name, p.last_name, p.display_name);

CREATE TRIGGER trg_people_updated_at BEFORE UPDATE ON public.people
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER trg_organizations_updated_at BEFORE UPDATE ON public.organizations
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Legacy member writes continue to work. person_id is the durable identity;
-- names and DOB in members are compatibility projections for old workflows.
CREATE FUNCTION public.member_share_person_identity()
RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
DECLARE
  v_person public.people%ROWTYPE;
  v_previous_source text;
BEGIN
  IF TG_OP = 'INSERT' AND NEW.person_id IS NULL THEN
    INSERT INTO public.people(display_name, first_name, last_name, date_of_birth)
    VALUES (
      COALESCE(NULLIF(btrim(concat_ws(' ', NEW.first_name, NEW.last_name)), ''),
               NULLIF(btrim(NEW.email), ''), 'Member ' || NEW.member_id::text),
      NEW.first_name, NEW.last_name, NEW.date_of_birth
    ) RETURNING person_id INTO NEW.person_id;
  ELSIF TG_OP = 'UPDATE' AND NEW.person_id IS DISTINCT FROM OLD.person_id THEN
    SELECT * INTO v_person FROM public.people WHERE person_id = NEW.person_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Unknown person %', NEW.person_id; END IF;
    -- Existing member details take precedence when a member is linked.
    v_previous_source := COALESCE(current_setting('signaturegate.identity_source', true), '');
    PERFORM set_config('signaturegate.identity_source', 'member', true);
    UPDATE public.people p SET
      first_name = COALESCE(NEW.first_name, p.first_name),
      last_name = COALESCE(NEW.last_name, p.last_name),
      date_of_birth = COALESCE(NEW.date_of_birth, p.date_of_birth),
      display_name = COALESCE(
        NULLIF(btrim(concat_ws(' ', NEW.first_name, NEW.last_name)), ''),
        p.display_name)
    WHERE p.person_id = NEW.person_id
      AND (p.first_name, p.last_name, p.date_of_birth, p.display_name)
          IS DISTINCT FROM (
            COALESCE(NEW.first_name, p.first_name),
            COALESCE(NEW.last_name, p.last_name),
            COALESCE(NEW.date_of_birth, p.date_of_birth),
            COALESCE(NULLIF(btrim(concat_ws(' ', NEW.first_name, NEW.last_name)), ''),
                     p.display_name)
          );
    PERFORM set_config('signaturegate.identity_source', v_previous_source, true);
  ELSIF TG_OP = 'UPDATE' AND
    (NEW.first_name, NEW.last_name, NEW.date_of_birth)
      IS DISTINCT FROM (OLD.first_name, OLD.last_name, OLD.date_of_birth)
  THEN
    v_previous_source := COALESCE(current_setting('signaturegate.identity_source', true), '');
    PERFORM set_config('signaturegate.identity_source', 'member', true);
    UPDATE public.people p SET
      first_name = NEW.first_name,
      last_name = NEW.last_name,
      date_of_birth = NEW.date_of_birth,
      display_name = COALESCE(
        NULLIF(btrim(concat_ws(' ', NEW.first_name, NEW.last_name)), ''),
        p.display_name)
    WHERE p.person_id = NEW.person_id
      AND (p.first_name, p.last_name, p.date_of_birth)
        IS DISTINCT FROM (NEW.first_name, NEW.last_name, NEW.date_of_birth);
    PERFORM set_config('signaturegate.identity_source', v_previous_source, true);
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER trg_members_share_person
BEFORE INSERT OR UPDATE OF first_name, last_name, date_of_birth, person_id
ON public.members FOR EACH ROW EXECUTE FUNCTION public.member_share_person_identity();

CREATE FUNCTION public.contributor_share_party_identity()
RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
DECLARE
  v_person public.people%ROWTYPE;
  v_org public.organizations%ROWTYPE;
  v_previous_source text;
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.contributor_type IS DISTINCT FROM OLD.contributor_type THEN
    RAISE EXCEPTION 'Contributor type cannot change; create a new identity.';
  END IF;
  IF NEW.contributor_type = 'individual' THEN
    IF NEW.person_id IS NULL THEN
      INSERT INTO public.people(display_name, first_name, last_name)
      VALUES (NEW.display_name, NEW.first_name, NEW.last_name)
      RETURNING person_id INTO NEW.person_id;
    ELSIF TG_OP = 'INSERT' OR NEW.person_id IS DISTINCT FROM OLD.person_id THEN
      SELECT * INTO v_person FROM public.people WHERE person_id = NEW.person_id;
      IF NOT FOUND THEN RAISE EXCEPTION 'Unknown person %', NEW.person_id; END IF;
      NEW.first_name := v_person.first_name;
      NEW.last_name := v_person.last_name;
      NEW.display_name := v_person.display_name;
    ELSIF TG_OP = 'UPDATE' AND
      (NEW.first_name, NEW.last_name, NEW.display_name)
        IS DISTINCT FROM (OLD.first_name, OLD.last_name, OLD.display_name)
    THEN
      v_previous_source := COALESCE(current_setting('signaturegate.identity_source', true), '');
      PERFORM set_config('signaturegate.identity_source', 'contributor', true);
      UPDATE public.people p SET
        first_name = NEW.first_name,
        last_name = NEW.last_name,
        display_name = NEW.display_name
      WHERE p.person_id = NEW.person_id
        AND (p.first_name, p.last_name, p.display_name)
          IS DISTINCT FROM (NEW.first_name, NEW.last_name, NEW.display_name);
      PERFORM set_config('signaturegate.identity_source', v_previous_source, true);
    END IF;
  ELSE
    IF NEW.organization_id IS NULL THEN
      INSERT INTO public.organizations(organization_name)
      VALUES (NEW.organization_name)
      RETURNING organization_id INTO NEW.organization_id;
    ELSIF TG_OP = 'INSERT' OR NEW.organization_id IS DISTINCT FROM OLD.organization_id THEN
      SELECT * INTO v_org FROM public.organizations
      WHERE organization_id = NEW.organization_id;
      IF NOT FOUND THEN RAISE EXCEPTION 'Unknown organization %', NEW.organization_id; END IF;
      NEW.organization_name := v_org.organization_name;
      NEW.display_name := v_org.organization_name;
    ELSIF TG_OP = 'UPDATE' AND NEW.organization_name IS DISTINCT FROM OLD.organization_name THEN
      v_previous_source := COALESCE(current_setting('signaturegate.identity_source', true), '');
      PERFORM set_config('signaturegate.identity_source', 'contributor', true);
      UPDATE public.organizations o SET organization_name = NEW.organization_name
      WHERE o.organization_id = NEW.organization_id
        AND o.organization_name IS DISTINCT FROM NEW.organization_name;
      PERFORM set_config('signaturegate.identity_source', v_previous_source, true);
    END IF;
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER trg_contributors_share_party
BEFORE INSERT OR UPDATE OF person_id, organization_id, contributor_type,
  display_name, first_name, last_name, organization_name
ON public.contributors FOR EACH ROW
EXECUTE FUNCTION public.contributor_share_party_identity();

-- Direct canonical edits propagate to both older read models. Predicates
-- prevent the reciprocal BEFORE triggers from repeatedly updating the person.
CREATE FUNCTION public.project_person_identity()
RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
BEGIN
  IF current_setting('signaturegate.identity_source', true)
     IS DISTINCT FROM 'member' THEN
    UPDATE public.members m
    SET first_name = NEW.first_name,
        last_name = NEW.last_name,
        date_of_birth = NEW.date_of_birth
    WHERE m.person_id = NEW.person_id
      AND (m.first_name, m.last_name, m.date_of_birth)
        IS DISTINCT FROM (NEW.first_name, NEW.last_name, NEW.date_of_birth);
  END IF;

  IF current_setting('signaturegate.identity_source', true)
     IS DISTINCT FROM 'contributor' THEN
    UPDATE public.contributors c
    SET first_name = NEW.first_name,
        last_name = NEW.last_name,
        display_name = NEW.display_name
    WHERE c.person_id = NEW.person_id
      AND (c.first_name, c.last_name, c.display_name)
        IS DISTINCT FROM (NEW.first_name, NEW.last_name, NEW.display_name);
  END IF;
  RETURN NULL;
END $$;

CREATE TRIGGER trg_people_project_identity
AFTER UPDATE OF first_name, last_name, date_of_birth, display_name
ON public.people FOR EACH ROW EXECUTE FUNCTION public.project_person_identity();

CREATE FUNCTION public.project_organization_identity()
RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
BEGIN
  IF current_setting('signaturegate.identity_source', true)
     IS DISTINCT FROM 'contributor' THEN
    UPDATE public.contributors c
    SET organization_name = NEW.organization_name,
        display_name = NEW.organization_name
    WHERE c.organization_id = NEW.organization_id
      AND (c.organization_name, c.display_name)
        IS DISTINCT FROM (NEW.organization_name, NEW.organization_name);
  END IF;
  RETURN NULL;
END $$;

CREATE TRIGGER trg_organizations_project_identity
AFTER UPDATE OF organization_name ON public.organizations
FOR EACH ROW EXECUTE FUNCTION public.project_organization_identity();

-- The donor's person ID survives joining membership; the member's ID survives
-- first becoming a donor. Active links must point to the SAME person.
CREATE FUNCTION public.reconcile_linked_person()
RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
DECLARE
  v_member_person uuid;
  v_donor_person uuid;
  v_keep uuid;
  v_drop uuid;
  v_member_name text;
  v_donor_name text;
  v_member_first text;
  v_member_last text;
  v_donor_first text;
  v_donor_last text;
BEGIN
  IF NEW.status <> 'active' THEN RETURN NULL; END IF;
  SELECT person_id, NULLIF(btrim(concat_ws(' ', first_name, last_name)), ''),
         first_name, last_name
    INTO v_member_person, v_member_name, v_member_first, v_member_last
    FROM public.members WHERE member_id = NEW.member_id FOR UPDATE;
  SELECT person_id, display_name, first_name, last_name
    INTO v_donor_person, v_donor_name, v_donor_first, v_donor_last
    FROM public.contributors WHERE contributor_id = NEW.contributor_id FOR UPDATE;

  IF v_member_person = v_donor_person THEN RETURN NULL; END IF;
  SELECT CASE WHEN cp.created_at < mp.created_at
              THEN v_donor_person ELSE v_member_person END
  INTO v_keep
  FROM public.people cp CROSS JOIN public.people mp
  WHERE cp.person_id = v_donor_person AND mp.person_id = v_member_person;

  INSERT INTO public.person_identity_review
    (person_id, member_id, contributor_id, member_name, contributor_name,
     member_names, contributor_names)
  SELECT v_keep, NEW.member_id, NEW.contributor_id,
    v_member_name, v_donor_name,
    jsonb_build_object('first_name', v_member_first, 'last_name', v_member_last),
    jsonb_build_object('first_name', v_donor_first, 'last_name', v_donor_last)
  WHERE (v_member_first, v_member_last, lower(btrim(v_member_name)))
    IS DISTINCT FROM (v_donor_first, v_donor_last, lower(btrim(v_donor_name)))
  ON CONFLICT (member_id, contributor_id) DO NOTHING;

  IF v_keep = v_donor_person THEN
    v_drop := v_member_person;
    UPDATE public.members SET person_id = v_keep WHERE member_id = NEW.member_id;
  ELSE
    v_drop := v_donor_person;
    UPDATE public.contributors SET person_id = v_keep
    WHERE contributor_id = NEW.contributor_id;
  END IF;

  DELETE FROM public.people p WHERE p.person_id = v_drop
    AND NOT EXISTS (SELECT 1 FROM public.members m WHERE m.person_id = v_drop)
    AND NOT EXISTS (SELECT 1 FROM public.contributors c WHERE c.person_id = v_drop)
    AND NOT EXISTS (SELECT 1 FROM public.person_identity_review r WHERE r.person_id = v_drop);
  RETURN NULL;
END $$;

CREATE TRIGGER trg_links_reconcile_person
AFTER INSERT OR UPDATE OF member_id, contributor_id, status
ON public.contributor_member_links FOR EACH ROW
EXECUTE FUNCTION public.reconcile_linked_person();

-- Check the invariant at transaction end; the link trigger may change two
-- tables in succession. It also protects direct edits to their person_id.
CREATE FUNCTION public.check_linked_person_identity()
RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.contributor_member_links cml
    JOIN public.members m ON m.member_id = cml.member_id
    JOIN public.contributors c ON c.contributor_id = cml.contributor_id
    WHERE cml.status = 'active' AND m.person_id <> c.person_id
  ) THEN
    RAISE EXCEPTION 'An active contributor/member link crosses two people.';
  END IF;
  RETURN NULL;
END $$;

CREATE CONSTRAINT TRIGGER trg_members_check_linked_person
AFTER INSERT OR UPDATE OF person_id ON public.members
DEFERRABLE INITIALLY DEFERRED FOR EACH ROW
EXECUTE FUNCTION public.check_linked_person_identity();
CREATE CONSTRAINT TRIGGER trg_contributors_check_linked_person
AFTER INSERT OR UPDATE OF person_id ON public.contributors
DEFERRABLE INITIALLY DEFERRED FOR EACH ROW
EXECUTE FUNCTION public.check_linked_person_identity();
CREATE CONSTRAINT TRIGGER trg_links_check_linked_person
AFTER INSERT OR UPDATE OF member_id, contributor_id, status
ON public.contributor_member_links
DEFERRABLE INITIALLY DEFERRED FOR EACH ROW
EXECUTE FUNCTION public.check_linked_person_identity();

-- Compatibility contact tables remain writable by the deployed application.
-- These views offer one deduplicated read surface per person for the next UI.
-- Distinct contact values remain visible for review; shared phone/email does
-- not, by itself, imply that two identities represent one person.
CREATE VIEW public.v_person_emails AS
SELECT DISTINCT ON (person_id, email_normalized)
  person_id, email, email_normalized, is_primary, is_verified,
  contact_source, contact_id
FROM (
  SELECT m.person_id, me.email, me.email_normalized,
    me.is_primary, me.is_verified, 'member'::text AS contact_source,
    me.member_email_id AS contact_id, 0 AS preference, me.updated_at
  FROM public.member_emails me
  JOIN public.members m ON m.member_id = me.member_id
  WHERE me.status = 'active' AND NULLIF(me.email_normalized, '') IS NOT NULL
  UNION ALL
  SELECT c.person_id, ce.email, ce.email_normalized,
    ce.is_primary, ce.is_verified, 'contributor',
    ce.contributor_email_id, 1, ce.updated_at
  FROM public.contributor_emails ce
  JOIN public.contributors c ON c.contributor_id = ce.contributor_id
  WHERE ce.status = 'active' AND c.person_id IS NOT NULL
    AND NULLIF(ce.email_normalized, '') IS NOT NULL
) contacts
ORDER BY person_id, email_normalized, preference, updated_at DESC;

CREATE VIEW public.v_person_phones AS
SELECT DISTINCT ON (person_id, phone_normalized)
  person_id, phone, phone_normalized, is_primary, is_verified,
  contact_source, contact_id
FROM (
  SELECT m.person_id, mp.phone, mp.phone_normalized,
    mp.is_primary, mp.is_verified, 'member'::text AS contact_source,
    mp.member_phone_id AS contact_id, 0 AS preference, mp.updated_at
  FROM public.member_phones mp
  JOIN public.members m ON m.member_id = mp.member_id
  WHERE mp.status = 'active' AND NULLIF(mp.phone_normalized, '') IS NOT NULL
  UNION ALL
  SELECT c.person_id, cp.phone, cp.phone_normalized,
    cp.is_primary, cp.is_verified, 'contributor',
    cp.contributor_phone_id, 1, cp.updated_at
  FROM public.contributor_phones cp
  JOIN public.contributors c ON c.contributor_id = cp.contributor_id
  WHERE cp.status = 'active' AND c.person_id IS NOT NULL
    AND NULLIF(cp.phone_normalized, '') IS NOT NULL
) contacts
ORDER BY person_id, phone_normalized, preference, updated_at DESC;

CREATE VIEW public.v_person_addresses AS
SELECT DISTINCT ON (person_id, identity_key)
  person_id, address_1, address_2, city, state, postal_code, country,
  address_type, is_primary, contact_source, contact_id
FROM (
  SELECT m.person_id, ma.address_1, ma.address_2, ma.city, ma.state,
    ma.postal_code, ma.country, ma.address_type, ma.is_primary,
    'member'::text AS contact_source, ma.member_address_id AS contact_id,
    COALESCE(NULLIF(ma.address_identity_key, ''), ma.member_address_id::text)
      AS identity_key, 0 AS preference, ma.updated_at
  FROM public.member_addresses ma
  JOIN public.members m ON m.member_id = ma.member_id
  WHERE ma.status = 'active'
  UNION ALL
  SELECT c.person_id, ca.address_1, ca.address_2, ca.city, ca.state,
    ca.postal_code, ca.country, ca.address_type, ca.is_primary,
    'contributor', ca.contributor_address_id,
    COALESCE(NULLIF(ca.address_identity_key, ''), ca.contributor_address_id::text),
    1, ca.updated_at
  FROM public.contributor_addresses ca
  JOIN public.contributors c ON c.contributor_id = ca.contributor_id
  WHERE ca.status = 'active' AND c.person_id IS NOT NULL
) contacts
ORDER BY person_id, identity_key, preference, updated_at DESC;

-- Linking identities must not reclassify donations that predate membership.
CREATE OR REPLACE FUNCTION public.link_contributor_to_member(
  p_contributor_id uuid,
  p_member_id uuid,
  p_actor_id uuid,
  p_reason text DEFAULT NULL
)
RETURNS public.contributor_member_links
LANGUAGE plpgsql VOLATILE SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_link public.contributor_member_links%ROWTYPE;
BEGIN
  IF p_actor_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.members m WHERE m.member_id = p_actor_id
      AND m.status = 'active' AND m.is_facilitator IS TRUE
      AND m.is_donations_reviewer IS TRUE
  ) THEN RAISE EXCEPTION 'An active donations reviewer is required.'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.members m
    WHERE m.member_id = p_member_id AND m.status = 'active'
  ) THEN RAISE EXCEPTION 'The selected member is not active.'; END IF;

  INSERT INTO public.contributor_member_links
    (contributor_id, member_id, status, linked_by, link_reason)
  VALUES (p_contributor_id, p_member_id, 'active', p_actor_id,
          NULLIF(btrim(p_reason), ''))
  RETURNING * INTO v_link;

  INSERT INTO public.audit_log (actor, action, entity_type, entity_id, details)
  SELECT actor.email, 'contributor.member_linked', 'contributor',
         p_contributor_id::text,
         jsonb_build_object('member_id', p_member_id, 'actor_id', p_actor_id,
                            'reason', NULLIF(btrim(p_reason), ''))
  FROM public.members actor WHERE actor.member_id = p_actor_id;
  RETURN v_link;
END $$;

COMMENT ON TABLE public.people IS
  'Shared person identity. Membership, donations, participation, and future appointments refer to this person without creating another human identity.';
COMMENT ON TABLE public.organizations IS
  'Shared organization identity; organizations cannot be members or ceremony participants.';
COMMENT ON COLUMN public.members.person_id IS
  'Member-specific record for this person; historical member_id references remain valid.';
COMMENT ON COLUMN public.contributors.person_id IS
  'Individual donor party linked to a person; null for organization donors.';
COMMENT ON TABLE public.person_identity_review IS
  'Pre-existing name differences requiring review; source values are retained.';

COMMIT;

SELECT (SELECT count(*) FROM public.members WHERE person_id IS NULL)
    AS members_without_person,
       (SELECT count(*) FROM public.contributors
        WHERE (contributor_type = 'individual' AND person_id IS NULL)
           OR (contributor_type = 'organization' AND organization_id IS NULL))
    AS contributors_without_identity,
       (SELECT count(*) FROM public.person_identity_review WHERE resolved_at IS NULL)
    AS names_to_review;
