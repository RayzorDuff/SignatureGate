-- Issue #19: read-only party directory for Appsmith's existing account model.
-- Apply after migrations_issue_19_party_contacts.sql and before importing the
-- accompanying Appsmith export. The member/reviewer flags remain transitional.
\set ON_ERROR_STOP on
BEGIN;

DO $$
BEGIN
  IF to_regclass('public.party_contacts') IS NULL
     OR to_regclass('public.party_contact_sources') IS NULL
     OR to_regclass('public.member_profiles') IS NULL
  THEN RAISE EXCEPTION 'Apply the Issue #19 contact foundation first'; END IF;
END $$;

CREATE FUNCTION public.issue19_directory_entries(p_actor_email text)
RETURNS TABLE (
  party_kind text,
  party_id uuid,
  display_name text,
  member_id uuid,
  contributor_id uuid,
  membership_status text,
  contributor_status text,
  email text,
  phone text,
  created_at timestamptz,
  can_view_membership boolean,
  can_view_contributions boolean
)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = public, pg_temp AS $$
WITH actor AS (
  SELECT m.member_id, m.person_id,
    m.is_document_reviewer, m.is_donations_reviewer
  FROM public.members m
  WHERE m.status = 'active' AND m.is_facilitator IS TRUE
    AND lower(btrim(m.email)) = lower(btrim(p_actor_email))
  LIMIT 1
), people_scope AS (
  SELECT p.person_id, p.display_name, p.created_at,
    m.member_id AS actual_member_id,
    c.contributor_id AS actual_contributor_id,
    m.status AS actual_membership_status,
    c.status AS actual_contributor_status,
    (m.member_id IS NOT NULL AND
      (a.is_document_reviewer IS TRUE OR m.member_id = a.member_id
       OR EXISTS (SELECT 1 FROM public.member_facilitators mf
         WHERE mf.member_id = m.member_id AND mf.facilitator_id = a.member_id
           AND mf.status = 'active'))) AS may_view_member,
    (c.contributor_id IS NOT NULL AND
      (a.is_donations_reviewer IS TRUE OR
       EXISTS (SELECT 1 FROM public.contributor_member_links l
         JOIN public.member_facilitators mf ON mf.member_id = l.member_id
         WHERE l.contributor_id = c.contributor_id AND l.status = 'active'
           AND mf.facilitator_id = a.member_id AND mf.status = 'active')))
      AS may_view_donor
  FROM public.people p CROSS JOIN actor a
  LEFT JOIN public.members m ON m.person_id = p.person_id AND m.status = 'active'
  LEFT JOIN public.contributors c ON c.person_id = p.person_id AND c.status = 'active'
), org_scope AS (
  SELECT o.organization_id, o.organization_name, o.created_at,
    c.contributor_id
  FROM public.organizations o
  JOIN public.contributors c ON c.organization_id = o.organization_id
    AND c.status = 'active'
  CROSS JOIN actor a WHERE a.is_donations_reviewer IS TRUE
), visible AS (
  SELECT 'individual'::text AS kind, s.person_id AS id,
    s.display_name AS name, s.created_at,
    CASE WHEN s.may_view_member THEN s.actual_member_id END AS member_id,
    CASE WHEN s.may_view_donor THEN s.actual_contributor_id END AS contributor_id,
    CASE WHEN s.may_view_member THEN s.actual_membership_status END AS membership_status,
    CASE WHEN s.may_view_donor THEN s.actual_contributor_status END AS contributor_status,
    s.may_view_member AS can_member, s.may_view_donor AS can_donor
  FROM people_scope s WHERE s.may_view_member OR s.may_view_donor
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

CREATE FUNCTION public.issue19_directory_contacts(
  p_actor_email text, p_party_kind text, p_party_id uuid
)
RETURNS TABLE (
  contact_kind text,
  contact_detail text,
  purpose text,
  is_primary boolean,
  is_verified boolean
)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = public, pg_temp AS $$
SELECT DISTINCT pc.contact_kind,
  CASE WHEN pc.contact_kind = 'address'
    THEN concat_ws(', ', NULLIF(concat_ws(' ',pc.address_1,pc.address_2),''),
      pc.city, pc.state, pc.postal_code, pc.country)
    ELSE pc.contact_value END AS contact_detail,
  CASE WHEN ps.source_table LIKE 'member_%' THEN 'membership'::text
    ELSE 'contributions'::text END AS purpose,
  ps.is_primary, ps.is_verified
FROM public.issue19_directory_entries(p_actor_email) visible
JOIN public.party_contacts pc
  ON (visible.party_kind = 'individual' AND pc.person_id = visible.party_id)
  OR (visible.party_kind = 'organization' AND pc.organization_id = visible.party_id)
JOIN public.party_contact_sources ps ON ps.party_contact_id = pc.party_contact_id
WHERE visible.party_kind = p_party_kind AND visible.party_id = p_party_id
  AND pc.status = 'active' AND ps.status = 'active'
  AND ((ps.source_table LIKE 'member_%' AND visible.can_view_membership)
    OR (ps.source_table LIKE 'contributor_%' AND visible.can_view_contributions))
ORDER BY contact_kind, contact_detail, purpose, is_primary DESC;
$$;

COMMENT ON FUNCTION public.issue19_directory_entries(text) IS
  'Read-only Appsmith directory projection for the current email-based facilitator/reviewer account model. The trusted Appsmith user email is supplied by the application.';
COMMENT ON FUNCTION public.issue19_directory_contacts(text,text,uuid) IS
  'Contact details filtered by the same party and member/contributor scope as the Appsmith directory.';
COMMIT;
