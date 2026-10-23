// BE-17: the staff roster (#15) and attendance (#16), D-042.
//
// The Admin keeps each store's roster (staff.manage); the Store Manager marks
// Present, Absent or Half-day with set() of the whole doc `{businessDate}_{staffId}`
// (attendance.mark at the location). Nothing is deleted. A batch of 15 marks
// (Limits.maxAttendanceBatch) has to stay inside the rules budget.

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
import { LOC } from './support/fixtures.js';
import { TODAY, attendanceId, makeAttendance, makeStaff } from './support/builders.js';
import { assertFails, assertSucceeds, useRulesEnv } from './support/env.js';
import { readLimits } from '../scripts/lib/core.js';
import { largestAttendanceBatch } from './support/caps.js';

const t = useRulesEnv();
const MAX_BATCH = readLimits().maxAttendanceBatch;

const staffRef = (db, id = 'staff1', loc = LOC.PTB) => doc(db, 'locations', loc, 'staff', id);
const markRef = (db, businessDate = TODAY, staffId = 'staff1', loc = LOC.PTB) =>
  doc(db, 'locations', loc, 'attendance', attendanceId(businessDate, staffId));

/** A roster entry as stored (rules off). */
const arrangeStaff = (id = 'staff1', loc = LOC.PTB, extra = {}) =>
  t.arrange((db) => setDoc(staffRef(db, id, loc), { ...makeStaff(), createdAt: new Date(), ...extra }));

/** A mark as stored (rules off). */
const arrangeMark = (o = {}, loc = LOC.PTB) =>
  t.arrange((db) => {
    const m = makeAttendance(o);
    return setDoc(markRef(db, m.businessDate, m.staffId, loc), { ...m, editedAt: new Date() });
  });

describe('#15 staff roster', () => {
  it('lets the Admin add a staff member at any location', async () => {
    await assertSucceeds(setDoc(staffRef(t.db('admin'), 'a1'), makeStaff()));
    await assertSucceeds(setDoc(staffRef(t.db('admin'), 'a2', LOC.MNJ), makeStaff({ name: 'Ravi', role: '' })));
  });

  it('requires createdBy to be the writer and createdAt the server time', async () => {
    const db = t.db('admin');
    await assertFails(setDoc(staffRef(db), { ...makeStaff(), createdBy: 'someone-else' }));
    await assertFails(setDoc(staffRef(db), { ...makeStaff(), createdAt: new Date() }));
  });

  it('checks the name (1 to 60) and role (up to 30) and the active flag on create', async () => {
    const db = t.db('admin');
    await assertSucceeds(setDoc(staffRef(db, 'ok60'), makeStaff({ name: 'x'.repeat(60), role: 'y'.repeat(30) })));
    await assertFails(setDoc(staffRef(db, 'n0'), makeStaff({ name: '' })));
    await assertFails(setDoc(staffRef(db, 'n61'), makeStaff({ name: 'x'.repeat(61) })));
    await assertFails(setDoc(staffRef(db, 'r31'), makeStaff({ role: 'y'.repeat(31) })));
    await assertFails(setDoc(staffRef(db, 'act'), { ...makeStaff(), active: 'yes' }));
    await assertFails(setDoc(staffRef(db, 'extra'), { ...makeStaff(), salary: 1 }));
    await assertFails(setDoc(staffRef(db, 'norole'), (({ role, ...rest }) => rest)(makeStaff())));
  });

  it('lets the Admin edit name, role and active with the update stamp, and nothing else', async () => {
    await arrangeStaff();
    const db = t.db('admin');
    const stamp = { updatedBy: 'admin', updatedAt: serverTimestamp() };
    await assertSucceeds(updateDoc(staffRef(db), { name: 'Asha K', role: 'Senior baker', ...stamp }));
    await assertSucceeds(updateDoc(staffRef(db), { active: false, ...stamp }));
    expect((await getDoc(staffRef(t.db('admin')))).data()).toMatchObject({ name: 'Asha K', active: false, updatedBy: 'admin' });
    await assertFails(updateDoc(staffRef(db), { createdBy: 'other', ...stamp }));
    await assertFails(updateDoc(staffRef(db), { name: 'No stamp' }));
    await assertFails(updateDoc(staffRef(db), { name: 'Wrong stamper', updatedBy: 'sm-ptb', updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(staffRef(db), { name: '', ...stamp }));
    await assertFails(updateDoc(staffRef(db), { name: 'y'.repeat(61), ...stamp }));
  });

  it('denies a Store Manager every roster write, at their own store too', async () => {
    await arrangeStaff();
    const sm = t.db('smPtb');
    await assertFails(setDoc(staffRef(sm, 'new1'), makeStaff({ uid: 'sm-ptb' })));
    await assertFails(updateDoc(staffRef(sm), { name: 'Hacked', updatedBy: 'sm-ptb', updatedAt: serverTimestamp() }));
    await assertFails(setDoc(staffRef(sm, 'new2', LOC.MNJ), makeStaff({ uid: 'sm-ptb' })));
  });

  it('never deletes, not even for the Admin', async () => {
    await arrangeStaff();
    await assertFails(deleteDoc(staffRef(t.db('admin'))));
    await assertFails(deleteDoc(staffRef(t.db('smPtb'))));
  });

  it('is readable by the Store Manager of that store and by the Admin, not by another store', async () => {
    await arrangeStaff();
    await arrangeStaff('staff9', LOC.MNJ);
    await assertSucceeds(getDoc(staffRef(t.db('smPtb'))));
    await assertSucceeds(getDocs(collection(t.db('smPtb'), 'locations', LOC.PTB, 'staff')));
    await assertSucceeds(getDoc(staffRef(t.db('admin'), 'staff9', LOC.MNJ)));
    await assertFails(getDoc(staffRef(t.db('smPtb'), 'staff9', LOC.MNJ)));
    await assertFails(getDoc(staffRef(t.db('smMnj'))));
    await assertFails(getDocs(collection(t.db('smMnj'), 'locations', LOC.PTB, 'staff')));
  });

  it('is not readable without a user, with a disabled user, or by a role with none of the permissions', async () => {
    await arrangeStaff();
    await assertFails(getDoc(staffRef(t.db('anonymous'))));
    await assertFails(getDoc(staffRef(t.db('disabled'))));
    await assertFails(getDoc(staffRef(t.db('noProfile'))));
    await assertFails(getDoc(staffRef(t.db('cashierPtb'))));
  });
});

describe('#16 attendance: marking', () => {
  it('lets the Store Manager mark today at their own store, with and without a note', async () => {
    const db = t.db('smPtb');
    await assertSucceeds(setDoc(markRef(db), makeAttendance()));
    await assertSucceeds(setDoc(markRef(db, TODAY, 'staff2'), makeAttendance({ staffId: 'staff2', status: 'HALF_DAY', note: 'Left at noon' })));
    await assertSucceeds(setDoc(markRef(db, TODAY, 'staff3'), makeAttendance({ staffId: 'staff3', status: 'ABSENT', note: 'x'.repeat(100) })));
    expect((await getDoc(markRef(t.db('smPtb'), TODAY, 'staff2'))).data()).toMatchObject({ status: 'HALF_DAY', note: 'Left at noon' });
  });

  it('accepts any past date: the 7-day window is the client\'s (D-031)', async () => {
    await assertSucceeds(setDoc(markRef(t.db('smPtb'), '2026-08-01'), makeAttendance({ businessDate: '2026-08-01' })));
  });

  it('marking again overwrites (last write wins), and a retry is harmless', async () => {
    const db = t.db('smPtb');
    await assertSucceeds(setDoc(markRef(db), makeAttendance({ status: 'ABSENT' })));
    await assertSucceeds(setDoc(markRef(db), makeAttendance({ status: 'PRESENT', note: 'Came late' })));
    await assertSucceeds(setDoc(markRef(db), makeAttendance({ status: 'PRESENT', note: 'Came late' })));
    expect((await getDoc(markRef(t.db('smPtb')))).data()).toMatchObject({ status: 'PRESENT', note: 'Came late' });
  });

  it('lets the Admin mark too (the role has attendance.mark everywhere)', async () => {
    await assertSucceeds(setDoc(markRef(t.db('admin'), TODAY, 'staff1', LOC.MNJ), makeAttendance({ uid: 'admin', userName: 'Admin' })));
  });

  it('denies a mark at another store (the Store Manager of MNJ marking at PTB, and the reverse)', async () => {
    await assertFails(setDoc(markRef(t.db('smMnj')), makeAttendance({ uid: 'sm-mnj' })));
    await assertFails(setDoc(markRef(t.db('smPtb'), TODAY, 'staff1', LOC.MNJ), makeAttendance()));
  });

  it('denies a role without attendance.mark, a disabled user and no user', async () => {
    await assertFails(setDoc(markRef(t.db('cashierPtb')), makeAttendance({ uid: 'cashier-ptb' })));
    await assertFails(setDoc(markRef(t.db('disabled')), makeAttendance({ uid: 'sm-ptb-disabled' })));
    await assertFails(setDoc(markRef(t.db('anonymous')), makeAttendance()));
  });

  it('denies deleting a mark, for the Store Manager and the Admin', async () => {
    await arrangeMark();
    await assertFails(deleteDoc(markRef(t.db('smPtb'))));
    await assertFails(deleteDoc(markRef(t.db('admin'))));
  });

  it('denies an ID that is not {businessDate}_{staffId} of the document', async () => {
    const db = t.db('smPtb');
    // staffId differs from the ID's second part.
    await assertFails(setDoc(markRef(db, TODAY, 'staff1'), makeAttendance({ staffId: 'staff2' })));
    // businessDate differs from the ID's first part.
    await assertFails(setDoc(markRef(db, TODAY), makeAttendance({ businessDate: '2026-09-25' })));
    // Not an attendance ID at all.
    await assertFails(setDoc(doc(db, 'locations', LOC.PTB, 'attendance', 'staff1'), makeAttendance()));
    await assertFails(setDoc(doc(db, 'locations', LOC.PTB, 'attendance', `${TODAY}-staff1`), makeAttendance()));
    // A date that is not YYYY-MM-DD.
    await assertFails(setDoc(markRef(db, '26-09-26'), makeAttendance({ businessDate: '26-09-26' })));
  });

  it('denies an unknown status', async () => {
    const db = t.db('smPtb');
    for (const status of ['LATE', 'present', 'HALFDAY', '', null, 1]) {
      await assertFails(setDoc(markRef(db), makeAttendance({ status })));
    }
  });

  it('denies a note over 100 characters, or one that is not a string', async () => {
    const db = t.db('smPtb');
    await assertFails(setDoc(markRef(db), makeAttendance({ note: 'x'.repeat(101) })));
    await assertFails(setDoc(markRef(db), makeAttendance({ note: 5 })));
  });

  it('checks who marked, the staff name, the device and the server time', async () => {
    const db = t.db('smPtb');
    await assertFails(setDoc(markRef(db), makeAttendance({ uid: 'sm-mnj' })));
    await assertFails(setDoc(markRef(db), makeAttendance({ staffName: '' })));
    await assertFails(setDoc(markRef(db), makeAttendance({ staffName: 'x'.repeat(61) })));
    await assertFails(setDoc(markRef(db), makeAttendance({ deviceId: 'phone' })));
    await assertFails(setDoc(markRef(db), { ...makeAttendance(), editedAt: new Date() }));
    await assertFails(setDoc(markRef(db), (({ editedAt, ...rest }) => rest)(makeAttendance())));
    await assertFails(setDoc(markRef(db), { ...makeAttendance(), extra: true }));
  });

  it('a correction cannot move the mark to another day or person by editing the fields in place', async () => {
    await arrangeMark();
    const db = t.db('smPtb');
    await assertFails(updateDoc(markRef(db), { staffId: 'staff2', editedAt: serverTimestamp() }));
    await assertFails(updateDoc(markRef(db), { businessDate: '2026-09-25', editedAt: serverTimestamp() }));
    await assertSucceeds(updateDoc(markRef(db), { status: 'ABSENT', editedAt: serverTimestamp() }));
  });
});

describe('#16 attendance: reading', () => {
  it('reads one day or a month of one store as that store\'s Store Manager', async () => {
    await arrangeMark();
    await arrangeMark({ businessDate: '2026-09-25' });
    const db = t.db('smPtb');
    const col = collection(db, 'locations', LOC.PTB, 'attendance');
    await assertSucceeds(getDoc(markRef(db)));
    const month = await assertSucceeds(
      getDocs(query(col, where('businessDate', '>=', '2026-09-01'), where('businessDate', '<', '2026-10-01'), orderBy('businessDate'))),
    );
    expect(month.size).toBe(2);
  });

  it('denies another store\'s Store Manager reading attendance, a document or a query', async () => {
    await arrangeMark();
    await assertFails(getDoc(markRef(t.db('smMnj'))));
    await assertFails(getDocs(collection(t.db('smMnj'), 'locations', LOC.PTB, 'attendance')));
  });

  it('lets the Admin read every location\'s attendance, per store and across stores', async () => {
    await arrangeMark();
    await arrangeMark({ staffId: 'staff7', uid: 'sm-mnj' }, LOC.MNJ);
    const admin = t.db('admin');
    await assertSucceeds(getDoc(markRef(admin)));
    await assertSucceeds(getDoc(markRef(admin, TODAY, 'staff7', LOC.MNJ)));
    const all = await assertSucceeds(getDocs(query(collectionGroup(admin, 'attendance'), where('businessDate', '==', TODAY))));
    expect(all.size).toBe(2);
  });

  it('denies the all-stores query to a Store Manager', async () => {
    await arrangeMark();
    await assertFails(getDocs(query(collectionGroup(t.db('smPtb'), 'attendance'), where('businessDate', '==', TODAY))));
  });
});

describe(`#16 attendance: a batch of ${MAX_BATCH} marks (Limits.maxAttendanceBatch) and the rules budget`, () => {
  const marks = (n, o = {}) => Array.from({ length: n }, (_, i) => makeAttendance({ staffId: `staff${String(i + 1).padStart(2, '0')}`, ...o }));

  function batchOfMarks(db, list, loc = LOC.PTB) {
    const b = writeBatch(db);
    for (const m of list) b.set(markRef(db, m.businessDate, m.staffId, loc), m);
    return b;
  }

  it('accepts a batch of 15 marks in one commit, then the same 15 again as corrections', async () => {
    await assertSucceeds(batchOfMarks(t.db('smPtb'), marks(MAX_BATCH)).commit());
    await assertSucceeds(batchOfMarks(t.db('smPtb'), marks(MAX_BATCH, { status: 'ABSENT' })).commit());
    const snap = await getDocs(collection(t.db('admin'), 'locations', LOC.PTB, 'attendance'));
    expect(snap.size).toBe(MAX_BATCH);
    expect(snap.docs.every((d) => d.data().status === 'ABSENT')).toBe(true);
  });

  it('denies the whole batch when one mark in it is bad', async () => {
    const list = marks(MAX_BATCH);
    list[7] = makeAttendance({ staffId: 'staff08', note: 'x'.repeat(101) });
    await assertFails(batchOfMarks(t.db('smPtb'), list).commit());
    const snap = await getDocs(collection(t.db('admin'), 'locations', LOC.PTB, 'attendance'));
    expect(snap.size).toBe(0);
  });

  // The headroom (expressions and access calls left under Firestore's limits)
  // is measured with the other cap cases in test/budget.test.js, on
  // largestAttendanceBatch: the batch needs two access calls however many
  // marks it holds (the user and the role), because rule #16 does not read the
  // roster.
  it('is the same batch the budget suite measures', () => {
    expect(largestAttendanceBatch.name).toBe(`attendance: ${MAX_BATCH} marks`);
  });
});
