-- Issues #19/#20: canonical person identity for storage access and releases.
-- Apply after migrations_issue_20_organization_terminology.sql; run once.
\set ON_ERROR_STOP on
BEGIN;

DO $$ BEGIN
  IF to_regclass('public.member_practitioner_assignments') IS NULL
     OR to_regclass('public.facilitator_storage_location_access') IS NULL
     OR to_regprocedure('public.issue20_organization_terminology()') IS NULL
     OR to_regprocedure('public.issue19_sacrament_release_agreement(uuid)') IS NULL THEN
    RAISE EXCEPTION 'Apply the Issue #19 practitioner and Issue #20 terminology migrations first';
  END IF;
END $$;

LOCK TABLE public.facilitator_storage_location_access IN SHARE ROW EXCLUSIVE MODE;
LOCK TABLE public.releases IN SHARE ROW EXCLUSIVE MODE;

CREATE TABLE public.practitioner_storage_location_access (
  practitioner_storage_location_access_id uuid PRIMARY KEY
    DEFAULT public.uuid_generate_v4(),
  practitioner_person_id uuid NOT NULL REFERENCES public.people(person_id),
  storage_location_name text NOT NULL,
  status text NOT NULL DEFAULT 'active'
    CHECK (status IN ('active','inactive')),
  assigned_by_person_id uuid REFERENCES public.people(person_id),
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT practitioner_storage_location_access_unique
    UNIQUE (practitioner_person_id,storage_location_name),
  CHECK (NULLIF(btrim(storage_location_name),'') IS NOT NULL)
);

CREATE INDEX practitioner_storage_location_person_status_idx
  ON public.practitioner_storage_location_access(
    practitioner_person_id,status);
CREATE INDEX practitioner_storage_location_name_status_idx
  ON public.practitioner_storage_location_access(
    storage_location_name,status);
CREATE TRIGGER trg_practitioner_storage_location_updated_at
BEFORE UPDATE ON public.practitioner_storage_location_access
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Preserve the legacy access IDs so audit references and UI rows continue to
-- identify the same grants after their owner moves from membership to person.
INSERT INTO public.practitioner_storage_location_access(
  practitioner_storage_location_access_id,practitioner_person_id,
  storage_location_name,status,assigned_by_person_id,notes,
  created_at,updated_at)
SELECT legacy.facilitator_storage_location_access_id,practitioner.person_id,
  legacy.storage_location_name,
  CASE WHEN lower(COALESCE(legacy.status,'active'))='active'
    THEN 'active' ELSE 'inactive' END,
  assigner.person_id,legacy.notes,legacy.created_at,legacy.updated_at
FROM public.facilitator_storage_location_access legacy
JOIN public.members practitioner
  ON practitioner.member_id=legacy.facilitator_id
LEFT JOIN public.members assigner
  ON assigner.member_id=legacy.assigned_by_member_id
ON CONFLICT (practitioner_person_id,storage_location_name) DO UPDATE SET
  status=EXCLUDED.status,
  assigned_by_person_id=COALESCE(EXCLUDED.assigned_by_person_id,
    public.practitioner_storage_location_access.assigned_by_person_id),
  notes=COALESCE(EXCLUDED.notes,
    public.practitioner_storage_location_access.notes),
  updated_at=GREATEST(
    public.practitioner_storage_location_access.updated_at,
    EXCLUDED.updated_at);

-- Members - Profile remains a compatibility writer during this phase.
CREATE FUNCTION public.issue19_sync_legacy_practitioner_storage_location()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER
SET search_path = public, pg_temp AS $$
DECLARE
  v_practitioner_person_id uuid;
  v_assigned_by_person_id uuid;
  v_status text;
BEGIN
  SELECT person_id INTO v_practitioner_person_id FROM public.members
  WHERE member_id=CASE WHEN TG_OP='DELETE'
    THEN OLD.facilitator_id ELSE NEW.facilitator_id END;
  IF v_practitioner_person_id IS NULL THEN
    IF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
  END IF;
  IF TG_OP<>'DELETE' AND NEW.assigned_by_member_id IS NOT NULL THEN
    SELECT person_id INTO v_assigned_by_person_id FROM public.members
    WHERE member_id=NEW.assigned_by_member_id;
  END IF;
  v_status := CASE WHEN TG_OP<>'DELETE'
    AND lower(COALESCE(NEW.status,'active'))='active'
    THEN 'active' ELSE 'inactive' END;

  INSERT INTO public.practitioner_storage_location_access(
    practitioner_storage_location_access_id,practitioner_person_id,
    storage_location_name,status,assigned_by_person_id,notes,
    created_at,updated_at)
  VALUES (
    CASE WHEN TG_OP='DELETE'
      THEN OLD.facilitator_storage_location_access_id
      ELSE NEW.facilitator_storage_location_access_id END,
    v_practitioner_person_id,
    CASE WHEN TG_OP='DELETE'
      THEN OLD.storage_location_name ELSE NEW.storage_location_name END,
    v_status,v_assigned_by_person_id,
    CASE WHEN TG_OP='DELETE' THEN OLD.notes ELSE NEW.notes END,
    CASE WHEN TG_OP='DELETE' THEN OLD.created_at ELSE NEW.created_at END,
    now())
  ON CONFLICT (practitioner_person_id,storage_location_name) DO UPDATE SET
    status=EXCLUDED.status,
    assigned_by_person_id=COALESCE(EXCLUDED.assigned_by_person_id,
      public.practitioner_storage_location_access.assigned_by_person_id),
    notes=COALESCE(EXCLUDED.notes,
      public.practitioner_storage_location_access.notes),updated_at=now();
  IF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END;
$$;

CREATE TRIGGER trg_issue19_sync_legacy_practitioner_storage_location
AFTER INSERT OR UPDATE OR DELETE
ON public.facilitator_storage_location_access
FOR EACH ROW EXECUTE FUNCTION
  public.issue19_sync_legacy_practitioner_storage_location();

CREATE FUNCTION public.issue19_set_practitioner_storage_location(
  p_actor_email text,p_practitioner_person_id uuid,
  p_storage_location_name text,p_active boolean,p_notes text,p_reason text
)
RETURNS uuid LANGUAGE plpgsql VOLATILE SECURITY INVOKER
SET search_path = public, pg_temp AS $$
DECLARE
  v_actor_person_id uuid;
  v_actor_member_id uuid;
  v_practitioner_member_id uuid;
  v_access_id uuid;
  v_location text := NULLIF(btrim(p_storage_location_name),'');
BEGIN
  IF NOT public.issue19_has_role(p_actor_email,'document_reviewer') THEN
    RAISE EXCEPTION 'Document reviewer permission required';
  END IF;
  IF p_practitioner_person_id IS NULL OR v_location IS NULL
     OR p_active IS NULL OR NULLIF(btrim(p_reason),'') IS NULL THEN
    RAISE EXCEPTION 'Practitioner, storage location, desired state, and reason are required';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.person_roles
      WHERE person_id=p_practitioner_person_id
        AND role_key='practitioner') THEN
    RAISE EXCEPTION 'Selected person does not hold the practitioner appointment';
  END IF;
  SELECT person_id INTO v_actor_person_id
  FROM public.person_app_accounts
  WHERE email_normalized=lower(btrim(p_actor_email)) AND status='active';

  INSERT INTO public.practitioner_storage_location_access(
    practitioner_person_id,storage_location_name,status,
    assigned_by_person_id,notes)
  VALUES (p_practitioner_person_id,v_location,
    CASE WHEN p_active THEN 'active' ELSE 'inactive' END,
    v_actor_person_id,NULLIF(btrim(p_notes),''))
  ON CONFLICT (practitioner_person_id,storage_location_name) DO UPDATE SET
    status=EXCLUDED.status,assigned_by_person_id=EXCLUDED.assigned_by_person_id,
    notes=COALESCE(EXCLUDED.notes,
      public.practitioner_storage_location_access.notes),updated_at=now()
  RETURNING practitioner_storage_location_access_id INTO v_access_id;

  -- Project the grant when both people still have member IDs so older pages
  -- and reports remain usable. Nonmember practitioners are canonical-only.
  SELECT member_id INTO v_actor_member_id FROM public.members
  WHERE person_id=v_actor_person_id
  ORDER BY (status='active') DESC,created_at DESC LIMIT 1;
  SELECT member_id INTO v_practitioner_member_id FROM public.members
  WHERE person_id=p_practitioner_person_id
  ORDER BY (status='active') DESC,created_at DESC LIMIT 1;
  IF v_practitioner_member_id IS NOT NULL THEN
    INSERT INTO public.facilitator_storage_location_access(
      facilitator_storage_location_access_id,facilitator_id,
      storage_location_name,status,assigned_by_member_id,notes)
    VALUES (v_access_id,v_practitioner_member_id,v_location,
      CASE WHEN p_active THEN 'active' ELSE 'inactive' END,
      v_actor_member_id,NULLIF(btrim(p_notes),''))
    ON CONFLICT (facilitator_id,storage_location_name) DO UPDATE SET
      status=EXCLUDED.status,
      assigned_by_member_id=COALESCE(EXCLUDED.assigned_by_member_id,
        public.facilitator_storage_location_access.assigned_by_member_id),
      notes=COALESCE(EXCLUDED.notes,
        public.facilitator_storage_location_access.notes),updated_at=now();
  END IF;

  INSERT INTO public.audit_log(actor,action,entity_type,entity_id,details)
  VALUES (lower(btrim(p_actor_email)),
    CASE WHEN p_active THEN 'practitioner_storage_location.assigned'
      ELSE 'practitioner_storage_location.removed' END,
    'practitioner_storage_location_access',v_access_id::text,
    jsonb_build_object('practitioner_person_id',p_practitioner_person_id,
      'storage_location_name',v_location,'active',p_active,
      'legacy_member_projection',v_practitioner_member_id IS NOT NULL,
      'reason',btrim(p_reason),'notes',NULLIF(btrim(p_notes),'')));
  RETURN v_access_id;
END;
$$;

-- Extend the existing guard: a practitioner appointment cannot disappear
-- while it still owns a member assignment or active storage grant.
CREATE OR REPLACE FUNCTION public.issue19_guard_practitioner_role_removal()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER
SET search_path = public, pg_temp AS $$
BEGIN
  IF OLD.role_key='practitioner' AND (
      EXISTS (SELECT 1 FROM public.member_practitioner_assignments assignment
        WHERE assignment.practitioner_person_id=OLD.person_id
          AND assignment.status='active')
      OR EXISTS (SELECT 1
        FROM public.practitioner_storage_location_access location_access
        WHERE location_access.practitioner_person_id=OLD.person_id
          AND location_access.status='active')) THEN
    RAISE EXCEPTION 'End active practitioner assignments and storage access before removing the practitioner appointment';
  END IF;
  RETURN OLD;
END;
$$;

ALTER TABLE public.releases
  ADD COLUMN practitioner_person_id uuid;
ALTER TABLE public.releases
  ADD CONSTRAINT releases_practitioner_person_id_fkey
  FOREIGN KEY (practitioner_person_id) REFERENCES public.people(person_id);
CREATE INDEX releases_practitioner_person_released_idx
  ON public.releases(practitioner_person_id,released_at DESC);

UPDATE public.releases release
SET practitioner_person_id=member.person_id
FROM public.members member
WHERE member.member_id=release.facilitator_id
  AND release.practitioner_person_id IS NULL;

CREATE FUNCTION public.issue19_sync_release_practitioner_identity()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER
SET search_path = public, pg_temp AS $$
DECLARE
  v_member_person_id uuid;
  v_legacy_member_id uuid;
BEGIN
  IF NEW.facilitator_id IS NOT NULL THEN
    SELECT person_id INTO v_member_person_id FROM public.members
    WHERE member_id=NEW.facilitator_id;
    IF NEW.practitioner_person_id IS NULL THEN
      NEW.practitioner_person_id := v_member_person_id;
    ELSIF NEW.practitioner_person_id IS DISTINCT FROM v_member_person_id THEN
      RAISE EXCEPTION 'Release practitioner person does not match legacy facilitator member';
    END IF;
  ELSIF NEW.practitioner_person_id IS NOT NULL THEN
    SELECT member_id INTO v_legacy_member_id FROM public.members
    WHERE person_id=NEW.practitioner_person_id
    ORDER BY (status='active') DESC,created_at DESC LIMIT 1;
    NEW.facilitator_id := v_legacy_member_id;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_issue19_sync_release_practitioner_identity
BEFORE INSERT OR UPDATE OF facilitator_id,practitioner_person_id
ON public.releases
FOR EACH ROW EXECUTE FUNCTION
  public.issue19_sync_release_practitioner_identity();

CREATE FUNCTION public.issue19_current_release_actor(p_actor_email text)
RETURNS TABLE (
  person_id uuid,member_id uuid,display_name text,first_name text,
  last_name text,email text,
  is_practitioner boolean,is_document_reviewer boolean,
  is_donations_reviewer boolean,practitioner_singular_label text,
  practitioner_plural_label text
)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = public, pg_temp AS $$
SELECT account.person_id,
  (SELECT m.member_id FROM public.members m
    WHERE m.person_id=account.person_id
    ORDER BY (m.status='active') DESC,m.created_at DESC LIMIT 1),
  person.display_name,person.first_name,person.last_name,account.email,
  public.issue19_has_role(p_actor_email,'practitioner'),
  public.issue19_has_role(p_actor_email,'document_reviewer'),
  public.issue19_has_role(p_actor_email,'donations_reviewer'),
  COALESCE(term.singular_label,'Practitioner'),
  COALESCE(term.plural_label,'Practitioners')
FROM public.person_app_accounts account
JOIN public.people person ON person.person_id=account.person_id
LEFT JOIN public.issue20_organization_terminology() term
  ON term.concept_key='practitioner'
WHERE account.status='active'
  AND account.email_normalized=lower(btrim(p_actor_email));
$$;

CREATE FUNCTION public.issue19_sacrament_release_members(p_actor_email text)
RETURNS TABLE (
  member_id uuid,first_name text,last_name text,email text,phone text,
  status text,is_facilitator boolean,created_at timestamptz,
  member_emails_search text,member_phones_search text,
  member_addresses_search text,member_search_text text,
  latest_release_agreement_status text,last_release_at timestamptz
)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = public, pg_temp AS $$
WITH actor AS (
  SELECT current_actor.person_id,current_actor.is_document_reviewer
  FROM public.issue19_current_release_actor(p_actor_email) current_actor
  WHERE current_actor.is_practitioner
), visible AS (
  SELECT profile.*
  FROM public.member_profiles profile CROSS JOIN actor
  WHERE profile.status='active' AND (
    actor.is_document_reviewer OR EXISTS (
      SELECT 1 FROM public.member_practitioner_assignments assignment
      WHERE assignment.member_id=profile.member_id
        AND assignment.practitioner_person_id=actor.person_id
        AND assignment.status='active'))
)
SELECT v.member_id,v.first_name,v.last_name,v.email,v.phone,v.status,
  EXISTS (SELECT 1 FROM public.person_roles role
    WHERE role.person_id=v.person_id AND role.role_key='practitioner'),
  v.created_at,
  COALESCE((SELECT string_agg(DISTINCT e.email,' ')
    FROM public.member_emails e WHERE e.member_id=v.member_id
      AND COALESCE(e.status,'active')='active'),'')::text,
  COALESCE((SELECT string_agg(DISTINCT p.phone,' ')
    FROM public.member_phones p WHERE p.member_id=v.member_id
      AND COALESCE(p.status,'active')='active'),'')::text,
  COALESCE((SELECT string_agg(DISTINCT concat_ws(' ',a.address_1,a.address_2,
      a.city,a.state,a.postal_code,a.country),' ')
    FROM public.member_addresses a WHERE a.member_id=v.member_id
      AND COALESCE(a.status,'active')='active'),'')::text,
  concat_ws(' ',v.member_id::text,v.first_name,v.last_name,v.email,v.phone,
    COALESCE((SELECT string_agg(DISTINCT e.email,' ')
      FROM public.member_emails e WHERE e.member_id=v.member_id
        AND COALESCE(e.status,'active')='active'),''),
    COALESCE((SELECT string_agg(DISTINCT p.phone,' ')
      FROM public.member_phones p WHERE p.member_id=v.member_id
        AND COALESCE(p.status,'active')='active'),''))::text,
  (SELECT agreement.agreement_status
    FROM public.issue19_sacrament_release_agreement(v.member_id) agreement
    LIMIT 1),
  (SELECT max(release.released_at) FROM public.releases release
    WHERE release.member_id=v.member_id)
FROM visible v
ORDER BY v.last_name NULLS LAST,v.first_name NULLS LAST,v.created_at DESC;
$$;

CREATE FUNCTION public.issue19_release_practitioners(
  p_actor_email text,p_member_id uuid
)
RETURNS TABLE (
  practitioner_person_id uuid,display_name text,first_name text,last_name text,
  account_email text,legacy_member_id uuid,is_current_actor boolean
)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = public, pg_temp AS $$
WITH actor AS (
  SELECT current_actor.person_id,current_actor.is_document_reviewer
  FROM public.issue19_current_release_actor(p_actor_email) current_actor
  WHERE current_actor.is_practitioner
)
SELECT person.person_id,person.display_name,person.first_name,person.last_name,
  account.email,
  (SELECT member.member_id FROM public.members member
    WHERE member.person_id=person.person_id
    ORDER BY (member.status='active') DESC,member.created_at DESC LIMIT 1),
  person.person_id=actor.person_id
FROM actor
JOIN public.member_practitioner_assignments assignment
  ON assignment.member_id=p_member_id AND assignment.status='active'
JOIN public.person_roles role
  ON role.person_id=assignment.practitioner_person_id
  AND role.role_key='practitioner'
JOIN public.people person
  ON person.person_id=assignment.practitioner_person_id
LEFT JOIN public.person_app_accounts account
  ON account.person_id=person.person_id AND account.status='active'
WHERE actor.is_document_reviewer
   OR person.person_id=actor.person_id
ORDER BY (person.person_id=actor.person_id) DESC,person.display_name;
$$;

CREATE FUNCTION public.issue19_release_storage_locations(
  p_actor_email text,p_member_id uuid,p_practitioner_person_id uuid
)
RETURNS TABLE (storage_location_name text)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = public, pg_temp AS $$
SELECT DISTINCT access.storage_location_name
FROM public.practitioner_storage_location_access access
WHERE access.practitioner_person_id=p_practitioner_person_id
  AND access.status='active'
  AND EXISTS (SELECT 1 FROM public.issue19_release_practitioners(
    p_actor_email,p_member_id) available
    WHERE available.practitioner_person_id=p_practitioner_person_id)
ORDER BY access.storage_location_name;
$$;

CREATE FUNCTION public.issue19_record_sacrament_release(
  p_actor_email text,p_member_id uuid,p_practitioner_person_id uuid,
  p_member_agreement_id uuid,p_mushroomprocess_product_id text,
  p_item_name text,p_quantity numeric,p_unit text,p_net_weight_g integer,
  p_strain text,p_storage_location_name text,p_notes text,
  p_override_reason text DEFAULT NULL
)
RETURNS TABLE (
  release_id uuid,practitioner_person_id uuid,facilitator_id uuid
)
LANGUAGE plpgsql VOLATILE SECURITY INVOKER
SET search_path = public, pg_temp AS $$
DECLARE
  v_actor record;
  v_legacy_member_id uuid;
  v_release_id uuid;
  v_location text := NULLIF(btrim(p_storage_location_name),'');
  v_override_reason text := NULLIF(btrim(p_override_reason),'');
BEGIN
  SELECT * INTO v_actor FROM public.issue19_current_release_actor(p_actor_email);
  IF v_actor.person_id IS NULL OR NOT v_actor.is_practitioner THEN
    RAISE EXCEPTION 'Practitioner appointment required to record a sacrament release';
  END IF;
  IF p_member_id IS NULL OR p_practitioner_person_id IS NULL
     OR NULLIF(btrim(p_mushroomprocess_product_id),'') IS NULL
     OR v_location IS NULL OR p_quantity IS NULL OR p_quantity<=0 THEN
    RAISE EXCEPTION 'Member, practitioner, product, quantity, and storage location are required';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.members
      WHERE member_id=p_member_id AND status='active') THEN
    RAISE EXCEPTION 'An active membership is required for sacrament release';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.issue19_release_practitioners(
      p_actor_email,p_member_id) available
      WHERE available.practitioner_person_id=p_practitioner_person_id) THEN
    RAISE EXCEPTION 'Selected practitioner is not available for this member';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.issue19_release_storage_locations(
      p_actor_email,p_member_id,p_practitioner_person_id) location_access
      WHERE lower(btrim(location_access.storage_location_name))=
        lower(v_location)) THEN
    RAISE EXCEPTION 'Selected practitioner does not have access to this storage location';
  END IF;

  IF p_member_agreement_id IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1
        FROM public.issue19_sacrament_release_agreement(p_member_id) agreement
        WHERE agreement.member_agreement_id=p_member_agreement_id) THEN
      RAISE EXCEPTION 'Selected agreement does not authorize sacrament release';
    END IF;
  ELSIF NOT v_actor.is_document_reviewer OR v_override_reason IS NULL THEN
    RAISE EXCEPTION 'A signed sacrament agreement or documented reviewer override is required';
  END IF;

  SELECT member_id INTO v_legacy_member_id FROM public.members
  WHERE person_id=p_practitioner_person_id
  ORDER BY (status='active') DESC,created_at DESC LIMIT 1;

  INSERT INTO public.releases(
    member_id,release_type,member_agreement_id,
    mushroomprocess_product_id,item_name,quantity,unit,net_weight_g,strain,
    practitioner_person_id,facilitator_id,storage_location_name,
    released_by,notes)
  VALUES (p_member_id,'sacrament_release',p_member_agreement_id,
    btrim(p_mushroomprocess_product_id),NULLIF(btrim(p_item_name),''),
    p_quantity,COALESCE(NULLIF(btrim(p_unit),''),'g'),p_net_weight_g,
    NULLIF(btrim(p_strain),''),p_practitioner_person_id,v_legacy_member_id,
    v_location,lower(btrim(p_actor_email)),NULLIF(btrim(p_notes),''))
  RETURNING public.releases.release_id INTO v_release_id;

  INSERT INTO public.audit_log(actor,action,entity_type,entity_id,details)
  VALUES (lower(btrim(p_actor_email)),'release.issued','release',
    v_release_id::text,jsonb_build_object(
      'member_id',p_member_id,'release_type','sacrament_release',
      'member_agreement_id',p_member_agreement_id,
      'practitioner_person_id',p_practitioner_person_id,
      'legacy_facilitator_member_id',v_legacy_member_id,
      'mushroomprocess_product_id',btrim(p_mushroomprocess_product_id),
      'storage_location_name',v_location,
      'agreement_override',p_member_agreement_id IS NULL,
      'override_reason',v_override_reason));

  RETURN QUERY SELECT v_release_id,p_practitioner_person_id,v_legacy_member_id;
END;
$$;

COMMENT ON TABLE public.practitioner_storage_location_access IS
  'Canonical person-based storage access for a practitioner appointment; membership is not required.';
COMMENT ON COLUMN public.releases.practitioner_person_id IS
  'Canonical practitioner responsible for the tangible transfer; facilitator_id is a compatibility projection.';
COMMENT ON FUNCTION public.issue19_record_sacrament_release(text,uuid,uuid,uuid,text,text,numeric,text,integer,text,text,text,text) IS
  'Records a guarded sacrament transfer using canonical practitioner identity and person-owned storage access.';
COMMIT;
