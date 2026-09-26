# QA Scenario Plan (QA-1)

Every acceptance item in `docs/01-MVP-SCOPE.md`, every rule in `docs/03-SYNC-AND-OFFLINE.md` and every security-rule behaviour in `docs/04-PERMISSIONS.md` #1–13 maps to at least one numbered scenario below. Scenarios are written from the contracts (`docs/`, `packages/core`, `packages/data/lib/src/api/`), not from any implementation. Where a contract is unclear or wrong, the scenario names the finding in `docs/QA-FINDINGS.md` that has to be settled before its expected result is final.

Revision 2 follows the central outcomes for QA-001 to QA-022 (D-016, D-028 to D-031 and the revised 02, 03 and 04). Findings still open are named where they apply: QA-023 to QA-030.

## Layers
| Layer | Where it runs | What it can reach |
|---|---|---|
| **Dart** | `test/e2e/test/`, `dart test`, no emulator | `nexus_core`, plus the backend's D-027 JSON plan fixtures once they exist (this package stays pure Dart; where the fixtures are written is QA-026) |
| **Rules** | Node harness in `firebase/` (`@firebase/rules-unit-testing`) on the Firestore emulator | Raw reads and writes as any fixture user, plus the backend's `WritePlan` JSON fixtures (D-027). The backend agent owns the directory, so QA hands over the case list and reviews the tests |
| **Device** | Android `integration_test` on an emulator, against the Firebase emulator (`demo-caramel-cottage`) | The real Firestore SDK with persistence, through the `nexus_data` interfaces only. Two devices = two named Firebase apps, each with its own Firestore instance; offline = `disableNetwork()` / `enableNetwork()`; a kill = dropping the app instance and reopening it on the same persistence. They live in `apps/pos/integration_test/` (QA-016), which needs the `integration_test` dev dependency first (QA-026) |
| **Manual** | QA-8 pilot checklist on the real phone and printer (B-6) | Paper output, Bluetooth, real reboots |

Status: **Written** (in this package and green), **Ready** (can be written now), **Waits** (needs the task IDs listed).

## Common fixtures
- **F-1 Seed.** Roles `ADMIN` and `STORE_MANAGER` exactly as `SeedRoles`. Users: `uid-admin` (Admin, no location), `uid-sm-ptb` (SM @ PTB), `uid-sm-mnj` (SM @ MNJ), `uid-sm-off` (SM @ PTB, `active: false`), and an anonymous client. Locations: `PTB` (no discount cap, `offlineLimitHours` 5, `overrideExtensionHours` 2, a known 8-digit PIN, `Limits.minOverridePinDigits`), `MNJ` (`maxDiscountPct` 20, `offlineLimitHours` 3, another 8-digit PIN). Both are created through `LocationService.save`, so `nextDeviceNo` starts at 0. Products: five ACTIVE global products with paise prices (e.g. ₹99.99, ₹18.75), one PENDING local special at PTB, one INACTIVE. Three raw materials (G, ML, PCS).
- **F-2 Devices.** PTB `D01`, `D02`; MNJ `D01` (the same code at another location, on purpose: audit IDs carry the location, D-028). Registered through `DeviceService.register`, so PTB's `nextDeviceNo` is 2 and MNJ's is 1.
- **F-3 Opening stock.** Each FG and RM item at PTB and MNJ has a known opening quantity from a STOCK_IN / PRODUCE, so "exact stock" is `opening + Σ movement deltas`.
- **Stock oracle.** For every item: `qty == Σ delta over all movement docs for that itemKey` (D-005). Asserted at the end of every Device scenario that writes stock.
- **Summary oracle.** The document-to-summary recomputation in `test/summary_reconciliation_test.dart` (`oracle`). Asserted at the end of every Device scenario that writes bills, cancellations or returns.

---

## A. Pilot acceptance (01-MVP-SCOPE)

### Acceptance #1 — two devices bill offline at once, sync, no duplicates, exact stock (QA-2)
**A1-1 Concurrent offline billing, same location.** Layer: Device. Waits: BE-9, BE-10, BE-12.
- Setup: F-1..F-3. Devices A (`D01`) and B (`D02`) at PTB, both signed in as `uid-sm-ptb` and synced.
- Steps: both go offline. A creates 20 bills, B creates 20 bills, overlapping products, including discounts and split payments. Both go online; run `SyncService.syncNow()` on each.
- Expected: 40 bill docs on the server with 40 distinct IDs and `billNo`s; each device's `seq` runs 1..20 with no reuse; every stock doc equals the stock oracle; `devices/D01.lastBillSeq == devices/D02.lastBillSeq == 20`; the day's summary equals the summary oracle; both devices' `SyncService.errors` are empty and their ledgers are empty.

**A1-2 Both sell the last piece.** Layer: Device. Waits: BE-10, BE-12.
- Setup: FG item X with qty 1 at PTB. A and B offline.
- Steps: A sells 1 × X, B sells 1 × X, both sync.
- Expected: both bills accepted (the sale is never blocked, 03-SYNC §5), `stock/FG_X.qty == -1`, X appears in `StockRepository.watchLowStock` if its threshold is ≥ −1.

**A1-3 Device registration and `nextDeviceNo`.** Layer: Device, with the denials in Rules (R-4). Waits: BE-2, BE-9.
- Steps: (a) at a new location (`nextDeviceNo == 0`) register one install; (b) two fresh installs at PTB call `DeviceService.register` at the same time; (c) an Admin saves the PTB location (`LocationService.save`) with a `Location` whose `nextDeviceNo` is stale, while (b) runs.
- Expected: (a) the device is `D01` and `nextDeviceNo` is 1 (registration takes +1 and creates `D{new value}`); (b) two different codes `D0n`, `D0n+1`, `nextDeviceNo` rose by exactly 2, neither device doc was overwritten, and each new device doc has `lastBillSeq == lastMovementSeq == lastReturnSeq == 0`; (c) the Admin's save leaves `nextDeviceNo` untouched (it never writes the field), so no code is handed out twice.

**A1-4 Reinstall never reuses a code.** Layer: Device. Waits: BE-8, BE-9.
- Steps: device `D01` bills 3 times and syncs; its local data is wiped (reinstall); it registers again and bills.
- Expected: it gets a new code (not `D01`), its first bill is `{new}-000001`, the three `D01` bills are untouched. `register` while offline throws `DataFailure(offline)`.

**A1-5 Two locations, same device code (D-028).** Layer: Device. Waits: BE-10, BE-12.
- Steps: PTB `D01` and MNJ `D01` each create a bill, cancel it the same day, create another bill and return part of it; also one WASTAGE and one ADJUST each.
- Expected: every batch at both locations is accepted and there are no sync errors. `auditLog` holds both `PTB-D01-000001-X` and `MNJ-D01-000001-X` (`Ids.auditId(loc, Ids.cancelId(billId))`), both `PTB-D01-R000001` and `MNJ-D01-R000001`, and both locations' `-M00000n` wastage and adjust entries; each has `locationId` set to its own location.

**A1-6 Cancel vs return of one bill on two offline devices (D-029).** Layer: Device (and Dart, `concurrent_returns_test.dart`, Written). Waits: BE-10, BE-12.
- Setup: bill X (today, COMPLETED, no returns) synced to A and B; both go offline.
- Steps: order 1: A returns 1 unit of X, B cancels X; A syncs first, then B. Order 2: the same with B syncing first.
- Expected: order 1: the return lands; B's whole cancel batch is rejected (rule #5(a) needs an empty `returnedQty`) and shows in B's `SyncService.errors`; X stays COMPLETED with `returnedQty` set; no CANCEL movement, no `{loc}-{X}-X` audit doc, no `cancelled` in the summary. Order 2: the cancel lands; A's whole return batch is rejected (rule #5(b) needs COMPLETED); no return doc, no RETURN movement, no stock or summary change from it. Both orders: stock oracle and summary oracle hold.

**A1-7 Two offline returns past the sold qty (D-029).** Layer: Device (and Dart, Written). Waits: BE-10, BE-12.
- Steps: bill X has 2 × item P. Offline, A returns 2 × P and B returns 1 × P; both sync.
- Expected: the first to sync lands; the second is rejected because `returnedQty[P]` would exceed `soldQty[P]`; X is refunded exactly its P value once.

**A1-8 Two offline returns within the sold qty.** Layer: Device (and Dart, Written as a skipped test). Waits: BE-10, BE-12, QA-024.
- Steps: bill X is 3 × ₹1.67 = ₹5. Offline, A and B each return 1 unit; both sync; then the last unit is returned online.
- Expected per D-024 (d): Σ `refundTotal` = ₹5. Today's contract refunds ₹2 + ₹2 + ₹2 = ₹6 (QA-024), so this stays open until the contract changes.

### Acceptance #2 — a kill or reboot mid-bill never duplicates a bill or a stock deduction (QA-3)
**A2-1 Kill after the number is allocated, before the batch.** Layer: Device (and BE-8 unit test). Waits: BE-8, BE-10.
- Steps: allocate a bill number (seq n) with the counter store, then drop the app instance before the batch is built; reopen and create a bill.
- Expected: no doc with seq n anywhere; the new bill has seq n+1; stock and summaries changed only by the new bill.

**A2-2 Kill after the local commit, before sync.** Layer: Device. Waits: BE-10, BE-12.
- Steps: offline, create a bill; drop the app instance; reopen (still offline) and check the bills list; go online and sync.
- Expected: the bill is in `SalesRepository.watchBills` before sync; after sync exactly one bill doc, one SALE movement, one stock deduction per line, summary counted once.

**A2-3 Reboot with a queue.** Layer: Device; Manual on the pilot phone. Waits: BE-10, BE-12.
- Steps: offline, create 10 bills, 1 cancel and 2 returns; restart the process (and, in QA-8, reboot the phone); go online.
- Expected: all 13 operations land exactly once; stock oracle and summary oracle hold; ledger empty.

**A2-4 The same batch submitted twice.** Layer: Rules (fixture replay) and Device. Waits: BE-3, BE-5, BE-10.
- Steps: apply the bill `WritePlan` fixture; apply it again unchanged. Repeat for a return plan and a stock-movement plan.
- Expected: the second application is denied as a whole: no second stock decrement, no second summary increment (03-SYNC §4, 04 #7, #9).

**A2-5 Double tap on Save.** Layer: POS widget test (POS-5), confirmed on Device. Waits: POS-5.
- Expected: `SalesService.createBill` is called once; one bill.

**A2-6 Counter recovery from the device doc (03-SYNC §3.4).** Layer: Device (and BE-8 unit test). Waits: BE-8, BE-10.
- Steps: sync 57 bills, 12 stock movements and 4 returns from `D01`; check `devices/D01` holds `lastBillSeq 57`, `lastMovementSeq 12`, `lastReturnSeq 4`; clear only the local counter store; start the app; create one bill, one STOCK_IN and one return. Repeat offline, with the device doc only in the cache (its values include the queued writes).
- Expected: the new IDs are `D01-000058`, `D01-M000013`, `D01-R000005`; no create is rejected; each counter on the device doc went up by one. SALE, RETURN and CANCEL movements don't use `movementSeq` (their IDs are the bill or return ID), so `lastMovementSeq` only follows STOCK_IN, STOCK_OUT_RAW, WASTAGE_*, PRODUCE and ADJUST.

### Acceptance #3 — a Store Manager can't read or write another location (rules #13)
**A3-1 Cross-location reads denied.** Layer: Rules. Waits: BE-6.
- As `uid-sm-ptb`, `get` and `list` on each of: `locations/MNJ`, and `locations/MNJ/{devices, stock, movements, bills, returns, dailySummary, monthlySummary}` → all denied. The same as `uid-sm-mnj` against PTB.

**A3-2 Cross-location writes denied.** Layer: Rules. Waits: BE-6, BE-10 fixtures.
- As `uid-sm-ptb`, apply every plan fixture rewritten to target MNJ (bill, cancel, return, each stock movement, adjust, threshold) → denied. Direct `create`/`update`/`delete` on each MNJ collection → denied.

**A3-3 Mixed batch.** Layer: Rules. Waits: BE-6.
- A PTB bill batch that also increments `locations/MNJ/dailySummary/{d}` → the whole batch is denied, and PTB is unchanged.

**A3-4 Through the SDK.** Layer: Device. Waits: BE-11.
- Signed in as SM @ PTB, `SalesRepository.getBill('MNJ', …)`, `findByBillNo('MNJ-…')`, `StockRepository.watchStock('MNJ')` and `SummaryRepository.daily('MNJ', …)` all fail with `DataFailure(notPermitted)` and return no data.

### Acceptance #4 — the printed receipt matches the saved bill (QA-8, printer suites)
**A4-1 Normal bill.** Layer: Device (the printer package is Flutter, so not Dart). Waits: PR-2, PR-5, BE-10.
- Steps: create a bill, read it back from the server with `SalesRepository.getBill` (`Source.server`), render `PrinterService.previewBill(bill, location)`.
- Expected: exactly the printed fields acceptance #4 lists, each with the saved value: location name, address and phone; `billNo`; date and time of `clientCreatedAt` in IST; each line's name, qty, `unitPrice` and `lineTotal`; subtotal; discount; round-off (always printed, ₹0.00 included); total; each payment's mode and amount, with cash tendered and change; `servedBy.name`; `receiptFooter`. All amounts as `Money.format()`. No GST block (`taxLines` empty, D-013). Fields that are never printed (`seq`, `createdBy`, `serverCreatedAt`, `soldQty`, `returnedQty`, `lastReturnId`, `servedBy.uid`) are not compared.

**A4-2 Discount, round-off and split payment.** As A4-1 with a % discount, a non-zero `roundOff` (its own line, D-010), three payments and cash tendered. Expected additionally: discount line with type and amount, round-off line, change = tendered − cash.

**A4-3 Cancelled bill reprint.** Expected: a CANCELLED banner and a REPRINT line; all other fields as A4-1.

**A4-4 Return slip.** `previewReturn(ret, bill, location)` shows the original `billNo`, each returned line and amount, `refundTotal`, and each refund mode and amount.

**A4-5 58 mm.** Every preview line is at most 32 characters (48 at 80 mm), long names wrap, amounts stay right-aligned, and no field is dropped.

**A4-6 Paper.** Layer: Manual (QA-8). The printed slip matches the on-screen preview for A4-1..A4-4, and the ₹ glyph or the `Rs.` fallback prints.

### Acceptance #5 — the admin's daily totals equal the bills and returns of that day (QA-5)
**P-01 Summary-equals-documents property, core.** Layer: Dart. **Written** (`test/summary_reconciliation_test.dart`).
- Setup: fixed seed `20260926`, 40 runs, two locations (MNJ with a 20% cap), two devices each, seven business days from 2026-09-27 (crosses into October).
- Steps: random bills (1–4 lines, and now and then 11–20 lines from a wider catalogue; paise prices, a free item, none / flat / % discounts up to 100%, 1–4 payments, cash tendered), same-day cancellations, full or partial returns of bills from any earlier day with 1–3 refund modes, and conflicting offline pairs (a stale cancel after a synced return, a stale return after a synced cancel, a stale return past `soldQty`). Every batch goes through a model of rules #5(a), #5(b) and #6; a rejected batch writes nothing and counts as a sync error. Summaries are built only from `SummaryDeltas`, both with `Summary.+` and as `increments()` field paths read back with `Summary.fromMap`.
- Expected, for every day and month at each location and for both combined: every field (counts, gross, discounts, round-off, net sales, returns, cancelled, `byMode`, `byProduct` qty and amount) equals the recomputation from the documents; `netRevenue` equals the money kept; Σ `byMode` equals `netRevenue`; Σ `byProduct.amount` equals the pre-round-off net; each monthly summary equals the sum of its days. Per bill: refunds never exceed its total, equal it after a full return, and follow D-024 (d) cumulatively; `returnedQty` matches its returns; per-line nets are the largest-remainder split. Per bill doc (D-029, D-030): at most 20 lines and 4 payments; `soldQty` holds each line's qty; `returnedQty` never holds a 0 and never exceeds `soldQty`; a CANCELLED bill has an empty `returnedQty`; `lastReturnId` names the bill's latest return. Every lost conflict is a sync error and left no return doc. A coverage test proves the seed reaches each edge case (zero-total bills, cap rejections, zero-refund returns, cross-month returns, refused next-day cancels, refused cancel after return, refused over-returns, refused returns on cancelled bills, bills over 10 lines and at exactly 20, a refused 21-line cart, and each of the three lost conflicts).
- Extension: when BE-10 lands, P-03 replaces the model in `test/support/shop_sim.dart` with the backend's `WritePlan` JSON fixtures.

**P-02 The same property on the emulator.** Layer: Device. Waits: BE-10, BE-11, BE-12.
- Steps: a scripted two-device day at PTB and MNJ: bills, a same-day cancel, a return of an earlier day's bill, a return on the first day of a new month.
- Expected: `SummaryRepository.daily` / `monthly` for each location, and their `Summary.+` across locations, equal the oracle over `SalesRepository` bills and returns.

**P-03 The property through the WritePlan fixtures.** Layer: Dart (`test/e2e` reads the D-027 JSON fixtures). Waits: BE-10, QA-026.
- Steps: the backend's exported plans for P-01's operation types are applied to an in-memory store that honours increment, merge and server-timestamp sentinels.
- Expected: P-01's assertions hold for the stored docs, plus the stock oracle for every FG item.

**P-04 Expenses and profit.** Layer: Dart (core) now; Device with BE-10. Waits: BE-10 for the Device part.
- Steps: create expenses in several categories, edit one's amount, move one to another month, move one to another location.
- Expected: each `monthlySummary.expenses` and `byExpenseCategory` equals Σ expenses with that location and month; `profit == netRevenue − expenses`.

### Acceptance #6 — at the offline limit billing is blocked, and an Admin PIN allows billing for the next 2 hours
All with a fake clock. Layer: Device (the `OfflineGuard` lives in `nexus_data`) plus BE-13's unit tests. Waits: BE-12, BE-13, POS-12. `lastSyncAt` is the end of the last pass in which `waitForPendingWrites` finished and every ledger entry was resolved (03-SYNC §6.4); it is first set at sign-in or registration.

**A6-1 Within limit.** Offline for 3 h 59 m at PTB (limit 5 h) → `WithinLimit`; billing works.
**A6-2 Warning at 80%.** Offline 4 h → `NearLimit(billingStopsIn: 1 h)`; billing still works; POS shows the amber banner.
**A6-3 Block at 100%.** Offline 5 h → `BillingBlocked`; `createBill` throws `DataFailure(billingBlocked)` and writes nothing; stock operations, cancels, returns, reports and reprints still work (only new billing is blocked, 03-SYNC §7).
**A6-4 Correct PIN.** At 5 h, `override(correctPin)` → true; billing works until `now + overrideExtensionHours` (2 h from the moment the PIN is entered, D-016); at entry + 2 h it blocks again. An `OFFLINE_OVERRIDE` audit doc with ID `Ids.overrideAuditId('PTB', 'D01', entryTime)` (`PTB-D01-OVR-{millis}`), `entityPath` = `locations/PTB/devices/D01`, `by` = the SM's uid, is queued and exists on the server after sync.
**A6-5 Wrong PIN.** `override(wrongPin)` → false, still blocked, no audit doc.
**A6-6 Repeat override.** A second correct PIN after the first extension runs out allows billing until its own entry + 2 h and writes a second audit doc with a different `OVR-{millis}` ID (D-016, D-028).
**A6-7 Per-location limit.** At MNJ (3 h) the warning is at 2 h 24 m and the block at 3 h.
**A6-8 What moves `lastSyncAt`.** (a) A pass in which the flush finished and every ledger entry was confirmed sets `lastSyncAt` to the pass end and returns the state to `WithinLimit`. (b) A pass in which one entry was rejected (a disabled user's bill) also sets it: the rejected entry moves to sync errors and billing is not blocked 5 h later. (c) A pass whose `waitForPendingWrites` times out (still offline) does not move it. (d) Right after registration, and after an online sign-in, `lastSyncAt` is set and never null.
**A6-9 Long closure.** Offline 10 h (overnight), one correct PIN → billing is allowed until entry + 2 h, however long the device was offline (D-016); a single PIN is enough.
**A6-10 Restart while blocked.** At 5 h offline, blocked, kill and restart the app (still offline; Firebase Auth restores the session). Expected: still `BillingBlocked`, with the same `elapsed`; an override still in force before the restart is still in force after it. Waits: QA-025 (the contract doesn't yet say `lastSyncAt` and the override survive a restart, or that a restored session isn't a "sign-in").
**A6-11 PIN length (D-031).** `LocationService.save(location, newPin: '1234567')` throws `DataFailure(ruleViolation)` and writes nothing; an 8-digit PIN is accepted and stored only as `overridePinHash` (`salt$hash`); a new location without a PIN is refused. Layer: Device (BE-11) and AD-3 widget test. Waits: BE-11, AD-3.

---

## S. Sync and offline protocol (03-SYNC)

**S1-1 Offline queue survives restarts (§1).** Covered by A2-2 and A2-3.

**S2-1 Bill batch contents (§2).** Layer: Dart (plans, P-03) and Rules (fixture). Waits: BE-10.
- Expected: the plan has exactly: bill create (with `soldQty` = each line's qty, `returnedQty` empty, `lastReturnId` null, at most 20 lines and 4 payments); one FG stock `set(merge)` per line with `qty: increment(−qty)` and `lastMovementId == billId`; the SALE movement `{billId}` with one line per bill line; daily and monthly summary increments equal to `SummaryDeltas.forBill` with `lastWriteRef` = the bill path; `devices/{id}.lastBillSeq = seq`. Nothing else.

**S2-2 Cancel batch.** Plan: bill update (`status`, `cancel` only, with `cancel.businessDate` = the bill's own); +qty per line; CANCEL movement `{billId}-X` with a reason; summary increments = `forCancel` on the bill's date; `lastWriteRef` = the CANCEL movement path; the BILL_CANCEL audit doc `{loc}-{billId}-X`. The service refuses to build it when `cancelBlocker` is not null (D-009, D-025). Waits: BE-10.

**S2-3 Return batch.** Plan: return create (at most 4 refunds, whole-rupee `refundTotal`); bill update of `returnedQty.{productId}` increments (never 0) and `lastReturnId` = the new return ID, nothing else; +qty per returned line; RETURN movement `{returnId}`; summary increments = `forReturn` on the return's date (D-012); `lastWriteRef` = the return path; the RETURN audit doc `{loc}-{returnId}`; `devices/{id}.lastReturnSeq = seq`. Waits: BE-10.

**S2-4 Stock in / out / wastage / produce.** One movement create with a `D0n-M000nnn` ID, at most 20 lines, and a stock `set(merge)` with `qty: increment(delta)` per line; `devices/{id}.lastMovementSeq = seq`; an audit doc `{loc}-{movementId}` only for WASTAGE_RAW and WASTAGE_FG; a STOCK_IN note is stored in `Movement.note`; PRODUCE is a single movement with negative RM lines and positive FG lines. A 21-line movement is refused before anything is written. Waits: BE-10.

**S2-5 Adjust.** One ADJUST movement with `before` = local qty, `after` = counted, `delta = counted − before`; one increment by `delta`; a STOCK_ADJUST audit doc `{loc}-{movementId}`; `lastMovementSeq` updated; a reason is required. Waits: BE-10.

**S2-6 Expense create and edit.** Expense doc, monthly summary increments = `SummaryDeltas.forExpense` (two docs when the month or location changes), an audit doc `EXP-{id}-{ms}`, `lastWriteRef` = that audit doc. Waits: BE-10.

**S2-7 All-or-nothing.** Layer: Rules and Device. For each plan type, drop one required doc (the audit, the movement, or the new doc named by `lastWriteRef`) → the whole batch is denied; stock and summaries unchanged. Waits: BE-5, BE-10.

**S3-1 Registration needs the network (§3.1).** Offline `register` → `DataFailure(offline)`; no device doc. Waits: BE-9.
**S3-2 Persist before build (§3.3).** A2-1. **S3-3 Recovery (§3.4).** A2-6. **S3-4 Reinstall (§3.5).** A1-4.
**S3-5 IDs across devices never clash.** A1-1, plus a 1000-bill Dart property over `Ids.billId` for all device codes once BE-8's counter store is testable. Waits: BE-8.

**S4-1 Deterministic IDs.** A retried operation with the same allocated number writes the same paths (A2-4).
**S4-2 Create-only on bills, returns, movements.** Rules: a `set` on an existing bill, return or movement path, with identical or different content, is denied; so its batch fails. Waits: BE-3, BE-4.
**S4-3 Save is built once.** A2-5.

**S5-1 Increments merge (§5).** A1-1 and A1-2.
**S5-2 Adjust against the local view.** Layer: Device. Waits: BE-10, BE-12.
- Steps: FG X = 10 on both devices. A goes offline; B (online) sells 2; A, still seeing 10 locally, enters a physical count of 7 (delta −3); A syncs.
- Expected: final qty = 10 − 2 − 3 = 5 (off by B's sale, as documented); the ADJUST movement stores before 10, after 7.
**S5-3 Negative stock shown, never blocking.** A1-2; plus POS widget test that negatives render in red (POS-9).
**S5-4 Concurrent PRODUCE, SALE, ADJUST (QA-6).** Layer: Device. Waits: BE-10.
- Steps: A produces (−RM, +FG), B sells FG, A adjusts RM, all offline, then sync in either order.
- Expected: every item equals the stock oracle; no increment lost.
**S5-5 First use of an item at a location.** Layer: Device and Rules. Waits: BE-10.
- Steps: a product approved today, with no stock doc at PTB, is sold offline on A while B (also offline, with no cached stock doc for it) sells it too; then a PRODUCE of it. Also a first-ever RETURN of an item with no stock doc.
- Expected: both bills accepted; the first `set(merge)` with `increment(−1)` creates the doc at −1, and the second makes it −2; after the PRODUCE, qty = produced − 2; no batch writes a literal `qty`, so it is never reset to 0.
**S5-6 Rename after first use.** Layer: Device and Rules. Waits: BE-4, BE-10, QA-023.
- Steps: FG item X has a stock doc at PTB; the Admin renames product X; the POS (with the new name cached) sells X; also rename a raw material and STOCK_IN it.
- Expected: both batches accepted, and the stock doc's `name` is the new one (02-DATA-MODEL "refreshed on the next write"). Today rule #8 allows `name` to change only on create, so both batches would be rejected (QA-023).

**S6-1 Ledger (§6).** Every bill, return and movement written goes into the ledger and is removed after a server read confirms it. Waits: BE-12.
**S6-2 Rejected write becomes a sync error.** Queue a bill as `uid-sm-off` (disabled while offline) → after sync, `SyncService.errors` lists its path; nothing of its batch is on the server; `lastSyncAt` still moves (A6-8 b). Waits: BE-12.
**S6-3 Status chip.** `SyncService.status` emits `Offline(since)` when the network drops, `Syncing(n)` with the ledger count while flushing, `Online` after. Waits: BE-12.
**S6-4 `lastSeenAt` throttling.** Several passes within 5 minutes update `devices/{id}.lastSeenAt` at most once; the update is allowed for any active user at the location (R-4d). Waits: BE-12.
**S6-5 Pass triggers.** A pass runs on reconnect, on app resume, and every 2 minutes online (fake clock). Waits: BE-12.

**S7-x Offline limit (§7).** A6-1..A6-11.

**S8-1 Offline session (§8).** Sign in online, go offline, restart: session, user, role, location, active products and raw materials are available from cache; billing works. Waits: BE-11, POS-2.
**S8-2 Disabled while offline.** An Admin disables `uid-sm-ptb` while device A is offline with queued bills, a cancel and a return → on sync every queued batch is rejected and shows as a sync error; stock and summaries show none of them. `signIn` for that user now throws `DataFailure(userDisabled)` (it can still read its own user doc, R-1). Waits: BE-2, BE-12.
**S8-3 First sign-in needs the network.** `signIn` offline on a fresh install → `DataFailure(offline)`. Waits: POS-2.

**S9-1 Admin web reads summaries only (§9, D-014).** Review of AD-2 / AD-8 (QA-7): reports use `SummaryRepository`, never bill queries. Layer: review.

---

## R. Security rules (04-PERMISSIONS #1–13)
All Rules layer, on F-1, with one allow and one deny test per line as a minimum. QA hands this list to the backend agent for `firebase/` and reviews it (QA-7).

| # | Scenario | Allow | Deny | Waits |
|---|---|---|---|---|
| R-1 | Default deny | `uid-sm-off` reads its own `users/{uid}` and `roles/*` (so sign-in can report `userDisabled`) | anonymous reads or writes anything; `uid-sm-off` reads anything else or writes anything | BE-2 |
| R-2 | `roles/*` | any signed-in user reads, active or not | any client write, including Admin | BE-2 |
| R-3 | `users/{uid}` | own read (active or not); Admin (`user.manage`) reads and writes all | SM reads another user; SM changes own `roleId`, `locationId` or `active`; SM creates a user | BE-2 |
| R-4 | `locations/{loc}` | active users at the location read; Admin writes every field but `nextDeviceNo`; a new location with `nextDeviceNo == 0`; `device.register` raises it by exactly 1 in the same transaction that creates `devices/D{new value}` | SM @ PTB reads MNJ; SM edits any field; Admin changes `nextDeviceNo` (even to its current value + 1 without a device); +2, −1, or a lower value; a new location with `nextDeviceNo != 0` | BE-2 |
| R-4d | `locations/{loc}/devices/*` | create by `device.register` at `loc` at `D{nextDeviceNo+1}` while not existing; `lastBillSeq` / `lastMovementSeq` / `lastReturnSeq` raised by a user with `bill.create` / `stock.move` or `stock.adjust` / `return.create`; `lastSeenAt` by any active user at `loc`; `label` / `retired` with `location.manage`; read with `device.register` or `location.manage` | create at an existing code; create at a code that isn't the new `nextDeviceNo`; create at MNJ as SM @ PTB; any `last*Seq` lowered; `label` or `retired` by an SM; any write by `uid-sm-off` | BE-2, QA-029 |
| R-5a | Bill create | SM @ PTB creates a valid bill at PTB | without `bill.create`; at MNJ; delete by anyone; a second create on the same path | BE-3 |
| R-5b | Bill cancel | COMPLETED→CANCELLED with `bill.cancel`, `cancel.businessDate == businessDate`, `cancel.by == auth.uid`, empty `returnedQty`, and the CANCEL movement and `auditLog/{loc}-{billId}-X` in the batch | a different `cancel.businessDate`; another user as `cancel.by`; CANCELLED→COMPLETED; a cancel that also changes `total`, `lines` or `payments`; a cancel of a bill with any `returnedQty` (D-025, D-029); a cancel without its movement or audit doc | BE-3 |
| R-5c | `returnedQty` | increments with `return.create`, `lastReturnId` naming a return created in the same batch, each value ≤ `soldQty` | a decrement; an increment without a new return doc; a `lastReturnId` naming an existing return; any increment on a CANCELLED bill (D-029); any value above `soldQty` (D-029); a key not in `soldQty`; a change to `soldQty` | BE-3 |
| R-6 | Bill validation | a valid bill with 1, 2, 3 and 4 payments, and with 1 and 20 lines | `total % 100 != 0`; 5 payments; Σ payments ≠ total for each of 1–4 entries; 21 lines; a `soldQty` missing a line, with an extra key or a wrong qty; a non-empty `returnedQty`; status CANCELLED on create; `billNo != loc-billId`; `createdBy != auth.uid` | BE-3 |
| R-7 | Returns and movements | create at own location with the matching permission when the path is new; a return with 1–4 refunds summing to a whole-rupee `refundTotal` | a second create on the same path; update; delete; without `return.create` / `stock.move` / `stock.adjust`; `createdBy != auth.uid`; 21 lines; a return with 5 refunds, Σ refunds ≠ `refundTotal`, a non-whole `refundTotal`, or `billNo != loc-billId` | BE-4, QA-029 |
| R-8 | `stock/{itemKey}` | `set(merge)` with `qty: increment(delta)` creating or updating the doc, with `lastMovementId` naming a movement that did not exist before the batch and does after; `lowThreshold` change with `stock.threshold` | a qty change with no movement; a qty change naming an old movement (`!exists` fails); a change to `kind`, `refId` or `unit` after create; `lowThreshold` without `stock.threshold`; any other field | BE-4, QA-023 |
| R-9 | Summaries | increments whose `lastWriteRef` is a doc created in the same batch | no `lastWriteRef`; a `lastWriteRef` to a doc that already existed; a `lastWriteRef` to a doc not written in the batch | BE-5 |
| R-10 | `auditLog` | create with `by == auth.uid` at `{loc}-{entityId}`; Admin reads | update or delete; `by` of another user; SM reads; an ADJUST, WASTAGE_*, cancel or return batch without `auditLog/{loc}-{same id}`; the same batch naming the unprefixed ID | BE-5 |
| R-11 | `products` | any `catalog.view` reads; SM creates PENDING with `scope == PTB`; Admin creates, prices, approves | SM creates PENDING scoped to MNJ or GLOBAL; SM creates ACTIVE; SM changes a price or status | BE-5 |
| R-12 | `expenses` | Admin creates, edits, reads | SM reads or writes | BE-5 |
| R-13 | Cross-location | — | A3-1, A3-2, A3-3 | BE-6 |
| R-14 | Rules access budget (D-030) | a 20-line bill with 4 payments, a 20-line return with 4 refunds, and a 20-line PRODUCE are each accepted on the emulator | — | BE-6 |
| R-15 | Reads per subcollection | stock with `catalog.view` at `loc`; movements with `stock.move`, `stock.adjust` or `report.own`; bills and returns with `report.own`, `bill.create` or `return.create`; summaries with `report.own`; devices with `device.register` or `location.manage`; Admin (`allLocations`) reads every location | each of these without the permission, and at another location | BE-6 |

---

## M. Money and decision rules
Mostly covered by the core unit tests (C-3) and by P-01; the rows here are what the end-to-end layers add.

| # | Rule | Scenario | Layer | Status |
|---|---|---|---|---|
| M-1 | D-010 round-off | Every bill total is whole rupees and `total == taxableValue + roundOff` | Dart | Written (P-01) |
| M-2 | D-011 cap | A discount over MNJ's 20% cap, flat or %, is refused before anything is written | Dart; Device with POS-5 | Written (P-01) |
| M-3 | D-024 (c), (d) | Per-line nets add up to the net; cumulative refunds equal the rounded value returned and never exceed the total | Dart | Written (P-01) |
| M-4 | D-012 | A return of a September bill processed in October counts in October only | Dart; Device (P-02) | Written (P-01) |
| M-5 | D-009, D-025, D-029 | Cancel after a return is refused by `cancelBlocker` (Dart) and by rule #5(a) (Rules); cancel vs return offline is A1-6; two devices cancelling the same bill offline: one succeeds, the other becomes a sync error. Next-day cancel is client-only (C-2) | Dart, Rules, Device | P-01 and A1-6 Dart written; rest waits BE-3, BE-12 |
| M-6 | Over-return | Refused by `ReturnCalculator` (Dart); A1-7 on the server (`soldQty`, D-029); A1-8 (QA-024) | Dart, Device | Dart written; Device waits BE-10, BE-12 |
| M-7 | D-008 | Client-only (D-031): see C-1 | Device | Waits BE-10, BE-11 |
| M-8 | D-013 | `taxLines` is empty on every bill; no GST block on any receipt | Dart (P-01), Device (A4) | Partly written |
| M-9 | D-030 list limits | `BillCalculator.compute` refuses 21 lines (`BillError.tooManyLines`); `checkPayments` refuses 5 payments; `checkRefunds` refuses 5 refunds (`RefundError.tooManyRefunds`); the stock service refuses a 21-line movement; the POS cart stops at 20 items with the `tooManyLines` message (QA-027) | Dart (P-01 for bills), Device, POS widget test | Bills written; rest waits BE-10, POS |

## C. Client-enforced rules (D-031)
The rules can't check these, so each is proven on the device, and the Rules layer proves only what the server does check.

| # | Rule | Scenario | Layer | Waits |
|---|---|---|---|---|
| C-1 | D-008 unsellable products | A PENDING or INACTIVE product is not in `CatalogRepository.watchSellable`, and `SalesService.createBill` with it throws before writing. A bill written straight to Firestore with a PENDING product's ID is accepted by the rules (documented, not a failure) | Device; Rules (the accepted write) | BE-10, BE-11 |
| C-2 | D-009 same-day cancel | On the device, `cancelBlocker(bill, today)` is `differentDay` for yesterday's bill and `SalesService.cancelBill` throws `DataFailure(ruleViolation)` without writing. In the rules, only `cancel.businessDate == businessDate` is checked (R-5b) | Dart (P-01 written); Device | BE-10 |
| C-3 | The device clock | Moving the clock back resets the offline timer; reports can flag bills whose `clientCreatedAt` and `serverCreatedAt` differ by more than the limit (03-SYNC §7). Recorded in the pilot checklist, not automated | Manual (QA-8) | — |
| C-4 | Override PIN | A6-11 (8-digit minimum); the hash is readable at the location (R-4 allows the read), accepted for the pilot | Device, Rules | BE-11 |

---

## Traceability
| Source | Scenarios |
|---|---|
| 01 acceptance #1 | A1-1..A1-8, S5-1, S5-5, S5-6 |
| 01 acceptance #2 | A2-1..A2-6, S4-1..S4-3 |
| 01 acceptance #3 | A3-1..A3-4, R-13 |
| 01 acceptance #4 | A4-1..A4-6 |
| 01 acceptance #5 | P-01..P-04, M-1..M-4 |
| 01 acceptance #6 | A6-1..A6-11 |
| 03 §1 | S1-1 |
| 03 §2 | S2-1..S2-7 |
| 03 §3 | S3-1..S3-5 |
| 03 §4 | S4-1..S4-3 |
| 03 §5 | S5-1..S5-6 |
| 03 §6 | S6-1..S6-5 |
| 03 §7 | A6-1..A6-11, C-3 |
| 03 §8 | S8-1..S8-3 |
| 03 §9 | S9-1 |
| 04 #1–#13 | R-1..R-13, R-4d, R-15 (+ R-14 for the access budget note) |
| 04 "Enforced on the client only", D-031 | C-1..C-4 |
| D-028 audit IDs | A1-5, S2-2..S2-5, R-10, A6-4 |
| D-029 first to sync wins | A1-6..A1-8, M-5, M-6, P-01 |
| D-030 list limits | M-9, R-6, R-7, R-14, P-01 |

## Not in this plan
Screen-level behaviour of the in-scope features (catalog browsing, stock screens, reports layout, audit viewer filters) is covered by each app agent's widget tests and reviewed under QA-7. Device-only checks (Bluetooth pairing, paper, a real reboot) go into the QA-8 pilot checklist.
