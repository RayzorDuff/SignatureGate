# Givebutter Webhook Integration

## Endpoint
POST /webhook/signaturegate/givebutter/transactions

## Events Handled
- transaction.succeeded

## Security
- Optional shared-secret validation via `Signature` header
- Controlled by `GIVEBUTTER_SIGNING_SECRET` environment variable in n8n

## Processing Flow
1. Receive webhook
2. Validate signature (if enabled)
3. Normalize donor and transaction data
4. Call `public.ingest_provider_donation(...)`
5. Match, in order, by Givebutter contact identity, unique contributor email,
   unique member email fallback, unique contributor phone, then unique member
   phone fallback
6. Insert the donation as `verified` when matched or `pending_review` when
   unresolved, preserving the raw payload in the audit log

## Notes
- `(provider, provider_reference)` is a database-enforced idempotency key, so
  duplicate webhook deliveries return the existing donation.
- The webhook never creates a member. Reviewers may create an individual or
  organization contributor, create a linked member, or assign the donation to
  an existing contributor/member in Appsmith.
- An ambiguous shared email or phone remains unresolved instead of being
  automatically assigned.

## Provider identity typing
Givebutter contact identifiers may arrive in webhook JSON as numbers. SignatureGate
stores external provider identities as text, and `public.ingest_provider_donation(...)`
accepts `p_provider_identity text`. The workflow therefore converts `contact_id` to a
string during normalization and explicitly casts the PostgreSQL bind parameter to
`text`. Do not remove that cast when editing the Postgres node; otherwise PostgreSQL
may try to resolve an `integer` overload of the ingestion function and reject the
call before the donation is inserted.

## Replaying a failed webhook
The provider/reference pair is the database idempotency key, so a failed or duplicate
delivery can be retried safely after the workflow fix is deployed. Prefer retrying the
failed n8n execution with the currently saved workflow so the original webhook body
is reused. If a manual replay is necessary, copy the original Webhook node input from
the failed execution and POST that JSON to the production webhook endpoint. Include
the configured `Signature` header when `GIVEBUTTER_SIGNING_SECRET` is enabled.

Before replaying, verify that the Issue #19 ingestion function is installed:

```sql
SELECT p.oid::regprocedure
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'ingest_provider_donation';
```

The expected signature ends with `text, text, text` for email, phone, and provider
identity. After replay, verify the transaction by provider reference rather than by
donor name:

```sql
SELECT donation_id, contributor_id, member_id, donor_kind, provider,
       provider_reference, amount_cents, currency, donated_at, status
FROM public.donations
WHERE provider = 'givebutter'
  AND provider_reference = '<givebutter-transaction-id>';
```
