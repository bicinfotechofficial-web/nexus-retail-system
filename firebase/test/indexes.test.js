// BE-7: firestore.indexes.json (02-DATA-MODEL "Indexes", plus what the
// repositories behind packages/data/lib/src/api/ query).
//
// The emulator serves every query without indexes, so it can't show that
// the file deploys. Instead:
// - the file passes the Firebase CLI's own index validation, the step
//   `firebase deploy --only firestore:indexes` runs before calling the API;
// - every index the repositories need is in it;
// - each of those queries runs on the emulator, with the rules on, as the
//   user who makes it in the apps.

import { execSync } from 'node:child_process';
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { homedir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import { collection, doc, getDocs, limit, orderBy, query, setDoc, startAfter, where } from 'firebase/firestore';
import { ACTORS, LOC } from './support/fixtures.js';
import { TODAY, makeAudit, makeBill, makeExpense, makeProduct, makeReturn, storedBill } from './support/builders.js';
import { assertSucceeds, useRulesEnv } from './support/env.js';

const t = useRulesEnv();

const INDEXES_JSON = fileURLToPath(new URL('../firestore.indexes.json', import.meta.url));
const spec = JSON.parse(readFileSync(INDEXES_JSON, 'utf8'));

/** firebase-tools' Firestore API module, from the CLI on PATH, the global npm root or the npx cache. */
function firebaseToolsApi() {
  const candidates = [];
  const sh = (cmd) => {
    try {
      return execSync(cmd, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
    } catch {
      return '';
    }
  };
  const bin = sh('command -v firebase');
  if (bin) candidates.push(join(dirname(sh(`readlink -f "${bin}"`) || bin), '..', '..'));
  const globalRoot = sh('npm root -g');
  if (globalRoot) candidates.push(join(globalRoot, 'firebase-tools'));
  const npx = join(homedir(), '.npm', '_npx');
  if (existsSync(npx)) {
    for (const d of readdirSync(npx)) candidates.push(join(npx, d, 'node_modules', 'firebase-tools'));
  }
  for (const dir of candidates) {
    const api = join(dir, 'lib', 'firestore', 'api.js');
    if (existsSync(api)) return createRequire(api)(api);
  }
  return null;
}

/** `collectionGroup: field DIR, field DIR` for each composite index. */
const described = spec.indexes.map(
  (i) => `${i.collectionGroup}: ${i.fields.map((f) => `${f.fieldPath} ${f.order === 'DESCENDING' ? 'DESC' : 'ASC'}`).join(', ')}`,
);

describe('BE-7 firestore.indexes.json', () => {
  it('passes the Firebase CLI validation that runs before a deploy', () => {
    const tools = firebaseToolsApi();
    expect(tools, 'firebase-tools not found: install the Firebase CLI (docs/SETUP-FIREBASE.md)').not.toBeNull();
    const api = new tools.FirestoreApi();
    expect(() => api.validateSpec(api.upgradeOldSpec(spec))).not.toThrow();
    // And it does reject a broken file, so the check above means something.
    const broken = { indexes: [{ collectionGroup: 'bills', queryScope: 'COLLECTION', fields: [{ fieldPath: 'x', order: 'UP' }] }] };
    expect(() => api.validateSpec(api.upgradeOldSpec(broken))).toThrow();
  });

  it('has every index 02-DATA-MODEL lists and the repositories need, and nothing twice', () => {
    expect(described.sort()).toEqual(
      [
        // 02-DATA-MODEL "Indexes"; bills of a day, newest first, and paged by date (BE-11).
        'bills: businessDate DESC, clientCreatedAt DESC',
        // Returns of a day (watchReturns) and of one bill (returnsForBill).
        'returns: businessDate DESC, clientCreatedAt DESC',
        'returns: billId ASC, clientCreatedAt ASC',
        // AuditQuery: by location, action or user, newest first, with a date
        // range on `at`. Two or three filters together are served by merging
        // these (Firestore index merging for equality filters).
        'auditLog: locationId ASC, at DESC',
        'auditLog: action ASC, at DESC',
        'auditLog: by ASC, at DESC',
        // watchExpenses for one location, by date.
        'expenses: locationId ASC, date DESC',
        // watchPending, and watchSellable (ACTIVE, scope GLOBAL or the location).
        'products: status ASC, sortOrder ASC',
        'products: status ASC, scope ASC, sortOrder ASC',
      ].sort(),
    );
    expect(spec.indexes.every((i) => i.queryScope === 'COLLECTION')).toBe(true);
  });
});

describe('BE-7 the indexed queries run under the rules', () => {
  const bills = (db, loc = LOC.PTB) => collection(db, 'locations', loc, 'bills');
  const returns = (db, loc = LOC.PTB) => collection(db, 'locations', loc, 'returns');

  it('bills of a day, newest first, and paged by date (Store Manager at the location)', async () => {
    await t.arrange((db) => setDoc(doc(bills(db), 'D01-000001'), storedBill(makeBill())));
    const db = t.db('smPtb');
    const day = await assertSucceeds(
      getDocs(query(bills(db), where('businessDate', '==', TODAY), orderBy('clientCreatedAt', 'desc'))),
    );
    expect(day.size).toBe(1);
    const page = query(bills(db), orderBy('businessDate', 'desc'), orderBy('clientCreatedAt', 'desc'), limit(50));
    const first = await assertSucceeds(getDocs(page));
    await assertSucceeds(getDocs(query(page, startAfter(first.docs[0]))));
  });

  it('returns of a day and of one bill (Store Manager at the location)', async () => {
    await t.arrange((db) => setDoc(doc(returns(db), 'D01-R000001'), { ...makeReturn(), serverCreatedAt: new Date() }));
    const db = t.db('smPtb');
    const day = await assertSucceeds(
      getDocs(query(returns(db), where('businessDate', '==', TODAY), orderBy('clientCreatedAt', 'desc'))),
    );
    expect(day.size).toBe(1);
    const forBill = await assertSucceeds(
      getDocs(query(returns(db), where('billId', '==', 'D01-000001'), orderBy('clientCreatedAt'))),
    );
    expect(forBill.size).toBe(1);
  });

  it('the audit log by location, action and user, newest first, in a date range (Admin)', async () => {
    await t.arrange((db) =>
      setDoc(
        doc(db, 'auditLog', 'PTB-D01-000001-X'),
        { ...makeAudit({ action: 'BILL_CANCEL', entityPath: 'locations/PTB/bills/D01-000001' }), at: new Date() },
      ),
    );
    const db = t.db('admin');
    const log = collection(db, 'auditLog');
    const from = new Date(Date.now() - 86_400_000);
    for (const filters of [
      [where('locationId', '==', LOC.PTB)],
      [where('action', '==', 'BILL_CANCEL')],
      [where('by', '==', ACTORS.smPtb.uid)],
      [where('locationId', '==', LOC.PTB), where('action', '==', 'BILL_CANCEL'), where('by', '==', ACTORS.smPtb.uid)],
    ]) {
      const snap = await assertSucceeds(
        getDocs(query(log, ...filters, where('at', '>=', from), where('at', '<=', new Date()), orderBy('at', 'desc'), limit(100))),
      );
      expect(snap.size).toBe(1);
    }
  });

  it('expenses of one location by date (Admin)', async () => {
    await t.arrange((db) => setDoc(doc(db, 'expenses', 'e1'), { ...makeExpense(), createdAt: new Date(), updatedAt: new Date() }));
    const db = t.db('admin');
    const snap = await assertSucceeds(
      getDocs(
        query(
          collection(db, 'expenses'),
          where('locationId', '==', LOC.PTB),
          where('date', '>=', `${TODAY.slice(0, 7)}-01`),
          where('date', '<=', `${TODAY.slice(0, 7)}-31`),
          orderBy('date', 'desc'),
        ),
      ),
    );
    expect(snap.size).toBe(1);
  });

  it('sellable and pending products by sortOrder (Store Manager)', async () => {
    await t.arrange(async (db) => {
      const at = { createdAt: new Date(), updatedAt: new Date() };
      await setDoc(doc(db, 'products', 'p1'), { ...makeProduct(), ...at });
      await setDoc(doc(db, 'products', 'p2'), { ...makeProduct({ status: 'PENDING', price: null, scope: LOC.PTB }), ...at });
    });
    const db = t.db('smPtb');
    const products = collection(db, 'products');
    const sellable = await assertSucceeds(
      getDocs(query(products, where('status', '==', 'ACTIVE'), where('scope', 'in', ['GLOBAL', LOC.PTB]), orderBy('sortOrder'))),
    );
    expect(sellable.size).toBe(1);
    const pending = await assertSucceeds(getDocs(query(products, where('status', '==', 'PENDING'), orderBy('sortOrder'))));
    expect(pending.size).toBe(1);
  });
});
