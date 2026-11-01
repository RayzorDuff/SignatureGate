-- Deployment terminology defaults, reconstructed from the earlier registry seed.
-- No private production records or configuration values are copied.
-- Existing labels, activation choices and stable keys are never overwritten.
-- The member compatibility key presents the Participant enrollment capacity.
\set ON_ERROR_STOP on
BEGIN;
INSERT INTO public.terminology_concepts
  (concept_key,concept_kind,description)
VALUES
  ('person','entity','Canonical individual identity.'),
  ('organization','entity','Canonical company or other organization identity.'),
  ('member','entity','Participant enrollment capacity of an individual; not a separate identity. Registry kind is retained for compatibility.'),
  ('participant','entity','Reserved event-participation concept, distinct from the operational member compatibility key.'),
  ('contributor','entity','Contributor capacity of an individual or company; not a separate identity.'),
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
  ('member','Participant','Participants','Participant',true,'organization_terminology_seed'),
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
