# Native object recreation and Directory startup

The operator reports that recreating the Directory JS object made page-load settings stick and fixed automatic Directory table loading. Navigation still starts with only People and Organizations, and other pages still have access/startup problems. Accept the table result; do not infer that the remaining pages passed.

## Synchronized source finding and correction

Appsmith checkpoint `3763b0a98f2fcb0faf3d35931ab23bd042dba3e3` recreates both Directory JS collections and their functions with new sync identities. Its saved modes are:

| Function | Mode in that checkpoint | Corrected mode |
| --- | --- | --- |
| `directoryFlows.load` | On page load | Preserved |
| `navigationLabels.initialize` | Manual | On page load, explicitly selected |
| `navigationLabels.label` | On page load | Manual; presentation helper |

This is the synchronized checkpoint, not a claim that newer unsynchronized editor changes cannot exist. The saved initializer mode explains why no automatic menu authority read is requested from that source. The formatter must not replace the initializer as a startup hook.

Development correction: [SignatureGate-Appsmith `4b1f56f`](https://github.com/RayzorDuff/SignatureGate-Appsmith/commit/4b1f56fb1fcffc78825b3548cac298ddb9fa08a9).

The generator previously replaced existing sync identities with generated name strings. This is a confirmed source-tooling defect: regeneration would undo the operator's recreation identities. It now preserves all **540 existing action/collection sync identities**, retains native metadata extensions/default arguments and current-page title geometry, and rejects duplicate/missing identities before writing. Only new resources receive fresh UUID-based identities, persisted once. Native JSON normalization alone no longer rewrites files. No duplicate action/collection sync IDs were found in this tracked checkpoint; a runtime stored-object association defect remains a hypothesis, not a proven duplicate-ID root cause. Existing identities on other pages are not rotated speculatively.

The native checkpoint restores `isAsync` metadata on other pages; it is retained without making that deprecated field an acceptance requirement. The recreated and now-working Directory loader omits per-function async/client-side flags. The source dispatch test now accepts that observed native representation, while still requiring the actual async source method and correct collection/function registration.

## Automatic evidence and limits

- `python3 tests/navigation-generation.py`: reproduces the Manual initializer/On-page-load formatter checkpoint, corrects the intended hook without replacing identities, retains native argument defaults/extensions/title size, verifies byte-stable reapplication, one-time new-resource identities and duplicate rejection.
- All 540 sync identities compare unchanged against the operator's synchronized checkpoint. Generator `--check` and 32 actual async startup declarations pass.
- Controller fixtures dispatch the 32 declared startup functions across 18 pages; navigation capability/account cases, 32 collection/793 expression syntax checks and 231 literal routes pass. These do not run Appsmith's server scheduler.
- A private generated candidate preserves 18 pages, 508 actions, 32 collections, four datasource descriptors and one JS library. The shipped Appsmith JSON is unchanged. Source fingerprints are refreshed; live import/startup/access remain open.

## Minimal operator sequence

1. In Appsmith Git, select `chatgpt_development` and pull the correction at `4b1f56f`. The operator's synchronized recreated IDs are preserved. If there are newer editor-only changes, commit those first rather than discarding them on pull. No deletion/recreation or Console write script is requested.
2. Reload **Directory in the editor** once. Without Refresh/Refresh access, observe whether the other authorized menu groups appear and the Directory table still loads. Return pass/fail for each.
3. If Directory passes, open **Terminology Administration in the editor** once and report whether its authorized form opens without Retry/Refresh access. Stop there; do not repeat the role or cash matrix. If Directory fails, report whether the current-page caption says Checking page access, lookup did not complete or no active account link; no private record data is needed.

This is editor acceptance. No production migration, role grant, datasource change, master promotion or published deployment is performed or requested. Other page access remains unresolved until actual runtime evidence supports a repair; Directory table success does not close that gate. Preserve any resulting Appsmith Git diff before another source synchronization.
