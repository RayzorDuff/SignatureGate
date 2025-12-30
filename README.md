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

