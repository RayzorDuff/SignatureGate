-- Issue #19: audited contributor archive/reactivation without deleting party,
-- contact, provider, donation, or membership-link history.
-- Apply after contributor_profile_history.sql.
\set ON_ERROR_STOP on
BEGIN;

DO $$ BEGIN
  IF to_regprocedure('public.issue19_contribution_history(text,text,uuid)') IS NULL
     OR to_regclass('public.person_roles') IS NULL THEN
    RAISE EXCEPTION 'Apply the Issue #19 profile-history and role migrations first';
  END IF;
END $$;

-- Keep archived contributors reachable only to users holding both contributor
-- maintenance permissions. Ordinary facilitator scope remains active-only.
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
    public.issue19_has_role(p_actor_email,'document_reviewer') AS can_member,
    public.issue19_has_role(p_actor_email,'donations_reviewer') AS can_donor,
    public.issue19_has_role(p_actor_email,'directory_manager') AS can_manage
  FROM public.person_app_accounts account
  LEFT JOIN public.members m ON m.person_id=account.person_id
    AND m.status='active'
  WHERE account.status='active'
    AND account.email_normalized=lower(btrim(p_actor_email))
), people_scope AS (
  SELECT p.person_id,p.display_name,p.created_at,
    m.member_id AS actual_member_id,
    c.contributor_id AS actual_contributor_id,
    m.status AS actual_membership_status,
    c.status AS actual_contributor_status,
    (m.member_id IS NOT NULL AND
      (a.can_member OR a.can_manage OR m.member_id=a.member_id
       OR EXISTS (SELECT 1 FROM public.member_facilitators mf
         WHERE mf.member_id=m.member_id AND mf.facilitator_id=a.member_id
           AND mf.status='active'))) AS may_view_member,
    (c.contributor_id IS NOT NULL AND (
      (c.status='active' AND (a.can_donor OR a.can_manage OR EXISTS (
        SELECT 1 FROM public.contributor_member_links l
        JOIN public.member_facilitators mf ON mf.member_id=l.member_id
        WHERE l.contributor_id=c.contributor_id AND l.status='active'
          AND mf.facilitator_id=a.member_id AND mf.status='active')))
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
    JOIN public.party_contact_sources ps ON ps.party_contact_id=pc.party_contact_id
    WHERE pc.status='active' AND pc.contact_kind='email'
      AND ((v.kind='individual' AND pc.person_id=v.id)
        OR (v.kind='organization' AND pc.organization_id=v.id))
      AND ps.status='active'
      AND ((ps.source_table='member_emails' AND v.can_member)
        OR (ps.source_table='contributor_emails' AND v.can_donor))
    ORDER BY ps.is_primary DESC,ps.created_at,ps.source_id LIMIT 1) AS email,
  (SELECT pc.contact_value FROM public.party_contacts pc
    JOIN public.party_contact_sources ps ON ps.party_contact_id=pc.party_contact_id
    WHERE pc.status='active' AND pc.contact_kind='phone'
      AND ((v.kind='individual' AND pc.person_id=v.id)
        OR (v.kind='organization' AND pc.organization_id=v.id))
      AND ps.status='active'
      AND ((ps.source_table='member_phones' AND v.can_member)
        OR (ps.source_table='contributor_phones' AND v.can_donor))
    ORDER BY ps.is_primary DESC,ps.created_at,ps.source_id LIMIT 1) AS phone,
  v.created_at,v.can_member,v.can_donor
FROM visible v;
$$;

CREATE FUNCTION public.issue19_contributor_status_state(
  p_actor_email text,p_party_kind text,p_party_id uuid
)
RETURNS TABLE (contributor_id uuid,current_status text,
  can_archive boolean,can_reactivate boolean,status_note text)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = public, pg_temp AS $$
SELECT c.contributor_id,c.status,
  c.status='active',c.status='archived',
  CASE c.status
    WHEN 'active' THEN 'Active contributor. Archive to stop future use while retaining history.'
    WHEN 'archived' THEN 'Archived contributor. Reactivate to use this contributor again.'
    ELSE 'Merged contributors cannot be changed from this profile.' END
FROM public.issue19_directory_entries(p_actor_email) visible
JOIN public.contributors c ON c.contributor_id=visible.contributor_id
WHERE visible.party_kind=p_party_kind AND visible.party_id=p_party_id
  AND public.issue19_has_role(p_actor_email,'directory_manager')
  AND public.issue19_has_role(p_actor_email,'donations_reviewer');
$$;

CREATE FUNCTION public.issue19_set_contributor_status(
  p_actor_email text,p_party_kind text,p_party_id uuid,
  p_target_status text,p_reason text
)
RETURNS uuid LANGUAGE plpgsql VOLATILE SECURITY INVOKER
SET search_path = public, pg_temp AS $$
DECLARE
  v_contributor public.contributors%ROWTYPE;
  v_actor_member_id uuid;
BEGIN
  IF NOT public.issue19_has_role(p_actor_email,'directory_manager')
     OR NOT public.issue19_has_role(p_actor_email,'donations_reviewer') THEN
    RAISE EXCEPTION 'Directory manager and donations reviewer permissions required';
  END IF;
  IF p_party_kind NOT IN ('individual','organization') OR p_party_id IS NULL THEN
    RAISE EXCEPTION 'Select an individual or organization contributor';
  END IF;
  IF p_target_status NOT IN ('active','archived') THEN
    RAISE EXCEPTION 'Contributor status must be active or archived';
  END IF;
  IF NULLIF(btrim(p_reason),'') IS NULL THEN
    RAISE EXCEPTION 'Enter a reason for the contributor status change';
  END IF;

  SELECT c.* INTO v_contributor FROM public.contributors c
  WHERE c.contributor_type=p_party_kind
    AND ((p_party_kind='individual' AND c.person_id=p_party_id)
      OR (p_party_kind='organization' AND c.organization_id=p_party_id))
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Contributor not found'; END IF;
  IF v_contributor.status='merged' THEN
    RAISE EXCEPTION 'Merged contributors cannot be reactivated or archived';
  END IF;
  IF v_contributor.status=p_target_status THEN
    RETURN v_contributor.contributor_id;
  END IF;

  SELECT m.member_id INTO v_actor_member_id
  FROM public.person_app_accounts account
  JOIN public.members m ON m.person_id=account.person_id AND m.status='active'
  WHERE account.status='active'
    AND account.email_normalized=lower(btrim(p_actor_email));

  UPDATE public.contributors SET status=p_target_status,
    archived_at=CASE WHEN p_target_status='archived' THEN now() END,
    archived_by=CASE WHEN p_target_status='archived' THEN v_actor_member_id END,
    archive_reason=CASE WHEN p_target_status='archived' THEN btrim(p_reason) END,
    updated_at=now()
  WHERE contributor_id=v_contributor.contributor_id;

  INSERT INTO public.audit_log(actor,action,entity_type,entity_id,details)
  VALUES (lower(btrim(p_actor_email)),
    CASE p_target_status WHEN 'archived' THEN 'contributor.archived'
      ELSE 'contributor.reactivated' END,
    'contributor',v_contributor.contributor_id::text,
    jsonb_build_object('party_kind',p_party_kind,'party_id',p_party_id,
      'previous_status',v_contributor.status,'new_status',p_target_status,
      'reason',btrim(p_reason)));
  RETURN v_contributor.contributor_id;
END;
$$;

COMMENT ON FUNCTION public.issue19_set_contributor_status(text,text,uuid,text,text) IS
  'Archives or reactivates a contributor without changing identity, contacts, donations, provider identities, or membership links.';
COMMIT;
