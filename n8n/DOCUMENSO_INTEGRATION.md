# Documenso integration (Appsmith ↔ n8n ↔ Documenso ↔ Postgres)

This project uses **n8n** as the integration/orchestration layer between:
- Appsmith (operator UI)
- SignatureGate Postgres (system of record)
- Documenso (email + signing workflow)
- NocoDB (optional admin UI over Postgres)

## Prerequisites

1. Documenso is reachable at your public URL (example: `https://documenso.danks.store`).
2. You have a Documenso API token.
3. The Documenso template envelope exists (example: `envelope_hyneotebbuzwfzly`) and has two recipient slots:
   - Recipient **5** = Member
   - Recipient **6** = Facilitator

## Database migration / seeding

Run:

```bash
psql "$SIGNATUREGATE_DATABASE_URL" -f db/migrations_documenso_integration.sql
```

This adds the Documenso columns and seeds the active `sacrament_release` template row with:
- `documenso_template_envelope_id`
- `documenso_member_recipient_id`
- `documenso_facilitator_recipient_id`

If you have multiple templates, adjust the `UPDATE` in the migration.

## n8n environment variables

Set these as environment variables for your n8n container (recommended), or configure directly in the workflow nodes:

- `DOCUMENSO_BASE_URL` (example: `https://documenso.danks.store`)
- `DOCUMENSO_API_TOKEN` (value looks like `api_...`)

## Import workflows

Two workflow exports are included under `n8n/workflows/`:

1. `documenso_send_release.json`
   - Webhook: `POST /webhook/signaturegate/documenso/send`
   - Input body:
     ```json
     { "member_agreement_id": "<uuid>" }
     ```
   - Behavior:
     - Loads member + facilitator + active template
     - Calls Documenso `POST /api/v2/envelope/use` with `distributeDocument=true`
     - Updates `member_agreements` with `signature_method='documenso'`, `status='pending_signature'`, and Documenso identifiers

2. `documenso_webhook_events.json`
   - Webhook: `POST /webhook/signaturegate/documenso/events`
   - Behavior:
     - Accepts Documenso webhook events (e.g. `document.completed`)
     - Updates `member_agreements.status` accordingly (`signed`, `cancelled`, `rejected`, etc.)

### Postgres credentials in n8n

Both workflows reference a Postgres credential named:

- `SIGNATUREGATE_POSTGRES`

Rename this in n8n to match, **or** edit the workflow JSON and replace that credential name with your actual credential name.

## Configure Documenso webhooks

In Documenso Admin → Webhooks, create a webhook pointing to:

- `https://n8n.<your-domain>/webhook/signaturegate/documenso/events`

Select events at minimum:
- `document.sent`
- `document.signed`
- `document.completed`
- `document.rejected`
- `document.cancelled`

(Exact event names may vary slightly by Documenso version; the workflow normalizes the common ones.)

## Appsmith wiring

### API action (recommended)

Create an Appsmith **API** (or JS fetch) to call n8n:

- Method: `POST`
- URL:
  - `https://n8n.<your-domain>/webhook/signaturegate/documenso/send`
- Body:
  ```json
  { "member_agreement_id": "{{ AgreementsTable.selectedRow.member_agreement_id }}" }
  ```

Attach this to your **Send Digital Release** button in Members – Profile.

After calling the webhook, refresh your `member_agreements` query to show the new status and Documenso ID.

## Status mapping

Recommended status values in `member_agreements.status`:
- `pending` (created but not sent)
- `pending_signature` (Documenso distributed)
- `signed` (Documenso completed)
- `rejected`
- `cancelled`

If you prefer different labels, update the `Normalize Event` node and the `PG - Update member_agreements` node in the workflows.
