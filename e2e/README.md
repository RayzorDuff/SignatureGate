# Post-v1.2.0 Appsmith browser-test foundation

This is SignatureGate #27, separate from the unreleased v1.2.0 scope and release
gates. VERSION and application exports are unchanged. **No true browser proof has
been executed yet**: the deleted Linode is not available and this checkout has no
running Appsmith. Guard tests and Playwright test discovery are static/contract
evidence only. The manual workflow tests PostgreSQL and harness contracts, not UI.
Do not broaden into MushroomProcess browser implementation until real SignatureGate
runs are reliable. Expand the role matrix only after the two initial journeys work.

## Isolated setup

Use a new dedicated test stack; never reuse/reset signaturegate, signaturegate_test
or a restored operational database. Install Node 22 and Docker on the future test
host, then from repository root:

```sh
umask 077
npm ci --prefix e2e --ignore-scripts --no-audit --no-fund
export E2E_DB_PASSWORD="$(openssl rand -hex 24)"
export E2E_INSTANCE_TOKEN="$(openssl rand -hex 32)"
# Preserve these values privately for this test instance, never in Git.
docker compose -f e2e/compose.yml up -d
export E2E_DATABASE_URL="postgresql://signaturegate_e2e:${E2E_DB_PASSWORD}@127.0.0.1:55432/signaturegate_e2e"
export E2E_ALLOW_RESET=1
npm run --prefix e2e db:reset
npm run --prefix e2e db:check
node e2e/database.test.mjs
```

The reset requires exact local/test-service host, database/user signaturegate_e2e,
PostgreSQL 16, explicit reset opt-in and a private instance-token marker. An
unmarked nonempty database or wrong marker is refused **before DROP**. Reset runs
under a transaction/advisory lock and rebuilds only public in that owned DB,
retaining e2e_control. The reviewed schema's psql restrict directives and top-level
BEGIN/COMMIT wrappers are removed so the rebuild stays one transaction. Fixtures
contain only deterministic artificial identities/roles/assignments/locations.
Do not add production records or point real Appsmith apps at this database.

The Compose project has internal-only networking, loopback ports and dedicated
volumes. Pull images before isolating an offline host. Appsmith v2.4.2 is the
RootedOps baseline, not proof of compatibility with the current export; record
actual image digest/source import revision on the new host. Use SSH tunnels for
first-account setup. Create purpose-built reviewer@example.invalid and
practitioner@example.invalid Appsmith accounts manually with unique private
passwords. Do not use production auth/OAuth grants. Browser credentials and
application roles are distinct; the seed maps these artificial account emails.

Import a **clone** of the actual reviewed SignatureGate export using the existing
appsmith/EXPORT.md procedure. Name the clone SignatureGate E2E. Preserve source
IDs in Git; never rewrite the committed export for testing. Rebind its PostgreSQL
datasource to postgres-e2e:5432/signaturegate_e2e and verify all action collections.
Do not claim the UI is tested against a fake HTML substitute. Review split-source
SignatureGate-Appsmith synchronization using existing release tools before import.

Keep n8n, Documenso, Givebutter, Listmonk, SMTP and ERP actions disabled or bound to
local test doubles. The internal Docker network is the server-side egress control;
Playwright's route blocking protects browser requests only. The initial cash path
writes PostgreSQL and must not call an external provider. Any required external
call must fail closed until a reviewed local double is configured. Keep app setup
and login behind loopback; do not expose unclaimed setup pages publicly.

## Browser execution and evidence

Inspect real Appsmith accessible names first. Copy selectors.example.json to
selectors.private.json and review every role/name or label locator. Example labels
come from the export; login/select/toast accessibility is **provisional**, not
verified. Do not replace them with positional CSS just to make a test pass. Record
locator discoveries and exact Appsmith/export versions in private run evidence.

```sh
cd e2e
npx playwright install chromium
export E2E_APPSMITH_URL=http://127.0.0.1:8081/
# Set the actual dedicated clone route, including Appsmith's generated page ID.
export E2E_APP_PATH=/app/signaturegate-e2e/REVIEWED_DONATIONS_ROUTE
export E2E_SELECTORS_FILE="$PWD/selectors.private.json"
export E2E_SELECTORS_REVIEWED=1
export E2E_POST_RELEASE_ACK=post-v1.2.0
# Read a purpose-built TEST password without putting it in shell history:
read -rs -p 'Test reviewer password: ' E2E_REVIEWER_PASSWORD; export E2E_REVIEWER_PASSWORD
npm test
npx playwright show-report artifacts/report
```

Auth is local Appsmith login, then actual clone navigation. Setup saves private
.auth state after confirming application readiness. The two proposed browser tests
check application load and one anonymous cash action with exact durable donation
and audit counts, plus contradictory error feedback. Backend assertions also check
assigned/unrelated member access; that is not a complete browser role matrix.
No default production URL, fallback credential or public browser CI exists.
Screenshots on failure, retained traces and HTML/JSON reports stay private under
artifacts with umask 077. They can contain test credentials/session cookies: do not
publish or upload them without sanitizing. Test accounts/fixtures must stay synthetic.
A failing selector or login is an unresolved POC failure, not permission to bypass
access controls or to substitute a mocked UI. Run reset before the next clean case;
setup refuses an existing cash operation from a previous run.

## Provenance and acceptance

Run `npm run --prefix e2e test:guards`, `node e2e/database.test.mjs` and
`npm run --prefix e2e test:list` separately and label their evidence accurately.
The manually dispatched appsmith-harness-contracts workflow deliberately has no
pull_request/release trigger and does not execute browsers. Browser CI adoption
requires a subsequent decision after several repeatable real-server runs.

Open gates for #27: actual login/navigation/cash POC; reviewer-denied page with
retained navigation; practitioner assigned-member readonly donation history;
contributor-vs-member capacity lists; location scoping; dual-capacity case; backend
permission assertions for every prohibited mutation; repeated reset/run reliability
and privacy-reviewed failure artifacts. No v1.2.0 acceptance checkbox is completed
by this foundation.

MushroomProcess follow-up remains gated on that proof. Reuse guard/marker/reset,
semantic locators, role fixtures, egress controls, private artifacts and backend
postconditions, with its own DB/schema/app clone and permission model. Candidate
journeys: create Lot, inoculate, spawn, harvest, return packaged Product, map catalog
and reserve/fulfill/cancel orders. Static export/SQL checks must remain explicitly
separate from true browser tests. Do not share test credentials or couple releases.

Cleanup: stop the dedicated project with `docker compose -f e2e/compose.yml down`.
Delete its named volumes only after confirming project labels and preserving needed
private evidence. Never issue a broad Docker/database prune. Revoke test accounts,
remove .auth and private reports when no longer needed; production is untouched.
