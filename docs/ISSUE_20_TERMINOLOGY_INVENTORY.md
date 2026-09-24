# Issue #20 Terminology Inventory

This inventory separates stable application concepts from deployment-specific
labels. It is the migration checklist for Issue #20, not an instruction to
globally replace `facilitator` with `Spiritual Practitioner`.

## Architectural rule

- Internal concept and role keys are stable contracts.
- Organization terminology controls presentation only.
- `practitioner` and a future regulated `facilitator` are distinct concepts.
- Rooted Psyche currently displays the operational `practitioner` concept as
  **Spiritual Practitioner**.
- Another deployment may display that same general concept as **Facilitator**.
- A future Rooted Psyche `facilitator` appointment can coexist with
  `practitioner`; activating a label must never grant a role or permission.

## Surface inventory

| Surface | Current state | Migration treatment |
| --- | --- | --- |
| `person_roles.role_key` and authorization functions | Stable internal `practitioner` key | Keep stable; never derive authorization from a label |
| `member_practitioner_assignments` | Canonical person-based assignment | Keep stable; consume configured labels in UI |
| `member_facilitators`, `members.is_facilitator`, legacy foreign keys | Transitional member-ID compatibility | Preserve until agreement, release-actor, and storage-access migrations are complete |
| Individual Profile assignment controls | New Issue #19 UI | First consumer of `organization_terminology` |
| Members - Intake/Profile/Directory | Older UI with facilitator literals | Agreement writes now resolve to a canonical practitioner person; migrate remaining page labels and member operations before retiring these pages |
| Sacrament Release | Canonical practitioner person, configured display label, nullable legacy member projection | Completed for release issuance and storage authorization; keep internal function/column contracts stable |
| Donations | Older facilitator wording for cash-entry actor | Keep contributor identity independent; migrate display text separately |
| Audit Log | Historical machine actions and text | Never rewrite history; new UI may render current labels around stored events |
| Agreement Templates | Renamed from Agreements - Templates | Completed; internal Documenso recipient field names remain compatibility contracts |
| n8n workflows | Field names and audit payloads include facilitator | Agreement delivery now resolves the canonical practitioner person and person-owned email; retain Documenso `facilitator_*` recipient names until template/API versioning |
| Database errors/comments/docs | Mixed user-facing and internal language | Migrate user-facing errors deliberately; retain clear legacy comments |
| Documenso templates and executed agreements | Legally significant text | Inventory only; do not modify while the Spiritual Practitioner Agreement is under review |

## Concept registry introduced by this phase

`terminology_concepts` owns immutable concept keys and their semantic kind.
`organization_terminology` owns deployment labels and whether a concept is
currently presented. SignatureGate is presently one organization per
deployment, so one terminology profile is sufficient without inventing a
multi-tenant organization boundary.

The registry includes separate keys for `practitioner`,
`spiritual_practitioner`, `traditional_practitioner`, `facilitator`, and
`minister`. Reserved concepts can remain inactive until their behavior,
authorization, and legal meaning are designed.

## Remaining phases

1. Add an operator UI for terminology changes and a preview of affected labels.
2. Migrate remaining Appsmith user-facing literals page by page.
3. Migrate the remaining Members pages from member-ID practitioner selectors to
   person-ID selectors. Agreement, release, and storage records now have
   canonical practitioner identity; retain legacy projections until old
   consumers are retired.
4. Inventory Documenso variables and templates after legal/board review; never
   rewrite executed agreements.
5. Test both Rooted Psyche defaults and an alternate deployment that presents
   `practitioner` as **Facilitator**, plus a future configuration where the
   separate `facilitator` concept is active at the same time.
