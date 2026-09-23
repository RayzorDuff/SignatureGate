-- Issue #20: separate stable domain concepts from deployment terminology.
-- Apply after migrations_issue_19_person_practitioner_assignments.sql; run once.
\set ON_ERROR_STOP on
BEGIN;

DO $$ BEGIN
  IF to_regclass('public.person_roles') IS NULL
     OR to_regprocedure('public.issue19_has_role(text,text)') IS NULL THEN
    RAISE EXCEPTION 'Apply the Issue #19 person-role migrations first';
  END IF;
END $$;

-- Concept keys are application contracts. Operators may change their labels,
-- but changing a label never renames a role, grants access, or merges concepts.
CREATE TABLE public.terminology_concepts (
  concept_key text PRIMARY KEY,
  concept_kind text NOT NULL
    CHECK (concept_kind IN ('entity','appointment','permission','workflow')),
  description text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (concept_key ~ '^[a-z][a-z0-9_]*$'),
  CHECK (NULLIF(btrim(description),'') IS NOT NULL)
);

-- SignatureGate is currently one organization per deployment. This table is
-- therefore the organization-level terminology profile for that deployment.
CREATE TABLE public.organization_terminology (
  concept_key text PRIMARY KEY
    REFERENCES public.terminology_concepts(concept_key),
  singular_label text NOT NULL,
  plural_label text NOT NULL,
  short_label text,
  is_active boolean NOT NULL DEFAULT true,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by text NOT NULL,
  CHECK (NULLIF(btrim(singular_label),'') IS NOT NULL),
  CHECK (NULLIF(btrim(plural_label),'') IS NOT NULL),
  CHECK (short_label IS NULL OR NULLIF(btrim(short_label),'') IS NOT NULL),
  CHECK (char_length(singular_label) <= 80),
  CHECK (char_length(plural_label) <= 80),
  CHECK (short_label IS NULL OR char_length(short_label) <= 40)
);

CREATE TRIGGER trg_organization_terminology_updated_at
BEFORE UPDATE ON public.organization_terminology
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

INSERT INTO public.terminology_concepts
  (concept_key,concept_kind,description)
VALUES
  ('person','entity','Canonical individual identity.'),
  ('organization','entity','Canonical company or other organization identity.'),
  ('member','entity','A person with membership capacity.'),
  ('participant','entity','A person participating in a ceremony or event.'),
  ('contributor','entity','An individual or organization with contributor capacity.'),
  ('practitioner','appointment','Current general practitioner appointment used by member assignment and access workflows.'),
  ('spiritual_practitioner','appointment','Reserved distinct appointment if a deployment later separates spiritual practice from the general practitioner concept.'),
  ('traditional_practitioner','appointment','Reserved distinct traditional-practitioner appointment.'),
  ('facilitator','appointment','Reserved distinct regulated facilitator appointment; it is not an alias for practitioner.'),
  ('minister','appointment','Reserved minister appointment.'),
  ('document_reviewer','permission','Permission to review membership documents and manage member operations.'),
  ('donations_reviewer','permission','Permission to review donations and contributor operations.'),
  ('directory_manager','permission','Permission to manage directory identities, accounts, roles, and terminology.'),
  ('sacrament_release','workflow','Tangible sacrament transfer workflow.')
ON CONFLICT (concept_key) DO NOTHING;

-- Rooted Psyche defaults. The stable operational key remains practitioner;
-- only its presentation is Spiritual Practitioner. The separate facilitator
-- concept stays inactive until a future regulated role is actually designed.
INSERT INTO public.organization_terminology
  (concept_key,singular_label,plural_label,short_label,is_active,updated_by)
VALUES
  ('person','Individual','Individuals','Person',true,'issue20_migration'),
  ('organization','Company','Companies','Company',true,'issue20_migration'),
  ('member','Member','Members',NULL,true,'issue20_migration'),
  ('participant','Participant','Participants',NULL,false,'issue20_migration'),
  ('contributor','Contributor','Contributors','Donor',true,'issue20_migration'),
  ('practitioner','Spiritual Practitioner','Spiritual Practitioners','Practitioner',true,'issue20_migration'),
  ('spiritual_practitioner','Spiritual Practitioner','Spiritual Practitioners',NULL,false,'issue20_migration'),
  ('traditional_practitioner','Traditional Practitioner','Traditional Practitioners',NULL,false,'issue20_migration'),
  ('facilitator','Facilitator','Facilitators',NULL,false,'issue20_migration'),
  ('minister','Minister','Ministers',NULL,false,'issue20_migration'),
  ('document_reviewer','Document Reviewer','Document Reviewers',NULL,true,'issue20_migration'),
  ('donations_reviewer','Donations Reviewer','Donations Reviewers',NULL,true,'issue20_migration'),
  ('directory_manager','Directory Manager','Directory Managers',NULL,true,'issue20_migration'),
  ('sacrament_release','Sacrament Release','Sacrament Releases','Release',true,'issue20_migration');

CREATE FUNCTION public.issue20_organization_terminology()
RETURNS TABLE (
  concept_key text,concept_kind text,singular_label text,plural_label text,
  short_label text,is_active boolean,description text,updated_at timestamptz
)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = public, pg_temp AS $$
SELECT concept.concept_key,concept.concept_kind,term.singular_label,
  term.plural_label,term.short_label,term.is_active,concept.description,
  term.updated_at
FROM public.terminology_concepts concept
JOIN public.organization_terminology term
  ON term.concept_key=concept.concept_key
ORDER BY concept.concept_kind,concept.concept_key;
$$;

CREATE FUNCTION public.issue20_set_organization_terminology(
  p_actor_email text,p_concept_key text,p_singular_label text,
  p_plural_label text,p_short_label text,p_is_active boolean,p_reason text
)
RETURNS boolean LANGUAGE plpgsql VOLATILE SECURITY INVOKER
SET search_path = public, pg_temp AS $$
DECLARE
  v_previous public.organization_terminology%ROWTYPE;
  v_singular text := NULLIF(btrim(p_singular_label),'');
  v_plural text := NULLIF(btrim(p_plural_label),'');
  v_short text := NULLIF(btrim(p_short_label),'');
BEGIN
  IF NOT public.issue19_has_role(p_actor_email,'directory_manager') THEN
    RAISE EXCEPTION 'Directory manager permission required';
  END IF;
  IF NULLIF(btrim(p_concept_key),'') IS NULL OR v_singular IS NULL
     OR v_plural IS NULL OR p_is_active IS NULL
     OR NULLIF(btrim(p_reason),'') IS NULL THEN
    RAISE EXCEPTION 'Concept, singular and plural labels, active state, and reason are required';
  END IF;
  IF char_length(v_singular)>80 OR char_length(v_plural)>80
     OR char_length(v_short)>40 THEN
    RAISE EXCEPTION 'Terminology label is too long';
  END IF;

  SELECT * INTO v_previous FROM public.organization_terminology
  WHERE concept_key=p_concept_key FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Unknown terminology concept %',p_concept_key;
  END IF;
  IF v_previous.singular_label=v_singular
     AND v_previous.plural_label=v_plural
     AND v_previous.short_label IS NOT DISTINCT FROM v_short
     AND v_previous.is_active=p_is_active THEN
    RETURN false;
  END IF;

  UPDATE public.organization_terminology SET
    singular_label=v_singular,plural_label=v_plural,short_label=v_short,
    is_active=p_is_active,updated_by=lower(btrim(p_actor_email))
  WHERE concept_key=p_concept_key;

  INSERT INTO public.audit_log(actor,action,entity_type,entity_id,details)
  VALUES (lower(btrim(p_actor_email)),'organization_terminology.changed',
    'terminology_concept',p_concept_key,
    jsonb_build_object(
      'before',jsonb_build_object(
        'singular_label',v_previous.singular_label,
        'plural_label',v_previous.plural_label,
        'short_label',v_previous.short_label,
        'is_active',v_previous.is_active),
      'after',jsonb_build_object(
        'singular_label',v_singular,'plural_label',v_plural,
        'short_label',v_short,'is_active',p_is_active),
      'reason',btrim(p_reason)));
  RETURN true;
END;
$$;

COMMENT ON TABLE public.terminology_concepts IS
  'Stable application concept registry. Keys are contracts and are changed only by migrations.';
COMMENT ON TABLE public.organization_terminology IS
  'Configurable presentation labels for this single-organization SignatureGate deployment.';
COMMENT ON FUNCTION public.issue20_organization_terminology() IS
  'Returns stable concept keys and the deployment terminology used by application surfaces.';
COMMENT ON FUNCTION public.issue20_set_organization_terminology(text,text,text,text,text,boolean,text) IS
  'Audited directory-manager terminology update; never changes role identity or authorization.';
COMMIT;
