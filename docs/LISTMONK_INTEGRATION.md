# Listmonk mailing-list integration

This integration keeps SignatureGate as the system of record for member identity and consent while using Listmonk for newsletter delivery, unsubscribe links, and campaign management.

## Database model

`db/migrations_listmonk_mailing_list.sql` adds mailing-list state to `member_emails` and creates `listmonk_sync_queue` as an outbox for n8n.

New email rows default to `mailing_subscription_status = 'subscribed'`. Appsmith creation flows can opt out by passing `not_subscribed` instead.

Important statuses:

- `subscribed`: SignatureGate should queue/sync this email to the configured Listmonk list.
- `not_subscribed`: the email exists in SignatureGate but should not be added to Listmonk.
- `unsubscribed`: the email has opted out, either from SignatureGate or from Listmonk.
- `suppressed`: manually suppressed; do not add to Listmonk.
- `sync_error`: n8n/Listmonk sync failed and needs review.

## n8n workflows

Import these workflows:

- `n8n/workflows/SignatureGate - Listmonk - Process Sync Queue.json`
- `n8n/workflows/SignatureGate - Listmonk - Poll Unsubscribes.json`

Both workflows expect these environment variables in n8n:

```env
LISTMONK_API_URL=http://listmonk:9000/api
LISTMONK_API_USER=signaturegate-sync
LISTMONK_API_TOKEN=<api-token>
LISTMONK_DEFAULT_LIST_ID=<numeric-list-id>
```

The workflows use HTTP header auth:

```text
Authorization: token <LISTMONK_API_USER>:<LISTMONK_API_TOKEN>
```

After import, attach your normal Postgres credential to every Postgres node.

## Listmonk unsubscribe reflection

Listmonk does not currently provide a general outbound webhook for normal subscriber unsubscribe events. The provided `Poll Unsubscribes` workflow queries the configured list for `subscription_status=unsubscribed` and records those changes back into SignatureGate using `public.listmonk_record_external_unsubscribe(...)`.

Run the polling workflow every 5-15 minutes for normal use.

## Appsmith changes

Do not patch the Appsmith JSON directly. Add the widgets/actions described in the handoff notes from the chat response:

- add opt-in checkboxes to new email flows, default checked;
- pass `mailing_subscription_status` and `mailing_subscription_source` into email inserts;
- add an `Unsubscribe` row action alongside Verify, Archive, and Reassign;
- call `public.member_email_request_mailing_unsubscribe(...)` from the row action.
