# Caramel Cottage — Cake Shop Management System
## Business Requirements Document

**Brand:** Caramel Cottage
**Website:** https://www.caramelcottage.in
**Scope:** Multi-location cake shop billing, inventory, and management system — Android, iOS, and Web
**Status:** v3 — All initial open items resolved; scope baseline ready for technical design

---

## 1. Overview

Caramel Cottage operates multiple cake shop locations across Kerala. This system replaces manual billing and stock tracking with an app-based solution covering point-of-sale billing, two-stage inventory (raw material → finished goods), multi-location administration, expense logging, and consolidated reporting — with offline resilience at the store level.

---

## 2. Platforms

| Platform | Purpose |
|---|---|
| Android app | Store Manager billing + stock operations (primary POS device) |
| iOS app | Same as Android, for stores/staff on iOS devices |
| Web app | Admin console — multi-location oversight, reporting, expense logging |

---

## 3. User Roles

### 3.1 Admin
- Created at system setup (super-user); can create/manage Store Manager accounts
- Full visibility across **all locations**, with ability to **drill into a single location**
- Can log expenses (rent, salaries, utilities)
- Can view all reports, audit trails, and stock across locations
- Receives low-stock alerts for **all** locations

### 3.2 Store Manager
- Created by Admin, scoped to **one location**
- Views cake catalog and pricing (pricing is **Admin-only** to edit)
- Can **add/suggest new cakes** to the catalog for their location (local specials)
- Configures **low-stock thresholds** for their own location's items
- Performs billing (create, print)
- Performs all stock operations: stock in, stock out, add, remove, update existing stock (manual entry for now)
- Receives low-stock alerts for **their own location only**

> **Note:** Only two roles exist today (Admin, Store Manager). Design the permission model as role-based (not hardcoded) so additional roles (e.g., Cashier with billing-only access) can be added later without rework.

---

## 4. Billing

### 4.1 Bill Format
- Printed via **Bluetooth thermal printer**
- Layout: narrow receipt style similar to a petrol pump bill, slightly larger width
- Bill contents: location name/address, bill number, date/time, cake line items (name, qty, price), discount (if any), GST breakup, total, payment mode, served-by (Store Manager)

### 4.2 Bill Numbering
- Bill numbers are **location-specific** (each location maintains its own sequence, e.g., `PKD-000123`)

### 4.3 GST
- GST applied per applicable rate(s) on cake items
- Bill must show taxable value, GST amount, and total separately

### 4.4 Discounts
- **Bill-level discount only** (no per-item discount)
- Discount reflected on printed bill and in sales reporting (gross vs. net sales)

### 4.5 Payment Modes
- Cash, UPI, Card, and other wallet modes supported
- **Split payment** on a single bill supported (e.g., part cash + part UPI)
- Reports must break down sales by payment mode

### 4.6 Returns
- Store Manager can process a return against a prior bill (full or partial item return)
- Return should:
  - Re-credit stock (finished goods) at that location
  - Generate a return record linked to the original bill number
  - Reflect in daily/monthly sales reports as a deduction, not hidden
- Refund method: **mixed refund modes supported** — refund can be split across payment types based on availability (e.g., partial cash + partial UPI reversal), not locked to the original single payment mode

---

## 5. Inventory Management

### 5.1 Two-Stage Stock Model
- **Store stock**: raw materials (e.g., cake mix, ingredients)
- **Shop stock**: finished goods (ready cakes) available for sale
- Conversion: raw material is deducted from Store stock and finished cake is added to Shop stock (currently a **manual entry** — Store Manager records "X units of cake mix consumed → Y cakes produced")

### 5.2 Stock Operations (Store Manager)
- Stock In (raw material received)
- Stock Out (raw material consumed / wastage)
- Add stock (finished goods produced)
- Remove stock (finished goods sold — auto-deducted on billing; manual removal for wastage/spoilage)
- Update existing stock (correction/adjustment)

### 5.3 Future Provision
- System should be designed to later support **recipe/BOM-based auto-deduction** (e.g., 1 kg cake mix → N units of a specific cake) without a data-model rework. For now, all conversion entries are manual.

### 5.4 Low Stock Alerts
- Threshold-based alert per item, per location — **thresholds configured by Store Manager** for their own location
- Alert recipients:
  - Admin — for all locations
  - Store Manager — for their own location only

---

## 6. Admin Dashboard & Reporting

### 6.1 Multi-Location View
- Consolidated view across all locations
- Drill-down into any single location for detail

### 6.2 Sales Reports
- Daily, Monthly, Annual sales
- Year-on-Year (YoY) comparison
- Returns reflected separately in reports

### 6.3 Financials
- Total sales, total expenses, revenue (net)
- Expense logging (Admin-only): rent, salaries, utilities — categorized, per location, with date

### 6.4 Audit Trail
- Every stock adjustment, bill edit/cancellation, return, and expense entry logged with: user, timestamp, location, before/after values (where applicable)
- Audit log viewable by Admin

---

## 7. Offline Mode

- Store-side app (Android/iOS) must support billing and stock entry while offline
- Transactions queued locally and synced automatically once connectivity resumes
- **Confirmed: a location can run multiple billing devices simultaneously.** This means offline sync must handle:
  - Bill numbering conflicts — two offline devices at the same location must not issue the same bill number once synced (e.g., device-prefixed temporary numbers reconciled into the location's sequence on sync, or a reserved number-block per device)
  - Stock sync conflicts — concurrent stock deductions/updates from two offline devices at the same location must merge without overwriting each other (e.g., delta-based sync rather than last-write-wins on absolute values)
- Max tolerated offline duration: **configurable, default 5 hours** — sync is required once the device has been offline past this window (app should warn the Store Manager as the threshold approaches, and block new billing if exceeded until sync succeeds — *confirm block-vs-warn-only behavior at technical design stage*)

---

## 8. Data Retention & Backup

- Active/hot data retained in-app/database for **1–2 months**
- Beyond that, data is **backed up to disk (cold storage)** for further analysis if required
- Backup process should be automated and recoverable (retrievable for audits, disputes, or historical analysis on demand)

---

## 9. Non-Functional Requirements (Draft — for review)

- Role-based access control enforced server-side, not just UI-level
- Bluetooth thermal printer integration (ESC/POS or equivalent standard)
- Sync mechanism must be idempotent (no duplicate bills/stock entries on retry after reconnect)
- Multi-location bill numbering must never collide

---

## 10. Resolved Decisions

| # | Item | Decision |
|---|---|---|
| 1 | Pricing control | Admin-only |
| 2 | Discount level | Bill-level only |
| 3 | Payment modes | Cash, UPI, Card, wallets; split payment supported on one bill |
| 4 | Return refund method | Mixed — refund split across payment types based on availability |
| 5 | Low-stock thresholds | Set by Store Manager per location |
| 6 | Offline duration | Configurable, default 5 hours; sync required past that window |
| 7 | Multiple devices per location | Yes — conflict-handling rules added to Section 7 |
| 8 | Catalog management | Store Manager can add/suggest local specials |
| 9 | Language | English only |
| 10 | Locations | 20 currently — architecture should assume this scale and headroom for growth |

---

*This document is the finalized v1 scope baseline. All initial open items are resolved as of this round. Next step is technical design (data model, sync protocol, API/DB architecture) based on this scope. Any new requirement or change discovered during design should be added back here and versioned rather than decided silently in code.*
