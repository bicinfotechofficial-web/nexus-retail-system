// BE-10 / BE-9: the app's own write plans against the rules (D-027).
//
// packages/data/test/plans/fixtures_test.dart exports every WritePlan type
// to test/fixtures/plans/<name>.json. Each fixture is applied here, exactly
// as the Dart adapter applies it, as the fixture's `uid`, on top of its
// `arrange` docs, and must be ACCEPTED. Tampered variants must be DENIED.
//
// Fixture ops, as in packages/data/lib/src/plans/write_plan.dart:
//   create   -> set(ref, data)            nested maps are literal
//   setMerge -> set(ref, data, {merge})   nested maps merge field by field
//   update   -> update(ref, data)         keys are dotted field paths
// Sentinels: {"__op": "increment", "by": n}, {"__op": "serverTimestamp"},
// {"__op": "timestamp", "value": ISO-8601}.

import { readdirSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import {
  Timestamp,
  doc,
  getDoc,
  increment,
  runTransaction,
  serverTimestamp,
  setDoc,
  updateDoc,
  writeBatch,
} from 'firebase/firestore';
import { ACTORS, LOC } from './support/fixtures.js';
import { assertFails, assertSucceeds, seedFixtures, useRulesEnv } from './support/env.js';

const t = useRulesEnv();

const DIR = fileURLToPath(new URL('./fixtures/plans/', import.meta.url));

/** Every plan type the Dart side must export (03-SYNC §2 and the admin writes). */
const EXPECTED = [
  'adjust',
  'adjust_stock_counter',
  'bill_cancel',
  'bill_create',
  'bill_create_max',
  'device_register',
  'device_retire',
  'expense_create',
  'expense_edit',
  'location_create',
  'location_edit',
  'produce',
  'product_approve',
  'product_create',
  'product_price_change',
  'product_suggest',
  'raw_material_create',
  'return_first',
  'return_second',
  'stock_in',
  'stock_out_raw',
  'threshold_set',
  'user_disable',
  'wastage_fg',
  'wastage_raw',
];

const FIXTURES = Object.fromEntries(
  readdirSync(DIR)
    .filter((f) => f.endsWith('.json'))
    .map((f) => [f.slice(0, -5), JSON.parse(readFileSync(`${DIR}${f}`, 'utf8'))]),
);

/** A deep copy, so a test can tamper with a fixture freely. */
const fx = (name) => structuredClone(FIXTURES[name]);

function decode(v) {
  if (Array.isArray(v)) return v.map(decode);
  if (v === null || typeof v !== 'object') return v;
  switch (v.__op) {
    case 'increment':
      return increment(v.by);
    case 'serverTimestamp':
      return serverTimestamp();
    case 'timestamp':
      return Timestamp.fromDate(new Date(v.value));
    default:
      return Object.fromEntries(Object.entries(v).map(([k, x]) => [k, decode(x)]));
  }
}

function actorKey(uid) {
  const key = Object.keys(ACTORS).find((k) => ACTORS[k].uid === uid);
  if (!key) throw new Error(`no actor with uid ${uid}`);
  return key;
}

/** The batch the Dart adapter builds from these ops. */
function batchOf(db, ops) {
  const b = writeBatch(db);
  for (const op of ops) {
    const ref = doc(db, op.path);
    const data = decode(op.data);
    if (op.kind === 'create') b.set(ref, data);
    else if (op.kind === 'setMerge') b.set(ref, data, { merge: true });
    else if (op.kind === 'update') b.update(ref, data);
    else throw new Error(`unknown kind ${op.kind}`);
  }
  return b;
}

async function arrange(f) {
  await t.arrange(async (db) => {
    for (const a of f.arrange) await setDoc(doc(db, a.path), decode(a.data));
  });
}

/** Arranges the fixture's docs and commits its ops as `actor` (default: its uid). */
async function apply(f, { actor, skipArrange = false } = {}) {
  if (!skipArrange) await arrange(f);
  return batchOf(t.db(actor ?? actorKey(f.uid)), f.ops).commit();
}

const without = (f, pred) => ({ ...f, ops: f.ops.filter((o) => !pred(o.path)) });
const opAt = (f, path) => f.ops.find((o) => o.path === path);

async function read(path) {
  let data;
  await t.arrange(async (db) => {
    data = (await getDoc(doc(db, path))).data();
  });
  return data;
}

// ---- Every plan type is accepted ---------------------------------------

describe('plan fixtures (D-027)', () => {
  it('has exactly the expected plan types', () => {
    expect(Object.keys(FIXTURES).sort()).toEqual(EXPECTED);
  });

  for (const name of EXPECTED) {
    it(`accepts ${name}: ${FIXTURES[name]?.description}`, async () => {
      await assertSucceeds(apply(fx(name)));
    });
  }
});

// ---- The summaries add up on the server ---------------------------------

describe('plan fixtures: exact state after the batches', () => {
  const DAY = 'locations/PTB/dailySummary/2026-09-26';
  const MONTH = 'locations/PTB/monthlySummary/2026-09';
  const BILL = 'locations/PTB/bills/D01-000007';

  it('bill then cancel: as billed, cancelled, and byMode/byProduct back to 0', async () => {
    await assertSucceeds(apply(fx('bill_create')));
    expect(await read(DAY)).toEqual({
      billCount: 1,
      grossSales: 70100,
      discounts: 7010,
      roundOff: 10,
      netSales: 63100,
      byMode: { CASH: 50000, UPI: 13100 },
      byProduct: {
        'cake-choco-1kg': { qty: 1, amount: 58500 },
        'puff-veg': { qty: 2, amount: 4590 },
      },
      lastWriteRef: BILL,
    });
    expect((await read('locations/PTB/stock/FG_puff-veg')).qty).toBe(-2);

    await assertSucceeds(apply(fx('bill_cancel'), { skipArrange: true }));
    const day = await read(DAY);
    expect(day).toEqual({
      billCount: 1,
      cancelCount: 1,
      grossSales: 70100,
      discounts: 7010,
      roundOff: 10,
      netSales: 63100,
      cancelled: 63100,
      byMode: { CASH: 0, UPI: 0 },
      byProduct: {
        'cake-choco-1kg': { qty: 0, amount: 0 },
        'puff-veg': { qty: 0, amount: 0 },
      },
      lastWriteRef: 'locations/PTB/movements/D01-000007-X',
    });
    expect(await read(MONTH)).toEqual(day);
    expect((await read('locations/PTB/stock/FG_puff-veg')).qty).toBe(0);
    expect((await read(BILL)).status).toBe('CANCELLED');
  });

  it('bill then two returns: refunds add up to the bill total exactly (D-024)', async () => {
    await assertSucceeds(apply(fx('bill_create')));
    await assertSucceeds(apply(fx('return_first'), { skipArrange: true }));
    await assertSucceeds(apply(fx('return_second'), { skipArrange: true }));
    const day = await read(DAY);
    expect(day).toEqual({
      billCount: 1,
      returnCount: 2,
      grossSales: 70100,
      discounts: 7010,
      roundOff: 10,
      netSales: 63100,
      returns: 63100,
      byMode: { CASH: 50000 - 2300 - 20800, UPI: 13100 - 40000 },
      byProduct: {
        'cake-choco-1kg': { qty: 0, amount: 0 },
        'puff-veg': { qty: 0, amount: 0 },
      },
      lastWriteRef: 'locations/PTB/returns/D01-R000004',
    });
    expect(await read(MONTH)).toEqual(day);
    const bill = await read(BILL);
    expect(bill.returnedQty).toEqual({ 'cake-choco-1kg': 1, 'puff-veg': 2 });
    expect(bill.lastReturnId).toBe('D01-R000004');
    expect((await read('locations/PTB/stock/FG_puff-veg')).qty).toBe(0);
    expect((await read('locations/PTB/devices/D01')).lastReturnSeq).toBe(4);
  });

  it('expense create then edit to another month and location', async () => {
    await assertSucceeds(apply(fx('expense_create')));
    await assertSucceeds(apply(fx('expense_edit'), { skipArrange: true }));
    const sep = await read('locations/PTB/monthlySummary/2026-09');
    expect(sep.expenses).toBe(0);
    expect(sep.byExpenseCategory).toEqual({ RENT: 0 });
    const aug = await read('locations/MNJ/monthlySummary/2026-08');
    expect(aug.expenses).toBe(300000);
    expect(aug.byExpenseCategory).toEqual({ UTILITIES: 300000 });
  });

  it('produce, adjust and threshold leave the stock doc exact', async () => {
    await assertSucceeds(apply(fx('stock_in')));
    // PRODUCE as the next movement number, on top of stock_in's.
    const produce = JSON.parse(JSON.stringify(fx('produce')).replaceAll('D01-M000042', 'D01-M000043'));
    opAt(produce, 'locations/PTB/devices/D01').data.lastMovementSeq = 43;
    await assertSucceeds(apply(produce, { skipArrange: true }));
    await assertSucceeds(apply(fx('threshold_set')));
    const flour = await read('locations/PTB/stock/RM_flour');
    expect(flour).toMatchObject({ kind: 'RAW', refId: 'flour', unit: 'G', qty: 4000, lastMovementId: 'D01-M000043' });
    const cream = await read('locations/PTB/stock/RM_cream');
    expect(cream).toMatchObject({ qty: 500, lowThreshold: 2000, name: 'Cream' });
    expect((await read('locations/PTB/stock/FG_cake-choco-1kg')).qty).toBe(2);
  });
});

// ---- Tampered plans are denied -----------------------------------------

describe('plan fixtures: tampered variants are denied', () => {
  it('a summary increment without its new bill (#9)', async () => {
    const f = fx('bill_create');
    await assertFails(apply(without(f, (p) => p.endsWith('/bills/D01-000007'))));
    await assertFails(apply({ ...f, ops: f.ops.filter((o) => o.path.includes('Summary')) }));
  });

  it('the same bill twice: the whole second batch fails (03-SYNC §4)', async () => {
    const f = fx('bill_create');
    await assertSucceeds(apply(f));
    const g = fx('bill_create');
    // A retry after a crash that re-allocated nothing: same number, and the
    // device counter would not go up either.
    opAt(g, 'locations/PTB/devices/D01').data.lastBillSeq = 8;
    await assertFails(apply(g, { skipArrange: true }));
  });

  it('a device counter that does not go up (#4)', async () => {
    const f = fx('bill_create');
    // The plan writes lastBillSeq 7; the device already used 8.
    f.arrange.find((a) => a.path.endsWith('/devices/D01')).data.lastBillSeq = 8;
    await assertFails(apply(f));
  });

  it('a stock qty change naming an old movement (#8)', async () => {
    const f = fx('stock_in');
    await t.arrange((db) =>
      setDoc(doc(db, 'locations/PTB/movements/D01-M000001'), { type: 'STOCK_IN', lines: [] }),
    );
    opAt(f, 'locations/PTB/stock/RM_flour').data.lastMovementId = 'D01-M000001';
    await assertFails(apply(f));
  });

  it('a return worked out from a stale bill: prevReturnId is not the bill\'s lastReturnId (D-029)', async () => {
    // The first return, but another return (R000009) landed first.
    const f = fx('return_first');
    const bill = f.arrange.find((a) => a.path.endsWith('/bills/D01-000007'));
    bill.data.returnedQty = { 'puff-veg': 1 };
    bill.data.lastReturnId = 'D01-R000009';
    await assertFails(apply(f));
    // The second return against a bill whose last return is another one.
    const g = fx('return_second');
    g.arrange.find((a) => a.path.endsWith('/bills/D01-000007')).data.lastReturnId = 'D01-R000009';
    await assertFails(apply(g));
  });

  it('a return beyond soldQty (D-029)', async () => {
    const f = fx('return_second');
    f.arrange.find((a) => a.path.endsWith('/bills/D01-000007')).data.returnedQty = { 'puff-veg': 2 };
    await assertFails(apply(f));
  });

  it('a return of a cancelled bill, and a cancel of a returned bill (D-025)', async () => {
    const r = fx('return_first');
    const bill = r.arrange.find((a) => a.path.endsWith('/bills/D01-000007'));
    bill.data.status = 'CANCELLED';
    await assertFails(apply(r));
    const c = fx('bill_cancel');
    const b2 = c.arrange.find((a) => a.path.endsWith('/bills/D01-000007'));
    b2.data.returnedQty = { 'puff-veg': 1 };
    b2.data.lastReturnId = 'D01-R000003';
    await assertFails(apply(c));
  });

  it('a cancel, return, wastage or adjust without its audit doc (#10)', async () => {
    for (const name of ['bill_cancel', 'return_first', 'wastage_fg', 'wastage_raw', 'adjust']) {
      await t.env.clearFirestore();
      await seedFixtures(t.env);
      await assertFails(apply(without(fx(name), (p) => p.startsWith('auditLog/'))));
    }
  });

  it('an expense summary without its audit doc, and an expense by a Store Manager (#9, #12)', async () => {
    await assertFails(apply(without(fx('expense_create'), (p) => p.startsWith('auditLog/'))));
    await assertFails(apply(fx('expense_create'), { actor: 'smPtb' }));
  });

  it('a stock movement without stock.move, while an adjust with only stock.adjust passes (QA-029)', async () => {
    await t.withPermissions('smPtb', ['catalog.view', 'stock.adjust']);
    await assertFails(apply(fx('stock_in')));
    await assertSucceeds(apply(fx('adjust')));
  });

  it('a threshold without stock.threshold (#8)', async () => {
    await assertFails(apply(fx('threshold_set'), { actor: 'cashierPtb' }));
  });

  it('another location: a PTB bill batch from the MNJ Store Manager (#13)', async () => {
    const f = fx('bill_create');
    await arrange(f);
    await t.withPermissions('smMnj', ['bill.create']);
    // Rewrite createdBy so only the location differs.
    const g = JSON.parse(JSON.stringify(f).replaceAll('"sm-ptb"', '"sm-mnj"'));
    await assertFails(apply(g, { skipArrange: true }));
  });

  it('a location edit that writes nextDeviceNo, and a create without it (QA-035)', async () => {
    const e = fx('location_edit');
    opAt(e, 'locations/PTB').data.nextDeviceNo = 5;
    await assertFails(apply(e));
    const c = fx('location_create');
    delete opAt(c, 'locations/KTL').data.nextDeviceNo;
    await assertFails(apply(c));
  });

  it('admin-only plans from a Store Manager', async () => {
    for (const name of ['user_disable', 'product_approve', 'product_price_change', 'location_edit', 'device_retire']) {
      const f = fx(name);
      await assertFails(apply(JSON.parse(JSON.stringify(f).replaceAll('"admin"', '"sm-ptb"'))));
    }
  });

  it('a suggestion scoped to another location (#11)', async () => {
    const f = fx('product_suggest');
    opAt(f, 'products/p-special').data.scope = 'MNJ';
    await assertFails(apply(f));
  });
});

// ---- BE-9: registration ----------------------------------------------------

describe('BE-9 device registration', () => {
  const REG = FIXTURES.device_register;
  const deviceData = (code, uid) => ({
    ...decode(REG.ops[1].data),
    code,
    registeredBy: uid,
  });

  /**
   * The transaction FirestoreDeviceService runs: read nextDeviceNo, +1,
   * create D{n}. When two registrations race, the emulator evaluates the
   * loser's writes against the winner's nextDeviceNo before it checks the
   * transaction's reads, so the loser gets PERMISSION_DENIED rather than
   * ABORTED, which the SDK doesn't retry. The service retries the whole
   * transaction on permission-denied, with a growing random pause,
   * re-reading the new value; so does this helper.
   */
  const register = async (actor, attempts = 8) => {
    const db = t.db(actor);
    for (let i = 1; ; i++) {
      try {
        return await runTransaction(db, async (tx) => {
          const locRef = doc(db, 'locations', LOC.PTB);
          const next = (await tx.get(locRef)).data().nextDeviceNo + 1;
          const code = `D${String(next).padStart(2, '0')}`;
          tx.update(locRef, { nextDeviceNo: next });
          tx.set(doc(db, 'locations', LOC.PTB, 'devices', code), deviceData(code, ACTORS[actor].uid));
          return code;
        });
      } catch (e) {
        if (e.code !== 'permission-denied' || i >= attempts) throw e;
        await new Promise((r) => setTimeout(r, 20 + Math.random() * 80 * i));
      }
    }
  };

  it('two concurrent registrations get D01 and D02', async () => {
    const codes = await Promise.all([register('smPtb'), register('cashierPtb')]);
    expect(codes.sort()).toEqual(['D01', 'D02']);
    expect((await read('locations/PTB')).nextDeviceNo).toBe(2);
    expect((await read('locations/PTB/devices/D01')).retired).toBe(false);
    expect((await read('locations/PTB/devices/D02')).lastBillSeq).toBe(0);
  });

  it('five concurrent registrations get D01 to D05, each once', async () => {
    const codes = await Promise.all(['smPtb', 'cashierPtb', 'admin', 'smPtb', 'cashierPtb'].map((a) => register(a)));
    expect(codes.sort()).toEqual(['D01', 'D02', 'D03', 'D04', 'D05']);
    expect((await read('locations/PTB')).nextDeviceNo).toBe(5);
  });

  it('a registration after a retirement gets a new code, never the old one (D-004)', async () => {
    await assertSucceeds(register('smPtb'));
    await assertSucceeds(batchOf(t.db('admin'), FIXTURES.device_retire.ops).commit());
    expect(await register('smPtb')).toBe('D02');
  });

  it('stops at D99', async () => {
    await t.arrange((db) => updateDoc(doc(db, 'locations', LOC.PTB), { nextDeviceNo: 99 }));
    await assertFails(register('smPtb', 1));
  });

  it('denies a registration that skips a number', async () => {
    const f = fx('device_register');
    opAt(f, 'locations/PTB').data.nextDeviceNo = 2;
    await assertFails(apply(f));
  });
});
