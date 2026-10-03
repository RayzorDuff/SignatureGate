-- Regression checks for cash donation reconciliation exceptions.

\set ON_ERROR_STOP on

DO $$
BEGIN
  IF to_regclass('public.cash_deposit_donation_exclusions') IS NULL THEN
    RAISE EXCEPTION 'cash_deposit_donation_exclusions table is missing';
  END IF;

  IF to_regprocedure('public.exclude_cash_donation_from_deposit(uuid,uuid,text,text)') IS NULL THEN
    RAISE EXCEPTION 'exclude_cash_donation_from_deposit function is missing';
  END IF;

  IF to_regprocedure('public.cash_on_hand_donations()') IS NULL THEN
    RAISE EXCEPTION 'cash_on_hand_donations function is missing';
  END IF;
END
$$;

SELECT
  has_table_privilege(
    current_user,
    'public.cash_deposit_donation_exclusions',
    'SELECT'
  ) AS exclusions_selectible;

SELECT
  has_function_privilege(
    current_user,
    'public.exclude_cash_donation_from_deposit(uuid,uuid,text,text)',
    'EXECUTE'
  ) AS exclusion_function_executable;

SELECT 'cash donation reconciliation exception schema checks passed' AS result;
