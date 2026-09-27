#!/usr/bin/env node
// Measures the rules budget of the largest batches (BE-6, D-030, CR-001)
// on a running Firestore emulator:
//
//   npm run budget          (FIRESTORE_EMULATOR_HOST, else firebase.json)
//
// For each cap case it prints the evaluated expressions the padded rule
// used out of 1000, and how many more access calls it had room for. See
// test/support/budget.js for how the probes work.

import { ACCESS_LIMIT_DOC, EXPRESSION_LIMIT, calibrate, measure } from '../test/support/budget.js';
import { CAP_CASES } from '../test/support/caps.js';

const capacity = await calibrate();
console.log(`Calibration: ${capacity} padding comparisons fill an empty rule's ${EXPRESSION_LIMIT} expressions.\n`);
console.log('| Case | Rule | Expressions used | Headroom | Spare access calls (emulator) |');
console.log('|---|---|---|---|---|');
for (const { scenario, targets } of CAP_CASES) {
  for (const target of targets) {
    const m = await measure(scenario, target, capacity);
    console.log(
      `| ${scenario.name} | ${target} | ~${m.usedExpressions} / ${EXPRESSION_LIMIT} | ~${m.headroomPct}% | ${m.spareCalls} of ${ACCESS_LIMIT_DOC} |`,
    );
  }
}
console.log(
  '\nThe emulator does not count an access call already made for an earlier document in the same batch, so the spare calls depend on the order it evaluates documents in.',
);
