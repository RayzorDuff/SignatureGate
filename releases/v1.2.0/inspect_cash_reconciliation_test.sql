-- Read-only summary. IDs, contacts, amounts, rationale and configuration never leave SQL.
\set ON_ERROR_STOP on
BEGIN READ ONLY;
WITH events AS (
 SELECT entity_id,created_at,row_number() OVER (ORDER BY created_at DESC,audit_log_id DESC) AS position
 FROM public.audit_log
 WHERE action='cash_donation.deposit_reconciliation_excluded' AND entity_type='donation'
 ORDER BY created_at DESC,audit_log_id DESC LIMIT 2
), latest AS (SELECT * FROM events WHERE position=1), prior AS (SELECT * FROM events WHERE position=2)
SELECT jsonb_build_object(
 'database_name',current_database(),
 'comparison_scope','latest_two_cash_exclusions',
 'intake_contact_reuse_api_available',to_regprocedure('public.issue19_assign_person_contact_role(text,uuid,text,uuid,text)') IS NOT NULL,
 'contributor_mailing_intake_api_available',to_regprocedure('public.issue19_create_contributor_with_mailing(text,text,text,text,text,text,text,text,boolean)') IS NOT NULL,
 'available_exclusion_events',(SELECT count(*) FROM events),
 'latest_two_exclusions_same_donation',(SELECT latest.entity_id=prior.entity_id FROM latest CROSS JOIN prior),
 'verification_between_for_prior_donation',(SELECT EXISTS(SELECT 1 FROM public.audit_log a WHERE a.entity_id=prior.entity_id AND a.entity_type='donation' AND a.action='donation.verified' AND a.created_at>prior.created_at AND a.created_at<latest.created_at) FROM latest CROSS JOIN prior),
 'latest_exclusion_donation_is_verified',(SELECT d.status='verified' FROM public.donations d JOIN latest ON d.donation_id::text=latest.entity_id),
 'latest_exclusion_is_currently_active',(SELECT EXISTS(SELECT 1 FROM public.cash_deposit_donation_exclusions e WHERE e.donation_id::text=latest.entity_id) FROM latest)
);
ROLLBACK;
