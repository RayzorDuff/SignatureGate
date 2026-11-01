# Canonical regression fixture validation

Issue [#30](https://github.com/RayzorDuff/SignatureGate/issues/30) tracks the five failures from the fresh shared Test2 database. The release still requires native Test2 and deployed Appsmith acceptance; an automated owner SQL run does not validate restricted-role grants, datasource destinations, OAuth or external storage.

The isolated embedded PostgreSQL reproduction on November 1, 2026 matched the reported 42/47 baseline. With the fixture repairs, all 47 checks pass. Native PostgreSQL 16 evidence is supplied separately by the `Canonical SQL regressions (PostgreSQL 16)` PR workflow; check its actual result before claiming native acceptance.

| Check | Cause and repair | Assertions retained |
| --- | --- | --- |
| Directory reads | Legacy membership flags replaced with canonical app accounts and reviewer roles; neither reviewer needs Participant enrollment | Capacity/contact separation and unknown-actor denial |
| Participant-operation reads | Practitioner role and assignment use canonical person authority and assignment IDs | Reviewer management, assigned practitioner read-only access, unrelated reviewer denial, revocation, ended enrollment history |
| Agreement signer attribution | Explicit transaction-local agreement type | Nonparticipant practitioner attribution, legacy ID compatibility, unassigned practitioner denial, audit |
| Sacrament agreement eligibility | Explicit transaction-local membership/sacrament types | Historical inactive template eligibility, scope separation, signed-version selection and cancellation |
| Shared identity | People/organizations own names; role presentation comes from profile views | Earlier Contributor identity retained during role reconciliation, historical donation unchanged, both name components projected, contact deduplication, Participant-first conversion and organization identity |

No schema, migration, application authorization function or Appsmith synchronization ID changes are required by these repairs. Agreement type fixtures roll back and do not become deployment seeds. Deferred constraints are forced before rollback in the repaired fixtures.

The sacrament release scope fixture also creates its own synthetic Participant. This removes an existing fresh-database skip of the invalid-release-type assertion.

## Native CI sequence

The workflow creates a job-owned PostgreSQL 16 service without published ports or deployment credentials. It applies only `db/schema.sql` and the public organization terminology seed, discovers all `db/tests/*.sql`, runs each twice with `ON_ERROR_STOP`, and compares the public data dump after every check with the bootstrap baseline. The service is discarded after the job. Owner access is necessary for fault-injection/DDL checks and is never granted to an Appsmith principal.

This CI workflow is independent of the deferred browser E2E harness. It neither opens Lish nor accesses the shared host. Review and merge the focused PR before a coordinated Test2 revalidation. Do not run an owner test sweep against production or point restored Appsmith/n8n actions at production destinations to obtain a passing result.

## Shared host access

The shared Test2 console uses an exclusive `flock` protocol. SignatureGate must enter `~/bin/test2-console-lock signaturegate`; Commerce uses `~/bin/test2-console-lock commerce`. If unavailable, stop console work and continue through GitHub. Exit the locking shell to release ownership. Keep the existing `commerce` and `signaturegate` Screen sessions separate; never remove the lock file, bypass `flock`, terminate another locking shell or take over with `screen -D -r`.

Another Weblish connection or SSH connection to the same Lish console can share input and display. A tmux session reached through that attached console does not isolate concurrent operators. Do not type into a console already occupied by the other workstream, including to attempt lock acquisition.

Akamai documents Glish as using `tty1`, a different device from the Lish serial console. This is a candidate access mechanism, not permission to bypass the console lock. Do not install a desktop, change getty/network/firewall/SSH settings or disturb another operator to obtain access. The lock grants console ownership only: shared Docker services, Appsmith/n8n, environment files, routes and another workstream's databases still require coordination. Use one focused deployment/validation session after console ownership is available.
