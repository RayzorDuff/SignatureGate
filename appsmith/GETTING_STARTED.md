# SignatureGate — Getting to a Working Appsmith + Postgres Setup

This doc is written to help a new user get to the **same working point** as the repo currently demonstrates:

- Postgres schema loaded
- Appsmith app imported
- Members can be created (Members – Intake)
- Duplicate-prevention runs before insert
- Optional agreement creation works
- Paper-release uploads work (via NocoDB storage API)

> Note: Appsmith “partial import” (page-only JSON) can fail with an Internal Server Error depending on Appsmith version/permissions. If that happens, use the **full app JSON import** workflow described below.

---

## Load Postgres schema

1. Create the Postgres DB (example):
   - DB name: `signaturegate`
2. Apply the schema:
   - Run the repo’s `db/schema.sql` against that DB.
   - Run any migrations.  See db/README.md
3. Verify tables exist:
   - `members`
   - `agreement_templates`
   - `member_agreements`
   - `sacrament_releases` (if present in your schema)

---

## NocoDB base (recommended)

Even if you prefer Appsmith → Postgres direct for core CRUD, keeping **NocoDB** connected is handy for:

- quick inspection
- attachment handling
- API endpoints

1. Create a NocoDB base and connect it to the same Postgres DB.
2. Confirm you can view/edit:
   - `members`
   - `member_agreements`
   - `agreement_templates`

### Important lesson learned: avoid routing file uploads through nginx (cookie/header bloat)

If your Appsmith datasource calls NocoDB through nginx and you see errors like:

`400 Request Header Or Cookie Too Large`

Route Appsmith to NocoDB using the **internal docker hostname / local network path** (bypassing nginx). This avoids oversized headers/cookies traveling through the reverse proxy.

---

## Import the Appsmith app

For the Issue #19 canonical-identity export, first apply
`db/migrations_issue_19_canonical_people.sql` and run its rollback-only smoke
test as described in `db/README.md`. Its member/contributor queries read the
`member_profiles` and `contributor_profiles` views. The Sacrament Release and
Members - Profile product actions use the MushroomProcess `/pgsql/` n8n
webhooks; those three PGSQL workflows must be active in n8n.

The next Issue #19 Directory export requires
`db/migrations_issue_19_party_contacts.sql` and
`db/migrations_issue_19_directory_read.sql`, with their rollback-only checks,
before import. Directory lists accessible people and organizations and routes
to the read-only Individual Profile or Company Profile. Individual Profile
links back to Members - Profile for authorized membership, agreement, and
release work. Existing Members - Directory and Members - Profile stay in place
until their other actions move; the person-role patch adds editing on Individual
Profile while the older operational workflows remain on the existing pages.

The person-role profile export additionally requires
`db/migrations_issue_19_person_roles.sql`. Run its rollback-only verification,
inspect the account owners, and bootstrap one `directory_manager` as shown in
`db/README.md` before importing the updated Appsmith export. The Individual
Profile then shows role assignment, revocation, and account linking controls to
that manager only. An account email may belong to only one person; use the
actual Appsmith sign-in email. Every change requires a reason and writes an
audit entry. New nonmember account holders can view their own Directory row;
legacy release and donation actions still use member IDs and transitional
member flags. Adding a reviewer role to a nonmember does not yet authorize
those legacy actions.

After `db/migrations_issue_20_organization_terminology.sql` and its
rollback-only verification, import the matching Appsmith export. Individual
Profile reads the configured label for the stable `practitioner` concept;
Rooted Psyche's default is **Spiritual Practitioner**. The separate
`facilitator` concept is inactive and reserved for a future regulated role.
Changing a label does not rename a role key, grant an appointment, or rewrite
audit history and executed agreements. Issue #20's remaining UI and Documenso
inventory is tracked in `docs/ISSUE_20_TERMINOLOGY_INVENTORY.md`.

After `db/migrations_issue_19_person_release_operations.sql` and its
rollback-only verification, import the matching Appsmith export. Sacrament
Release authenticates the signed-in person's practitioner appointment, lists
only practitioners assigned to the selected active member, and filters
MushroomProcess products through that selected person's storage grants. The
configured practitioner label is presentation only. A practitioner no longer
needs a member record to be selected or attributed on a release. Existing
member-based release IDs and storage grants are retained as compatibility
projections while the older Members - Profile storage editor remains in use.

After `db/migrations_issue_19_contributor_directory_intake.sql` and its
rollback-only verification, import the next Appsmith export. A donations
reviewer can create a standalone individual or company contributor in
Directory, with optional email and phone. Existing contacts block creation
until the reviewer checks the Directory for a matching identity; leave the
contact blank only when the contributor is known to be distinct. A person
already present in Individual Profile can be enabled as a contributor by a
directory manager who is also a donations reviewer. Both operations require
a reason and write an audit entry. Neither grants membership or release
eligibility. The contributor intake phase does not add company-contact editing
or membership enrollment to the new profiles.

After applying `db/migrations_issue_19_contributor_contacts.sql` and its
rollback-only verification, import the newer Appsmith export. A donations
reviewer can then add or archive contributor-purpose email and phone contacts
from either Individual Profile or Company Profile. Adding a contact makes it
primary for its type; archiving the primary promotes the oldest remaining
active contact. Each action requires a reason and is audited. A contact
already owned by a different person or company is refused until that shared
contact has been reviewed. Member-purpose email and phone records remain on
the existing Members - Profile workflow; these contributor controls never
edit those membership contacts.

After applying `db/migrations_issue_19_existing_person_membership.sql` and
its rollback-only check, import the newer export. Individual Profile offers
**Enable membership** to an account with both directory-manager and
document-reviewer permission. The reviewer confirms first and last names and
enters a reason. For a person missing structured names, the reviewed names
complete the central `people` identity. A different existing name cannot be
silently overwritten. The new member links to the same person and any active
individual contributor; it does not alter past donations. Follow the link to
Members - Profile to add membership-purpose contact details and agreements.
An existing archived member requires separate review rather than creation of
a second member ID.

After `db/migrations_issue_19_end_membership.sql` and its rollback-only check,
import the newer export. A directory manager who is also a document reviewer
can use Individual Profile to **End membership** for an active member. The
action requires a reason. It sets the member to inactive, ends any active
contributor/member link, and keeps the person, contributor when present,
donations, agreement and release history.
Pending agreements, practitioner/reviewer permissions, and active facilitator
assignments must be resolved first. An ended membership remains visible in the
individual's membership history; **Enable membership** does not create another
member ID for this person. The button to enable membership is intentionally
hidden for everyone who already has a member record. The Sacrament Release page
checks membership again before calling the inventory shipment endpoint; the
database also refuses any new release for an inactive member.
Ending membership neither requires nor creates a contributor. Member-purpose
contacts remain on the historical member record and are not copied
automatically into contributor contact records.
The End membership section remains visible to an authorized reviewer even
when the action is unavailable. It displays the first condition to resolve;
the button becomes available only after database eligibility checks pass.

After `db/migrations_issue_19_contributor_addresses.sql` and its rollback-only
verification, import the next Appsmith export. Donations reviewers can add
and archive contributor-purpose mailing addresses on Individual and Company
Profile, with a required reason and audit history. The street, unit, postal
code, and country identify a physical address; differing city/state spelling
does not create a second address, while different apartments remain distinct.
The first active address is primary. Archiving the primary promotes the oldest
remaining address. A shared building may legitimately have multiple people
or organizations, so matching mailing addresses do not merge identities.
Member-purpose addresses remain on the historical member record.

After `db/migrations_issue_19_contact_role_assignment.sql` and its rollback-only
verification, import the newer Appsmith export. Individual Profile then offers
**Use an existing contact for the other role** to a directory manager with both
document-reviewer and donations-reviewer permissions. Select an existing
membership or contributor email, phone, or physical address and enter a reason.
The contact remains with its original capacity and acquires a second capacity
source on the *same person-owned contact*. A contact already used by both is
omitted. An active contributor can reuse a contact from an ended membership;
Individual Profile shows that source as **former membership** to authorized
reviewers. A member-only individual can see existing contacts before enabling
contributions, but assignment waits until the contributor is active. Assigning
to membership still requires an active membership. A company cannot gain a
membership contact. New membership email sources default to not
subscribed to Listmonk. Verification of the original email does not
automatically verify the newly assigned copy. If a shared household email or
phone belongs to a different party, review the identity conflict before
assigning it across capacities.

After `db/migrations_issue_19_contributor_profile_history.sql` and its
rollback-only verification, import the matching Appsmith export. Individual
Profile and Company Profile then show contributor-attributed donation history
and external provider identities. These are read-only profile sections and use
the same contribution visibility scope as Directory; they do not infer
membership or expose reviewer notes. The profile sections render whenever the
profile itself is available; their database functions continue to enforce
contribution visibility. The contributor mailing-address apartment/suite field
is optional.

After `db/migrations_issue_19_contributor_status.sql` and its rollback-only
verification, import the matching Appsmith export. A directory manager who is
also a donations reviewer can archive or reactivate an individual or company
contributor from its profile. Every change requires a reason and is audited.
Archiving stops the contributor from active intake and matching but preserves
the party, contacts, provider identities, donations, and any separate
membership. Archived contributors remain in Directory for those authorized
managers so that their history can be reviewed and they can be reactivated.
Contributor contact controls remain unavailable while the contributor is
archived.

After `db/migrations_issue_19_party_identity_editing.sql` and its rollback-only
verification, import the matching Appsmith export. A directory manager can
correct an individual's canonical display name, structured name, and optional
birth date from Individual Profile, or an organization's canonical name from
Company Profile. A reason is required, old and new values are audited, and a
stale profile must be refreshed before saving. The change updates the central
`people` or `organizations` identity only; it does not replace member or
contributor IDs or alter donations, contacts, agreements, releases, or roles.

After `db/migrations_issue_19_sacrament_release_scope.sql` and its rollback-only
verification, import the matching Appsmith export. The former **Release -
Issue** page is now **Sacrament Release**. It records only tangible sacrament
transfers, always writes `release_type = 'sacrament_release'`, and checks an
agreement authorizing sacrament release. Membership, sweat-lodge, and retreat
agreement types are not release choices. Directory provides **Record Release**
only for an individual with an active membership; company, nonmember, and ended
membership rows remain disabled. Historical non-sacrament release values are
reported for review rather than silently reclassified.

After `db/migrations_issue_19_member_operations_read.sql` and its rollback-only
verification, import the matching Appsmith export. Individual Profile shows
agreement history and practitioner assignments to document reviewers and to
the practitioner currently assigned to that membership. A donations-only
reviewer does not gain access. **Open member operations** continues to use the
existing Members - Profile write workflow while it is migrated, and **Record
sacrament release** opens the dedicated transfer page only for an active
membership. Agreement approval, sending, cancellation, contact changes, and
assignment changes remain on Members - Profile in this phase.

After `db/migrations_issue_19_membership_contributor_independence.sql` and its
rollback-only verification, import the matching Appsmith export. A member-only
individual can end membership without first being made a contributor. If the
person independently has contributor capacity, it remains active and any
member/contributor link is ended; donation attribution is not rewritten. The
profile language no longer describes membership closure as conversion to a
contributor.

After `db/migrations_issue_19_member_contact_profiles.sql` and its rollback-only
verification, import the matching Appsmith export. Individual Profile then
provides one email/phone editor with a **Contact role** selector. It offers only
Membership and/or Contributor when that capacity exists and the signed-in
reviewer may access it. Membership writes still go only to `member_emails` and
`member_phones`; contributor writes still go only to the contributor tables.
Assigned practitioners have read-only membership visibility. New member emails
start as not subscribed to Listmonk, and an existing contact is shared across
capacities only through the separate reviewed cross-role assignment control.

After `db/migrations_issue_19_sacrament_agreement_gate.sql` and its rollback-only
verification, import the matching Appsmith export. Sacrament Release accepts a
signed agreement from any template version whose `required_for` includes
`sacrament_release`. Deactivating an old template prevents new selection but
does not invalidate agreements already signed from it. Reviewed template-free
paper/manual agreements retain their legacy eligibility path.

After `db/migrations_issue_19_member_address_profiles.sql` and its rollback-only
verification, import the matching Appsmith export. The role-aware contact editor
also handles **Mailing address**. Choose Membership or Contributor before adding
or archiving an address. Membership operations write only `member_addresses`;
contributor operations write only `contributor_addresses`. Apartment or suite
remains optional. Reusing one existing address for the other capacity still
uses the separate reviewed cross-role assignment control.

After `db/migrations_issue_19_person_practitioner_assignments.sql` and its
rollback-only verification, import the matching Appsmith export. Individual
Profile can assign or end a practitioner relationship for an active membership.
The selector lists people holding the practitioner appointment, including
people who are not members. A reason is required and assignment history remains
visible. Existing `member_facilitators` rows are backfilled and legacy pages
continue to synchronize through a compatibility projection when the
practitioner has a member ID. Agreement sending and sacrament-release actor
fields still use the legacy member-based workflow in this phase, so those
legacy action buttons remain available only to an actor with an active legacy
facilitator member record. End active assignments before removing a person's
practitioner appointment.

### Most reliable: import the **full app JSON**
1. In Appsmith, go to the workspace → **Create New → Import**.
2. Import:
   - `appsmith/Rooted Psyche Membership Ops.json` (repo)
   - or the updated full export provided alongside this doc 

3. Update datasources in Appsmith:
   - Postgres datasource → point to your `signaturegate` DB.
   - Any NocoDB API datasource (if used) → point to NocoDB internal hostname.


---

## Configure key pages

### Members - Directory
- Lists members
- Row click should navigate to Members - Profile with a URL param `member_id` (recommended)

### Members – Intake
- Creates a new member
- Validates duplicates (first+last, email, phone)
- Optionally creates an agreement record (OpenSign or Paper)
- If paper is chosen, evidence attachments are uploaded and `member_agreements.evidence` is populated.

### Members - Profile
- Used to initiate agreement flows for an existing member (same logic as intake but with member_id already known)

---
## Agreement Template Selection

When issuing or sending a digital agreement, facilitators must explicitly select an agreement template.

The system does not automatically choose a template based on type alone.
This ensures correct handling of multiple templates (e.g. language variants).

- Create your agreement template entries using the page Agreements - Templates.
- You can get your envelopeId from Documenso.  After you have created the Agreement Template in Documenso,
  find the envelopeID pattern in the URL.  For example:  
  
  https://documenso.danks.store/t/facilitators/templates/envelope_hyneotebbuzwfzly
  
  The envelopeID is envelope_hyneotebbuzwfzly
- Issue the following command to determine the signers for the Template:
```bash
  curl -sS -X GET "https://documenso.danks.store/api/v2/envelope/envelope_hyneotebbuzwfzly" \
  -H "Authorization: api_yourapiauthsecret" | jq '.recipients[] | {id,email,name,role,signingOrder}'

{
  "id": 5,
  "email": "",
  "name": "",
  "role": "SIGNER",
  "signingOrder": 1
}
{
  "id": 6,
  "email": "",
  "name": "",
  "role": "SIGNER",
  "signingOrder": 2
}
```
- In the above example, the first signer, id 5 is the MemberID and the second signer, id 6 is the FacilitatorID.

---

## NocoDB attachments and evidence

In Postgres, `member_agreements.evidence` is stored as **jsonb** (array of file objects).

In NocoDB UI you may set the field to “Attachment”. NocoDB still stores JSON behind the scenes, but:

- SQL should continue to treat it as `jsonb`
- Upload flow should:
  1) upload file(s) to NocoDB storage (`/api/v2/storage/upload`)
  2) update `member_agreements.evidence` with the returned JSON objects

---

## Where we go next

1. Member information updates, unassigning sacraments and member removal
2. Event Management

---

## Temporary Airtable integration for product_id inventory

While MushroomProcess is still on Airtable, N8N will temporarily connect to it:

- n8n has Airtable nodes/connectors

---

## Authentication, roles, and access control

SignatureGate relies on **Appsmith authentication** and then maps the authenticated email to `public.members`.

### Appsmith settings (must-do)

1) **Do not make the app public** (login required)
   - In Appsmith: App → Share / Access settings → ensure public/anonymous access is disabled.
2) Add users in Appsmith using the same email they will use to sign in.
3) Confirm `appsmith.user.email` shows the correct value in a widget or via a debug toast during setup.

### Database setup for users

Each person who needs access should have:

- an Appsmith user account (email-based)
- a matching `public.members` row:
  - `email` matches Appsmith login email
  - `status = 'active'`
  - set at least one role flag:
    - `is_facilitator = TRUE` for facilitators
    - `is_document_reviewer = TRUE` for reviewers (optional)

### What the app enforces

On page load, the app runs an auth gate (JS) that:

- waits for `appsmith.user.email` to be available
- calls `qCurrentFacilitator` using `{ email: appsmith.user.email }`
- treats “no matching active facilitator/reviewer row” as **Access denied**
- treats real query errors (DB down, bad SQL, etc.) as **Access check failed**
- stores useful context in `appsmith.store` (for defaults and filtering)

### Query parameter best-practice

To avoid issues with auth hydration timing, prefer passing the email as a parameter:

```sql
WHERE lower(email) = lower({{ this.params.email }})
```

…and in JS:

```js
qCurrentFacilitator.run({ email: appsmith.user.email })
```

### Troubleshooting

If a user is unexpectedly denied:

1) Confirm the Appsmith user can log in and `appsmith.user.email` is populated.
2) Confirm the member row exists in Postgres and is active:

```sql
SELECT member_id, email, status, is_facilitator, is_document_reviewer
FROM public.members
WHERE lower(email) = lower('<email>');
```

3) Confirm migrations were applied in this order:
   - `db/migrations_facilitator_review.sql`
   - `db/migrations_facilitator_authentication.sql`
   - `db/migrations_sacrament_release.sql`
   - (optional) `db/migrations_documenso_integration*.sql`

## Audit logging behavior

Most Appsmith workflows automatically write audit records when performing sensitive actions.

When modifying or adding workflows that:
- create members
- issue agreements
- attach evidence
- issue sacrament releases

ensure that an audit entry is written using the shared audit helper.

Audit logging must never block the primary workflow, but it must not be removed or bypassed.

When adding or modifying Appsmith workflows:
- Any action that changes legal, financial, or sacramental state **must** write an audit log entry

## Donations Workflow

### Cash Donations
1. Facilitator selects a contributor/member identity or the explicit `Anonymous cash donor` option
2. Facilitator creates a cash donation entry (`pending_review`)
3. Anonymous cash retains `member_id = NULL`; no synthetic member is created
4. Donations reviewer verifies or rejects the entry
5. Audit log records both actions

### Givebutter Donations

Issue #19 makes contributor identity independent of membership. In the pending
review queue, a donations reviewer can assign a Givebutter donation to an
existing contributor or member, create a new individual contributor, create a
new organization contributor, or create a new member with a linked individual
contributor. Creating or selecting a contributor does not create a membership
agreement or grant sacrament-release eligibility.

The contributor/member selector uses prefixed values (`contributor:<uuid>` and
`member:<uuid>`) so the database can preserve compatibility while treating
`contributor_id` as the authoritative donation identity.

The current export creates individual or organization contributors only while
resolving an unresolved Givebutter donation. Standalone contributor creation,
contact maintenance, and starting or ending a contributor-member link require
the planned contributor administration UI; they are not exposed by the current
Donations page.

- Automatically ingested via n8n webhook
- Automatically verified
- Contributor is matched by provider identity or a unique email/phone, with a
  member-contact compatibility fallback
- Audit entry written on receipt

### Permissions
- `is_facilitator`: create cash donations
- `is_donations_reviewer`: verify donations, see full member list

## Contributing

Appsmith exports the json for the project in a single line text file.  To convert this file, 
prior to commit or manipulation with a merge tool, run:

```bash
node pretty-json.mjs --in "Rooted Psyche Membership Ops - your-export.json" --out "Rooted Psyche Membership Ops.json" --sort-keys
```
