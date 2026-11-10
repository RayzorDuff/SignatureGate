# Candidate upgrade manifest review

`UPGRADE_MANIFEST_DRAFT.json` now records all 24 source-level dispositions:
12 selected forward files, 11 skipped legacy replays and one skipped generic
terminology operation. Every source checksum was reverified. The explicit
`candidate_forward_order` matches the accepted November 10 rehearsal.

**Still non-executable:** current private effective-definition, role/owner/grant,
historical note/data, isolation/dependency and recovery approvals are not available
in this workspace. Nine final environment proofs remain false. Selection means
proposed forward application, not production authorization or proof that every
skipped file was historically executed.

The selected migration descriptions identify top-level mutations. In particular,
identity-note backfill updates people notes/timestamps; authorization snapshots
actor references; new receipt/contact tables do not themselves submit operational
requests. Legacy cash date correction and ERP structures are preserved, and older
helpers must not overwrite canonical authorization. Terminology adoption remains
a separate audited organization operation.

See [the current handoff](PREPRODUCTION_HANDOFF.md) for the exact selected order,
protected owner/ACL restore procedure, new row-content/catalog comparator,
actual-principal matrix, cutover sequence and rollback limits. Retain the accepted
[12-file rehearsal](evidence/november_10_restored_production_migration_rehearsal.md);
do not repeat its entire functional suite to compensate for missing private evidence.

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
