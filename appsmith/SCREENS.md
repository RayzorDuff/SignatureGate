# Appsmith screens (starter)

## 1) Dashboard
- Today’s events
- Pending agreements (members with upcoming event but missing signed docs)
- Recent sacrament releases
- Quick search (member / email / phone / product_id)

## 2) Members
- List + filters (active/inactive)
- Member detail: contact info, agreements, releases, donations
- Actions: create member, deactivate, merge duplicates

## 3) Agreements
- Agreement templates (name, version, required_for, active)
- Member agreements (status, evidence link, method)

## 4) Event Check-in
- Select event
- Check-in member (verify signed agreements)
- If missing: send OpenSign link, or mark “paper signed pending upload”

## 5) Sacrament Release (Gate)
- Input/scan: member + product_id
- Quantity + unit
- “Validate lot” (from bridge or API)
- “Release” button (runs hard gate)
- Print receipt / QR (optional later)

## 6) Donations
- Manual entry (cash)
- List Givebutter imports (read-only)
- Member donation history

