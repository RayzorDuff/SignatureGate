BEGIN;

DO $$
DECLARE
  v_missing integer;
BEGIN
  SELECT count(*)
  INTO v_missing
  FROM (
    VALUES
      ('deposit_batch_id'),
      ('status'),
      ('deposit_date'),
      ('deposit_slip_number'),
      ('destination_bank_account'),
      ('preparer_email'),
      ('prepared_at'),
      ('verifier_email'),
      ('confirmed_at'),
      ('expected_amount_cents'),
      ('actual_amount_cents'),
      ('donation_id'),
      ('donated_at'),
      ('donor_kind'),
      ('donor_name'),
      ('provider_reference'),
      ('donation_notes'),
      ('review_notes'),
      ('item_amount_cents')
  ) AS required(column_name)
  WHERE NOT EXISTS (
    SELECT 1
    FROM information_schema.columns c
    WHERE c.table_schema = 'public'
      AND c.table_name = 'cash_deposit_batch_print'
      AND c.column_name = required.column_name
  );

  IF v_missing <> 0 THEN
    RAISE EXCEPTION
      'cash_deposit_batch_print is missing % required column(s).',
      v_missing;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_views
    WHERE schemaname = 'public'
      AND viewname = 'cash_deposit_batch_print'
  ) THEN
    RAISE EXCEPTION 'cash_deposit_batch_print view was not created.';
  END IF;

  RAISE NOTICE 'Cash deposit print report checks passed.';
END
$$;

ROLLBACK;
