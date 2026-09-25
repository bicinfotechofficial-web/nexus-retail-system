# Decision Log

The central agent owns this file. A decision recorded here is part of the contract, and no build agent may change it.
To propose a change, add an entry to `docs/CHANGE-REQUESTS.md` and wait until it is accepted.

Status values: **Locked** (build against it), **Proposed** (waiting for Bicy's OK), **Superseded**.

| ID | Decision | Why | Revisit when | Status |
|---|---|---|---|---|
| D-001 | Run on the **Firebase Spark (free) plan** only, with **no Cloud Functions**. All business logic runs on the device, and Firestore Security Rules are the only thing enforcing it on the server. | The client should approve the product before any paid plan. | After the pilot is approved we move to Blaze. See "Blaze upgrade path" below. | Locked |
| D-002 | Stack: Flutter (Android first) for the POS app, Flutter Web for the admin console, Firestore, and Firebase Auth (email + password). One monorepo using Dart pub workspaces. | We can share models and business rules across both apps. | — | Locked |
| D-003 | **Bill number = `{LOC}-{DEV}-{SEQ}`**, e.g. `PTB-D01-000123`. Each device has its own sequence. The Firestore doc ID is `{DEV}-{SEQ}`, so it is deterministic. | Without a server we cannot allocate a single store-wide sequence that is safe offline. Per-device series never collide and have no gaps. | On Blaze, a function can assign a store-wide number (`PTB-000123`) on sync and keep the device number as a secondary reference. **This departs from BRD §4.2 and must go back into the BRD as v4.** | Locked |
| D-004 | Every app install registers as a **new device code** (D01…D99, per location), and codes are never reused. Registration requires network. | A reinstall loses the local counter. Reusing a code would produce duplicate bill numbers. | — | Locked |
| D-005 | All stock changes are written as **deltas** using `FieldValue.increment` (integers only), and every change also writes a movement record. | Concurrent offline devices merge correctly, and there is no last-write-wins. | — | Locked |
| D-006 | Quantities are integers in **base units**: raw materials in g, ml or pcs, and finished goods in pcs. Money is integer **paise**. | Avoids floating-point drift in increments and totals. | — | Locked |
| D-007 | Each sellable size is its own product (for example, "Black Forest 1 kg" and "Black Forest 500 g"). There are no variants in the MVP. | Keeps billing, stock and reports simple. | If the catalog grows past ~300 SKUs. | Locked |
| D-008 | Cakes a Store Manager suggests are created as `pending` with a proposed price. They **cannot be sold until an Admin approves them** and sets the price. | Pricing is Admin-only (BRD §3.2). | If approval turns out to be a bottleneck, auto-approve at the proposed price and let the Admin edit it later. | Locked |
| D-009 | Bills are never edited. A Store Manager can **cancel a bill on the same business day** with a reason, which restocks the items and reverses the summaries. After that day, only returns are allowed. | Summaries stay correct and every change leaves an audit trail. | — | Locked |
| D-010 | The bill total is **rounded to the nearest ₹1**, and the round-off is shown as its own line. | Common practice at the counter, so no coins are needed. | — | Locked |
| D-011 | A bill-level discount is either a flat amount or a percentage (rounded half-up to the paise). Each location has an optional `maxDiscountPct` cap, with no cap by default. | Matches BRD §4.4. The cap is optional. | — | Locked |
| D-012 | A return counts on **the day it is processed**, not on the original bill's date. | Closed days never change. | — | Locked |
| D-013 | **No GST in the MVP.** The data model includes `gstRate` on products and `taxLines` on bills, both empty for now. The printer prints the GST block only when `taxLines` is non-empty. | Flat bills for the pilot, as agreed. | When GST is enabled. | Locked |
| D-014 | Reports read **pre-aggregated summary docs** (daily and monthly per location), which are incremented in the same write batch as the bill, return, cancellation or expense. | Without Functions, this keeps admin reads cheap enough for the Spark quota. | — | Locked |
| D-015 | Low-stock alerts are **computed in the app** from the stock docs and shown as an in-app badge and list. **No push notifications** in the MVP. | Server-side push needs Functions (Blaze). | Blaze: an FCM push from a Firestore trigger. | Locked |
| D-016 | Offline limit: a warning at 80% of the location's `offlineLimitHours` (default 5), and **new billing is blocked** at 100%. An **Admin override PIN** (per store) grants 2 more hours. The override is audited and can be repeated. | BRD §7. The block-or-warn question is now settled as "block, with a PIN override". | — | Locked |
| D-017 | Roles are data (`roles/{roleId}.permissions[]`), and both the rules and the UI check permissions, never role names. | BRD §3 note: a Cashier role should be addable later without rework. | — | Locked |
| D-018 | Admin creates Store Manager logins from the web console through a **secondary Firebase App instance**, so the Admin session isn't replaced. Disabling a user sets `active=false`, and the rules then deny every operation for that user. | Without the Admin SDK, we can't create other users any other way. | Blaze: move to a callable function with the Admin SDK and custom claims. | Locked |
| D-019 | Audit entries are written **in the same batch** as the change, with the same ID. The rules use `existsAfter()` to require that the audit entry exists. Audit docs are create-only. | Audit on the server without Functions. | — | Locked |
| D-020 | Printer paper width is **80 mm (48 columns)** by default, with 58 mm (32 columns) configurable per device. Connection is Bluetooth Classic SPP with ESC/POS. | "Slightly larger than a petrol-pump slip". | After hardware testing with the pilot printer. | Locked |
| D-021 | Cold-storage backup and data retention are **out of the MVP**. Scheduled Firestore export needs Blaze. | One pilot store stays well under the free storage limit. | Blaze. | Locked |
| D-022 | Business date = the device's local date in IST (`Asia/Kolkata`), stored as `YYYY-MM-DD` next to `serverCreatedAt`. | Summaries need a stable day key that works offline. | If clock tampering shows up, compare it against `serverCreatedAt` in reports. | Locked |

## Blaze upgrade path (after approval)

1. Store-wide bill numbers are assigned by a Firestore trigger (D-003).
2. Push notifications for low stock (D-015).
3. User management through a callable function with custom claims (D-018).
4. A scheduled export to Cloud Storage for cold backup (D-021).
5. Summaries recomputed on the server, as a cross-check against the client-written ones (D-014).

None of these steps change the data model. They add server writers alongside the client writers.
