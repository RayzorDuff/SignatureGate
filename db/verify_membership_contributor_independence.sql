-- Rollback-only checks that membership and contributor lifecycles are separate.
\set ON_ERROR_STOP on
BEGIN;
DO $$
DECLARE
  v_actor uuid;
  v_member_only_person uuid;
  v_member_only_id uuid;
  v_linked_person uuid;
  v_linked_member uuid;
  v_contributor uuid;
  v_donation uuid;
BEGIN
  INSERT INTO public.people(display_name) VALUES ('Issue 19 Capacity Reviewer')
    RETURNING person_id INTO v_actor;
  INSERT INTO public.person_app_accounts(person_id,email)
    VALUES (v_actor,'issue19-capacity-reviewer@example.invalid');
  INSERT INTO public.person_roles(person_id,role_key,assigned_by)
    VALUES (v_actor,'directory_manager','issue19_verify'),
      (v_actor,'document_reviewer','issue19_verify'),
      (v_actor,'donations_reviewer','issue19_verify');

  -- A person with membership capacity only can end it without acquiring
  -- contributor capacity as a side effect.
  INSERT INTO public.people(display_name,first_name,last_name)
    VALUES ('Member Only Person','Member','Only')
    RETURNING person_id INTO v_member_only_person;
  v_member_only_id := public.issue19_enable_person_membership(
    'issue19-capacity-reviewer@example.invalid',v_member_only_person,
    'Member','Only','Member-only independence check');
  IF NOT (SELECT can_end FROM public.issue19_person_membership_state(
      'issue19-capacity-reviewer@example.invalid',v_member_only_person)) THEN
    RAISE EXCEPTION 'Member-only person was incorrectly blocked from ending membership';
  END IF;
  PERFORM public.issue19_end_person_membership(
    'issue19-capacity-reviewer@example.invalid',v_member_only_person,
    'End member-only capacity');
  IF EXISTS (SELECT 1 FROM public.contributors
      WHERE person_id=v_member_only_person)
    OR NOT EXISTS (SELECT 1 FROM public.members
      WHERE member_id=v_member_only_id AND status='inactive')
    OR NOT EXISTS (SELECT 1 FROM public.audit_log
      WHERE action='membership.ended_for_person'
        AND entity_id=v_member_only_id::text
        AND details->>'had_active_contributor'='false'
        AND details->>'contributor_id' IS NULL)
  THEN RAISE EXCEPTION 'Ending member-only capacity created or required a contributor'; END IF;

  -- When both independent capacities exist, ending membership closes only the
  -- relationship and leaves contributor identity and donation attribution.
  INSERT INTO public.people(display_name,first_name,last_name)
    VALUES ('Member Contributor Person','Member','Contributor')
    RETURNING person_id INTO v_linked_person;
  v_linked_member := public.issue19_enable_person_membership(
    'issue19-capacity-reviewer@example.invalid',v_linked_person,
    'Member','Contributor','Linked-capacity check');
  v_contributor := public.issue19_enable_person_contributor(
    'issue19-capacity-reviewer@example.invalid',v_linked_person,
    'Enable separate contributor capacity');
  INSERT INTO public.contributor_member_links(
    contributor_id,member_id,status,link_reason)
  VALUES (v_contributor,v_linked_member,'active','Independence verification');
  INSERT INTO public.donations(
    contributor_id,member_id,donor_kind,provider,amount_cents,status)
  VALUES (v_contributor,v_linked_member,'identified','cash',1900,'pending_review')
  RETURNING donation_id INTO v_donation;

  PERFORM public.issue19_end_person_membership(
    'issue19-capacity-reviewer@example.invalid',v_linked_person,
    'End membership; retain contributions');
  IF NOT EXISTS (SELECT 1 FROM public.contributors
      WHERE contributor_id=v_contributor AND person_id=v_linked_person
        AND status='active')
    OR NOT EXISTS (SELECT 1 FROM public.contributor_member_links
      WHERE contributor_id=v_contributor AND member_id=v_linked_member
        AND status='ended' AND ended_at IS NOT NULL)
    OR NOT EXISTS (SELECT 1 FROM public.donations
      WHERE donation_id=v_donation AND contributor_id=v_contributor
        AND member_id=v_linked_member)
    OR NOT EXISTS (SELECT 1 FROM public.audit_log
      WHERE action='membership.ended_for_person'
        AND entity_id=v_linked_member::text
        AND details->>'had_active_contributor'='true'
        AND details->>'contributor_id'=v_contributor::text)
  THEN RAISE EXCEPTION 'Ending membership changed contributor capacity or donation history'; END IF;

  RAISE NOTICE 'Membership/contributor independence checks passed; rolling back synthetic records.';
END $$;
ROLLBACK;
