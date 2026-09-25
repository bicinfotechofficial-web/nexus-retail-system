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
| nextDeviceNo | int | Incremented in a transaction when a device registers |
| active | bool | |

### locations/{loc}/devices/{deviceId}
`deviceId` = the device code, e.g. `D01`.
| Field | Type | Notes |
|---|---|---|
| code | string | `D01` |
| label | string | e.g. "Counter 1 – Redmi" |
| registeredBy, registeredAt | | |
| lastSeenAt | Timestamp | Updated on each successful server round trip, at most once every 5 minutes |
| lastBillSeq | int | Updated in the same batch as each bill. Used to recover the counter (see sync doc) |
| retired | bool | |

### locations/{loc}/stock/{itemKey}
`itemKey` = `RM_{materialId}` for raw materials, `FG_{productId}` for finished goods.
| Field | Type | Notes |
|---|---|---|
| kind | `RAW` \| `FINISHED` | |
| refId | string | materialId or productId |
| name | string | Copied from the product or material. Refreshed on the next write if it was renamed |
| unit | `G` \| `ML` \| `PCS` | |
| qty | int | **Written only with `increment()`**, except when the doc is created |
| lowThreshold | int \| null | Set by the SM |
| lastMovementId | string | The movement written in the same batch. The rules check it (see `04-PERMISSIONS.md` #8) |
| updatedAt | Timestamp | |

The doc is created with `qty: 0` and `set(..., merge: true)` the first time an item is used at a location. After that, `qty` changes only through increments.

### locations/{loc}/movements/{movementId}
`movementId` = `{deviceId}-M{seq}`, using a separate per-device movement counter. For movements caused by a bill, return or cancellation, the ID is `{billId}` / `{returnId}` / `{billId}-X`.
| Field | Type | Notes |
|---|---|---|
| type | enum | `STOCK_IN`, `STOCK_OUT_RAW`, `WASTAGE_RAW`, `PRODUCE`, `WASTAGE_FG`, `ADJUST`, `SALE`, `RETURN`, `CANCEL` |
| lines | `[{itemKey, delta:int, before?:int, after?:int}]` | `before`/`after` are only set on ADJUST, taken from the device's local view |
| reason | string \| null | Required for WASTAGE_*, ADJUST and CANCEL |
| refId | string \| null | billId or returnId |
| businessDate, clientCreatedAt, serverCreatedAt, createdBy, deviceId | | |

PRODUCE example: `lines: [{RM_cakemix, -1000}, {RM_cream, -500}, {FG_bf1kg, +2}]`. A future recipe/BOM feature only has to fill these lines in automatically, so the model doesn't change.

### locations/{loc}/bills/{billId}
`billId` = `{deviceId}-{seq:6}`, e.g. `D01-000123`. `billNo` = `{loc}-{billId}`.
| Field | Type | Notes |
|---|---|---|
| billNo | string | `PTB-D01-000123` |
| deviceId, seq | string, int | |
| lines | `[{productId, name, qty, unitPrice, lineTotal}]` | `name` and `unitPrice` are copied at the time of sale |
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
| returnedQty | map productId → int | Incremented by returns |
| servedBy | `{uid, name}` | |
| businessDate, clientCreatedAt, serverCreatedAt | | |

### locations/{loc}/returns/{returnId}
`returnId` = `{deviceId}-R{seq}`, using a separate per-device return counter.
| Field | Type | Notes |
|---|---|---|
| billId, billNo | string | |
| lines | `[{productId, name, qty, amount}]` | `amount` is prorated: the line's share of the bill's net amount, rounded to the paise |
| refundTotal | int | Σ amount, rounded to the nearest ₹1 |
| refunds | `[{mode, amount}]` | Σ == refundTotal. Any mix of modes |
| reason | string | |
| businessDate, createdBy, deviceId, clientCreatedAt, serverCreatedAt | | |

Before creating a return, the client checks that `bill.returnedQty[p] + qty ≤ sold qty`.

### locations/{loc}/dailySummary/{YYYY-MM-DD} and monthlySummary/{YYYY-MM}
Same shape for both. Every numeric field is written **only with `increment()`**.
| Field | Type |
|---|---|
| billCount, cancelCount, returnCount | int |
| grossSales | int — Σ subtotal |
| discounts | int |
| roundOff | int |
| netSales | int — Σ total of completed bills |
| returns | int — Σ refundTotal |
| cancelled | int — Σ total of bills cancelled that day |
| byMode | map mode → int (net payments minus refunds) |
| byProduct | map productId → `{qty:int, amount:int}` |
| expenses | int (monthly only) |
| byExpenseCategory | map category → int (monthly only) |
| lastWriteRef | string — full path (from the database root) of the *new* doc created in the same batch: the bill, return, CANCEL movement (`{billId}-X`) or expense audit doc. The rules check it (`04-PERMISSIONS.md` #9) |

Net revenue for a period = `netSales − returns − cancelled`. Profit = that figure − `expenses`.

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
`auditId` = the ID of the entity doc it covers, plus a suffix when that entity can have more than one audited event (e.g. `D01-000123-X` for a cancellation, `EXP-{id}-{ts}` for an expense edit).
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
