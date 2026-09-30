// BE-6: the rules budget at the list caps (D-030, CR-001). The largest
// batches the caps allow are accepted as complete batches, one line over the
// cap is denied, and each keeps a margin under Firestore's per-evaluation
// limits, so a rules change that eats into the headroom fails here before it
// fails at a counter.
//
// Measure the actual headroom with `npm run budget` (see
// test/support/budget.js for how the probes work).

import { beforeAll, describe, expect, it } from 'vitest';
import { CAP_CASES, largestBill, largestFirstReturn, largestProduce, largestSecondReturn, overCapBill } from './support/caps.js';
import { ACCESS_LIMIT_DOC, EXPRESSION_LIMIT, calibrate, comparisonsFor, probe } from './support/budget.js';
import { assertFails, assertSucceeds, useRulesEnv } from './support/env.js';

const t = useRulesEnv();

async function accept(scenario) {
  if (scenario.arrange) await t.arrange(scenario.arrange);
  return scenario.run(t.db);
}

describe('rules budget: the largest batches are accepted (D-030)', () => {
  it('accepts the complete bill batch with 15 lines and 4 payments', async () => {
    await assertSucceeds(accept(largestBill));
  });

  it('accepts the complete return batch that brings all 15 products into returnedQty, with 4 refunds', async () => {
    await assertSucceeds(accept(largestFirstReturn));
  });

  it('accepts a second return over all 15 products already in returnedQty', async () => {
    await assertSucceeds(accept(largestSecondReturn));
  });

  it('accepts a 20-line PRODUCE with its 20 new stock docs', async () => {
    await assertSucceeds(accept(largestProduce));
  });

  it('denies the complete bill batch with 16 lines', async () => {
    await assertFails(accept(overCapBill));
  });
});

// A rules change must leave every cap case at least this far under the
// limits. Measured headroom is 28% or more of the expressions (the return's
// bill update is the tightest) and 6 or more access calls (a PRODUCE stock
// doc), per `npm run budget`.
const MIN_SPARE_EXPRESSIONS = 200;
const MIN_SPARE_CALLS = 2;

describe(`rules budget: every cap case keeps ${MIN_SPARE_EXPRESSIONS} of ${EXPRESSION_LIMIT} expressions and ${MIN_SPARE_CALLS} access calls spare`, () => {
  let capacity;
  beforeAll(async () => {
    capacity = await calibrate();
    // A sanity check on the calibration itself: 1 == 1 is a handful of
    // expressions, not one and not dozens.
    expect(capacity).toBeGreaterThan(EXPRESSION_LIMIT / 10);
    expect(capacity).toBeLessThan(EXPRESSION_LIMIT / 2);
  }, 120_000);

  const cases = CAP_CASES.flatMap(({ scenario, targets }) => targets.map((target) => [scenario.name, target, scenario]));

  it.each(cases)('%s: %s', async (_, target, scenario) => {
    expect(await probe(scenario, { target, exprs: comparisonsFor(MIN_SPARE_EXPRESSIONS, capacity) })).toBe(true);
    expect(await probe(scenario, { target, calls: MIN_SPARE_CALLS })).toBe(true);
  }, 60_000);

  // The access-call bite pads past the per-document limit on its own. The
  // emulator doesn't count a call an earlier document in the same batch
  // already made, and the order it evaluates a batch's documents in changes
  // from one emulator start to the next: when the summaries (which read the
  // same return doc, #9) go first, the bill update's own calls are only
  // the padding, and 10 more calls fit. Eleven never do. The expression
  // count doesn't depend on that order.
  it(`the probes do bite: the largest return update is denied with 400 more expressions or ${ACCESS_LIMIT_DOC + 1} more calls`, async () => {
    expect(await probe(largestFirstReturn, { target: 'billUpdate', exprs: comparisonsFor(400, capacity) })).toBe(false);
    expect(await probe(largestFirstReturn, { target: 'billUpdate', calls: ACCESS_LIMIT_DOC + 1 })).toBe(false);
  }, 60_000);
});
