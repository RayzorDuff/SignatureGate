# Mailing-list integration

The application records purpose-specific contact consent and queues synchronization. The mailing service delivers messages and reflects external unsubscribes. Participant and Contributor capacities remain independent; a subscription does not grant either capacity or system access.

## Contributor list configuration

The committed queue worker supports **`LISTMONK_CONTRIBUTOR_LIST_ID`** for a separate Contributor mailing list. Set it to the intended list in private deployment configuration; do not record the actual list ID or mapping in Git. Processing a Contributor contact requires this configuration rather than borrowing the Participant list.

Related stable configuration keys are `LISTMONK_NEWSLETTER_LIST_ID`, `LISTMONK_MEMBER_COMMUNICATIONS_LIST_ID` and the legacy newsletter fallback `LISTMONK_DEFAULT_LIST_ID`. The existing `MEMBER` key is a compatibility identifier for Participant communications. Configure each intended list purpose explicitly and verify the effective mapping privately.

Contributor contact rows route to the Contributor list. Participant contact rows follow the configured Participant/newsletter communications purposes. A second capacity must not imply consent to another list.

## Consent and unsubscribe behavior

Consent defaults depend on the creation API. Current Participant contact maintenance begins unsubscribed; Intake records explicit checkbox choices. Existing Contributor contacts are not silently opted in. Subscription state, contact verification, contact purpose and capacity are separate.

The current unsubscribe poller reflects subscriber-wide unsubscribe state through the guarded application API. It does not independently poll each list. Shared-address and dual-capacity behavior must be verified explicitly, including retry and archived-contact cases.

## Private validation sequence

Use synthetic contacts to verify opted-in Participant routing, Contributor-only routing, opt-out suppression, dual-capacity same-address behavior, external unsubscribe reflection, and retry without duplicate effects. Review the actual deployed worker/poller revisions, connection destinations, credentials and list mappings privately.

Record only sanitized pass/fail, software/source revisions and remaining gaps in Git. Keep actual subscriber names/contacts, list identifiers, configuration values, credentials and operational screenshots outside the repository. The architecture guide describes system responsibility; published integration compatibility remains a release gate.
