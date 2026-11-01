BEGIN;

CREATE OR REPLACE VIEW public.cash_deposit_batch_print AS
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
  b.notes AS batch_notes,

  i.deposit_batch_item_id,
  i.created_at AS item_added_at,
  i.donation_id,
  i.amount_cents AS item_amount_cents,

  d.donated_at,
  d.currency,
  d.donor_kind,
  d.provider_reference,
  d.notes AS donation_notes,
  d.review_notes,

  cp.display_name AS donor_name,
  cp.first_name AS donor_first_name,
  cp.last_name AS donor_last_name,
  cp.organization_name AS donor_organization_name

FROM public.cash_deposit_batches b
JOIN public.cash_deposit_batch_items i
  ON i.deposit_batch_id = b.deposit_batch_id
 AND i.removed_at IS NULL
JOIN public.donations d
  ON d.donation_id = i.donation_id
LEFT JOIN public.contributor_profiles cp
  ON cp.contributor_id = d.contributor_id
LEFT JOIN public.members prep
  ON prep.member_id = b.preparer_id
LEFT JOIN public.members ver
  ON ver.member_id = b.verifier_id
WHERE b.status IN ('prepared', 'confirmed');

COMMENT ON VIEW public.cash_deposit_batch_print IS
  'Printable accounting detail for prepared or confirmed cash deposit batches. One row per active donation, with batch header fields repeated for report generation.';

COMMIT;
