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
| `staff.manage` | Create and edit the staff roster of any location (D-042) |
| `attendance.mark` | Mark staff attendance at your own location (D-042) |
| `order.manage` | Take, deliver and cancel pre-orders at your own location (D-043) |

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
| staff.manage | ✓ | | |
| attendance.mark | ✓ | ✓ | |
| order.manage | ✓ | ✓ | |

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
**Budgets.** Firestore allows 10 document-access calls (`get`, `exists`, `getAfter`, `existsAfter`) per single-document request and 20 per batch, and repeated calls to the same document are counted once. `me()` and `role()` cost 2. It also stops a rule evaluation after 1000 evaluated expressions, per document (CR-001). Every batch stays within both because list sizes are capped (D-030): at most 15 lines per bill and return, 20 per movement, 4 payments and 4 refunds. BE-6 tests the largest cases (a 15-line bill with 4 payments, a return update that brings all 15 products into `returnedQty`, a 20-line PRODUCE), and CI fails if a change in counting pushes one over.

**Lists without loops.** The rules language has no loops, so every per-line or per-key check is unrolled up to the cap: a helper checks index `i` when `list.size() > i`, for `i` = 0…14 on bills and returns.

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
6. Bill create validation: `total % 100 == 0`, `payments.size() <= 4`, Σpayments == total (spelled out for up to 4 entries), `lines.size() <= 15`, `soldQty` has one key per line with that line's qty (unrolled), `returnedQty.size() == 0`, `status == 'COMPLETED'`, `billNo == loc + '-' + billId`, and `createdBy == request.auth.uid`.
7. `returns` and `movements`: create-only with `!exists`, with the matching permission at the location (`return.create` for returns and RETURN movements; `stock.move` or `stock.adjust` for stock movements; `bill.create` for SALE and `bill.cancel` for CANCEL movements). `createdBy == request.auth.uid` on both, and `lines.size() <= 15` on returns and `<= 20` on movements.
   Return validation: `refundTotal % 100 == 0`, `refunds.size() <= 4`, Σrefunds == `refundTotal` (spelled out), and `billNo == loc + '-' + billId`.
   Return also: `refundTotal <= get(bill).total` (QA-040). Movement ties (QA-038): a SALE movement needs a bill with the same ID that is new in the batch; a RETURN movement a return with the same ID that is new in the batch; a CANCEL movement `{billId}-X` needs that bill to go COMPLETED → CANCELLED in the same batch.
   **read:** returns like bills (#5); movements with `stock.move`, `stock.adjust` or `report.own` at `loc`.
8. `stock/{itemKey}`: batches never write a literal `qty`; it is always `increment(delta)` through `set(merge)`, which also creates the doc on first use (D-005). Create and update may change only `kind`, `refId`, `unit` (these three only on create), `name` (refreshed on any write, so a renamed product or material keeps selling; QA-023), `qty`, `lastMovementId`, `updatedAt`, and `lowThreshold` (which needs `stock.threshold`). Any change to `qty` requires that the movement named in `request.resource.data.lastMovementId` did **not** exist before the batch and **does** after (`!exists` and `existsAfter`).
   **read:** any active user at `loc` with `catalog.view` (the POS low-stock badge and stock hub).
9. Summaries: create or update only when `existsAfter(<doc named by lastWriteRef>)` is true and that doc did **not** exist before (`!exists`). A movement may be named only if it is a CANCEL movement (`{billId}-X`, QA-039). This ties every summary increment to a new bill, return, cancellation or expense doc.
   **read:** `report.own` at `loc`.
10. `auditLog`: create-only, and `by == request.auth.uid`. Reads need `audit.view`. IDs follow D-032 (the table in 02-DATA-MODEL). A location-scoped event must have `locationId` set, its ID must start with `{loc}-`, and the writer needs the action's permission **at that location**. Only PRICE_CHANGE, PRODUCT_APPROVE and user events for a user with no location may have a null `locationId` (QA-037). Permissions by action: STOCK_ADJUST `stock.adjust`, WASTAGE `stock.move`, BILL_CANCEL `bill.cancel`, RETURN `return.create`, OFFLINE_OVERRIDE `bill.create`, EXPENSE_* `expense.manage`, PRICE_CHANGE and PRODUCT_APPROVE `catalog.manage`, USER_* `user.manage`, LOCATION_UPDATE `location.manage`. Movements of type ADJUST and WASTAGE_*, cancellations and returns require `existsAfter(auditLog/{loc}-{same id})`.
11. `products`: reads need `catalog.view`. Creating with status PENDING needs `catalog.suggest` and `scope == me().locationId`. Everything else needs `catalog.manage`.
12. `expenses`: `expense.manage` only.
13. Tests must prove that an SM at `PTB` cannot read or write anything under `locations/MNJ/**`.

15. `locations/{loc}/staff/{staffId}`: create and update need `staff.manage` (the Admin passes every location). Create requires `active` bool, `name` 1–60 chars and `role` string ≤ 30, `createdBy == request.auth.uid` and `createdAt == request.time`; update may change only `name`, `role`, `active`, `updatedBy`, `updatedAt`. No delete. **Read:** `attendance.mark`, `staff.manage` or `report.own` at `loc`, and `report.all`.
16. `locations/{loc}/attendance/{docId}`: create and update need `attendance.mark` at `loc`. The ID must be `{businessDate}_{staffId}` with `data.businessDate` and `data.staffId` equal to its parts, `businessDate` a `YYYY-MM-DD` string, `status` one of PRESENT, ABSENT, HALF_DAY, `note` null or a string ≤ 100, `markedBy.uid == request.auth.uid`, `staffName` a string of 1–60 chars, and `editedAt == request.time`. No delete. The rules do not read the staff document (a batch of 15 marks must stay inside the get() budget) and do not check the date window (D-031). **Read:** `attendance.mark` or `report.own` at `loc`, and `report.all`.
17. Tests for #15 and #16: an SM at `PTB` cannot write the roster, cannot mark at `MNJ`, cannot delete a mark, cannot write a mismatched ID, an unknown status or a note over 100 characters; the Admin can write the roster and read every location's attendance; a batch of 15 marks passes the rules budget.

18. `locations/{loc}/orders/{orderId}`: **create** with `order.manage` at `loc` and `!exists`, the ID equal to `{deviceId}-O{seq:6}` with `deviceId` a registered device code, `orderNo == loc + '-' + orderId`, `status == 'OPEN'`, `billId == null`, no `cancel`, the customer fields as in #6, `description` 1–500 chars, `price` a positive multiple of 100, `advance` a multiple of 100 with `0 ≤ advance ≤ price`, `advanceMode` null exactly when `advance == 0` and otherwise one of CASH, UPI, CARD, WALLET, OTHER, `createdBy == request.auth.uid`, and in the same batch the device's `lastOrderSeq` equal to `seq` (#4). **Update (a) deliver:** `order.manage` plus the order was OPEN, `status` → DELIVERED, `billId` names a bill that is new in the batch (`!exists`, `existsAfter`) whose `orderId` is this order, and only `status`, `billId` and `deliveredAt` change. **Update (b) cancel:** `order.manage`, the order was OPEN, `status` → CANCELLED with a `cancel` map (`reason` 1–100 chars, `by == request.auth.uid`, `refunded` a multiple of 100 with `0 ≤ refunded ≤ advance`) and the audit entry `{loc}-{orderId}-X` created in the batch (`existsAfter`), and only `status` and `cancel` change. A delivered or cancelled order can't change again, and there is no delete. **Read:** `order.manage` or `report.own` at `loc`, and `report.all`.
19. Bill create (#5, #6) also accepts `orderId` (null or a string). When it is set, the order must exist and be OPEN before the batch and DELIVERED after it (`get` and `getAfter`), with `billId` equal to this bill, and `payments` must contain exactly one ADVANCE entry whose amount equals the order's `advance` (skip the entry when the advance is 0, and then none is allowed). The other payment modes are unchanged. An ADVANCE payment is **not** accepted on a bill without `orderId`.
20. Summaries (#9): a summary write may also name a **pre-order** as its `lastWriteRef` when that order is new in the batch (an order created with an advance), or a cancelled one's audit entry `{loc}-{orderId}-X`. `advanceReceived` may only go up by the new order's `advance`; `advanceRefunded` only by the cancel's `refunded`.
21. Tests for #18–#20: an advance above the price (denied), an ADVANCE payment on an ordinary bill (denied), a delivery bill whose ADVANCE entry isn't the order's advance (denied), delivering twice or delivering a cancelled order (denied), a cancel whose refund is above the advance (denied), an SM at `PTB` reading or writing `MNJ` orders (denied), and an order create followed by a delivery in the offline replay fixtures.

`report.all` and `allLocations` roles pass every `atLoc` check, so the Admin reads every location with the permissions above.

## Enforced on the client only (accepted for the pilot, D-031)
The rules can't check these, so they are client-side and visible in reports:
- A PENDING or inactive product can't be sold (D-008). The rules can't read product docs per bill line within budget.
- Same-day cancellation (D-009). The rule keeps `cancel.businessDate` equal to the bill's own, but both dates come from the client.
- The device clock (03-SYNC §7).
- The override PIN hash is readable by anyone at the location, so it can be guessed offline. PINs are at least 8 digits (`Limits.minOverridePinDigits`) to make that slow.
