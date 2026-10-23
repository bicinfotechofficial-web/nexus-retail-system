// Doc builders for rules tests. They produce the same shapes as the core
// models' toMap(), with consistent arithmetic, so a test only spells out the
// field it's tampering with.

import { createHash } from 'node:crypto';
import { increment, serverTimestamp, Timestamp } from 'firebase/firestore';
import { ACTORS, LOC } from './fixtures.js';

export const TODAY = '2026-09-26';
export const TOMORROW = '2026-09-27';

/** `D01-000123` */
export function billId(deviceId, seq) {
  return `${deviceId}-${String(seq).padStart(6, '0')}`;
}

/** Halves away from zero, to the nearest rupee (D-024a). */
function roundToRupee(paise) {
  const sign = paise < 0 ? -1 : 1;
  return sign * Math.floor((Math.abs(paise) + 50) / 100) * 100;
}

/** `{phone}_{nameKey}` (D-037): the first 10 hex of SHA-256 of the trimmed, space-collapsed, lower-cased name. */
export function customerId(phone, name) {
  const normal = name.trim().replace(/\s+/g, ' ').toLowerCase();
  return `${phone}_${createHash('sha256').update(normal).digest('hex').slice(0, 10)}`;
}

/**
 * The four customer fields of a bill (D-034, D-037). `whatsapp` defaults to
 * the phone (the mobile is on WhatsApp); pass null for no WhatsApp.
 */
export function customerFields({ name = 'Test Customer', phone = '9876543210', whatsapp = phone } = {}) {
  return { customerId: customerId(phone, name), customerName: name, customerPhone: phone, customerWhatsapp: whatsapp };
}

/**
 * A valid bill. `lines` is `[[productId, qty, unitPricePaise], ...]`;
 * `payments` defaults to one CASH payment of the total. `customer` is the
 * options of customerFields(); `customerOverride` replaces fields as they
 * are on the bill, for the tampered cases.
 */
export function makeBill({
  loc = LOC.PTB,
  deviceId = 'D01',
  seq = 1,
  lines = [['cake-choco-1kg', 1, 65000], ['puff-veg', 2, 2550]],
  discount = null,
  payments,
  uid = ACTORS.smPtb.uid,
  userName = 'Store Manager PTB',
  businessDate = TODAY,
  customer = {},
  customerOverride = {},
  orderId,
} = {}) {
  const billLines = lines.map(([productId, qty, unitPrice]) => ({
    productId,
    name: `Product ${productId}`,
    qty,
    unitPrice,
    lineTotal: qty * unitPrice,
  }));
  const subtotal = billLines.reduce((a, l) => a + l.lineTotal, 0);
  const taxableValue = subtotal - (discount?.amount ?? 0);
  const total = roundToRupee(taxableValue);
  const id = billId(deviceId, seq);
  return {
    billNo: `${loc}-${id}`,
    deviceId,
    seq,
    lines: billLines,
    subtotal,
    discount,
    taxableValue,
    taxLines: [],
    roundOff: total - taxableValue,
    total,
    payments: payments ?? [{ mode: 'CASH', amount: total }],
    cashTendered: null,
    status: 'COMPLETED',
    cancel: null,
    returnedQty: {},
    soldQty: Object.fromEntries(billLines.map((l) => [l.productId, l.qty])),
    lastReturnId: null,
    servedBy: { uid, name: userName },
    businessDate,
    clientCreatedAt: Timestamp.fromDate(new Date(`${businessDate}T10:00:00+05:30`)),
    serverCreatedAt: serverTimestamp(),
    createdBy: uid,
    ...customerFields(customer),
    // Only a delivery bill carries the key (D-043); an ordinary bill omits it.
    ...(orderId === undefined ? {} : { orderId }),
    ...customerOverride,
  };
}

/**
 * What a bill's batch writes to its customer doc (D-037, set with merge):
 * the customer fields of the bill, the server time, both counters as
 * increments and the bill's ID.
 */
export function customerWrite(bill, id, overrides = {}) {
  return {
    name: bill.customerName,
    phone: bill.customerPhone,
    whatsapp: bill.customerWhatsapp,
    lastBillAt: serverTimestamp(),
    billCount: increment(1),
    totalSpend: increment(bill.total),
    lastWriteRef: id,
    ...overrides,
  };
}

/** A customer doc as stored after `billCount` bills worth `totalSpend` (for arranging state). */
export function storedCustomer({ name = 'Test Customer', phone = '9876543210', whatsapp = phone, billCount = 1, totalSpend = 70100, lastWriteRef = 'D01-000001' } = {}) {
  return { name, phone, whatsapp, lastBillAt: Timestamp.now(), billCount, totalSpend, lastWriteRef };
}

/** The same bill as it reads back from the server (for arranging state). */
export function storedBill(bill) {
  return { ...bill, serverCreatedAt: Timestamp.now() };
}

/** The `cancel` map of a cancellation. */
export function makeCancel({ uid = ACTORS.smPtb.uid, businessDate = TODAY, reason = 'Customer changed order' } = {}) {
  return { reason, by: uid, at: Timestamp.now(), businessDate };
}

/** `n` distinct lines of one piece each, for cap tests. */
export function manyLines(n, unitPrice = 10000) {
  return Array.from({ length: n }, (_, i) => [`p${String(i + 1).padStart(2, '0')}`, 1, unitPrice]);
}

/** `D01-R000007` */
export function returnId(deviceId, seq) {
  return `${deviceId}-R${String(seq).padStart(6, '0')}`;
}

/** `D01-M000042` */
export function movementId(deviceId, seq) {
  return `${deviceId}-M${String(seq).padStart(6, '0')}`;
}

/**
 * A return of `lines` (`[[productId, qty, amountPaise], ...]`) from bill
 * `billId`. `refunds` defaults to one CASH refund of the rupee-rounded total.
 */
export function makeReturn({
  loc = LOC.PTB,
  deviceId = 'D01',
  billId: forBill = billId('D01', 1),
  lines = [['puff-veg', 1, 2550]],
  refunds,
  refundTotal,
  prevReturnId = null,
  uid = ACTORS.smPtb.uid,
  businessDate = TODAY,
} = {}) {
  const returnLines = lines.map(([productId, qty, amount]) => ({ productId, name: `Product ${productId}`, qty, amount }));
  const total = refundTotal ?? roundToRupee(returnLines.reduce((a, l) => a + l.amount, 0));
  return {
    billId: forBill,
    billNo: `${loc}-${forBill}`,
    lines: returnLines,
    refundTotal: total,
    refunds: refunds ?? [{ mode: 'CASH', amount: total }],
    reason: 'Damaged in transit',
    prevReturnId,
    businessDate,
    createdBy: uid,
    deviceId,
    clientCreatedAt: Timestamp.now(),
    serverCreatedAt: serverTimestamp(),
  };
}

/** A movement. `lines` is `[[itemKey, delta], ...]`. */
export function makeMovement({
  type = 'STOCK_IN',
  lines = [['RM_flour', 5000]],
  reason = null,
  note = null,
  refId = null,
  deviceId = 'D01',
  uid = ACTORS.smPtb.uid,
  businessDate = TODAY,
} = {}) {
  return {
    type,
    lines: lines.map(([itemKey, delta]) => ({ itemKey, delta })),
    reason,
    note,
    refId,
    businessDate,
    clientCreatedAt: Timestamp.now(),
    serverCreatedAt: serverTimestamp(),
    createdBy: uid,
    deviceId,
  };
}

/** The set(merge) data a batch writes to one stock doc (D-005). */
export function stockWrite(itemKey, delta, lastMovementId, { name } = {}) {
  const raw = itemKey.startsWith('RM_');
  const refId = itemKey.slice(3);
  return {
    kind: raw ? 'RAW' : 'FINISHED',
    refId,
    name: name ?? `Item ${refId}`,
    unit: raw ? 'G' : 'PCS',
    qty: increment(delta),
    lastMovementId,
    updatedAt: serverTimestamp(),
  };
}

/** An audit doc as the batches write it (02-DATA-MODEL auditLog). */
export function makeAudit({
  action,
  entityPath,
  locationId = LOC.PTB,
  uid = ACTORS.smPtb.uid,
  reason = null,
  deviceId = 'D01',
  before = null,
  after = null,
} = {}) {
  return {
    action,
    entityPath,
    locationId,
    before,
    after,
    reason,
    by: uid,
    deviceId,
    clientAt: Timestamp.now(),
    at: serverTimestamp(),
  };
}

/**
 * The set(merge) data for a daily or monthly summary: `fields` are plain
 * numbers that become increments; nested maps (byMode, byProduct) too.
 */
export function summaryWrite(lastWriteRef, fields = { billCount: 1, netSales: 70100 }) {
  const toIncrements = (o) =>
    Object.fromEntries(
      Object.entries(o).map(([k, v]) => [k, typeof v === 'number' ? increment(v) : toIncrements(v)]),
    );
  return { ...toIncrements(fields), lastWriteRef };
}

/** A valid expense doc. */
export function makeExpense({ locationId = LOC.PTB, amount = 1500000, category = 'RENT', uid = ACTORS.admin.uid } = {}) {
  return {
    locationId,
    category,
    amount,
    date: TODAY,
    note: 'September rent',
    createdBy: uid,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  };
}

/** A valid product doc. */
export function makeProduct({ status = 'ACTIVE', price = 65000, proposedPrice = null, scope = 'GLOBAL', uid = ACTORS.admin.uid } = {}) {
  return {
    name: 'Black Forest 1 kg',
    category: 'Cakes',
    price,
    proposedPrice,
    unit: 'PCS',
    gstRate: null,
    scope,
    status,
    recipe: null,
    sortOrder: 10,
    createdBy: uid,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  };
}

// ---- Staff, attendance and pre-orders (D-042, D-043) ------------------------

/** A new staff doc as the Admin's create writes it (auto ID). */
export function makeStaff({ name = 'Asha Baker', role = 'Baker', active = true, uid = ACTORS.admin.uid } = {}) {
  return { name, role, active, createdBy: uid, createdAt: serverTimestamp() };
}

/** `2026-09-26_staff1`. */
export const attendanceId = (businessDate, staffId) => `${businessDate}_${staffId}`;

/** One attendance mark as the POS writes it (set of the whole doc). */
export function makeAttendance({
  staffId = 'staff1',
  staffName = 'Asha Baker',
  businessDate = TODAY,
  status = 'PRESENT',
  note = null,
  uid = ACTORS.smPtb.uid,
  userName = 'Store Manager PTB',
  deviceId = 'D01',
} = {}) {
  return {
    staffId,
    staffName,
    businessDate,
    status,
    note,
    markedBy: { uid, name: userName },
    deviceId,
    editedAt: serverTimestamp(),
  };
}

/** `D01-O000007` */
export function orderId(deviceId, seq) {
  return `${deviceId}-O${String(seq).padStart(6, '0')}`;
}

/**
 * A new pre-order as the create writes it. Amounts are paise; `advance` 0
 * means no mode. `override` replaces fields as they are, for tampered cases.
 */
export function makeOrder({
  loc = LOC.PTB,
  deviceId = 'D01',
  seq = 1,
  price = 150000,
  advance = 50000,
  advanceMode = advance === 0 ? null : 'UPI',
  dueDate = TOMORROW,
  dueTime = '16:30',
  description = 'Two layer chocolate truffle, 1.5 kg, "Happy Birthday Anu"',
  uid = ACTORS.smPtb.uid,
  userName = 'Store Manager PTB',
  businessDate = TODAY,
  customer = {},
  override = {},
} = {}) {
  const id = orderId(deviceId, seq);
  return {
    orderNo: `${loc}-${id}`,
    deviceId,
    seq,
    ...customerFields(customer),
    dueDate,
    dueTime,
    description,
    price,
    advance,
    advanceMode,
    status: 'OPEN',
    billId: null,
    servedBy: { uid, name: userName },
    businessDate,
    clientCreatedAt: Timestamp.fromDate(new Date(`${businessDate}T10:00:00+05:30`)),
    serverCreatedAt: serverTimestamp(),
    createdBy: uid,
    ...override,
  };
}

/** The same order as it reads back (for arranging state): server times filled in. */
export function storedOrder(order, extra = {}) {
  return { ...order, serverCreatedAt: Timestamp.now(), ...extra };
}

/** The `cancel` map of a cancelled pre-order. */
export function makeOrderCancel({ uid = ACTORS.smPtb.uid, businessDate = TODAY, reason = 'Customer cancelled', refunded = 0 } = {}) {
  return { reason, by: uid, at: Timestamp.now(), businessDate, refunded };
}
