// The largest batches the list caps allow (D-030): the cases the rules
// budget is sized for. Each scenario is `{ arrange(db), run(dbAs) }`, as
// budget.js's probe() and the suite (test/budget.test.js) both use it:
// `arrange` writes the starting state with the rules off, and `run` commits
// the batch as the Store Manager at PTB.

import { doc, setDoc } from 'firebase/firestore';
import { ACTORS, LOC } from './fixtures.js';
import { billId, makeBill, makeMovement, makeReturn, manyLines, movementId, returnId, storedBill, storedCustomer } from './builders.js';
import { billBatch, returnBatch, stockBatch } from './batches.js';
import { readLimits } from '../../scripts/lib/core.js';

// The caps come from Limits in packages/core, so a change there moves these
// cases with it.
const LIMITS = readLimits();
export const MAX_BILL_LINES = LIMITS.maxBillLines;
export const MAX_MOVEMENT_LINES = LIMITS.maxMovementLines;
if (LIMITS.maxPayments !== 4 || LIMITS.maxRefunds !== 4) {
  throw new Error('caps.js: fourWay() and the rules spell out 4 payments and refunds; update both with Limits');
}

const MODES = ['CASH', 'UPI', 'CARD', 'WALLET'];

/** `total` split into four payments (or refunds), one per mode. */
export function fourWay(total) {
  const part = Math.floor(total / 4 / 100) * 100;
  return MODES.map((mode, i) => ({ mode, amount: i < 3 ? part : total - 3 * part }));
}

const BILL = billId('D01', 1);
const R1 = returnId('D01', 1);
const R2 = returnId('D01', 2);

function device(db, counters = {}) {
  return setDoc(doc(db, 'locations', LOC.PTB, 'devices', 'D01'), {
    code: 'D01',
    label: 'Counter 1',
    registeredBy: ACTORS.smPtb.uid,
    lastBillSeq: 0,
    lastMovementSeq: 0,
    lastReturnSeq: 0,
    retired: false,
    ...counters,
  });
}

/** A bill of `lines` lines, `qty` of each, paid in four parts. */
export function bigBill(lines = MAX_BILL_LINES, qty = 1) {
  const draft = makeBill({ lines: manyLines(lines).map(([p, , price]) => [p, qty, price]) });
  return makeBill({ lines: draft.lines.map((l) => [l.productId, l.qty, l.unitPrice]), payments: fourWay(draft.total) });
}

/** The complete bill batch (bill, stock, SALE movement, device, summaries) for a 15-line bill with 4 payments. */
export const largestBill = {
  name: 'bill: 15 lines, 4 payments',
  arrange: (db) => device(db),
  run: (dbAs) => billBatch(dbAs('smPtb'), bigBill(), { full: true }).commit(),
};

/**
 * The same bill by a customer who already has a record, so its customer write
 * is an update (billCount and totalSpend go up by this bill's).
 */
export const largestRepeatBill = {
  name: 'bill: 15 lines, 4 payments, repeat customer',
  arrange: async (db) => {
    await device(db);
    await setDoc(
      doc(db, 'locations', LOC.PTB, 'customers', bigBill().customerId),
      storedCustomer({ billCount: 4, totalSpend: 1_000_000, lastWriteRef: 'D01-000099' }),
    );
  },
  run: (dbAs) => billBatch(dbAs('smPtb'), bigBill(), { full: true }).commit(),
};

/** The same batch with 16 lines: over the cap, denied. */
export const overCapBill = {
  name: 'bill: 16 lines',
  arrange: (db) => device(db),
  run: (dbAs) => billBatch(dbAs('smPtb'), bigBill(MAX_BILL_LINES + 1), { full: true }).commit(),
};

/** A return of every line of `bill`, `qty` of each, worth `perLine` each. */
function returnOf(bill, { qty, perLine, prevReturnId = null }) {
  const lines = bill.lines.map((l) => [l.productId, qty, perLine]);
  const refundTotal = perLine * bill.lines.length;
  return makeReturn({ lines, refundTotal, refunds: fourWay(refundTotal), prevReturnId });
}

/**
 * The complete return batch (return, bill update, stock, RETURN movement,
 * device, summaries, audit): the first return of a 15-line bill, bringing
 * all 15 products into returnedQty, with 4 refunds.
 */
export const largestFirstReturn = {
  name: 'return: first, all 15 products, 4 refunds',
  arrange: async (db) => {
    await setDoc(doc(db, 'locations', LOC.PTB, 'bills', BILL), storedBill(bigBill()));
    await device(db);
  },
  run: (dbAs) => {
    const bill = bigBill();
    const ret = returnOf(bill, { qty: 1, perLine: 10000 });
    return returnBatch(dbAs('smPtb'), { rid: R1, ret, returnedQty: bill.soldQty, seq: 1, full: true }).commit();
  },
};

/**
 * The costliest return update: a second return on a 15-line bill whose 15
 * products are all in returnedQty already, raising every one of them, with a
 * prevReturnId to match and 4 refunds.
 */
export const largestSecondReturn = {
  name: 'return: second, 15 products already returned, 4 refunds',
  arrange: async (db) => {
    const bill = bigBill(MAX_BILL_LINES, 2);
    const half = Object.fromEntries(Object.keys(bill.soldQty).map((p) => [p, 1]));
    await setDoc(doc(db, 'locations', LOC.PTB, 'bills', BILL), { ...storedBill(bill), returnedQty: half, lastReturnId: R1 });
    await device(db, { lastReturnSeq: 1 });
  },
  run: (dbAs) => {
    const bill = bigBill(MAX_BILL_LINES, 2);
    const ret = returnOf(bill, { qty: 1, perLine: 10000, prevReturnId: R1 });
    return returnBatch(dbAs('smPtb'), { rid: R2, ret, returnedQty: bill.soldQty, seq: 2, full: true }).commit();
  },
};

/** A 20-line PRODUCE (19 raw materials used, one cake made) creating its 20 stock docs. */
export const largestProduce = {
  name: 'PRODUCE: 20 lines, 20 new stock docs',
  arrange: (db) => device(db),
  run: (dbAs) => {
    const lines = [
      ...Array.from({ length: MAX_MOVEMENT_LINES - 1 }, (_, i) => [`RM_m${String(i + 1).padStart(2, '0')}`, -100]),
      ['FG_cake', 2],
    ];
    const movement = makeMovement({ type: 'PRODUCE', lines });
    return stockBatch(dbAs('smPtb'), { mid: movementId('D01', 1), movement, seq: 1 }).commit();
  },
};

/** Every cap case, with the rules each one is measured on. */
export const CAP_CASES = [
  { scenario: largestBill, targets: ['billCreate', 'customerCreate'] },
  { scenario: largestRepeatBill, targets: ['customerUpdate'] },
  { scenario: largestFirstReturn, targets: ['billUpdate', 'returnCreate'] },
  { scenario: largestSecondReturn, targets: ['billUpdate', 'returnCreate'] },
  { scenario: largestProduce, targets: ['movementCreate', 'stockCreate'] },
];
