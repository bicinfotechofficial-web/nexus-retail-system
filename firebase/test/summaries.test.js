// BE-5: summaries (04-PERMISSIONS #9), through the complete bill, cancel,
// return and expense batches of 03-SYNC §2.

import { describe, it } from 'vitest';
import { deleteDoc, doc, getDoc, serverTimestamp, setDoc, writeBatch } from 'firebase/firestore';
import { ACTORS, LOC } from './support/fixtures.js';
import {
  TODAY,
  billId,
  makeAudit,
  makeBill,
  makeExpense,
  makeReturn,
  manyLines,
  returnId,
  storedBill,
  summaryWrite,
} from './support/builders.js';
import { addSummaries, arrangeDevice, billBatch, cancelBatch, returnBatch } from './support/batches.js';
import { assertFails, assertSucceeds, useRulesEnv } from './support/env.js';

const t = useRulesEnv();

const BILL = billId('D01', 1);
const BILL_PATH = `locations/${LOC.PTB}/bills/${BILL}`;
const dailyRef = (db, loc = LOC.PTB, day = TODAY) => doc(db, 'locations', loc, 'dailySummary', day);
const monthlyRef = (db, loc = LOC.PTB, month = TODAY.slice(0, 7)) => doc(db, 'locations', loc, 'monthlySummary', month);

describe('#9 summaries in the complete batches', () => {
  it('accepts the complete bill batch', async () => {
    await arrangeDevice(t);
    await assertSucceeds(billBatch(t.db('smPtb'), makeBill(), { full: true }).commit());
  });

  it('accepts the complete bill batch at the maximum: 20 lines, 4 payments', async () => {
    await arrangeDevice(t);
    const payments = ['CASH', 'UPI', 'CARD', 'WALLET'].map((mode) => ({ mode, amount: 50000 }));
    const bill = makeBill({ lines: manyLines(20), payments });
    await assertSucceeds(billBatch(t.db('smPtb'), bill, { full: true }).commit());
  });

  it('accepts the complete cancel batch, audit included', async () => {
    const bill = makeBill();
    await t.arrange((db) => setDoc(doc(db, BILL_PATH), storedBill(bill)));
    await arrangeDevice(t);
    await assertSucceeds(cancelBatch(t.db('smPtb'), bill).commit());
  });

  it('accepts the complete return batch, audit included', async () => {
    const bill = makeBill();
    await t.arrange((db) => setDoc(doc(db, BILL_PATH), storedBill(bill)));
    await arrangeDevice(t);
    const rid = returnId('D01', 1);
    const b = returnBatch(t.db('smPtb'), { rid, ret: makeReturn(), returnedQty: { 'puff-veg': 1 }, seq: 1, full: true });
    await assertSucceeds(b.commit());
  });

  it('accepts the complete expense batch: expense, monthly summary, audit', async () => {
    const db = t.db('admin');
    const auditId = 'EXP-e1-1790000000000';
    const b = writeBatch(db);
    b.set(doc(db, 'expenses/e1'), makeExpense());
    b.set(monthlyRef(db), summaryWrite(`auditLog/${auditId}`, { expenses: 1500000, byExpenseCategory: { RENT: 1500000 } }), { merge: true });
    b.set(doc(db, 'auditLog', auditId), makeAudit({ action: 'EXPENSE_CREATE', entityPath: 'expenses/e1', uid: ACTORS.admin.uid, deviceId: null }));
    await assertSucceeds(b.commit());
  });
});

describe('#9 summaries: lastWriteRef', () => {
  it('denies a summary increment without a new doc', async () => {
    await assertFails(setDoc(dailyRef(t.db('smPtb')), summaryWrite(BILL_PATH), { merge: true }));
  });

  it('denies a summary increment that names a doc that already existed', async () => {
    await t.arrange((db) => setDoc(doc(db, BILL_PATH), storedBill(makeBill())));
    await assertFails(setDoc(dailyRef(t.db('smPtb')), summaryWrite(BILL_PATH), { merge: true }));
    await assertFails(setDoc(monthlyRef(t.db('smPtb')), summaryWrite(BILL_PATH), { merge: true }));
  });

  it('denies replaying a bill\'s increment in a second batch', async () => {
    await arrangeDevice(t);
    await assertSucceeds(billBatch(t.db('smPtb'), makeBill(), { full: true }).commit());
    await assertFails(setDoc(dailyRef(t.db('smPtb')), summaryWrite(BILL_PATH), { merge: true }));
  });

  it('denies a summary without lastWriteRef', async () => {
    await arrangeDevice(t);
    const db = t.db('smPtb');
    const b = billBatch(db, makeBill());
    const { lastWriteRef, ...noRef } = summaryWrite(BILL_PATH);
    b.set(dailyRef(db), noRef, { merge: true });
    await assertFails(b.commit());
  });

  it('denies a malformed lastWriteRef', async () => {
    await arrangeDevice(t);
    const db = t.db('smPtb');
    const b1 = billBatch(db, makeBill());
    addSummaries(b1, db, { loc: LOC.PTB, ref: `/${BILL_PATH}` });
    await assertFails(b1.commit());
  });

  it('denies a lastWriteRef to a new doc that is not a business event', async () => {
    // A device registered in the same batch is new, but it isn't a bill,
    // return, cancellation or expense.
    const db = t.db('smPtb');
    const b = writeBatch(db);
    b.update(doc(db, 'locations', LOC.PTB), { nextDeviceNo: 1 });
    b.set(doc(db, 'locations', LOC.PTB, 'devices', 'D01'), {
      code: 'D01',
      label: 'Counter 1',
      registeredBy: ACTORS.smPtb.uid,
      registeredAt: serverTimestamp(),
      lastSeenAt: serverTimestamp(),
      lastBillSeq: 0,
      lastMovementSeq: 0,
      lastReturnSeq: 0,
      retired: false,
    });
    b.set(dailyRef(db), summaryWrite(`locations/${LOC.PTB}/devices/D01`), { merge: true });
    await assertFails(b.commit());
  });

  it("denies the Admin feeding one location's bill into another location's summary", async () => {
    await arrangeDevice(t);
    const db = t.db('admin');
    const b = billBatch(db, makeBill({ uid: ACTORS.admin.uid, userName: 'Admin' }));
    b.set(dailyRef(db, LOC.MNJ), summaryWrite(BILL_PATH), { merge: true });
    await assertFails(b.commit());
  });

  it("denies writing another location's summary from this location's bill", async () => {
    await arrangeDevice(t);
    const db = t.db('smPtb');
    const b = billBatch(db, makeBill());
    b.set(dailyRef(db, LOC.MNJ), summaryWrite(BILL_PATH), { merge: true });
    await assertFails(b.commit());
  });

  it('denies unknown fields and bad document IDs', async () => {
    await arrangeDevice(t);
    const db = t.db('smPtb');
    const b1 = billBatch(db, makeBill());
    b1.set(dailyRef(db), { ...summaryWrite(BILL_PATH), bonus: 1 }, { merge: true });
    await assertFails(b1.commit());
    const b2 = billBatch(db, makeBill());
    b2.set(dailyRef(db, LOC.PTB, '26-09-2026'), summaryWrite(BILL_PATH), { merge: true });
    await assertFails(b2.commit());
    const b3 = billBatch(db, makeBill());
    b3.set(monthlyRef(db, LOC.PTB, '2026-9'), summaryWrite(BILL_PATH), { merge: true });
    await assertFails(b3.commit());
  });

  it('denies deleting a summary', async () => {
    await t.arrange((db) => setDoc(dailyRef(db), { billCount: 1, lastWriteRef: BILL_PATH }));
    await assertFails(deleteDoc(dailyRef(t.db('admin'))));
  });
});

describe('#9 summaries: read', () => {
  it('lets report.own at the location read, and the Admin everywhere', async () => {
    await t.arrange(async (db) => {
      await setDoc(dailyRef(db), { billCount: 1, lastWriteRef: BILL_PATH });
      await setDoc(dailyRef(db, LOC.MNJ), { billCount: 1, lastWriteRef: 'x' });
    });
    await assertSucceeds(getDoc(dailyRef(t.db('smPtb'))));
    await assertSucceeds(getDoc(dailyRef(t.db('admin'), LOC.MNJ)));
  });

  it("denies another location's SM and a disabled user", async () => {
    await t.arrange((db) => setDoc(dailyRef(db), { billCount: 1, lastWriteRef: BILL_PATH }));
    await assertFails(getDoc(dailyRef(t.db('smMnj'))));
    await assertFails(getDoc(dailyRef(t.db('disabled'))));
  });
});
