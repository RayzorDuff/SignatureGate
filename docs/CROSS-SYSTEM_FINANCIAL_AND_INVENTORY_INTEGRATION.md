# Cross-System Financial and Inventory Integration Specification

**Primary repository:** SignatureGate  
**Related systems:** RootedOps / ERPNext, MushroomProcess, n8n, Givebutter  
**Status:** Draft v0.2  
**Supersedes:** Donation Processing Specification v0.1

## Purpose

Define the architectural boundary between operational applications and ERPNext for Rooted Psyche and related operations.

The initial use case was donation processing:

- Givebutter processes online donations and issues receipts.
- SignatureGate manages donor/member context, cash review, cash on hand, deposit preparation, and receipt tracking.
- ERPNext owns accounting, bank transactions, reconciliation, and financial reporting.

A second use case now establishes the same architectural pattern for purchased materials used by MushroomProcess:

- ERPNext manages vendors, purchasing, Purchase Receipts, accounting, inventory value, and warehouse-level stock.
- MushroomProcess manages cultivation-domain definitions, recipes, ingredient usage, operational traceability, and process consumption.
- MushroomProcess references ERP-originated purchased inventory rather than creating an independent purchasing ledger.

The objective is a reusable cross-system integration model rather than separate one-off integrations.

---

# Architectural Principle

## Operational applications own operational meaning; ERPNext owns financial meaning.

SignatureGate and MushroomProcess may maintain operational representations of money, inventory, or transactions when those representations are necessary to perform their domain workflows.

They should not independently recreate ERPNext's accounting or purchasing ledgers.

ERPNext is authoritative for:

- General ledger
- Bank accounts
- Supplier/vendor master data where accounting is involved
- Purchase transactions
- Purchase Receipts
- Accounts payable
- Inventory valuation
- Warehouse accounting
- Bank reconciliation
- Financial statements

Operational systems are authoritative for domain-specific context that ERPNext does not model well.

---

# Shared Integration Pattern

Both SignatureGate and MushroomProcess use the same general model:

```text
External / Physical Event
        |
        v
Operational Application
        |
        | domain review / selection / classification
        v
Confirmed Operational Event
        |
        | integration request
        v
RootedOps / ERPNext
        |
        | authoritative ERP document / accounting transaction
        v
ERP Identifier + Status
        |
        v
Operational Application
```

The operational application stores the ERP document identity and synchronization state.

The operational application does not duplicate ERPNext's ledger.

---

# System Responsibilities

## Givebutter

Responsible for:

- Online donation processing
- Donation forms and campaigns
- Recurring donations
- Venmo and supported payment methods
- Payment fraud controls
- Tax receipt generation for contributions recorded in Givebutter
- Donor-facing payment experience

Not authoritative for:

- Rooted Psyche membership
- Sacrament Release status
- Cash-on-hand operations
- Bank reconciliation
- General ledger

---

## SignatureGate

Authoritative for:

- Rooted Psyche people/member relationships
- Contribution/member linkage
- Contribution review
- Cash-on-hand operational state
- Deposit batch preparation
- Donation receipt tracking
- Audit history
- Facilitator/member context

Not authoritative for:

- Bank balances
- General ledger
- Final bank reconciliation

---

## MushroomProcess

Authoritative for:

- Mushroom cultivation operations
- Recipes and recipe composition
- Operational ingredient definitions
- Process-specific lots, runs, events, and products
- Ingredient consumption within cultivation workflows
- Traceability between received source material and its use in recipes/processes
- Remaining operational quantity when MushroomProcess is the system consuming that material

Not authoritative for:

- Supplier invoices
- Accounts payable
- Vendor payment
- General ledger
- Financial inventory valuation
- ERP warehouse accounting

---

## RootedOps / ERPNext

RootedOps provides custom integration services around ERPNext.

ERPNext is authoritative for:

- Chart of accounts
- Journal Entries and other accounting documents
- Banks and bank reconciliation
- Suppliers
- Purchase Orders where used
- Purchase Receipts
- Purchase Invoices
- Accounts payable
- ERP inventory items
- ERP warehouses
- Inventory valuation
- ERP batch/stock identities when used
- Financial reporting

RootedOps may provide stable integration endpoints so Appsmith applications do not depend directly on low-level ERPNext implementation details.

---

## n8n

Responsible for:

- Webhook transport
- Scheduled synchronization where appropriate
- Retry orchestration
- Notifications
- Mapping between external APIs when a synchronous RootedOps call is not appropriate

Business rules should remain in the owning application or RootedOps/ERPNext, not be hidden primarily inside n8n workflows.

---

# Integration Identity Requirements

Every cross-system object must have durable identifiers.

Operational tables that reference ERPNext should store, as appropriate:

- `erp_doctype`
- `erp_name`
- `erp_company`
- `erp_item_code`
- `erp_supplier`
- `erp_warehouse`
- `erp_batch_no`
- `erp_source_document_type`
- `erp_source_document_name`
- `erp_source_document_row`
- `erp_sync_status`
- `erp_synced_at`
- `erp_last_error`
- optional synchronization/version metadata

Exact fields may be normalized into integration tables rather than added to every operational record.

Cross-system references must use immutable or durable ERP identifiers rather than display labels alone.

---

# Idempotency

All write integrations must be idempotent.

An operational event must not create multiple ERP documents because of:

- user double-click
- Appsmith retry
- HTTP retry
- n8n retry
- timeout after ERPNext accepted the request
- browser refresh

Each integration request should carry a stable source key such as:

```text
signaturegate:deposit_batch:<uuid>
mushroomprocess:vendor_receipt_link:<uuid>
mushroomprocess:ingredient_consumption:<uuid>
```

RootedOps should detect an existing transaction for the source key and return the existing ERP document instead of creating another one.

---

# Synchronization Status

Operational records that create or depend on ERP activity should expose synchronization state.

Recommended states:

- `not_required`
- `pending`
- `synced`
- `failed`
- `superseded`

A failed integration must not silently leave the operational application appearing complete.

Error detail should be retained for administrative review.

---

# Audit Requirements

Cross-system integration must preserve:

- originating user
- originating system
- originating record
- timestamp
- action
- request/source key
- resulting ERP document
- synchronization result
- failure information
- later correction or reversal

Operational records should not be silently edited to erase previously synchronized history.

---

# Part I — Contribution and Cash Deposit Processing

## Contribution Lifecycle

```text
Pending Review
      |
      v
Reviewed
      |
      v
Cash on Hand
      |
      v
Assigned to Deposit Batch
      |
      v
Deposit Prepared
      |
      v
Deposit Confirmed
      |
      v
ERP Accounting Created
      |
      v
Bank Reconciled
```

An ignored contribution exits the active cash workflow but remains in history.

Examples of legitimate historical ignore reasons may include cash received before this workflow existed and no longer physically on hand because it was previously spent or otherwise dispositioned.

Going forward, ignored reviewed cash should be exceptional.

---

## Cash on Hand

Cash on Hand consists of cash contributions that:

- have been reviewed
- are not ignored
- have not already been assigned to a completed deposit
- are expected to physically exist

SignatureGate is authoritative for this operational cash queue.

This is not intended to replace ERPNext cash-account accounting if Rooted Psyche later decides to recognize cash financially at receipt time.

---

## Deposit Batch

A Deposit Batch represents one intended physical bank deposit.

Recommended fields:

- Deposit Batch ID
- Batch Number
- Created Date/Time
- Prepared By
- Verified By
- Intended Bank Account
- Expected Total
- Actual Total
- Deposit Date
- Deposit Slip Number/reference
- Notes
- Status
- ERP document type
- ERP document name
- ERP synchronization status
- ERP synchronization timestamp

Recommended statuses:

- Draft
- Prepared
- Deposited
- Reconciled
- Cancelled

The batch stores links to each underlying contribution.

---

## Deposit Tally / Slip

SignatureGate should produce a printable or mobile-friendly deposit tally showing at minimum:

- Deposit batch number
- Date
- Bank/account identifier sufficient for internal use
- Cash denomination tally if implemented
- Individual contribution amounts or summarized cash total
- Expected total
- Prepared by
- Verification field

A bank's actual deposit slip may still be completed separately if required by the financial institution.

---

## Deposit Confirmation

After the physical deposit is made, an authorized user records:

- actual deposited amount
- deposit date
- bank reference/deposit slip reference
- discrepancy explanation when actual differs from expected

Only after confirmation should the ERP integration run under the initial design.

---

## ERP Accounting for Deposits

The initial conceptual accounting event is:

```text
Debit: Bank / Checking
Credit: Contribution Revenue
```

The final ERP document type and account mapping should be implemented in RootedOps and may evolve as Rooted Psyche's accounting policy matures.

The important architectural rule is that SignatureGate submits a business event and ERPNext determines the authoritative accounting document.

SignatureGate stores the resulting ERP document identity.

---

## Givebutter Receipts

Givebutter remains the preferred receipt engine for contributions recorded there, including eligible manually entered/offline donations.

SignatureGate tracks receipt metadata rather than rebuilding Givebutter's mature receipt system unless a later requirement makes native receipt generation necessary.

Possible metadata:

- provider
- provider transaction ID
- receipt ID
- receipt sent timestamp
- receipt status
- receipt URL/reference where supported

---

# Part II — Purchased Ingredient and Vendor Inventory Integration

## Background

MushroomProcess issue #79 expands recipes beyond a single free-text ingredient field.

The issue describes a future model in which:

- recipe ingredients become defined entities
- ingredients can identify specific amounts
- ingredients can identify vendors/sources
- vendor ingredients can be received into inventory
- received containers have total weight or volume
- recipe use can decrement received ingredient containers
- remaining quantity can inform purchasing decisions

This introduces a direct boundary with ERPNext because vendor purchasing and receipt are already accounting and inventory functions.

---

# ERPNext Purchase-Side Authority

ERPNext should remain authoritative for the commercial receipt of purchased materials.

A normal purchased ingredient may originate in ERPNext as:

```text
Supplier
   |
   v
Purchase Order (optional)
   |
   v
Purchase Receipt
   |
   +--> ERP Item
   +--> Quantity / UOM
   +--> Warehouse
   +--> Batch identity where applicable
   +--> Supplier
   +--> Valuation / accounting impact
   |
   v
Purchase Invoice / Accounts Payable
```

MushroomProcess should not independently implement:

- supplier invoices
- payable balances
- vendor payment status
- financial inventory valuation
- duplicate Purchase Receipt functionality

---

# MushroomProcess Operational Ingredient Model

MushroomProcess should maintain its own domain representation where required for recipe and cultivation use.

Recommended conceptual entities:

## Ingredient

Defines the thing used in a recipe.

Possible fields:

- Ingredient ID
- Name
- Description
- Default UOM
- Category
- Active
- ERP Item Code link, when applicable
- Default supplier/vendor reference, if useful
- Notes

A recipe should reference Ingredient records rather than rely only on free text.

---

## Recipe Ingredient

Defines how an Ingredient participates in a recipe.

Possible fields:

- Recipe ID
- Ingredient ID
- Required amount
- UOM
- optional percentage or ratio
- sequence/order
- notes
- substitution rules if ever supported

The vendor should generally **not** be hard-coded as part of the recipe unless the vendor/source is materially part of the formulation.

The recipe defines *what is required*.

Received inventory defines *which physical source supplied it*.

---

## Received Ingredient Inventory

Represents physical purchased ingredient stock that MushroomProcess can consume operationally.

A received-inventory record should link back to the authoritative ERP receipt identity.

Possible fields:

- MushroomProcess received inventory ID
- Ingredient ID
- ERP Item Code
- ERP Purchase Receipt
- ERP Purchase Receipt Item row or equivalent durable source reference
- ERP Supplier
- ERP Warehouse
- ERP Batch No. when applicable
- received quantity
- received UOM
- operational remaining quantity
- manufacturer / vendor lot number when available
- received date
- expiration/best-by date where relevant
- status
- synchronization metadata

This record is a domain projection/reference to ERP-originated stock, not a second financial receipt.

---

# Receipt Synchronization Direction

The preferred direction is:

```text
Vendor Purchase
      |
      v
ERPNext Purchase Receipt
      |
      | synchronization / lookup
      v
MushroomProcess Received Ingredient Inventory
      |
      v
Recipe / Process Consumption
```

ERPNext establishes that the purchased material arrived.

MushroomProcess establishes how that material is actually used in mushroom cultivation.

---

# Inventory Consumption

Issue #79 anticipates decrementing received ingredient containers as recipes are used.

That creates two potentially different inventory concepts:

## Financial / ERP stock

ERPNext answers questions such as:

- What purchased stock does the company own?
- What is its valuation?
- In what ERP warehouse is it held?
- What accounting entries resulted from receipt or consumption?

## Operational recipe inventory

MushroomProcess answers questions such as:

- Which exact bag/container/source lot was used?
- How much remains available for recipes?
- Which recipe consumed it?
- Which production run or lot consumed it?
- What source/vendor lot is traceable into downstream product?

These should be linked but should not be treated as automatically identical without an explicit synchronization design.

---

# Consumption Synchronization Decision

A design decision remains open regarding whether recipe consumption in MushroomProcess should also create ERPNext stock consumption transactions.

Possible models:

## Model A — Operational-only decrement

MushroomProcess decrements its own received ingredient balance.

ERPNext purchasing/accounting inventory is reconciled periodically or treated at a broader expense level.

Advantages:

- simpler
- avoids coupling every recipe operation to ERPNext
- preserves detailed MushroomProcess traceability

Disadvantages:

- ERP stock quantity may not represent real-time recipe usage

## Model B — Real-time ERP consumption

Each confirmed MushroomProcess consumption event creates an ERPNext Stock Entry or other appropriate stock transaction through RootedOps.

Advantages:

- ERP stock stays synchronized
- inventory valuation reflects production consumption

Disadvantages:

- tighter coupling
- greater transaction volume
- unit-of-measure and reversal handling become more important
- operational corrections must safely reverse/update ERP stock

## Initial recommendation

Design the schema and integration IDs so **Model B remains possible**, but do not require it as part of issue #79.

Issue #79 should focus on recipe creation and operational ingredient linkage.

A separate MushroomProcess/ERP integration issue should establish receipt synchronization first.

Consumption posting to ERPNext should be a later explicit issue after receipt identity and UOM mapping are stable.

---

# Unit of Measure Requirements

Vendor receipts and recipe consumption may use different units.

Examples:

- 50 lb bag purchased
- recipe consumes grams
- liquid purchased by gallon
- recipe consumes milliliters

Cross-system design must define:

- ERP UOM
- MushroomProcess canonical UOM
- conversion factor
- conversion precision
- rounding rules

Conversions must be deterministic and auditable.

Do not decrement purchased inventory using display-formatted values.

---

# Lot / Batch Traceability

Where the vendor provides a manufacturer lot number or ERPNext uses a Batch:

MushroomProcess should preserve that identity into operational consumption.

Traceability goal:

```text
Supplier
  |
ERP Purchase Receipt
  |
ERP Batch / Vendor Lot
  |
MP Received Ingredient Inventory
  |
Recipe Consumption
  |
Production Run / Lot
  |
Finished Product
```

This permits later investigation of supplier quality, contamination, recalls, and cost or sourcing questions.

---

# Supplier / Vendor Ownership

ERPNext should be authoritative for supplier identities used in purchasing.

MushroomProcess may cache/display supplier information but should preferably store the ERP Supplier identifier rather than independently creating a divergent vendor master.

If MushroomProcess needs cultivation-specific supplier notes, those should be stored as operational metadata associated with the ERP Supplier identity.

---

# Appsmith Integration Pattern

SignatureGate and MushroomProcess should use the same integration principles.

Appsmith should call stable application/backend endpoints rather than embedding substantial ERPNext business logic in widget JavaScript.

Preferred:

```text
Appsmith
   |
   v
Application SQL / JS business action
   |
   v
RootedOps integration service
   |
   v
ERPNext
```

n8n may be used when asynchronous webhook orchestration or external SaaS connectivity is useful.

For actions that need immediate transactional confirmation, direct RootedOps/API integration is generally preferable to hiding state-changing business logic in n8n.

---

# RootedOps Integration Responsibilities

RootedOps should evolve toward a small integration service layer supporting business operations from multiple applications.

Candidate service families:

## Contributions

- create/resolve deposit accounting document
- query deposit synchronization status
- reverse/correct deposit accounting transaction if policy permits

## Purchasing / Inventory

- query ERP Items available for MushroomProcess linkage
- query Suppliers
- query submitted Purchase Receipts
- query receipt line details
- query Batch / warehouse identities
- expose received inventory suitable for import/linking
- optionally create ERP stock consumption transactions in a later phase
- return stable ERP document references

This avoids separate ERPNext integration logic being reinvented independently in SignatureGate and MushroomProcess.

---

# Security

Operational applications should not receive unrestricted ERPNext credentials.

Integration credentials should be scoped to required operations where feasible.

State-changing ERP calls must identify:

- application
- application user
- source record
- source key

Sensitive ERP accounting operations should remain constrained to authorized application workflows.

---

# Failure Handling

A cross-system failure must be visible.

Example:

```text
Deposit confirmed
ERP sync failed
```

should produce a visible `failed` ERP synchronization state rather than reverting the deposit to an apparently unconfirmed state.

Likewise:

```text
ERP Purchase Receipt exists
MP import/link failed
```

must not duplicate the Purchase Receipt.

Retry should operate against the same source identity.

---

# Reconciliation

Cross-system reconciliation reports should eventually identify:

## SignatureGate / ERPNext

- confirmed deposits without ERP documents
- ERP deposit documents without expected SignatureGate source references
- amount mismatches
- failed synchronization

## MushroomProcess / ERPNext

- ERP Purchase Receipt lines expected to be available to MushroomProcess but not linked
- MushroomProcess received inventory with missing ERP source documents
- quantity/UOM mapping discrepancies
- duplicate ERP receipt links
- optional future differences between ERP stock and operational remaining quantities

---

# Immediate Implementation Issues

## SignatureGate

1. Cash Deposit Management
2. Contribution Lifecycle and Cash-on-Hand State
3. ERPNext Deposit Integration
4. Receipt Metadata Tracking
5. Givebutter Synchronization

## MushroomProcess

1. #79 — Recipe creation/modification and normalized ingredient definitions
2. ERPNext Vendor Inventory / Purchase Receipt Integration
3. Vendor-Received Ingredient Inventory
4. UOM Mapping and Conversion
5. Future: Recipe Consumption -> ERPNext Stock Consumption
6. Future: Procurement/Reorder visibility from remaining operational ingredient inventory

## RootedOps

1. Shared ERP integration service contract
2. Deposit accounting endpoint
3. ERP Purchase Receipt / Supplier / Item read endpoints for MushroomProcess
4. Idempotency registry or equivalent durable source-key handling
5. Future stock-consumption endpoint

---

# Open Design Decisions

1. Which ERPNext document should represent a confirmed Rooted Psyche cash deposit?
2. Should cash be recognized financially at receipt time or only at bank deposit time?
3. Should MushroomProcess ingredient consumption post real-time Stock Entries to ERPNext?
4. Which system owns canonical UOM conversion definitions?
5. Should ERP Purchase Receipts be pushed to MushroomProcess or pulled/imported from the Appsmith interface?
6. Should each physical ingredient container be separately represented when multiple containers exist on one Purchase Receipt line?
7. How should partial containers and vendor/manufacturer lot numbers be represented?
8. Should reorder recommendations be calculated in MushroomProcess, ERPNext, or both?
9. Which RootedOps APIs should be generic reusable ERP endpoints versus domain-specific commands?

---

# Guiding Rule

When deciding where a new feature belongs:

> If the question is "what happened operationally and what does it mean to this domain?", the operational application owns it.

> If the question is "what did the organization buy, own, owe, receive financially, deposit, expense, or report?", ERPNext owns it.

The systems should reference each other through durable identifiers rather than duplicate each other's authoritative ledgers.
