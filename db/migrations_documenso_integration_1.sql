ALTER TABLE member_agreements
  ADD COLUMN IF NOT EXISTS documenso_completed_pdf_uploaded_at timestamptz;
