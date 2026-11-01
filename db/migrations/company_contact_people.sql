-- Explicit company-to-person relationships; no capacity, permission or contact inheritance.
\set ON_ERROR_STOP on
BEGIN;
CREATE TABLE IF NOT EXISTS public.organization_contact_people (
  organization_contact_person_id uuid PRIMARY KEY DEFAULT public.uuid_generate_v4(),
  organization_id uuid NOT NULL REFERENCES public.organizations(organization_id),
  person_id uuid NOT NULL REFERENCES public.people(person_id),
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','archived')),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (organization_id,person_id)
);
CREATE INDEX IF NOT EXISTS organization_contact_people_person_idx
  ON public.organization_contact_people(person_id);
COMMENT ON TABLE public.organization_contact_people IS
  'Explicit company contact people. Relationships grant no roles, capacities, profile access, mailing consent or donation attribution.';

CREATE OR REPLACE FUNCTION public.application_company_contact_access(p_actor_email text,p_organization_id uuid,p_write boolean DEFAULT false)
RETURNS boolean LANGUAGE sql STABLE SET search_path=public,pg_temp AS $company$
SELECT EXISTS (
  SELECT 1 FROM public.application_access(p_actor_email) a
  JOIN public.issue19_directory_entries(p_actor_email) d
    ON d.party_kind='organization' AND d.party_id=p_organization_id
  WHERE (a.is_directory_manager OR a.is_donations_reviewer)
    AND (NOT p_write OR d.contributor_status='active')
);
$company$;

CREATE OR REPLACE FUNCTION public.application_company_contact_people(p_actor_email text,p_organization_id uuid)
RETURNS TABLE(organization_contact_person_id uuid,organization_id uuid,person_id uuid,display_name text,status text,updated_at text)
LANGUAGE sql STABLE SET search_path=public,pg_temp AS $company$
SELECT l.organization_contact_person_id,l.organization_id,l.person_id,p.display_name,l.status,l.updated_at::text
FROM public.organization_contact_people l JOIN public.people p USING(person_id)
WHERE l.organization_id=p_organization_id
  AND public.application_company_contact_access(p_actor_email,p_organization_id)
ORDER BY l.status,p.display_name,l.person_id;
$company$;

CREATE OR REPLACE FUNCTION public.application_company_contact_candidates(p_actor_email text,p_organization_id uuid)
RETURNS TABLE(person_id uuid,display_name text)
LANGUAGE sql STABLE SET search_path=public,pg_temp AS $company$
SELECT DISTINCT d.party_id,d.display_name
FROM public.issue19_directory_entries(p_actor_email) d
WHERE d.party_kind='individual'
  AND public.application_company_contact_access(p_actor_email,p_organization_id,true)
  AND NOT EXISTS (SELECT 1 FROM public.organization_contact_people l
    WHERE l.organization_id=p_organization_id AND l.person_id=d.party_id AND l.status='active')
ORDER BY d.display_name,d.party_id;
$company$;

CREATE OR REPLACE FUNCTION public.application_set_company_contact_person(
 p_actor_email text,p_organization_id uuid,p_person_id uuid,p_active boolean,
 p_expected_updated_at timestamptz,p_reason text)
RETURNS public.organization_contact_people
LANGUAGE plpgsql SET search_path=public,pg_temp AS $company$
DECLARE prior public.organization_contact_people; changed public.organization_contact_people; actor record;
BEGIN
 SELECT * INTO actor FROM public.application_access(p_actor_email);
 IF NOT public.application_company_contact_access(p_actor_email,p_organization_id,true) THEN
  RAISE EXCEPTION 'Active company and Directory Manager or Donations Reviewer permission required';
 END IF;
 IF p_person_id IS NULL OR p_active IS NULL OR NULLIF(btrim(p_reason),'') IS NULL THEN
  RAISE EXCEPTION 'Individual, desired relationship state and reason are required';
 END IF;
 -- Serialize changes to a company before locking its person; duplicate links cannot race.
 PERFORM 1 FROM public.organizations WHERE organization_id=p_organization_id FOR UPDATE;
 -- Recheck active contributor state while holding its lock, including concurrent archival.
 PERFORM 1 FROM public.contributors WHERE organization_id=p_organization_id AND status='active' FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Company contributor is no longer active'; END IF;
 PERFORM 1 FROM public.people WHERE person_id=p_person_id FOR KEY SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Existing individual required'; END IF;
 SELECT * INTO prior FROM public.organization_contact_people
  WHERE organization_id=p_organization_id AND person_id=p_person_id FOR UPDATE;
 IF prior.organization_contact_person_id IS NULL THEN
  IF NOT p_active OR p_expected_updated_at IS NOT NULL THEN RAISE EXCEPTION 'Relationship changed; reload before continuing'; END IF;
 ELSE
  IF p_expected_updated_at IS NULL OR p_expected_updated_at IS DISTINCT FROM prior.updated_at
    OR (prior.status='active')=p_active THEN RAISE EXCEPTION 'Relationship changed; reload before continuing'; END IF;
 END IF;
 -- Removal needs company authority, not additional access to the former contact's own profile.
 IF p_active AND NOT EXISTS (SELECT 1 FROM public.issue19_directory_entries(p_actor_email) d
   WHERE d.party_kind='individual' AND d.party_id=p_person_id) THEN
  RAISE EXCEPTION 'Selected individual is outside the accessible directory';
 END IF;
 IF prior.organization_contact_person_id IS NULL THEN
  INSERT INTO public.organization_contact_people(organization_id,person_id)
    VALUES(p_organization_id,p_person_id) RETURNING * INTO changed;
 ELSE
  UPDATE public.organization_contact_people SET status=CASE WHEN p_active THEN 'active' ELSE 'archived' END,
    updated_at=clock_timestamp() WHERE organization_contact_person_id=prior.organization_contact_person_id
    RETURNING * INTO changed;
 END IF;
 INSERT INTO public.audit_log(actor,action,entity_type,entity_id,details)
 VALUES(lower(btrim(actor.email)),'organization_contact_person.changed','organization',p_organization_id::text,
  jsonb_build_object('actor_person_id',actor.person_id,'organization_contact_person_id',changed.organization_contact_person_id,
   'person_id',p_person_id,'previous_status',prior.status,'status',changed.status,'reason',btrim(p_reason)));
 RETURN changed;
END;
$company$;
COMMIT;
