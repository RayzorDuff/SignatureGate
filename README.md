# SignatureGate

SignatureGate is an open-source, self-hosted membership + agreement + sacrament-release tracking system for **Rooted Psyche**.

It is designed to stay **separate but interoperable** with the MushroomProcess inventory/workflow system used by Dank Mushrooms, by linking to MushroomProcess lot IDs (and/or packaged product IDs) without requiring a shared database.

## What this solves

- Track **members** and their contact info
- Track **agreements** (paper, OpenSign, etc.) and ensure the correct agreement(s) are signed **before** a sacrament release
- Track **sacrament releases** to members with **traceability back to MushroomProcess lot_id**
- Track **events** (ceremony, retreat, sweat lodge, etc.) and tie agreements + releases to a specific event
- Track **voluntary donations** (cash, Givebutter) without treating them as payment for sacrament

> Rooted Psyche packet language: sacraments are not sold; donations are voluntary. See `docs/policy-notes.md`. 

## Architecture (high level)

- **Postgres #1**: `signaturegate_db` (this project’s core data)
- **Postgres #2**: `mushroomprocess_bridge_db` (optional; either a replica/readonly mirror of MushroomProcess tables, or a small “bridge” schema for caching lot metadata)
- **NocoDB**: admin UI for both DBs (separate Bases / data sources)
- **n8n**: automation + sync between systems (OpenSign/Givebutter/email/etc.)
- **Appsmith**: operator-facing app (check-in, releases, scanning QR/lot IDs)

See: `docs/architecture.md`.

## Quick start (Docker Compose)

1. Copy environment file:
   ```bash
   cp .env.example .env
   ```
2. Start services:
   ```bash
   docker compose -f deploy/docker/docker-compose.yml up -d
   ```
3. Open:
   - NocoDB: http://localhost:8080
   - n8n: http://localhost:5678
   - Appsmith: http://localhost:8081

## License

This repository is licensed under **GNU GPL v3.0** (see `LICENSE`).

Rationale: MushroomProcess is GPL; choosing GPLv3 here keeps license compatibility to allow for shared code or common modules between projects.

## Development notes

- Database schema (baseline): `db/schema.sql`
- Seed data: `db/seed.sql` (optional)
- n8n workflow stubs: `n8n/workflows/`
- Appsmith screen specs: `appsmith/SCREENS.md`

## Security / privacy note

This system will store personal contact info and signed agreement references. Use:
- TLS (Caddy/Traefik), strong passwords, least-privilege DB users
- Encrypted storage for documents (S3 compatible / object storage recommended)
- Regular backups (Postgres + object storage)

## Audit Logging

SignatureGate maintains a centralized, append-only audit trail in `public.audit_log`.

The audit log records all legally, spiritually, and operationally significant events, including:

- Authentication outcomes
- Member creation and status changes
- Agreement creation, signing, and evidence attachment
- Sacrament release issuance
- Product shipment and final release completion

### Design principles

- Audit records are **append-only** and must never be modified or deleted.
- Audit logging is **not** a debugging or analytics system.
- If an action would ever need to be explained, reviewed, or defended later, it must be audited.

### Where audits are written

- **Appsmith**
  - User-initiated actions (auth, member creation, agreement issuance, release issuance)
- **n8n**
  - External system callbacks (Documenso)
  - Final irreversible workflow steps (product shipment)

Audit writes are intentionally split this way to ensure:
- correct actor attribution
- durability even when external systems are involved

## Authentication and role-based access (Appsmith)

SignatureGate is intended to be deployed as a **private Appsmith app** (login required). The app reads the authenticated user identity from:

- `appsmith.user.email`

…and maps that email to a row in `public.members` to determine permissions.

### Roles

- **Facilitator**: `members.is_facilitator = TRUE`
  - Can use the app.
  - Member directory results are scoped to: members they created, members where they are the facilitator on an agreement, or members where a sacrament release exists with them as facilitator.

- **Document Reviewer**: `members.is_document_reviewer = TRUE`
  - Sees the full member directory (for review/QA workflows).

### Deployment requirements

- Do **not** make the app public.
- Create Appsmith users (invite) using the **same email** you store in `members.email`.
- Ensure the member row is `status='active'` and has the appropriate role flag(s).

Implementation details and troubleshooting are in `appsmith/GETTING_STARTED.md`.

## Documenso signing

### Documenso database migrations

If you enable Documenso integration, apply the Documenso migration(s) in addition to the core schema/migrations:

- `db/migrations_documenso_integration.sql`
- `db/migrations_documenso_integration_1.sql`

See `n8n/DOCUMENSO_INTEGRATION.md` for the Documenso workflow wiring and tokens.

Two-party signing (Member + Facilitator) is implemented via n8n + Documenso.

- Setup & workflows: `n8n/DOCUMENSO_INTEGRATION.md`
- Certificate troubleshooting: `deploy/DOCUMENSO_CERT_TROUBLESHOOTING.md`
