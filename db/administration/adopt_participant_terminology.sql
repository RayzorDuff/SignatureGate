-- Explicit, audited presentation change for an existing installation.
-- Does not seed operational identities, copy permissions or change executed documents.
\set ON_ERROR_STOP on
\if :{?admin_email}
\else
DO $missing$ BEGIN RAISE EXCEPTION 'Provide the intended Appsmith account with -v admin_email'; END $missing$;
\endif
BEGIN;
SELECT public.issue20_set_organization_terminology(
  :'admin_email','member','Participant','Participants','Participant',true,
  'Adopt Participant presentation for the v1.2.0 release') AS terminology_changed;
COMMIT;
