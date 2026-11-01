# Business relationships, ownership, custody and access

This guide describes system boundaries without recording an actual company's relationships, operating arrangements, inventory details or future business plans. Keep those deployment-specific facts private.

## Identities and capacities

An individual is a person; a company is a business/organization entity. Participant and Contributor are capacities held by identities. An individual can hold either or both; a company can be a Contributor but cannot become a Participant through one of its contacts.

Facilitator/Spiritual Practitioner, Document Reviewer, Donations Reviewer and Directory Manager characterize authorized system access. Their appointments do not create a new identity, automatically grant Participant/Contributor capacity, or establish ownership of assets.

## Independent boundaries

| Concept | Meaning | System implication |
| --- | --- | --- |
| Physical location | Where an item is held | Location identity does not identify its owner or authorized operator |
| Ownership | Which entity owns an item | Must follow an explicit reviewed event; cannot be inferred from a display label or location |
| Custody | Which entity currently holds an item | Can differ from ownership and operator access |
| Access | Which appointed users may perform an operation | Enforced through permissions, assignments and explicit grants |
| Allocation | A reservation or commitment | Does not itself prove transfer or delivery |
| Transfer/release | An authorized event changing custody or state | Preserve source identity, actor, event and audit references |

A Facilitator/Spiritual Practitioner's access to a location does not make that person its owner. Participant-facing agreements and release records belong to the operational application; inventory lifecycle belongs to the inventory system. Neither system should infer business relationships from a person's name or a contact value.

## Responsibility split

SignatureGate owns party identities, capacities, permissions, agreements and operational release/deposit records. MushroomProcess owns inventory identity/lifecycle/location. RootedOps/ERPNext owns accounting and reconciliation; Listmonk owns mailing delivery. Use explicit integration contracts rather than copying another system's authoritative data into unrelated fields.

Current integration uses reviewed n8n routes and stable source identifiers. Shared storage/access, business ownership and accounting must remain separate even when one deployment uses all three services.

## Changes and review

If ownership/custody or allocation needs a new representation, design its event and invariants first. Preserve historical references and distinguish planned capabilities from deployed behavior. Do not infer legal/business authority from a database role or a terminology label.

Keep actual entity relationships, account mappings, transaction values, item details and operational examples outside Git. Public architecture documentation should describe contracts and validation status only. See [party identity](PARTY_IDENTITY_AND_INVENTORY_MODEL.md), [architecture](ARCHITECTURE.md) and [ERP integration](../n8n/CASH_DEPOSIT_ERP_INTEGRATION.md).
