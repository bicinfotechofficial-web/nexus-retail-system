// BE-2: helpers, default deny, roles, users, locations and devices
// (04-PERMISSIONS #1-4).

import { describe, it } from 'vitest';
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  increment,
  runTransaction,
  serverTimestamp,
  setDoc,
  updateDoc,
  writeBatch,
} from 'firebase/firestore';
import { ACTORS, LOC, LOCATIONS, ROLE } from './support/fixtures.js';
import { assertFails, assertSucceeds, useRulesEnv } from './support/env.js';

const t = useRulesEnv();

// ---- Builders ---------------------------------------------------------

function newUser(overrides = {}) {
  return {
    name: 'New Store Manager',
    email: 'new-sm@example.test',
    roleId: ROLE.STORE_MANAGER,
    locationId: LOC.PTB,
    active: true,
    createdAt: serverTimestamp(),
    createdBy: ACTORS.admin.uid,
    ...overrides,
  };
}

function newLocation(code, overrides = {}) {
  return { ...LOCATIONS[LOC.PTB], code, name: `Store ${code}`, nextDeviceNo: 0, ...overrides };
}

function newDevice(code, uid, overrides = {}) {
  return {
    code,
    label: 'Counter 1',
    registeredBy: uid,
    registeredAt: serverTimestamp(),
    lastSeenAt: serverTimestamp(),
    lastBillSeq: 0,
    lastMovementSeq: 0,
    lastReturnSeq: 0,
    retired: false,
    ...overrides,
  };
}

/** The registration batch: nextDeviceNo +1 and devices/{code}. */
function registrationBatch(db, loc, { nextDeviceNo, code, uid }) {
  const b = writeBatch(db);
  b.update(doc(db, 'locations', loc), { nextDeviceNo });
  b.set(doc(db, 'locations', loc, 'devices', code), newDevice(code, uid));
  return b;
}

/** Arranges PTB with D01 registered by SM@PTB. */
async function withDeviceD01(fields = {}) {
  await t.arrange(async (db) => {
    await updateDoc(doc(db, 'locations', LOC.PTB), { nextDeviceNo: 1 });
    await setDoc(
      doc(db, 'locations', LOC.PTB, 'devices', 'D01'),
      newDevice('D01', ACTORS.smPtb.uid, fields),
    );
  });
}

const devicePath = (loc = LOC.PTB, id = 'D01') => `locations/${loc}/devices/${id}`;

// ---- #1 Default deny --------------------------------------------------

describe('#1 default deny', () => {
  it('denies an anonymous user everything', async () => {
    const db = t.db('anonymous');
    await assertFails(getDoc(doc(db, 'locations', LOC.PTB)));
    await assertFails(getDoc(doc(db, 'users', ACTORS.smPtb.uid)));
    await assertFails(setDoc(doc(db, 'locations/XYZ'), newLocation('XYZ')));
  });

  it('denies a disabled user their location and devices', async () => {
    await withDeviceD01();
    const db = t.db('disabled');
    await assertFails(getDoc(doc(db, 'locations', LOC.PTB)));
    await assertFails(getDoc(doc(db, devicePath())));
    await assertFails(registrationBatch(db, LOC.PTB, { nextDeviceNo: 2, code: 'D02', uid: ACTORS.disabled.uid }).commit());
  });

  it('denies a signed-in user without a profile their location', async () => {
    await assertFails(getDoc(doc(t.db('noProfile'), 'locations', LOC.PTB)));
  });

  it('denies collections the contract does not name, even to the Admin', async () => {
    const db = t.db('admin');
    await assertFails(getDoc(doc(db, 'scratch/any')));
    await assertFails(setDoc(doc(db, 'scratch/any'), { x: 1 }));
  });
});

// ---- #2 roles ---------------------------------------------------------

describe('#2 roles', () => {
  it('lets any signed-in user read roles, active or not', async () => {
    for (const actor of ['admin', 'smPtb', 'disabled', 'noProfile']) {
      await assertSucceeds(getDoc(doc(t.db(actor), 'roles', ROLE.STORE_MANAGER)));
    }
    await assertSucceeds(getDocs(collection(t.db('smPtb'), 'roles')));
  });

  it('denies an anonymous read', async () => {
    await assertFails(getDoc(doc(t.db('anonymous'), 'roles', ROLE.ADMIN)));
  });

  it('denies every client write, even from the Admin', async () => {
    const db = t.db('admin');
    await assertFails(updateDoc(doc(db, 'roles', ROLE.STORE_MANAGER), { allLocations: true }));
    await assertFails(setDoc(doc(db, 'roles/CASHIER'), { name: 'Cashier', permissions: [], allLocations: false }));
    await assertFails(deleteDoc(doc(db, 'roles', ROLE.STORE_MANAGER)));
  });
});

// ---- #3 users ---------------------------------------------------------

describe('#3 users: read', () => {
  it('lets a user read their own doc', async () => {
    await assertSucceeds(getDoc(doc(t.db('smPtb'), 'users', ACTORS.smPtb.uid)));
  });

  it('lets a disabled user read their own doc, so sign-in can report userDisabled', async () => {
    await assertSucceeds(getDoc(doc(t.db('disabled'), 'users', ACTORS.disabled.uid)));
  });

  it('lets a user without a profile look up their (missing) doc, so sign-in can report noProfile', async () => {
    const snap = await assertSucceeds(getDoc(doc(t.db('noProfile'), 'users', ACTORS.noProfile.uid)));
    if (snap.exists()) throw new Error('expected no profile doc');
  });

  it("denies reading someone else's doc without user.manage", async () => {
    await assertFails(getDoc(doc(t.db('smPtb'), 'users', ACTORS.admin.uid)));
    await assertFails(getDoc(doc(t.db('smPtb'), 'users', ACTORS.smMnj.uid)));
    await assertFails(getDoc(doc(t.db('disabled'), 'users', ACTORS.smPtb.uid)));
  });

  it('lets user.manage read and list every user', async () => {
    await assertSucceeds(getDoc(doc(t.db('admin'), 'users', ACTORS.smMnj.uid)));
    await assertSucceeds(getDocs(collection(t.db('admin'), 'users')));
  });

  it('denies listing users without user.manage', async () => {
    await assertFails(getDocs(collection(t.db('smPtb'), 'users')));
  });
});

describe('#3 users: create', () => {
  it('lets user.manage create a Store Manager', async () => {
    await assertSucceeds(setDoc(doc(t.db('admin'), 'users/new-sm'), newUser()));
  });

  it('lets user.manage create a user with no location', async () => {
    await assertSucceeds(setDoc(doc(t.db('admin'), 'users/new-admin'), newUser({ roleId: ROLE.ADMIN, locationId: null })));
  });

  it('denies creating a user without user.manage', async () => {
    await assertFails(setDoc(doc(t.db('smPtb'), 'users/new-sm'), newUser({ createdBy: ACTORS.smPtb.uid })));
  });

  it('denies creating your own profile', async () => {
    await assertFails(setDoc(doc(t.db('noProfile'), 'users', ACTORS.noProfile.uid), newUser({ createdBy: ACTORS.noProfile.uid })));
  });

  it('denies an unknown role, an unknown location, a wrong createdBy, a client createdAt and extra fields', async () => {
    const db = t.db('admin');
    const ref = doc(db, 'users/new-sm');
    await assertFails(setDoc(ref, newUser({ roleId: 'SUPERUSER' })));
    await assertFails(setDoc(ref, newUser({ locationId: 'XYZ' })));
    await assertFails(setDoc(ref, newUser({ createdBy: ACTORS.smPtb.uid })));
    await assertFails(setDoc(ref, newUser({ createdAt: new Date() })));
    await assertFails(setDoc(ref, newUser({ isAdmin: true })));
  });
});

describe('#3 users: update and delete', () => {
  it('lets user.manage disable a user, and move them to another location', async () => {
    const db = t.db('admin');
    await assertSucceeds(updateDoc(doc(db, 'users', ACTORS.smPtb.uid), { active: false }));
    await assertSucceeds(updateDoc(doc(db, 'users', ACTORS.smMnj.uid), { locationId: LOC.PTB }));
  });

  it('lets user.manage rename themselves', async () => {
    await assertSucceeds(updateDoc(doc(t.db('admin'), 'users', ACTORS.admin.uid), { name: 'Admin (Head Office)' }));
  });

  it('denies anyone changing their own roleId, locationId or active, user.manage included', async () => {
    const admin = doc(t.db('admin'), 'users', ACTORS.admin.uid);
    await assertFails(updateDoc(admin, { active: false }));
    await assertFails(updateDoc(admin, { locationId: LOC.PTB }));
    await assertFails(updateDoc(admin, { roleId: ROLE.STORE_MANAGER }));
  });

  it('denies a user without user.manage changing their own doc', async () => {
    const own = doc(t.db('smPtb'), 'users', ACTORS.smPtb.uid);
    await assertFails(updateDoc(own, { locationId: LOC.MNJ }));
    await assertFails(updateDoc(own, { roleId: ROLE.ADMIN }));
    await assertFails(updateDoc(own, { name: 'Renamed' }));
  });

  it('denies a disabled user re-enabling themselves', async () => {
    await assertFails(updateDoc(doc(t.db('disabled'), 'users', ACTORS.disabled.uid), { active: true }));
  });

  it('denies an update to an unknown role or with createdBy changed', async () => {
    const ref = doc(t.db('admin'), 'users', ACTORS.smPtb.uid);
    await assertFails(updateDoc(ref, { roleId: 'SUPERUSER' }));
    await assertFails(updateDoc(ref, { createdBy: ACTORS.admin.uid }));
  });

  it('denies deleting a user, even with user.manage', async () => {
    await assertFails(deleteDoc(doc(t.db('admin'), 'users', ACTORS.smPtb.uid)));
  });
});

// ---- #4 locations -----------------------------------------------------

describe('#4 locations: read', () => {
  it('lets an active user read their own location', async () => {
    await assertSucceeds(getDoc(doc(t.db('smPtb'), 'locations', LOC.PTB)));
  });

  it('denies an SM reading another location', async () => {
    await assertFails(getDoc(doc(t.db('smPtb'), 'locations', LOC.MNJ)));
    await assertFails(getDoc(doc(t.db('smMnj'), 'locations', LOC.PTB)));
  });

  it('lets the Admin read every location', async () => {
    await assertSucceeds(getDoc(doc(t.db('admin'), 'locations', LOC.MNJ)));
    await assertSucceeds(getDocs(collection(t.db('admin'), 'locations')));
  });

  it('denies an SM listing every location', async () => {
    await assertFails(getDocs(collection(t.db('smPtb'), 'locations')));
  });
});

describe('#4 locations: create, update, delete', () => {
  it('lets location.manage create a location with nextDeviceNo 0', async () => {
    await assertSucceeds(setDoc(doc(t.db('admin'), 'locations/KOC'), newLocation('KOC')));
  });

  it('denies a new location whose nextDeviceNo is not 0, or whose code is wrong', async () => {
    const db = t.db('admin');
    await assertFails(setDoc(doc(db, 'locations/KOC'), newLocation('KOC', { nextDeviceNo: 3 })));
    await assertFails(setDoc(doc(db, 'locations/KOC'), newLocation('PTB')));
    await assertFails(setDoc(doc(db, 'locations/koc'), newLocation('koc')));
    await assertFails(setDoc(doc(db, 'locations/KOCHI'), newLocation('KOCHI')));
  });

  it('denies a new location with missing or extra fields', async () => {
    const { receiptFooter, ...missing } = newLocation('KOC');
    await assertFails(setDoc(doc(t.db('admin'), 'locations/KOC'), missing));
    await assertFails(setDoc(doc(t.db('admin'), 'locations/KOC'), newLocation('KOC', { owner: 'x' })));
  });

  it('denies creating a location without location.manage', async () => {
    await assertFails(setDoc(doc(t.db('smPtb'), 'locations/KOC'), newLocation('KOC')));
  });

  it('lets location.manage edit a location', async () => {
    const ref = doc(t.db('admin'), 'locations', LOC.PTB);
    await assertSucceeds(updateDoc(ref, { receiptFooter: 'See you soon', maxDiscountPct: null }));
    await assertSucceeds(updateDoc(ref, { offlineLimitHours: 6, overrideExtensionHours: 3 }));
  });

  it('denies location.manage changing nextDeviceNo or code', async () => {
    const ref = doc(t.db('admin'), 'locations', LOC.PTB);
    await assertFails(updateDoc(ref, { nextDeviceNo: 5 }));
    await assertFails(updateDoc(ref, { code: 'PTX' }));
  });

  it('denies an SM editing their location', async () => {
    await assertFails(updateDoc(doc(t.db('smPtb'), 'locations', LOC.PTB), { receiptFooter: 'Hi' }));
  });

  it('denies an out-of-range discount cap', async () => {
    await assertFails(updateDoc(doc(t.db('admin'), 'locations', LOC.PTB), { maxDiscountPct: 150 }));
  });

  it('denies deleting a location', async () => {
    await assertFails(deleteDoc(doc(t.db('admin'), 'locations', LOC.PTB)));
  });
});

describe('#4 device registration', () => {
  it('lets device.register increment nextDeviceNo by 1 and create that device, in a batch', async () => {
    const db = t.db('smPtb');
    await assertSucceeds(registrationBatch(db, LOC.PTB, { nextDeviceNo: 1, code: 'D01', uid: ACTORS.smPtb.uid }).commit());
  });

  it('works as the transaction DeviceService runs, twice in a row', async () => {
    const db = t.db('smPtb');
    const register = () =>
      runTransaction(db, async (tx) => {
        const locRef = doc(db, 'locations', LOC.PTB);
        const next = (await tx.get(locRef)).data().nextDeviceNo + 1;
        const code = `D${String(next).padStart(2, '0')}`;
        tx.update(locRef, { nextDeviceNo: increment(1) });
        tx.set(doc(db, 'locations', LOC.PTB, 'devices', code), newDevice(code, ACTORS.smPtb.uid));
        return code;
      });
    const first = await assertSucceeds(register());
    const second = await assertSucceeds(register());
    if (first !== 'D01' || second !== 'D02') throw new Error(`got ${first}, ${second}`);
  });

  it('lets the Admin register a device at any location', async () => {
    await assertSucceeds(registrationBatch(t.db('admin'), LOC.MNJ, { nextDeviceNo: 1, code: 'D01', uid: ACTORS.admin.uid }).commit());
  });

  it('pads codes to two digits past D09', async () => {
    await t.arrange((db) => updateDoc(doc(db, 'locations', LOC.PTB), { nextDeviceNo: 9 }));
    const db = t.db('smPtb');
    await assertFails(registrationBatch(db, LOC.PTB, { nextDeviceNo: 10, code: 'D010', uid: ACTORS.smPtb.uid }).commit());
    await assertSucceeds(registrationBatch(db, LOC.PTB, { nextDeviceNo: 10, code: 'D10', uid: ACTORS.smPtb.uid }).commit());
  });

  it('denies incrementing nextDeviceNo without creating the device', async () => {
    await assertFails(updateDoc(doc(t.db('smPtb'), 'locations', LOC.PTB), { nextDeviceNo: 1 }));
  });

  it('denies creating a device without incrementing nextDeviceNo', async () => {
    const db = t.db('smPtb');
    await assertFails(setDoc(doc(db, devicePath()), newDevice('D01', ACTORS.smPtb.uid)));
    // Even when nextDeviceNo already names a code that has no device doc.
    await t.arrange((a) => updateDoc(doc(a, 'locations', LOC.PTB), { nextDeviceNo: 1 }));
    await assertFails(setDoc(doc(db, devicePath()), newDevice('D01', ACTORS.smPtb.uid)));
  });

  it('denies skipping a number, or creating a device code other than the new number', async () => {
    const db = t.db('smPtb');
    await assertFails(registrationBatch(db, LOC.PTB, { nextDeviceNo: 2, code: 'D02', uid: ACTORS.smPtb.uid }).commit());
    await assertFails(registrationBatch(db, LOC.PTB, { nextDeviceNo: 1, code: 'D02', uid: ACTORS.smPtb.uid }).commit());
  });

  it('denies reusing a device code that already exists', async () => {
    // An inconsistent state that can't arise through the rules: D01 exists
    // but nextDeviceNo is still 0.
    await t.arrange((db) => setDoc(doc(db, devicePath()), newDevice('D01', ACTORS.admin.uid)));
    await assertFails(registrationBatch(t.db('smPtb'), LOC.PTB, { nextDeviceNo: 1, code: 'D01', uid: ACTORS.smPtb.uid }).commit());
  });

  it('denies an SM registering at another location', async () => {
    await assertFails(registrationBatch(t.db('smPtb'), LOC.MNJ, { nextDeviceNo: 1, code: 'D01', uid: ACTORS.smPtb.uid }).commit());
  });

  it('denies a device that does not start clean', async () => {
    const db = t.db('smPtb');
    const attempt = (fields) => {
      const b = writeBatch(db);
      b.update(doc(db, 'locations', LOC.PTB), { nextDeviceNo: 1 });
      b.set(doc(db, devicePath()), newDevice('D01', ACTORS.smPtb.uid, fields));
      return b.commit();
    };
    await assertFails(attempt({ lastBillSeq: 500 }));
    await assertFails(attempt({ retired: true }));
    await assertFails(attempt({ registeredBy: ACTORS.admin.uid }));
    await assertFails(attempt({ registeredAt: new Date() }));
    await assertFails(attempt({ code: 'D09' }));
  });

  it('denies changing nextDeviceNo together with other location fields', async () => {
    const db = t.db('admin');
    const b = writeBatch(db);
    b.update(doc(db, 'locations', LOC.PTB), { nextDeviceNo: 1, receiptFooter: 'Hi' });
    b.set(doc(db, devicePath()), newDevice('D01', ACTORS.admin.uid));
    await assertFails(b.commit());
  });
});

// ---- #4 devices -------------------------------------------------------

describe('#4 devices: read', () => {
  it('lets device.register at the location read its devices', async () => {
    await withDeviceD01();
    await assertSucceeds(getDoc(doc(t.db('smPtb'), devicePath())));
    await assertSucceeds(getDocs(collection(t.db('smPtb'), 'locations', LOC.PTB, 'devices')));
  });

  it('lets location.manage read devices anywhere', async () => {
    await withDeviceD01();
    await assertSucceeds(getDocs(collection(t.db('admin'), 'locations', LOC.PTB, 'devices')));
  });

  it("denies another location's SM", async () => {
    await withDeviceD01();
    await assertFails(getDoc(doc(t.db('smMnj'), devicePath())));
    await assertFails(getDocs(collection(t.db('smMnj'), 'locations', LOC.PTB, 'devices')));
  });
});

describe('#4 devices: update', () => {
  it('lets bill.create, stock.move and return.create raise their sequence', async () => {
    await withDeviceD01({ lastBillSeq: 10, lastMovementSeq: 4, lastReturnSeq: 1 });
    const ref = doc(t.db('smPtb'), devicePath());
    await assertSucceeds(updateDoc(ref, { lastBillSeq: 11 }));
    await assertSucceeds(updateDoc(ref, { lastMovementSeq: 9 }));
    await assertSucceeds(updateDoc(ref, { lastReturnSeq: 2 }));
  });

  it('accepts the merge the bill batch writes', async () => {
    await withDeviceD01({ lastBillSeq: 10 });
    await assertSucceeds(setDoc(doc(t.db('smPtb'), devicePath()), { lastBillSeq: 11 }, { merge: true }));
  });

  it('denies lowering a sequence', async () => {
    await withDeviceD01({ lastBillSeq: 10, lastMovementSeq: 4, lastReturnSeq: 3 });
    const ref = doc(t.db('smPtb'), devicePath());
    await assertFails(updateDoc(ref, { lastBillSeq: 9 }));
    await assertFails(updateDoc(ref, { lastMovementSeq: 0 }));
    await assertFails(updateDoc(ref, { lastReturnSeq: 2 }));
    await assertFails(updateDoc(ref, { lastBillSeq: '11' }));
  });

  it("denies another location's SM raising a sequence", async () => {
    await withDeviceD01({ lastBillSeq: 10 });
    await assertFails(updateDoc(doc(t.db('smMnj'), devicePath()), { lastBillSeq: 11 }));
  });

  it('lets any active user at the location stamp lastSeenAt with the server time', async () => {
    await withDeviceD01();
    await assertSucceeds(updateDoc(doc(t.db('smPtb'), devicePath()), { lastSeenAt: serverTimestamp() }));
  });

  it('denies a client-supplied lastSeenAt, and a disabled user', async () => {
    await withDeviceD01();
    await assertFails(updateDoc(doc(t.db('smPtb'), devicePath()), { lastSeenAt: new Date() }));
    await assertFails(updateDoc(doc(t.db('disabled'), devicePath()), { lastSeenAt: serverTimestamp() }));
  });

  it('lets location.manage relabel and retire a device', async () => {
    await withDeviceD01();
    const ref = doc(t.db('admin'), devicePath());
    await assertSucceeds(updateDoc(ref, { label: 'Counter 2' }));
    await assertSucceeds(updateDoc(ref, { retired: true }));
  });

  it('denies an SM relabelling or retiring a device', async () => {
    await withDeviceD01();
    const ref = doc(t.db('smPtb'), devicePath());
    await assertFails(updateDoc(ref, { label: 'Mine' }));
    await assertFails(updateDoc(ref, { retired: true }));
  });

  it('denies changing code, registeredBy or unknown fields, and deleting', async () => {
    await withDeviceD01();
    const ref = doc(t.db('admin'), devicePath());
    await assertFails(updateDoc(ref, { code: 'D02' }));
    await assertFails(updateDoc(ref, { registeredBy: ACTORS.admin.uid }));
    await assertFails(updateDoc(ref, { printer: 'x' }));
    await assertFails(deleteDoc(ref));
  });
});
