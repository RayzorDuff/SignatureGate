# Appsmith screens: historical starter outline

**This outline is outdated and is not the current supported navigation or acceptance checklist.** It is retained until the v1.2.0 navigation work is accepted. The release todo explicitly requires replacing it with the final page/group inventory, role visibility, `Directory`-only profile entry points, deep-link behavior and page-purpose guidance before packaging. See `releases/v1.2.0/RELEASE_PLAN.md` and `appsmith/GETTING_STARTED.md` for the current setup/release boundaries.

## 1) Dashboard
- Today’s events
- Pending agreements (participants with upcoming event but missing signed docs)
- Recent sacrament releases
- Quick search (participant / email / phone / product_id)

## 2) Participants
- ✔️List + filters (active/inactive)
- ✔️Participant detail: contact info, agreements, releases, donations
- Actions:
	✔️create participant,
	deactivate,
	merge duplicates

## 3) Agreements
- Agreement templates (name, version, required_for, active)
- ✔️Participant agreements (status, evidence link, method)

## 4) Event Check-in
- Select event
- Check-in participant (verify signed agreements)
- If missing: send Documenso link, or mark “paper signed pending upload”

## 5) `Sacrament Release` (Gate)
- Input/scan: participant + product_id
- Quantity + unit
- “Validate lot” (from bridge or API)
- ✔️“Release” button (runs hard gate)
- Print receipt / QR (optional later)

## 6) Donations
- ✔️Manual entry (cash)
- List Givebutter imports (read-only)
- ✔️Participant donation history

