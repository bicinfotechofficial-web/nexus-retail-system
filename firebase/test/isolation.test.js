// BE-6: cross-location isolation (04-PERMISSIONS #13). A Store Manager at
// PTB can read or write nothing under locations/MNJ/**: the location doc and
// every subcollection, every read (get and list) and every write kind
// (create, update, set(merge), delete, and the whole business batches).
//
// Every case runs twice: the Store Manager at PTB is denied, and then the
// same operation, made by the Store Manager at MNJ, is accepted. The second
// half shows the denial is about the location, not a malformed write.

import { describe, it } from 'vitest';
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  serverTimestamp,
  setDoc,
  updateDoc,
  writeBatch,
} from 'firebase/firestore';
import { ACTORS, LOC } from './support/fixtures.js';
import {
  TODAY,
  billId,
  customerFields,
  makeAudit,
  makeBill,
  makeMovement,
  makeReturn,
  movementId,
  returnId,
  stockWrite,
  storedBill,
  storedCustomer,
  summaryWrite,
} from './support/builders.js';
import { arrangeDevice, billBatch, cancelBatch, returnBatch, stockBatch } from './support/batches.js';
import { assertFails, assertSucceeds, useRulesEnv } from './support/env.js';

const t = useRulesEnv();

const MNJ = LOC.MNJ;
const BILL = billId('D01', 1);
const R1 = returnId('D01', 1);
const M1 = movementId('D01', 1);
const MONTH = TODAY.slice(0, 7);

const at = (db, ...path) => doc(db, 'locations', MNJ, ...path);
const uid = (actor) => ACTORS[actor].uid;

/**
 * State at MNJ that every subcollection read needs: device D01, a bill, a
 * return, a movement, a stock doc and both summaries. Written with the
 * rules off.
 */
async function arrangeMnj() {
  await arrangeDevice(t, MNJ);
  await t.arrange(async (db) => {
    const bill = makeBill({ loc: MNJ, uid: uid('smMnj') });
    await setDoc(at(db, 'bills', BILL), storedBill(bill));
    await setDoc(at(db, 'returns', R1), { ...makeReturn({ loc: MNJ, uid: uid('smMnj') }), serverCreatedAt: new Date() });
    await setDoc(at(db, 'movements', M1), { ...makeMovement({ uid: uid('smMnj') }), serverCreatedAt: new Date() });
    await setDoc(at(db, 'stock', 'RM_flour'), { ...stockWrite('RM_flour', 0, M1), qty: 5000, updatedAt: new Date() });
    await setDoc(at(db, 'dailySummary', TODAY), { billCount: 1, lastWriteRef: `locations/${MNJ}/bills/${BILL}` });
    await setDoc(at(db, 'monthlySummary', MONTH), { billCount: 1, lastWriteRef: `locations/${MNJ}/bills/${BILL}` });
    await setDoc(at(db, 'customers', customerFields().customerId), storedCustomer());
  });
}

// ---- Reads ------------------------------------------------------------------

const DOCS = [
  ['the location doc', []],
  ['a device', ['devices', 'D01']],
  ['a bill', ['bills', BILL]],
  ['a return', ['returns', R1]],
  ['a movement', ['movements', M1]],
  ['a stock doc', ['stock', 'RM_flour']],
  ['a daily summary', ['dailySummary', TODAY]],
  ['a monthly summary', ['monthlySummary', MONTH]],
  ['a customer', ['customers', customerFields().customerId]],
];

const COLLECTIONS = ['devices', 'bills', 'returns', 'movements', 'stock', 'dailySummary', 'monthlySummary', 'customers'];

describe('#13 isolation: SM@PTB reads nothing at MNJ', () => {
  it.each(DOCS)('denies a get of %s', async (_, path) => {
    await arrangeMnj();
    await assertFails(getDoc(at(t.db('smPtb'), ...path)));
    await assertSucceeds(getDoc(at(t.db('smMnj'), ...path)));
  });

  it.each(COLLECTIONS)('denies listing %s', async (name) => {
    await arrangeMnj();
    await assertFails(getDocs(collection(t.db('smPtb'), 'locations', MNJ, name)));
    await assertSucceeds(getDocs(collection(t.db('smMnj'), 'locations', MNJ, name)));
  });
});

// ---- Writes -----------------------------------------------------------------

/**
 * Each write kind as `(db, actor) => Promise`, valid for the actor at MNJ,
 * with the state it needs. The ids advance per actor where a successful
 * write by one would block the other's.
 */
const WRITES = [
  {
    name: 'registering a device (nextDeviceNo +1 and devices/D01)',
    write: (db, actor) => {
      const b = writeBatch(db);
      b.update(doc(db, 'locations', MNJ), { nextDeviceNo: 1 });
      b.set(at(db, 'devices', 'D01'), {
        code: 'D01',
        label: 'Counter 1',
        registeredBy: uid(actor),
        registeredAt: serverTimestamp(),
        lastSeenAt: serverTimestamp(),
        lastBillSeq: 0,
        lastMovementSeq: 0,
        lastReturnSeq: 0,
        retired: false,
      });
      return b.commit();
    },
  },
  {
    name: 'a device counter update (lastBillSeq, lastMovementSeq, lastReturnSeq)',
    arrange: () => arrangeDevice(t, MNJ),
    write: (db) => updateDoc(at(db, 'devices', 'D01'), { lastBillSeq: 1, lastMovementSeq: 1, lastReturnSeq: 1 }),
  },
  {
    name: 'a device lastSeenAt stamp',
    arrange: () => arrangeDevice(t, MNJ),
    write: (db) => updateDoc(at(db, 'devices', 'D01'), { lastSeenAt: serverTimestamp() }),
  },
  {
    name: 'the complete bill batch (bill, stock, SALE movement, device, summaries)',
    arrange: () => arrangeDevice(t, MNJ),
    write: (db, actor) => billBatch(db, makeBill({ loc: MNJ, uid: uid(actor) }), { loc: MNJ, full: true }).commit(),
  },
  {
    name: 'a bill on its own',
    write: (db, actor) => setDoc(at(db, 'bills', BILL), makeBill({ loc: MNJ, uid: uid(actor) })),
  },
  {
    name: 'the complete cancel batch (bill update, stock, CANCEL movement, summaries, audit)',
    arrange: async () => {
      await arrangeDevice(t, MNJ);
      await t.arrange((db) => setDoc(at(db, 'bills', BILL), storedBill(makeBill({ loc: MNJ, uid: uid('smMnj') }))));
    },
    write: (db, actor) => cancelBatch(db, makeBill({ loc: MNJ }), { loc: MNJ, uid: uid(actor) }).commit(),
  },
  {
    name: 'the complete return batch (return, bill update, stock, RETURN movement, device, summaries, audit)',
    arrange: async () => {
      await arrangeDevice(t, MNJ);
      await t.arrange((db) => setDoc(at(db, 'bills', BILL), storedBill(makeBill({ loc: MNJ, uid: uid('smMnj') }))));
    },
    write: (db, actor) =>
      returnBatch(db, {
        loc: MNJ,
        rid: R1,
        ret: makeReturn({ loc: MNJ, uid: uid(actor) }),
        returnedQty: { 'puff-veg': 1 },
        seq: 1,
        full: true,
      }).commit(),
  },
  {
    name: 'a STOCK_IN batch (movement, stock set(merge), device)',
    arrange: () => arrangeDevice(t, MNJ),
    write: (db, actor) =>
      stockBatch(db, { loc: MNJ, mid: M1, movement: makeMovement({ uid: uid(actor) }), seq: 1 }).commit(),
  },
  {
    name: 'an ADJUST batch with its audit doc',
    arrange: () => arrangeDevice(t, MNJ),
    write: (db, actor) => {
      const movement = makeMovement({ type: 'ADJUST', lines: [['RM_flour', -120]], reason: 'Physical count', uid: uid(actor) });
      const b = stockBatch(db, { loc: MNJ, mid: M1, movement, seq: 1 });
      b.set(
        doc(db, 'auditLog', `${MNJ}-${M1}`),
        makeAudit({ action: 'STOCK_ADJUST', entityPath: `locations/${MNJ}/movements/${M1}`, locationId: MNJ, uid: uid(actor) }),
      );
      return b.commit();
    },
  },
  {
    name: 'a WASTAGE_FG batch with its audit doc',
    arrange: () => arrangeDevice(t, MNJ),
    write: (db, actor) => {
      const movement = makeMovement({ type: 'WASTAGE_FG', lines: [['FG_cake', -1]], reason: 'Dropped', uid: uid(actor) });
      const b = stockBatch(db, { loc: MNJ, mid: M1, movement, seq: 1 });
      b.set(
        doc(db, 'auditLog', `${MNJ}-${M1}`),
        makeAudit({ action: 'WASTAGE', entityPath: `locations/${MNJ}/movements/${M1}`, locationId: MNJ, uid: uid(actor) }),
      );
      return b.commit();
    },
  },
  {
    name: 'a stock threshold update',
    arrange: arrangeMnj,
    write: (db) => updateDoc(at(db, 'stock', 'RM_flour'), { lowThreshold: 1000, updatedAt: serverTimestamp() }),
  },
  {
    name: 'a stock rename with set(merge)',
    arrange: arrangeMnj,
    write: (db) => setDoc(at(db, 'stock', 'RM_flour'), { name: 'Maida', updatedAt: serverTimestamp() }, { merge: true }),
  },
  {
    name: 'an audit doc for an MNJ event',
    write: (db, actor) =>
      setDoc(
        doc(db, 'auditLog', `${MNJ}-D01-OVR-1790000000000`),
        makeAudit({ action: 'OFFLINE_OVERRIDE', entityPath: `locations/${MNJ}/devices/D01`, locationId: MNJ, uid: uid(actor) }),
      ),
  },
];

describe('#13 isolation: SM@PTB writes nothing at MNJ', () => {
  it.each(WRITES.map((w) => [w.name, w]))('denies %s', async (_, w) => {
    if (w.arrange) await w.arrange();
    await assertFails(w.write(t.db('smPtb'), 'smPtb'));
    await assertSucceeds(w.write(t.db('smMnj'), 'smMnj'));
  });
});

// Writes nobody may make are denied to SM@PTB at MNJ as well, whatever the
// reason; these have no MNJ control.
describe('#13 isolation: other MNJ writes', () => {
  it('denies SM@PTB editing the MNJ location doc', async () => {
    await assertFails(updateDoc(doc(t.db('smPtb'), 'locations', MNJ), { receiptFooter: 'Hello' }));
    await assertFails(setDoc(doc(t.db('smPtb'), 'locations', MNJ), { receiptFooter: 'Hello' }, { merge: true }));
  });

  it('denies SM@PTB feeding its own new PTB bill into an MNJ summary', async () => {
    await arrangeDevice(t);
    const db = t.db('smPtb');
    const ref = `locations/${LOC.PTB}/bills/${BILL}`;
    const b = billBatch(db, makeBill());
    b.set(at(db, 'dailySummary', TODAY), summaryWrite(ref), { merge: true });
    b.set(at(db, 'monthlySummary', MONTH), summaryWrite(ref), { merge: true });
    await assertFails(b.commit());
    // The same bill with its own PTB summaries is fine.
    await assertSucceeds(billBatch(db, makeBill(), { full: true }).commit());
  });

  it('denies SM@PTB every delete at MNJ', async () => {
    await arrangeMnj();
    const db = t.db('smPtb');
    await assertFails(deleteDoc(doc(db, 'locations', MNJ)));
    for (const [, path] of DOCS.slice(1)) await assertFails(deleteDoc(at(db, ...path)));
  });

  it('denies a PTB batch that also touches one MNJ doc, as a whole', async () => {
    await arrangeDevice(t);
    await arrangeDevice(t, MNJ);
    const db = t.db('smPtb');
    const b = billBatch(db, makeBill(), { full: true });
    // On its own, any active user at MNJ may make this write.
    b.update(at(db, 'devices', 'D01'), { lastSeenAt: serverTimestamp() });
    await assertFails(b.commit());
    await assertSucceeds(billBatch(db, makeBill(), { full: true }).commit());
  });
});
