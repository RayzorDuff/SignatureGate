# v1.2.0 changelog coverage audit

The authoritative release changelog is `docs/CHANGELOG.md`. Keep its work in **Unreleased** until packaging/acceptance completes. The actual v1.1.0 tag resolves to `654b02c00dd39165a65a6ab3aebd28455264b70a`; the audited source baseline `9fb5aa53b60baa670fe86fabe63e6b5752be0109` contains **176 subsequent commits**. Their exact SHAs and subjects are in `evidence/commits_since_v1.1.0.csv`.

The goal is substantive behavior coverage, not one changelog bullet per intermediate repair commit. Release documentation itself also needs a short entry. Reconcile any subsequent implementation commits before finalizing v1.2.0.

The table below records the initial source-baseline assessment; it is retained as audit provenance, not a claim that the current summary still omits every listed family.

| Change family | Initial Unreleased coverage | Required reconciliation |
| --- | --- | --- |
| Canonical people/organizations, independent contributors, contact ownership, lifecycle and donation attribution (#19) | Extensive existing entries | Rewrite around final domain/page boundaries; preserve historical-attribution and permission details |
| Anonymous cash and Givebutter matching/review (#17/#19) | Existing entries | Include final contributor categories, scoped cash entry and the numeric provider-identity fix |
| Cash-on-hand, batch preparation/confirmation, tally and PDF printing (#17) | Anonymous intake listed; full operational batch feature lacks a consolidated entry | Add lifecycle, mixed-donor batching, exact snapshots, preparation vs deposit dates, printing and confirmed-composition protection |
| Reconciliation exclusion/revival and donation financial visibility | No clear consolidated entries | Add audited exclusions, reasoned revival and final reviewer/practitioner access policy |
| ERP synchronization, retry and confirmed-date correction (#18) | Sync/correction listed | Include durable source key, failed-sync custody preservation, bank-account selection and correction boundary; identify external RootedOps dependency |
| Canonical practitioner assignment, storage grants, agreement signing and sacrament gating (#19/#20) | Existing entries | Reconcile final operational pages and current permission behavior; preserve old signed template eligibility |
| Contributor/dual-capacity Listmonk subscriptions | Participant email references present; new contributor worker/list behavior lacks complete coverage | Add independent opt-in/out, contributor list and worker/unsubscribe behavior |
| Organization contact reassignment and identity notes | Not captured in current Unreleased section | Add canonical ownership preservation, audited notes and participant-note migration once validated |
| `Directory`, `Intake` and operational workspace consolidation | Transitional references still say Participants - Profile/Donations | Record current four `Directory` actions, retired `Directory`, `Member Functions` cleanup, `Intake` parity/collision/email validation, Company JS registration repair, and legacy `Intake` retirement when verified |
| Configurable Spiritual Practitioner/Participant terminology and grouped navigation (#20/Appsmith #4) | Practitioner foundation listed | Add final Participant display migration and navigation when complete; document external Documenso/legal dependency without claiming document revision |
| Agreement Type administration (Appsmith #2) and `Reports` regression (#23) | Type creation absent; historical report summaries listed | Add implemented type administration and restored `Reports` behavior only after acceptance |
| Export regeneration/datasource rebinding and release validation | Some validation repairs listed | Include first Appsmith release, exact-source monolithic JSON packaging, retained jsPDF/datasource definitions and source/export verification once repaired |
| Physical address identity hardening after v1.1.0 | Earlier address notes span multiple releases | Audit commit `3d07fd0` and resulting schema against tag; capture any additional post-v1.1.0 behavior without duplicating earlier release claims |

Appsmith has **no prior release tag** at this audit. Its first-release notes should describe the resulting application, identify the pinned Appsmith production-bound commit, reference the combined SignatureGate v1.2.0 changelog, and specify database/integration prerequisites. The current `master` comparison is useful for promotion review; it is not a substitute for comparing the Appsmith JSON shipped in SignatureGate v1.1.0 with the final packaged JSON.

Final gate: review history, acceptance ledger and old/new packaged artifacts together; include changes from every subproject; remove superseded transitional descriptions from the new release summary; update VERSION/README/dated v1.2.0 release notes; commit the exact-source generated JSON; run current source/export checks and `make release-check`; then create release tags.

October 11 follow-up: the combined public Unreleased summary now covers identity/capacity/contact history, notes/provenance, role access, contributor mailing, cash lifecycle and accounting boundaries, seeds, Agreement Types and exporter/naming corrections. It also records canonical Reports access and six contribution groups, the fresh-bootstrap deposit-date guard fix and live test notes SQL acceptance. Full historic deployment narratives were not republished; original technical history remains in Git. Final navigation/Participant presentation, reason-aware revival, accepted production dependency/export and remaining live checks still need reconciliation before the dated release.


October 13 reconciliation: Unreleased includes generated workflow navigation, explicit/stale-safe profile entry, Participant initialization/audited adoption, configured controller/report copy, staged signing/ERP/Listmonk feedback, empty-table vector repair, dormant upload retirement and safe audit rendering. These source changes remain development candidates; first Appsmith release notes, final dependency/source pins and old/new packaged comparison are pending release gates. The initial 176-commit inventory remains historical provenance, not the current head count.
