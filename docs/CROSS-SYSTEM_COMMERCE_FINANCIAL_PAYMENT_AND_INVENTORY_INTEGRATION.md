# Cross-System Commerce, Financial, Payment, and Inventory Integration Specification

**Primary repository:** SignatureGate\
**Related systems:** RootedOps / ERPNext, MushroomProcess, n8n,
Givebutter, ecommerce providers, payment processors\
**Status:** Draft v0.3\
**Supersedes:** Cross-System Financial and Inventory Integration
Specification v0.2

## Purpose

Define the architectural boundaries among operational applications,
ERPNext, sales channels, payment processors, and external financial
services used by Rooted Psyche and related operations.

The specification began with donation processing and expanded to ERPNext
purchasing and MushroomProcess ingredient inventory. This revision adds
commerce and payment processing:

-   ERPNext becomes authoritative for commercial sales documents and
    accounting regardless of sales channel.
-   Ecommerce systems such as Ecwid or a future WooCommerce
    implementation are sales channels rather than authoritative
    commercial ledgers.
-   Payment processors such as Moov or legacy Clover are payment
    channels rather than authoritative sales ledgers.
-   Moov may also expose a point-of-sale catalog and Tap to Pay sales
    channel.
-   MushroomProcess remains authoritative for production, lot
    traceability, sellable operational inventory, and fulfillment.
-   Product/catalog synchronization is provider-neutral so ecommerce and
    payment-facing catalogs can be replaced without redefining the
    underlying product.

The objective is a reusable cross-system integration model rather than
separate one-off integrations.

# Architectural Principles

## Operational applications own operational meaning; ERPNext owns financial meaning

SignatureGate and MushroomProcess may maintain operational
representations of money, inventory, or transactions when necessary for
their domain workflows. They should not independently recreate ERPNext
accounting, purchasing, receivables, or payment ledgers.

ERPNext is authoritative for the general ledger, bank accounts,
suppliers, purchasing, Purchase Receipts, accounts payable, inventory
valuation, warehouse accounting, commercial sales documents, accounts
receivable, Payment Entries, bank reconciliation, and financial
statements.

## ERPNext owns commercial transactions; external platforms are channels

ERPNext should be authoritative for commercial documents representing
the sale of goods or services regardless of where the transaction
originated or how payment was collected.

ERPNext should own, as applicable:

-   Customer
-   Item
-   Item Price
-   Sales Order
-   Sales Invoice
-   Payment Entry
-   tax/accounting treatment
-   accounts receivable
-   refund/reversal accounting

An ecommerce provider does not become the authoritative order ledger
merely because the customer used that storefront. A payment processor
does not become the authoritative sales ledger merely because it
collected payment.

## Sales channel and payment processor are separate concepts

Examples:

``` text
sales_channel = ecwid
payment_processor = moov
```

``` text
sales_channel = moov_pos
payment_processor = moov
```

``` text
sales_channel = ecwid
payment_processor = clover
```

``` text
sales_channel = appsmith
payment_processor = cash
```

The data model must not infer payment processor from sales channel or
vice versa.

## Product identity has multiple authoritative dimensions

### ERPNext Item

ERPNext owns commercial/accounting identity: item code, sales UOM, Item
Price, tax/accounting classification, and stock/accounting configuration
where applicable.

### MushroomProcess operational product

MushroomProcess owns item/strain relationships, package configuration,
production lots, physical/sellable quantity, production lineage,
cultivation-specific availability, and fulfillment state.

### External channel listing

An ecommerce or POS provider owns only its channel-specific
representation: external product ID, external SKU, title/description,
image, options/add-ons, visibility, presentation, and intentional
channel-specific price overrides.

# Target Architecture

``` text
                         SALES CHANNELS

          Ecommerce                          Point of Sale
   Ecwid / future WooCommerce                 Moov Tap
              |                                  |
              +---------------+------------------+
                              |
                              v
                      RootedOps / ERPNext
                      -------------------
                      Customer
                      Item / Item Price
                      Sales Order
                      Sales Invoice
                      Payment Entry
                      Purchase Receipt
                      Accounting
                              |
                +-------------+-------------+
                |                           |
                v                           v
        MushroomProcess               SignatureGate
        ---------------               -------------
        Production                    Contributions
        Sellable inventory            Members/donors
        Lot/product identity           Cash operations
        Fulfillment                    Deposit batches
        Traceability
```

Payment processing is orthogonal:

``` text
                    PAYMENT PROCESSORS

                  Moov     Clover (legacy)
                    \       /
                     \     /
                      \   /
                       v v
                  ERPNext Payment
                     identity
```

This permits Ecwid+Moov, future WooCommerce+Moov, Moov Tap to Pay+Moov,
manual/Appsmith+cash, and legacy Ecwid+Clover without changing the
authoritative ERP commercial model.

# System Responsibilities

## Givebutter

Owns online donation processing, campaigns, recurring donations,
supported payment methods, fraud controls, tax receipt generation for
contributions recorded there, and donor-facing payment experience. It
does not own membership, cash-on-hand operations, bank reconciliation,
or the general ledger.

## SignatureGate

Owns Rooted Psyche people/member relationships, contribution/member
linkage, contribution review, cash-on-hand operational state, deposit
preparation, receipt tracking, audit history, and facilitator/member
context. It does not own bank balances, the general ledger, or final
bank reconciliation.

## MushroomProcess

Owns cultivation operations, recipes, ingredient definitions and
consumption, lots/runs/events/products, source-material traceability,
sellable operational quantity, production lineage, fulfillment state,
and operational inventory consumption.

It does not own supplier invoices, accounts payable, vendor payment, the
general ledger, financial inventory valuation, authoritative Sales
Invoices, or Payment Entries.

## RootedOps / ERPNext

RootedOps provides custom integration services around ERPNext.

ERPNext owns chart of accounts, Journal Entries, banks, Suppliers,
Purchase Orders where used, Purchase Receipts, Purchase Invoices,
accounts payable, ERP Items, warehouses, inventory valuation, ERP
batch/stock identities, Customers, commercial Items and Item Prices,
Sales Orders where used, Sales Invoices, Payment Entries, accounts
receivable, and financial reporting.

RootedOps should provide stable integration endpoints so Appsmith
applications and n8n workflows do not depend directly on low-level
ERPNext implementation details.

## Ecommerce Providers

Current: Ecwid. Planned/evaluated: WooCommerce/WooV or another future
storefront.

Ecommerce providers own storefront presentation, cart/checkout
experience, customer-facing product discovery, and channel-specific
state. They do not own accounting, final commercial invoice identity,
the payment ledger, production inventory, or cross-channel commercial
history.

## Moov

Moov is expected to serve as both a payment processor and, for Tap to
Pay, a POS sales channel with a product catalog where supported. Moov
payment identity and Moov catalog/sales-channel identity must remain
separate. Moov must not become the authoritative inventory or commercial
ledger.

## Clover

Clover is a legacy payment processor/POS integration retained during
migration. Existing Clover-specific data should be migrated or projected
into provider-neutral payment fields before legacy behavior is retired.

## n8n

n8n owns webhook transport, scheduled synchronization, retries,
notifications, and external API orchestration where useful. Core
business rules should remain in the owning application or
RootedOps/ERPNext rather than being hidden primarily inside workflows.

# Cross-System Identity

Operational tables referencing ERPNext should store, as appropriate:

-   `erp_doctype`
-   `erp_name`
-   `erp_company`
-   `erp_item_code`
-   `erp_supplier`
-   `erp_warehouse`
-   `erp_batch_no`
-   `erp_source_document_type`
-   `erp_source_document_name`
-   `erp_source_document_row`
-   `erp_sync_status`
-   `erp_synced_at`
-   `erp_last_error`

Exact fields may be normalized into integration tables.

Provider-neutral external mappings should use concepts such as:

-   `provider`
-   `site_key`
-   `external_product_id`
-   `external_sku`
-   `external_order_id`
-   `external_payment_id`
-   `external_customer_id`
-   `external_status`
-   `last_synced_at`
-   `last_error`

New integrations should not require legacy `ecwid_*` or `clover_*`
names.

# Idempotency

All write integrations must be idempotent. Retries, webhook redelivery,
browser refresh, n8n retries, or timeouts must not create duplicate ERP
documents.

Example stable source keys:

``` text
signaturegate:deposit_batch:<uuid>
mushroomprocess:vendor_receipt_link:<uuid>
mushroomprocess:ingredient_consumption:<uuid>
ecwid:order:<external-id>
moov:payment:<external-id>
moov:pos-sale:<external-id>
```

RootedOps should detect an existing source key and return the existing
ERP document.

A shared registry should be considered with source system/type/ID/key,
ERP DocType/name, status, timestamps, and last error.

# Synchronization and Audit

Recommended synchronization states:

-   `not_required`
-   `pending`
-   `synced`
-   `failed`
-   `superseded`

Failures must remain visible and retryable.

Cross-system audit must preserve originating user/system/record,
timestamp, action, source key, resulting ERP document, synchronization
result, failure information, and later correction/reversal.

# Part I --- Contribution and Cash Deposit Processing

The contribution lifecycle remains:

``` text
Pending Review
 -> Reviewed
 -> Cash on Hand
 -> Assigned to Deposit Batch
 -> Deposit Prepared
 -> Deposit Confirmed
 -> ERP Accounting Created
 -> Bank Reconciled
```

SignatureGate owns the operational cash queue and deposit batch. After
physical deposit confirmation, SignatureGate sends an idempotent
business event to RootedOps.

The initial conceptual accounting event remains:

``` text
Debit: Bank / Checking
Credit: Contribution Revenue
```

The final ERP document type/account mapping belongs in
RootedOps/ERPNext.

Givebutter remains the preferred receipt engine for contributions
recorded there; SignatureGate tracks provider transaction/receipt
identity and status.

# Part II --- Purchased Ingredient and Vendor Inventory Integration

MushroomProcess issue #79 normalizes recipe/ingredient definitions.
ERPNext remains authoritative for the commercial receipt:

``` text
Supplier
 -> Purchase Order (optional)
 -> Purchase Receipt
    -> ERP Item
    -> Quantity / UOM
    -> Warehouse
    -> Batch where applicable
    -> Supplier
    -> Valuation/accounting
 -> Purchase Invoice / Accounts Payable
```

MushroomProcess should maintain Ingredient, Recipe Ingredient, and
Received Ingredient Inventory domain records as needed, with received
inventory linked durably to ERP Purchase Receipt identity.

Preferred direction:

``` text
Vendor Purchase
 -> ERPNext Purchase Receipt
 -> MushroomProcess Received Ingredient Inventory
 -> Recipe / Process Consumption
```

ERPNext answers financial/warehouse stock questions. MushroomProcess
answers exact container/source-lot, recipe consumption, production
lineage, and operational remaining-quantity questions.

Real-time MushroomProcess consumption posting to ERPNext should remain
possible but should be deferred until receipt identity and UOM mapping
are stable.

Cross-system UOM conversions must be deterministic, precise, and
auditable.

# Part III --- Commercial Catalog and Product Synchronization

Conceptually:

``` text
MushroomProcess operational definition
             +
        ERPNext Item
             |
             v
    Commercial Catalog Mapping
             |
       +-----+------+------+
       |            |      |
     Ecwid       future   Moov POS
                 store
```

ERPNext answers what commercial Item this is and how it is
priced/accounted for. MushroomProcess answers whether it is
operationally sellable, how much exists, which lots/packages are
available, and what production identity supports fulfillment. External
channels answer how the product is presented there.

The provider-neutral mapping contemplated by MushroomProcess #80 should
be reused rather than replaced.

Moov catalog synchronization may include title, description, image, base
price, add-on/modifier groups, option price adjustments, and active
state where supported. Stock quantity, automatic decrement, SKU/barcode,
categories, and other inventory semantics must be verified against the
bank/Moov API before being treated as supported.

# Part IV --- Sales Orders, Invoices, Fulfillment, and Payments

A sale may originate from Ecwid, Moov POS/Tap to Pay, future
WooCommerce/WooV, Appsmith/manual entry, or another future channel.

A confirmed external sale should create or resolve the appropriate
ERPNext commercial document through RootedOps:

``` text
External order / POS sale
 -> normalize customer + line items
 -> RootedOps
    -> resolve/create Customer
    -> resolve ERP Items
    -> create/resolve Sales Order when needed
    -> create/resolve Sales Invoice
 -> return durable ERP identities
```

Sales Order should be used where reservation/fulfillment before
completion requires it. Immediate paid POS transactions may be
adequately represented by Sales Invoice plus Payment Entry.

Payment processors should be generic: Moov, Clover, cash, check, bank
transfer, or future processors.

Recommended normalized payment data includes processor, processor
transaction ID/status, amount, currency, timestamp, reconciliation
status/confidence, ERP Payment Entry, sync status, and error/provider
metadata.

## Target Moov ecommerce flow

``` text
Ecwid checkout
 -> custom Moov payment integration
 -> Moov payment
 -> Moov webhook
 -> RootedOps / ERPNext
    -> Sales Invoice
    -> Payment Entry
 -> Ecwid paid/order state updated
 -> MushroomProcess fulfillment
```

## Target Moov Tap to Pay flow

``` text
Moov POS sale
 -> Moov payment event
 -> RootedOps / ERPNext
    -> Sales Invoice
    -> Payment Entry
 -> MushroomProcess fulfillment / inventory event
```

## Clover migration

Clover remains supported during transition. Historical identity must be
preserved. Clover reconciliation should be projected into generic
payment fields. Appsmith Fulfillment should eventually display Clover
and Moov consistently.

## MushroomProcess Fulfillment

Fulfillment should operate on normalized order/payment identity:

``` text
Order
  sales_channel
  external_order_id
  erp_sales_order
  erp_sales_invoice

Payment
  processor
  processor_payment_id
  amount
  status
  erp_payment_entry

Fulfillment
  MushroomProcess fulfillment state
```

# Part V --- RootedOps Integration Service

RootedOps should evolve toward a shared integration service around
ERPNext.

Service families should include:

-   shared source-key/idempotency and audit handling
-   contributions/deposit accounting
-   purchasing/Purchase Receipt/Supplier/Item reads
-   commercial catalog/Item/Item Price reads and mapping
-   Customer/Sales Order/Sales Invoice creation/resolution
-   Payment Entry creation/resolution and reconciliation
-   future ERP stock-consumption posting

# Appsmith Integration Pattern

Preferred:

``` text
Appsmith
 -> Application SQL / JS business action
 -> RootedOps integration service
 -> ERPNext
```

n8n remains appropriate for asynchronous webhook/SaaS orchestration.
Immediate state-changing business operations should not be hidden
primarily inside n8n when a stable RootedOps command is more
appropriate.

# Security

Operational applications should not receive unrestricted ERPNext
credentials. State-changing calls must identify application, application
user, source record, and source key. External webhook integrations must
validate authenticity according to provider capabilities.

# Failure Handling and Reconciliation

A downstream failure must not erase the original confirmed event.

Examples:

``` text
Deposit confirmed
ERP sync failed
```

``` text
Moov payment completed
ERP Payment Entry failed
```

``` text
ERP Purchase Receipt exists
MushroomProcess import/link failed
```

Retry must operate against the same source identity.

Reconciliation should eventually cover SignatureGate/ERP deposits,
MushroomProcess/ERP purchasing, sales-channel/ERP invoices,
processor/ERP payments, and external catalog mappings.

# Open Design Decisions

1.  Which ERPNext document should represent a confirmed Rooted Psyche
    cash deposit?
2.  Should cash be recognized financially at receipt time or bank
    deposit time?
3.  Should MushroomProcess ingredient consumption post real-time Stock
    Entries?
4.  Which system owns canonical UOM conversions?
5.  Should Purchase Receipts be pushed to MushroomProcess or
    pulled/imported?
6.  How should physical containers and vendor lots be represented?
7.  Where should reorder recommendations be calculated?
8.  Which RootedOps APIs should be generic versus domain-specific?
9.  When should an external sale create Sales Order versus direct Sales
    Invoice?
10. At what point in ecommerce checkout should Sales Invoice be created?
11. How should failed/abandoned payment attempts avoid misleading
    receivables?
12. Which customer attributes are canonical in ERPNext?
13. How should anonymous/walk-up POS customers be represented?
14. Which tax calculation system is authoritative for each channel?
15. Which Moov catalog capabilities are actually exposed by the
    bank-provided application/API?
16. Should channel-specific price overrides be allowed and where are
    they stored?
17. How should refunds, partial refunds, chargebacks, and reversals
    propagate?
18. How long should legacy Clover-specific fields/workflows remain?
19. Should catalog synchronization originate directly from RootedOps or
    through n8n adapters?

# Recommended Implementation Sequence

## Phase 1 --- Adopt the shared architecture

1.  Check this v0.3 specification into SignatureGate as the cross-system
    architectural source of truth.
2.  Cross-reference it from implementation issues in all three
    repositories.
3.  Preserve existing working integrations while introducing
    provider-neutral concepts.

## Phase 2 --- RootedOps integration foundation

4.  Implement the shared RootedOps ERP integration service contract.
5.  Implement durable source-key/idempotency handling.
6.  Standardize synchronization status, structured errors, audit
    metadata, and ERP references.
7.  Use scoped RootedOps operations rather than unrestricted ERPNext
    credentials.

## Phase 3 --- ERP commercial catalog foundation

8.  Establish ERPNext Item and Item Price as durable commercial product
    identity.
9.  Map MushroomProcess operational products to ERP Items without
    transferring production authority.
10. Extend the provider-neutral mapping contemplated by MushroomProcess
    #80.
11. Preserve Ecwid mappings while allowing future Moov POS and
    WooCommerce mappings.

## Phase 4 --- Purchase-side ERP/MushroomProcess integration

12. Continue MushroomProcess #79 normalized recipe/ingredient work.
13. Implement MushroomProcess #84 ERPNext Purchase Receipt/vendor
    inventory linkage.
14. Establish UOM conversion and durable receipt-line identity.
15. Defer real-time recipe-consumption posting until receipt/UOM
    behavior is stable.

## Phase 5 --- ERP sales-document integration

16. Implement RootedOps Customer, Sales Order, and Sales Invoice
    operations.
17. Define when Sales Order is required versus direct Sales Invoice.
18. Introduce normalized sales-channel identity.
19. Allow external sales to resolve to ERP commercial documents
    independently of Ecwid.

## Phase 6 --- Provider-neutral MushroomProcess Fulfillment

20. Refactor Fulfillment so order source, payment processor, ERP invoice
    identity, and fulfillment state are independent.
21. Project legacy Ecwid/Clover data into the normalized model.
22. Preserve current Ecwid/Clover behavior during migration.
23. Validate fulfillment against legacy and normalized records.

## Phase 7 --- Moov payment processing

24. Implement Moov payment/transfer integration and webhook handling.
25. Create/resolve ERPNext Payment Entries from confirmed Moov payments.
26. Implement idempotent reconciliation and explicit refund/reversal
    behavior.
27. Update Fulfillment to display Moov and Clover through the same
    normalized model.

## Phase 8 --- Moov catalog / Tap to Pay

28. Verify bank/Moov API capabilities for catalog synchronization,
    options, images, stock, SKU/barcode, categories, and availability.
29. Implement ERP/MushroomProcess-to-Moov catalog synchronization for
    supported fields.
30. Treat Moov POS as a sales channel and Moov as a processor
    independently.
31. Implement Moov POS-originated ERP Sales Invoice/Payment Entry
    creation.
32. Feed Moov POS sales into MushroomProcess fulfillment/inventory where
    applicable.

## Phase 9 --- Ecwid payment cutover

33. Implement Moov as the Ecwid payment processor using the supported
    custom-payment model.
34. Route Ecwid orders into the normalized ERP sales-document flow.
35. Confirm Moov payment by webhook and create/resolve ERP Payment
    Entry.
36. Update Ecwid payment/order state from confirmed integration results.
37. Perform controlled validation before disabling Clover processing.

## Phase 10 --- Ecommerce platform replacement

38. Evaluate/implement WooCommerce/WooV or another storefront as a
    replaceable channel adapter.
39. Reuse ERP Items, provider-neutral mappings, Moov payment
    integration, and MushroomProcess fulfillment.
40. Migrate channel listings/order intake without changing ERPNext
    commercial authority.
41. Retire Ecwid only after catalog, checkout, order, payment, tax,
    fulfillment, and reconciliation parity.

## Phase 11 --- Cleanup and advanced synchronization

42. Retire Clover-specific workflows after historical reconciliation and
    production validation.
43. Retire obsolete Ecwid-specific schema fields after provider-neutral
    mappings are verified.
44. Add cross-system reconciliation reporting.
45. Revisit real-time MushroomProcess consumption -\> ERPNext stock
    transactions.
46. Add procurement/reorder visibility using linked operational and ERP
    inventory.

# Immediate Issue Backlog

## SignatureGate

-   Existing #17 --- Cash Deposit Management
-   New --- ERPNext Contribution and Deposit Integration

## RootedOps

-   New --- Cross-System ERP Integration Service and Idempotency
    Registry
-   New --- ERPNext Commercial Catalog and External Channel Mapping
    Service
-   New --- ERPNext Sales Order / Sales Invoice Integration for External
    Sales Channels
-   New --- Moov Payment Processor Integration and Payment Entry
    Reconciliation

## MushroomProcess

-   Existing #79 --- normalized recipe/ingredient work
-   Existing #80 --- Ecommerce Catalog Mapping UI
-   Existing #84 --- ERPNext purchasing / Purchase Receipt integration
-   New --- Abstract Fulfillment Orders and Payment Reconciliation from
    Ecwid/Clover
-   New --- Synchronize ERP Commercial Catalog to Ecommerce and Moov POS
    Catalogs

# Guiding Rules

> If the question is "what happened operationally and what does it mean
> to this domain?", the operational application owns it.

> If the question is "what did the organization buy, own, owe, receive
> financially, sell, invoice, collect, deposit, expense, or report?",
> ERPNext owns it.

> If the question is "where did the customer place the order?", that is
> sales-channel identity.

> If the question is "how was money collected?", that is
> payment-processor identity.

> If the question is "how is the product presented on this storefront or
> POS?", that is channel-specific catalog identity.

Systems should reference each other through durable identifiers rather
than duplicate authoritative ledgers.
