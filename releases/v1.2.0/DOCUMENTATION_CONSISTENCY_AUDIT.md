# Documentation consistency audit — November 10, 2026 (UTC)

Scope: current `SignatureGate/main` release/process documentation following merged PR #39 (rehearsal evidence) and PR #40 (shared Appsmith export workflow); cross-checked against `SignatureGate-Appsmith/master` Git datasource definitions and the checked-in workflow/scripts. This audit does **not** validate saved live Appsmith connections, role grants, worker credentials, external service versions, or a production migration.

## Confirmed current state

- Backend `VERSION=1.1.0`; v1.2.0 is unreleased. No tag or production SQL run is authorized.
- Appsmith split source is canonical in `SignatureGate-Appsmith`. The generated release JSON is committed in `SignatureGate/appsmith/Rooted Psyche Membership Ops.json`.
- The shared `scripts/prepare-appsmith-release-export.mjs` is called by the `Regenerate Appsmith export` Action; it temporarily rebinds PostgreSQL action descriptors using the existing tool and generates/validates the JSON. The `master` source has `signaturegate-postgres`; development has `signaturegate-postgres-test`. Git descriptors do not contain the runtime connection target/secret.
- Isolated restored-production rehearsal: 12 of 12 migration files PASS; 12 of 12 scoped SQL verifications PASS; zero differences across the compared eight structural categories against development; original 35 production table row counts unchanged.
- The manifest draft remains non-executable: 24 selected/skipped decisions and nine environment proofs open. Neither structural equality nor the test suite validates final production owner/grant preservation or external integrations.
- The native synthetic NocoDB paper upload and independent reviewer acceptance were recorded; production publication and final source/mode reconciliation are separate gates.

## Inconsistencies resolved in this audit

| Severity | Area | Prior problem | Resolution |
| --- | --- | --- | --- |
| High | `releases/v1.2.0/README.md` | Current index claimed test/production database differences and live paper acceptance remained wholly unresolved, and directed repeating paper-upload and Test2 work | Current checkpoint, accepted rehearsal and paper evidence, and explicit remaining promotion gates now lead the index; old Test2 links labeled historical |
| High | `PRODUCTION_UPGRADE_AND_PROMOTION.md` | Step 1 still ordered an already-accepted issue #36 upload/review; Step 2 still ordered retry/recovery; raw exporter commands duplicated the merged PR #40 shared script | Front-loaded November 10 gate list, marked old diagnostics historical and replaced old raw-export instructions with the canonical shared command |
| Medium | `CURRENT_MIGRATION_CANDIDATES.md` and `UPGRADE_MANIFEST_REVIEW.md` | Introductory language said restored-production rehearsal had not happened | Rehearsal PASS and limits linked without incorrectly selecting the 24 draft manifest entries |
| Medium | `STATUS.md` | Paper row still said source merge pending, master/export row did not mention PR #40, and historical October table still reported 23 entries | Separate source/deployment promotion, note shared export tooling, and label dated historical counts explicitly |
| Medium | `RELEASE_CANDIDATE.md` / `RELEASE_PLAN.md` | Older source SHAs and pending acceptance statements could be mistaken for current release instructions | Superseding November 10 status and links added, historical content retained for traceability |
| Medium | `docs/RELEASE_PROCESS.md` | Had only manual Action invocation; no shared isolated rebind procedure or pinned master boundary | Documents same manual/Action entry point, commit pins, Appsmith reconciliation before export and live connection checks |
| Low | Navigation | Current evidence and canonical export docs were difficult to find from the v1.2.0 landing page | Added direct links and checked relative Markdown links |

## Outstanding technical/documentation work (not marked completed)

1. **Final release manifest:** Record evidence and selected/skipped outcome for every one of the 24 entries and nine environment proofs, plus file checksums, reproducible order and recovery procedure. Keep the draft non-executable until that evidence is reviewed.
2. **Production role and data safety:** Rehearse ownership/ACL restore (first restore used `--no-owner --no-acl`), test actual deployed roles and permissions, prove data-level historical invariants, isolate n8n and external side effects, and rehearse cutover/restore against final pins.
3. **Appsmith promotion:** Review `chatgpt_development` against `master` with a per-file master-only-change disposition; preserve native IDs; explicitly verify ERP confirm/retry `mode: "test"`, signing and storage routing before production promotion.
4. **Export reproducibility:** The shared script and Action have the same transformation logic, but the Action's separate checkout of a moving Appsmith `master` for the descriptor is not inherently an immutable pin. For final release evidence record the actual descriptor commit as well as the selected Appsmith source commit and generated export checksum; consider a workflow input requiring/pinning the descriptor ref in a future code change.
5. **Deployment boundary:** The Action commits the export but does **not** merge Appsmith branches, validate live saved database credentials, deploy/publish Appsmith, change n8n or ERP modes, apply production SQL, or set VERSION/tag. These remain deliberate approved steps.
6. **Historical docs:** The dated October migration/validation documents and Appsmith `README.md` routing instructions remain historical/reference material; they should not be interpreted as live release checklists. A full copyedit of every archived phase document would erase useful provenance and was deliberately avoided.

## Validation performed

- Examined the live merged workflow and exporter/rebinder source, plus Appsmith `master` and development datasource definitions.
- Read the main release/process entry points and historical release status/candidate/migration documents.
- Checked relative Markdown links in ten active entry-point documents against the repository tree: no missing relative destinations detected.
- This PR updates **documentation only**; no production source exports, application settings, VERSION, manifest statuses, workflow code, database schemas or tags are changed.
