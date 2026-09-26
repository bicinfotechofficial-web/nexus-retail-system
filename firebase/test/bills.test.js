// BE-3: bills create, validation, cancel and returnedQty (04-PERMISSIONS #5-6).

import { describe, it } from 'vitest';
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  query,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
} from 'firebase/firestore';
import { ACTORS, LOC } from './support/fixtures.js';
import { TODAY, TOMORROW, billId, makeBill, makeCancel, manyLines, storedBill } from './support/builders.js';
import { assertFails, assertSucceeds, useRulesEnv } from './support/env.js';

const t = useRulesEnv();

const ID = billId('D01', 1);
const billRef = (db, loc = LOC.PTB, id = ID) => doc(db, 'locations', loc, 'bills', id);

/** Creates the bill as `actor` (rules on). */
const create = (actor, bill = makeBill(), loc = LOC.PTB, id = ID) => setDoc(billRef(t.db(actor), loc, id), bill);

/** Arranges an existing bill (rules off). */
const arrangeBill = (bill = makeBill(), loc = LOC.PTB, id = ID) =>
  t.arrange((db) => setDoc(billRef(db, loc, id), storedBill(bill)));

/**
 * Arranges the CANCEL movement and its audit doc. Their own rules land in
 * BE-4 and BE-5; the cancel rule only needs them to exist after the batch.
 */
const arrangeCancelDocs = ({ loc = LOC.PTB, id = ID, movement = true, audit = true, auditId } = {}) =>
  t.arrange(async (db) => {
    if (movement) await setDoc(doc(db, 'locations', loc, 'movements', `${id}-X`), { type: 'CANCEL' });
    if (audit) await setDoc(doc(db, 'auditLog', auditId ?? `${loc}-${id}-X`), { action: 'BILL_CANCEL' });
  });

// ---- #5 create --------------------------------------------------------

describe('#5 bills: create', () => {
  it('lets an SM create a bill at their location', async () => {
    await assertSucceeds(create('smPtb'));
  });

  it('lets the Admin create a bill at any location', async () => {
    const bill = makeBill({ loc: LOC.MNJ, uid: ACTORS.admin.uid, userName: 'Admin' });
    await assertSucceeds(create('admin', bill, LOC.MNJ));
  });

  it('denies a duplicate create of the same bill ID', async () => {
    await assertSucceeds(create('smPtb'));
    await assertFails(create('smPtb'));
    // Not even a different bill under the same ID.
    await assertFails(create('smPtb', makeBill({ lines: [['puff-veg', 1, 2500]] })));
  });

  it('denies an SM creating a bill at another location', async () => {
    const bill = makeBill({ loc: LOC.MNJ });
    await assertFails(create('smPtb', bill, LOC.MNJ));
  });

  it('denies a disabled user, a user without a profile and an anonymous user', async () => {
    await assertFails(create('disabled', makeBill({ uid: ACTORS.disabled.uid })));
    await assertFails(create('noProfile', makeBill({ uid: ACTORS.noProfile.uid })));
    await assertFails(create('anonymous'));
  });
});

// ---- #6 validation ----------------------------------------------------
// The rules check what #6 lists. Line arithmetic, positive quantities and
// payment modes and signs are BillCalculator's: at 20 lines there's no room
// for them in the 1000-expression budget (see firestore.rules).

describe('#6 bills: validation', () => {
  it('accepts a discounted bill with round-off and a split payment', async () => {
    const bill = makeBill({
      lines: [['cake-choco-1kg', 1, 65000], ['puff-veg', 3, 2550]],
      discount: { type: 'PCT', value: 10, amount: 7265 },
      payments: [{ mode: 'CASH', amount: 30000 }, { mode: 'UPI', amount: 35400, ref: 'UPI-REF-1' }],
    });
    // 72650 − 7265 = 65385 → 65400, round-off +15.
    if (bill.total !== 65400 || bill.roundOff !== 15) throw new Error('builder arithmetic changed');
    await assertSucceeds(create('smPtb', bill));
  });

  it('accepts four payments and denies five', async () => {
    const four = [
      { mode: 'CASH', amount: 10000 },
      { mode: 'UPI', amount: 20000 },
      { mode: 'CARD', amount: 30000 },
      { mode: 'WALLET', amount: 10100 },
    ];
    await assertSucceeds(create('smPtb', makeBill({ payments: four })));
    const five = [...four.slice(0, 3), { mode: 'WALLET', amount: 10000 }, { mode: 'OTHER', amount: 100 }];
    await assertFails(create('smPtb', makeBill({ seq: 2, payments: five }), LOC.PTB, billId('D01', 2)));
  });

  it('denies a bad payment sum', async () => {
    await assertFails(create('smPtb', makeBill({ payments: [{ mode: 'CASH', amount: 70000 }] })));
    await assertFails(
      create('smPtb', makeBill({ payments: [{ mode: 'CASH', amount: 50000 }, { mode: 'UPI', amount: 30000 }] })),
    );
  });

  it('denies a total that is not a whole rupee', async () => {
    const bill = makeBill();
    const total = bill.total + 50;
    await assertFails(create('smPtb', { ...bill, total, payments: [{ mode: 'CASH', amount: total }] }));
  });

  it('denies a billNo, deviceId or seq that disagrees with the bill ID', async () => {
    const bill = makeBill();
    await assertFails(create('smPtb', { ...bill, billNo: `MNJ-${ID}` }));
    await assertFails(create('smPtb', { ...bill, billNo: ID }));
    await assertFails(create('smPtb', { ...bill, deviceId: 'D02' }));
    await assertFails(create('smPtb', { ...bill, seq: 2 }));
  });

  it('denies a malformed bill ID', async () => {
    const bill = makeBill();
    await assertFails(create('smPtb', { ...bill, billNo: 'PTB-D1-000001' }, LOC.PTB, 'D1-000001'));
    await assertFails(create('smPtb', { ...bill, billNo: 'PTB-D01-1' }, LOC.PTB, 'D01-1'));
  });

  it('denies createdBy other than the caller', async () => {
    await assertFails(create('smPtb', { ...makeBill(), createdBy: ACTORS.smMnj.uid }));
  });

  it('denies a bill that starts cancelled, returned or with a lastReturnId', async () => {
    const bill = makeBill();
    await assertFails(create('smPtb', { ...bill, status: 'CANCELLED' }));
    await assertFails(create('smPtb', { ...bill, cancel: makeCancel() }));
    await assertFails(create('smPtb', { ...bill, returnedQty: { 'puff-veg': 1 } }));
    await assertFails(create('smPtb', { ...bill, lastReturnId: 'D01-R000001' }));
  });

  it('denies soldQty that does not match the lines', async () => {
    const bill = makeBill();
    await assertFails(create('smPtb', { ...bill, soldQty: { 'cake-choco-1kg': 1 } }));
    await assertFails(create('smPtb', { ...bill, soldQty: { 'cake-choco-1kg': 1, 'puff-veg': 3 } }));
    await assertFails(create('smPtb', { ...bill, soldQty: { 'cake-choco-1kg': 1, 'puff-veg': 2, extra: 1 } }));
    await assertFails(create('smPtb', { ...bill, soldQty: { 'cake-choco-1kg': 1, 'puff-egg': 2 } }));
  });

  it('denies two lines for one product (D-024)', async () => {
    const bill = makeBill({ lines: [['puff-veg', 1, 2550], ['puff-veg', 2, 2550]] });
    // The builder's soldQty collapses to one key.
    await assertFails(create('smPtb', { ...bill, payments: [{ mode: 'CASH', amount: bill.total }] }));
  });

  it('accepts 20 lines with 4 payments, the largest bill, and denies 21 lines (D-030)', async () => {
    const payments = [
      { mode: 'CASH', amount: 50000 },
      { mode: 'UPI', amount: 50000 },
      { mode: 'CARD', amount: 50000 },
      { mode: 'WALLET', amount: 50000 },
    ];
    await assertSucceeds(create('smPtb', makeBill({ lines: manyLines(20), payments })));
    const id2 = billId('D01', 2);
    await assertFails(create('smPtb', makeBill({ seq: 2, lines: manyLines(21) }), LOC.PTB, id2));
  });

  it('denies an empty bill', async () => {
    const bill = makeBill({ lines: [] });
    await assertFails(create('smPtb', { ...bill, payments: [] }));
  });

  it('denies a client serverCreatedAt, a bad businessDate, and missing or extra fields', async () => {
    const bill = makeBill();
    await assertFails(create('smPtb', { ...bill, serverCreatedAt: new Date() }));
    await assertFails(create('smPtb', { ...bill, businessDate: '26-09-2026' }));
    const { cashTendered, ...missing } = bill;
    await assertFails(create('smPtb', missing));
    await assertFails(create('smPtb', { ...bill, note: 'x' }));
  });
});

// ---- #5 read ----------------------------------------------------------

describe('#5 bills: read', () => {
  it("lets an SM read and query their location's bills", async () => {
    await arrangeBill();
    const db = t.db('smPtb');
    await assertSucceeds(getDoc(billRef(db)));
    const bills = collection(db, 'locations', LOC.PTB, 'bills');
    await assertSucceeds(getDocs(query(bills, where('businessDate', '==', TODAY))));
  });

  it('lets the Admin read every location', async () => {
    await arrangeBill(makeBill({ loc: LOC.MNJ }), LOC.MNJ);
    await assertSucceeds(getDoc(billRef(t.db('admin'), LOC.MNJ)));
  });

  it("denies another location's SM and a disabled user", async () => {
    await arrangeBill();
    await assertFails(getDoc(billRef(t.db('smMnj'))));
    await assertFails(getDocs(collection(t.db('smMnj'), 'locations', LOC.PTB, 'bills')));
    await assertFails(getDoc(billRef(t.db('disabled'))));
  });
});

// ---- #5(a) cancel -----------------------------------------------------

describe('#5(a) bills: cancel', () => {
  const cancel = (actor, fields = {}) =>
    updateDoc(billRef(t.db(actor)), { status: 'CANCELLED', cancel: makeCancel({ uid: ACTORS[actor].uid }), ...fields });

  it('lets an SM cancel a same-day bill with its CANCEL movement and audit doc', async () => {
    await arrangeBill();
    await arrangeCancelDocs();
    await assertSucceeds(cancel('smPtb'));
  });

  it('denies a next-day cancel', async () => {
    await arrangeBill();
    await arrangeCancelDocs();
    await assertFails(
      updateDoc(billRef(t.db('smPtb')), { status: 'CANCELLED', cancel: makeCancel({ businessDate: TOMORROW }) }),
    );
  });

  it('denies a cancel without the CANCEL movement or the audit doc', async () => {
    await arrangeBill();
    await arrangeCancelDocs({ movement: false });
    await assertFails(cancel('smPtb'));
    await t.arrange((db) => deleteDoc(doc(db, 'auditLog', `${LOC.PTB}-${ID}-X`)));
    await arrangeCancelDocs({ audit: false });
    await assertFails(cancel('smPtb'));
  });

  it('denies an audit doc without the location prefix (D-028)', async () => {
    await arrangeBill();
    await arrangeCancelDocs({ auditId: `${ID}-X` });
    await assertFails(cancel('smPtb'));
  });

  it('denies cancel.by other than the caller, and an empty reason', async () => {
    await arrangeBill();
    await arrangeCancelDocs();
    const ref = billRef(t.db('smPtb'));
    await assertFails(updateDoc(ref, { status: 'CANCELLED', cancel: makeCancel({ uid: ACTORS.admin.uid }) }));
    await assertFails(updateDoc(ref, { status: 'CANCELLED', cancel: makeCancel({ reason: '' }) }));
  });

  it('denies cancelling a bill that has a return (D-025)', async () => {
    await arrangeBill({ ...makeBill(), returnedQty: { 'puff-veg': 1 }, lastReturnId: 'D01-R000001' });
    await arrangeCancelDocs();
    await assertFails(cancel('smPtb'));
  });

  it('denies cancelling twice', async () => {
    await arrangeBill({ ...makeBill(), status: 'CANCELLED', cancel: makeCancel() });
    await arrangeCancelDocs();
    await assertFails(cancel('smPtb', { cancel: makeCancel({ reason: 'again' }) }));
  });

  it('denies changing anything else with the cancel', async () => {
    await arrangeBill();
    await arrangeCancelDocs();
    await assertFails(cancel('smPtb', { total: 0 }));
    await assertFails(cancel('smPtb', { payments: [] }));
  });

  it('denies status changes that are not COMPLETED to CANCELLED', async () => {
    await arrangeBill();
    await arrangeCancelDocs();
    await assertFails(updateDoc(billRef(t.db('smPtb')), { status: 'REFUNDED', cancel: makeCancel() }));
    await assertFails(updateDoc(billRef(t.db('smPtb')), { status: 'CANCELLED' }));
  });

  it("denies another location's SM, and a user without bill.cancel", async () => {
    await arrangeBill();
    await arrangeCancelDocs();
    await assertFails(cancel('smMnj'));
    await assertFails(cancel('disabled'));
  });

  it('lets the Admin cancel at any location', async () => {
    await arrangeBill();
    await arrangeCancelDocs();
    await assertSucceeds(cancel('admin'));
  });
});

// ---- #5(b) returnedQty ------------------------------------------------

describe('#5(b) bills: returnedQty', () => {
  const RETURN_ID = 'D01-R000001';

  it.todo('lets a return raise returnedQty with a new return doc (BE-4, once returns can be created)');
  it.todo('denies a return on a cancelled bill (BE-4)');
  it.todo('denies returnedQty above soldQty, or lowered (BE-4)');
  it.todo('denies a stale return: prevReturnId is not the bill\'s lastReturnId (QA-024, BE-4)');
  it.todo('accepts the second return when its prevReturnId is the first return (BE-4)');

  it('denies raising returnedQty without a new return doc', async () => {
    await arrangeBill();
    const ref = billRef(t.db('smPtb'));
    await assertFails(updateDoc(ref, { returnedQty: { 'puff-veg': 1 } }));
    await assertFails(updateDoc(ref, { returnedQty: { 'puff-veg': 1 }, lastReturnId: RETURN_ID }));
  });

  it('denies naming a return that already existed before the batch', async () => {
    await arrangeBill();
    await t.arrange((db) => setDoc(doc(db, 'locations', LOC.PTB, 'returns', RETURN_ID), { billId: ID }));
    await assertFails(updateDoc(billRef(t.db('smPtb')), { returnedQty: { 'puff-veg': 1 }, lastReturnId: RETURN_ID }));
  });

  it('denies changing anything else with returnedQty', async () => {
    await arrangeBill();
    await assertFails(updateDoc(billRef(t.db('smPtb')), { returnedQty: { 'puff-veg': 1 }, total: 0 }));
  });
});

// ---- delete -----------------------------------------------------------

describe('#5 bills: delete', () => {
  it('denies deleting a bill, even for the Admin', async () => {
    await arrangeBill();
    await assertFails(deleteDoc(billRef(t.db('admin'))));
  });

  it('denies any other update', async () => {
    await arrangeBill();
    await assertFails(updateDoc(billRef(t.db('admin')), { serverCreatedAt: serverTimestamp() }));
    await assertFails(updateDoc(billRef(t.db('admin')), { servedBy: { uid: 'x', name: 'y' } }));
  });
});
