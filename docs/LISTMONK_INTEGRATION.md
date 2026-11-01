# Listmonk mailing-list integration

SignatureGate owns identity, purpose-specific contacts and recorded consent. Listmonk owns subscriber/list delivery state, campaigns and external unsubscribes. Participant and Contributor capacities are independent; a mailing-list subscription grants neither capacity nor system access.

## Database and queue

`db/schema.sql` defines consent on `member_emails` and `contributor_emails`, with `listmonk_sync_queue` as the outbox. Stable `member*` identifiers represent Participant contact sources. Consent defaults depend on the creation API: current Participant contact maintenance starts contacts as `not_subscribed`, while `Intake` records the explicit checkbox choice. Existing Contributor contacts are not silently opted in.

States include `subscribed`, `not_subscribed`, `unsubscribed`, `suppressed` and `sync_error`. Contact purpose, verification and consent remain separate. Retained forward files `listmonk_contributor_email_support.sql` and `listmonk_dual_capacity_contributor_email.sql` are selected only after effective deployment review.

## Committed workflows

- `n8n/workflows/SignatureGate - Listmonk - Process Sync Queue.json`
- `n8n/workflows/SignatureGate - Listmonk - Poll Unsubscribes.json`

Attach the intended SignatureGate PostgreSQL credential and Listmonk HTTP authentication after import. Review published workflow versions and actual destinations privately; Git exports do not prove active deployment.

## Environment variables and separate contributor list

| Variable | Use |
| --- | --- |
| `LISTMONK_API_URL` | Listmonk API base URL |
| `LISTMONK_API_USER` / `LISTMONK_API_TOKEN` | HTTP token-auth identity/secret; never commit actual values |
| `LISTMONK_NEWSLETTER_LIST_ID` | Newsletter routing for Participant contact queue rows |
| `LISTMONK_MEMBER_COMMUNICATIONS_LIST_ID` | Participant communications list; stable compatibility name |
| `LISTMONK_CONTRIBUTOR_LIST_ID` | **Separate contributor mailing list**, required when processing Contributor contact rows |
| `LISTMONK_DEFAULT_LIST_ID` | Legacy fallback when newsletter mapping is absent; not the contributor mapping |

Set all intended list mappings explicitly in deployment configuration. Do not depend on the worker's numeric fallback IDs or copy another deployment's list IDs. Contributor rows route only to the contributor list; Participant rows use their configured primary list plus newsletter/Participant communications lists. Review distinct list purpose and consent in dual-capacity cases.

```env
LISTMONK_API_URL=http://listmonk:9000/api
LISTMONK_API_USER=<service-user>
LISTMONK_API_TOKEN=<private-token>
LISTMONK_NEWSLETTER_LIST_ID=<newsletter-list-id>
LISTMONK_MEMBER_COMMUNICATIONS_LIST_ID=<participant-communications-list-id>
LISTMONK_CONTRIBUTOR_LIST_ID=<contributor-list-id>
LISTMONK_DEFAULT_LIST_ID=<legacy-newsletter-list-id>
```

The queue worker uses the list variables. The unsubscribe poller uses the API/auth variables and currently queries **subscriber-wide** unsubscribes; it does not independently poll each list. It reflects changes through `public.listmonk_record_external_unsubscribe(...)`. Keep the existing periodic schedule and validate retry/pagination/shared-address behavior rather than assuming list-level isolation.

## Appsmith consent and validation

Use the split Appsmith source for widget/action changes; the final JSON is generated at the release gate. `Intake`'s Participant/Contributor opt-in controls record explicit choices. Profile contact operations preserve consent and use the reviewed unsubscribe API; adding a second capacity must not silently subscribe its contacts.

On synthetic test contacts, verify in this order: opted-in Participant routing, opted-in Contributor-only routing, opt-out suppression, dual-capacity same-address behavior, external unsubscribe reflection, retry without duplicate queue/audit effects, and archived-contact handling. Review actual Listmonk results and mappings privately. Record only sanitized pass/fail, versions and workflow/source revisions in Git.
