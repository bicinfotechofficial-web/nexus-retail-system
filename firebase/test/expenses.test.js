// BE-5: expenses (04-PERMISSIONS #12).

import { describe, it } from 'vitest';
import { collection, deleteDoc, doc, getDoc, getDocs, query, serverTimestamp, setDoc, updateDoc, where } from 'firebase/firestore';
import { ACTORS, LOC } from './support/fixtures.js';
import { makeExpense } from './support/builders.js';
import { assertFails, assertSucceeds, useRulesEnv } from './support/env.js';

const t = useRulesEnv();

const expenseRef = (db, id = 'e1') => doc(db, 'expenses', id);
const arrangeExpense = () =>
  t.arrange((db) => setDoc(expenseRef(db), { ...makeExpense(), createdAt: new Date(), updatedAt: new Date() }));

describe('#12 expenses', () => {
  it('lets expense.manage create one for any location', async () => {
    await assertSucceeds(setDoc(expenseRef(t.db('admin')), makeExpense()));
    await assertSucceeds(setDoc(expenseRef(t.db('admin'), 'e2'), makeExpense({ locationId: LOC.MNJ, category: 'SALARY' })));
  });

  it('denies a Store Manager, who has no expense.manage', async () => {
    await assertFails(setDoc(expenseRef(t.db('smPtb')), makeExpense({ uid: ACTORS.smPtb.uid })));
  });

  it('denies an unknown location or category, a negative amount, a bad date and extra fields', async () => {
    const db = t.db('admin');
    await assertFails(setDoc(expenseRef(db), makeExpense({ locationId: 'XY1' })));
    await assertFails(setDoc(expenseRef(db), makeExpense({ category: 'PARTY' })));
    await assertFails(setDoc(expenseRef(db), makeExpense({ amount: -100 })));
    await assertFails(setDoc(expenseRef(db), { ...makeExpense(), date: '26/09/2026' }));
    await assertFails(setDoc(expenseRef(db), { ...makeExpense(), paidTo: 'x' }));
  });

  it('denies createdBy other than the caller, and client timestamps', async () => {
    const db = t.db('admin');
    await assertFails(setDoc(expenseRef(db), makeExpense({ uid: ACTORS.smPtb.uid })));
    await assertFails(setDoc(expenseRef(db), { ...makeExpense(), createdAt: new Date() }));
  });

  it('lets expense.manage edit an expense, but not createdBy or createdAt', async () => {
    await arrangeExpense();
    const ref = expenseRef(t.db('admin'));
    await assertSucceeds(updateDoc(ref, { amount: 1600000, updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(ref, { createdBy: ACTORS.smPtb.uid, updatedAt: serverTimestamp() }));
    await assertFails(updateDoc(ref, { createdAt: serverTimestamp(), updatedAt: serverTimestamp() }));
  });

  it('denies an SM editing, and anyone deleting', async () => {
    await arrangeExpense();
    await assertFails(updateDoc(expenseRef(t.db('smPtb')), { amount: 1, updatedAt: serverTimestamp() }));
    await assertFails(deleteDoc(expenseRef(t.db('admin'))));
  });

  it('lets expense.manage read and filter, and denies an SM', async () => {
    await arrangeExpense();
    await assertSucceeds(getDoc(expenseRef(t.db('admin'))));
    await assertSucceeds(getDocs(query(collection(t.db('admin'), 'expenses'), where('locationId', '==', LOC.PTB))));
    await assertFails(getDoc(expenseRef(t.db('smPtb'))));
    await assertFails(getDocs(collection(t.db('smPtb'), 'expenses')));
  });
});
