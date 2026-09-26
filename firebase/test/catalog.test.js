// BE-5: products and raw materials (04-PERMISSIONS #11).

import { describe, it } from 'vitest';
import { collection, deleteDoc, doc, getDoc, getDocs, serverTimestamp, setDoc, updateDoc } from 'firebase/firestore';
import { ACTORS, LOC } from './support/fixtures.js';
import { makeProduct } from './support/builders.js';
import { assertFails, assertSucceeds, useRulesEnv } from './support/env.js';

const t = useRulesEnv();

const productRef = (db, id = 'p1') => doc(db, 'products', id);
const materialRef = (db, id = 'flour') => doc(db, 'rawMaterials', id);
const suggestion = (overrides = {}) =>
  makeProduct({ status: 'PENDING', price: null, proposedPrice: 45000, scope: LOC.PTB, uid: ACTORS.smPtb.uid, ...overrides });
const arrangeProduct = (fields = {}) =>
  t.arrange((db) => setDoc(productRef(db), { ...makeProduct(), createdAt: new Date(), updatedAt: new Date(), ...fields }));

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

  it('denies a disabled user and an anonymous user', async () => {
    await assertFails(setDoc(productRef(t.db('disabled')), suggestion({ uid: ACTORS.disabled.uid })));
    await assertFails(setDoc(productRef(t.db('anonymous')), makeProduct()));
  });
});

describe('#11 products: update and delete', () => {
  it('lets catalog.manage change a price, approve and deactivate', async () => {
    await arrangeProduct({ status: 'PENDING', price: null, scope: LOC.PTB });
    const ref = productRef(t.db('admin'));
    await assertSucceeds(updateDoc(ref, { status: 'ACTIVE', price: 45000, updatedAt: serverTimestamp() }));
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

describe('#11 products: read', () => {
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
});
