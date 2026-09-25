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
(These two `get()` calls count towards the 10-doc limit per rules evaluation. Batches must stay within it, and rules tests must cover the largest batch, which is a return.)

## Rules — required behaviour (the backend agent writes a test for each)
1. **Default deny.** Nothing is readable without an active user.
2. `roles/*`: read by any signed-in user. No client writes.
3. `users/{uid}`: a user can read their own doc, and `user.manage` can read and write all of them. Users cannot change their own `roleId`, `locationId` or `active`.
4. `locations/{loc}`: readable by users at that location. Writable only with `location.manage`, except `nextDeviceNo`, which `device.register` may increment by exactly 1.
5. `bills`: **create-only**, with `canAt('bill.create', loc)`. Update is allowed only for (a) `status` COMPLETED→CANCELLED plus `cancel`, with `bill.cancel` and `businessDate == request.resource.data.cancel.businessDate`, or (b) `returnedQty` increments with `return.create`. No delete.
6. Bill validation: `total % 100 == 0`, `payments.size() <= 4`, Σpayments == total (spelled out for up to 4 entries), `billNo == loc + '-' + billId`, and `createdBy == request.auth.uid`.
7. `returns`, `movements`: create-only, with `!exists()`, with the matching permission at the location.
8. `stock/{itemKey}`: create with `qty == 0`. Updates may change only `qty`, `name`, `updatedAt`, and `lowThreshold` (which needs `stock.threshold`). A change to `qty` requires `existsAfter` of a movement whose ID is in `request.resource.data.lastMovementId`. *(The stock doc gets the field `lastMovementId: string`, which is set in the same batch.)*
9. Summaries: create or update only when `existsAfter(<doc named by lastWriteRef>)` is true and that doc did **not** exist before (`!exists`). This ties every summary increment to a new bill, return, cancellation or expense doc.
10. `auditLog`: create-only, and `by == request.auth.uid`. Reads need `audit.view`. Movements of type ADJUST and WASTAGE_*, cancellations and returns require `existsAfter(auditLog/<same id>)`.
11. `products`: reads need `catalog.view`. Creating with status PENDING needs `catalog.suggest` and `scope == me().locationId`. Everything else needs `catalog.manage`.
12. `expenses`: `expense.manage` only.
13. Tests must prove that an SM at `PTB` cannot read or write anything under `locations/MNJ/**`.
