# Navigation and Participant presentation candidate

This increment advances Phase 3 independently of the operator's interface walkthrough. It does not close Phase 2/3/4 runtime or integration gates and does not change production, DB permissions, executed documents or internal member/practitioner identifiers.

## Implementation and automatic confidence

One Appsmith `navigation/registry.json` defines four workflow groups. `scripts/generate-navigation.py` creates the standard Menu Button copies, two read-only queries and shared presentation helpers on every page; `--check` detects drift. The native title/sign-in/Directory bar remains enabled. Other pages are hidden from the flat native list, but active pages remain reachable through capability-filtered groups. Profiles require explicit Directory/deep links; unfinished event/queue pages and Unauthorized stay unlisted. No external API or mutation runs to populate a menu.

Installed Appsmith is Community 2.4.2. The matching [navigation settings contract](https://github.com/appsmithorg/appsmith/blob/v2.4.2/app/client/src/constants/AppConstants.ts), [Menu Button renderer/defaults](https://github.com/appsmithorg/appsmith/blob/v2.4.2/app/client/src/widgets/MenuButtonWidget/widget/index.tsx) and [menu-item property contract](https://github.com/appsmithorg/appsmith/blob/v2.4.2/app/client/src/widgets/MenuButtonWidget/widget/propertyConfig/childPanels/menuItemsConfig.ts) support the implementation. The native settings model is flat; generated standard widgets provide the grouping. This is source evidence, not live rendering/keyboard acceptance.

Menus use canonical account capabilities, compare the actor email with current sign-in and offer Directory even while lookup fails or access is denied. Participant-only sees its functions, Donations Reviewer gets Cash, and permission-specific groups never confer authority. Audit/Reports follow their existing reviewer/practitioner SQL boundaries; Directory Manager alone gets Terminology, not financial/report access. Stable page IDs/routes remain compatibility identifiers; menu and widget captions consume configuration.

High-confidence automated coverage includes all 18 page dispositions, seven role/cache menu cases on every page, registered triggers, explicit read-only query settings, mobile spans, alternate/colliding label configurations, explicit/missing/invalid profile links, current-account/route isolation and late A-to-B reads. Actual prepared navigation SQL is included in authorization tests. Full controller regressions and exact-source export checks are reused. These tests do not establish native rendering, mobile layout, keyboard operation, external delivery or production upgrade safety.

## Test-only preparation

Fresh terminology defaults now present the `member` compatibility key as Participant. Reapplying the initializer preserves installed overrides and attribution. The operator's existing test seed still has its previous labels, so this sequence explicitly updates only the enrollment presentation through the audited Directory Manager API. It creates no operational person/organization, appointment, permission or agreement.

```bash
cd ~/signaturegate
git pull --ff-only
env -u 'BASH_FUNC__sudo%%' bash releases/v1.2.0/validate_navigation_terminology_test.sh
```

The runner targets only `signaturegate_test`. Enter the intended Appsmith Directory Manager sign-in email at the hidden prompt; do not add SQL quotes. It seeds missing defaults twice, adopts Participant presentation and runs rollback-only authority/alternate-label/no-op/domain checks. Expected exit **0**. Keep detailed logs and the entered address private; return only exit code and failed stage if any. Stop on failure; do not bootstrap another manager. Production configuration changes belong to the reviewed release manifest.

## Remaining high-risk UI acceptance

Preserve editor work, pull `chatgpt_development` after the command passes and reload against test. Use the operator's forthcoming walkthrough for these observations:

1. On an authorized and a denied page, open a workflow group and navigate back to Directory. Check one menu with Tab/Enter and one narrow viewport. Navigation remains visible; only permitted entries appear.
2. Open an Individual/Company from Directory, then another record. A direct profile link without an ID must show the selection message and Back; it must not reopen a saved record. Do this read-only.

Terminology cold loading still has operator evidence only after Retry; retest it during the same walkthrough. Stage feedback may be observed during normal authorized test operations. No full role matrix, duplicate contact/consent matrix or repeat cash Exclude/Revive scenario is requested. Paper remains blocked before records/files; actual signing/Listmonk/ERP completion and protected restored-production rehearsal remain separate gates.
