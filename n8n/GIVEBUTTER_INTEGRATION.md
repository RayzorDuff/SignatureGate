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
