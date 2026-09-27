// BE-14: the seed script (scripts/seed.mjs), run as a command against the
// Firestore and Auth emulators, in its own demo project so it never mixes
// with the rules suite's data.
//
// Done when "Running it twice changes nothing": the second run reports
// nothing to change, and every doc (content and update time) and the Auth
// account are exactly as the first run left them.

import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { fileURLToPath } from 'node:url';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { deleteApp, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { readLimits, readPermissions, verifyPin } from '../scripts/lib/core.js';
import { LOCATIONS, PRODUCTS, PROD_PROJECT, RAW_MATERIALS, resolveTarget } from '../scripts/seed.mjs';

const run = promisify(execFile);
const SEED = fileURLToPath(new URL('../scripts/seed.mjs', import.meta.url));
const PROJECT = 'demo-caramel-cottage-seed';
const EMAIL = 'admin@example.test';
const PASSWORD = 'seed-test-password';
const PIN = '97531864';

const target = resolveTarget(['--project', PROJECT]);
const COLLECTIONS = ['roles', 'users', 'locations', 'products', 'rawMaterials'];

/** Runs the seed command; `env` adds to (or, with undefined, removes from) the inputs. */
async function seed(env = {}, args = ['--project', PROJECT]) {
  const inputs = { SEED_ADMIN_EMAIL: EMAIL, SEED_ADMIN_PASSWORD: PASSWORD, SEED_OVERRIDE_PIN: PIN, ...env };
  const full = { ...process.env, ...target.env, ...inputs };
  for (const [k, v] of Object.entries(inputs)) if (v === undefined) delete full[k];
  const { stdout } = await run(process.execPath, [SEED, ...args], { env: full, timeout: 60_000 });
  return stdout;
}

let app;
let db;
let auth;

async function clearEmulators() {
  const fs = target.env.FIRESTORE_EMULATOR_HOST;
  const au = target.env.FIREBASE_AUTH_EMULATOR_HOST;
  await fetch(`http://${fs}/emulator/v1/projects/${PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  await fetch(`http://${au}/emulator/v1/projects/${PROJECT}/accounts`, { method: 'DELETE' });
}

/** Every seeded doc with its update time, and the Auth accounts. */
async function snapshot() {
  const docs = {};
  for (const c of COLLECTIONS) {
    for (const d of (await db.collection(c).get()).docs) {
      docs[d.ref.path] = { updateTime: d.updateTime.toMillis(), data: JSON.stringify(d.data()) };
    }
  }
  const users = (await auth.listUsers()).users.map((u) => ({
    uid: u.uid,
    email: u.email,
    passwordHash: u.passwordHash,
    passwordSalt: u.passwordSalt,
    tokensValidAfterTime: u.tokensValidAfterTime,
    created: u.metadata.creationTime,
  }));
  return { docs, users };
}

beforeAll(async () => {
  // The Admin SDK reads the emulator hosts from the environment.
  Object.assign(process.env, target.env);
  app = initializeApp({ projectId: PROJECT }, 'seed-test');
  db = getFirestore(app);
  auth = getAuth(app);
});

beforeEach(clearEmulators);

afterAll(async () => {
  await clearEmulators();
  if (app) await deleteApp(app);
});

describe('BE-14 seed script', () => {
  it('seeds roles, the Admin, both locations, 10 products and 5 raw materials', async () => {
    const out = await seed();
    expect(out).toMatch(/Done: 21 created or updated\./);

    const perms = readPermissions();
    expect((await db.doc(`roles/${perms.adminId}`).get()).data()).toEqual({
      name: 'Admin',
      permissions: perms.adminPermissions,
      allLocations: true,
    });
    expect((await db.doc(`roles/${perms.storeManagerId}`).get()).data()).toEqual({
      name: 'Store Manager',
      permissions: perms.storeManagerPermissions,
      allLocations: false,
    });

    const admin = await auth.getUserByEmail(EMAIL);
    const user = (await db.doc(`users/${admin.uid}`).get()).data();
    expect(user).toMatchObject({ name: 'Admin', email: EMAIL, roleId: perms.adminId, locationId: null, active: true });

    const minPin = readLimits().minOverridePinDigits;
    expect(PIN.length).toBeGreaterThanOrEqual(minPin);
    for (const { code, name } of LOCATIONS) {
      const loc = (await db.doc(`locations/${code}`).get()).data();
      expect(loc).toMatchObject({
        code,
        name,
        nextDeviceNo: 0,
        offlineLimitHours: 5,
        overrideExtensionHours: 2,
        maxDiscountPct: null,
        gstin: null,
        active: true,
      });
      // PBKDF2-SHA256, 100k iterations, salt$hash in base64 (02-DATA-MODEL).
      const [salt, hash] = loc.overridePinHash.split('$');
      expect(Buffer.from(salt, 'base64')).toHaveLength(16);
      expect(Buffer.from(hash, 'base64')).toHaveLength(32);
      expect(verifyPin(PIN, loc.overridePinHash)).toBe(true);
      expect(verifyPin('12345678', loc.overridePinHash)).toBe(false);
    }
    const [ptb, mnj] = await Promise.all(LOCATIONS.map(({ code }) => db.doc(`locations/${code}`).get()));
    expect(ptb.data().overridePinHash).not.toBe(mnj.data().overridePinHash);

    const products = (await db.collection('products').get()).docs;
    expect(products.map((d) => d.id).sort()).toEqual(PRODUCTS.map(([id]) => id).sort());
    for (const d of products) {
      const p = d.data();
      expect(p).toMatchObject({ status: 'ACTIVE', scope: 'GLOBAL', unit: 'PCS', proposedPrice: null });
      expect(Number.isInteger(p.price) && p.price > 0 && p.price % 100 === 0).toBe(true);
      expect(['Cakes', 'Pastries']).toContain(p.category);
    }

    const materials = (await db.collection('rawMaterials').get()).docs;
    expect(materials).toHaveLength(RAW_MATERIALS.length);
    expect(new Set(materials.map((d) => d.data().unit))).toEqual(new Set(['G', 'ML', 'PCS']));
  });

  it('changes nothing when run twice, and needs no password or PIN the second time', async () => {
    await seed();
    const before = await snapshot();
    expect(Object.keys(before.docs)).toHaveLength(2 + 1 + 2 + 10 + 5);
    expect(before.users).toHaveLength(1);

    const out = await seed({ SEED_ADMIN_PASSWORD: undefined, SEED_OVERRIDE_PIN: undefined });
    expect(out).toMatch(/Done: nothing to change\./);
    expect(out).not.toMatch(/^(created|updated) /m);
    expect(await snapshot()).toEqual(before);
  });

  it('never overwrites what an Admin changed since, but puts roles back in line with packages/core', async () => {
    await seed();
    await db.doc('locations/PTB').update({ phone: '0000000000', nextDeviceNo: 3 });
    await db.doc('products/chocolate-pastry').update({ price: 9500 });
    await db.doc('roles/STORE_MANAGER').update({ permissions: ['catalog.view'] });

    const out = await seed();
    expect(out).toMatch(/^updated +roles\/STORE_MANAGER$/m);
    expect((await db.doc('locations/PTB').get()).data()).toMatchObject({ phone: '0000000000', nextDeviceNo: 3 });
    expect((await db.doc('products/chocolate-pastry').get()).data().price).toBe(9500);
    expect((await db.doc('roles/STORE_MANAGER').get()).data().permissions).toEqual(readPermissions().storeManagerPermissions);
  });

  it('rejects a short PIN and a short password', async () => {
    await expect(seed({ SEED_OVERRIDE_PIN: '1234567' })).rejects.toThrow(/at least 8 digits/);
    await clearEmulators();
    await expect(seed({ SEED_ADMIN_PASSWORD: 'short' })).rejects.toThrow(/at least 8 characters/);
  });

  it('only touches production with --project caramel-cottage-retail --yes-really, and never through an emulator', () => {
    expect(resolveTarget([], {})).toMatchObject({ project: 'demo-caramel-cottage', emulator: true });
    expect(() => resolveTarget(['--project', 'some-other-project'], {})).toThrow(/Refusing project/);
    expect(() => resolveTarget(['--project', PROD_PROJECT], {})).toThrow(/--yes-really/);
    expect(() => resolveTarget(['--yes-really'], {})).not.toThrow();
    expect(() =>
      resolveTarget(['--project', PROD_PROJECT, '--yes-really'], { FIRESTORE_EMULATOR_HOST: '127.0.0.1:8080' }),
    ).toThrow(/Refusing to seed production/);
    expect(resolveTarget([`--project=${PROD_PROJECT}`, '--yes-really'], {})).toEqual({
      project: PROD_PROJECT,
      emulator: false,
      env: {},
    });
  });
});
