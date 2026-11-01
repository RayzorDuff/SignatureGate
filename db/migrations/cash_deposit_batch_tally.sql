-- Cash deposit batch tally/read surface.
-- This migration is operational only; ERPNext synchronization remains separate.
\set ON_ERROR_STOP on
BEGIN;

CREATE OR REPLACE VIEW public.cash_deposit_batch_tally AS
SELECT
  b.deposit_batch_id,
  b.status,
  b.created_at AS batch_created_at,
  b.updated_at AS batch_updated_at,
  b.deposit_date,
  b.deposit_slip_number,
  b.destination_bank_account,
  b.preparer_id,
  prep.email AS preparer_email,
  b.prepared_by,
  b.prepared_at,
  b.verifier_id,
  ver.email AS verifier_email,
  b.confirmed_at,
  b.cancelled_at,
  b.cancelled_by,
  b.expected_amount_cents,
  b.actual_amount_cents,
  count(i.deposit_batch_item_id) OVER (
    PARTITION BY b.deposit_batch_id
  ) AS item_count,
  COALESCE(
    sum(i.amount_cents) OVER (
      PARTITION BY b.deposit_batch_id
    ),
    0
  ) AS item_total_cents,
  i.deposit_batch_item_id,
  i.created_at AS item_created_at,
  i.donation_id,
  i.amount_cents AS item_amount_cents,
  d.donated_at,
  d.currency,
  d.donor_kind,
  d.member_id,
  d.contributor_id,
  d.notes AS donation_notes
FROM public.cash_deposit_batches b
LEFT JOIN public.cash_deposit_batch_items i
  ON i.deposit_batch_id = b.deposit_batch_id
 AND i.removed_at IS NULL
LEFT JOIN public.members prep
  ON prep.member_id = b.preparer_id
LEFT JOIN public.members ver
  ON ver.member_id = b.verifier_id
LEFT JOIN public.donations d
  ON d.donation_id = i.donation_id;

COMMENT ON VIEW public.cash_deposit_batch_tally IS
  'Authoritative active-item cash deposit batch tally for operational review and printable deposit documentation. Contributor-neutral; donor identity remains on the donation.';

COMMIT;
