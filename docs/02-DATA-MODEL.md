# Firestore Data Model

Conventions:
- Money is `int` **paise**. Quantities are `int` in **base units** (D-006).
- Timestamps: `clientCreatedAt` (device time, Timestamp) and `serverCreatedAt` (`FieldValue.serverTimestamp()`).
- `businessDate` is a `"YYYY-MM-DD"` string in IST (D-022).
- Enums are stored as UPPER_SNAKE strings.
- Every write carries `createdBy: uid`, and device writes also carry `deviceId`.
- `{loc}` = the location ID, which is the same as the location code (e.g. `PTB`): 2–4 uppercase letters, and it never changes.

```
roles/{roleId}
users/{uid}
locations/{loc}
  devices/{deviceId}
  stock/{itemKey}
  movements/{movementId}
  bills/{billId}
  returns/{returnId}
  dailySummary/{YYYY-MM-DD}
  monthlySummary/{YYYY-MM}
products/{productId}
rawMaterials/{materialId}
expenses/{expenseId}
auditLog/{auditId}
```

---

## roles/{roleId}
| Field | Type | Notes |
|---|---|---|
| name | string | "Admin", "Store Manager" |
| permissions | string[] | See `04-PERMISSIONS.md` |
| allLocations | bool | true = not scoped to one location |

Seed data: `ADMIN`, `STORE_MANAGER`. Only the seeding script writes these. There is no UI for them in the MVP.

## users/{uid}
| Field | Type | Notes |
|---|---|---|
| name | string | |
| email | string | |
| roleId | string | → roles |
| locationId | string \| null | null only when the role has `allLocations` |
| active | bool | false = every operation is denied |
| createdAt, createdBy | | |

## locations/{loc}
| Field | Type | Notes |
|---|---|---|
| code | string | Same as the doc ID, e.g. `PTB` |
| name, address, phone | string | Printed on the receipt |
| gstin | string \| null | Reserved |
| offlineLimitHours | int | Default 5 |
| overridePinHash | string | PBKDF2-SHA256, 100k iterations, `salt$hash` base64 |
| overrideExtensionHours | int | Default 2 |
| maxDiscountPct | int \| null | null = no cap |
| receiptFooter | string | e.g. "Thank you! Visit caramelcottage.in" |
| nextDeviceNo | int | The last device number handed out. 0 for a new location. Registration increments it by exactly 1 in a transaction and creates `D{new value}`. Nothing else writes it (D-004) |
| active | bool | |

### locations/{loc}/devices/{deviceId}
`deviceId` = the device code, e.g. `D01`.
| Field | Type | Notes |
|---|---|---|
| code | string | `D01` |
| label | string | e.g. "Counter 1 – Redmi" |
| registeredBy, registeredAt | | |
| lastSeenAt | Timestamp | Updated on each successful server round trip, at most once every 5 minutes |
| lastBillSeq, lastMovementSeq, lastReturnSeq | int | Updated in the same batch as each bill, movement or return. They only go up, and they recover the local counters (03-SYNC §3) |
| retired | bool | |

### locations/{loc}/stock/{itemKey}
`itemKey` = `RM_{materialId}` for raw materials, `FG_{productId}` for finished goods.
| Field | Type | Notes |
|---|---|---|
| kind | `RAW` \| `FINISHED` | |
| refId | string | materialId or productId |
| name | string | Copied from the product or material. Refreshed on every write, so a rename shows up on the next sale or movement |
| unit | `G` \| `ML` \| `PCS` | |
| qty | int | **Written only with `increment()`**, never a literal value |
| lowThreshold | int \| null | Set by the SM |
| lastMovementId | string | The movement written in the same batch. The rules check it (see `04-PERMISSIONS.md` #8) |
| updatedAt | Timestamp | |

Every write is `set(..., merge: true)` with `qty: increment(delta)`. The first use at a location creates the doc (an increment on a missing field starts from 0), and a device that doesn't have the doc cached can never reset another device's quantity (D-005). `kind`, `refId`, `name` and `unit` are written with it.

### locations/{loc}/movements/{movementId}
`movementId` = `{deviceId}-M{seq:6}` (e.g. `D01-M000042`), using a separate per-device movement counter. For movements caused by a bill, return or cancellation, the ID is `{billId}` / `{returnId}` / `{billId}-X`.
| Field | Type | Notes |
|---|---|---|
| type | enum | `STOCK_IN`, `STOCK_OUT_RAW`, `WASTAGE_RAW`, `PRODUCE`, `WASTAGE_FG`, `ADJUST`, `SALE`, `RETURN`, `CANCEL` |
| lines | `[{itemKey, delta:int, before?:int, after?:int}]` | At most 20 (D-030). `before`/`after` are only set on ADJUST, taken from the device's local view |
| reason | string \| null | Required for WASTAGE_*, ADJUST and CANCEL |
| note | string \| null | Free text, e.g. the supplier on a STOCK_IN |
| refId | string \| null | billId or returnId |
| businessDate, clientCreatedAt, serverCreatedAt, createdBy, deviceId | | |

PRODUCE example: `lines: [{RM_cakemix, -1000}, {RM_cream, -500}, {FG_bf1kg, +2}]`. A future recipe/BOM feature only has to fill these lines in automatically, so the model doesn't change.

### locations/{loc}/bills/{billId}
`billId` = `{deviceId}-{seq:6}`, e.g. `D01-000123`. `billNo` = `{loc}-{billId}`.
| Field | Type | Notes |
|---|---|---|
| billNo | string | `PTB-D01-000123` |
| deviceId, seq | string, int | |
| lines | `[{productId, name, qty, unitPrice, lineTotal}]` | `name` and `unitPrice` are copied at the time of sale. At most one line per product (D-024) |
| subtotal | int | Σ lineTotal |
| discount | `{type: FLAT\|PCT, value:int, amount:int}` \| null | `value` is paise for FLAT, whole % for PCT |
| taxableValue | int | subtotal − discount.amount |
| taxLines | `[{rate, taxable, cgst, sgst}]` | Empty in the MVP |
| roundOff | int | May be negative |
| total | int | taxableValue + Σtax + roundOff, always a multiple of 100 |
| payments | `[{mode, amount, ref?}]` | Σamount == total. At most 4 entries. Modes: `CASH`, `UPI`, `CARD`, `WALLET`, `OTHER` |
| cashTendered | int \| null | For showing change only |
| status | `COMPLETED` \| `CANCELLED` | |
| cancel | `{reason, by, at, businessDate}` \| null | `businessDate` must equal the bill's own (the same-day rule) |
| soldQty | map productId → int | The qty of each line, written at creation so the rules can cap returns (D-029) |
| returnedQty | map productId → int | Starts empty. Incremented by returns, never with 0. Must stay ≤ `soldQty` |
| lastReturnId | string \| null | The return that last raised `returnedQty`, written in the same batch |
| servedBy | `{uid, name}` | |
| businessDate, clientCreatedAt, serverCreatedAt | | |

### locations/{loc}/returns/{returnId}
`returnId` = `{deviceId}-R{seq:6}` (e.g. `D01-R000007`), using a separate per-device return counter.
| Field | Type | Notes |
|---|---|---|
| billId, billNo | string | |
| lines | `[{productId, name, qty, amount}]` | `amount` is prorated from the line's share of the bill's net amount, cumulatively (D-024) |
| refundTotal | int | Whole rupees, rounded cumulatively so a bill's refunds add up to its total (D-024) |
| refunds | `[{mode, amount}]` | Σ == refundTotal. Any mix of modes |
| reason | string | |
| prevReturnId | string \| null | The bill's `lastReturnId` when this return was worked out; null for the first. The rules reject a stale one (D-029) |
| businessDate, createdBy, deviceId, clientCreatedAt, serverCreatedAt | | |

Before creating a return, the client checks that `bill.returnedQty[p] + qty ≤ sold qty`. `ReturnCalculator` in `packages/core` does this and all the return arithmetic.

### locations/{loc}/dailySummary/{YYYY-MM-DD} and monthlySummary/{YYYY-MM}
Same shape for both. Every numeric field is written **only with `increment()`**.
| Field | Type |
|---|---|
| billCount, cancelCount, returnCount | int |
| grossSales | int — Σ subtotal |
| discounts | int |
| roundOff | int |
| netSales | int — Σ total of bills **created** that day, including ones cancelled later |
| returns | int — Σ refundTotal |
| cancelled | int — Σ total of bills cancelled that day |
| byMode | map mode → int (net payments minus refunds) |
| byProduct | map productId → `{qty:int, amount:int}` — `amount` is net of the bill discount (D-024) |
| expenses | int (monthly only) |
| byExpenseCategory | map category → int (monthly only) |
| lastWriteRef | string — full path (from the database root) of the *new* doc created in the same batch: the bill, return, CANCEL movement (`{billId}-X`) or expense audit doc. The rules check it (`04-PERMISSIONS.md` #9) |

Net revenue for a period = `netSales − returns − cancelled`. Profit = that figure − `expenses`.

`grossSales`, `discounts`, `roundOff`, `billCount` and `netSales` are **as billed**: a cancellation doesn't reverse them; it adds to `cancelled` and `cancelCount`. `byMode` and `byProduct` are net of cancellations and returns. Reports show **net revenue** as the headline "Sales" figure, with cancellations and returns as their own lines.

## products/{productId}
| Field | Type | Notes |
|---|---|---|
| name, category | string | |
| price | int \| null | null while pending |
| proposedPrice | int \| null | Set by the SM when suggesting |
| unit | `PCS` | Always PCS in the MVP |
| gstRate | int \| null | Reserved (5, 12, 18) |
| scope | `GLOBAL` \| `{loc}` | Local specials use the location code |
| status | `ACTIVE` \| `PENDING` \| `INACTIVE` | |
| recipe | `[{materialId, qty}]` \| null | Reserved for BOM |
| sortOrder | int | |
| createdBy, createdAt, updatedAt | | |

## rawMaterials/{materialId}
`name`, `unit` (`G`/`ML`/`PCS`), `active`, `createdBy`. Any user with `rawMaterial.create` can add one.

## expenses/{expenseId}
| Field | Type |
|---|---|
| locationId | string |
| category | `RENT` \| `SALARY` \| `UTILITIES` \| `OTHER` |
| amount | int |
| date | `YYYY-MM-DD` |
| note | string |
| createdBy, createdAt, updatedAt | |

When an expense is edited, `monthlySummary.expenses` is incremented by (new − old) in the same batch.

## auditLog/{auditId}
`auditId` for a location-scoped event = `{loc}-{entityId}` (`Ids.auditId`), because device codes repeat across locations (D-028): `PTB-D01-000123-X` for a cancellation, `PTB-D01-R000007` for a return, `PTB-D01-M000042` for a wastage or adjust. An offline override is `{loc}-{deviceId}-OVR-{millis}` with `entityPath` = the device doc. An expense create or edit is `EXP-{id}-{millis}`.
| Field | Type |
|---|---|
| action | `STOCK_ADJUST`, `WASTAGE`, `BILL_CANCEL`, `RETURN`, `EXPENSE_CREATE`, `EXPENSE_UPDATE`, `PRICE_CHANGE`, `PRODUCT_APPROVE`, `USER_CREATE`, `USER_DISABLE`, `OFFLINE_OVERRIDE`, `THRESHOLD_CHANGE`, `LOCATION_UPDATE` |
| entityPath | string |
| locationId | string \| null |
| before, after | map \| null |
| reason | string \| null |
| by | uid |
| deviceId | string \| null |
| at | serverTimestamp |
| clientAt | Timestamp |

## Indexes (initial)
- `bills`: `businessDate DESC, clientCreatedAt DESC`
- `auditLog`: `locationId ASC, at DESC`, and `action ASC, at DESC`
- `expenses`: `locationId ASC, date DESC`
- `products`: `status ASC, sortOrder ASC`
