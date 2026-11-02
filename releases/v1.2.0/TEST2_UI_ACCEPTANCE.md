# Test2 UI acceptance checkpoint

Updated November 1, 2026 (America/Denver). This checkpoint supersedes earlier deployment-status statements; earlier operator UI acceptance remains historical evidence. Production promotion is on hold.

## Git synchronization

- The reported `syncBranch` conflict is an Appsmith application-level Redis lock. At direct inspection that key was absent, and no filesystem Git lock existed. No lock was deleted.
- Fresh native Git synchronization fails because GitHub cannot resolve from Appsmith's deliberately isolated runtime. The shared network is internal. Deleting Git metadata or clearing unrelated Redis keys would not repair that failure.
- The existing `chatgpt_development` editor opens directly with its native application/page identities. This is not proof of a successful current-source pull: incorporation of merged Appsmith PR #7 remains unverified.
- Appsmith's native backup completed, including MongoDB and Git storage. The archive, encryption configuration and checksum receipt are retained privately outside Git. Uncommitted checkout differences were preserved; no reset, discard, reimport or shared-service restart was performed.
- A remote-source access method must be coordinated before changing the intentionally isolated runtime. Stop Git investigation once native source synchronization succeeds.

## Connection isolation

The existing development datasource is configured for the dedicated synthetic database, but still uses the owner login. Its connection must be changed to the restricted application login before UI write acceptance. Preserve datasource/action IDs and production-facing configurations.

A direct connection using the private restricted-role credentials succeeded against the dedicated test database. Catalog checks confirm no superuser flag, schema-creation permission, public-schema creation permission or ownership of public objects.

The same login can connect to the restored database. Catalog checks there report zero readable public relations and zero public tables with INSERT/UPDATE/DELETE privilege, but connection denial is not enforced. These checks do not certify every routine, alternate schema or connection path. Do not report complete isolation from role flags or hostnames alone.

The saved n8n datasource still targets production. Identify shared usage before making any change; isolate only the acceptance workflows and verify their database, storage, signing, mailing and ERP destinations/credentials. Keep workflows inactive until that review is complete. No workflow action was used to test a production endpoint.

## Focused acceptance matrix

| Check | Result | Evidence or remaining cause |
| --- | --- | --- |
| HTTPS and native sign-in | PASS | Authenticated application/editor reached |
| Dedicated database and restricted-role authentication | PASS | Native connection and narrow catalog checks |
| Former-Participant forward migration | PASS | Applied twice; focused rollback check passed; function identity/owner/grants preserved |
| Open existing development branch | PASS | Existing editor opens directly; no reimport |
| Pull current development source including Appsmith PR #7 | BLOCKED | GitHub unavailable from isolated Appsmith runtime |
| Restricted datasource configuration and complete isolation | BLOCKED | Owner login remains saved; cross-database connection still possible |
| Test-only n8n routing | BLOCKED | Saved production destination; workflow targets/credentials not yet certified |
| Directory/Profile and Reports functional smoke | BLOCKED | Source/binding prerequisites; current sign-in lacks an active synthetic directory account link |
| Repeated Participant Intake | BLOCKED | Source/binding prerequisites |
| Agreement creation/review | BLOCKED | Source/binding and integration prerequisites |
| Former-Participant contact reassignment in browser | BLOCKED | Source/binding and authorized synthetic reviewer prerequisites |
| Contributor identity and cash deposits | BLOCKED | Source/binding prerequisites |
| Paper storage (Drive/NocoDB) | BLOCKED | Test-only workflow/storage credentials and destinations unverified |

The passing 47-check PostgreSQL suites and Appsmith CI remain accepted evidence. They were not repeated. No browser write workflow is counted as passing.

## Next focused operations

1. Coordinate a safe Git source-access method, then use the existing Git-linked development application to synchronize current source without discarding preserved changes or touching master.
2. Update only the development datasource to the restricted role; verify the actual application connection and negative access boundaries. Review shared n8n datasource usage and isolate the required acceptance endpoints.
3. Provision/use synthetic application actors, then perform the requested single browser acceptance pass. Record actual results and only repair demonstrated core-workflow failures.
4. Assess historical replay only after synthetic UI acceptance. No replay decision or restore is justified by the current Git/network blocker.
5. Pin the accepted sources, reviewed forward migrations and external dependencies; document tested rollback before requesting production promotion. Preserve private backup material; never use instance-wide restore as an individual-app recovery step.

The exclusive console lock was explicitly released and availability verified after the focused operations. Commerce subsequently resumed its console work. No production promotion, production-facing app change, shared Docker/network change or Commerce mutation occurred.
