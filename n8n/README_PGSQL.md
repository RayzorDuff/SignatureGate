# PostgreSQL workflow integration

The PostgreSQL-backed workflows use separate routes during migration so operators can validate them alongside earlier integrations. Review the tracked workflow exports and actual published revisions before changing application routes.

Each database node must use the credential for its owning system. Business data and SignatureGate audit data may belong to different databases. Validate destinations privately; never infer a credential destination from a display label. Preserve required audit writes when migrating an external callback.

## Validation sequence

1. Select the reviewed source revision and import the required workflows into the test environment.
2. Assign credentials after checking each node's destination privately.
3. Keep production routes inactive until the application and workflow revisions have been accepted together.
4. Verify response compatibility, permitted reads, authorized state transitions and audit behavior with synthetic fixtures.
5. Verify denied operations and duplicate/retry behavior before publication.
6. Record accepted revisions and pass/fail; keep endpoint values, credentials, operational identifiers and business records outside Git.

## Mailing-list synchronization

Mailing synchronization uses the database outbox. Fresh deployments initialize the tables and functions from the canonical schema; existing deployments use the reviewed release migration manifest. Validate consent and queue behavior for both Participant and Contributor capacities.

The contributor list has its own configuration key, `LISTMONK_CONTRIBUTOR_LIST_ID`. Participant communications use `LISTMONK_MEMBER_COMMUNICATIONS_LIST_ID`; the stable variable name remains for compatibility. Newsletter and legacy fallback configuration are documented in [Listmonk integration](../docs/LISTMONK_INTEGRATION.md). Actual list identifiers and connection/authentication settings remain private.

## Accounting integration

Cash-deposit accounting and ERP bank lookup workflows are maintained in RootedOps. See [the ERP dependency guide](CASH_DEPOSIT_ERP_INTEGRATION.md). The coordinated release must pin a compatible released RootedOps tag/SHA and verify published routes and modes before SignatureGate promotion.
