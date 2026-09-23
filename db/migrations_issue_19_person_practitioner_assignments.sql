-- Issue #19: assign practitioners to memberships by canonical person identity.
-- Apply after migrations_issue_19_member_address_profiles.sql; run once.
\set ON_ERROR_STOP on
BEGIN;

DO $$ BEGIN
  IF to_regprocedure('public.issue19_person_member_operations_state(text,uuid)') IS NULL
     OR to_regprocedure('public.issue19_directory_entries(text)') IS NULL
     OR to_regclass('public.person_roles') IS NULL
     OR to_regclass('public.member_facilitators') IS NULL THEN
    RAISE EXCEPTION 'Apply the Issue #19 identity, role, and member-operation migrations first';
  END IF;
END $$;

-- Keep the legacy backfill and trigger installation atomic with respect to
-- assignment and appointment changes during this one-time migration.
LOCK TABLE public.member_facilitators IN SHARE ROW EXCLUSIVE MODE;
LOCK TABLE public.person_roles IN SHARE ROW EXCLUSIVE MODE;

CREATE TABLE public.member_practitioner_assignments (
  member_practitioner_assignment_id uuid PRIMARY KEY
    DEFAULT public.uuid_generate_v4(),
  member_id uuid NOT NULL REFERENCES public.members(member_id),
  practitioner_person_id uuid NOT NULL REFERENCES public.people(person_id),
  assigned_by_person_id uuid REFERENCES public.people(person_id),
  status text NOT NULL DEFAULT 'active'
    CHECK (status IN ('active','inactive')),
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  ended_at timestamptz,
  ended_by_person_id uuid REFERENCES public.people(person_id),
  end_reason text,
  CONSTRAINT member_practitioner_assignments_unique
    UNIQUE (member_id,practitioner_person_id),
  CONSTRAINT member_practitioner_assignments_end_check CHECK (
    (status='active' AND ended_at IS NULL)
    OR (status='inactive' AND ended_at IS NOT NULL)
  )
);

CREATE INDEX member_practitioner_assignments_member_status_idx
  ON public.member_practitioner_assignments(member_id,status);
CREATE INDEX member_practitioner_assignments_person_status_idx
  ON public.member_practitioner_assignments(practitioner_person_id,status);

CREATE TRIGGER trg_member_practitioner_assignments_updated_at
BEFORE UPDATE ON public.member_practitioner_assignments
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Preserve every legacy assignment, including inactive history. The legacy
-- facilitator member is resolved to the person who owns that membership.
INSERT INTO public.member_practitioner_assignments(
  member_practitioner_assignment_id,member_id,practitioner_person_id,
  assigned_by_person_id,status,notes,created_at,updated_at,ended_at,end_reason)
SELECT legacy.member_facilitator_id,legacy.member_id,practitioner.person_id,
  assigner.person_id,
  CASE WHEN lower(COALESCE(legacy.status,'active'))='active'
    THEN 'active' ELSE 'inactive' END,
  legacy.notes,legacy.created_at,legacy.updated_at,
  CASE WHEN lower(COALESCE(legacy.status,'active'))='active'
    THEN NULL ELSE legacy.updated_at END,
  CASE WHEN lower(COALESCE(legacy.status,'active'))='active'
    THEN NULL ELSE 'Imported inactive legacy facilitator assignment' END
FROM public.member_facilitators legacy
JOIN public.members practitioner
  ON practitioner.member_id=legacy.facilitator_id
LEFT JOIN public.members assigner
  ON assigner.member_id=legacy.assigned_by_member_id
ON CONFLICT (member_id,practitioner_person_id) DO UPDATE SET
  status=EXCLUDED.status,
  notes=COALESCE(EXCLUDED.notes,
    public.member_practitioner_assignments.notes),
  updated_at=GREATEST(public.member_practitioner_assignments.updated_at,
    EXCLUDED.updated_at),
  ended_at=EXCLUDED.ended_at,
  end_reason=EXCLUDED.end_reason;

CREATE FUNCTION public.issue19_guard_practitioner_role_removal()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER
SET search_path = public, pg_temp AS $$
BEGIN
  IF OLD.role_key='practitioner' AND EXISTS (
      SELECT 1 FROM public.member_practitioner_assignments assignment
      WHERE assignment.practitioner_person_id=OLD.person_id
        AND assignment.status='active') THEN
    RAISE EXCEPTION 'End active practitioner assignments before removing the practitioner appointment';
  END IF;
  RETURN OLD;
END;
$$;

CREATE TRIGGER trg_issue19_guard_practitioner_role_removal
BEFORE DELETE ON public.person_roles
FOR EACH ROW EXECUTE FUNCTION public.issue19_guard_practitioner_role_removal();

-- Old Appsmith pages still write member_facilitators. Mirror those changes
-- into the canonical person assignment until those pages are retired.
CREATE FUNCTION public.issue19_sync_legacy_member_facilitator()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER
SET search_path = public, pg_temp AS $$
DECLARE
  v_practitioner_person_id uuid;
  v_assigned_by_person_id uuid;
  v_status text;
BEGIN
  SELECT person_id INTO v_practitioner_person_id
  FROM public.members
  WHERE member_id=CASE WHEN TG_OP='DELETE'
    THEN OLD.facilitator_id ELSE NEW.facilitator_id END;
  IF v_practitioner_person_id IS NULL THEN
    IF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
  END IF;

  IF TG_OP <> 'DELETE' AND NEW.assigned_by_member_id IS NOT NULL THEN
    SELECT person_id INTO v_assigned_by_person_id
    FROM public.members WHERE member_id=NEW.assigned_by_member_id;
  END IF;
  v_status := CASE
    WHEN TG_OP <> 'DELETE'
      AND lower(COALESCE(NEW.status,'active'))='active' THEN 'active'
    ELSE 'inactive' END;

  INSERT INTO public.member_practitioner_assignments(
    member_practitioner_assignment_id,member_id,practitioner_person_id,
    assigned_by_person_id,status,notes,created_at,updated_at,
    ended_at,end_reason)
  VALUES (
    CASE WHEN TG_OP='DELETE' THEN OLD.member_facilitator_id
      ELSE NEW.member_facilitator_id END,
    CASE WHEN TG_OP='DELETE' THEN OLD.member_id ELSE NEW.member_id END,
    v_practitioner_person_id,
    v_assigned_by_person_id,v_status,
    CASE WHEN TG_OP='DELETE' THEN OLD.notes ELSE NEW.notes END,
    CASE WHEN TG_OP='DELETE' THEN OLD.created_at ELSE NEW.created_at END,
    now(),CASE WHEN v_status='inactive' THEN now() END,
    CASE WHEN TG_OP='DELETE' THEN 'Legacy facilitator assignment deleted'
      WHEN v_status='inactive' THEN 'Legacy facilitator assignment ended'
    END)
  ON CONFLICT (member_id,practitioner_person_id) DO UPDATE SET
    assigned_by_person_id=COALESCE(EXCLUDED.assigned_by_person_id,
      public.member_practitioner_assignments.assigned_by_person_id),
    status=EXCLUDED.status,notes=EXCLUDED.notes,updated_at=now(),
    ended_at=CASE WHEN EXCLUDED.status='active' THEN NULL ELSE COALESCE(
      public.member_practitioner_assignments.ended_at,EXCLUDED.ended_at) END,
    end_reason=CASE WHEN EXCLUDED.status='active' THEN NULL ELSE COALESCE(
      public.member_practitioner_assignments.end_reason,EXCLUDED.end_reason) END,
    ended_by_person_id=CASE WHEN EXCLUDED.status='active' THEN NULL ELSE
      public.member_practitioner_assignments.ended_by_person_id END;
  IF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END;
$$;

CREATE TRIGGER trg_issue19_sync_legacy_member_facilitator
AFTER INSERT OR UPDATE OR DELETE ON public.member_facilitators
FOR EACH ROW EXECUTE FUNCTION public.issue19_sync_legacy_member_facilitator();

CREATE OR REPLACE FUNCTION public.issue19_person_member_operations_state(
  p_actor_email text,p_person_id uuid
)
RETURNS TABLE (member_id uuid,membership_status text,
  can_view boolean,can_manage boolean)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = public, pg_temp AS $$
WITH actor AS (
  SELECT account.person_id,
    public.issue19_has_role(p_actor_email,'document_reviewer') AS can_review,
    public.issue19_has_role(p_actor_email,'practitioner') AS is_practitioner
  FROM public.person_app_accounts account
  WHERE account.status='active'
    AND account.email_normalized=lower(btrim(p_actor_email))
), target AS (
  SELECT m.member_id,m.status
  FROM public.members m WHERE m.person_id=p_person_id
  ORDER BY (m.status='active') DESC,m.created_at DESC LIMIT 1
)
SELECT target.member_id,target.status,
  (actor.can_review OR (actor.is_practitioner AND EXISTS (
    SELECT 1 FROM public.member_practitioner_assignments assignment
    WHERE assignment.member_id=target.member_id
      AND assignment.practitioner_person_id=actor.person_id
      AND assignment.status='active'))),
  actor.can_review
FROM target CROSS JOIN actor;
$$;

DROP FUNCTION public.issue19_person_practitioner_assignments(text,uuid);
CREATE FUNCTION public.issue19_person_practitioner_assignments(
  p_actor_email text,p_person_id uuid
)
RETURNS TABLE (
  member_id uuid,membership_status text,
  member_facilitator_id uuid,member_practitioner_assignment_id uuid,
  practitioner_person_id uuid,
  practitioner_name text,practitioner_email text,assignment_status text,
  assigned_at timestamptz,updated_at timestamptz,notes text,
  ended_at timestamptz,end_reason text
)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = public, pg_temp AS $$
SELECT state.member_id,state.membership_status,
  assignment.member_practitioner_assignment_id,
  assignment.member_practitioner_assignment_id,
  assignment.practitioner_person_id,practitioner.display_name,
  account.email,assignment.status,assignment.created_at,
  assignment.updated_at,assignment.notes,assignment.ended_at,
  assignment.end_reason
FROM public.issue19_person_member_operations_state(
  p_actor_email,p_person_id) state
JOIN public.member_practitioner_assignments assignment
  ON assignment.member_id=state.member_id
JOIN public.people practitioner
  ON practitioner.person_id=assignment.practitioner_person_id
LEFT JOIN public.person_app_accounts account
  ON account.person_id=practitioner.person_id AND account.status='active'
WHERE state.can_view
ORDER BY (assignment.status='active') DESC,
  practitioner.display_name,assignment.created_at;
$$;

CREATE FUNCTION public.issue19_available_member_practitioners(
  p_actor_email text,p_person_id uuid
)
RETURNS TABLE (
  practitioner_person_id uuid,display_name text,account_email text,
  has_active_membership boolean,already_assigned boolean
)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = public, pg_temp AS $$
SELECT practitioner.person_id,practitioner.display_name,account.email,
  EXISTS (SELECT 1 FROM public.members m
    WHERE m.person_id=practitioner.person_id AND m.status='active'),
  EXISTS (SELECT 1 FROM public.member_practitioner_assignments assignment
    WHERE assignment.member_id=state.member_id
      AND assignment.practitioner_person_id=practitioner.person_id
      AND assignment.status='active')
FROM public.issue19_person_member_operations_state(
  p_actor_email,p_person_id) state
JOIN public.person_roles role ON role.role_key='practitioner'
JOIN public.people practitioner ON practitioner.person_id=role.person_id
LEFT JOIN public.person_app_accounts account
  ON account.person_id=practitioner.person_id AND account.status='active'
WHERE state.can_manage AND state.membership_status='active'
ORDER BY practitioner.display_name,practitioner.person_id;
$$;

CREATE FUNCTION public.issue19_assign_member_practitioner(
  p_actor_email text,p_person_id uuid,p_practitioner_person_id uuid,
  p_notes text,p_reason text
)
RETURNS uuid LANGUAGE plpgsql VOLATILE SECURITY INVOKER
SET search_path = public, pg_temp AS $$
DECLARE
  v_actor_person_id uuid;
  v_actor_member_id uuid;
  v_member_id uuid;
  v_practitioner_member_id uuid;
  v_assignment_id uuid;
BEGIN
  IF NOT public.issue19_has_role(p_actor_email,'document_reviewer') THEN
    RAISE EXCEPTION 'Document reviewer permission required';
  END IF;
  IF p_person_id IS NULL OR p_practitioner_person_id IS NULL
     OR NULLIF(btrim(p_reason),'') IS NULL THEN
    RAISE EXCEPTION 'Select a member and practitioner and enter a reason';
  END IF;
  SELECT account.person_id INTO v_actor_person_id
  FROM public.person_app_accounts account
  WHERE account.status='active'
    AND account.email_normalized=lower(btrim(p_actor_email));
  SELECT m.member_id INTO v_actor_member_id FROM public.members m
  WHERE m.person_id=v_actor_person_id AND m.status='active'
  ORDER BY m.created_at DESC LIMIT 1;
  SELECT m.member_id INTO v_member_id FROM public.members m
  WHERE m.person_id=p_person_id AND m.status='active' FOR UPDATE;
  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'This person has no active membership';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.person_roles role
      WHERE role.person_id=p_practitioner_person_id
        AND role.role_key='practitioner') THEN
    RAISE EXCEPTION 'Selected person does not hold the practitioner appointment';
  END IF;

  INSERT INTO public.member_practitioner_assignments(
    member_id,practitioner_person_id,assigned_by_person_id,status,notes)
  VALUES (v_member_id,p_practitioner_person_id,v_actor_person_id,'active',
    NULLIF(btrim(p_notes),''))
  ON CONFLICT (member_id,practitioner_person_id) DO UPDATE SET
    assigned_by_person_id=EXCLUDED.assigned_by_person_id,status='active',
    notes=COALESCE(EXCLUDED.notes,
      public.member_practitioner_assignments.notes),
    ended_at=NULL,ended_by_person_id=NULL,end_reason=NULL,updated_at=now()
  RETURNING member_practitioner_assignment_id INTO v_assignment_id;

  -- Compatibility projection for legacy agreement/release pages. A person
  -- without membership remains a valid canonical practitioner assignment.
  SELECT m.member_id INTO v_practitioner_member_id FROM public.members m
  WHERE m.person_id=p_practitioner_person_id AND m.status='active'
  ORDER BY m.created_at DESC LIMIT 1;
  IF v_practitioner_member_id IS NOT NULL THEN
    INSERT INTO public.member_facilitators(
      member_id,facilitator_id,assigned_by_member_id,status,notes)
    VALUES (v_member_id,v_practitioner_member_id,v_actor_member_id,'active',
      NULLIF(btrim(p_notes),''))
    ON CONFLICT (member_id,facilitator_id) DO UPDATE SET
      assigned_by_member_id=EXCLUDED.assigned_by_member_id,status='active',
      notes=COALESCE(EXCLUDED.notes,public.member_facilitators.notes),
      updated_at=now();
  END IF;

  INSERT INTO public.audit_log(actor,action,entity_type,entity_id,details)
  VALUES (lower(btrim(p_actor_email)),'member_practitioner.assigned',
    'member_practitioner_assignment',v_assignment_id::text,
    jsonb_build_object('member_id',v_member_id,'member_person_id',p_person_id,
      'practitioner_person_id',p_practitioner_person_id,
      'legacy_member_projection',v_practitioner_member_id IS NOT NULL,
      'reason',btrim(p_reason),'notes',NULLIF(btrim(p_notes),'')));
  RETURN v_assignment_id;
END;
$$;

CREATE FUNCTION public.issue19_end_member_practitioner(
  p_actor_email text,p_person_id uuid,p_assignment_id uuid,p_reason text
)
RETURNS uuid LANGUAGE plpgsql VOLATILE SECURITY INVOKER
SET search_path = public, pg_temp AS $$
DECLARE
  v_actor_person_id uuid;
  v_member_id uuid;
  v_practitioner_person_id uuid;
  v_practitioner_member_id uuid;
BEGIN
  IF NOT public.issue19_has_role(p_actor_email,'document_reviewer') THEN
    RAISE EXCEPTION 'Document reviewer permission required';
  END IF;
  IF p_person_id IS NULL OR p_assignment_id IS NULL
     OR NULLIF(btrim(p_reason),'') IS NULL THEN
    RAISE EXCEPTION 'Select an active assignment and enter a reason';
  END IF;
  SELECT account.person_id INTO v_actor_person_id
  FROM public.person_app_accounts account
  WHERE account.status='active'
    AND account.email_normalized=lower(btrim(p_actor_email));
  SELECT assignment.member_id,assignment.practitioner_person_id
    INTO v_member_id,v_practitioner_person_id
  FROM public.member_practitioner_assignments assignment
  JOIN public.members member ON member.member_id=assignment.member_id
  WHERE assignment.member_practitioner_assignment_id=p_assignment_id
    AND member.person_id=p_person_id AND assignment.status='active'
  FOR UPDATE OF assignment;
  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'Active practitioner assignment not found for this member';
  END IF;

  UPDATE public.member_practitioner_assignments SET status='inactive',
    ended_at=now(),ended_by_person_id=v_actor_person_id,
    end_reason=btrim(p_reason),updated_at=now()
  WHERE member_practitioner_assignment_id=p_assignment_id;

  SELECT m.member_id INTO v_practitioner_member_id FROM public.members m
  WHERE m.person_id=v_practitioner_person_id
  ORDER BY (m.status='active') DESC,m.created_at DESC LIMIT 1;
  IF v_practitioner_member_id IS NOT NULL THEN
    UPDATE public.member_facilitators SET status='inactive',updated_at=now(),
      notes=concat_ws(E'\n',NULLIF(notes,''),
        'Ended from Individual Profile: ' || btrim(p_reason))
    WHERE member_id=v_member_id AND facilitator_id=v_practitioner_member_id
      AND status='active';
  END IF;

  INSERT INTO public.audit_log(actor,action,entity_type,entity_id,details)
  VALUES (lower(btrim(p_actor_email)),'member_practitioner.ended',
    'member_practitioner_assignment',p_assignment_id::text,
    jsonb_build_object('member_id',v_member_id,'member_person_id',p_person_id,
      'practitioner_person_id',v_practitioner_person_id,
      'reason',btrim(p_reason)));
  RETURN p_assignment_id;
END;
$$;

-- Directory scope now follows canonical person assignments. Practitioners do
-- not need membership merely to see the people assigned to them.
CREATE OR REPLACE FUNCTION public.issue19_directory_entries(p_actor_email text)
RETURNS TABLE (
  party_kind text,party_id uuid,display_name text,member_id uuid,
  contributor_id uuid,membership_status text,contributor_status text,
  email text,phone text,created_at timestamptz,
  can_view_membership boolean,can_view_contributions boolean
)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = public, pg_temp AS $$
WITH actor AS (
  SELECT account.person_id,
    public.issue19_has_role(p_actor_email,'document_reviewer') AS can_member,
    public.issue19_has_role(p_actor_email,'donations_reviewer') AS can_donor,
    public.issue19_has_role(p_actor_email,'directory_manager') AS can_manage,
    public.issue19_has_role(p_actor_email,'practitioner') AS is_practitioner
  FROM public.person_app_accounts account
  WHERE account.status='active'
    AND account.email_normalized=lower(btrim(p_actor_email))
), people_scope AS (
  SELECT p.person_id,p.display_name,p.created_at,
    m.member_id AS actual_member_id,c.contributor_id AS actual_contributor_id,
    m.status AS actual_membership_status,c.status AS actual_contributor_status,
    (m.member_id IS NOT NULL AND
      (a.can_member OR a.can_manage OR p.person_id=a.person_id
       OR (a.is_practitioner AND EXISTS (
        SELECT 1 FROM public.member_practitioner_assignments assignment
        WHERE assignment.member_id=m.member_id
          AND assignment.practitioner_person_id=a.person_id
          AND assignment.status='active')))) AS may_view_member,
    (c.contributor_id IS NOT NULL AND (
      (c.status='active' AND (a.can_donor OR a.can_manage
       OR (a.is_practitioner AND EXISTS (
        SELECT 1 FROM public.contributor_member_links link
        JOIN public.member_practitioner_assignments assignment
          ON assignment.member_id=link.member_id
        WHERE link.contributor_id=c.contributor_id AND link.status='active'
          AND assignment.practitioner_person_id=a.person_id
          AND assignment.status='active'))))
      OR (c.status='archived' AND a.can_donor AND a.can_manage)
    )) AS may_view_donor,
    (a.can_manage OR a.person_id=p.person_id) AS may_view_person
  FROM public.people p CROSS JOIN actor a
  LEFT JOIN public.members m ON m.person_id=p.person_id AND m.status='active'
  LEFT JOIN public.contributors c ON c.person_id=p.person_id
    AND c.status IN ('active','archived')
), org_scope AS (
  SELECT o.organization_id,o.organization_name,o.created_at,
    c.contributor_id,c.status AS contributor_status
  FROM public.organizations o
  JOIN public.contributors c ON c.organization_id=o.organization_id
    AND c.status IN ('active','archived')
  CROSS JOIN actor a
  WHERE (c.status='active' AND (a.can_donor OR a.can_manage))
     OR (c.status='archived' AND a.can_donor AND a.can_manage)
), visible AS (
  SELECT 'individual'::text AS kind,s.person_id AS id,
    s.display_name AS name,s.created_at,
    CASE WHEN s.may_view_member THEN s.actual_member_id END AS member_id,
    CASE WHEN s.may_view_donor THEN s.actual_contributor_id END AS contributor_id,
    CASE WHEN s.may_view_member THEN s.actual_membership_status END AS membership_status,
    CASE WHEN s.may_view_donor THEN s.actual_contributor_status END AS contributor_status,
    s.may_view_member AS can_member,s.may_view_donor AS can_donor
  FROM people_scope s
  WHERE s.may_view_member OR s.may_view_donor OR s.may_view_person
  UNION ALL
  SELECT 'organization',s.organization_id,s.organization_name,s.created_at,
    NULL::uuid,s.contributor_id,NULL::text,s.contributor_status,false,true
  FROM org_scope s
)
SELECT v.kind,v.id,v.name,v.member_id,v.contributor_id,
  v.membership_status,v.contributor_status,
  (SELECT pc.contact_value FROM public.party_contacts pc
    JOIN public.party_contact_sources ps
      ON ps.party_contact_id=pc.party_contact_id
    WHERE pc.status='active' AND pc.contact_kind='email'
      AND ((v.kind='individual' AND pc.person_id=v.id)
        OR (v.kind='organization' AND pc.organization_id=v.id))
      AND ps.status='active'
      AND ((ps.source_table='member_emails' AND v.can_member)
        OR (ps.source_table='contributor_emails' AND v.can_donor))
    ORDER BY ps.is_primary DESC,ps.created_at,ps.source_id LIMIT 1),
  (SELECT pc.contact_value FROM public.party_contacts pc
    JOIN public.party_contact_sources ps
      ON ps.party_contact_id=pc.party_contact_id
    WHERE pc.status='active' AND pc.contact_kind='phone'
      AND ((v.kind='individual' AND pc.person_id=v.id)
        OR (v.kind='organization' AND pc.organization_id=v.id))
      AND ps.status='active'
      AND ((ps.source_table='member_phones' AND v.can_member)
        OR (ps.source_table='contributor_phones' AND v.can_donor))
    ORDER BY ps.is_primary DESC,ps.created_at,ps.source_id LIMIT 1),
  v.created_at,v.can_member,v.can_donor
FROM visible v;
$$;

COMMENT ON TABLE public.member_practitioner_assignments IS
  'Canonical person-based practitioner assignment to a membership; practitioner membership is not required.';
COMMENT ON FUNCTION public.issue19_assign_member_practitioner(text,uuid,uuid,text,text) IS
  'Assigns a person holding the practitioner role to an active membership and creates a legacy projection when possible.';
COMMENT ON FUNCTION public.issue19_end_member_practitioner(text,uuid,uuid,text) IS
  'Ends a canonical practitioner assignment without removing the practitioner role or changing membership/contributor capacity.';
COMMIT;
