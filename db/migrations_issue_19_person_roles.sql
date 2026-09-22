-- Issue #19: person appointments and Appsmith permissions independent of membership.
-- Apply after migrations_issue_19_directory_read.sql. Run once.
\set ON_ERROR_STOP on
BEGIN;

DO $$ BEGIN
  IF to_regprocedure('public.issue19_directory_entries(text)') IS NULL
     OR to_regclass('public.people') IS NULL THEN
    RAISE EXCEPTION 'Apply the Issue #19 directory migration first';
  END IF;
END $$;

-- An account belongs to exactly one person. Never infer the owner of a shared
-- household email: ambiguous existing facilitator accounts abort the migration.
DO $$ BEGIN
  IF EXISTS (
    SELECT 1 FROM public.members
    WHERE status = 'active'
      AND (is_facilitator OR is_document_reviewer OR is_donations_reviewer)
      AND NULLIF(btrim(email), '') IS NOT NULL
    GROUP BY lower(btrim(email)) HAVING count(DISTINCT person_id) > 1
  ) THEN
    RAISE EXCEPTION 'Shared active facilitator email: resolve the account owner before applying person roles';
  END IF;
END $$;

CREATE TABLE public.person_app_accounts (
  person_id uuid PRIMARY KEY REFERENCES public.people(person_id),
  email text NOT NULL,
  email_normalized text GENERATED ALWAYS AS (lower(btrim(email))) STORED,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'disabled')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (NULLIF(btrim(email), '') IS NOT NULL)
);
CREATE UNIQUE INDEX uq_person_app_accounts_email
  ON public.person_app_accounts(email_normalized);

-- Appointment roles describe a person; permission roles authorize Appsmith
-- tasks. directory_manager is deliberately never seeded automatically.
CREATE TABLE public.person_roles (
  person_id uuid NOT NULL REFERENCES public.people(person_id),
  role_key text NOT NULL CHECK (role_key IN
    ('practitioner', 'document_reviewer', 'donations_reviewer',
     'directory_manager', 'minister')),
  assigned_at timestamptz NOT NULL DEFAULT now(),
  assigned_by text NOT NULL,
  PRIMARY KEY (person_id, role_key)
);
CREATE INDEX person_roles_role_key_idx ON public.person_roles(role_key, person_id);

INSERT INTO public.person_app_accounts (person_id, email)
SELECT DISTINCT ON (m.person_id) m.person_id, m.email
FROM public.members m
WHERE m.status = 'active'
  AND (m.is_facilitator OR m.is_document_reviewer OR m.is_donations_reviewer)
  AND NULLIF(btrim(m.email), '') IS NOT NULL
ORDER BY m.person_id, m.updated_at DESC;

INSERT INTO public.person_roles (person_id, role_key, assigned_by)
SELECT m.person_id, role.role_key, 'issue19_migration'
FROM public.members m
CROSS JOIN LATERAL (VALUES
  ('practitioner', m.is_facilitator),
  ('document_reviewer', m.is_document_reviewer),
  ('donations_reviewer', m.is_donations_reviewer)
) AS role(role_key, enabled)
WHERE m.status = 'active' AND role.enabled;

CREATE FUNCTION public.issue19_has_role(p_actor_email text, p_role_key text)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER
SET search_path = public, pg_temp AS $$
SELECT EXISTS (
  SELECT 1 FROM public.person_app_accounts account
  JOIN public.person_roles role ON role.person_id = account.person_id
  WHERE account.email_normalized = lower(btrim(p_actor_email))
    AND account.status = 'active' AND role.role_key = p_role_key
);
$$;

CREATE FUNCTION public.issue19_profile_roles(p_actor_email text, p_person_id uuid)
RETURNS TABLE (role_key text) LANGUAGE sql STABLE SECURITY INVOKER
SET search_path = public, pg_temp AS $$
SELECT role.role_key
FROM public.person_roles role
WHERE role.person_id = p_person_id
  AND EXISTS (
    SELECT 1 FROM public.issue19_directory_entries(p_actor_email) d
    WHERE d.party_kind = 'individual' AND d.party_id = p_person_id
  )
  AND (public.issue19_has_role(p_actor_email, 'directory_manager')
    OR (role.role_key = 'practitioner' AND
        public.issue19_has_role(p_actor_email, 'document_reviewer'))
    OR (role.role_key = 'donations_reviewer' AND
        public.issue19_has_role(p_actor_email, 'donations_reviewer')));
$$;

CREATE FUNCTION public.issue19_profile_account(p_actor_email text, p_person_id uuid)
RETURNS TABLE (email text, status text)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = public, pg_temp AS $$
SELECT account.email, account.status
FROM public.person_app_accounts account
WHERE account.person_id = p_person_id
  AND public.issue19_has_role(p_actor_email, 'directory_manager');
$$;

CREATE FUNCTION public.issue19_set_person_app_account(
  p_actor_email text, p_person_id uuid, p_email text, p_reason text
)
RETURNS boolean LANGUAGE plpgsql SECURITY INVOKER
SET search_path = public, pg_temp AS $$
DECLARE v_previous text;
BEGIN
  IF NOT public.issue19_has_role(p_actor_email, 'directory_manager') THEN
    RAISE EXCEPTION 'Directory manager permission required';
  END IF;
  IF NULLIF(btrim(p_email), '') IS NULL OR position('@' in btrim(p_email)) < 2
     OR NULLIF(btrim(p_reason), '') IS NULL THEN
    RAISE EXCEPTION 'Account email and reason required';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.people WHERE person_id = p_person_id) THEN
    RAISE EXCEPTION 'Person not found';
  END IF;
  SELECT email INTO v_previous FROM public.person_app_accounts
  WHERE person_id = p_person_id;
  IF v_previous IS NOT NULL
     AND lower(btrim(v_previous)) = lower(btrim(p_actor_email)) THEN
    RAISE EXCEPTION 'A directory manager cannot reassign their own account';
  END IF;
  IF v_previous IS NOT NULL AND lower(btrim(v_previous)) = lower(btrim(p_email))
  THEN RETURN false; END IF;
  INSERT INTO public.person_app_accounts(person_id, email)
  VALUES (p_person_id, lower(btrim(p_email)))
  ON CONFLICT (person_id) DO UPDATE SET
    email = EXCLUDED.email, status = 'active', updated_at = now();
  INSERT INTO public.audit_log(actor, action, entity_type, entity_id, details)
  VALUES (lower(btrim(p_actor_email)), 'person_app_account_changed', 'person',
    p_person_id::text,
    jsonb_build_object('previous_email', v_previous,
                       'email', lower(btrim(p_email)), 'reason', btrim(p_reason)));
  RETURN true;
END;
$$;

-- Appsmith uses one database credential and sends appsmith.user.email as the
-- actor. Only the trusted Appsmith application should be given DB access.
-- The initial directory manager must be selected explicitly by the DB operator.
CREATE FUNCTION public.issue19_set_person_role(
  p_actor_email text, p_person_id uuid, p_role_key text,
  p_enabled boolean, p_reason text
)
RETURNS boolean LANGUAGE plpgsql SECURITY INVOKER
SET search_path = public, pg_temp AS $$
DECLARE v_changed boolean := false;
BEGIN
  IF NOT public.issue19_has_role(p_actor_email, 'directory_manager') THEN
    RAISE EXCEPTION 'Directory manager permission required';
  END IF;
  IF p_role_key NOT IN ('practitioner', 'document_reviewer', 'donations_reviewer')
     OR p_enabled IS NULL OR NULLIF(btrim(p_reason), '') IS NULL THEN
    RAISE EXCEPTION 'A supported role, desired state, and reason are required';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.people WHERE person_id = p_person_id) THEN
    RAISE EXCEPTION 'Person not found';
  END IF;
  IF EXISTS (SELECT 1 FROM public.person_app_accounts
    WHERE person_id = p_person_id
      AND email_normalized = lower(btrim(p_actor_email))) THEN
    RAISE EXCEPTION 'A directory manager cannot change their own roles';
  END IF;
  IF p_enabled THEN
    INSERT INTO public.person_roles(person_id, role_key, assigned_by)
    VALUES (p_person_id, p_role_key, lower(btrim(p_actor_email)))
    ON CONFLICT DO NOTHING;
  ELSE
    DELETE FROM public.person_roles
    WHERE person_id = p_person_id AND role_key = p_role_key;
  END IF;
  v_changed := FOUND;

  -- A member's existing workflows still read these flags. In particular,
  -- do not imply practitioner status when granting a reviewer permission.
  UPDATE public.members m SET
    is_facilitator = CASE WHEN p_role_key = 'practitioner' THEN p_enabled
      ELSE m.is_facilitator END,
    is_document_reviewer = CASE WHEN p_role_key = 'document_reviewer'
      THEN p_enabled ELSE m.is_document_reviewer END,
    is_donations_reviewer = CASE WHEN p_role_key = 'donations_reviewer'
      THEN p_enabled ELSE m.is_donations_reviewer END,
    updated_at = now()
  WHERE m.person_id = p_person_id AND m.status = 'active'
    AND ((p_role_key = 'practitioner' AND m.is_facilitator IS DISTINCT FROM p_enabled)
      OR (p_role_key = 'document_reviewer' AND m.is_document_reviewer IS DISTINCT FROM p_enabled)
      OR (p_role_key = 'donations_reviewer' AND m.is_donations_reviewer IS DISTINCT FROM p_enabled));
  v_changed := v_changed OR FOUND;

  IF v_changed THEN
    INSERT INTO public.audit_log(actor, action, entity_type, entity_id, details)
    VALUES (lower(btrim(p_actor_email)), 'person_role_changed', 'person',
      p_person_id::text,
      jsonb_build_object('role', p_role_key, 'enabled', p_enabled,
                         'reason', btrim(p_reason)));
  END IF;
  RETURN v_changed;
END;
$$;

-- Existing member workflows stay operational; the Directory can now expose
-- individuals with their own Appsmith account even without membership.
CREATE OR REPLACE FUNCTION public.issue19_directory_entries(p_actor_email text)
RETURNS TABLE (
  party_kind text, party_id uuid, display_name text, member_id uuid,
  contributor_id uuid, membership_status text, contributor_status text,
  email text, phone text, created_at timestamptz,
  can_view_membership boolean, can_view_contributions boolean
)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = public, pg_temp AS $$
WITH actor AS (
  SELECT account.person_id, m.member_id,
    public.issue19_has_role(p_actor_email, 'document_reviewer') AS can_member,
    public.issue19_has_role(p_actor_email, 'donations_reviewer') AS can_donor,
    public.issue19_has_role(p_actor_email, 'directory_manager') AS can_manage
  FROM public.person_app_accounts account
  LEFT JOIN public.members m ON m.person_id = account.person_id
    AND m.status = 'active'
  WHERE account.status = 'active'
    AND account.email_normalized = lower(btrim(p_actor_email))
), people_scope AS (
  SELECT p.person_id, p.display_name, p.created_at,
    m.member_id AS actual_member_id,
    c.contributor_id AS actual_contributor_id,
    m.status AS actual_membership_status,
    c.status AS actual_contributor_status,
    (m.member_id IS NOT NULL AND
      (a.can_member OR a.can_manage OR m.member_id = a.member_id
       OR EXISTS (SELECT 1 FROM public.member_facilitators mf
         WHERE mf.member_id = m.member_id AND mf.facilitator_id = a.member_id
           AND mf.status = 'active'))) AS may_view_member,
    (c.contributor_id IS NOT NULL AND
      (a.can_donor OR a.can_manage OR
       EXISTS (SELECT 1 FROM public.contributor_member_links l
         JOIN public.member_facilitators mf ON mf.member_id = l.member_id
         WHERE l.contributor_id = c.contributor_id AND l.status = 'active'
           AND mf.facilitator_id = a.member_id AND mf.status = 'active')))
      AS may_view_donor,
    (a.can_manage OR a.person_id = p.person_id) AS may_view_person
  FROM public.people p CROSS JOIN actor a
  LEFT JOIN public.members m ON m.person_id = p.person_id AND m.status = 'active'
  LEFT JOIN public.contributors c ON c.person_id = p.person_id AND c.status = 'active'
), org_scope AS (
  SELECT o.organization_id, o.organization_name, o.created_at,
    c.contributor_id
  FROM public.organizations o
  JOIN public.contributors c ON c.organization_id = o.organization_id
    AND c.status = 'active'
  CROSS JOIN actor a WHERE a.can_donor OR a.can_manage
), visible AS (
  SELECT 'individual'::text AS kind, s.person_id AS id,
    s.display_name AS name, s.created_at,
    CASE WHEN s.may_view_member THEN s.actual_member_id END AS member_id,
    CASE WHEN s.may_view_donor THEN s.actual_contributor_id END AS contributor_id,
    CASE WHEN s.may_view_member THEN s.actual_membership_status END AS membership_status,
    CASE WHEN s.may_view_donor THEN s.actual_contributor_status END AS contributor_status,
    s.may_view_member AS can_member, s.may_view_donor AS can_donor
  FROM people_scope s
  WHERE s.may_view_member OR s.may_view_donor OR s.may_view_person
  UNION ALL
  SELECT 'organization', s.organization_id, s.organization_name,
    s.created_at, NULL::uuid, s.contributor_id,
    NULL::text, 'active'::text, false, true
  FROM org_scope s
)
SELECT v.kind, v.id, v.name, v.member_id, v.contributor_id,
  v.membership_status, v.contributor_status,
  (SELECT pc.contact_value FROM public.party_contacts pc
    JOIN public.party_contact_sources ps ON ps.party_contact_id = pc.party_contact_id
    WHERE pc.status = 'active' AND pc.contact_kind = 'email'
      AND ((v.kind = 'individual' AND pc.person_id = v.id)
        OR (v.kind = 'organization' AND pc.organization_id = v.id))
      AND ps.status = 'active'
      AND ((ps.source_table = 'member_emails' AND v.can_member)
        OR (ps.source_table = 'contributor_emails' AND v.can_donor))
    ORDER BY ps.is_primary DESC, ps.created_at, ps.source_id LIMIT 1) AS email,
  (SELECT pc.contact_value FROM public.party_contacts pc
    JOIN public.party_contact_sources ps ON ps.party_contact_id = pc.party_contact_id
    WHERE pc.status = 'active' AND pc.contact_kind = 'phone'
      AND ((v.kind = 'individual' AND pc.person_id = v.id)
        OR (v.kind = 'organization' AND pc.organization_id = v.id))
      AND ps.status = 'active'
      AND ((ps.source_table = 'member_phones' AND v.can_member)
        OR (ps.source_table = 'contributor_phones' AND v.can_donor))
    ORDER BY ps.is_primary DESC, ps.created_at, ps.source_id LIMIT 1) AS phone,
  v.created_at, v.can_member, v.can_donor
FROM visible v;
$$;

COMMENT ON TABLE public.person_roles IS
  'Person appointments and Appsmith permissions; legacy members reviewer/facilitator flags remain transitional.';
COMMENT ON TABLE public.person_app_accounts IS
  'Explicit ownership of an Appsmith sign-in email by one person; no matching by shared contact address.';
COMMIT;
