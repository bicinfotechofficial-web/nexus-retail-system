# Sync & Offline Protocol

The POS app must work without network for hours, with **several devices at the same location**, and without a server-side function (D-001). This file defines how that works.

## 1. The offline queue is Firestore's own
- Firestore offline persistence is enabled, with `cacheSizeBytes = 100 MB`.
- All writes go through `WriteBatch`. The SDK stores pending batches on disk, keeps them through app kills and reboots, and applies each batch **exactly once** when the device is back online.
- **We do not build our own outbox.** We do keep a small local ledger (§6) so that we can *verify* the sync.

## 2. Every business operation is one atomic batch
| Operation | Docs in the batch |
|---|---|
| Create bill | bill (create) · stock `FG_*` increments (−qty) · SALE movement · dailySummary + monthlySummary increments · device `lastBillSeq` |
| Cancel bill | bill (update status → CANCELLED) · stock increments (+qty) · CANCEL movement · summary increments (cancelled, byMode −, byProduct −) · audit |
| Return | return (create) · bill `returnedQty` increments · stock increments (+qty) · RETURN movement · summary increments · audit |
| Stock in / out / wastage / produce | movement (create) · stock increments · audit (wastage only) |
| Adjust (physical count) | movement with before/after · stock increment by (counted − localQty) · audit |
| Expense create/edit | expense · monthlySummary increment · audit |

A batch either lands completely or not at all. Neither the summaries nor the stock can drift away from the documents they are derived from.

## 3. Bill numbering without collisions (D-003, D-004)
1. **Device registration** (online only): in a transaction, read `locations/{loc}.nextDeviceNo`, increment it, and create `devices/D{nn}`. Store `deviceId` locally.
2. **Per-device counters**: `billSeq`, `movementSeq` and `returnSeq` are stored in a local durable key-value store (Hive box, flushed after every write).
3. **Allocating a number**: increment the counter and **persist it before building the batch**. If the app is killed after that point, a number is skipped, which is acceptable. A number is never used twice.
4. **Recovering the counter** on app start: `billSeq = max(local, devices/{id}.lastBillSeq from cache or server)`.
5. **Reinstalling** gives a new device code, never the old one.

Result: bill IDs are unique across the whole system with no coordination, and two offline devices can never clash.

## 4. Idempotency — no double bills, no double stock
- Doc IDs are deterministic (`D01-000123`), so a retry writes the same doc.
- The rules allow **create** on bills, returns and movements only when the doc doesn't exist yet (`!exists(path)`). A duplicate submission makes the *whole batch* fail, so its stock and summary increments are never applied twice.
- The UI disables Save as soon as it's tapped, and the batch is built only once for each allocated number.

## 5. Stock never overwrites (D-005)
- `qty` is only ever changed with `FieldValue.increment(delta)`. Two offline devices selling the same cake → both −1 → the result is −2 after sync. This is correct.
- An **Adjust** is recorded as a delta from the device's *local* view: `delta = counted − localQty`. If another device sold an item offline during the count, the final quantity is off by that sale. This is accepted, and we recommend doing counts while the device is online. The before/after values are stored for audit.
- Stock may go **negative** (for example, if two devices both sell the last piece). The app shows negative stock in red and does not block the sale. The shop sells what is physically on the counter.

## 6. Sync health & verification
The local ledger (Hive box `pending`) holds `{path, createdAt}` for every bill, return and movement written.
- **Sync pass** (on connectivity regained, on app resume, and every 2 minutes while online):
  1. `await firestore.waitForPendingWrites()` (timeout 30 s).
  2. For each ledger entry, run `get(GetOptions(source: Source.server))`. If the doc exists, remove it from the ledger.
  3. If a doc is **missing** after the pending writes flushed, the server rejected it: show it as a **Sync error** on the sync-health screen with the bill details so the SM can re-enter it. This should never happen, and each one is treated as a bug.
  4. On success, set `lastSyncAt = now` (local) and update `devices/{id}.lastSeenAt` (at most every 5 minutes).
- UI: a status chip in the app bar showing ● Online / ◐ Syncing (n pending) / ○ Offline since HH:MM.

## 7. Offline limit (D-016)
- `elapsed = now − lastSyncAt`. `limit = location.offlineLimitHours` (cached, default 5).
- `elapsed ≥ 0.8 × limit`: a persistent amber banner, "Connect to internet — billing will stop in X min".
- `elapsed ≥ limit`: **billing is blocked**. Stock operations and viewing still work. The block screen offers:
  - **Retry sync**
  - **Admin PIN override**: the entered PIN is verified locally against the cached `overridePinHash` (PBKDF2). On success, `lastSyncAt` is treated as extended by `overrideExtensionHours`, and an `OFFLINE_OVERRIDE` audit doc is queued.
- Known limitation: someone can move the device clock back to get around the block. This is accepted for the pilot. Reports can flag bills where `clientCreatedAt` and `serverCreatedAt` differ by more than the limit.

## 8. Auth while offline
- The first login on a device needs network. Firebase Auth keeps the session afterwards.
- `users/{uid}`, `roles/*`, `locations/{loc}`, the active products and the raw materials are pre-fetched at login and kept fresh with snapshot listeners, so they're always in the cache.
- If a user is disabled while a device is offline, their queued writes will be **rejected** on sync (the rules check `active`). This shows up as sync errors, which is the correct outcome.

## 9. Admin web
- Online only. Firestore persistence is left off on web in the MVP.
- Admin reads summaries for reports (D-014), and `stock/*` for low-stock lists (a snapshot listener per location).
- **Read budget (Spark: 50k/day):** one pilot store uses a small fraction of it. At 20 stores, the admin low-stock view (~20 × 150 stock docs) is the biggest cost. Before scaling out, move it to a per-location `lowStock` summary doc or to Blaze.
