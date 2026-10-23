// Whole business batches (03-SYNC §2), hand-built for the rules tests until
// BE-10's plan fixtures replace them. By default they leave out summaries and
// audit docs; pass `full: true` for the complete batch.

import { doc, serverTimestamp, setDoc, writeBatch } from 'firebase/firestore';
import { ACTORS, LOC } from './fixtures.js';
import {
  TODAY,
  customerWrite,
  makeAudit,
  makeCancel,
  makeMovement,
  makeOrderCancel,
  orderId as orderIdOf,
  stockWrite,
  summaryWrite,
} from './builders.js';

/** Adds the daily and monthly summary increments for `ref` (#9). */
export function addSummaries(b, db, { loc = LOC.PTB, ref, fields, date = TODAY }) {
  b.set(doc(db, 'locations', loc, 'dailySummary', date), summaryWrite(ref, fields), { merge: true });
  b.set(doc(db, 'locations', loc, 'monthlySummary', date.slice(0, 7)), summaryWrite(ref, fields), { merge: true });
  return b;
}

const at = (db, loc, ...path) => doc(db, 'locations', loc, ...path);

/** Arranges device D01 at `loc` with the given counters (rules off). */
export async function arrangeDevice(t, loc = LOC.PTB, counters = {}) {
  await t.arrange((db) =>
    setDoc(at(db, loc, 'devices', 'D01'), {
      code: 'D01',
      label: 'Counter 1',
      registeredBy: ACTORS.smPtb.uid,
      lastBillSeq: 0,
      lastMovementSeq: 0,
      lastReturnSeq: 0,
      lastOrderSeq: 0,
      retired: false,
      ...counters,
    }),
  );
}

/**
 * Create bill: bill, FG stock decrements, SALE movement, device lastBillSeq
 * and the customer doc (set with merge, in every bill's batch, D-037;
 * `customer: false` leaves it out, `customer: {..}` overrides its data).
 */
export function billBatch(db, bill, { loc = LOC.PTB, full = false, customer = true } = {}) {
  const id = `${bill.deviceId}-${String(bill.seq).padStart(6, '0')}`;
  const b = writeBatch(db);
  b.set(at(db, loc, 'bills', id), bill);
  for (const l of bill.lines) {
    b.set(at(db, loc, 'stock', `FG_${l.productId}`), stockWrite(`FG_${l.productId}`, -l.qty, id), { merge: true });
  }
  b.set(
    at(db, loc, 'movements', id),
    makeMovement({
      type: 'SALE',
      lines: bill.lines.map((l) => [`FG_${l.productId}`, -l.qty]),
      refId: id,
      deviceId: bill.deviceId,
      uid: bill.createdBy,
    }),
  );
  b.set(at(db, loc, 'devices', bill.deviceId), { lastBillSeq: bill.seq }, { merge: true });
  if (customer && bill.customerId) {
    b.set(at(db, loc, 'customers', bill.customerId), customerWrite(bill, id, customer === true ? {} : customer), { merge: true });
  }
  if (full) {
    addSummaries(b, db, { loc, ref: `locations/${loc}/bills/${id}`, fields: { billCount: 1, netSales: bill.total } });
  }
  return b;
}

/**
 * Cancel bill: bill update, FG stock increments, CANCEL movement, summaries
 * and audit (the whole batch).
 */
export function cancelBatch(db, bill, { loc = LOC.PTB, uid = ACTORS.smPtb.uid, deviceId = 'D01' } = {}) {
  const id = `${bill.deviceId}-${String(bill.seq).padStart(6, '0')}`;
  const x = `${id}-X`;
  const b = writeBatch(db);
  b.update(at(db, loc, 'bills', id), { status: 'CANCELLED', cancel: makeCancel({ uid }) });
  for (const l of bill.lines) {
    b.set(at(db, loc, 'stock', `FG_${l.productId}`), stockWrite(`FG_${l.productId}`, l.qty, x), { merge: true });
  }
  b.set(
    at(db, loc, 'movements', x),
    makeMovement({
      type: 'CANCEL',
      lines: bill.lines.map((l) => [`FG_${l.productId}`, l.qty]),
      refId: id,
      reason: 'Customer changed order',
      deviceId,
      uid,
    }),
  );
  addSummaries(b, db, { loc, ref: `locations/${loc}/movements/${x}`, fields: { cancelCount: 1, cancelled: bill.total } });
  b.set(
    doc(db, 'auditLog', `${loc}-${x}`),
    makeAudit({ action: 'BILL_CANCEL', entityPath: `locations/${loc}/bills/${id}`, locationId: loc, uid, deviceId }),
  );
  return b;
}

/**
 * Return: return doc, bill returnedQty + lastReturnId, FG stock increments,
 * RETURN movement, device lastReturnSeq.
 */
export function returnBatch(db, { loc = LOC.PTB, rid, ret, returnedQty, seq, full = false }) {
  const b = writeBatch(db);
  b.set(at(db, loc, 'returns', rid), ret);
  b.update(at(db, loc, 'bills', ret.billId), { returnedQty, lastReturnId: rid });
  for (const l of ret.lines) {
    b.set(at(db, loc, 'stock', `FG_${l.productId}`), stockWrite(`FG_${l.productId}`, l.qty, rid), { merge: true });
  }
  b.set(
    at(db, loc, 'movements', rid),
    makeMovement({
      type: 'RETURN',
      lines: ret.lines.map((l) => [`FG_${l.productId}`, l.qty]),
      refId: rid,
      deviceId: ret.deviceId,
      uid: ret.createdBy,
    }),
  );
  b.set(at(db, loc, 'devices', ret.deviceId), { lastReturnSeq: seq }, { merge: true });
  if (full) {
    addSummaries(b, db, { loc, ref: `locations/${loc}/returns/${rid}`, fields: { returnCount: 1, returns: ret.refundTotal } });
    b.set(
      doc(db, 'auditLog', `${loc}-${rid}`),
      makeAudit({ action: 'RETURN', entityPath: `locations/${loc}/returns/${rid}`, locationId: loc, uid: ret.createdBy }),
    );
  }
  return b;
}

/** Stock operation: movement, stock increments, device lastMovementSeq. */
export function stockBatch(db, { loc = LOC.PTB, mid, movement, seq, names = {} }) {
  const b = writeBatch(db);
  b.set(at(db, loc, 'movements', mid), movement);
  for (const l of movement.lines) {
    b.set(at(db, loc, 'stock', l.itemKey), stockWrite(l.itemKey, l.delta, mid, { name: names[l.itemKey] }), {
      merge: true,
    });
  }
  b.set(at(db, loc, 'devices', movement.deviceId), { lastMovementSeq: seq }, { merge: true });
  return b;
}

/**
 * Create a pre-order: the order, the device's lastOrderSeq and, when the
 * advance is above zero, the summaries' advanceReceived naming the order
 * (#18, #20). `full: false` leaves the summaries out.
 */
export function orderCreateBatch(db, order, { loc = LOC.PTB, full = true } = {}) {
  const id = orderIdOf(order.deviceId, order.seq);
  const b = writeBatch(db);
  b.set(at(db, loc, 'orders', id), order);
  b.set(at(db, loc, 'devices', order.deviceId), { lastOrderSeq: order.seq }, { merge: true });
  if (full && order.advance > 0) {
    addSummaries(b, db, {
      loc,
      ref: `locations/${loc}/orders/${id}`,
      date: order.businessDate,
      fields: { advanceReceived: order.advance },
    });
  }
  return b;
}

/**
 * Deliver an open order: the delivery bill's whole batch (billBatch) plus the
 * order update (#18 (a), #19). `bill` must carry `orderId` and the ADVANCE
 * payment; `orderUpdate` overrides the update's data for tampered cases.
 */
export function deliverBatch(db, bill, { loc = LOC.PTB, orderUpdate = {}, ...opts } = {}) {
  const id = `${bill.deviceId}-${String(bill.seq).padStart(6, '0')}`;
  const b = billBatch(db, bill, { loc, full: true, ...opts });
  b.update(at(db, loc, 'orders', bill.orderId), {
    status: 'DELIVERED',
    billId: id,
    deliveredAt: serverTimestamp(),
    ...orderUpdate,
  });
  return b;
}

/**
 * Cancel an open order: the order update, the ORDER_CANCEL audit
 * `{loc}-{orderId}-X` and, when something is refunded, the summaries'
 * advanceRefunded naming that audit entry (#18 (b), #20).
 */
export function orderCancelBatch(db, orderId, { loc = LOC.PTB, uid = ACTORS.smPtb.uid, refunded = 0, deviceId = 'D01', cancel = {}, date = TODAY } = {}) {
  const x = `${orderId}-X`;
  const b = writeBatch(db);
  b.update(at(db, loc, 'orders', orderId), {
    status: 'CANCELLED',
    cancel: { ...makeOrderCancel({ uid, refunded, businessDate: date }), ...cancel },
  });
  b.set(
    doc(db, 'auditLog', `${loc}-${x}`),
    makeAudit({ action: 'ORDER_CANCEL', entityPath: `locations/${loc}/orders/${orderId}`, locationId: loc, uid, deviceId, reason: 'Customer cancelled' }),
  );
  if (refunded > 0) {
    addSummaries(b, db, { loc, ref: `auditLog/${loc}-${x}`, date, fields: { advanceRefunded: refunded } });
  }
  return b;
}
