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

### Most reliable: import the **full app JSON**
1. In Appsmith, go to the workspace → **Create New → Import**.
2. Import:
   - `appsmith/Rooted Psyche Membership Ops.json` (repo)
   - or the updated full export provided alongside this doc (if you generated/received one)

3. Update datasources in Appsmith:
   - Postgres datasource → point to your `signaturegate` DB.
   - Any NocoDB API datasource (if used) → point to NocoDB internal hostname.

### If “partial import” fails
If Appsmith partial import fails, use:

- Full app import (recommended), or
- Git Sync and commit the app JSON to a repo.

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

## NocoDB attachments and evidence

In Postgres, `member_agreements.evidence` is stored as **jsonb** (array of file objects).

In NocoDB UI you may set the field to “Attachment”. NocoDB still stores JSON behind the scenes, but:

- your SQL should continue to treat it as `jsonb`
- your upload flow should:
  1) upload file(s) to NocoDB storage (`/api/v2/storage/upload`)
  2) update `member_agreements.evidence` with the returned JSON objects

---

## Where we go next

1. **Agreements - Templates** page (manage templates & required_for tags)
2. Manual-signature reviewer workflow (pending_review → signed/rejected)
3. Release Workflow page (gate: only release if signed)
4. Member information updates, unassigning sacraments and member removal
5. Givebutter integration and tracking member donations

---

## Temporary Airtable integration for product_id inventory

While MushroomProcess is still on Airtable, you can temporarily connect to it:

- n8n has Airtable nodes/connectors
- Appsmith can call Airtable REST API

Recommended pattern:

- Use n8n to periodically sync `products.product_id` (and any metadata you need) into a local mirror table in Postgres.
- This keeps SignatureGate fast and stable while you transition MushroomProcess to NocoDB.

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

## Contributing

Appsmith exports the json for the project in a single line text file.  To convert this file, 
prior to commit or manipulation with a merge tool, run:

```bash
node pretty-json.mjs --in "Rooted Psyche Membership Ops - your-export.json" --out "Rooted Psyche Membership Ops.json" --sort-keys
```

