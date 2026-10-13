# SignatureGate Appsmith screen inventory

This is the v1.2.0 development candidate inventory. Source/generated-menu tests pass; live grouped-menu, keyboard/mobile and profile rendering acceptance remains open. Production retains its separately published revision until release gates pass. The application/export's technical name remains Rooted Psyche Membership Ops.

The native title, sign-in and Directory navigation remain available. Four generated Menu Button groups provide the active workflow links. Pages without required canonical authority are omitted from groups; denied pages retain an escape to Directory. Menu visibility is presentation only: every data/action still needs its existing signed database/API permission.

| Group | Default display | Stable page ID | Authority and purpose |
| --- | --- | --- | --- |
| People & Organizations | Directory | Directory | Accessible identities and selected-profile entry; scoped SQL determines visible rows |
| People & Organizations | Intake | Intake | Document Reviewer for Participant enrollment; Donations Reviewer for Contributor enrollment; Directory Manager plus both reviewers for dual capacity |
| People & Organizations | Legacy Intake | Members – Intake | Retained Document Reviewer workflow until parity; paper blocked |
| Participation & Practice | Participant Functions | Member Functions | Participant self-read; Document Reviewer/assigned Spiritual Practitioner operations, subject to resource/write checks |
| Participation & Practice | Spiritual Practitioner Functions | Facilitator Functions | Document Reviewer manages assignments and storage scope; labels follow the practitioner configuration |
| Participation & Practice | Sacrament Release | Sacrament Release | Spiritual Practitioner appointment and scoped Participant/location/agreement gate |
| Contributions | Contributor Functions | Contributor Functions | Reviewers and scoped Spiritual Practitioners; donations review requires Donations Reviewer; cash recording follows its separate permission |
| Contributions | Cash Deposits | Cash Deposits | Donations Reviewer only; reconciliation, batches and guarded ERP synchronization |
| Reports & Administration | Reports | Reports | Reviewers/Spiritual Practitioners; financial metrics require Donations Reviewer independently |
| Reports & Administration | Agreement Templates | Agreement Templates | Document Reviewer; types and template administration |
| Reports & Administration | Audit Log | Audit Log | Reviewers/Spiritual Practitioners; financial versus document/assigned-person audits scoped independently |
| Reports & Administration | Terminology Administration | Terminology Administration | Directory Manager; audited organization-facing labels; no role/capacity grants |

Individual Profile and Company Profile are hidden context pages. Directory supplies an explicit UUID; valid accessible deep links also work. Missing/invalid/inaccessible links never reuse stored selections. Back to Directory remains available. Profile content stays hidden during dependent loading or after stale account/route/query results; reload restores the selected record after a failed read.

Unauthorized, Agreements - Queue, Events - Create and Events - Check In remain unlisted. Their presence in source is not acceptance of a supported workflow. Events/queue are not exposed by this navigation increment. No page is deleted, and legacy Intake is not retired yet.

Participant and Spiritual Practitioner captions use deployment labels while `member`, `member_id`, `practitioner`, compatibility field names and page IDs remain stable. Historical records and executed agreement text are not passed through the UI-copy formatter. Rooted Psyche defaults refer to Facilitator/Spiritual Practitioner in explanatory documentation; a separately reserved regulated facilitator concept remains distinct and inactive.

The source of truth is `SignatureGate-Appsmith/navigation/registry.json` plus `navigation/labels.js`. Run `python3 scripts/generate-navigation.py`, then `--check`, controller/menu tests and exact-source export validation after changes. Review pull/reload behavior before packaging. See [the validation sequence](../releases/v1.2.0/NAVIGATION_AND_PARTICIPANT_VALIDATION.md).
