// BE-1: proves the harness works. The fixtures match the permission contract,
// seeding runs, and each actor gets its own rules-enforced client. The rule
// suites themselves start in BE-2.

import { describe, expect, it } from 'vitest';
import { collection, doc, getDoc, getDocs, setDoc } from 'firebase/firestore';
import { ACTORS, LOC, PERMS, ROLE, ROLES, TEST_PIN, hashPin } from './support/fixtures.js';
import { assertFails, useRulesEnv } from './support/env.js';

describe('fixtures', () => {
  it('read every permission from packages/core', () => {
    expect(PERMS.all).toHaveLength(17);
    expect(new Set(PERMS.all).size).toBe(17);
  });

  it('give Admin every permission and all locations', () => {
    expect(ROLES[ROLE.ADMIN].permissions).toEqual(PERMS.all);
    expect(ROLES[ROLE.ADMIN].allLocations).toBe(true);
  });

  it('match the Store Manager column of the role matrix', () => {
    const sm = ROLES[ROLE.STORE_MANAGER];
    expect(sm.allLocations).toBe(false);
    expect([...sm.permissions].sort()).toEqual(
      [
        'bill.cancel',
        'bill.create',
        'catalog.suggest',
        'catalog.view',
        'device.register',
        'rawMaterial.create',
        'report.own',
        'return.create',
        'stock.adjust',
        'stock.move',
        'stock.threshold',
      ].sort(),
    );
  });

  it('cover Admin, SM@PTB, SM@MNJ, a disabled user and an anonymous user', () => {
    expect(ACTORS.admin.doc).toMatchObject({ roleId: ROLE.ADMIN, locationId: null, active: true });
    expect(ACTORS.smPtb.doc).toMatchObject({ roleId: ROLE.STORE_MANAGER, locationId: LOC.PTB, active: true });
    expect(ACTORS.smMnj.doc).toMatchObject({ roleId: ROLE.STORE_MANAGER, locationId: LOC.MNJ, active: true });
    expect(ACTORS.disabled.doc).toMatchObject({ active: false });
    expect(ACTORS.anonymous.uid).toBeNull();
  });

  it('hash the override PIN as salt$hash in base64', () => {
    const value = hashPin(TEST_PIN, Buffer.from('salt'));
    const [salt, hash] = value.split('$');
    expect(Buffer.from(salt, 'base64').toString()).toBe('salt');
    expect(Buffer.from(hash, 'base64')).toHaveLength(32);
  });
});

describe('emulator harness', () => {
  const t = useRulesEnv();

  it('seeds roles, locations and users', async () => {
    let counts;
    await t.arrange(async (db) => {
      const [roles, locations, users] = await Promise.all(
        ['roles', 'locations', 'users'].map((c) => getDocs(collection(db, c))),
      );
      counts = [roles.size, locations.size, users.size];
    });
    expect(counts).toEqual([2, 2, 4]);
  });

  it('starts every test from a clean database', async () => {
    await t.arrange((db) => setDoc(doc(db, 'scratch/leftover'), { x: 1 }));
    // The next test checks the doc is gone; here we only check it was written.
    let exists;
    await t.arrange(async (db) => {
      exists = (await getDoc(doc(db, 'scratch/leftover'))).exists();
    });
    expect(exists).toBe(true);
  });

  it('cleared the doc written by the previous test', async () => {
    let exists;
    await t.arrange(async (db) => {
      exists = (await getDoc(doc(db, 'scratch/leftover'))).exists();
    });
    expect(exists).toBe(false);
  });

  it('denies an anonymous read (default deny)', async () => {
    await assertFails(getDoc(doc(t.db('anonymous'), 'users', ACTORS.admin.uid)));
  });

  it('denies a disabled user reading their own doc', async () => {
    const { uid } = ACTORS.disabled;
    await assertFails(getDoc(doc(t.db('disabled'), 'users', uid)));
  });
});
