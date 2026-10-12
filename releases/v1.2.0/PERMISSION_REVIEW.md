# Application permission regression repair

The operator's October 11 checks found unauthorized Intake/cash visibility, inconsistent canonical reviewer entry, unusable denial navigation, an over-escaped email validator, contradictory cash alerts and unscoped inventory on an empty location list. These are release blockers. The implementation below passes isolated tests; live acceptance remains pending.

## Authority and access matrix

An active `person_app_accounts` owner and canonical `person_roles` determine access. Participant capacity enables only self-read access; it does not grant operational roles. Legacy membership flags and shared browser stores do not grant permissions. Directory Manager permission does not implicitly grant reviewer or practitioner roles.

| Surface | Participant only | Document Reviewer | Donations Reviewer | Facilitator/Spiritual Practitioner |
| --- | --- | --- | --- | --- |
| Participant/Member Functions | Read own active Participant only | Manage Participants and documents | Own read if a Participant; no document administration | Assigned Participant workflows |
| Intake | Denied | Participant enrollment | Contributor enrollment | Denied |
| Practitioner administration | Denied | Allowed, independent of Participant capacity | Denied | Denied unless also Document Reviewer |
| Cash recording | Denied | Participant-linked or anonymous pending cash | Contributor/Participant/anonymous pending cash | Assigned Participant-linked pending cash only |
| Financial review and Cash Deposits | Denied | Denied | Allowed without Participant capacity | Denied |
| Sacrament Release | Denied | Denied unless also a practitioner | Denied unless also a practitioner | Assigned Participant and explicit practitioner storage grants |
| Reports | Denied | Participation metrics | Contribution metrics | Assigned participation metrics |
| Terminology Administration | Directory Manager required | Directory Manager required | Directory Manager required | Directory Manager required |

A combined-role account receives the explicitly granted capabilities. A Contributor capacity alone grants no staff access. Appsmith application invitation/platform access is separate from these business permissions; use viewer test accounts rather than trusted application editors for end-user acceptance.

## Implementation

- `application_authorization.sql` adds a single canonical access context and participant read/write scope. New Intake/cash/review APIs take the current application's authenticated email; actions do not take their actor from a form or cached UUID.
- Transitional actor references preserve existing cash actor UUIDs while allowing new canonical staff IDs in cash batches/items/exclusions. No historical actor IDs, deposit composition or role grants are rewritten. Tally/print actor labels resolve canonical people/accounts. Reapplication is tested. Constraint changes require a restored-copy rehearsal before production.
- New cash recording and review APIs authorize independently and audit atomically. Document Reviewers need no Participant record to enter pending anonymous cash; they cannot verify/reject or browse organization-wide financials. Audit failure rolls back the cash write.
- Participant self-read queries enforce identity ownership in SQL. Changing a selected/stored/URL UUID cannot reveal another Participant. Staff controls and row actions are hidden for self-read accounts; raw writes and external-action controllers reject them.
- Denials remain on the requested page with its native navigation. The hidden legacy denial page has explicit return buttons and no longer tells every user to become a practitioner.
- Intake's regex now uses correct escaping and matches the profile-style practical email rule. It is checked before writes. Optional blank email is not inserted when phone/address supply the accepted two contacts.
- Cash donor choices are role scoped. The Participant compatibility choice is explicitly labeled as creating Contributor capacity when cash is recorded. Capacity creation does not grant system permissions.
- SQL dynamic binding paths are registered; prepared SQL bindings are not placed inside SQL string quotes. A failed refresh after a committed cash write yields one warning that the write succeeded, rather than a false failure or a retry invitation.
- Inventory does not load before authorization/assignment scope. Empty grants produce no request and no displayed products; requested empty/malformed location filters also deny all locations in the isolated Code-node helper candidate. Storage grants belong to the selected practitioner, not directly to the Participant.

## Evidence and limits

`verify_application_authorization.sql` covers canonical-only roles, stale legacy flags, Participant self/other/write scope, direct Intake/cash denial, assigned/unassigned practitioner cash, anonymous and company boundaries, nonmember reviewer cash lifecycle, tally/print, immutable confirmation, audited date correction, disabled accounts and audit failure rollback. Cash end-to-end/lifecycle/tally/print/ERP/correction regressions pass with artificial canonical accounts. The end-to-end fixture no longer depends on an operational person's sign-in address.

Appsmith tests execute the actual source action SQL with bind parameters, and check email validation, self routing, raw mutation denial, financial audit scope, cash refresh/write failure separation and on-load inventory isolation. Source/export preservation, all collection syntax/JSON, naming and release checks pass.

`evidence/application_permissions.csv` inventories every current DB/API action. Its markers are review indicators, not a claim that every deployed action or external endpoint has been certified. Provider-resolution/contact parity, external send/cancel/upload/ERP/bank-lookup authentication and publication/credential targets still need their own source/runtime review. Unfiltered legacy/admin inventory consumers are retained; this increment does not certify direct HTTP endpoint authorization. No production migration, workflow publication or Appsmith master promotion has occurred.

Follow [PERMISSION_VALIDATION.md](PERMISSION_VALIDATION.md). Return role/capability pass/fail and error classes; retain names, contacts, amounts, account values, screenshots and detailed logs privately.

The n8n export was excluded after automatic approval review rejected its operational configuration. Only the isolated helper and synthetic tests are included; see [INVENTORY_LOCATION_SCOPE.md](../../n8n/INVENTORY_LOCATION_SCOPE.md). Its workflow integration remains pending.
