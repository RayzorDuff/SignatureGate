# Party identity, capacity and inventory model

## Identity is distinct from capacity and access

An **individual** is a person. A **company** is a corporation or other business/organization entity. SignatureGate stores these identities in `people` and `organizations`; the shared term **party** covers either kind.

Participant and Contributor describe capacities a party can hold. They are not people. An individual may be a Participant, a Contributor, both, or neither. A company may be a Contributor and may have individual contacts; it cannot become a Participant merely because a contact person participates. Identity and contact history remain when a capacity ends.

Functional appointments/permissions characterize access. Facilitator/Spiritual Practitioner, Document Reviewer, Donations Reviewer and `Directory` Manager are not additional people or identity kinds. Link an Appsmith account to an individual, then assign the intended permissions. A Facilitator/Spiritual Practitioner or reviewer can have system access without Participant or Contributor capacity.

| Concept | Canonical representation | Meaning |
| --- | --- | --- |
| Individual | `people.person_id` | Person identity, independent of account and capacity |
| Company | `organizations.organization_id` | Business/organization identity |
| Participant capacity | `members.member_id`, linked to `people` | Existing operational participation record and history; `member*` names remain compatibility contracts |
| Contributor capacity | `contributors.contributor_id`, linked to an individual or company | Donation attribution and contributor operations |
| Appsmith sign-in ownership | `person_app_accounts` | Explicit active owner of a sign-in email; not inferred from contact matching |
| Access appointments/permissions | `person_roles` | Stable authorization keys such as `practitioner` and `document_reviewer` |
| Contact and purpose | `party_contacts`, `party_contact_sources` and retained source tables | Contact identity with capacity-specific provenance/preferences |

For Rooted Psyche documentation, say **Participant** and **Facilitator/Spiritual Practitioner**. The UI terminology work in Phase 3 must make the active interface consistent; literal current page names and SQL/API identifiers are preserved until their accepted changes. Statutory governance membership, if applicable, is a separate organizational concept and must not be inferred from participation.

## Identity correction and duplicate review

Individuals' names and dates belong to `people`; company names belong to `organizations`. `member_profiles` and `contributor_profiles` are read projections, not independent identity copies. Reviewed creation/enrollment retains the existing identity ID. Do not match or merge parties by name alone, and do not assume a shared email/phone proves the same identity.

`Directory` Manager identity corrections require a reason and stale-edit protection. Conflicting historical identity evidence remains reviewable; canonical corrections must preserve agreement, donation, release, provider and audit references.

## Contacts and consent

A contact belongs to one party; identical values owned by different parties do not merge those parties. The same individual's Participant and Contributor sources can share a canonical contact while retaining independent purpose, consent, verification and archival state.

Purpose-specific writes use guarded APIs. Adding or archiving primary email/phone/address contacts follows duplicate protection and primary promotion rules. Cross-capacity assignment and reassignment to a different party require reviewed authorization and reasons. Do not change Contributor consent just because a Participant contact was edited, or change company ownership because an individual contact participates.

Company contacts are relationships to individual identities and/or owned contact sources, not Participant records for the company. The remaining representation/ownership cases belong to the release acceptance ledger.

Listmonk delivery is an external projection of recorded consent. Contributor mail uses its own list mapping; Participant communications use the existing stable environment keys. Subscriber-wide unsubscribe reflection and shared-address behavior require explicit acceptance. See [Listmonk integration](LISTMONK_INTEGRATION.md).

## Notes

Administrative notes belong to the individual/company identity. Original historical Participant-source notes remain preserved in `members.notes`. The forward notes migration records one historical decision per source; reruns do not restore a cleared canonical note or reimport changed legacy text. Previously audited identity edits take precedence and require private historical-source review where appropriate.

Canonical note writes require authorized visible-party access and a reason; no-op normalization follows the API's audit behavior. Audit failure rolls back the write. Facilitator/Spiritual Practitioner access alone does not grant identity-note access. See [the notes validation sequence](../releases/v1.2.0/NOTES_VALIDATION_COMMANDS.md).

## Contributor attribution and participation lifecycle

Givebutter ingestion retains provider identity and event identifiers for idempotency. Unique reviewed evidence may select a Contributor; ambiguity remains unresolved for review. Anonymous contributions do not create synthetic individuals or Participants. Donation amounts do not confer capacity, system permission or release eligibility.

An existing individual may be enrolled as a Participant without replacing their identity or Contributor record. Ending Participant capacity preserves identity, contacts, agreements, financial attribution and historical releases; it does not require or create Contributor capacity. If both capacities exist, their status/link changes follow their own guarded lifecycle rules. Companies cannot acquire Participant capacity.

Contributor archive/reactivation likewise preserves identity, contact/provider history and donation references. Neither capacity grants operational roles automatically.

## Practitioner assignment, agreements and releases

Facilitator/Spiritual Practitioner access uses the stable `practitioner` appointment, active Participant assignments and explicit storage grants. Do not require a practitioner to have Participant capacity merely to sign or receive attribution. Do not grant broad document/donation review privileges to work around a remaining legacy path.

Canonical practitioner person IDs are authoritative for new assignments, agreements and releases. Nullable legacy practitioner participant-ID projections remain for older consumers. Ending an assignment or appointment must preserve historical attribution and pass the relevant guards.

Participant agreements authorize their configured scope. A signed older template version can remain valid after that template is deactivated. Only the accepted release scope permits a tangible transfer. Agreement method, evidence, review state and practitioner attribution are distinct fields and must remain intact during terminology changes.

Assigned practitioners may access only the operations/history allowed by their scope. Contributor financial history and organization-wide review are separate permissions; unassigned parties and inappropriate company access must be denied.

## Inventory authority and location

MushroomProcess owns inventory identity, state and location. SignatureGate records the transfer reference and authorized operational actor. Physical storage location, inventory owner/custodian and authorized user access are separate concepts. Access to a location does not transfer ownership; an allocation does not prove delivery.

Current inventory routes are PostgreSQL-backed n8n integration. Older Airtable exports are compatibility artifacts, not the default current architecture. See [business relationship boundaries](BUSINESS_RELATIONSHIP_MODEL.md).

## Cash deposits and accounting

SignatureGate owns contributor-attributed donations, review, confirmed deposit composition and synchronization state. RootedOps/ERPNext owns accounting documents, durable source-key replay and bank reconciliation. Reposting a retry must not create duplicate accounting or mutate a confirmed deposit's composition.

The ERP n8n workflows live in RootedOps and are required release dependencies. Development's `mode: "test"` route skips production writes; actual accounting needs a protected rehearsal and production validation. See [the ERP integration guide](../n8n/CASH_DEPOSIT_ERP_INTEGRATION.md).

## Implementation and acceptance

Definitions are consolidated in `db/schema.sql`; explicit terminology seeds are in `db/seeds/`. Retired historical migration filenames are not installation prerequisites. Existing databases use reviewed forward migrations and a restored-production rehearsal.

Focused rollback-only checks cover canonical people, party contacts, directory/account/role access, contacts and ownership, Contributor lifecycle/history, participation enrollment/closure, practitioner assignments, signing/release, notes, terminology and deposits. See `db/tests/` and the v1.2.0 acceptance ledger for required live evidence and remaining gaps. Source tests do not certify deployed datasource targets, publication or integration modes.

Never put operational identities, contact details, note text, financial values, product information, account identifiers or integration mappings into public validation records. Preserve those privately; record sanitized pass/fail findings and source/version provenance in Git.
