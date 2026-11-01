# Documenso integration (Appsmith ↔ n8n ↔ Documenso ↔ Postgres)

This project uses **n8n** as the integration/orchestration layer between:
- Appsmith (operator UI)
- SignatureGate Postgres (system of record)
- Documenso (email + signing workflow)
- NocoDB (optional admin UI over Postgres)

## Prerequisites

1. Documenso is reachable at your public URL (example: `https://signing.example.invalid`).
2. You have a Documenso API token.
3. The Documenso template envelope exists (deployment-specific envelope ID) and has two recipient slots:
   - Participant recipient slot
   - Practitioner recipient slot

## Database setup and template configuration

A fresh deployment loads `db/schema.sql`, which includes the Documenso columns and signing APIs. Follow `db/README.md` for bootstrap and initial agreement-template setup. For an existing database, apply only the reviewed forward changes in the release manifest; do not replay retired migration files or bootstrap over operational records.

Configure the actual template through `Agreement Templates`. Review its envelope and recipient slots privately, then set:

- `documenso_template_envelope_id`
- `documenso_member_recipient_id`
- `documenso_facilitator_recipient_id`

The last two field names are stable compatibility contracts; their labels may change with deployment terminology. Do not assume a recipient ID identifies a person or reuse another deployment's recipient IDs. Existing signed agreements are not rewritten by a label change.

## n8n environment variables

Set these as environment variables for your n8n container (recommended), or configure directly in the workflow nodes:

- `DOCUMENSO_BASE_URL` (example: `https://signing.example.invalid`)
- `DOCUMENSO_API_TOKEN` (value looks like `api_...`)

## Import workflows

Two workflow exports are included under `n8n/workflows/`:

1. `SignatureGate - Documenso - Send Release (Member+Facilitator)`
   - Webhook: `POST /webhook/signaturegate/documenso/send`
   - Input body:
     ```json
     { "member_agreement_id": "<uuid>" }
     ```
   - Behavior:
     - Loads the participant, the canonical practitioner person, and active template
       (the existing `facilitator_*` Documenso recipient fields are retained as
       compatibility contracts)
     - Calls Documenso `POST /api/v2/envelope/use` with `distributeDocument=true`
     - Updates `member_agreements` with `signature_method='documenso'`, `status='pending_signature'`, and Documenso identifiers

2. `SignatureGate - Documenso - Webhook Events.json`
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

Attach this to your **Send Digital Release** button in Participants – Profile.

After calling the webhook, refresh your `member_agreements` query to show the new status and Documenso ID.

## Status mapping

Recommended status values in `member_agreements.status`:
- `pending` (created but not sent)
- `pending_signature` (Documenso distributed)
- `signed` (Documenso completed)
- `rejected`
- `cancelled`

If you prefer different labels, update the `Normalize Event` node and the `PG - Update member_agreements` node in the workflows.
