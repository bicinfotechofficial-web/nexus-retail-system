// Rules test environment: connects to the running Firestore emulator, loads
// firestore.rules from disk, and seeds the fixtures before every test.
//
// Usage in a test file:
//
//   const t = useRulesEnv();
//   it('...', async () => {
//     await assertFails(getDoc(doc(t.db('smPtb'), 'users/admin')));
//   });

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { afterAll, beforeAll, beforeEach } from 'vitest';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { doc, serverTimestamp, setDoc } from 'firebase/firestore';
import { ACTORS, LOCATIONS, ROLES } from './fixtures.js';

export { assertFails, assertSucceeds };

// Local runs and tests use the demo project only (docs/SETUP-FIREBASE.md §2).
export const PROJECT_ID = 'demo-caramel-cottage';

const FIREBASE_DIR = fileURLToPath(new URL('../../', import.meta.url));

/** Emulator address: FIRESTORE_EMULATOR_HOST if set, else firebase.json. */
export function emulatorAddress() {
  const fromEnv = process.env.FIRESTORE_EMULATOR_HOST;
  if (fromEnv) {
    const i = fromEnv.lastIndexOf(':');
    return { host: fromEnv.slice(0, i), port: Number(fromEnv.slice(i + 1)) };
  }
  const config = JSON.parse(
    readFileSync(`${FIREBASE_DIR}firebase.json`, 'utf8'),
  );
  const { host, port } = config.emulators.firestore;
  return { host, port };
}

export function loadRules() {
  return readFileSync(`${FIREBASE_DIR}firestore.rules`, 'utf8');
}

export async function createRulesEnv() {
  const { host, port } = emulatorAddress();
  try {
    return await initializeTestEnvironment({
      projectId: PROJECT_ID,
      firestore: { host, port, rules: loadRules() },
    });
  } catch (e) {
    throw new Error(
      `Could not reach the Firestore emulator at ${host}:${port}. ` +
        'Start it with `firebase emulators:start` in firebase/, or run ' +
        '`npm run test:emulator`.\n' +
        `Cause: ${e.message}`,
    );
  }
}

/** Writes roles, locations and users with the rules turned off. */
export async function seedFixtures(env) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    const writes = [];
    for (const [id, role] of Object.entries(ROLES)) {
      writes.push(setDoc(doc(db, 'roles', id), role));
    }
    for (const [id, loc] of Object.entries(LOCATIONS)) {
      writes.push(setDoc(doc(db, 'locations', id), loc));
    }
    for (const actor of Object.values(ACTORS)) {
      if (!actor.doc) continue;
      writes.push(
        setDoc(doc(db, 'users', actor.uid), {
          ...actor.doc,
          createdAt: serverTimestamp(),
          createdBy: 'seed',
        }),
      );
    }
    await Promise.all(writes);
  });
}

/** Firestore client acting as one of the ACTORS, with the rules on. */
export function dbAs(env, actorKey) {
  const actor = ACTORS[actorKey];
  if (!actor) throw new Error(`Unknown actor: ${actorKey}`);
  const ctx = actor.uid
    ? env.authenticatedContext(actor.uid, {
        email: actor.doc?.email ?? `${actor.uid}@example.test`,
      })
    : env.unauthenticatedContext();
  return ctx.firestore();
}

/**
 * Runs `fn(db)` with the rules turned off, for arranging state a test needs
 * (e.g. an existing bill) without going through the rules under test.
 */
export async function arrange(env, fn) {
  await env.withSecurityRulesDisabled((ctx) => fn(ctx.firestore()));
}

/**
 * Registers the suite hooks: one environment per file, and a clean,
 * freshly seeded database before every test.
 */
export function useRulesEnv() {
  const t = {
    env: null,
    db: (actorKey) => dbAs(t.env, actorKey),
    arrange: (fn) => arrange(t.env, fn),
  };
  beforeAll(async () => {
    t.env = await createRulesEnv();
  });
  beforeEach(async () => {
    await t.env.clearFirestore();
    await seedFixtures(t.env);
  });
  afterAll(async () => {
    await t.env?.cleanup();
  });
  return t;
}
