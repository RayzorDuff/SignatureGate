CREATE INDEX IF NOT EXISTS idx_member_agreements_signed_report
  ON public.member_agreements (
    status,
    signed_at,
    reviewed_at,
    verified_at
  )
  WHERE lower(COALESCE(status, '')) = 'signed';

CREATE INDEX IF NOT EXISTS idx_releases_report
  ON public.releases (
    released_at,
    created_at,
    status
  );

CREATE INDEX IF NOT EXISTS idx_donations_report
  ON public.donations (
    donated_at,
    created_at,
    status
  );

CREATE INDEX IF NOT EXISTS idx_members_created_report
  ON public.members (
    created_at,
    status
  );

