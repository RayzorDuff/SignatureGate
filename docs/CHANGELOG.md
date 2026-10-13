# Changelog

Public release notes describe software behavior and technical contracts. Rooted Psyche and Dank Mushrooms may be named; actual individual names, other company names from operational records, contacts, financial values, product details, accounts and secrets remain private. Earlier versions retain their original version/date markers and concise behavior summaries; detailed historical source remains in repository history.

## [Unreleased]

- Add audited company contact-person links, archive/reactivation and Company Profile controls without enrollment, permission, consent or donation inheritance.
- Make Cash Deposits initialization use one canonical sign-in authority, distinguish account/lookup/permission failures, retain retry and provide a privacy-safe read-only access diagnostic.
- Make missing bootstrap inputs fail with a PostgreSQL script error and suppress supplied identity values in normal bootstrap output; clarify that first-manager bootstrap grants no Donations Reviewer role.


- Restore staged Intake and digital-signing feedback, and add ERP/mailing progress that distinguishes saved records, queued requests and confirmed external completion.
- Repair Terminology page-load initialization with account-bound access state; retry one transient read-only Cash/Terminology startup failure without retrying writes.
- Honor Intake mailing consent, reuse shared Participant/Contributor phone/address roles, bind Intake audit actor to sign-in and guard profile mailing changes by selected identity and signed authority.
- Block paper Intake and retained legacy paper Intake before record creation pending integration validation; warn clearly when a later Intake/signing step fails after saving records.

### Added

- Independent individual and company identities, with Participant and Contributor capacities kept separate from system access permissions.
- Canonical account ownership and operational role assignment, including authorized accounts without Participant capacity.
- Directory and selected-identity profiles, with guarded identity correction and stale-edit protection.
- Standalone Contributor creation, reviewed enrollment, archive/reactivation and capacity history.
- Participant closure that preserves identity, contact and financial history without creating Contributor capacity.
- Reasoned contact maintenance, primary promotion, physical-address duplicate protection and reviewed cross-capacity assignment/reassignment.
- Profile contribution/provider history and permission-scoped agreement/assignment history.
- Canonical practitioner assignment and agreement/release attribution, independent of the practitioner's Participant capacity.
- Identity-level notes, historical-source preservation and transaction/provenance protection against duplicate import or cleared-note restoration.
- A stable terminology registry, audited label administration and repeatable initialization that preserves installed overrides.
- Reviewer-controlled agreement-type creation, field/duplicate validation, selector refresh and atomic audit.
- Separate capacity-specific consent controls and mailing synchronization, including Contributor-only routing and external unsubscribe reflection.
- Deposit lifecycle, composition snapshots, confirmation, reporting/printing, exception/revival paths and durable external synchronization state.
- Audited confirmed-date correction before successful external accounting synchronization, with preserved attempt history.
- Reports count/dollar groups for overall, individual, company, anonymous, unresolved and Participant-linked contributions. Participant linkage uses current shared identity and active capacity; financial metrics require Donations Reviewer permission independently in SQL.
- Read-only deployment/catalog evidence tools, sanitized review records and explicit release acceptance/dependency gates.

### Changed

- Consolidated database bootstrap definitions and retained only reviewed forward deployment changes; added explicit deployment seeds.
- Separated identity/profile administration from capacity-specific operational pages; legacy entry points remain until parity is accepted.
- Made contact-method validation and capacity enrollment independent from identity notes and operational appointments.
- Preserved compatibility identifiers and historical signed-document references while preparing Participant/practitioner presentation changes.
- Documented the external accounting/reconciliation dependency and separate operational versus accounting authority.
- Defined functional filenames/directories and make targets, with repository naming checks and updated active setup references.
- Scheduled the final screen inventory after navigation acceptance and before application packaging.
- Required exact accepted source/export consistency and the coordinated application export before final release tagging.

### Fixed
- Removed legacy Participant requirements from provider review; made ambiguous matching conservative, prevented duplicate party creation, and guarded donor reassignment with atomic before/after audit and deposit-history protection.
- Preserved deliberate Manual execution for guarded queries and bank/inventory APIs through Appsmith dependency recalculation after Git pull.
- Required an explicit reason for cash reconciliation revival; preserved original exclusion rationale in atomic audit and added a reviewed Exclude/Revive dialog with committed-refresh recovery.
- Guarded Participant and practitioner-administration audit insertion by canonical staff scope and signed actor; disabled development paper-evidence uploads pending destination and authorization validation.

- Enforced canonical account/role and Participant self/assignment scope across Intake, operational pages and financial reads; retained navigation during denial and added Participant self-read access. Staff roles remain independent of Participant capacity and stale legacy flags.
- Supported nonmember reviewers in pending cash recording/review and cash-deposit actor references; made cash writes/audits atomic, repaired prepared binding metadata/quoting, and separated committed writes from refresh failures.
- Corrected Intake email escaping and optional blank-email handling; prevented inventory loading/display when no location scope is authorized and added an isolated Code-node helper that denies requested empty/malformed inventory scopes (workflow integration pending).

- Preserved the audited confirmed-deposit date-correction guard during fresh bootstrap; a later schema section no longer overwrites it with the earlier unconditional guard.
- Verified notes migration, repeat application and rollback-only behavioral checks on live PostgreSQL 16.13. Profile/Intake UI and restored-production acceptance remain pending.
- Enabled canonical Reports access without Participant capacity, used person-based practitioner assignments, and cleared stale authorization state and cached financial display after account changes.

- Corrected provider identity parameter normalization and typed ingestion calls.
- Preserved valid signatures from older inactive template versions without allowing unrelated or pending documents through the release gate.
- Preserved historical Participant contact visibility and guarded ownership in contact assignment/reassignment.
- Corrected profile initialization, dynamic role/visibility bindings and optional contact fields.
- Preserved datasource/library descriptors and nested widgets in generated exports; rejected conflicting/missing dependencies.
- Corrected canonical function delimiters and transaction completion so fresh bootstrap APIs persist.
- Added rollback-only behavioral checks for permissions, invalid/duplicate inputs, audit failure, historical-note reruns and provenance failure.
- Distinguished a committed creation from a later selector-refresh failure to avoid duplicate operator writes.

### Release status

These changes remain unreleased. Test evidence and source checks are recorded separately from production acceptance. Remaining role/scoping, terminology/navigation, fresh/upgraded rehearsal, integration target/mode and packaging gates must pass before release.

## [v1.1.0] - 2026-08-13

- Hardened contact/address identity, exact-contact duplicate protection and guarded contact upsert.
- Expanded contribution resolution and external-system boundary documentation.

## [v1.0.4] - 2026-07-09

- Hardened identity/contact duplicate checks, scoped access and document expiration handling.
- Aligned inventory eligibility filtering across integration routes.

## [v1.0.3] - 2026-05-09

- Expanded agreement and release administration, contact maintenance and audit coverage.

## [v1.0.2] — 2026-04-22

- Added multiple-practitioner assignments and scoped contribution/release operations.
- Separated application-owned assets from shared deployment infrastructure.

## [v1.0.1] — 2026-03-14

- Moved shared infrastructure ownership into the companion deployment repository.

## [v1.0.0] — 2026-01-22

- Established the stable agreement, contact, release and reviewer administration baseline.

## [v0.1.3-beta] — 2026-01-19

- Expanded agreement type/template selection and document integration handling.

## [v0.1.2-beta] — 2026-01-17

- Improved authenticated actor context and scoped operational permissions.

## [v0.1.1-beta] — 2026-01-15

- Added reviewer/practitioner access boundaries and corrected upload/authentication behavior.

## [v0.1.0-beta] – 2026-01-13

- Added end-to-end digital signing, evidence retrieval and guarded release integration.

## [v0.0.1-alpha] – 2026-01-08

- Introduced the initial authenticated operator application, database, agreements and integration documentation.
