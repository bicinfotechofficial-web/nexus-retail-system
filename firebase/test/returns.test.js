// BE-4: returns (04-PERMISSIONS #7) and the bill's returnedQty (#5(b)),
// through the whole return batch.

import { describe, it } from 'vitest';
import { collection, deleteDoc, doc, getDoc, getDocs, setDoc, updateDoc } from 'firebase/firestore';
import { ACTORS, LOC } from './support/fixtures.js';
import { billId, makeBill, makeCancel, makeReturn, manyLines, returnId, storedBill } from './support/builders.js';
import { arrangeDevice, returnBatch } from './support/batches.js';
import { assertFails, assertSucceeds, useRulesEnv } from './support/env.js';

const t = useRulesEnv();

const BILL = billId('D01', 1);
const R1 = returnId('D01', 1);
const R2 = returnId('D01', 2);
// 1 × cake ₹650 + 2 × puff ₹25.50 = ₹701.
const bill = makeBill();

const billRef = (db) => doc(db, 'locations', LOC.PTB, 'bills', BILL);
const returnRef = (db, id = R1, loc = LOC.PTB) => doc(db, 'locations', loc, 'returns', id);
const arrangeAudit = (id) => t.arrange((db) => setDoc(doc(db, 'auditLog', `${LOC.PTB}-${id}`), { x: 1 }));

/** Arranges the bill (optionally after earlier returns), device D01 and the audit doc for R1 and R2. */
async function arrangeBill(fields = {}) {
  await t.arrange((db) => setDoc(billRef(db), { ...storedBill(bill), ...fields }));
  await arrangeDevice(t);
  await arrangeAudit(R1);
  await arrangeAudit(R2);
}

/** The return batch for one puff, as the first return. */
const firstReturn = (actor = 'smPtb', overrides = {}, db = t.db(actor)) =>
  returnBatch(db, {
    rid: R1,
    ret: makeReturn({ uid: ACTORS[actor].uid, ...overrides }),
    returnedQty: { 'puff-veg': 1 },
    seq: 1,
  });

// ---- Allowed ------------------------------------------------------------

describe('#5(b), #7 returns: accepted', () => {
  it('accepts a first return with its bill update, stock, movement and device counter', async () => {
    await arrangeBill();
    await assertSucceeds(firstReturn().commit());
  });

  it('accepts a second return whose prevReturnId is the first (QA-024)', async () => {
    await arrangeBill({ returnedQty: { 'puff-veg': 1 }, lastReturnId: R1 });
    await arrangeDevice(t, LOC.PTB, { lastReturnSeq: 1 });
    const ret = makeReturn({ prevReturnId: R1 });
    await assertSucceeds(
      returnBatch(t.db('smPtb'), { rid: R2, ret, returnedQty: { 'puff-veg': 2 }, seq: 2 }).commit(),
    );
  });

  it('accepts returning everything that was sold, keeping earlier keys', async () => {
    await arrangeBill({ returnedQty: { 'puff-veg': 1 }, lastReturnId: R1 });
    await arrangeDevice(t, LOC.PTB, { lastReturnSeq: 1 });
    const ret = makeReturn({ prevReturnId: R1, lines: [['cake-choco-1kg', 1, 65000], ['puff-veg', 1, 2550]] });
    await assertSucceeds(
      returnBatch(t.db('smPtb'), {
        rid: R2,
        ret,
        returnedQty: { 'puff-veg': 2, 'cake-choco-1kg': 1 },
        seq: 2,
      }).commit(),
    );
  });

  it('accepts the largest return: every product of a 20-line bill (D-030, CR-001)', async () => {
    const big = makeBill({ lines: manyLines(20) });
    await t.arrange((db) => setDoc(billRef(db), storedBill(big)));
    await arrangeDevice(t);
    await arrangeAudit(R1);
    const lines = big.lines.map((l) => [l.productId, 1, l.lineTotal]);
    const refunds = ['CASH', 'UPI', 'CARD', 'WALLET'].map((mode) => ({ mode, amount: 50000 }));
    const ret = makeReturn({ lines, refunds });
    await assertSucceeds(
      returnBatch(t.db('smPtb'), { rid: R1, ret, returnedQty: big.soldQty, seq: 1 }).commit(),
    );
  });

  it('lets the Admin make a return at any location', async () => {
    await arrangeBill();
    await assertSucceeds(firstReturn('admin').commit());
  });
});

// ---- #5(b) on the bill ----------------------------------------------------

describe('#5(b) returns: the bill update', () => {
  it('denies a stale return: prevReturnId is not the bill\'s lastReturnId (QA-024)', async () => {
    await arrangeBill({ returnedQty: { 'puff-veg': 1 }, lastReturnId: R1 });
    await arrangeDevice(t, LOC.PTB, { lastReturnSeq: 1 });
    // Worked out on a device that hadn't seen R1 yet.
    const ret = makeReturn({ prevReturnId: null });
    await assertFails(returnBatch(t.db('smPtb'), { rid: R2, ret, returnedQty: { 'puff-veg': 2 }, seq: 2 }).commit());
  });

  it('denies returnedQty above soldQty', async () => {
    await arrangeBill();
    const ret = makeReturn({ lines: [['puff-veg', 3, 7650]] });
    await assertFails(returnBatch(t.db('smPtb'), { rid: R1, ret, returnedQty: { 'puff-veg': 3 }, seq: 1 }).commit());
  });

  it('denies a product that is not on the bill', async () => {
    await arrangeBill();
    const ret = makeReturn({ lines: [['bread', 1, 4000]] });
    await assertFails(returnBatch(t.db('smPtb'), { rid: R1, ret, returnedQty: { bread: 1 }, seq: 1 }).commit());
  });

  it('denies lowering returnedQty, or dropping a key', async () => {
    await arrangeBill({ returnedQty: { 'puff-veg': 2, 'cake-choco-1kg': 1 }, lastReturnId: R1 });
    await arrangeDevice(t, LOC.PTB, { lastReturnSeq: 1 });
    const ret = makeReturn({ prevReturnId: R1 });
    const attempt = (returnedQty) => returnBatch(t.db('smPtb'), { rid: R2, ret, returnedQty, seq: 2 }).commit();
    await assertFails(attempt({ 'puff-veg': 1, 'cake-choco-1kg': 1 }));
    await assertFails(attempt({ 'puff-veg': 2 }));
  });

  it('denies a return on a cancelled bill (D-029)', async () => {
    await arrangeBill({ status: 'CANCELLED', cancel: makeCancel() });
    await assertFails(firstReturn().commit());
  });

  it('denies a return doc without the bill update', async () => {
    await arrangeBill();
    await assertFails(setDoc(returnRef(t.db('smPtb')), makeReturn()));
  });

  it('denies a bill update that names a different return', async () => {
    await arrangeBill();
    const db = t.db('smPtb');
    const b = firstReturn('smPtb', {}, db);
    b.update(billRef(db), { returnedQty: { 'puff-veg': 1 }, lastReturnId: R2 });
    await assertFails(b.commit());
  });
});

// ---- #7 the return doc ----------------------------------------------------

describe('#7 returns: the return doc', () => {
  it('denies a return without its audit doc (#10)', async () => {
    await t.arrange((db) => setDoc(billRef(db), storedBill(bill)));
    await arrangeDevice(t);
    await assertFails(firstReturn().commit());
  });

  it('denies a refund sum that does not match refundTotal, and five refunds', async () => {
    await arrangeBill();
    await assertFails(firstReturn('smPtb', { refunds: [{ mode: 'CASH', amount: 2500 }] }).commit());
    const five = [100, 100, 100, 100, 2200].map((amount) => ({ mode: 'CASH', amount }));
    await assertFails(firstReturn('smPtb', { refunds: five }).commit());
  });

  it('accepts a split refund', async () => {
    await arrangeBill();
    const refunds = [{ mode: 'CASH', amount: 1000 }, { mode: 'UPI', amount: 1600 }];
    await assertSucceeds(firstReturn('smPtb', { refunds }).commit());
  });

  it('denies a refundTotal that is not a whole rupee', async () => {
    await arrangeBill();
    await assertFails(firstReturn('smPtb', { refundTotal: 2550, refunds: [{ mode: 'CASH', amount: 2550 }] }).commit());
  });

  it('denies a billNo from another location, and createdBy other than the caller', async () => {
    await arrangeBill();
    const db = t.db('smPtb');
    const b1 = firstReturn('smPtb', {}, db);
    b1.set(returnRef(db), { ...makeReturn(), billNo: `MNJ-${BILL}` });
    await assertFails(b1.commit());
    const b2 = firstReturn('smPtb', {}, db);
    b2.set(returnRef(db), makeReturn({ uid: ACTORS.admin.uid }));
    await assertFails(b2.commit());
  });

  it('denies more than 20 lines, and missing or extra fields', async () => {
    await arrangeBill();
    const lines = Array.from({ length: 21 }, (_, i) => [`p${i}`, 1, 100]);
    await assertFails(firstReturn('smPtb', { lines }).commit());
    const db = t.db('smPtb');
    const { prevReturnId, ...missing } = makeReturn();
    const b = firstReturn('smPtb', {}, db);
    b.set(returnRef(db), missing);
    await assertFails(b.commit());
  });

  it("denies another location's SM and a user without return.create", async () => {
    await arrangeBill();
    await assertFails(firstReturn('smMnj').commit());
    await assertFails(firstReturn('disabled').commit());
  });

  it('denies updating or deleting a return', async () => {
    await t.arrange((db) => setDoc(returnRef(db), { ...makeReturn(), serverCreatedAt: new Date() }));
    await assertFails(updateDoc(returnRef(t.db('admin')), { reason: 'x' }));
    await assertFails(deleteDoc(returnRef(t.db('admin'))));
  });
});

describe('#7 returns: read', () => {
  it('reads like bills: own location, or the Admin', async () => {
    await t.arrange((db) => setDoc(returnRef(db), { ...makeReturn(), serverCreatedAt: new Date() }));
    await assertSucceeds(getDoc(returnRef(t.db('smPtb'))));
    await assertSucceeds(getDocs(collection(t.db('admin'), 'locations', LOC.PTB, 'returns')));
    await assertFails(getDoc(returnRef(t.db('smMnj'))));
    await assertFails(getDoc(returnRef(t.db('disabled'))));
  });
});
