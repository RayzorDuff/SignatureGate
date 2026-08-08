# Donation Processing Specification

**Project:** SignatureGate  
**Status:** Draft v0.1

## Purpose

Define the authoritative workflow for all monetary and non-monetary contributions received by Rooted Psyche.

This specification establishes:

- System responsibilities
- Data ownership
- Accounting integration
- Audit requirements
- Receipt generation
- Future fundraising compatibility

---

# Design Goals

1. **Single donor record**
   - One donor exists exactly once.

2. **Single contribution record**
   - Every contribution exists exactly once regardless of source:
     - Givebutter
     - Cash
     - Check
     - Venmo
     - ACH
     - Stock
     - In-kind
     - Cryptocurrency (future)

3. **Single accounting record**
   - Every contribution produces one accounting event.
   - ERPNext is the accounting system of record.

4. **Single tax receipt**
   - Every tax-deductible contribution has exactly one receipt.

5. **Complete audit trail**
   - Every state transition is recorded.
   - No silent edits.

---

# System Responsibilities

## Givebutter

Responsible for:

- Payment processing
- Online donation forms
- Campaigns
- Recurring donations
- Fraud prevention
- Tax receipt generation
- Donor payment experience

Not responsible for:

- Accounting
- Member management
- Cash management
- Bank reconciliation

---

## SignatureGate

Authoritative for:

- Contributors
- Member relationships
- Contribution history
- Contribution review
- Cash on hand
- Deposit preparation
- Receipt tracking
- Audit log

Not authoritative for:

- Bank balances
- General ledger

---

## ERPNext

Authoritative for:

- General ledger
- Journal entries
- Bank accounts
- Financial reporting
- Reconciliation
- Budgeting

---

## n8n

Responsible for:

- Synchronization
- Webhooks
- Retry logic
- Notifications

No business logic should reside in n8n.

---

# Contribution Lifecycle

Pending Review

↓

Reviewed

↓

Available as Cash on Hand

↓

Assigned to Deposit Batch

↓

Deposit Confirmed

↓

ERPNext Journal Entry Created

↓

Bank Reconciled

Ignored contributions permanently exit the workflow but remain in the audit trail.

---

# Cash Management

Cash on Hand consists of reviewed contributions that:

- have not been ignored
- have not been deposited

Cash on Hand is the source for Deposit Batches.

---

# Deposit Batch

A Deposit Batch represents one physical bank deposit.

Fields include:

- Batch Number
- Deposit Date
- Prepared By
- Verified By
- Expected Amount
- Actual Amount
- Deposit Slip Number
- Bank Account
- Status (Draft, Prepared, Deposited, Reconciled)

The batch contains references to individual contributions while preserving donor-level history.

---

# ERP Integration

SignatureGate creates accounting events only after a deposit has been confirmed.

Journal Entry (conceptual):

Debit: Checking Account

Credit: Donation Revenue

This keeps accounting synchronized with actual bank activity while maintaining detailed donor records in SignatureGate.

---

# Future Enhancements

- Fund restrictions
- Annual giving statements
- Multi-bank support
- Deposit discrepancy workflow
- In-kind valuation
- Stock gifts
- Cryptocurrency
- Campaign synchronization
