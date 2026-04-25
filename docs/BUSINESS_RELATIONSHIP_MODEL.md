# Architecture Note: Rooted Psyche, Dank Mushrooms, and Future Company Inventory Relationships

## Purpose

This note describes the current business and systems relationship between **Rooted Psyche** and **Dank Mushrooms**, and outlines how the model can evolve for future companies while preserving a practical path for both **SignatureGate** and **MushroomProcess**.

---

## 1) Current business relationship

At present, the relationship is functionally closer to this:

- Dank Mushrooms operates the facility and packaging workflow.
- Rooted Psyche uses that facility under a lease-like operational relationship.
- Products intended for Rooted Psyche are, in practice, treated differently from ordinary Dank Mushrooms customer fulfillment.
- In MushroomProcess today, some owner/custodian semantics are already partially represented through fields such as:
  - `regulated`
  - `label_company_prod`

Under the current workflow, packaging may cause a regulated product to become associated with Rooted Psyche via `label_company_prod`.

This means the current system already contains the beginnings of an ownership/custody distinction, even if it is not yet modeled as a formal inventory transfer system.

---

## 2) Current technical reality

In SignatureGate today, release inventory access has transitioned from coupled to facilitator identity to allowing facilitators access to storage locations definied in the MushroomProcess database and granted access by a SignatureGate document reviewer.  The name-based location system was workable for a simple one-facilitator/one-location model, but it did not map well to shared access or to future inventory ownership distinctions.

---

## 3) The key concepts that must remain separate

Long-term, the model should separate these concepts:

### A. Physical storage location
Where the product is physically sitting.

Examples:
- shelf
- room
- cooler
- vault
- Rooted Psyche holding area

### B. Inventory owner or custodian
Who operationally or legally controls the inventory at that point in time.

Examples:
- Dank Mushrooms
- Rooted Psyche
- future natural medicine organization

### C. Access authority
Who is allowed to view, reserve, allocate, release, or otherwise act on inventory in the system.

Examples:
- a facilitator
- a reviewer
- a company administrator

### D. Transfer / delivery / release event
The specific event that changes inventory state.

Examples:
- packaged
- allocated
- delivered
- released
- shipped
- retired
- consumed
- voided

These are not the same thing and should not be forced into one field.

---

## 4) Recommended near-term model for Rooted Psyche

For Rooted Psyche **right now**, the best model is:

- keep Airtable/MushroomProcess `products.storage_location` as the location key for now
- add SignatureGate-side access control so facilitators can access multiple storage locations
- utilize an explicit storage location definition when releasing product
- record the selected storage location on the release record

This gives Rooted Psyche a workable operational model without prematurely building a full Rooted Psyche inventory subsystem.

### Why this is the right immediate step

- minimal disruption to current Appsmith + n8n + Airtable flow
- solves shared access cleanly
- avoids duplicating the location catalog before necessary
- creates a better audit trail
- remains compatible with later inventory-transfer modeling

---

## 5) Recommended medium-term model

As MushroomProcess becomes the system of record and additional companies are onboarded, the model should evolve from location-driven access into **inventory ownership and allocation**.

### Suggested future entities

#### `organizations`
Examples:
- Dank Mushrooms
- Rooted Psyche
- future natural medicine company

#### `products`
The product or inventory unit itself.

Important fields may eventually include:
- `current_storage_location`
- `current_owner_org_id`
- `regulated`
- `label_company_prod`
- `inventory_status`

#### `product_allocations`
Represents product that is reserved or committed to a specific organization.

Possible fields:
- `product_id`
- `allocated_to_org_id`
- `allocated_by`
- `allocated_at`
- `status` (`reserved`, `picked`, `delivered`, `cancelled`)

#### `inventory_transfers`
Represents a formal custody/ownership movement.

Possible fields:
- `product_id`
- `from_org_id`
- `to_org_id`
- `transfer_type`
- `effective_at`
- `notes`

#### `organization_facilitators`
Maps facilitators to organizations or programs.

#### `facilitator_storage_location_access`
Continues to manage who can work with stock in a physical location.

---

## 6) Future scenario: Dank Mushrooms becomes a licensed grow facility

In that future state, Dank Mushrooms may maintain inventory in storage until another company takes delivery.

That changes the business meaning of the inventory model:

- inventory may remain physically stored at Dank Mushrooms
- inventory may still be owned/custodied by Dank Mushrooms while awaiting allocation or delivery
- Rooted Psyche or another company may have rights to request or receive it later
- physical location and ownership are no longer equivalent

### Implication

The durable system should not say:

- “this location belongs to facilitator X”
- or “this shelf belongs to Rooted Psyche”

Instead it should say:

- the product is stored here
- it is currently owned/custodied by this organization
- it may be allocated to another organization
- specific users are authorized to act on it

That model supports both the current Rooted Psyche relationship and future licensed delivery scenarios.

---

## 7) How Rooted Psyche fits into that future model

Rooted Psyche can be handled in one of two ways depending on the business event  ultimately defined.

### Option 1: Packaging implies ownership/custody transfer
If regulated product packaged for Rooted Psyche is truly treated as Rooted Psyche inventory at that moment, then:

- MushroomProcess should record an ownership/custody transition at packaging
- product becomes Rooted Psyche inventory even if still physically stored at Dank
- SignatureGate releases consume Rooted Psyche inventory

### Option 2: Packaging does not imply transfer
If Dank Mushrooms keeps inventory until a later delivery/allocation event, then:

- product remains Dank Mushrooms inventory after packaging
- product may be reserved/allocated for Rooted Psyche
- delivery/release later moves or consumes it

### Recommendation

Do not force this question into the storage-location design. Treat it as an inventory ownership/custody rule.

---

## 8) Implications for SignatureGate

### Rooted Psyche now
SignatureGate should manage:
- facilitator identity
- facilitator access to members
- facilitator access to allowed storage locations
- release issuance against allowed inventory locations
- release audit trail, including source location

### Future
SignatureGate may eventually also need:
- organization context
- organization-specific inventory visibility
- allocation/release permissions by organization
- delivery confirmation workflows

SignatureGate should remain primarily the operational interface for:
- member-facing agreements and releases
- controlled access to inventory allocations

It should not become the deep inventory system if MushroomProcess is fulfilling that role.

---

## 9) Implications for MushroomProcess

MushroomProcess is the better long-term home for:

- product lifecycle
- storage location tracking
- ownership/custody state
- allocation and delivery events
- regulated inventory state transitions
- company/customer delivery relationships

### Near-term role
MushroomProcess / Airtable remains the source of product location and availability.

### Long-term role
MushroomProcess should become the system of record for:
- inventory state
- owner/custodian organization
- allocation to customer organizations
- delivery / release / retirement events

SignatureGate can query or consume those results.

---

## 10) Recommended phased roadmap

### Phase 1: Rooted Psyche immediate improvement (COMPLETE)
- add facilitator access to multiple storage locations in SignatureGate
- use existing Airtable location names
- stop deriving location from facilitator name
- record the selected location on releases

### Phase 2: Improve Rooted Psyche inventory semantics
- decide whether packaging implies transfer to Rooted Psyche
- start storing more explicit owner/custodian state in MushroomProcess
- distinguish physical location from owner/custodian

### Phase 3: Multi-company support
- add `organizations`
- add allocation and transfer concepts
- allow products to remain at Dank Mushrooms while allocated to a downstream company
- manage company-specific release eligibility

### Phase 4: Full integrated model
- MushroomProcess becomes inventory system of record
- SignatureGate becomes the controlled operational interface for releases, agreements, and member-facing workflows

---

## 11) Bottom line

### For Rooted Psyche right now
The correct move is:
- implement facilitator access to multiple existing storage locations
- keep location names sourced from Airtable/MushroomProcess
- do not model facilitator ownership of locations

### For the future
The durable model should center on:
- **physical location**
- **inventory owner/custodian**
- **authorized access**
- **allocation / transfer / delivery events**

That provides a clean path from today’s Rooted Psyche lease-like workflow to a future where Dank Mushrooms operates as a licensed inventory holder serving multiple downstream organizations.
