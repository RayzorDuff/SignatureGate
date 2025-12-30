# n8n event list (starter)

This is the minimum automation set for SignatureGate.

## Identity & agreements

1. **Member created/updated**
   - Trigger: Appsmith form submit or NocoDB webhook
   - Actions: normalize contact info, de-dupe by email/phone, write audit_log.

2. **OpenSign signature completed**
   - Trigger: OpenSign webhook (or polling)
   - Actions:
     - upsert `member_agreements` (status=signed, signed_at, evidence_url)
     - notify facilitator/operator if member is checked in for an event.

3. **Paper agreement uploaded**
   - Trigger: Appsmith upload (to S3/object storage)
   - Actions: store `evidence_url`, mark agreement verified.

## Sacrament release gatekeeping

4. **Attempted release**
   - Trigger: Appsmith “Release” button
   - Actions (hard gate):
     - verify required agreement(s) are signed (member_agreements.status=signed) for `required_for @> {'sacrament_release'}`
     - verify eligibility checklist captured if you adopt it (future enhancement)
     - if OK: create `sacrament_releases` record + audit_log
     - if not OK: return error + create audit_log denial entry.

## Inventory interop (choose one)

5A. **Bridge sync: MushroomProcess → bridge db**
   - Trigger: cron (every 5–15 minutes)
   - Actions: read MushroomProcess products and cache minimal fields keyed by `product_id`.

5B. **On-demand lookup**
   - Trigger: Appsmith “Validate Lot” action
   - Actions: query MushroomProcess API; optionally cache to bridge db.

## Donations

6. **Givebutter donation received**
   - Trigger: Givebutter webhook (or polling)
   - Actions: create `donations` row; link to member by email if possible; audit_log.

