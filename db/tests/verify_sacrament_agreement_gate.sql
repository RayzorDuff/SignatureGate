-- Rollback-only checks for version-independent sacrament agreement gating.
\set ON_ERROR_STOP on
BEGIN;
DO $$
DECLARE
  v_person uuid;
  v_member uuid;
  v_old_template uuid;
  v_new_template uuid;
  v_membership_template uuid;
  v_old_agreement uuid;
  v_new_agreement uuid;
  v_manual_agreement uuid;
BEGIN
  INSERT INTO public.people(display_name)
    VALUES ('Issue 19 Agreement Gate Target')
    RETURNING person_id INTO v_person;
  INSERT INTO public.members(person_id)
    VALUES (v_person) RETURNING member_id INTO v_member;

  INSERT INTO public.agreement_templates(
    name,version,required_for,active)
  VALUES ('Issue 19 Sacrament Agreement','1.0',
    ARRAY['membership','sacrament_release'],false)
  RETURNING agreement_template_id INTO v_old_template;
  INSERT INTO public.agreement_templates(
    name,version,required_for,active)
  VALUES ('Issue 19 Sacrament Agreement','2.0',
    ARRAY['membership','sacrament_release'],true)
  RETURNING agreement_template_id INTO v_new_template;
  INSERT INTO public.agreement_templates(
    name,version,required_for,active)
  VALUES ('Issue 19 Membership Only','1.0',ARRAY['membership'],true)
  RETURNING agreement_template_id INTO v_membership_template;

  INSERT INTO public.member_agreements(
    member_id,agreement_template_id,status,signature_method,signed_at)
  VALUES (v_member,v_old_template,'signed','documenso',now()-interval '1 year')
  RETURNING member_agreement_id INTO v_old_agreement;
  INSERT INTO public.member_agreements(
    member_id,agreement_template_id,status,signature_method)
  VALUES (v_member,v_new_template,'pending_signature','documenso');
  INSERT INTO public.member_agreements(
    member_id,agreement_template_id,status,signature_method,signed_at)
  VALUES (v_member,v_membership_template,'signed','documenso',now())
  RETURNING member_agreement_id INTO v_new_agreement;

  IF NOT EXISTS (SELECT 1
      FROM public.issue19_sacrament_release_agreement(v_member)
      WHERE member_agreement_id=v_old_agreement
        AND template_version='1.0'
        AND template_active=false
        AND eligibility_basis='signed_sacrament_template') THEN
    RAISE EXCEPTION 'An inactive older template version did not authorize release';
  END IF;
  IF EXISTS (SELECT 1
      FROM public.issue19_sacrament_release_agreement(v_member)
      WHERE member_agreement_id=v_new_agreement) THEN
    RAISE EXCEPTION 'A membership-only agreement authorized sacrament release';
  END IF;

  UPDATE public.member_agreements SET status='signed',signed_at=now()
  WHERE member_id=v_member AND agreement_template_id=v_new_template;
  SELECT member_agreement_id INTO v_new_agreement
  FROM public.member_agreements
  WHERE member_id=v_member AND agreement_template_id=v_new_template;
  IF NOT EXISTS (SELECT 1
      FROM public.issue19_sacrament_release_agreement(v_member)
      WHERE member_agreement_id=v_new_agreement
        AND template_version='2.0' AND template_active=true) THEN
    RAISE EXCEPTION 'Newest signed sacrament agreement was not selected';
  END IF;

  UPDATE public.member_agreements SET status='canceled'
  WHERE member_id=v_member
    AND agreement_template_id IN (v_old_template,v_new_template);
  INSERT INTO public.member_agreements(
    member_id,agreement_template_id,status,signature_method,signed_at)
  VALUES (v_member,NULL,'signed','paper',now())
  RETURNING member_agreement_id INTO v_manual_agreement;
  IF NOT EXISTS (SELECT 1
      FROM public.issue19_sacrament_release_agreement(v_member)
      WHERE member_agreement_id=v_manual_agreement
        AND eligibility_basis='reviewed_manual_agreement') THEN
    RAISE EXCEPTION 'Reviewed template-free paper agreement did not authorize release';
  END IF;

  RAISE NOTICE 'Version-independent sacrament agreement gate checks passed; rolling back synthetic records.';
END $$;
ROLLBACK;
