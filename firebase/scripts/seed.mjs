#!/usr/bin/env node
// Seed script (BE-14): roles, the first Admin, locations PTB and MNJ, a
// sample catalog and raw materials. See firebase/README.md "Seeding".
//
//   npm run seed                                   the emulator, demo-caramel-cottage
//   npm run seed -- --project demo-<anything>      another emulator project
//   npm run seed -- --project caramel-cottage-retail --yes-really   production
//
// Idempotent: it creates what is missing and leaves everything that exists
// alone, so a second run changes nothing, and an Admin's later edits to a
// location, product or raw material are never overwritten. The one
// exception is roles, which only this script writes (02-DATA-MODEL): a role
// whose permissions differ from packages/core is brought back in line.
//
// Inputs come from the environment, or a prompt when they're needed and
// missing (never hard-coded):
//   SEED_ADMIN_EMAIL     the Admin's sign-in email
//   SEED_ADMIN_PASSWORD  only used when the Admin's Auth account is created
//   SEED_OVERRIDE_PIN    only used when a location is created: its offline
//                        override PIN, at least Limits.minOverridePinDigits
//                        digits (the same PIN for both; change it per store
//                        in the admin console)

import { readFileSync } from 'node:fs';
import { createInterface } from 'node:readline/promises';
import { fileURLToPath } from 'node:url';
import { deleteApp, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { hashPin, readLimits, readPermissions } from './lib/core.js';

export const DEMO_PROJECT = 'demo-caramel-cottage';
export const PROD_PROJECT = 'caramel-cottage-retail';

const SEED = 'seed';

// ---- What gets seeded ------------------------------------------------------

export function roles() {
  const p = readPermissions();
  return {
    [p.adminId]: { name: 'Admin', permissions: p.adminPermissions, allLocations: true },
    [p.storeManagerId]: { name: 'Store Manager', permissions: p.storeManagerPermissions, allLocations: false },
  };
}

export const LOCATIONS = [
  { code: 'PTB', name: 'Caramel Cottage Pattambi', address: 'Pattambi, Palakkad, Kerala' },
  { code: 'MNJ', name: 'Caramel Cottage Manjeri', address: 'Manjeri, Malappuram, Kerala' },
];

/** [id, name, category, price in paise] */
export const PRODUCTS = [
  ['black-forest-500g', 'Black Forest 500 g', 'Cakes', 45000],
  ['black-forest-1kg', 'Black Forest 1 kg', 'Cakes', 85000],
  ['white-forest-1kg', 'White Forest 1 kg', 'Cakes', 85000],
  ['red-velvet-500g', 'Red Velvet 500 g', 'Cakes', 60000],
  ['chocolate-truffle-1kg', 'Chocolate Truffle 1 kg', 'Cakes', 110000],
  ['pineapple-500g', 'Pineapple 500 g', 'Cakes', 40000],
  ['chocolate-pastry', 'Chocolate Pastry', 'Pastries', 9000],
  ['butterscotch-pastry', 'Butterscotch Pastry', 'Pastries', 8000],
  ['red-velvet-pastry', 'Red Velvet Pastry', 'Pastries', 10000],
  ['blueberry-pastry', 'Blueberry Pastry', 'Pastries', 11000],
];

/** [id, name, unit] */
export const RAW_MATERIALS = [
  ['maida', 'Maida', 'G'],
  ['sugar', 'Sugar', 'G'],
  ['fresh-cream', 'Fresh Cream', 'ML'],
  ['eggs', 'Eggs', 'PCS'],
  ['cocoa-powder', 'Cocoa Powder', 'G'],
];

function locationDoc({ code, name, address }, pin) {
  return {
    code,
    name,
    address,
    phone: '',
    gstin: null,
    offlineLimitHours: 5,
    overridePinHash: hashPin(pin),
    overrideExtensionHours: 2,
    maxDiscountPct: null,
    receiptFooter: 'Thank you! Visit caramelcottage.in',
    // The last device number handed out; 0 for a new location (D-004).
    nextDeviceNo: 0,
    active: true,
  };
}

function productDoc([, name, category, price], i) {
  return {
    name,
    category,
    price,
    proposedPrice: null,
    unit: 'PCS',
    gstRate: null,
    scope: 'GLOBAL',
    status: 'ACTIVE',
    recipe: null,
    sortOrder: (i + 1) * 10,
    createdBy: SEED,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };
}

// ---- Seeding ---------------------------------------------------------------

/** JSON with object keys sorted, so stored maps compare by content, not key order. */
const canonical = (v) =>
  JSON.stringify(v, (_, x) =>
    x && typeof x === 'object' && !Array.isArray(x) ? Object.fromEntries(Object.entries(x).sort(([a], [b]) => a.localeCompare(b))) : x,
  );
const sameJson = (a, b) => canonical(a) === canonical(b);

/**
 * Creates the doc unless it exists, and builds `data` (a value, or an async
 * function) only when it doesn't. Returns 'created' or 'unchanged'.
 */
async function createIfMissing(ref, data) {
  if ((await ref.get()).exists) return 'unchanged';
  try {
    await ref.create(typeof data === 'function' ? await data() : data);
    return 'created';
  } catch (e) {
    if (e.code === 6 /* ALREADY_EXISTS */) return 'unchanged';
    throw e;
  }
}

/**
 * Seeds `db` and `auth` (Admin SDK instances). `inputs` has async getters
 * `email()`, `password()` and `pin()`, each called only when needed.
 * Returns `{ path: 'created' | 'updated' | 'unchanged' }`.
 */
export async function seed({ db, auth, inputs }) {
  const report = {};

  for (const [id, role] of Object.entries(roles())) {
    const ref = db.doc(`roles/${id}`);
    const snap = await ref.get();
    if (snap.exists && sameJson(snap.data(), role)) {
      report[ref.path] = 'unchanged';
    } else {
      await ref.set(role);
      report[ref.path] = snap.exists ? 'updated' : 'created';
    }
  }

  const email = await inputs.email();
  let admin;
  try {
    admin = await auth.getUserByEmail(email);
    report[`auth:${email}`] = 'unchanged';
  } catch (e) {
    if (e.code !== 'auth/user-not-found') throw e;
    admin = await auth.createUser({ email, password: await inputs.password(), displayName: 'Admin' });
    report[`auth:${email}`] = 'created';
  }
  const { adminId } = readPermissions();
  const userRef = db.doc(`users/${admin.uid}`);
  report[userRef.path] = await createIfMissing(userRef, {
    name: 'Admin',
    email,
    roleId: adminId,
    locationId: null,
    active: true,
    createdAt: FieldValue.serverTimestamp(),
    createdBy: SEED,
  });

  for (const loc of LOCATIONS) {
    const ref = db.doc(`locations/${loc.code}`);
    report[ref.path] = await createIfMissing(ref, async () => locationDoc(loc, await inputs.pin()));
  }

  for (const [i, product] of PRODUCTS.entries()) {
    const ref = db.doc(`products/${product[0]}`);
    report[ref.path] = await createIfMissing(ref, productDoc(product, i));
  }

  for (const [id, name, unit] of RAW_MATERIALS) {
    const ref = db.doc(`rawMaterials/${id}`);
    report[ref.path] = await createIfMissing(ref, { name, unit, active: true, createdBy: SEED });
  }

  return report;
}

// ---- Command line ----------------------------------------------------------

const FIREBASE_JSON = fileURLToPath(new URL('../firebase.json', import.meta.url));

/** Which project, and whether it's the emulator. Throws on anything unsafe. */
export function resolveTarget(argv, env = process.env) {
  const args = [...argv];
  let project = DEMO_PROJECT;
  let yesReally = false;
  while (args.length) {
    const a = args.shift();
    if (a === '--project') project = args.shift();
    else if (a.startsWith('--project=')) project = a.slice('--project='.length);
    else if (a === '--yes-really') yesReally = true;
    else throw new Error(`Unknown argument: ${a}`);
  }
  if (!project) throw new Error('--project needs a project ID');

  if (project.startsWith('demo-')) {
    const { emulators } = JSON.parse(readFileSync(FIREBASE_JSON, 'utf8'));
    return {
      project,
      emulator: true,
      env: {
        FIRESTORE_EMULATOR_HOST: env.FIRESTORE_EMULATOR_HOST || `${emulators.firestore.host}:${emulators.firestore.port}`,
        FIREBASE_AUTH_EMULATOR_HOST: env.FIREBASE_AUTH_EMULATOR_HOST || `${emulators.auth.host}:${emulators.auth.port}`,
        // No credentials are needed, so don't look for a GCE metadata server.
        METADATA_SERVER_DETECTION: 'none',
      },
    };
  }
  if (project !== PROD_PROJECT) {
    throw new Error(`Refusing project ${project}: use a demo- project (the emulator) or ${PROD_PROJECT}.`);
  }
  if (!yesReally) {
    throw new Error(`Seeding production (${PROD_PROJECT}) needs --yes-really as well.`);
  }
  if (env.FIRESTORE_EMULATOR_HOST || env.FIREBASE_AUTH_EMULATOR_HOST) {
    throw new Error('Refusing to seed production with FIRESTORE_EMULATOR_HOST or FIREBASE_AUTH_EMULATOR_HOST set.');
  }
  return { project, emulator: false, env: {} };
}

/** Inputs from the environment, else a prompt (if there is a terminal). */
export function inputsFrom(env = process.env, { minPinDigits = readLimits().minOverridePinDigits } = {}) {
  let rl;
  const ask = async (question, name) => {
    if (!process.stdin.isTTY) throw new Error(`${name} is not set, and there is no terminal to ask on.`);
    rl ??= createInterface({ input: process.stdin, output: process.stdout });
    return (await rl.question(question)).trim();
  };
  const once = (fn) => {
    let p;
    return () => (p ??= fn());
  };
  return {
    email: once(async () => {
      const v = env.SEED_ADMIN_EMAIL || (await ask('Admin email: ', 'SEED_ADMIN_EMAIL'));
      if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(v)) throw new Error('SEED_ADMIN_EMAIL is not an email address.');
      return v;
    }),
    password: once(async () => {
      const v = env.SEED_ADMIN_PASSWORD || (await ask('Admin password (at least 8 characters): ', 'SEED_ADMIN_PASSWORD'));
      if (v.length < 8) throw new Error('SEED_ADMIN_PASSWORD must be at least 8 characters.');
      return v;
    }),
    pin: once(async () => {
      const v = env.SEED_OVERRIDE_PIN || (await ask(`Offline override PIN (${minPinDigits}+ digits): `, 'SEED_OVERRIDE_PIN'));
      if (!new RegExp(`^[0-9]{${minPinDigits},}$`).test(v)) {
        throw new Error(`SEED_OVERRIDE_PIN must be at least ${minPinDigits} digits.`);
      }
      return v;
    }),
    close: () => rl?.close(),
  };
}

async function main() {
  const target = resolveTarget(process.argv.slice(2));
  Object.assign(process.env, target.env);
  console.log(
    target.emulator
      ? `Seeding the emulator, project ${target.project} (Firestore ${target.env.FIRESTORE_EMULATOR_HOST}, Auth ${target.env.FIREBASE_AUTH_EMULATOR_HOST}).`
      : `Seeding PRODUCTION, project ${target.project}.`,
  );
  const app = initializeApp({ projectId: target.project }, `seed-${Date.now()}`);
  const inputs = inputsFrom();
  try {
    const report = await seed({ db: getFirestore(app), auth: getAuth(app), inputs });
    for (const [path, outcome] of Object.entries(report)) console.log(`${outcome.padEnd(9)} ${path}`);
    const created = Object.values(report).filter((o) => o !== 'unchanged').length;
    console.log(created ? `Done: ${created} created or updated.` : 'Done: nothing to change.');
  } finally {
    inputs.close();
    await deleteApp(app);
  }
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  main().catch((e) => {
    console.error(`Seed failed: ${e.message}`);
    process.exit(1);
  });
}
