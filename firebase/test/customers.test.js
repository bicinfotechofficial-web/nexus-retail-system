// BE-15: customers on bills (D-034, D-037; rule #14) and the customer fields
// of a new bill (#5, #6).
//
// A customer doc is written only in the batch of a bill that creates it:
// `set(merge)` with the same name and phone, the latest WhatsApp number, the
// server time, both counters as increments and the bill's ID. The first bill
// creates the doc (billCount 1, totalSpend that bill's total); each later bill
// raises both counters by exactly its own count and total.

import { describe, expect, it } from 'vitest';
import {
  collection,
  collectionGroup,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  increment,
  limit,
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
  billId,
  customerFields,
  customerId,
  customerWrite,
  makeBill,
  storedBill,
  storedCustomer,
} from './support/builders.js';
import { arrangeDevice, billBatch } from './support/batches.js';
import { assertFails, assertSucceeds, seedFixtures, useRulesEnv } from './support/env.js';

const t = useRulesEnv();

const ME = customerFields();
const customerRef = (db, id = ME.customerId, loc = LOC.PTB) => doc(db, 'locations', loc, 'customers', id);
const billRef = (db, id, loc = LOC.PTB) => doc(db, 'locations', loc, 'bills', id);

/** What the customer doc holds now (rules off). */
async function readCustomer(id = ME.customerId, loc = LOC.PTB) {
  let data;
  await t.arrange(async (db) => {
    data = (await getDoc(customerRef(db, id, loc))).data();
  });
  return data;
}

/** The bill batch (with its customer write) as `actor`; `opts` is billBatch's. */
const commitBill = (bill, { actor = 'smPtb', loc = LOC.PTB, ...opts } = {}) =>
  billBatch(t.db(actor), bill, { loc, ...opts }).commit();

const bill = (seq, o = {}) => makeBill({ seq, ...o });

/** A hand-built batch of one bill and one customer write, for the tampered cases. */
function customAssembly(db, b, id, customerDocId, data, { merge = true, loc = LOC.PTB } = {}) {
  const batch = writeBatch(db);
  batch.set(billRef(db, id, loc), b);
  batch.set(customerRef(db, customerDocId, loc), data, merge ? { merge: true } : undefined);
  return batch;
}

describe('#14 customers: the first and later bills', () => {
  it('creates the customer with billCount 1 and totalSpend equal to the bill total', async () => {
    await arrangeDevice(t);
    const b = bill(1);
    await assertSucceeds(commitBill(b));
    expect(await readCustomer()).toMatchObject({
      name: 'Test Customer',
      phone: '9876543210',
      whatsapp: '9876543210',
      billCount: 1,
      totalSpend: b.total,
      lastWriteRef: billId('D01', 1),
    });
    expect((await readCustomer()).lastBillAt).toBeTruthy();
  });

  it('adds exactly the count and the total of each later bill', async () => {
    await arrangeDevice(t);
    const first = bill(1);
    const second = bill(2, { lines: [['puff-veg', 3, 2500]] });
    const third = bill(3, { lines: [['puff-veg', 1, 2500]] });
    await assertSucceeds(commitBill(first));
    await assertSucceeds(commitBill(second));
    await assertSucceeds(commitBill(third));
    expect(await readCustomer()).toMatchObject({
      billCount: 3,
      totalSpend: first.total + second.total + third.total,
      lastWriteRef: billId('D01', 3),
    });
  });

  it('accepts a free bill (total 0): the count goes up, the spend does not', async () => {
    await arrangeDevice(t);
    await assertSucceeds(commitBill(bill(1)));
    const free = bill(2, { lines: [['gift', 1, 0]] });
    expect(free.total).toBe(0);
    await assertSucceeds(commitBill(free));
    const c = await readCustomer();
    expect(c.billCount).toBe(2);
    expect(c.totalSpend).toBe(bill(1).total);
  });

  it('overwrites whatsapp with the latest number, or with null', async () => {
    await arrangeDevice(t);
    await assertSucceeds(commitBill(bill(1)));
    await assertSucceeds(commitBill(bill(2, { customer: { whatsapp: '9123456780' } })));
    expect((await readCustomer()).whatsapp).toBe('9123456780');
    await assertSucceeds(commitBill(bill(3, { customer: { whatsapp: null } })));
    expect((await readCustomer()).whatsapp).toBeNull();
  });

  it('keeps the same customer when only the letter case of the name differs (the id is the same)', async () => {
    await arrangeDevice(t);
    await assertSucceeds(commitBill(bill(1)));
    const shouting = bill(2, { customer: { name: 'TEST CUSTOMER' } });
    expect(shouting.customerId).toBe(ME.customerId);
    await assertSucceeds(commitBill(shouting));
    expect(await readCustomer()).toMatchObject({ name: 'TEST CUSTOMER', billCount: 2 });
  });

  it('makes a second customer for another name on the same phone', async () => {
    await arrangeDevice(t);
    await assertSucceeds(commitBill(bill(1)));
    const other = customerFields({ name: 'Another Customer' });
    expect(other.customerId).not.toBe(ME.customerId);
    await assertSucceeds(commitBill(bill(2, { customer: { name: 'Another Customer' } })));
    expect((await readCustomer(other.customerId)).billCount).toBe(1);
    expect((await readCustomer()).billCount).toBe(1);
  });

  it('lets a Cashier with bill.create write it, and denies a role without bill.create', async () => {
    await arrangeDevice(t);
    const b = makeBill({ uid: ACTORS.cashierPtb.uid, userName: 'Cashier PTB' });
    await assertSucceeds(commitBill(b, { actor: 'cashierPtb' }));
    // A role without bill.create cannot write the customer doc, even beside an existing bill.
    await t.env.clearFirestore();
    await seedFixtures(t.env);
    await arrangeDevice(t);
    await t.withPermissions('counterPtb', ['catalog.view', 'stock.adjust']);
    await assertFails(commitBill(makeBill({ uid: ACTORS.counterPtb.uid }), { actor: 'counterPtb' }));
    await assertFails(
      setDoc(customerRef(t.db('counterPtb')), customerWrite(b, billId('D01', 1)), { merge: true }),
    );
  });
});

describe('#14 customers: writes without their bill are denied', () => {
  it('denies a customer doc written alone', async () => {
    await arrangeDevice(t);
    const b = bill(1);
    await assertFails(setDoc(customerRef(t.db('smPtb')), customerWrite(b, billId('D01', 1)), { merge: true }));
  });

  it('denies pointing lastWriteRef at an existing bill (replaying one bill for more increments)', async () => {
    await arrangeDevice(t);
    const b = bill(1);
    await t.arrange((db) => setDoc(billRef(db, billId('D01', 1)), storedBill(b)));
    await assertFails(setDoc(customerRef(t.db('smPtb')), customerWrite(b, billId('D01', 1)), { merge: true }));
    // Even with the real customer already there.
    await t.arrange((db) => setDoc(customerRef(db), storedCustomer({ totalSpend: b.total, lastWriteRef: 'D01-000009' })));
    await assertFails(setDoc(customerRef(t.db('smPtb')), customerWrite(b, billId('D01', 1)), { merge: true }));
  });

  it('denies a bill that does not match the customer doc: another customerId', async () => {
    await arrangeDevice(t);
    const b = bill(1);
    const other = customerFields({ name: 'Another Customer' });
    const db = t.db('smPtb');
    // Bill for ME, customer doc under another id.
    await assertFails(customAssembly(db, b, billId('D01', 1), other.customerId, customerWrite(b, billId('D01', 1))).commit());
    // Bill for another customer, customer doc under ME.
    const b2 = bill(1, { customer: { name: 'Another Customer' } });
    await assertFails(customAssembly(db, b2, billId('D01', 1), ME.customerId, customerWrite(b2, billId('D01', 1))).commit());
  });

  it('denies a customer doc whose name, phone or whatsapp differ from the bill', async () => {
    await arrangeDevice(t);
    const b = bill(1);
    const db = t.db('smPtb');
    const id = billId('D01', 1);
    for (const override of [{ name: 'Someone Else' }, { phone: '9123456780' }, { whatsapp: '9123456780' }, { whatsapp: null }]) {
      await assertFails(customAssembly(db, b, id, ME.customerId, customerWrite(b, id, override)).commit());
    }
  });

  it('denies a customer doc whose lastWriteRef names a different new bill', async () => {
    await arrangeDevice(t);
    const b = bill(1);
    const db = t.db('smPtb');
    await assertFails(customAssembly(db, b, billId('D01', 1), ME.customerId, customerWrite(b, billId('D01', 2))).commit());
    await assertFails(customAssembly(db, b, billId('D01', 1), ME.customerId, customerWrite(b, 'locations/PTB/bills/D01-000001')).commit());
  });

  it('denies a bill at one location with its customer doc at another', async () => {
    await arrangeDevice(t);
    const b = bill(1);
    const db = t.db('smPtb');
    const batch = writeBatch(db);
    batch.set(billRef(db, billId('D01', 1)), b);
    batch.set(customerRef(db, ME.customerId, LOC.MNJ), customerWrite(b, billId('D01', 1)), { merge: true });
    await assertFails(batch.commit());
  });
});

describe('#14 customers: the counters', () => {
  it('denies a first bill that sets billCount or totalSpend to anything but 1 and the bill total', async () => {
    await arrangeDevice(t);
    const b = bill(1);
    const id = billId('D01', 1);
    const db = t.db('smPtb');
    for (const override of [
      { billCount: increment(2) },
      { billCount: increment(0) },
      { totalSpend: increment(b.total + 100) },
      { totalSpend: increment(0) },
      { billCount: 2 },
      { totalSpend: b.total + 100 },
    ]) {
      await assertFails(customAssembly(db, b, id, ME.customerId, customerWrite(b, id, override)).commit());
    }
  });

  it('denies a later bill that raises billCount by 2, by 0 or by a negative number', async () => {
    await arrangeDevice(t);
    await assertSucceeds(commitBill(bill(1)));
    const b = bill(2);
    const id = billId('D01', 2);
    const db = t.db('smPtb');
    for (const by of [2, 0, -1]) {
      await assertFails(customAssembly(db, b, id, ME.customerId, customerWrite(b, id, { billCount: increment(by) })).commit());
    }
  });

  it('denies a later bill whose totalSpend moves by anything but its own total', async () => {
    await arrangeDevice(t);
    await assertSucceeds(commitBill(bill(1)));
    const b = bill(2);
    const id = billId('D01', 2);
    const db = t.db('smPtb');
    for (const by of [b.total + 100, b.total - 100, 0, -b.total]) {
      await assertFails(customAssembly(db, b, id, ME.customerId, customerWrite(b, id, { totalSpend: increment(by) })).commit());
    }
  });

  it('denies resetting the counters of an existing customer (a plain set of billCount 1)', async () => {
    await arrangeDevice(t);
    await assertSucceeds(commitBill(bill(1)));
    await assertSucceeds(commitBill(bill(2)));
    const b = bill(3);
    const id = billId('D01', 3);
    const db = t.db('smPtb');
    // A literal count and total instead of increments: a reset.
    const reset = customerWrite(b, id, { billCount: 1, totalSpend: b.total });
    await assertFails(customAssembly(db, b, id, ME.customerId, reset).commit());
    // The same as a full replacement (no merge).
    await assertFails(customAssembly(db, b, id, ME.customerId, reset, { merge: false }).commit());
  });
});

describe('#14 customers: name and phone never change', () => {
  it('denies a later bill that changes the name to another name (same id)', async () => {
    await arrangeDevice(t);
    await assertSucceeds(commitBill(bill(1)));
    const b = bill(2);
    const id = billId('D01', 2);
    // The bill says Test Customer; the customer doc is written with another name.
    await assertFails(customAssembly(t.db('smPtb'), b, id, ME.customerId, customerWrite(b, id, { name: 'Renamed Person' })).commit());
    // A bill that itself carries another name under the same customerId is the same problem.
    const renamed = bill(2, { customerOverride: { customerName: 'Renamed Person' } });
    await assertFails(commitBill(renamed));
    expect((await readCustomer()).name).toBe('Test Customer');
  });

  it('denies a name that only looks like a case change, or adds spaces', async () => {
    await arrangeDevice(t);
    await assertSucceeds(commitBill(bill(1)));
    await assertFails(commitBill(bill(2, { customerOverride: { customerName: 'Test Customer ' } })));
    await assertFails(commitBill(bill(2, { customerOverride: { customerName: 'Test  Customer' } })));
  });

  it('denies a later bill that changes the phone of an existing customer id', async () => {
    await arrangeDevice(t);
    await assertSucceeds(commitBill(bill(1)));
    const b = bill(2);
    const id = billId('D01', 2);
    await assertFails(customAssembly(t.db('smPtb'), b, id, ME.customerId, customerWrite(b, id, { phone: '9123456780' })).commit());
    // And a bill under that id with another phone fails its own rule (the id must start with the phone).
    await assertFails(commitBill(bill(2, { customerOverride: { customerPhone: '9123456780' } })));
    expect((await readCustomer()).phone).toBe('9876543210');
  });

  it('denies extra fields, a missing field and a client lastBillAt', async () => {
    await arrangeDevice(t);
    const b = bill(1);
    const id = billId('D01', 1);
    const db = t.db('smPtb');
    const data = customerWrite(b, id);
    await assertFails(customAssembly(db, b, id, ME.customerId, { ...data, createdBy: ACTORS.smPtb.uid }).commit());
    const { whatsapp, ...noWhatsapp } = data;
    await assertFails(customAssembly(db, b, id, ME.customerId, noWhatsapp).commit());
    await assertFails(customAssembly(db, b, id, ME.customerId, { ...data, lastBillAt: new Date() }).commit());
    const { lastBillAt, ...noTime } = data;
    await assertFails(customAssembly(db, b, id, ME.customerId, noTime).commit());
  });
});

describe('#14 customers: delete and plain updates', () => {
  it('denies deleting a customer, for the Admin too', async () => {
    await t.arrange((db) => setDoc(customerRef(db), storedCustomer()));
    await assertFails(deleteDoc(customerRef(t.db('smPtb'))));
    await assertFails(deleteDoc(customerRef(t.db('admin'))));
  });

  it('denies updating a customer with no bill, for the Store Manager and the Admin', async () => {
    await t.arrange((db) => setDoc(customerRef(db), storedCustomer()));
    await assertFails(updateDoc(customerRef(t.db('smPtb')), { billCount: 2 }));
    await assertFails(updateDoc(customerRef(t.db('admin')), { whatsapp: null }));
    await assertFails(updateDoc(customerRef(t.db('smPtb')), { name: 'X' }));
  });

  it('writes at the user\'s own location only, and lets the Admin write at any', async () => {
    await arrangeDevice(t, LOC.MNJ);
    await assertFails(commitBill(makeBill({ loc: LOC.MNJ }), { loc: LOC.MNJ }));
    const adminBill = makeBill({ loc: LOC.MNJ, uid: ACTORS.admin.uid, userName: 'Admin' });
    await assertSucceeds(commitBill(adminBill, { actor: 'admin', loc: LOC.MNJ }));
    expect((await readCustomer(ME.customerId, LOC.MNJ)).billCount).toBe(1);
  });

  it('denies a disabled user, and a user with no profile', async () => {
    await arrangeDevice(t);
    const b = bill(1);
    await assertFails(commitBill(b, { actor: 'disabled' }));
    await assertFails(commitBill(b, { actor: 'noProfile' }));
    await assertFails(setDoc(customerRef(t.db('anonymous')), customerWrite(b, billId('D01', 1)), { merge: true }));
  });
});

describe('#14 customers: read', () => {
  const arrangeCustomers = () =>
    t.arrange(async (db) => {
      await setDoc(customerRef(db), storedCustomer());
      await setDoc(customerRef(db, customerId('9123456780', 'Second Customer')), storedCustomer({ name: 'Second Customer', phone: '9123456780' }));
      await setDoc(customerRef(db, ME.customerId, LOC.MNJ), storedCustomer());
    });

  it('lets billing and reporting staff read their own location', async () => {
    await arrangeCustomers();
    await assertSucceeds(getDoc(customerRef(t.db('smPtb'))));
    await assertSucceeds(getDocs(collection(t.db('smPtb'), 'locations', LOC.PTB, 'customers')));
    // bill.create alone (the Cashier) and report.own alone both suffice.
    await assertSucceeds(getDoc(customerRef(t.db('cashierPtb'))));
    await t.withPermissions('counterPtb', ['report.own']);
    await assertSucceeds(getDoc(customerRef(t.db('counterPtb'))));
  });

  it('denies a Store Manager the other location, as a doc and as a query', async () => {
    await arrangeCustomers();
    await assertFails(getDoc(customerRef(t.db('smPtb'), ME.customerId, LOC.MNJ)));
    await assertFails(getDocs(collection(t.db('smPtb'), 'locations', LOC.MNJ, 'customers')));
    await assertSucceeds(getDoc(customerRef(t.db('smMnj'), ME.customerId, LOC.MNJ)));
  });

  it('lets the Admin read every location, as docs, as a location query and as a collection group query', async () => {
    await arrangeCustomers();
    const db = t.db('admin');
    await assertSucceeds(getDoc(customerRef(db)));
    await assertSucceeds(getDoc(customerRef(db, ME.customerId, LOC.MNJ)));
    await assertSucceeds(getDocs(collection(db, 'locations', LOC.MNJ, 'customers')));
    const all = await assertSucceeds(getDocs(query(collectionGroup(db, 'customers'), orderBy('lastBillAt', 'desc'), limit(500))));
    expect(all.size).toBe(3);
  });

  it('denies a collection group query to a Store Manager, a Cashier and an anonymous user', async () => {
    await arrangeCustomers();
    for (const actor of ['smPtb', 'smMnj', 'cashierPtb', 'anonymous']) {
      await assertFails(getDocs(collectionGroup(t.db(actor), 'customers')));
    }
  });

  it('denies a role with neither bill.create nor report.own, a disabled user and anonymous', async () => {
    await arrangeCustomers();
    await assertFails(getDoc(customerRef(t.db('counterPtb'))));
    await assertFails(getDoc(customerRef(t.db('disabled'))));
    await assertFails(getDoc(customerRef(t.db('noProfile'))));
    await assertFails(getDoc(customerRef(t.db('anonymous'))));
    await t.withPermissions('disabled', ['report.all', 'bill.create']);
    await assertFails(getDocs(collectionGroup(t.db('disabled'), 'customers')));
  });

  it('runs the lookups the app makes: by phone prefix, and most recent first (Store Manager)', async () => {
    await arrangeCustomers();
    const db = t.db('smPtb');
    const col = collection(db, 'locations', LOC.PTB, 'customers');
    const byPhone = await assertSucceeds(
      getDocs(query(col, where('phone', '>=', '98765'), where('phone', '<', '98765'), orderBy('phone'), limit(10))),
    );
    expect(byPhone.docs.map((d) => d.data().phone)).toEqual(['9876543210']);
    const recent = await assertSucceeds(getDocs(query(col, orderBy('lastBillAt', 'desc'), limit(200))));
    expect(recent.size).toBe(2);
  });
});

describe('#5 bills: the customer fields of a new bill', () => {
  const create = (b, actor = 'smPtb') => setDoc(billRef(t.db(actor), billId('D01', 1)), b);

  it('accepts a valid customer', async () => {
    await assertSucceeds(create(makeBill()));
  });

  it('accepts a name of 1 and of 60 characters, and a WhatsApp number that differs or is null', async () => {
    for (const customer of [{ name: 'A' }, { name: 'B'.repeat(60) }, { whatsapp: '9123456780' }, { whatsapp: null }]) {
      await t.env.clearFirestore();
      await seedFixtures(t.env);
      await assertSucceeds(create(makeBill({ customer })));
    }
  });

  it('denies a missing, empty or 61-character name', async () => {
    const good = makeBill();
    const { customerName, ...noName } = good;
    await assertFails(create(noName));
    await assertFails(create(makeBill({ customerOverride: { customerName: '' } })));
    await assertFails(create(makeBill({ customerOverride: { customerName: 'N'.repeat(61) } })));
    await assertFails(create(makeBill({ customerOverride: { customerName: null } })));
    await assertFails(create(makeBill({ customerOverride: { customerName: 7 } })));
  });

  it('denies a name that is not trimmed', async () => {
    await assertFails(create(makeBill({ customerOverride: { customerName: ' Test Customer' } })));
    await assertFails(create(makeBill({ customerOverride: { customerName: 'Test Customer ' } })));
    await assertFails(create(makeBill({ customerOverride: { customerName: '   ' } })));
  });

  it('denies a phone that is missing, has 9 or 11 digits, starts with 5 or has a non-digit', async () => {
    const good = makeBill();
    const { customerPhone, ...noPhone } = good;
    await assertFails(create(noPhone));
    for (const phone of ['987654321', '98765432100', '5876543210', '0876543210', '98765 43210', '+919876543210', '98765x3210', null, 9876543210]) {
      await assertFails(create(makeBill({ customerOverride: { customerPhone: phone, customerId: `${phone}_aaaaaaaaaa` } })));
    }
  });

  it('denies a WhatsApp number that is not a mobile number or is of the wrong type', async () => {
    for (const w of ['abc', '', '12345', '5876543210', '98765432101', 9876543210, false]) {
      await assertFails(create(makeBill({ customerOverride: { customerWhatsapp: w } })));
    }
    const { customerWhatsapp, ...missing } = makeBill();
    await assertFails(create(missing));
  });

  it('denies a customerId that is missing, malformed, or does not start with the phone', async () => {
    const good = makeBill();
    const { customerId: _omit, ...noId } = good;
    await assertFails(create(noId));
    const key = ME.customerId.split('_')[1];
    for (const id of [
      `9123456780_${key}`, // another phone
      `5876543210_${key}`, // not a mobile
      `9876543210-${key}`, // wrong separator
      `9876543210_${key.slice(0, 9)}`, // key too short
      `9876543210_${key}a`, // key too long
      `9876543210_${key.toUpperCase().replace(/[0-9]/g, 'G')}`, // not hex
      '9876543210',
      '',
      null,
    ]) {
      await assertFails(create(makeBill({ customerOverride: { customerId: id } })));
    }
  });

  it('denies a bill with an extra customer field', async () => {
    await assertFails(create(makeBill({ customerOverride: { customerEmail: 'x@example.test' } })));
  });

  it('denies a bill created without any customer fields (D-034)', async () => {
    const { customerId: a, customerName: b, customerPhone: c, customerWhatsapp: d, ...old } = makeBill();
    await assertFails(create(old));
  });
});
