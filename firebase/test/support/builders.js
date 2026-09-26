// Doc builders for rules tests. They produce the same shapes as the core
// models' toMap(), with consistent arithmetic, so a test only spells out the
// field it's tampering with.

import { serverTimestamp, Timestamp } from 'firebase/firestore';
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

/**
 * A valid bill. `lines` is `[[productId, qty, unitPricePaise], ...]`;
 * `payments` defaults to one CASH payment of the total.
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
  };
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
