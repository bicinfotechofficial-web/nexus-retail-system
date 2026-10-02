// Rules budget probes (BE-6, D-030, CR-001).
//
// Firestore stops a rule evaluation after 1000 evaluated expressions (per
// document) and 10 access calls (get, exists, getAfter, existsAfter) per
// document, 20 per batch. Neither count is visible from outside, so the
// probes measure headroom directly: they append padding to the rule under
// test (`&& <pad>`, evaluated only after the rule itself has passed) and find
// the most padding with which the batch is still accepted.
//
// - Expression padding is `n` comparisons (`1 == 1`), grouped ten to a
//   function. A calibration run on a rule that does nothing else finds how
//   many fit in the whole budget, so n comparisons ≈ n × 1000 / capacity
//   expressions.
// - Access padding is `k` exists() calls on distinct docs that never exist.
//   The emulator doesn't count a call an earlier document in the same batch
//   already made, and its evaluation order varies between emulator starts,
//   so a rule's own count can drop to the padding alone. Only `k` above the
//   per-document limit is denied every time.
//
// Each probe loads its own copy of the rules into a separate emulator
// project, so it never disturbs the suite's `demo-caramel-cottage`.

import { initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { doc, setDoc } from 'firebase/firestore';
import { dbAs, emulatorAddress, loadRules, seedFixtures } from './env.js';

export const EXPRESSION_LIMIT = 1000;
export const ACCESS_LIMIT_DOC = 10;
export const ACCESS_LIMIT_BATCH = 20;

const BUDGET_PROJECT = 'demo-caramel-cottage-budget';

/**
 * The rule each target pads: the exact `allow` line in firestore.rules and
 * its padded form. A target that no longer matches throws, so a rules
 * refactor can't silently turn a probe into a no-op.
 */
export const TARGETS = {
  billCreate: {
    line: "allow create: if canAt('bill.create', loc) && validNewBill(loc, billId);",
    padded: (p) => `allow create: if canAt('bill.create', loc) && validNewBill(loc, billId) && ${p};`,
  },
  billUpdate: {
    line: 'allow update: if isReturnUpdate(loc) || isCancel(loc, billId);',
    padded: (p) => `allow update: if (isReturnUpdate(loc) || isCancel(loc, billId)) && ${p};`,
  },
  returnCreate: {
    line: "allow create: if canAt('return.create', loc) && validNewReturn(loc, returnId);",
    padded: (p) => `allow create: if canAt('return.create', loc) && validNewReturn(loc, returnId) && ${p};`,
  },
  movementCreate: {
    line: 'allow create: if validNewMovement(loc, movementId);',
    padded: (p) => `allow create: if validNewMovement(loc, movementId) && ${p};`,
  },
  // The customer rules are several lines long, so their padding goes in front.
  customerCreate: {
    line: 'allow create: if validCustomerWrite(loc, customerId, customerBill(loc))',
    padded: (p) => `allow create: if ${p} && validCustomerWrite(loc, customerId, customerBill(loc))`,
  },
  customerUpdate: {
    line: 'allow update: if validCustomerWrite(loc, customerId, customerBill(loc))',
    padded: (p) => `allow update: if ${p} && validCustomerWrite(loc, customerId, customerBill(loc))`,
  },
  stockCreate: {
    line: 'allow create: if activeAt(loc) && validNewStock(loc, itemKey);',
    padded: (p) => `allow create: if activeAt(loc) && validNewStock(loc, itemKey) && ${p};`,
  },
};

const ROOT = 'match /databases/{database}/documents {';

function padFunctions(exprs, calls) {
  const ten = Array(10).fill('1 == 1').join(' && ');
  const cmp = [...Array(Math.floor(exprs / 10)).fill('__budgetTen()'), ...Array(exprs % 10).fill('1 == 1')];
  const acc = Array.from({ length: calls }, (_, i) => `!exists(/databases/$(database)/documents/budgetPad/p${i})`);
  return `
    function __budgetTen() { return ${ten}; }
    function __budgetPad() { return ${[...cmp, ...acc].join(' && ') || 'true'}; }`;
}

/** firestore.rules with `target`'s rule padded by `exprs` comparisons and `calls` access calls. */
export function paddedRules({ target, exprs = 0, calls = 0, rules = loadRules() }) {
  if (!target) return rules;
  const withFns = rules.replace(ROOT, `${ROOT}${padFunctions(exprs, calls)}`);
  if (target === 'calibration') {
    return withFns.replace(ROOT, `${ROOT}\n    match /budgetCalibration/{id} { allow write: if __budgetPad(); }`);
  }
  const { line, padded } = TARGETS[target];
  const parts = withFns.split(line);
  if (parts.length !== 2) throw new Error(`budget: rule for ${target} not found exactly once in firestore.rules`);
  return parts.join(padded('__budgetPad()'));
}

/**
 * Runs one scenario against padded rules and says whether the batch was
 * accepted. A scenario is `{ arrange(db), run(dbAs) }`: `arrange` writes
 * state with the rules off, `run` returns the promise of the write under
 * test, made through `dbAs(actorKey)`.
 */
export async function probe(scenario, { target, exprs = 0, calls = 0 }) {
  const { host, port } = emulatorAddress();
  const env = await initializeTestEnvironment({
    projectId: BUDGET_PROJECT,
    firestore: { host, port, rules: paddedRules({ target, exprs, calls }) },
  });
  try {
    await env.clearFirestore();
    await seedFixtures(env);
    if (scenario.arrange) await env.withSecurityRulesDisabled((ctx) => scenario.arrange(ctx.firestore()));
    await scenario.run((actor) => dbAs(env, actor));
    return true;
  } catch (e) {
    if (e?.code === 'permission-denied' || /PERMISSION_DENIED/.test(String(e?.message))) return false;
    throw e;
  } finally {
    await env.cleanup();
  }
}

/** The largest value in [lo, hi] for which `ok(value)` holds, given ok is monotone and ok(lo). */
async function largest(ok, lo, hi) {
  if (await ok(hi)) return hi;
  while (hi - lo > 1) {
    const mid = Math.floor((lo + hi) / 2);
    if (await ok(mid)) lo = mid;
    else hi = mid;
  }
  return lo;
}

/** A write to a rule that does nothing but the padding. */
export const CALIBRATION = {
  run: (dbAs) => setDoc(doc(dbAs('smPtb'), 'budgetCalibration/x'), { x: 1 }),
};

/** How many padding comparisons fit in an empty rule: the whole 1000-expression budget. */
export async function calibrate() {
  return largest((n) => probe(CALIBRATION, { target: 'calibration', exprs: n }), 0, 600);
}

/**
 * Measures one target in one scenario: the spare expressions (in units of
 * the 1000-expression limit, using `capacity` from calibrate()) and the
 * spare access calls. Throws if the scenario isn't accepted unpadded.
 */
export async function measure(scenario, target, capacity) {
  if (!(await probe(scenario, { target }))) throw new Error(`budget: scenario is denied without padding (${target})`);
  const spareCmp = await largest((n) => probe(scenario, { target, exprs: n }), 0, capacity);
  const spareCalls = await largest((k) => probe(scenario, { target, calls: k }), 0, ACCESS_LIMIT_DOC);
  const spare = Math.round((spareCmp * EXPRESSION_LIMIT) / capacity);
  return {
    target,
    usedExpressions: EXPRESSION_LIMIT - spare,
    spareExpressions: spare,
    headroomPct: Math.round((spare * 100) / EXPRESSION_LIMIT),
    spareCalls,
  };
}

/** Comparisons worth `expressions` of the 1000-expression budget, rounded up. */
export function comparisonsFor(expressions, capacity) {
  return Math.ceil((expressions * capacity) / EXPRESSION_LIMIT);
}
