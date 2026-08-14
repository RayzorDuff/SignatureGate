# SignatureGate v1.1.0

Release date: 2026-08-13

## Summary

This release establishes the SignatureGate member, agreement, release, and donation baseline that accompanies MushroomProcess v1.2.0. It hardens identity and document workflows and records the approved direction for Givebutter donation reporting and ERPNext integration without claiming those future integrations are complete.

## Highlights

- Blocks Member Intake when an exact normalized active phone already belongs to another member.
- Repairs Members Intake Agreement Type and facilitator list initialization.
- Hardens multi-file paper agreement uploads and synchronizes generated profile actions.
- Hides rejected donations by default and excludes Sample-class inventory from release selection.
- Documents the cross-system commerce, financial, payment, donation, and inventory architecture.

## Architecture boundary

Givebutter ingestion already exists, but making Givebutter the official member donation-reporting interface and posting reviewed donations/deposits into ERPNext remain planned work. The cross-system specification is authoritative design input, not a declaration that the new workflows are deployed.

## Deployment notes

- Apply `db/migrations_member_intake_exact_phone_block.sql` after the v1.0.4 identity migrations and before importing the updated Appsmith export.
- Deploy the updated Appsmith export and n8n assets only after reviewing environment-specific bindings.

## Coordinated baseline

- MushroomProcess `v1.2.0`
- SignatureGate `v1.1.0`
- RootedOps `v1.1.0`
- BookWorks `bookworks-v3.3.0`
