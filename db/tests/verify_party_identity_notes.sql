BEGIN;
DO $$
DECLARE v_count integer;
BEGIN
 SELECT count(*) INTO v_count FROM information_schema.columns
 WHERE table_schema='public' AND ((table_name='people' AND column_name='notes') OR (table_name='organizations' AND column_name='notes'));
 IF v_count<>2 THEN RAISE EXCEPTION 'Canonical note columns missing'; END IF;
 IF to_regprocedure('public.issue19_party_notes(text,text,uuid)') IS NULL OR
    to_regprocedure('public.issue19_set_party_notes(text,text,uuid,text,text)') IS NULL THEN
  RAISE EXCEPTION 'Identity notes API missing';
 END IF;
 RAISE NOTICE 'Canonical identity notes schema and API available; rolling back verification';
END $$;
ROLLBACK;
