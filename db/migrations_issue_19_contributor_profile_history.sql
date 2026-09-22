-- Issue #19: permission-scoped contributor donation history and external
-- provider identities for Individual Profile and Company Profile.
-- Apply after contact_role_visibility.sql.
\set ON_ERROR_STOP on
BEGIN;

DO $$ BEGIN
  IF to_regprocedure('public.issue19_directory_entries(text)') IS NULL
     OR to_regclass('public.contributor_external_identities') IS NULL
     OR to_regclass('public.donations') IS NULL THEN
    RAISE EXCEPTION 'Apply the Issue #19 directory and contributor migrations first';
  END IF;
END $$;

CREATE FUNCTION public.issue19_contribution_history(
  p_actor_email text, p_party_kind text, p_party_id uuid
)
RETURNS TABLE (
  donation_id uuid,
  donation_date timestamptz,
  amount_cents integer,
  currency text,
  provider text,
  provider_reference text,
  status text,
  created_at timestamptz
)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = public, pg_temp AS $$
SELECT d.donation_id,
  COALESCE(d.donated_at,d.created_at) AS donation_date,
  d.amount_cents,d.currency,d.provider,d.provider_reference,d.status,d.created_at
FROM public.issue19_directory_entries(p_actor_email) visible
JOIN public.contributors c ON c.contributor_id=visible.contributor_id
JOIN public.donations d ON d.contributor_id=c.contributor_id
WHERE visible.party_kind=p_party_kind AND visible.party_id=p_party_id
  AND visible.can_view_contributions
ORDER BY COALESCE(d.donated_at,d.created_at) DESC,d.donation_id;
$$;

CREATE FUNCTION public.issue19_contributor_provider_identities(
  p_actor_email text, p_party_kind text, p_party_id uuid
)
RETURNS TABLE (
  contributor_external_identity_id uuid,
  provider text,
  provider_identity text,
  status text,
  source text,
  created_at timestamptz
)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = public, pg_temp AS $$
SELECT x.contributor_external_identity_id,x.provider,x.provider_identity,
  x.status,x.source,x.created_at
FROM public.issue19_directory_entries(p_actor_email) visible
JOIN public.contributors c ON c.contributor_id=visible.contributor_id
JOIN public.contributor_external_identities x
  ON x.contributor_id=c.contributor_id
WHERE visible.party_kind=p_party_kind AND visible.party_id=p_party_id
  AND visible.can_view_contributions
ORDER BY (x.status='active') DESC,x.provider,x.created_at,x.contributor_external_identity_id;
$$;

COMMENT ON FUNCTION public.issue19_contribution_history(text,text,uuid) IS
  'Contributor-attributed donation history filtered through Issue #19 directory contribution scope.';
COMMENT ON FUNCTION public.issue19_contributor_provider_identities(text,text,uuid) IS
  'Contributor external identities filtered through Issue #19 directory contribution scope.';
COMMIT;
