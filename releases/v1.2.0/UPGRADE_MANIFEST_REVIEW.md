# Conditional upgrade planning checkpoint

`UPGRADE_MANIFEST_DRAFT.json` pins the 19 retained migration sources and the explicit Participant configuration step in a conditional dependency order. **It is not an execution list. All 20 selections remain undecided and all final environment proofs remain open.** Do not run every listed file or load bootstrap over an existing database.

The read-only validator checks source existence/checksums, unique step IDs, prerequisite order, review fields and the rule that older cash/financial helpers cannot follow canonical authorization. It has no SQL execution or deployment function:

```bash
python3 scripts/validate_upgrade_manifest.py releases/v1.2.0/UPGRADE_MANIFEST_DRAFT.json
```

Automatic checks reject changed checksums, reversed prerequisites, duplicate entries and selected/skipped steps without disposition evidence. Passing validates the draft's structure, not production readiness.

## Required review before a final manifest

1. Refresh the private production catalog/effective-definition review for the final source target. Preserve already-reviewed matching definitions, including the confirmed-date correction guard. A matching name or different hash alone is not a replay decision.
2. Verify canonical base objects, account ownership/roles, contact/identity invariants, historical backfills and owners/grants. Reconstruct missing forward changes if the retained sources cannot upgrade the actual baseline. Do not infer staff authority from old Member flags or initialize another manager.
3. Give each step an explicit selected/skipped disposition, evidence location and scoped verification. Identify actual affected data/locks privately. Preserve unrelated installed terminology overrides; the Participant adoption is a separate approved configuration change.
4. Pin the released/deployed RootedOps dependency, active n8n revisions/principals/routes, test/production modes and private Listmonk/Documenso/account mappings. Stop workers across incompatible queue/schema boundaries.
5. Verify a backup restore, isolate workers and external destinations, rehearse only selected changes on that protected copy and verify final definitions, history and recovery. Fresh bootstrap or synthetic cases alone cannot close this gate.

Source compatibility follow-up: the current RootedOps 1.5.25 source checkpoint has the same four SignatureGate workflow/API/service blobs as the reviewed baseline. This is source reuse, not a release/deployment pin. Its standalone deposit unit test attempt is blocked in this workspace by missing `frappe`; it supplies no new ERP/runtime acceptance. Run the appropriate tests in the prepared ERP/Frappe test environment during dependency acceptance.

Final production operations, datasource promotion, generated export packaging, VERSION changes and tags remain gated by the coordinated release plan. No production command or change is made by this planning checkpoint.
