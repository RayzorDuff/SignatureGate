-- Canonical party notes; preserve member notes as historical source data.
\set ON_ERROR_STOP on
BEGIN;
ALTER TABLE public.people ADD COLUMN IF NOT EXISTS notes text;
ALTER TABLE public.organizations ADD COLUMN IF NOT EXISTS notes text;
COMMENT ON COLUMN public.people.notes IS 'Administrative notes about the individual identity; not limited to membership.';
COMMENT ON COLUMN public.organizations.notes IS 'Administrative notes about the organization identity.';

-- Store provenance, not a second copy of private notes. One decision per historical
-- membership prevents later reruns from undoing an identity edit or clear.
CREATE TABLE IF NOT EXISTS public.member_identity_note_backfill (
  member_id uuid PRIMARY KEY REFERENCES public.members(member_id),
  person_id uuid NOT NULL REFERENCES public.people(person_id),
  outcome text NOT NULL CHECK (outcome IN ('imported','already_present','preserved_edit','blank')),
  processed_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE OR REPLACE FUNCTION public.backfill_member_identity_notes()
RETURNS integer LANGUAGE plpgsql SECURITY INVOKER
SET search_path TO 'public','pg_temp' AS $backfill$
DECLARE
  v_person uuid;
  v_member record;
  v_notes text;
  v_chunk text;
  v_edited boolean;
  v_outcome text;
  v_processed integer := 0;
BEGIN
  FOR v_person IN
    SELECT DISTINCT m.person_id FROM public.members m
    WHERE NOT EXISTS (SELECT 1 FROM public.member_identity_note_backfill b WHERE b.member_id=m.member_id)
    ORDER BY m.person_id
  LOOP
    -- Serialize migration reruns with each other and with canonical note edits.
    SELECT p.notes INTO v_notes FROM public.people p WHERE p.person_id=v_person FOR UPDATE;
    SELECT EXISTS (SELECT 1 FROM public.audit_log a
      WHERE a.action='party.notes_updated' AND a.entity_type='individual'
        AND a.entity_id=v_person::text) INTO v_edited;
    FOR v_member IN
      SELECT m.member_id,m.notes FROM public.members m WHERE m.person_id=v_person
      ORDER BY m.created_at,m.member_id FOR SHARE
    LOOP
      IF EXISTS (SELECT 1 FROM public.member_identity_note_backfill b WHERE b.member_id=v_member.member_id) THEN
        CONTINUE;
      END IF;
      v_chunk := 'Member ' || v_member.member_id::text || ': ' || btrim(v_member.notes);
      IF NULLIF(btrim(v_member.notes),'') IS NULL THEN
        v_outcome := 'blank';
      ELSIF v_edited THEN
        -- A prior canonical edit (including clearing notes) takes precedence.
        -- The original source is retained for private operator review.
        v_outcome := 'preserved_edit';
      ELSIF position(v_chunk IN COALESCE(v_notes,'')) > 0 THEN
        v_outcome := 'already_present';
      ELSE
        v_notes := CASE WHEN NULLIF(btrim(v_notes),'') IS NULL THEN v_chunk
          ELSE v_notes || E'\n\n' || v_chunk END;
        UPDATE public.people SET notes=v_notes WHERE person_id=v_person;
        v_outcome := 'imported';
      END IF;
      INSERT INTO public.member_identity_note_backfill(member_id,person_id,outcome)
        VALUES(v_member.member_id,v_person,v_outcome);
      v_processed := v_processed + 1;
    END LOOP;
  END LOOP;
  RETURN v_processed;
END;
$backfill$;
REVOKE ALL ON FUNCTION public.backfill_member_identity_notes() FROM PUBLIC;
COMMENT ON FUNCTION public.backfill_member_identity_notes() IS
  'Operator-only, one-time historical member-note import; preserves canonical edits and original member notes. Review preserved_edit sources privately.';

CREATE OR REPLACE FUNCTION public.issue19_party_notes(p_actor_email text,p_party_kind text,p_party_id uuid)
RETURNS TABLE(notes text,can_edit boolean)
LANGUAGE plpgsql STABLE SET search_path TO 'public','pg_temp' AS $$
BEGIN
 IF NOT (public.issue19_has_role(p_actor_email,'directory_manager')
  OR public.issue19_has_role(p_actor_email,'document_reviewer')
  OR public.issue19_has_role(p_actor_email,'donations_reviewer')) THEN RETURN; END IF;
 IF NOT EXISTS (SELECT 1 FROM public.issue19_directory_entries(p_actor_email) d
   WHERE d.party_kind=p_party_kind AND d.party_id=p_party_id) THEN RETURN; END IF;
 IF p_party_kind='individual' THEN
   RETURN QUERY SELECT p.notes,true FROM public.people p WHERE p.person_id=p_party_id;
 ELSIF p_party_kind='organization' THEN
   RETURN QUERY SELECT o.notes,true FROM public.organizations o WHERE o.organization_id=p_party_id;
 END IF;
END; $$;

CREATE OR REPLACE FUNCTION public.issue19_set_party_notes(p_actor_email text,p_party_kind text,p_party_id uuid,p_notes text,p_reason text)
RETURNS uuid LANGUAGE plpgsql SET search_path TO 'public','pg_temp' AS $$
DECLARE v_old text; v_new text:=NULLIF(btrim(p_notes),'');
BEGIN
 IF NULLIF(btrim(p_reason),'') IS NULL THEN RAISE EXCEPTION 'A reason for changing notes is required'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.issue19_party_notes(p_actor_email,p_party_kind,p_party_id)) THEN
   RAISE EXCEPTION 'Not authorized to edit identity notes';
 END IF;
 IF p_party_kind='individual' THEN
   SELECT p.notes INTO v_old FROM public.people p WHERE p.person_id=p_party_id FOR UPDATE;
   UPDATE public.people SET notes=v_new WHERE person_id=p_party_id;
 ELSIF p_party_kind='organization' THEN
   SELECT o.notes INTO v_old FROM public.organizations o WHERE o.organization_id=p_party_id FOR UPDATE;
   UPDATE public.organizations SET notes=v_new WHERE organization_id=p_party_id;
 ELSE RAISE EXCEPTION 'Invalid party kind'; END IF;
 IF v_old IS NOT DISTINCT FROM v_new THEN RETURN p_party_id; END IF;
 INSERT INTO public.audit_log(actor,action,entity_type,entity_id,details)
 VALUES (lower(btrim(p_actor_email)),'party.notes_updated',p_party_kind,p_party_id::text,
 jsonb_build_object('reason',btrim(p_reason),'previous',v_old,'current',v_new));
 RETURN p_party_id;
END; $$;

-- Return only a count; never print the imported notes.
SELECT public.backfill_member_identity_notes() AS historical_memberships_processed;
COMMIT;
