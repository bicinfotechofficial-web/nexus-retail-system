// BE-4: movements and stock (04-PERMISSIONS #7, #8), and the SALE side of
// the bill batch.

import { describe, it } from 'vitest';
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  increment,
  serverTimestamp,
  setDoc,
  updateDoc,
  writeBatch,
} from 'firebase/firestore';
import { ACTORS, LOC } from './support/fixtures.js';
import { makeBill, makeMovement, manyLines, movementId, stockWrite } from './support/builders.js';
import { arrangeDevice, billBatch, stockBatch } from './support/batches.js';
import { assertFails, assertSucceeds, useRulesEnv } from './support/env.js';

const t = useRulesEnv();

const M1 = movementId('D01', 1);
const stockRef = (db, key, loc = LOC.PTB) => doc(db, 'locations', loc, 'stock', key);
const movementRef = (db, id = M1, loc = LOC.PTB) => doc(db, 'locations', loc, 'movements', id);
const arrangeAudit = (id, loc = LOC.PTB) => t.arrange((db) => setDoc(doc(db, 'auditLog', `${loc}-${id}`), { x: 1 }));

/** Arranges an existing stock doc (rules off). */
const arrangeStock = (key, qty, extra = {}) =>
  t.arrange((db) =>
    setDoc(stockRef(db, key), {
      ...stockWrite(key, 0, 'D01-M000000'),
      qty,
      updatedAt: new Date(),
      ...extra,
    }),
  );

/** Switches SM@PTB to a one-off role with exactly these permissions. */
const withRole = (permissions) =>
  t.arrange(async (db) => {
    await setDoc(doc(db, 'roles/TEST'), { name: 'Test', permissions, allLocations: false });
    await updateDoc(doc(db, 'users', ACTORS.smPtb.uid), { roleId: 'TEST' });
  });

// ---- Stock operation batches -------------------------------------------

describe('#7-8 stock operation batches', () => {
  it('accepts a STOCK_IN batch that creates the stock docs on first use', async () => {
    await arrangeDevice(t);
    const movement = makeMovement({ lines: [['RM_flour', 5000], ['RM_cream', 2000]], note: 'Supplier A' });
    await assertSucceeds(stockBatch(t.db('smPtb'), { mid: M1, movement, seq: 1 }).commit());
    let qty;
    await t.arrange(async (db) => (qty = (await getDoc(stockRef(db, 'RM_flour'))).data().qty));
    if (qty !== 5000) throw new Error(`qty ${qty}`);
  });

  it('accepts a 20-line PRODUCE batch (D-030)', async () => {
    await arrangeDevice(t);
    const lines = [...Array.from({ length: 19 }, (_, i) => [`RM_m${i}`, -100]), ['FG_cake', 2]];
    await assertSucceeds(stockBatch(t.db('smPtb'), { mid: M1, movement: makeMovement({ type: 'PRODUCE', lines }), seq: 1 }).commit());
  });

  it('accepts ADJUST and WASTAGE with a reason and their audit doc', async () => {
    await arrangeDevice(t);
    await arrangeStock('RM_flour', 5000);
    await arrangeAudit(M1);
    const adjust = makeMovement({ type: 'ADJUST', lines: [['RM_flour', -120]], reason: 'Physical count' });
    await assertSucceeds(stockBatch(t.db('smPtb'), { mid: M1, movement: adjust, seq: 1 }).commit());
    const M2 = movementId('D01', 2);
    await arrangeAudit(M2);
    const waste = makeMovement({ type: 'WASTAGE_RAW', lines: [['RM_flour', -80]], reason: 'Spilled' });
    await assertSucceeds(stockBatch(t.db('smPtb'), { mid: M2, movement: waste, seq: 2 }).commit());
  });

  it('denies ADJUST and WASTAGE without their audit doc, or without a reason', async () => {
    await arrangeDevice(t);
    const db = t.db('smPtb');
    const adjust = makeMovement({ type: 'ADJUST', lines: [['RM_flour', -120]], reason: 'Physical count' });
    await assertFails(stockBatch(db, { mid: M1, movement: adjust, seq: 1 }).commit());
    await arrangeAudit(M1);
    await assertFails(stockBatch(db, { mid: M1, movement: { ...adjust, reason: '' }, seq: 1 }).commit());
    const waste = makeMovement({ type: 'WASTAGE_FG', lines: [['FG_cake', -1]], reason: null });
    await assertFails(stockBatch(db, { mid: M1, movement: waste, seq: 1 }).commit());
  });

  it('denies an audit doc without the location prefix (D-028)', async () => {
    await arrangeDevice(t);
    await t.arrange((db) => setDoc(doc(db, 'auditLog', M1), { x: 1 }));
    const adjust = makeMovement({ type: 'ADJUST', lines: [['RM_flour', -120]], reason: 'Physical count' });
    await assertFails(stockBatch(t.db('smPtb'), { mid: M1, movement: adjust, seq: 1 }).commit());
  });

  it('refreshes a renamed item on the next write (QA-023)', async () => {
    await arrangeDevice(t);
    await arrangeStock('FG_cake', 10, { name: 'Black Forest 1 kg' });
    const movement = makeMovement({ type: 'PRODUCE', lines: [['FG_cake', 2]] });
    const names = { FG_cake: 'Black Forest Cake 1 kg' };
    await assertSucceeds(stockBatch(t.db('smPtb'), { mid: M1, movement, seq: 1, names }).commit());
  });
});

// ---- #7 movements --------------------------------------------------------

describe('#7 movements: create', () => {
  const create = (actor, movement, id = M1, loc = LOC.PTB) => setDoc(movementRef(t.db(actor), id, loc), movement);

  it('matches each type to its permission', async () => {
    await withRole(['stock.adjust']);
    await assertFails(create('smPtb', makeMovement()));
    await arrangeAudit(M1);
    await assertSucceeds(create('smPtb', makeMovement({ type: 'ADJUST', reason: 'Count' })));
  });

  it('denies stock movements to a role with only bill.create', async () => {
    await withRole(['bill.create']);
    await assertFails(create('smPtb', makeMovement()));
    await assertFails(create('smPtb', makeMovement({ type: 'PRODUCE' })));
  });

  it('requires bill.create for SALE, bill.cancel for CANCEL and return.create for RETURN', async () => {
    const sale = makeMovement({ type: 'SALE', lines: [['FG_cake', -1]], refId: 'D01-000001' });
    const cancel = makeMovement({ type: 'CANCEL', lines: [['FG_cake', 1]], refId: 'D01-000001', reason: 'Wrong item' });
    const ret = makeMovement({ type: 'RETURN', lines: [['FG_cake', 1]], refId: 'D01-R000001' });
    await withRole(['stock.move', 'stock.adjust']);
    await assertFails(create('smPtb', sale, 'D01-000001'));
    await assertFails(create('smPtb', cancel, 'D01-000001-X'));
    await assertFails(create('smPtb', ret, 'D01-R000001'));
    await withRole(['bill.create', 'bill.cancel', 'return.create']);
    await assertSucceeds(create('smPtb', sale, 'D01-000001'));
    await assertSucceeds(create('smPtb', cancel, 'D01-000001-X'));
    await assertSucceeds(create('smPtb', ret, 'D01-R000001'));
  });

  it('lets another device cancel a bill (CANCEL keeps the bill ID)', async () => {
    const cancel = makeMovement({ type: 'CANCEL', lines: [['FG_cake', 1]], refId: 'D01-000001', reason: 'x', deviceId: 'D02' });
    await assertSucceeds(create('smPtb', cancel, 'D01-000001-X'));
  });

  it('denies an ID that does not fit the type, device or refId', async () => {
    await assertFails(create('smPtb', makeMovement(), 'D01-000001'));
    await assertFails(create('smPtb', makeMovement({ deviceId: 'D02' })));
    await assertFails(create('smPtb', makeMovement({ type: 'SALE', lines: [['FG_cake', -1]], refId: 'D01-000002' }), 'D01-000001'));
    await assertFails(create('smPtb', makeMovement({ type: 'SALE', lines: [['FG_cake', -1]], refId: 'D01-000001' }), M1));
  });

  it('denies an unknown type, createdBy other than the caller, and bad fields', async () => {
    await assertFails(create('smPtb', makeMovement({ type: 'GIFT' })));
    await assertFails(create('smPtb', makeMovement({ uid: ACTORS.admin.uid })));
    await assertFails(create('smPtb', { ...makeMovement(), serverCreatedAt: new Date() }));
    await assertFails(create('smPtb', { ...makeMovement(), businessDate: 'today' }));
    await assertFails(create('smPtb', { ...makeMovement(), extra: 1 }));
    const { note, ...missing } = makeMovement();
    await assertFails(create('smPtb', missing));
  });

  it('accepts 20 lines and denies 21 or none (D-030)', async () => {
    const lines = (n) => Array.from({ length: n }, (_, i) => [`RM_m${i}`, 10]);
    await assertSucceeds(create('smPtb', makeMovement({ lines: lines(20) })));
    await assertFails(create('smPtb', makeMovement({ lines: lines(21) }), movementId('D01', 2)));
    await assertFails(create('smPtb', makeMovement({ lines: [] }), movementId('D01', 3)));
  });

  it('denies a duplicate movement ID (create-only, !exists)', async () => {
    await assertSucceeds(create('smPtb', makeMovement()));
    await assertFails(create('smPtb', makeMovement({ lines: [['RM_sugar', 10]] })));
  });

  it("denies another location's SM, a disabled user and an anonymous user", async () => {
    await assertFails(create('smMnj', makeMovement({ uid: ACTORS.smMnj.uid })));
    await assertFails(create('disabled', makeMovement({ uid: ACTORS.disabled.uid })));
    await assertFails(create('anonymous', makeMovement()));
  });

  it('denies updating or deleting a movement', async () => {
    await t.arrange((db) => setDoc(movementRef(db), { ...makeMovement(), serverCreatedAt: new Date() }));
    await assertFails(updateDoc(movementRef(t.db('admin')), { reason: 'x' }));
    await assertFails(deleteDoc(movementRef(t.db('admin'))));
  });
});

describe('#7 movements: read', () => {
  it('lets stock.move, stock.adjust or report.own at the location read', async () => {
    await t.arrange((db) => setDoc(movementRef(db), { ...makeMovement(), serverCreatedAt: new Date() }));
    await assertSucceeds(getDoc(movementRef(t.db('smPtb'))));
    await assertSucceeds(getDocs(collection(t.db('admin'), 'locations', LOC.PTB, 'movements')));
    await withRole(['report.own']);
    await assertSucceeds(getDoc(movementRef(t.db('smPtb'))));
  });

  it("denies another location's SM, and a role with none of the three", async () => {
    await t.arrange((db) => setDoc(movementRef(db), { ...makeMovement(), serverCreatedAt: new Date() }));
    await assertFails(getDoc(movementRef(t.db('smMnj'))));
    await withRole(['bill.create']);
    await assertFails(getDoc(movementRef(t.db('smPtb'))));
  });
});

// ---- #8 stock ------------------------------------------------------------

describe('#8 stock: qty', () => {
  it('denies a qty change without a movement', async () => {
    await arrangeStock('RM_flour', 5000);
    const db = t.db('smPtb');
    await assertFails(updateDoc(stockRef(db, 'RM_flour'), { qty: increment(100), updatedAt: serverTimestamp() }));
    await assertFails(setDoc(stockRef(db, 'RM_flour'), stockWrite('RM_flour', 100, M1), { merge: true }));
  });

  it('denies a qty change that names a movement that already existed', async () => {
    await arrangeStock('RM_flour', 5000);
    await t.arrange((db) => setDoc(movementRef(db), { ...makeMovement(), serverCreatedAt: new Date() }));
    const db = t.db('smPtb');
    await assertFails(setDoc(stockRef(db, 'RM_flour'), stockWrite('RM_flour', 5000, M1), { merge: true }));
  });

  it('denies creating a stock doc with qty but no movement', async () => {
    await assertFails(setDoc(stockRef(t.db('smPtb'), 'RM_flour'), stockWrite('RM_flour', 5000, M1), { merge: true }));
  });

  it('denies a literal qty that is not an int', async () => {
    await arrangeDevice(t);
    const movement = makeMovement();
    const db = t.db('smPtb');
    const b = writeBatch(db);
    b.set(movementRef(db), movement);
    b.set(stockRef(db, 'RM_flour'), { ...stockWrite('RM_flour', 0, M1), qty: 'lots' }, { merge: true });
    await assertFails(b.commit());
  });
});

describe('#8 stock: fields', () => {
  it('denies an itemKey that does not match kind and refId', async () => {
    await arrangeDevice(t);
    const db = t.db('smPtb');
    const b = writeBatch(db);
    b.set(movementRef(db), makeMovement({ lines: [['FG_flour', 10]] }));
    b.set(stockRef(db, 'FG_flour'), stockWrite('RM_flour', 10, M1), { merge: true });
    await assertFails(b.commit());
  });

  it('denies changing kind, refId or unit on an existing doc', async () => {
    await arrangeStock('RM_flour', 5000);
    const ref = stockRef(t.db('admin'), 'RM_flour');
    await assertFails(updateDoc(ref, { kind: 'FINISHED', updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(ref, { refId: 'sugar', updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(ref, { unit: 'ML', updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(ref, { owner: 'x', updatedAt: serverTimestamp() }));
  });

  it('lets any active user at the location refresh the name', async () => {
    await arrangeStock('RM_flour', 5000);
    await assertSucceeds(updateDoc(stockRef(t.db('smPtb'), 'RM_flour'), { name: 'Maida', updatedAt: serverTimestamp() }));
  });

  it('denies a client updatedAt', async () => {
    await arrangeStock('RM_flour', 5000);
    await assertFails(updateDoc(stockRef(t.db('smPtb'), 'RM_flour'), { name: 'Maida', updatedAt: new Date() }));
  });

  it('lets stock.threshold set or clear lowThreshold, even before the item is stocked', async () => {
    await arrangeStock('RM_flour', 5000);
    const db = t.db('smPtb');
    await assertSucceeds(updateDoc(stockRef(db, 'RM_flour'), { lowThreshold: 1000, updatedAt: serverTimestamp() }));
    await assertSucceeds(updateDoc(stockRef(db, 'RM_flour'), { lowThreshold: null, updatedAt: serverTimestamp() }));
    const { qty, lastMovementId, ...fresh } = stockWrite('RM_sugar', 0, M1);
    await assertSucceeds(setDoc(stockRef(db, 'RM_sugar'), { ...fresh, lowThreshold: 500 }, { merge: true }));
  });

  it('denies lowThreshold without stock.threshold, or negative', async () => {
    await arrangeStock('RM_flour', 5000);
    await assertFails(updateDoc(stockRef(t.db('smPtb'), 'RM_flour'), { lowThreshold: -1, updatedAt: serverTimestamp() }));
    await withRole(['stock.move', 'catalog.view']);
    await assertFails(updateDoc(stockRef(t.db('smPtb'), 'RM_flour'), { lowThreshold: 1000, updatedAt: serverTimestamp() }));
  });

  it('denies deleting a stock doc', async () => {
    await arrangeStock('RM_flour', 5000);
    await assertFails(deleteDoc(stockRef(t.db('admin'), 'RM_flour')));
  });
});

describe('#8 stock: read', () => {
  it('lets catalog.view at the location read stock', async () => {
    await arrangeStock('RM_flour', 5000);
    await assertSucceeds(getDoc(stockRef(t.db('smPtb'), 'RM_flour')));
    await assertSucceeds(getDocs(collection(t.db('smPtb'), 'locations', LOC.PTB, 'stock')));
    await assertSucceeds(getDocs(collection(t.db('admin'), 'locations', LOC.PTB, 'stock')));
  });

  it("denies another location's SM and a disabled user", async () => {
    await arrangeStock('RM_flour', 5000);
    await assertFails(getDoc(stockRef(t.db('smMnj'), 'RM_flour')));
    await assertFails(getDoc(stockRef(t.db('disabled'), 'RM_flour')));
  });
});

// ---- The bill batch (SALE side) ----------------------------------------------

describe('bill batch', () => {
  it('accepts a bill with its stock decrements, SALE movement and device counter', async () => {
    await arrangeDevice(t);
    await assertSucceeds(billBatch(t.db('smPtb'), makeBill()).commit());
  });

  it('accepts the largest bill: 20 lines and 4 payments (D-030)', async () => {
    await arrangeDevice(t);
    const payments = ['CASH', 'UPI', 'CARD', 'WALLET'].map((mode) => ({ mode, amount: 50000 }));
    await assertSucceeds(billBatch(t.db('smPtb'), makeBill({ lines: manyLines(20), payments })).commit());
  });

  it('denies the batch when a stock line names another movement', async () => {
    await arrangeDevice(t);
    const db = t.db('smPtb');
    const b = billBatch(db, makeBill());
    b.set(stockRef(db, 'FG_extra'), stockWrite('FG_extra', -1, 'D01-000999'), { merge: true });
    await assertFails(b.commit());
  });

  it('denies the batch when the device counter goes down', async () => {
    await arrangeDevice(t, LOC.PTB, { lastBillSeq: 5 });
    await assertFails(billBatch(t.db('smPtb'), makeBill({ seq: 3 })).commit());
  });
});
