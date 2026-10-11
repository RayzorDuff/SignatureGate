# Cross-system operational, financial and inventory integration

This specification records generic responsibility boundaries. It omits actual organization relationships, provider names, product details, account mappings, transaction values and deployment-specific business plans. Detailed historical design remains in source history; it is not evidence of current deployment.

## Responsibility and identity

An operational application owns its operational event and identity references. The accounting service owns accounting documents and reconciliation. An inventory service owns item identity, lifecycle and availability. A mailing service owns delivery; consent remains with its recorded contact source.

Individual and company identities are distinct from Participant/Contributor capacities and system permissions. Only an individual can hold Participant capacity. Functional access appointments, including Facilitator/Spiritual Practitioner and review permissions, do not create identities, imply consent or transfer ownership.

## Independent commercial concepts

| Concept | Contract |
| --- | --- |
| Sales channel | Origin of a commercial request; not necessarily its payment processor |
| Payment processor | Payment settlement/status authority; does not own operational identity |
| Accounting item | Financial/catalog identity maintained by the accounting service |
| Operational item | Lifecycle/custody identity maintained by the inventory service |
| Channel listing | Provider-specific presentation mapped to a stable catalog reference |
| Ownership and custody | Explicit reviewed state/events; neither inferred from operator access |

Map stable references explicitly. Avoid copying authoritative data into another system's unrelated fields or resolving ambiguity by matching a name alone.

## Event and replay contract

Each external business event needs a stable source key, schema/version, source identity, operation and request fingerprint. Preserve that key across retry and response loss. An identical successful replay returns the existing outcome; a conflicting payload under the same source key requires review.

Track pending, processing, successful and failed states durably. Separate operational confirmation from external accounting completion. Do not claim a successful integration merely because an HTTP request was accepted or an operator interface completed its local write.

## Current deposit boundary

The operational application owns reviewed contribution composition and confirmed deposit snapshots. The accounting service validates the event, finds an unambiguous eligible bank match and creates/replays its accounting and reconciliation outcome. No/ambiguous match, missing previously recorded document and conflicting fingerprint require explicit handling.

Test mode must be explicitly selected and proven non-writing. A skipped test route is not accounting acceptance. Use protected rehearsal copies for accounting/reconciliation validation, followed by approved production acceptance against a pinned released dependency.

See [the ERP boundary](../n8n/CASH_DEPOSIT_ERP_INTEGRATION.md) for the current technical source contracts and release gate.

## Planned commercial extensions

Purchasing, catalog synchronization, fulfillment, invoicing and payment settlement are separate events. Define authority, invariants, source keys, mapping, failure recovery and acceptance before implementing an extension. Label planned capabilities explicitly; do not imply that an architecture diagram means they are deployed.

An allocation does not prove custody transfer; delivery does not prove settlement; payment does not grant Participant capacity or permission. Preserve these distinctions through external-channel changes.

## Security, audit and release

Use reviewed environment-specific credentials and endpoints. Never derive authorization from a configurable display label. Sensitive operational state changes require atomic audit; external completion requires durable outcome recording and reconciliation.

Publish only sanitized structural findings, technical contracts, source/version provenance and pass/fail status. Keep identities, contacts, financial values, account identifiers, product information and actual provider/configuration mappings private. Do not include operational examples in public command transcripts.

Before release, pin compatible dependency versions/SHAs, verify deployed/published revisions and destinations, rehearse the ordered upgrade and recovery, and complete idempotency/mode/permission acceptance. Refer to [architecture](ARCHITECTURE.md), [party identity](PARTY_IDENTITY_AND_INVENTORY_MODEL.md) and the release acceptance ledger.
