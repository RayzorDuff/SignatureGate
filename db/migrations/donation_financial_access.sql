-- Donation financial information access
--
-- Centralizes the read authorization for donation amounts and cash-deposit
-- financial information. Non-reviewer facilitators may perform practitioner
-- and donation-entry work, but organization-wide donation financials are
-- restricted to active donations reviewers.

CREATE OR REPLACE FUNCTION public.can_view_donation_financials(
  p_member_id uuid
) RETURNS boolean
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.members m
    WHERE m.member_id = p_member_id
      AND m.status = 'active'
      AND m.is_facilitator IS TRUE
      AND m.is_donations_reviewer IS TRUE
  );
$$;

COMMENT ON FUNCTION public.can_view_donation_financials(uuid) IS
  'Returns true only for an active facilitator who is also a donations reviewer and may view organization-wide donation financial information.';

CREATE OR REPLACE FUNCTION public.assert_donation_financial_viewer(
  p_member_id uuid
) RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.can_view_donation_financials(p_member_id) THEN
    RAISE EXCEPTION
      'An active donations reviewer is required to view donation financial information.';
  END IF;
END;
$$;

COMMENT ON FUNCTION public.assert_donation_financial_viewer(uuid) IS
  'Raises unless the actor is an active donations reviewer authorized to view organization-wide donation financial information.';
