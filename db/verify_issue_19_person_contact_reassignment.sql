-- Issue #19 verification: person contact reassignment.
\set ON_ERROR_STOP on

SELECT to_regprocedure(
  'public.issue19_reassign_person_contact(text,uuid,text,text,uuid,uuid,text)'
) AS reassign_function;

SELECT tg.tgname, c.relname AS source_table
FROM pg_trigger tg
JOIN pg_class c ON c.oid = tg.tgrelid
WHERE tg.tgname IN (
  'trg_member_emails_party_contact',
  'trg_member_phones_party_contact',
  'trg_member_addresses_party_contact',
  'trg_contributor_emails_party_contact',
  'trg_contributor_phones_party_contact',
  'trg_contributor_addresses_party_contact'
)
ORDER BY c.relname;

DO $$
BEGIN
  IF to_regprocedure(
    'public.issue19_reassign_person_contact(text,uuid,text,text,uuid,uuid,text)'
  ) IS NULL THEN
    RAISE EXCEPTION 'Issue #19 person contact reassignment function is missing';
  END IF;

  IF (
    SELECT count(*)
    FROM pg_trigger tg
    JOIN pg_class c ON c.oid = tg.tgrelid
    WHERE tg.tgname IN (
      'trg_member_emails_party_contact',
      'trg_member_phones_party_contact',
      'trg_member_addresses_party_contact',
      'trg_contributor_emails_party_contact',
      'trg_contributor_phones_party_contact',
      'trg_contributor_addresses_party_contact'
    )
  ) <> 6 THEN
    RAISE EXCEPTION 'Expected all six party-contact source synchronization triggers';
  END IF;
END $$;

SELECT 'Issue #19 person contact reassignment verification passed.' AS status;
