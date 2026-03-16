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
4. Match or create member by email
5. Insert donation with status `verified`
6. Write audit log entry

## Notes
- Duplicate transactions are ignored
- Donations without an email address will not create members