# Roles, Permissions & Security Rules Contract

The permissions are the contract. The UI hides actions the user doesn't have permission for, and **Firestore rules enforce the same permissions on the server** (BRD §9). Code checks permission strings and never role names (D-017).

## Permission catalogue
| Permission | Meaning |
|---|---|
| `catalog.view` | Read active products and raw materials |
| `catalog.suggest` | Create a PENDING product scoped to your own location |
| `catalog.manage` | Create and edit any product, set prices, approve and deactivate products |
| `rawMaterial.create` | Add a raw material |
| `bill.create` | Create bills |
| `bill.cancel` | Cancel a same-day bill |
| `return.create` | Create returns |
| `stock.move` | Stock in, stock out, produce, wastage |
| `stock.adjust` | Physical-count adjustment |
| `stock.threshold` | Set `lowThreshold` |
| `report.own` | Read your own location's summaries, bills and returns |
| `report.all` | Read every location |
| `expense.manage` | Create and edit expenses |
| `audit.view` | Read the audit log |
| `user.manage` | Create and disable users |
| `location.manage` | Create and edit locations and devices |
| `device.register` | Register this device for your own location |

## Role matrix
| Permission | ADMIN | STORE_MANAGER | *CASHIER (future)* |
|---|:-:|:-:|:-:|
| catalog.view | ✓ | ✓ | ✓ |
| catalog.suggest | ✓ | ✓ | |
| catalog.manage | ✓ | | |
| rawMaterial.create | ✓ | ✓ | |
| bill.create | ✓ | ✓ | ✓ |
| bill.cancel | ✓ | ✓ | |
| return.create | ✓ | ✓ | |
| stock.move | ✓ | ✓ | |
| stock.adjust | ✓ | ✓ | |
| stock.threshold | ✓ | ✓ | |
| report.own | ✓ | ✓ | |
| report.all | ✓ | | |
| expense.manage | ✓ | | |
| audit.view | ✓ | | |
| user.manage | ✓ | | |
| location.manage | ✓ | | |
| device.register | ✓ | ✓ | ✓ |

`ADMIN.allLocations = true`. Every other role is scoped to `users/{uid}.locationId`.

## Rules — required helper functions
```
function me()            { return get(/databases/$(database)/documents/users/$(request.auth.uid)).data; }
function role()          { return get(/databases/$(database)/documents/roles/$(me().roleId)).data; }
function active()        { return request.auth != null && me().active == true; }
function can(p)          { return active() && p in role().permissions; }
function atLoc(loc)      { return role().allLocations == true || me().locationId == loc; }
function canAt(p, loc)   { return can(p) && atLoc(loc); }
```
**Access-call budget.** Firestore allows 10 document-access calls (`get`, `exists`, `getAfter`, `existsAfter`) per single-document request and 20 per batch, and repeated calls to the same document are counted once. `me()` and `role()` cost 2. Every batch stays within budget because list sizes are capped (D-030): at most 20 lines per bill, return or movement, 4 payments and 4 refunds. BE-6 tests the largest batches (a 20-line bill, a 20-line return, a 20-line PRODUCE) and must confirm the counting on the emulator.

**Lists without loops.** The rules language has no loops, so every per-line or per-key check is unrolled up to the cap: a helper checks index `i` when `list.size() > i`, for `i` = 0…19.

## Rules — required behaviour (the backend agent writes a test for each)
1. **Default deny.** Nothing is readable or writable without an active user, except #2 and #3's own-doc reads.
2. `roles/*`: read by any signed-in user, active or not. No client writes.
3. `users/{uid}`: a signed-in user can always read their own doc, even when inactive, so sign-in can tell `userDisabled` from `noProfile`. `user.manage` can read and write all of them. Users can't change their own `roleId`, `locationId` or `active`.
4. `locations/{loc}`: readable by active users at that location. Writable with `location.manage`, except `nextDeviceNo`: no one may change it except `device.register` at that location, by exactly +1, in the same transaction that creates `devices/D{new value}`. A new location is created with `nextDeviceNo == 0`.
   `locations/{loc}/devices/{deviceId}`:
   - **create:** `device.register` at `loc`, only if it doesn't exist, with `getAfter(location).data.nextDeviceNo == get(location).data.nextDeviceNo + 1`, the new value ≤ 99, and the ID equal to `D` plus that new value in 2 digits.
   - **update `lastBillSeq`, `lastMovementSeq`, `lastReturnSeq`:** any active user at `loc` with `bill.create`, `stock.move` or `stock.adjust`, or `return.create` respectively; each may only go up.
   - **update `lastSeenAt`:** any active user at `loc`.
   - **update `label`, `retired`:** `location.manage`.
   - **read:** `device.register` or `location.manage` at `loc`.
5. `bills`: **create-only** with `!exists`, with `canAt('bill.create', loc)`. No delete. Two kinds of update, and nothing else may change:
   - **(a) cancel:** `status` COMPLETED → CANCELLED plus `cancel`, with `bill.cancel`. Requires `resource.data.returnedQty.size() == 0` (D-025), `cancel.businessDate == businessDate`, `cancel.by == request.auth.uid`, and `existsAfter` of both the CANCEL movement `{billId}-X` and the audit doc `auditLog/{loc}-{billId}-X`.
   - **(b) return:** only `returnedQty` and `lastReturnId` change, with `return.create`. Requires `resource.data.status == 'COMPLETED'`, `lastReturnId` names a return that did not exist before the batch (`!exists`) and does after (`existsAfter`), that return's `prevReturnId` equals the bill's current `lastReturnId` (`getAfter(return).data.prevReturnId == resource.data.lastReturnId`, both null for the first return), and for each key in `returnedQty` (unrolled): the value only grows, and `returnedQty[p] <= soldQty[p]`. The `prevReturnId` check rejects a return worked out from an out-of-date bill, so two offline returns can't over-refund (QA-024).
   Whichever of a cancel and a return syncs second is rejected and becomes a sync error (D-029).
   **read:** `report.own`, `bill.create` or `return.create` at `loc`.
6. Bill create validation: `total % 100 == 0`, `payments.size() <= 4`, Σpayments == total (spelled out for up to 4 entries), `lines.size() <= 20`, `soldQty` has one key per line with that line's qty (unrolled), `returnedQty.size() == 0`, `status == 'COMPLETED'`, `billNo == loc + '-' + billId`, and `createdBy == request.auth.uid`.
7. `returns` and `movements`: create-only with `!exists`, with the matching permission at the location (`return.create` for returns and RETURN movements; `stock.move` or `stock.adjust` for stock movements; `bill.create` for SALE and `bill.cancel` for CANCEL movements). `createdBy == request.auth.uid` and `lines.size() <= 20` on both.
   Return validation: `refundTotal % 100 == 0`, `refunds.size() <= 4`, Σrefunds == `refundTotal` (spelled out), and `billNo == loc + '-' + billId`.
   **read:** returns like bills (#5); movements with `stock.move`, `stock.adjust` or `report.own` at `loc`.
8. `stock/{itemKey}`: batches never write a literal `qty`; it is always `increment(delta)` through `set(merge)`, which also creates the doc on first use (D-005). Create and update may change only `kind`, `refId`, `unit` (these three only on create), `name` (refreshed on any write, so a renamed product or material keeps selling; QA-023), `qty`, `lastMovementId`, `updatedAt`, and `lowThreshold` (which needs `stock.threshold`). Any change to `qty` requires that the movement named in `request.resource.data.lastMovementId` did **not** exist before the batch and **does** after (`!exists` and `existsAfter`).
   **read:** any active user at `loc` with `catalog.view` (the POS low-stock badge and stock hub).
9. Summaries: create or update only when `existsAfter(<doc named by lastWriteRef>)` is true and that doc did **not** exist before (`!exists`). This ties every summary increment to a new bill, return, cancellation or expense doc.
   **read:** `report.own` at `loc`.
10. `auditLog`: create-only, and `by == request.auth.uid`. Reads need `audit.view`. The audit ID of a location-scoped event is `{loc}-{entityId}` (D-028). Movements of type ADJUST and WASTAGE_*, cancellations and returns require `existsAfter(auditLog/{loc}-{same id})`.
11. `products`: reads need `catalog.view`. Creating with status PENDING needs `catalog.suggest` and `scope == me().locationId`. Everything else needs `catalog.manage`.
12. `expenses`: `expense.manage` only.
13. Tests must prove that an SM at `PTB` cannot read or write anything under `locations/MNJ/**`.

`report.all` and `allLocations` roles pass every `atLoc` check, so the Admin reads every location with the permissions above.

## Enforced on the client only (accepted for the pilot, D-031)
The rules can't check these, so they are client-side and visible in reports:
- A PENDING or inactive product can't be sold (D-008). The rules can't read product docs per bill line within budget.
- Same-day cancellation (D-009). The rule keeps `cancel.businessDate` equal to the bill's own, but both dates come from the client.
- The device clock (03-SYNC §7).
- The override PIN hash is readable by anyone at the location, so it can be guessed offline. PINs are at least 8 digits (`Limits.minOverridePinDigits`) to make that slow.
