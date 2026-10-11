-- Deployment terminology defaults, reconstructed from the earlier registry seed.
-- No private production records or configuration values are copied.
-- Existing labels, activation choices and stable keys are never overwritten.
-- Phase 3 must revise Member/Participant defaults after its UI changes are accepted.
\set ON_ERROR_STOP on
BEGIN;
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
  ('person','Individual','Individuals','Person',true,'organization_terminology_seed'),
  ('organization','Company','Companies','Company',true,'organization_terminology_seed'),
  ('member','Member','Members',NULL,true,'organization_terminology_seed'),
  ('participant','Participant','Participants',NULL,false,'organization_terminology_seed'),
  ('contributor','Contributor','Contributors','Donor',true,'organization_terminology_seed'),
  ('practitioner','Spiritual Practitioner','Spiritual Practitioners','Practitioner',true,'organization_terminology_seed'),
  ('spiritual_practitioner','Spiritual Practitioner','Spiritual Practitioners',NULL,false,'organization_terminology_seed'),
  ('traditional_practitioner','Traditional Practitioner','Traditional Practitioners',NULL,false,'organization_terminology_seed'),
  ('facilitator','Facilitator','Facilitators',NULL,false,'organization_terminology_seed'),
  ('minister','Minister','Ministers',NULL,false,'organization_terminology_seed'),
  ('document_reviewer','Document Reviewer','Document Reviewers',NULL,true,'organization_terminology_seed'),
  ('donations_reviewer','Donations Reviewer','Donations Reviewers',NULL,true,'organization_terminology_seed'),
  ('directory_manager','Directory Manager','Directory Managers',NULL,true,'organization_terminology_seed'),
  ('sacrament_release','Sacrament Release','Sacrament Releases','Release',true,'organization_terminology_seed')
ON CONFLICT (concept_key) DO NOTHING;

COMMIT;
