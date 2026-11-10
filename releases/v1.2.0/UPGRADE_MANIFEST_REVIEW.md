# Conditional upgrade planning checkpoint

`UPGRADE_MANIFEST_DRAFT.json` pins 24 conditional migration/configuration entries in a conditional dependency order. **It is not an execution list. All 24 selections remain undecided and all final environment proofs remain open.** Do not run every listed file or load bootstrap over an existing database.

**November 10 scoped rehearsal checkpoint:** 12 migrations were executed on a checksum-verified network-isolated restored production database, with 12/12 targeted rollback-only SQL tests PASS, zero compared structural differences from development, and 35/35 original production-table counts preserved. The evidence is [here](evidence/november_10_restored_production_migration_rehearsal.md). This does not change the draft manifest's **24 undecided selected/skipped entries and nine unverified environment proofs**. The final reviewed order, owner/grant preservation and recovery rehearsal remain pending.

The read-only validator checks canonical-schema and step-source checksums, unique step IDs, prerequisite order, review fields, the complete nine-proof inventory and the rule that older cash/financial helpers cannot follow canonical authorization. Checks remain enabled under optimized Python (`-O`). It has no SQL execution or deployment function:

```bash
python3 scripts/validate_upgrade_manifest.py releases/v1.2.0/UPGRADE_MANIFEST_DRAFT.json
python3 scripts/test_upgrade_manifest.py
```

Automatic CLI checks exercise normal and optimized Python, rejecting changed checksums, reversed prerequisites, duplicate entries, missing proofs, malformed review fields and selected/skipped steps without disposition evidence. Changing the required proof inventory requires an explicit validator update as well as a manifest change. Passing validates the draft's structure, not production readiness.

## Required review before a final manifest

1. Refresh the private production catalog/effective-definition review for the final source target. Preserve already-reviewed matching definitions, including the confirmed-date correction guard. A matching name or different hash alone is not a replay decision.
2. Verify canonical base objects, account ownership/roles, contact/identity invariants, historical backfills and owners/grants. Reconstruct missing forward changes if the retained sources cannot upgrade the actual baseline. Do not infer staff authority from old Member flags or initialize another manager.
3. Give each step an explicit selected/skipped disposition, evidence location and scoped verification. Identify actual affected data/locks privately. Preserve unrelated installed terminology overrides; the Participant adoption is a separate approved configuration change.
4. Pin the released/deployed RootedOps dependency, active n8n revisions/principals/routes, test/production modes and private Listmonk/Documenso/account mappings. Stop workers across incompatible queue/schema boundaries.
5. Verify a backup restore, isolate workers and external destinations, rehearse only selected changes on that protected copy and verify final definitions, history and recovery. Fresh bootstrap or synthetic cases alone cannot close this gate.

Source compatibility follow-up: the current RootedOps 1.5.25 source checkpoint has the same four SignatureGate workflow/API/service blobs as the reviewed baseline. This is source reuse, not a release/deployment pin. Its standalone deposit unit test attempt is blocked in this workspace by missing `frappe`; it supplies no new ERP/runtime acceptance. Run the appropriate tests in the prepared ERP/Frappe test environment during dependency acceptance.

Final production operations, datasource promotion, generated export packaging, VERSION changes and tags remain gated by the coordinated release plan. No production command or change is made by this planning checkpoint.


October 18 dependency check: GitHub's latest published RootedOps release is v1.1.0; all four required SignatureGate workflow/API/service paths are absent at that exact tag. See `evidence/rootedops_release_inventory.json`. Select and accept a new compatible released/deployed dependency before completing its environment proof. No draft selection or repository VERSION is substituted for this gate.
