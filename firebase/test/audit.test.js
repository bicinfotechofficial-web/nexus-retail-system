// BE-5: the audit log (04-PERMISSIONS #10).

import { describe, it } from 'vitest';
import { collection, deleteDoc, doc, getDoc, getDocs, query, setDoc, updateDoc, where } from 'firebase/firestore';
import { ACTORS, LOC } from './support/fixtures.js';
import { makeAudit } from './support/builders.js';
import { assertFails, assertSucceeds, useRulesEnv } from './support/env.js';

const t = useRulesEnv();

const auditRef = (db, id) => doc(db, 'auditLog', id);
const create = (actor, id, fields) => setDoc(auditRef(t.db(actor), id), makeAudit({ uid: ACTORS[actor].uid, ...fields }));

describe('#10 auditLog: create', () => {
  it('lets an SM record location events under {loc}-{entityId} (D-028)', async () => {
    await assertSucceeds(create('smPtb', 'PTB-D01-000001-X', { action: 'BILL_CANCEL', entityPath: 'locations/PTB/bills/D01-000001' }));
    await assertSucceeds(create('smPtb', 'PTB-D01-R000001', { action: 'RETURN', entityPath: 'locations/PTB/returns/D01-R000001' }));
    await assertSucceeds(create('smPtb', 'PTB-D01-M000001', { action: 'STOCK_ADJUST', entityPath: 'locations/PTB/movements/D01-M000001' }));
    await assertSucceeds(create('smPtb', 'PTB-D01-OVR-1790000000000', { action: 'OFFLINE_OVERRIDE', entityPath: 'locations/PTB/devices/D01' }));
  });

  it('denies an ID without the location prefix, or with another location\'s', async () => {
    await assertFails(create('smPtb', 'D01-000001-X', { action: 'BILL_CANCEL', entityPath: 'x' }));
    await assertFails(create('smPtb', 'MNJ-D01-000001-X', { action: 'BILL_CANCEL', entityPath: 'x' }));
  });

  it('denies an SM recording at another location', async () => {
    await assertFails(create('smPtb', 'MNJ-D01-000001-X', { action: 'BILL_CANCEL', entityPath: 'x', locationId: LOC.MNJ }));
  });

  it('denies by other than the caller, a client at, an unknown action and extra fields', async () => {
    const id = 'PTB-D01-000001-X';
    const ok = { action: 'BILL_CANCEL', entityPath: 'x' };
    await assertFails(setDoc(auditRef(t.db('smPtb'), id), makeAudit({ ...ok, uid: ACTORS.admin.uid })));
    await assertFails(setDoc(auditRef(t.db('smPtb'), id), { ...makeAudit(ok), at: new Date() }));
    await assertFails(create('smPtb', id, { action: 'COFFEE_BREAK', entityPath: 'x' }));
    await assertFails(setDoc(auditRef(t.db('smPtb'), id), { ...makeAudit(ok), extra: 1 }));
  });

  it('keeps Admin actions to their permissions', async () => {
    const product = { action: 'PRICE_CHANGE', entityPath: 'products/p1', locationId: null, deviceId: null };
    await assertFails(create('smPtb', 'PRICE-p1-1790000000000', product));
    await assertSucceeds(create('admin', 'PRICE-p1-1790000000000', product));
    await assertFails(create('admin', 'p1-1790000000000', product));
    const user = { action: 'USER_DISABLE', entityPath: 'users/sm-ptb', locationId: 'PTB', deviceId: null };
    await assertFails(create('smPtb', 'PTB-USR-sm-ptb-1790000000000', user));
    await assertSucceeds(create('admin', 'PTB-USR-sm-ptb-1790000000000', user));
    await assertFails(create('admin', 'USR-sm-ptb-1790000000001', user));
  });

  it('needs catalog.manage for PRODUCT_APPROVE and PRODUCT_DECLINE, global with the right ID (D-038)', async () => {
    const decline = { action: 'PRODUCT_DECLINE', entityPath: 'products/p1', locationId: null, deviceId: null };
    await assertSucceeds(create('admin', 'DECLINE-p1-1790000000000', decline));
    await assertFails(create('smPtb', 'DECLINE-p1-1790000000001', decline));
    // The ID shape is DECLINE-{productId}-{millis}: another prefix, a missing time or an APPROVE ID are denied.
    await assertFails(create('admin', 'APPROVE-p1-1790000000002', decline));
    await assertFails(create('admin', 'PRICE-p1-1790000000003', decline));
    await assertFails(create('admin', 'DECLINE-p1', decline));
    await assertFails(create('admin', 'DECLINE-p1-x', decline));
    await assertFails(create('admin', 'p1-1790000000004', decline));
    // Global: a location, or a location-prefixed ID, is not allowed.
    await assertFails(create('admin', 'PTB-DECLINE-p1-1790000000005', { ...decline, locationId: 'PTB' }));
    await assertFails(create('admin', 'DECLINE-p1-1790000000006', { ...decline, locationId: 'PTB' }));
    // And a decline can't take an approval's ID shape in the other direction.
    const approve = { action: 'PRODUCT_APPROVE', entityPath: 'products/p1', locationId: null, deviceId: null };
    await assertSucceeds(create('admin', 'APPROVE-p1-1790000000007', approve));
    await assertFails(create('admin', 'DECLINE-p1-1790000000008', approve));
    await assertFails(create('smPtb', 'APPROVE-p1-1790000000009', approve));
  });

  it('scopes expense audits to their location (D-032)', async () => {
    const expense = { action: 'EXPENSE_CREATE', entityPath: 'expenses/e1', locationId: 'PTB', deviceId: null };
    await assertSucceeds(create('admin', 'PTB-EXP-e1-1790000000000', expense));
    await assertFails(create('smPtb', 'PTB-EXP-e2-1790000000000', expense));
    await assertFails(create('admin', 'EXP-e1-1790000000001', expense));
    await assertFails(create('admin', 'MNJ-EXP-e1-1790000000002', expense));
  });

  it('denies a location event with a null locationId, and one without its permission (QA-037)', async () => {
    const cancel = { action: 'BILL_CANCEL', entityPath: 'locations/MNJ/bills/D01-000001', locationId: null, deviceId: null };
    await assertFails(create('smPtb', 'MNJ-D01-000001-X', cancel));
    const cancelMnj = { ...cancel, locationId: 'MNJ' };
    await assertFails(create('smPtb', 'MNJ-D01-000001-X', cancelMnj));
    const adjust = { action: 'STOCK_ADJUST', entityPath: 'locations/PTB/movements/D01-M000001', locationId: 'PTB', deviceId: 'D01' };
    await assertFails(create('cashierPtb', 'PTB-D01-M000001', adjust));
    await assertSucceeds(create('smPtb', 'PTB-D01-M000001', adjust));
  });

  it('ties each action to its ID shape (QA-044)', async () => {
    const override = { action: 'OFFLINE_OVERRIDE', entityPath: 'locations/PTB/devices/D01', locationId: 'PTB', deviceId: 'D01', uid: 'cashier-ptb' };
    // An override can't take a cancellation's or an expense's ID.
    await assertFails(create('cashierPtb', 'PTB-D01-000001-X', override));
    await assertFails(create('cashierPtb', 'PTB-EXP-e1-1790000000000', override));
    await assertSucceeds(create('cashierPtb', 'PTB-D01-OVR-1790000000000', override));
    // THRESHOLD_CHANGE is reserved (D-032).
    const threshold = { action: 'THRESHOLD_CHANGE', entityPath: 'locations/PTB/stock/FG_x', locationId: 'PTB', deviceId: 'D01' };
    await assertFails(create('smPtb', 'PTB-D01-M000001', threshold));
  });

  it('denies a disabled user and an anonymous user', async () => {
    await assertFails(create('disabled', 'PTB-D01-000001-X', { action: 'BILL_CANCEL', entityPath: 'x' }));
    await assertFails(setDoc(auditRef(t.db('anonymous'), 'PTB-D01-000001-X'), makeAudit({ action: 'BILL_CANCEL', entityPath: 'x' })));
  });

  it('denies updating or deleting an entry (create-only)', async () => {
    await t.arrange((db) => setDoc(auditRef(db, 'PTB-D01-000001-X'), { ...makeAudit({ action: 'BILL_CANCEL', entityPath: 'x' }), at: new Date() }));
    await assertFails(updateDoc(auditRef(t.db('admin'), 'PTB-D01-000001-X'), { reason: 'edited' }));
    await assertFails(deleteDoc(auditRef(t.db('admin'), 'PTB-D01-000001-X')));
    await assertFails(create('smPtb', 'PTB-D01-000001-X', { action: 'BILL_CANCEL', entityPath: 'x' }));
  });
});

describe('#10 auditLog: read', () => {
  it('lets audit.view read and filter every location', async () => {
    await t.arrange((db) => setDoc(auditRef(db, 'MNJ-D01-000001-X'), { ...makeAudit({ action: 'BILL_CANCEL', entityPath: 'x', locationId: LOC.MNJ }), at: new Date() }));
    const db = t.db('admin');
    await assertSucceeds(getDoc(auditRef(db, 'MNJ-D01-000001-X')));
    await assertSucceeds(getDocs(query(collection(db, 'auditLog'), where('locationId', '==', LOC.MNJ))));
  });

  it('denies a Store Manager, who has no audit.view', async () => {
    await t.arrange((db) => setDoc(auditRef(db, 'PTB-D01-000001-X'), { ...makeAudit({ action: 'BILL_CANCEL', entityPath: 'x' }), at: new Date() }));
    await assertFails(getDoc(auditRef(t.db('smPtb'), 'PTB-D01-000001-X')));
    await assertFails(getDocs(collection(t.db('smPtb'), 'auditLog')));
  });

  it('keeps a location-scoped audit.view role to its own location', async () => {
    await t.arrange(async (db) => {
      await setDoc(doc(db, 'roles/AUDITOR'), { name: 'Auditor', permissions: ['audit.view'], allLocations: false });
      await updateDoc(doc(db, 'users', ACTORS.smPtb.uid), { roleId: 'AUDITOR' });
      await setDoc(auditRef(db, 'PTB-D01-000001-X'), { ...makeAudit({ action: 'BILL_CANCEL', entityPath: 'x' }), at: new Date() });
      await setDoc(auditRef(db, 'MNJ-D01-000001-X'), { ...makeAudit({ action: 'BILL_CANCEL', entityPath: 'x', locationId: LOC.MNJ }), at: new Date() });
    });
    const db = t.db('smPtb');
    await assertSucceeds(getDoc(auditRef(db, 'PTB-D01-000001-X')));
    await assertFails(getDoc(auditRef(db, 'MNJ-D01-000001-X')));
    await assertSucceeds(getDocs(query(collection(db, 'auditLog'), where('locationId', '==', LOC.PTB))));
    await assertFails(getDocs(collection(db, 'auditLog')));
  });
});
