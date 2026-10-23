// BE-18: pre-orders (#18), the delivery bill (#19), the summaries' advance
// fields (#20), the device's lastOrderSeq (#4), the ORDER_CANCEL audit entry
// (#10) and the product's `openPrice` (#11), D-043.
//
// An order is created OPEN with `!exists`, and afterwards has exactly two
// updates: delivery (with one new bill that names it and carries an ADVANCE
// payment equal to the advance) and cancellation (a reason, a refund of 0 up
// to the advance, and the audit entry). Nothing is deleted.

import { describe, expect, it } from 'vitest';
import {
  collection,
  collectionGroup,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  orderBy,
  query,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
  writeBatch,
} from 'firebase/firestore';
import { ACTORS, LOC } from './support/fixtures.js';
import {
  TODAY,
  billId,
  makeAudit,
  makeBill,
  makeOrder,
  makeOrderCancel,
  makeProduct,
  orderId,
  storedBill,
  storedOrder,
} from './support/builders.js';
import { addSummaries, arrangeDevice, billBatch, deliverBatch, orderCancelBatch, orderCreateBatch } from './support/batches.js';
import { assertFails, assertSucceeds, useRulesEnv } from './support/env.js';

const t = useRulesEnv();

const O1 = orderId('D01', 1);
const orderRef = (db, id = O1, loc = LOC.PTB) => doc(db, 'locations', loc, 'orders', id);
const deviceRef = (db, loc = LOC.PTB, id = 'D01') => doc(db, 'locations', loc, 'devices', id);
const summaryRef = (db, kind = 'dailySummary', key = TODAY, loc = LOC.PTB) => doc(db, 'locations', loc, kind, key);

const create = (order = makeOrder(), { actor = 'smPtb', ...opts } = {}) => orderCreateBatch(t.db(actor), order, opts).commit();

/** An open order in the database (rules off), with the device counter at its seq. */
async function arrangeOrder(o = {}, { loc = LOC.PTB, extra = {} } = {}) {
  const order = makeOrder({ loc, ...o });
  await arrangeDevice(t, loc, { lastOrderSeq: order.seq });
  await t.arrange((db) => setDoc(orderRef(db, orderId(order.deviceId, order.seq), loc), storedOrder(order, extra)));
  return order;
}

/** The delivery bill for `order`: the ADVANCE entry first, the rest in cash. */
function deliveryBill(order, { seq = 1, payments, orderIdOverride, ...rest } = {}) {
  const balance = order.price - order.advance;
  return makeBill({
    seq,
    lines: [['CUSTOM-CAKE', 1, order.price]],
    payments: payments ?? [
      ...(order.advance > 0 ? [{ mode: 'ADVANCE', amount: order.advance }] : []),
      ...(balance > 0 ? [{ mode: 'CASH', amount: balance }] : []),
    ],
    orderId: orderIdOverride === undefined ? orderId(order.deviceId, order.seq) : orderIdOverride,
    customer: { name: 'Test Customer' },
    ...rest,
  });
}

const deliver = (bill, { actor = 'smPtb', ...opts } = {}) => deliverBatch(t.db(actor), bill, opts).commit();
const cancel = (id = O1, { actor = 'smPtb', ...opts } = {}) => orderCancelBatch(t.db(actor), id, { uid: ACTORS[actor].uid, ...opts }).commit();

async function read(ref) {
  let data;
  await t.arrange(async (db) => {
    data = (await getDoc(ref(db))).data();
  });
  return data;
}

describe('#18 creating a pre-order', () => {
  it('creates an order with an advance, and counts it in both summaries and lastOrderSeq', async () => {
    await arrangeDevice(t);
    await assertSucceeds(create());
    const o = await read((db) => orderRef(db));
    expect(o).toMatchObject({ status: 'OPEN', billId: null, advance: 50000, advanceMode: 'UPI', orderNo: 'PTB-D01-O000001' });
    expect((await read((db) => deviceRef(db))).lastOrderSeq).toBe(1);
    expect(await read((db) => summaryRef(db))).toMatchObject({ advanceReceived: 50000, lastWriteRef: `locations/PTB/orders/${O1}` });
    expect(await read((db) => summaryRef(db, 'monthlySummary', TODAY.slice(0, 7)))).toMatchObject({ advanceReceived: 50000 });
  });

  it('creates an order with no advance and no time', async () => {
    await arrangeDevice(t);
    await assertSucceeds(create(makeOrder({ advance: 0, dueTime: null })));
    expect((await read((db) => orderRef(db))).advanceMode).toBeNull();
  });

  it('creates the second order of the device in sequence', async () => {
    await arrangeDevice(t);
    await assertSucceeds(create(makeOrder({ seq: 1 })));
    await assertSucceeds(create(makeOrder({ seq: 2, advance: 0 })));
    expect((await read((db) => deviceRef(db))).lastOrderSeq).toBe(2);
  });

  it('accepts an advance equal to the price, and a 500-character description', async () => {
    await arrangeDevice(t);
    await assertSucceeds(create(makeOrder({ price: 100000, advance: 100000, description: 'd'.repeat(500) })));
  });

  it('denies an advance above the price', async () => {
    await arrangeDevice(t);
    await assertFails(create(makeOrder({ price: 100000, advance: 100100 })));
  });

  it('denies a bad price or advance: zero or negative price, not whole rupees, a negative advance', async () => {
    await arrangeDevice(t);
    await assertFails(create(makeOrder({ price: 0, advance: 0 })));
    await assertFails(create(makeOrder({ price: -100, advance: 0 })));
    await assertFails(create(makeOrder({ price: 150050, advance: 0 })));
    await assertFails(create(makeOrder({ price: 150000, advance: 25050 })));
    await assertFails(create(makeOrder({ advance: -100, advanceMode: null })));
    await assertFails(create(makeOrder({ override: { price: '1500' } })));
  });

  it('wants an advance mode exactly when there is an advance, and never ADVANCE', async () => {
    await arrangeDevice(t);
    await assertFails(create(makeOrder({ advance: 50000, advanceMode: null })));
    await assertFails(create(makeOrder({ advance: 0, advanceMode: 'CASH' })));
    await assertFails(create(makeOrder({ advance: 50000, advanceMode: 'ADVANCE' })));
    await assertFails(create(makeOrder({ advance: 50000, advanceMode: 'BARTER' })));
    for (const [i, mode] of ['CASH', 'UPI', 'CARD', 'WALLET', 'OTHER'].entries()) {
      await assertSucceeds(create(makeOrder({ seq: i + 1, advanceMode: mode })));
    }
  });

  it('checks the description (1 to 500) and the due date and time', async () => {
    await arrangeDevice(t);
    await assertFails(create(makeOrder({ description: '' })));
    await assertFails(create(makeOrder({ description: 'd'.repeat(501) })));
    await assertFails(create(makeOrder({ dueDate: 'tomorrow' })));
    await assertFails(create(makeOrder({ dueTime: '4pm' })));
    await assertFails(create(makeOrder({ dueTime: '24:00' })));
    await assertSucceeds(create(makeOrder({ dueTime: '00:00' })));
  });

  it('checks the customer fields as a bill does', async () => {
    await arrangeDevice(t);
    await assertFails(create(makeOrder({ override: { customerName: '' } })));
    await assertFails(create(makeOrder({ override: { customerName: ' padded ' } })));
    await assertFails(create(makeOrder({ override: { customerPhone: '1234567890' } })));
    await assertFails(create(makeOrder({ override: { customerId: '1234567890_0000000000' } })));
    await assertSucceeds(create(makeOrder({ customer: { whatsapp: null } })));
  });

  it('wants orderNo, deviceId and seq to agree with the ID', async () => {
    await arrangeDevice(t);
    await assertFails(create(makeOrder({ override: { orderNo: 'MNJ-D01-O000001' } })));
    await assertFails(create(makeOrder({ override: { deviceId: 'D02' } })));
    const db = t.db('smPtb');
    const o = makeOrder();
    // A document ID that is not the order's own.
    const b = writeBatch(db);
    b.set(orderRef(db, 'D01-O000009'), o);
    b.set(deviceRef(db), { lastOrderSeq: 1 }, { merge: true });
    await assertFails(b.commit());
    const b2 = writeBatch(db);
    b2.set(orderRef(db, 'D01-000001'), o);
    b2.set(deviceRef(db), { lastOrderSeq: 1 }, { merge: true });
    await assertFails(b2.commit());
  });

  it('wants a registered device code, and lastOrderSeq equal to seq in the same batch', async () => {
    // No device document at all.
    await assertFails(create());
    await arrangeDevice(t);
    // The batch leaves the counter alone.
    const db = t.db('smPtb');
    const b = writeBatch(db);
    b.set(orderRef(db), makeOrder());
    await assertFails(b.commit());
    // The counter says another number.
    const b2 = writeBatch(db);
    b2.set(orderRef(db), makeOrder());
    b2.set(deviceRef(db), { lastOrderSeq: 2 }, { merge: true });
    await assertFails(b2.commit());
  });

  it('wants status OPEN, no bill, no cancel and no delivery stamp', async () => {
    await arrangeDevice(t);
    await assertFails(create(makeOrder({ override: { status: 'DELIVERED' } })));
    await assertFails(create(makeOrder({ override: { billId: 'D01-000001' } })));
    await assertFails(create(makeOrder({ override: { cancel: makeOrderCancel() } })));
    await assertFails(create(makeOrder({ override: { deliveredAt: serverTimestamp() } })));
    await assertFails(create(makeOrder({ override: { createdBy: 'someone-else' } })));
    await assertFails(create(makeOrder({ override: { serverCreatedAt: new Date() } })));
    await assertFails(create(makeOrder({ override: { surprise: 1 } })));
  });

  it('is create-only: the same ID again is an update that fails, and nothing is deleted', async () => {
    await arrangeDevice(t);
    await assertSucceeds(create());
    await assertFails(create(makeOrder({ price: 999900, advance: 0 })));
    await assertFails(deleteDoc(orderRef(t.db('smPtb'))));
    await assertFails(deleteDoc(orderRef(t.db('admin'))));
  });

  it('denies another store, a role without order.manage, a disabled user and no user', async () => {
    await arrangeDevice(t);
    await arrangeDevice(t, LOC.MNJ);
    await assertFails(create(makeOrder(), { actor: 'smMnj' }));
    await assertFails(orderCreateBatch(t.db('smMnj'), makeOrder({ loc: LOC.MNJ })).commit());
    await assertFails(create(makeOrder({ uid: ACTORS.cashierPtb.uid }), { actor: 'cashierPtb' }));
    await assertFails(create(makeOrder({ uid: ACTORS.disabled.uid }), { actor: 'disabled' }));
    await assertFails(create(makeOrder(), { actor: 'anonymous' }));
    // The Store Manager of MNJ writing into PTB's orders.
    await assertFails(setDoc(orderRef(t.db('smMnj')), makeOrder({ uid: ACTORS.smMnj.uid })));
  });
});

describe('#4 the device counter lastOrderSeq', () => {
  it('only goes up, and only for order.manage', async () => {
    await arrangeDevice(t, LOC.PTB, { lastOrderSeq: 5 });
    const sm = t.db('smPtb');
    await assertFails(updateDoc(deviceRef(sm), { lastOrderSeq: 4 }));
    await assertFails(updateDoc(deviceRef(sm), { lastOrderSeq: 'six' }));
    await assertSucceeds(updateDoc(deviceRef(sm), { lastOrderSeq: 6 }));
    // A cashier holds bill.create but not order.manage.
    await assertFails(updateDoc(deviceRef(t.db('cashierPtb')), { lastOrderSeq: 7 }));
    // Another store's Store Manager can't touch it either.
    await assertFails(updateDoc(deviceRef(t.db('smMnj')), { lastOrderSeq: 7 }));
  });

  it('is accepted as 0 on a new device and is not required there', async () => {
    const reg = (counters) => {
      const db = t.db('smPtb');
      const b = writeBatch(db);
      b.update(doc(db, 'locations', LOC.PTB), { nextDeviceNo: 1 });
      b.set(deviceRef(db), {
        code: 'D01',
        label: 'Counter 1',
        registeredBy: ACTORS.smPtb.uid,
        registeredAt: serverTimestamp(),
        lastBillSeq: 0,
        retired: false,
        ...counters,
      });
      return b.commit();
    };
    await assertSucceeds(reg({ lastOrderSeq: 0 }));
    await t.env.clearFirestore();
    await import('./support/env.js').then((m) => m.seedFixtures(t.env));
    await assertFails(reg({ lastOrderSeq: 3 }));
    await assertSucceeds(reg({}));
  });
});

describe('#18 (a) delivering an order, and #19 the delivery bill', () => {
  it('delivers an order with a bill: ADVANCE entry plus the balance in cash', async () => {
    const order = await arrangeOrder();
    await assertSucceeds(deliver(deliveryBill(order)));
    expect(await read((db) => orderRef(db))).toMatchObject({ status: 'DELIVERED', billId: billId('D01', 1) });
    expect((await read((db) => orderRef(db))).deliveredAt).toBeTruthy();
    const bill = await read((db) => doc(db, 'locations', LOC.PTB, 'bills', billId('D01', 1)));
    expect(bill).toMatchObject({ orderId: O1, total: 150000 });
    expect(bill.payments).toEqual([
      { mode: 'ADVANCE', amount: 50000 },
      { mode: 'CASH', amount: 100000 },
    ]);
  });

  it('delivers an order paid in full in advance: one ADVANCE payment and nothing else', async () => {
    const order = await arrangeOrder({ price: 80000, advance: 80000 });
    await assertSucceeds(deliver(deliveryBill(order)));
  });

  it('delivers an order with no advance: no ADVANCE entry', async () => {
    const order = await arrangeOrder({ advance: 0 });
    await assertSucceeds(deliver(deliveryBill(order)));
  });

  it('delivers from another device than the one that took the order', async () => {
    const order = await arrangeOrder();
    await arrangeDevice(t, LOC.PTB, { lastOrderSeq: 1 });
    await t.arrange((db) => setDoc(deviceRef(db, LOC.PTB, 'D02'), { code: 'D02', label: 'Counter 2', lastBillSeq: 0, lastMovementSeq: 0, lastReturnSeq: 0, lastOrderSeq: 0, retired: false }));
    await assertSucceeds(deliver(deliveryBill(order, { deviceId: 'D02' })));
  });

  it('denies delivering twice', async () => {
    const order = await arrangeOrder();
    await assertSucceeds(deliver(deliveryBill(order, { seq: 1 })));
    await assertFails(deliver(deliveryBill(order, { seq: 2 })));
    expect((await read((db) => orderRef(db))).billId).toBe(billId('D01', 1));
  });

  it('denies delivering a cancelled order', async () => {
    const order = await arrangeOrder({}, { extra: { status: 'CANCELLED', cancel: makeOrderCancel() } });
    await assertFails(deliver(deliveryBill(order)));
  });

  it('denies a delivery bill whose ADVANCE entry is not the order\'s advance', async () => {
    const order = await arrangeOrder();
    const pay = (advance, rest) => [{ mode: 'ADVANCE', amount: advance }, { mode: 'CASH', amount: rest }];
    await assertFails(deliver(deliveryBill(order, { payments: pay(40000, 110000) })));
    await assertFails(deliver(deliveryBill(order, { payments: pay(60000, 90000) })));
    await assertFails(deliver(deliveryBill(order, { payments: [{ mode: 'CASH', amount: 150000 }] })));
    // Two ADVANCE entries adding up to the advance are not one entry.
    await assertFails(
      deliver(deliveryBill(order, { payments: [{ mode: 'ADVANCE', amount: 20000 }, { mode: 'ADVANCE', amount: 30000 }, { mode: 'CASH', amount: 100000 }] })),
    );
    // The advance as UPI instead of ADVANCE.
    await assertFails(deliver(deliveryBill(order, { payments: [{ mode: 'UPI', amount: 50000 }, { mode: 'CASH', amount: 100000 }] })));
  });

  it('denies an ADVANCE entry when the order had no advance', async () => {
    const order = await arrangeOrder({ advance: 0 });
    await assertFails(deliver(deliveryBill(order, { payments: [{ mode: 'ADVANCE', amount: 10000 }, { mode: 'CASH', amount: 140000 }] })));
  });

  it('denies an ADVANCE payment on an ordinary bill (#19)', async () => {
    await arrangeDevice(t);
    const ordinary = makeBill({ payments: [{ mode: 'ADVANCE', amount: 70100 }] });
    await assertFails(billBatch(t.db('smPtb'), ordinary, { full: true }).commit());
    const mixed = makeBill({ payments: [{ mode: 'CASH', amount: 20100 }, { mode: 'ADVANCE', amount: 50000 }] });
    await assertFails(billBatch(t.db('smPtb'), mixed, { full: true }).commit());
    // The same bill paid in cash is fine, with or without a null orderId.
    await assertSucceeds(billBatch(t.db('smPtb'), makeBill({ orderId: null }), { full: true }).commit());
  });

  it('denies a bill that names an order but does not deliver it in the batch', async () => {
    const order = await arrangeOrder();
    await assertFails(billBatch(t.db('smPtb'), deliveryBill(order), { full: true }).commit());
  });

  it('denies a bill that names an order that does not exist, or is not a valid order ID', async () => {
    await arrangeDevice(t);
    const order = makeOrder();
    await assertFails(billBatch(t.db('smPtb'), deliveryBill(order, { orderIdOverride: 'D01-O000099' }), { full: true }).commit());
    await assertFails(billBatch(t.db('smPtb'), deliveryBill(order, { orderIdOverride: 'nonsense' }), { full: true }).commit());
    await assertFails(billBatch(t.db('smPtb'), deliveryBill(order, { orderIdOverride: 7 }), { full: true }).commit());
  });

  it('denies an order update whose bill is not new, is another bill, or does not name the order', async () => {
    const order = await arrangeOrder();
    const bill = deliveryBill(order);
    // The bill already exists.
    await arrangeDevice(t, LOC.PTB, { lastOrderSeq: 1, lastBillSeq: 1 });
    await t.arrange((db) => setDoc(doc(db, 'locations', LOC.PTB, 'bills', billId('D01', 1)), storedBill(bill)));
    await assertFails(deliver(deliveryBill(order, { seq: 1 })));
    // billId names a different bill from the one in the batch.
    await assertFails(deliver(deliveryBill(order, { seq: 2 }), { orderUpdate: { billId: billId('D01', 3) } }));
    // The bill in the batch does not carry orderId (an ordinary bill with an order update).
    await assertFails(deliver(deliveryBill(order, { seq: 2, payments: [{ mode: 'CASH', amount: 150000 }], orderIdOverride: undefined, customerOverride: {} }), { orderUpdate: { billId: billId('D01', 2) } }).catch((e) => { throw e; }));
  });

  it('denies an update that changes more than status, billId and deliveredAt', async () => {
    const order = await arrangeOrder();
    await assertFails(deliver(deliveryBill(order), { orderUpdate: { price: 100 } }));
    await assertFails(deliver(deliveryBill(order), { orderUpdate: { advance: 0 } }));
    await assertFails(deliver(deliveryBill(order), { orderUpdate: { description: 'something else' } }));
    await assertFails(deliver(deliveryBill(order), { orderUpdate: { deliveredAt: new Date() } }));
    await assertFails(deliver(deliveryBill(order), { orderUpdate: { status: 'CANCELLED' } }));
  });

  it('denies another store, and a role without order.manage', async () => {
    const order = await arrangeOrder();
    await arrangeDevice(t, LOC.MNJ);
    await assertFails(deliver(deliveryBill(order, { uid: ACTORS.smMnj.uid }), { actor: 'smMnj' }));
    await assertFails(deliver(deliveryBill(order, { uid: ACTORS.cashierPtb.uid }), { actor: 'cashierPtb' }));
    // The bill is a cashier's to make, the order update is not.
    expect((await read((db) => orderRef(db))).status).toBe('OPEN');
  });

  it('denies cancelling the delivery bill (D-043 (d)), and allows a return against it', async () => {
    const order = await arrangeOrder();
    const bill = deliveryBill(order);
    await assertSucceeds(deliver(bill));
    const { cancelBatch } = await import('./support/batches.js');
    await assertFails(cancelBatch(t.db('smPtb'), bill).commit());
    expect((await read((db) => doc(db, 'locations', LOC.PTB, 'bills', billId('D01', 1))))).toMatchObject({ status: 'COMPLETED' });
  });
});

describe('#18 (b) cancelling an order, and the ORDER_CANCEL audit entry', () => {
  it('cancels with the full advance refunded, with its audit entry and summaries', async () => {
    await arrangeOrder();
    await assertSucceeds(cancel(O1, { refunded: 50000 }));
    expect(await read((db) => orderRef(db))).toMatchObject({ status: 'CANCELLED', cancel: { refunded: 50000, by: 'sm-ptb' } });
    expect(await read((db) => doc(db, 'auditLog', `PTB-${O1}-X`))).toMatchObject({ action: 'ORDER_CANCEL', locationId: 'PTB' });
    expect(await read((db) => summaryRef(db))).toMatchObject({ advanceRefunded: 50000, lastWriteRef: `auditLog/PTB-${O1}-X` });
  });

  it('cancels with a part refund and with none (the shop keeps the rest)', async () => {
    await arrangeOrder();
    await assertSucceeds(cancel(O1, { refunded: 20000 }));
    await arrangeOrder({ seq: 2 });
    await assertSucceeds(cancel(orderId('D01', 2), { refunded: 0 }));
  });

  it('cancels an order that had no advance', async () => {
    await arrangeOrder({ advance: 0 });
    await assertSucceeds(cancel(O1, { refunded: 0 }));
  });

  it('denies a refund above the advance, below zero or not in whole rupees', async () => {
    await arrangeOrder();
    await assertFails(cancel(O1, { refunded: 50100 }));
    await assertFails(cancel(O1, { refunded: -100 }));
    await assertFails(cancel(O1, { refunded: 25050 }));
    await assertFails(cancel(O1, { refunded: 150000 }));
  });

  it('denies a cancel without a reason, with one over 100 characters, or by someone else', async () => {
    await arrangeOrder();
    await assertFails(cancel(O1, { cancel: { reason: '' } }));
    await assertFails(cancel(O1, { cancel: { reason: 'r'.repeat(101) } }));
    await assertSucceeds(cancel(O1, { cancel: { reason: 'r'.repeat(100) } }));
  });

  it('denies a cancel that names another user, or has extra or missing fields', async () => {
    await arrangeOrder();
    await assertFails(cancel(O1, { cancel: { by: 'someone-else' } }));
    await assertFails(cancel(O1, { cancel: { extra: 1 } }));
  });

  it('denies a cancel without the audit entry in the batch', async () => {
    await arrangeOrder();
    const db = t.db('smPtb');
    const b = writeBatch(db);
    b.update(orderRef(db), { status: 'CANCELLED', cancel: makeOrderCancel() });
    await assertFails(b.commit());
  });

  it('denies cancelling twice, cancelling a delivered order and delivering a cancelled one', async () => {
    await arrangeOrder();
    await assertSucceeds(cancel(O1));
    await t.arrange((db) => updateDoc(doc(db, 'auditLog', `PTB-${O1}-X`), { reason: 'again' }).catch(() => {}));
    await arrangeOrder({ seq: 2 }, { extra: { status: 'DELIVERED', billId: 'D01-000001' } });
    await assertFails(cancel(orderId('D01', 2)));
  });

  it('denies a cancelled order cancelling again (audit entry would exist, and the order is not OPEN)', async () => {
    await arrangeOrder({}, { extra: { status: 'CANCELLED', cancel: makeOrderCancel() } });
    await assertFails(cancel(O1));
  });

  it('denies cancelling with other fields changed in the same update', async () => {
    await arrangeOrder();
    const db = t.db('smPtb');
    const b = writeBatch(db);
    b.update(orderRef(db), { status: 'CANCELLED', cancel: makeOrderCancel(), price: 100 });
    b.set(doc(db, 'auditLog', `PTB-${O1}-X`), makeAudit({ action: 'ORDER_CANCEL', entityPath: `locations/PTB/orders/${O1}` }));
    await assertFails(b.commit());
  });

  it('denies a cancel by another store or by a role without order.manage', async () => {
    await arrangeOrder();
    await assertFails(cancel(O1, { actor: 'smMnj' }));
    await assertFails(cancel(O1, { actor: 'cashierPtb' }));
    expect((await read((db) => orderRef(db))).status).toBe('OPEN');
  });

  it('writes the audit entry only with order.manage at the location, in the ORDER_CANCEL shape', async () => {
    const audit = (id, o = {}) => setDoc(doc(t.db(o.actor ?? 'smPtb'), 'auditLog', id), makeAudit({ action: 'ORDER_CANCEL', entityPath: `locations/PTB/orders/${O1}`, ...o.fields }));
    await assertSucceeds(audit(`PTB-${O1}-X`));
    await assertFails(audit(`PTB-${O1}`)); // not the cancel shape
    await assertFails(audit(`PTB-D01-000001-X`)); // a bill's shape
    await assertFails(audit(`MNJ-${O1}-X`, { fields: { locationId: LOC.MNJ } })); // another store
    await assertFails(audit(`PTB-${orderId('D01', 2)}-X`, { actor: 'cashierPtb', fields: { uid: ACTORS.cashierPtb.uid } }));
    await assertFails(audit(`PTB-${orderId('D01', 3)}-X`, { actor: 'smMnj', fields: { uid: ACTORS.smMnj.uid } }));
    await assertSucceeds(audit(`PTB-${orderId('D01', 4)}-X`, { actor: 'admin', fields: { uid: ACTORS.admin.uid } }));
  });
});

describe('#20 the summaries\' advance fields', () => {
  const overSummary = (extra, ref, date = TODAY) => {
    const db = t.db('smPtb');
    const b = writeBatch(db);
    addSummaries(b, db, { ref, fields: extra, date });
    return b;
  };

  it('moves advanceReceived only with a new order, by exactly its advance', async () => {
    await arrangeDevice(t);
    const order = makeOrder();
    const db = t.db('smPtb');
    // Too much, and too little.
    for (const wrong of [60000, 40000, 0]) {
      const b = writeBatch(db);
      b.set(orderRef(db), order);
      b.set(deviceRef(db), { lastOrderSeq: 1 }, { merge: true });
      addSummaries(b, db, { ref: `locations/PTB/orders/${O1}`, fields: { advanceReceived: wrong || 1 } });
      await assertFails(b.commit());
    }
    await assertSucceeds(create(order));
  });

  it('names the order as lastWriteRef only when the order is new in the batch', async () => {
    await arrangeOrder();
    await assertFails(overSummary({ advanceReceived: 50000 }, `locations/PTB/orders/${O1}`).commit());
  });

  it('denies advanceReceived or advanceRefunded on a bill, return or any other event', async () => {
    await arrangeDevice(t);
    const bill = makeBill();
    const withAdvance = (fields) => {
      const db = t.db('smPtb');
      const b = billBatch(db, bill);
      addSummaries(b, db, { ref: `locations/PTB/bills/${billId('D01', 1)}`, fields: { billCount: 1, netSales: bill.total, ...fields } });
      return b.commit();
    };
    await assertFails(withAdvance({ advanceReceived: 100 }));
    await assertFails(withAdvance({ advanceRefunded: 100 }));
    await assertSucceeds(withAdvance({}));
  });

  it('moves advanceRefunded only with a cancelled order\'s audit entry, by exactly the refund', async () => {
    await arrangeOrder();
    const db = t.db('smPtb');
    const attempt = (summed) => {
      const b = writeBatch(db);
      b.update(orderRef(db), { status: 'CANCELLED', cancel: makeOrderCancel({ refunded: 30000 }) });
      b.set(doc(db, 'auditLog', `PTB-${O1}-X`), makeAudit({ action: 'ORDER_CANCEL', entityPath: `locations/PTB/orders/${O1}` }));
      addSummaries(b, db, { ref: `auditLog/PTB-${O1}-X`, fields: summed });
      return b.commit();
    };
    await assertFails(attempt({ advanceRefunded: 40000 }));
    await assertFails(attempt({ advanceRefunded: 20000 }));
    await assertFails(attempt({ advanceReceived: 30000 }));
    await assertSucceeds(attempt({ advanceRefunded: 30000 }));
  });

  it('accepts a cancel with a refund of 0 and no summary write at all', async () => {
    await arrangeOrder();
    await assertSucceeds(cancel(O1, { refunded: 0 }));
    expect(await read((db) => summaryRef(db))).toBeUndefined();
  });

  it('adds up across orders on the same day', async () => {
    await arrangeDevice(t);
    await assertSucceeds(create(makeOrder({ seq: 1, advance: 50000 })));
    await assertSucceeds(create(makeOrder({ seq: 2, advance: 20000 })));
    await assertSucceeds(cancel(orderId('D01', 2), { refunded: 10000 }));
    expect(await read((db) => summaryRef(db))).toMatchObject({ advanceReceived: 70000, advanceRefunded: 10000 });
  });

  it('keeps the other summary rules: an audit ref of another action is denied', async () => {
    await arrangeOrder();
    const db = t.db('smPtb');
    const b = writeBatch(db);
    b.set(doc(db, 'auditLog', `PTB-${orderId('D01', 8)}-X`), makeAudit({ action: 'BILL_CANCEL', entityPath: 'x' }));
    addSummaries(b, db, { ref: `auditLog/PTB-${orderId('D01', 8)}-X`, fields: { advanceRefunded: 100 } });
    await assertFails(b.commit());
  });
});

describe('#18 reading orders', () => {
  const arrangeBoth = async () => {
    await arrangeOrder();
    await arrangeOrder({ uid: ACTORS.smMnj.uid }, { loc: LOC.MNJ });
  };

  it('is readable by the Store Manager of that store, by document and by query', async () => {
    await arrangeBoth();
    await assertSucceeds(getDoc(orderRef(t.db('smPtb'))));
    const open = await assertSucceeds(
      getDocs(query(collection(t.db('smPtb'), 'locations', LOC.PTB, 'orders'), where('status', '==', 'OPEN'), orderBy('dueDate'))),
    );
    expect(open.size).toBe(1);
  });

  it('denies an SM at PTB reading or writing MNJ orders, and the reverse', async () => {
    await arrangeBoth();
    await assertFails(getDoc(orderRef(t.db('smPtb'), O1, LOC.MNJ)));
    await assertFails(getDocs(collection(t.db('smPtb'), 'locations', LOC.MNJ, 'orders')));
    await assertFails(getDoc(orderRef(t.db('smMnj'))));
    await assertFails(setDoc(orderRef(t.db('smPtb'), O1, LOC.MNJ), makeOrder({ loc: LOC.MNJ })));
    await assertFails(updateDoc(orderRef(t.db('smPtb'), O1, LOC.MNJ), { status: 'CANCELLED', cancel: makeOrderCancel({ refunded: 0 }) }));
    await assertFails(deleteDoc(orderRef(t.db('smPtb'), O1, LOC.MNJ)));
  });

  it('lets the Admin read every store\'s orders, one by one and across stores (read only)', async () => {
    await arrangeBoth();
    const admin = t.db('admin');
    await assertSucceeds(getDoc(orderRef(admin, O1, LOC.MNJ)));
    const all = await assertSucceeds(
      getDocs(query(collectionGroup(admin, 'orders'), where('status', '==', 'OPEN'), orderBy('dueDate'))),
    );
    expect(all.size).toBe(2);
    const noFilter = await assertSucceeds(getDocs(query(collectionGroup(admin, 'orders'), orderBy('dueDate'))));
    expect(noFilter.size).toBe(2);
  });

  it('denies the all-stores query to a Store Manager, and reads to a role without any of the permissions', async () => {
    await arrangeBoth();
    await assertFails(getDocs(query(collectionGroup(t.db('smPtb'), 'orders'), orderBy('dueDate'))));
    await assertFails(getDoc(orderRef(t.db('cashierPtb'))));
    await assertFails(getDoc(orderRef(t.db('anonymous'))));
  });
});

describe('#11 the product field openPrice (D-043)', () => {
  const product = (o = {}, extra = {}) => ({ ...makeProduct(o), ...extra });
  const prodRef = (db, id = 'CUSTOM-CAKE') => doc(db, 'products', id);

  it('lets the Admin create the open-price CUSTOM-CAKE at price 0', async () => {
    await assertSucceeds(setDoc(prodRef(t.db('admin')), product({ price: 0 }, { name: 'Custom cake', openPrice: true })));
  });

  it('accepts openPrice false from anyone who may create the product, and no field at all', async () => {
    await assertSucceeds(setDoc(prodRef(t.db('admin'), 'a'), product({}, { openPrice: false })));
    await assertSucceeds(setDoc(prodRef(t.db('admin'), 'b'), product()));
    const suggestion = makeProduct({ status: 'PENDING', price: null, scope: LOC.PTB, uid: ACTORS.smPtb.uid });
    await assertSucceeds(setDoc(prodRef(t.db('smPtb'), 'c'), { ...suggestion, openPrice: false }));
  });

  it('denies a suggestion that sets openPrice, and a non-bool value', async () => {
    const suggestion = makeProduct({ status: 'PENDING', price: null, scope: LOC.PTB, uid: ACTORS.smPtb.uid });
    await assertFails(setDoc(prodRef(t.db('smPtb'), 'd'), { ...suggestion, openPrice: true }));
    await assertFails(setDoc(prodRef(t.db('admin'), 'e'), product({}, { openPrice: 'yes' })));
    await assertFails(setDoc(prodRef(t.db('smPtb'), 'f'), product({ uid: ACTORS.smPtb.uid }, { openPrice: true })));
  });

  it('lets only catalog.manage switch it on or off an existing product', async () => {
    await t.arrange((db) => setDoc(prodRef(db, 'g'), { ...makeProduct(), createdAt: new Date(), updatedAt: new Date() }));
    await assertFails(updateDoc(prodRef(t.db('smPtb'), 'g'), { openPrice: true, updatedAt: serverTimestamp() }));
    await assertSucceeds(updateDoc(prodRef(t.db('admin'), 'g'), { openPrice: true, updatedAt: serverTimestamp() }));
    await assertSucceeds(updateDoc(prodRef(t.db('admin'), 'g'), { openPrice: false, updatedAt: serverTimestamp() }));
  });
});
