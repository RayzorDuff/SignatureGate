-- Canonical party notes; preserve member notes as historical source data.
ALTER TABLE public.people ADD COLUMN IF NOT EXISTS notes text;
ALTER TABLE public.organizations ADD COLUMN IF NOT EXISTS notes text;
COMMENT ON COLUMN public.people.notes IS 'Administrative notes about the individual identity; not limited to membership.';
COMMENT ON COLUMN public.organizations.notes IS 'Administrative notes about the organization identity.';

WITH legacy AS (
  SELECT m.person_id, string_agg('Member ' || m.member_id::text || ': ' || btrim(m.notes), E'\n\n' ORDER BY m.created_at, m.member_id) AS notes
  FROM public.members m
  WHERE m.person_id IS NOT NULL AND NULLIF(btrim(m.notes),'') IS NOT NULL
  GROUP BY m.person_id
)
UPDATE public.people p SET notes = CASE
  WHEN NULLIF(btrim(p.notes),'') IS NULL THEN legacy.notes
  ELSE p.notes || E'\n\n' || legacy.notes
END
FROM legacy WHERE p.person_id=legacy.person_id
  AND position(legacy.notes IN COALESCE(p.notes,''))=0;

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
