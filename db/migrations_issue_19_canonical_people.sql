-- Issue #19: finish person/organization identity consolidation.
-- Apply ONCE after migrations_issue_19_shared_identity.sql, before importing
-- the accompanying Appsmith export. Run during a brief write pause.
\set ON_ERROR_STOP on

BEGIN;

DO $$
BEGIN
  IF to_regclass('public.people') IS NULL
     OR to_regclass('public.organizations') IS NULL
     OR to_regclass('public.person_identity_review') IS NULL
     OR to_regprocedure('public.create_member_from_intake(text,text,text,text,date,text,boolean,uuid)') IS NULL
  THEN
    RAISE EXCEPTION 'Apply the shared-identity and member-intake migrations first.';
  END IF;
END $$;

LOCK TABLE public.people, public.organizations,
  public.members, public.contributors,
  public.contributor_member_links IN SHARE ROW EXCLUSIVE MODE;

-- Fail before dropping any columns if the original backfill is incomplete.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.members WHERE person_id IS NULL)
     OR EXISTS (SELECT 1 FROM public.contributors
       WHERE (contributor_type = 'individual' AND person_id IS NULL)
          OR (contributor_type = 'organization' AND organization_id IS NULL))
  THEN
    RAISE EXCEPTION 'Member/contributor identity backfill is incomplete.';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.contributor_member_links l
    JOIN public.members m ON m.member_id = l.member_id
    JOIN public.contributors c ON c.contributor_id = l.contributor_id
    WHERE l.status = 'active' AND m.person_id <> c.person_id
  ) THEN
    RAISE EXCEPTION 'An active membership link crosses person identities.';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.members m
    JOIN public.people p ON p.person_id = m.person_id
    WHERE (m.first_name, m.last_name, m.date_of_birth)
      IS DISTINCT FROM (p.first_name, p.last_name, p.date_of_birth)
  ) OR EXISTS (
    SELECT 1 FROM public.contributors c
    JOIN public.people p ON p.person_id = c.person_id
    WHERE (c.first_name, c.last_name, c.display_name)
      IS DISTINCT FROM (p.first_name, p.last_name, p.display_name)
  ) OR EXISTS (
    SELECT 1 FROM public.contributors c
    JOIN public.organizations o ON o.organization_id = c.organization_id
    WHERE (c.organization_name, c.display_name)
      IS DISTINCT FROM (o.organization_name, o.organization_name)
  ) THEN
    RAISE EXCEPTION 'Role identity differs from the central identity; reconcile before dropping copied columns.';
  END IF;
END $$;

-- The old synchronization triggers are replaced with direct references to
-- people/organizations. Dropping these columns makes copies impossible.
DROP TRIGGER IF EXISTS trg_members_share_person ON public.members;
DROP TRIGGER IF EXISTS trg_contributors_share_party ON public.contributors;
DROP TRIGGER IF EXISTS trg_people_project_identity ON public.people;
DROP TRIGGER IF EXISTS trg_organizations_project_identity ON public.organizations;
DROP FUNCTION IF EXISTS public.member_share_person_identity();
DROP FUNCTION IF EXISTS public.contributor_share_party_identity();
DROP FUNCTION IF EXISTS public.project_person_identity();
DROP FUNCTION IF EXISTS public.project_organization_identity();

ALTER TABLE public.contributors DROP CONSTRAINT IF EXISTS contributors_name_check;
ALTER TABLE public.members
  DROP COLUMN first_name,
  DROP COLUMN last_name,
  DROP COLUMN date_of_birth;
ALTER TABLE public.contributors
  DROP COLUMN display_name,
  DROP COLUMN first_name,
  DROP COLUMN last_name,
  DROP COLUMN organization_name;

-- The current application reads the enriched profiles. These are views: there
-- are no extra stored name or birth-date values in either role table.
CREATE VIEW public.member_profiles AS
SELECT m.*,
  COALESCE(NULLIF(btrim(concat_ws(' ', p.first_name, p.last_name)), ''),
           p.display_name) AS display_name,
  p.first_name, p.last_name, p.date_of_birth
FROM public.members m
JOIN public.people p ON p.person_id = m.person_id;

CREATE VIEW public.contributor_profiles AS
SELECT c.*,
  CASE WHEN c.contributor_type = 'individual'
    THEN COALESCE(NULLIF(btrim(concat_ws(' ', p.first_name, p.last_name)), ''),
                  p.display_name)
    ELSE o.organization_name END AS display_name,
  p.first_name,
  p.last_name,
  o.organization_name
FROM public.contributors c
LEFT JOIN public.people p ON p.person_id = c.person_id
LEFT JOIN public.organizations o ON o.organization_id = c.organization_id;

COMMENT ON VIEW public.member_profiles IS
  'Membership fields with current person details, assembled without copies.';
COMMENT ON VIEW public.contributor_profiles IS
  'Donation-party fields with person or organization details, without copies.';

CREATE OR REPLACE FUNCTION public.create_member_from_intake(
  p_first_name text,
  p_last_name text,
  p_email text DEFAULT NULL,
  p_phone text DEFAULT NULL,
  p_date_of_birth date DEFAULT NULL,
  p_notes text DEFAULT NULL,
  p_is_facilitator boolean DEFAULT false,
  p_created_by_facilitator_id uuid DEFAULT NULL
)
RETURNS TABLE (
  member_id uuid,
  duplicate_blocked boolean
)
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_first_name text := NULLIF(btrim(p_first_name), '');
  v_last_name text := NULLIF(btrim(p_last_name), '');
  v_email text := NULLIF(lower(btrim(p_email)), '');
  v_phone text := NULLIF(btrim(p_phone), '');
  v_phone_normalized text :=
    NULLIF(public.normalize_us_phone(p_phone), '');
  v_member_id uuid;
  v_person_id uuid;
BEGIN
  IF v_first_name IS NULL OR v_last_name IS NULL THEN
    RAISE EXCEPTION 'First and last name are required.';
  END IF;

  -- Intake volume is low. Serialize the duplicate-check/insert section across
  -- the member and contact tables so a concurrent member or contact insert
  -- cannot race the final exact-email or exact-phone check.
  LOCK TABLE
    public.members,
    public.people,
    public.member_emails,
    public.member_phones
  IN SHARE ROW EXCLUSIVE MODE;

  IF (
    v_email IS NOT NULL
    AND (
      EXISTS (
        SELECT 1
        FROM public.members m
        WHERE m.status = 'active'
          AND lower(btrim(m.email)) = v_email
      )
      OR EXISTS (
        SELECT 1
        FROM public.member_emails me
        JOIN public.members m
          ON m.member_id = me.member_id
        WHERE me.email_normalized = v_email
          AND COALESCE(me.status, 'active') = 'active'
          AND m.status = 'active'
      )
    )
  )
  OR (
    v_phone_normalized IS NOT NULL
    AND (
      EXISTS (
        SELECT 1
        FROM public.member_phones mp
        JOIN public.members m
          ON m.member_id = mp.member_id
        WHERE mp.phone_normalized = v_phone_normalized
          AND COALESCE(mp.status, 'active') = 'active'
          AND m.status = 'active'
      )
      OR EXISTS (
        SELECT 1
        FROM public.members m
        WHERE m.status = 'active'
          AND public.normalize_us_phone(m.phone) =
              v_phone_normalized
      )
    )
  )
  OR (
    p_date_of_birth IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM public.members m
      JOIN public.people p ON p.person_id = m.person_id
      WHERE m.status = 'active'
        AND lower(btrim(p.first_name)) =
            lower(v_first_name)
        AND lower(btrim(p.last_name)) =
            lower(v_last_name)
        AND p.date_of_birth = p_date_of_birth
    )
  )
  THEN
    member_id := NULL;
    duplicate_blocked := TRUE;
    RETURN NEXT;
    RETURN;
  END IF;

  BEGIN
    INSERT INTO public.people (display_name, first_name, last_name, date_of_birth)
    VALUES (concat_ws(' ', v_first_name, v_last_name),
      v_first_name, v_last_name, p_date_of_birth)
    RETURNING person_id INTO v_person_id;
    INSERT INTO public.members AS m
      (person_id, email, phone, notes, is_facilitator, created_by_facilitator_id)
    VALUES (v_person_id, v_email, v_phone, NULLIF(btrim(p_notes), ''),
      COALESCE(p_is_facilitator, false), p_created_by_facilitator_id)
    RETURNING m.member_id INTO v_member_id;
  EXCEPTION
    WHEN unique_violation THEN
      member_id := NULL;
      duplicate_blocked := TRUE;
      RETURN NEXT;
      RETURN;
  END;

  member_id := v_member_id;
  duplicate_blocked := FALSE;
  RETURN NEXT;
END;
$$;

CREATE OR REPLACE FUNCTION public.ensure_member_contributor(p_member_id uuid)
RETURNS uuid
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_contributor_id uuid;
  v_member public.member_profiles%ROWTYPE;
BEGIN
  IF p_member_id IS NULL THEN
    RAISE EXCEPTION 'A member is required.';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(p_member_id::text, 190019));

  SELECT cml.contributor_id
  INTO v_contributor_id
  FROM public.contributor_member_links cml
  JOIN public.contributors c ON c.contributor_id = cml.contributor_id
  JOIN public.members m ON m.member_id = cml.member_id
  WHERE cml.member_id = p_member_id
    AND (
      (cml.status = 'active' AND c.status = 'active')
      OR
      (m.status <> 'active' AND cml.status = 'ended' AND c.status = 'archived')
    )
  ORDER BY CASE WHEN cml.status = 'active' THEN 0 ELSE 1 END, cml.linked_at DESC
  LIMIT 1;

  IF v_contributor_id IS NOT NULL THEN
    RETURN v_contributor_id;
  END IF;

  SELECT *
  INTO v_member
  FROM public.member_profiles m
  WHERE m.member_id = p_member_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Member % was not found.', p_member_id;
  END IF;

  -- A person may already have a contributor from an earlier, ended membership
  -- link. Reuse that role instead of violating the unique person identity.
  SELECT c.contributor_id INTO v_contributor_id
  FROM public.contributors c
  WHERE c.person_id = v_member.person_id
    AND c.status = 'active';
  IF FOUND THEN
    IF v_member.status <> 'active' THEN
      RAISE EXCEPTION 'Review the existing contributor for inactive member %.', p_member_id;
    END IF;
    INSERT INTO public.contributor_member_links
      (contributor_id, member_id, status, link_reason)
    VALUES (v_contributor_id, p_member_id, 'active',
      'Re-linked existing contributor to member for Issue #19');
    RETURN v_contributor_id;
  END IF;

  INSERT INTO public.contributors (contributor_type, person_id, status, source, notes)
  VALUES ('individual', v_member.person_id,
    CASE WHEN v_member.status = 'active' THEN 'active' ELSE 'archived' END,
    'member_backfill', 'Created from member identity for Issue #19')
  RETURNING contributor_id INTO v_contributor_id;

  -- Historical donations can reference inactive members. Their contributor is
  -- retained as archived but still receives a historical ended link.
  IF v_member.status = 'active' THEN
    INSERT INTO public.contributor_member_links (
      contributor_id,
      member_id,
      status,
      link_reason
    )
    VALUES (
      v_contributor_id,
      p_member_id,
      'active',
      'Member contributor backfill for Issue #19'
    );
  ELSE
    INSERT INTO public.contributor_member_links (
      contributor_id,
      member_id,
      status,
      link_reason,
      ended_at,
      end_reason
    )
    VALUES (
      v_contributor_id,
      p_member_id,
      'ended',
      'Member contributor backfill for Issue #19',
      now(),
      'Member was not active when contributor identity was created'
    );
  END IF;

  INSERT INTO public.contributor_emails (
    contributor_id, email, is_primary, is_verified, source, notes
  )
  SELECT
    v_contributor_id,
    me.email,
    me.is_primary,
    me.is_verified,
    'member_backfill',
    'Copied from member email for Issue #19'
  FROM public.member_emails me
  WHERE me.member_id = p_member_id
    AND me.status = 'active'
    AND NULLIF(btrim(me.email), '') IS NOT NULL
  ON CONFLICT (contributor_id, email_normalized)
  WHERE status = 'active'
    AND email_normalized IS NOT NULL
    AND email_normalized <> ''
  DO NOTHING;

  IF NOT EXISTS (
    SELECT 1 FROM public.contributor_emails ce
    WHERE ce.contributor_id = v_contributor_id
      AND ce.status = 'active'
  ) AND NULLIF(btrim(v_member.email), '') IS NOT NULL THEN
    INSERT INTO public.contributor_emails (
      contributor_id, email, is_primary, source, notes
    )
    VALUES (
      v_contributor_id,
      v_member.email,
      true,
      'members.email',
      'Copied from member compatibility email for Issue #19'
    )
    ON CONFLICT (contributor_id, email_normalized)
    WHERE status = 'active'
      AND email_normalized IS NOT NULL
      AND email_normalized <> ''
    DO NOTHING;
  END IF;

  INSERT INTO public.contributor_phones (
    contributor_id, phone, is_primary, is_verified, source, notes
  )
  SELECT
    v_contributor_id,
    mp.phone,
    mp.is_primary,
    mp.is_verified,
    'member_backfill',
    'Copied from member phone for Issue #19'
  FROM public.member_phones mp
  WHERE mp.member_id = p_member_id
    AND mp.status = 'active'
    AND NULLIF(public.normalize_us_phone(mp.phone), '') IS NOT NULL
  ON CONFLICT (contributor_id, phone_normalized)
  WHERE status = 'active'
    AND phone_normalized IS NOT NULL
    AND phone_normalized <> ''
  DO NOTHING;

  IF NOT EXISTS (
    SELECT 1 FROM public.contributor_phones cp
    WHERE cp.contributor_id = v_contributor_id
      AND cp.status = 'active'
  ) AND NULLIF(public.normalize_us_phone(v_member.phone), '') IS NOT NULL THEN
    INSERT INTO public.contributor_phones (
      contributor_id, phone, is_primary, source, notes
    )
    VALUES (
      v_contributor_id,
      v_member.phone,
      true,
      'members.phone',
      'Copied from member compatibility phone for Issue #19'
    )
    ON CONFLICT (contributor_id, phone_normalized)
    WHERE status = 'active'
      AND phone_normalized IS NOT NULL
      AND phone_normalized <> ''
    DO NOTHING;
  END IF;

  INSERT INTO public.contributor_addresses (
    contributor_id,
    address_type,
    address_1,
    address_2,
    city,
    state,
    postal_code,
    country,
    is_primary,
    source,
    notes
  )
  SELECT
    v_contributor_id,
    ma.address_type,
    ma.address_1,
    ma.address_2,
    ma.city,
    ma.state,
    ma.postal_code,
    ma.country,
    ma.is_primary,
    'member_backfill',
    'Copied from member address for Issue #19'
  FROM public.member_addresses ma
  WHERE ma.member_id = p_member_id
    AND ma.status = 'active'
  ON CONFLICT (contributor_id, address_identity_key)
  WHERE status = 'active'
    AND address_identity_key IS NOT NULL
    AND address_identity_key <> ''
  DO NOTHING;

  RETURN v_contributor_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_contributor_from_pending_donation(
  p_donation_id uuid,
  p_reviewer_id uuid,
  p_contributor_type text DEFAULT 'individual',
  p_organization_name text DEFAULT NULL,
  p_review_notes text DEFAULT NULL
)
RETURNS public.contributors
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_payload jsonb;
  v_first_name text;
  v_last_name text;
  v_email text;
  v_organization_name text;
  v_display_name text;
  v_contributor public.contributors%ROWTYPE;
  v_person_id uuid;
  v_organization_id uuid;
BEGIN
  IF p_reviewer_id IS NULL OR NOT EXISTS (
    SELECT 1
    FROM public.members m
    WHERE m.member_id = p_reviewer_id
      AND m.status = 'active'
      AND m.is_facilitator IS TRUE
      AND m.is_donations_reviewer IS TRUE
  ) THEN
    RAISE EXCEPTION 'An active donations reviewer is required.';
  END IF;

  IF p_contributor_type NOT IN ('individual', 'organization') THEN
    RAISE EXCEPTION 'Contributor type must be individual or organization.';
  END IF;

  PERFORM 1
  FROM public.donations d
  WHERE d.donation_id = p_donation_id
    AND d.provider <> 'cash'
    AND d.donor_kind = 'unresolved'
    AND d.status = 'pending_review'
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Only an unresolved provider donation can create a contributor.';
  END IF;

  v_payload := COALESCE(public.donation_provider_payload(p_donation_id), '{}'::jsonb);
  v_first_name := NULLIF(btrim(COALESCE(
    v_payload->>'first_name',
    v_payload #>> '{donor,first_name}',
    v_payload #>> '{supporter,first_name}'
  )), '');
  v_last_name := NULLIF(btrim(COALESCE(
    v_payload->>'last_name',
    v_payload #>> '{donor,last_name}',
    v_payload #>> '{supporter,last_name}'
  )), '');
  v_email := NULLIF(lower(btrim(COALESCE(
    v_payload->>'email',
    v_payload #>> '{donor,email}',
    v_payload #>> '{supporter,email}'
  ))), '');
  v_organization_name := NULLIF(btrim(COALESCE(
    p_organization_name,
    v_payload->>'organization_name',
    v_payload->>'company_name',
    v_payload->>'company',
    v_payload->>'business_name',
    v_payload #>> '{donor,company}',
    v_payload #>> '{supporter,company}'
  )), '');

  IF p_contributor_type = 'organization' AND v_organization_name IS NULL THEN
    RAISE EXCEPTION
      'The provider payload has no organization name; enter or correct it before creating an organization contributor.';
  END IF;

  v_display_name := CASE
    WHEN p_contributor_type = 'organization' THEN v_organization_name
    ELSE COALESCE(
      NULLIF(btrim(concat_ws(' ', v_first_name, v_last_name)), ''),
      v_email
    )
  END;

  IF v_display_name IS NULL THEN
    RAISE EXCEPTION 'The provider payload does not contain enough contributor identity.';
  END IF;

  IF p_contributor_type = 'individual' THEN
    INSERT INTO public.people (display_name, first_name, last_name)
    VALUES (v_display_name, v_first_name, v_last_name)
    RETURNING person_id INTO v_person_id;
  ELSE
    INSERT INTO public.organizations (organization_name)
    VALUES (v_organization_name)
    RETURNING organization_id INTO v_organization_id;
  END IF;
  INSERT INTO public.contributors
    (contributor_type, person_id, organization_id, status, source, notes)
  VALUES (p_contributor_type, v_person_id, v_organization_id, 'active',
    'givebutter_review', 'Created from pending donation ' || p_donation_id::text)
  RETURNING * INTO v_contributor;

  PERFORM public.resolve_pending_donation(
    p_donation_id,
    p_reviewer_id,
    v_contributor.contributor_id,
    p_review_notes
  );

  INSERT INTO public.audit_log (actor, action, entity_type, entity_id, details)
  SELECT
    reviewer.email,
    'contributor.created_from_donation',
    'contributor',
    v_contributor.contributor_id::text,
    jsonb_build_object(
      'donation_id', p_donation_id,
      'contributor_type', p_contributor_type,
      'reviewer_id', p_reviewer_id
    )
  FROM public.members reviewer
  WHERE reviewer.member_id = p_reviewer_id;

  RETURN v_contributor;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_member_from_pending_donation(
  p_donation_id uuid,
  p_reviewer_id uuid,
  p_review_notes text DEFAULT NULL
)
RETURNS public.members
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_payload jsonb;
  v_contributor public.contributors%ROWTYPE;
  v_first_name text;
  v_last_name text;
  v_member public.members%ROWTYPE;
  v_member_id uuid;
  v_duplicate_blocked boolean;
BEGIN
  SELECT *
  INTO v_contributor
  FROM public.create_contributor_from_pending_donation(
    p_donation_id,
    p_reviewer_id,
    'individual',
    NULL,
    p_review_notes
  );

  SELECT p.first_name, p.last_name INTO v_first_name, v_last_name
  FROM public.people p WHERE p.person_id = v_contributor.person_id;

  v_payload := COALESCE(public.donation_provider_payload(p_donation_id), '{}'::jsonb);

  SELECT created.member_id, created.duplicate_blocked
  INTO v_member_id, v_duplicate_blocked
  FROM public.create_member_from_intake(
    p_first_name => v_first_name,
    p_last_name => v_last_name,
    p_email => COALESCE(
      v_payload->>'email',
      v_payload #>> '{donor,email}',
      v_payload #>> '{supporter,email}'
    ),
    p_phone => COALESCE(
      v_payload->>'phone',
      v_payload #>> '{donor,phone}',
      v_payload #>> '{supporter,phone}'
    ),
    p_date_of_birth => NULL,
    p_notes => 'Created from pending donation ' || p_donation_id::text,
    p_is_facilitator => false,
    p_created_by_facilitator_id => p_reviewer_id
  ) created;

  IF COALESCE(v_duplicate_blocked, false) OR v_member_id IS NULL THEN
    RAISE EXCEPTION
      'Member creation was blocked by an existing identity. Resolve the donation to the existing member/contributor instead.';
  END IF;

  PERFORM public.link_contributor_to_member(
    v_contributor.contributor_id,
    v_member_id,
    p_reviewer_id,
    'Member created from pending donation ' || p_donation_id::text
  );

  INSERT INTO public.member_emails (
    member_id,
    email,
    is_primary,
    is_verified,
    source,
    notes
  )
  SELECT
    v_member_id,
    ce.email,
    ce.is_primary,
    ce.is_verified,
    'contributor_promotion',
    'Copied from contributor ' || v_contributor.contributor_id::text
  FROM public.contributor_emails ce
  WHERE ce.contributor_id = v_contributor.contributor_id
    AND ce.status = 'active'
  ON CONFLICT (email_normalized)
  WHERE email_normalized IS NOT NULL
    AND email_normalized <> ''
    AND status = 'active'
  DO NOTHING;

  INSERT INTO public.member_phones (
    member_id,
    phone,
    is_primary,
    is_verified,
    source,
    notes
  )
  SELECT
    v_member_id,
    cp.phone,
    cp.is_primary,
    cp.is_verified,
    'contributor_promotion',
    'Copied from contributor ' || v_contributor.contributor_id::text
  FROM public.contributor_phones cp
  WHERE cp.contributor_id = v_contributor.contributor_id
    AND cp.status = 'active'
    AND NOT EXISTS (
      SELECT 1
      FROM public.member_phones mp
      WHERE mp.member_id = v_member_id
        AND mp.phone_normalized = cp.phone_normalized
        AND mp.status = 'active'
    );

  PERFORM public.upsert_member_address(
    p_member_id => v_member_id,
    p_address_1 => ca.address_1,
    p_address_type => COALESCE(NULLIF(ca.address_type, ''), 'home'),
    p_address_2 => ca.address_2,
    p_city => ca.city,
    p_state => ca.state,
    p_postal_code => ca.postal_code,
    p_country => ca.country,
    p_is_primary => ca.is_primary,
    p_source => 'contributor_promotion',
    p_notes => 'Copied from contributor ' || v_contributor.contributor_id::text
  )
  FROM public.contributor_addresses ca
  WHERE ca.contributor_id = v_contributor.contributor_id
    AND ca.status = 'active'
    AND NULLIF(btrim(ca.address_1), '') IS NOT NULL;

  SELECT * INTO v_member
  FROM public.members m
  WHERE m.member_id = v_member_id;

  RETURN v_member;
END;
$$;

CREATE OR REPLACE FUNCTION public.reconcile_linked_person()
RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
DECLARE
  v_member_person uuid;
  v_donor_person uuid;
  v_keep uuid;
  v_drop uuid;
  v_member_name text;
  v_donor_name text;
  v_member_first text;
  v_member_last text;
  v_donor_first text;
  v_donor_last text;
BEGIN
  IF NEW.status <> 'active' THEN RETURN NULL; END IF;
  SELECT m.person_id, p.display_name, p.first_name, p.last_name
    INTO v_member_person, v_member_name, v_member_first, v_member_last
    FROM public.members m JOIN public.people p ON p.person_id = m.person_id
    WHERE m.member_id = NEW.member_id FOR UPDATE OF m;
  SELECT c.person_id, p.display_name, p.first_name, p.last_name
    INTO v_donor_person, v_donor_name, v_donor_first, v_donor_last
    FROM public.contributors c JOIN public.people p ON p.person_id = c.person_id
    WHERE c.contributor_id = NEW.contributor_id FOR UPDATE OF c;

  IF v_member_person = v_donor_person THEN RETURN NULL; END IF;
  SELECT CASE WHEN cp.created_at < mp.created_at
              THEN v_donor_person ELSE v_member_person END
  INTO v_keep
  FROM public.people cp CROSS JOIN public.people mp
  WHERE cp.person_id = v_donor_person AND mp.person_id = v_member_person;

  INSERT INTO public.person_identity_review
    (person_id, member_id, contributor_id, member_name, contributor_name,
     member_names, contributor_names)
  SELECT v_keep, NEW.member_id, NEW.contributor_id,
    v_member_name, v_donor_name,
    jsonb_build_object('first_name', v_member_first, 'last_name', v_member_last),
    jsonb_build_object('first_name', v_donor_first, 'last_name', v_donor_last)
  WHERE (v_member_first, v_member_last, lower(btrim(v_member_name)))
    IS DISTINCT FROM (v_donor_first, v_donor_last, lower(btrim(v_donor_name)))
  ON CONFLICT (member_id, contributor_id) DO NOTHING;

  IF v_keep = v_donor_person THEN
    v_drop := v_member_person;
    UPDATE public.members SET person_id = v_keep WHERE member_id = NEW.member_id;
  ELSE
    v_drop := v_donor_person;
    UPDATE public.contributors SET person_id = v_keep
    WHERE contributor_id = NEW.contributor_id;
  END IF;

  DELETE FROM public.people p WHERE p.person_id = v_drop
    AND NOT EXISTS (SELECT 1 FROM public.members m WHERE m.person_id = v_drop)
    AND NOT EXISTS (SELECT 1 FROM public.contributors c WHERE c.person_id = v_drop)
    AND NOT EXISTS (SELECT 1 FROM public.person_identity_review r WHERE r.person_id = v_drop);
  RETURN NULL;
END $$;

COMMIT;

SELECT (SELECT count(*) FROM public.members WHERE person_id IS NULL)
         AS members_without_people,
       (SELECT count(*) FROM public.contributors
         WHERE contributor_type = 'individual' AND person_id IS NULL)
         AS individuals_without_people,
       (SELECT count(*) FROM public.contributors
         WHERE contributor_type = 'organization' AND organization_id IS NULL)
         AS organizations_without_identity,
       (SELECT count(*) FROM public.person_identity_review WHERE resolved_at IS NULL)
         AS identity_names_to_review;
