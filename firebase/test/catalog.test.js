// BE-5: products and raw materials (04-PERMISSIONS #11).

import { describe, expect, it } from 'vitest';
import { collection, deleteDoc, doc, getDoc, getDocs, query, serverTimestamp, setDoc, updateDoc, where } from 'firebase/firestore';
import { ACTORS, LOC } from './support/fixtures.js';
import { makeProduct } from './support/builders.js';
import { assertFails, assertSucceeds, seedFixtures, useRulesEnv } from './support/env.js';

const t = useRulesEnv();

const productRef = (db, id = 'p1') => doc(db, 'products', id);
const materialRef = (db, id = 'flour') => doc(db, 'rawMaterials', id);
const suggestion = (overrides = {}) =>
  makeProduct({ status: 'PENDING', price: null, proposedPrice: 45000, scope: LOC.PTB, uid: ACTORS.smPtb.uid, ...overrides });
const arrangeProduct = (fields = {}) =>
  t.arrange((db) => setDoc(productRef(db), { ...makeProduct(), createdAt: new Date(), updatedAt: new Date(), ...fields }));

/** The Admin's approval of a PENDING suggestion (D-038): what AdminPlans.approveProduct writes. */
const approval = (fields = {}) => ({
  status: 'ACTIVE',
  price: 45000,
  reviewedBy: ACTORS.admin.uid,
  reviewedAt: serverTimestamp(),
  updatedAt: serverTimestamp(),
  ...fields,
});
/** The Admin's decline (D-038): what AdminPlans.declineProduct writes. */
const decline = (fields = {}) => ({
  status: 'INACTIVE',
  reviewNote: 'Too close to the Black Forest',
  reviewedBy: ACTORS.admin.uid,
  reviewedAt: serverTimestamp(),
  updatedAt: serverTimestamp(),
  ...fields,
});
const arrangePending = (fields = {}) =>
  arrangeProduct({ status: 'PENDING', price: null, proposedPrice: 45000, scope: LOC.PTB, createdBy: ACTORS.smPtb.uid, ...fields });

describe('#11 products: create', () => {
  it('lets catalog.manage create an active product', async () => {
    await assertSucceeds(setDoc(productRef(t.db('admin')), makeProduct()));
  });

  it('lets catalog.suggest create a PENDING product for their own location (D-008)', async () => {
    await assertSucceeds(setDoc(productRef(t.db('smPtb')), suggestion()));
  });

  it('denies a suggestion that is active, priced, global or for another location', async () => {
    const db = t.db('smPtb');
    await assertFails(setDoc(productRef(db), suggestion({ status: 'ACTIVE' })));
    await assertFails(setDoc(productRef(db), suggestion({ price: 45000 })));
    await assertFails(setDoc(productRef(db), suggestion({ scope: 'GLOBAL' })));
    await assertFails(setDoc(productRef(db), suggestion({ scope: LOC.MNJ })));
  });

  it('denies a bad ID, createdBy other than the caller, missing fields and a unit other than PCS', async () => {
    const db = t.db('admin');
    await assertFails(setDoc(productRef(db, 'black forest'), makeProduct()));
    await assertFails(setDoc(productRef(db), makeProduct({ uid: ACTORS.smPtb.uid })));
    const { sortOrder, ...missing } = makeProduct();
    await assertFails(setDoc(productRef(db), missing));
    await assertFails(setDoc(productRef(db), { ...makeProduct(), unit: 'G' }));
  });

  it('denies a suggestion from a role without catalog.suggest (QA-034)', async () => {
    await assertFails(setDoc(productRef(t.db('cashierPtb')), suggestion({ uid: ACTORS.cashierPtb.uid })));
    await t.withPermissions('cashierPtb', ['catalog.suggest']);
    await assertSucceeds(setDoc(productRef(t.db('cashierPtb')), suggestion({ uid: ACTORS.cashierPtb.uid })));
  });

  it('denies a disabled user and an anonymous user', async () => {
    await assertFails(setDoc(productRef(t.db('disabled')), suggestion({ uid: ACTORS.disabled.uid })));
    await assertFails(setDoc(productRef(t.db('anonymous')), makeProduct()));
  });
});

describe('#11 products: update and delete', () => {
  it('lets catalog.manage change a price, approve and deactivate', async () => {
    await arrangeProduct({ status: 'PENDING', price: null, scope: LOC.PTB });
    const ref = productRef(t.db('admin'));
    await assertSucceeds(updateDoc(ref, approval()));
    await assertSucceeds(updateDoc(ref, { price: 47000, updatedAt: serverTimestamp() }));
    await assertSucceeds(updateDoc(ref, { status: 'INACTIVE', updatedAt: serverTimestamp() }));
  });

  it('denies an SM editing any product, their own suggestion included', async () => {
    await arrangeProduct({ status: 'PENDING', price: null, scope: LOC.PTB, createdBy: ACTORS.smPtb.uid });
    await assertFails(updateDoc(productRef(t.db('smPtb')), { proposedPrice: 40000, updatedAt: serverTimestamp() }));
  });

  it('denies changing createdBy or createdAt, and a client updatedAt', async () => {
    await arrangeProduct();
    const ref = productRef(t.db('admin'));
    await assertFails(updateDoc(ref, { createdBy: ACTORS.smPtb.uid, updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(ref, { createdAt: serverTimestamp(), updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(ref, { price: 1, updatedAt: new Date() }));
  });

  it('denies deleting a product', async () => {
    await arrangeProduct();
    await assertFails(deleteDoc(productRef(t.db('admin'))));
  });
});

describe('#11 products: approve and decline a suggestion (D-038)', () => {
  it('lets catalog.manage approve a PENDING product with the reviewer and the server time', async () => {
    await arrangePending();
    await assertSucceeds(updateDoc(productRef(t.db('admin')), approval()));
  });

  it('lets catalog.manage decline a PENDING product with a note, leaving it INACTIVE and unpriced', async () => {
    await arrangePending();
    await assertSucceeds(updateDoc(productRef(t.db('admin')), decline()));
    let after;
    await t.arrange(async (db) => {
      after = (await getDoc(productRef(db))).data();
    });
    expect(after).toMatchObject({
      status: 'INACTIVE',
      price: null,
      reviewedBy: ACTORS.admin.uid,
      reviewNote: 'Too close to the Black Forest',
    });
  });

  it('accepts a note of 1 and of 200 characters, and denies an empty, a 201-character, an untrimmed and a null one', async () => {
    const notes = [['x', true], ['x'.repeat(200), true], ['', false], ['x'.repeat(201), false], [' padded', false], ['padded ', false], [null, false]];
    for (const [note, ok] of notes) {
      await t.env.clearFirestore();
      await seedFixtures(t.env);
      await arrangePending();
      const run = updateDoc(productRef(t.db('admin')), decline({ reviewNote: note }));
      await (ok ? assertSucceeds(run) : assertFails(run));
    }
  });

  it('denies an approval or decline that skips the reviewer or the server time', async () => {
    await arrangePending();
    const ref = productRef(t.db('admin'));
    await assertFails(updateDoc(ref, approval({ reviewedBy: ACTORS.smPtb.uid })));
    await assertFails(updateDoc(ref, approval({ reviewedAt: new Date() })));
    const { reviewedAt, ...noTime } = approval();
    await assertFails(updateDoc(ref, noTime));
    await assertFails(updateDoc(ref, decline({ reviewedBy: ACTORS.smPtb.uid })));
    await assertFails(updateDoc(ref, decline({ reviewedAt: new Date() })));
    const { reviewNote, ...noNote } = decline();
    await assertFails(updateDoc(ref, noNote));
  });

  it('denies every other edit to a PENDING product, even from the Admin', async () => {
    await arrangePending();
    const ref = productRef(t.db('admin'));
    // The old reject path, a price on a still-pending product, a rename, an
    // approval that also edits something else, and a decline that prices it.
    await assertFails(updateDoc(ref, { status: 'INACTIVE', updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(ref, { price: 45000, updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(ref, { name: 'Renamed', updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(ref, approval({ name: 'Renamed' })));
    await assertFails(updateDoc(ref, decline({ price: 45000 })));
    await assertFails(updateDoc(ref, approval({ status: 'PENDING' })));
    await assertFails(updateDoc(ref, decline({ status: 'ACTIVE' })));
  });

  it('denies an approval with no price, a zero price or a non-integer price', async () => {
    await arrangePending();
    const ref = productRef(t.db('admin'));
    await assertFails(updateDoc(ref, approval({ price: null })));
    await assertFails(updateDoc(ref, approval({ price: 0 })));
    await assertFails(updateDoc(ref, approval({ price: 450.5 })));
  });

  it('denies a Store Manager approving or declining, and re-approving a declined suggestion', async () => {
    await arrangePending();
    const sm = productRef(t.db('smPtb'));
    await assertFails(updateDoc(sm, approval({ reviewedBy: ACTORS.smPtb.uid })));
    await assertFails(updateDoc(sm, decline({ reviewedBy: ACTORS.smPtb.uid })));
    await t.env.clearFirestore();
    await seedFixtures(t.env);
    await arrangeProduct({
      status: 'INACTIVE',
      price: null,
      proposedPrice: 45000,
      scope: LOC.PTB,
      createdBy: ACTORS.smPtb.uid,
      reviewedBy: ACTORS.admin.uid,
      reviewNote: 'No',
      reviewedAt: new Date(),
    });
    await assertFails(updateDoc(sm, approval({ reviewedBy: ACTORS.smPtb.uid })));
    await assertFails(updateDoc(sm, { status: 'PENDING', updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(sm, { status: 'ACTIVE', price: 45000, updatedAt: serverTimestamp() }));
  });

  it('keeps the review fields out of ordinary edits, and out of every create', async () => {
    await arrangeProduct({ reviewedBy: ACTORS.admin.uid, reviewedAt: new Date() });
    const ref = productRef(t.db('admin'));
    await assertSucceeds(updateDoc(ref, { price: 47000, updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(ref, { reviewNote: 'edited', updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(ref, { reviewedBy: ACTORS.smPtb.uid, updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(ref, { reviewedAt: serverTimestamp(), updatedAt: serverTimestamp() }));
    await assertFails(setDoc(productRef(t.db('admin'), 'p2'), { ...makeProduct(), reviewedBy: ACTORS.admin.uid }));
    await assertFails(setDoc(productRef(t.db('smPtb'), 'p3'), { ...suggestion(), reviewedAt: serverTimestamp() }));
  });

  it('lets the Admin edit a declined product again (a later change of mind)', async () => {
    await arrangePending();
    await assertSucceeds(updateDoc(productRef(t.db('admin')), decline()));
    await assertSucceeds(
      updateDoc(productRef(t.db('admin')), { status: 'ACTIVE', price: 45000, updatedAt: serverTimestamp() }),
    );
  });

  it("reads the Store Manager's own suggestions in any status, as the app's query does (BE-16)", async () => {
    await t.arrange(async (db) => {
      const at = { createdAt: new Date(), updatedAt: new Date() };
      await setDoc(productRef(db, 'mine1'), { ...suggestion(), ...at });
      await setDoc(productRef(db, 'mine2'), { ...suggestion({ status: 'INACTIVE' }), reviewedBy: ACTORS.admin.uid, reviewNote: 'No', reviewedAt: new Date(), ...at });
      await setDoc(productRef(db, 'other'), { ...suggestion({ uid: ACTORS.cashierPtb.uid }), ...at });
      await setDoc(productRef(db, 'elsewhere'), { ...suggestion({ scope: LOC.MNJ }), ...at });
    });
    const mine = query(
      collection(t.db('smPtb'), 'products'),
      where('createdBy', '==', ACTORS.smPtb.uid),
      where('scope', '==', LOC.PTB),
    );
    const snap = await assertSucceeds(getDocs(mine));
    expect(snap.docs.map((d) => d.id).sort()).toEqual(['mine1', 'mine2']);
  });
});

describe('#11 products: read', () => {
  it('denies a role without catalog.view (QA-034)', async () => {
    await arrangeProduct();
    await t.withPermissions('cashierPtb', ['bill.create']);
    await assertFails(getDoc(productRef(t.db('cashierPtb'))));
  });

  it('lets catalog.view read products', async () => {
    await arrangeProduct();
    await assertSucceeds(getDoc(productRef(t.db('smMnj'))));
    await assertSucceeds(getDocs(collection(t.db('smPtb'), 'products')));
  });

  it('denies a disabled user, a user without a profile and an anonymous user', async () => {
    await arrangeProduct();
    await assertFails(getDoc(productRef(t.db('disabled'))));
    await assertFails(getDoc(productRef(t.db('noProfile'))));
    await assertFails(getDoc(productRef(t.db('anonymous'))));
  });
});

describe('raw materials', () => {
  const material = (uid = ACTORS.smPtb.uid, fields = {}) => ({ name: 'Flour', unit: 'G', active: true, createdBy: uid, ...fields });

  it('lets rawMaterial.create add one', async () => {
    await assertSucceeds(setDoc(materialRef(t.db('smPtb')), material()));
  });

  it('denies a role without rawMaterial.create (QA-034)', async () => {
    await assertFails(setDoc(materialRef(t.db('cashierPtb')), material(ACTORS.cashierPtb.uid)));
  });

  it('denies an inactive or bad-unit material, createdBy other than the caller, and extra fields', async () => {
    const db = t.db('smPtb');
    await assertFails(setDoc(materialRef(db), material(undefined, { active: false })));
    await assertFails(setDoc(materialRef(db), material(undefined, { unit: 'KG' })));
    await assertFails(setDoc(materialRef(db), material(ACTORS.admin.uid)));
    await assertFails(setDoc(materialRef(db), material(undefined, { price: 1 })));
  });

  it('lets catalog.manage rename and deactivate, but not change the unit', async () => {
    await t.arrange((db) => setDoc(materialRef(db), material()));
    const ref = materialRef(t.db('admin'));
    await assertSucceeds(updateDoc(ref, { name: 'Maida' }));
    await assertSucceeds(updateDoc(ref, { active: false }));
    await assertFails(updateDoc(ref, { unit: 'ML' }));
  });

  it('denies an SM editing, and anyone deleting', async () => {
    await t.arrange((db) => setDoc(materialRef(db), material()));
    await assertFails(updateDoc(materialRef(t.db('smPtb')), { name: 'Maida' }));
    await assertFails(deleteDoc(materialRef(t.db('admin'))));
  });

  it('lets catalog.view read, and denies a disabled user', async () => {
    await t.arrange((db) => setDoc(materialRef(db), material()));
    await assertSucceeds(getDocs(collection(t.db('smMnj'), 'rawMaterials')));
    await assertFails(getDoc(materialRef(t.db('disabled'))));
  });

  it('needs catalog.view: a role with only it reads, one with rawMaterial.create and no catalog.view does not (QA-042)', async () => {
    await t.arrange((db) => setDoc(materialRef(db), material()));
    await t.withPermissions('smPtb', ['catalog.view']);
    await assertSucceeds(getDoc(materialRef(t.db('smPtb'))));
    await assertSucceeds(getDocs(collection(t.db('smPtb'), 'rawMaterials')));
    await t.withPermissions('smPtb', ['rawMaterial.create', 'stock.move', 'report.own']);
    await assertFails(getDoc(materialRef(t.db('smPtb'))));
    await assertFails(getDocs(collection(t.db('smPtb'), 'rawMaterials')));
  });
});
