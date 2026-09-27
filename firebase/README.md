# Firestore rules and tests

`firestore.rules` enforces `docs/04-PERMISSIONS.md`. The suite under `test/` proves it on the Firestore emulator (BE-1 to BE-6).

## Running the tests
Once, and after `package-lock.json` changes:

```bash
cd firebase
npm ci
```

Then either start the emulator yourself and run the suite against it (what `tool/check.sh --e2e` does):

```bash
firebase emulators:start --only firestore   # terminal 1
npm test                                     # terminal 2 (npm run test:watch to re-run on save)
```

or let the Firebase CLI start and stop an emulator around one run:

```bash
npm run test:emulator
```

The tests use the `demo-caramel-cottage` project and **clear its Firestore data before every test**, so don't keep hand-made emulator data you care about while they run. The budget probes use `demo-caramel-cottage-budget` and clear it too. The emulator address comes from `FIRESTORE_EMULATOR_HOST` if it is set, otherwise from `firebase.json`. The rules are read from `firestore.rules` on disk at the start of each test file, so there's no need to restart the emulator after editing them.

## Layout
| Path | What it is |
|---|---|
| `test/support/fixtures.js` | Roles, locations and the test actors. Roles are parsed from `packages/core/lib/src/permissions.dart`, so they can't drift from the app's permission sets |
| `test/support/env.js` | `useRulesEnv()`: one test environment per file, and a clean, seeded database before each test. `t.db('<actor>')` gives a client acting as that actor with the rules on; `t.arrange(fn)` writes setup state with the rules off; `t.withPermissions(actor, perms)` narrows an actor's role |
| `test/support/builders.js` | Doc builders (`makeBill`, `makeReturn`, `makeMovement`, `stockWrite`, `makeAudit`, `summaryWrite`, ...) with consistent arithmetic, so a test only spells out the field it tampers with |
| `test/support/batches.js` | Whole business batches (bill, cancel, return, stock operation), with or without summaries and audit, until BE-10's plan fixtures replace them |
| `test/support/caps.js` | The largest batches the list caps allow (D-030), with the caps read from `Limits` in `packages/core` |
| `test/support/budget.js` | Probes that measure how far a rule is from Firestore's evaluation limits (see "Rules budget") |
| `test/*.test.js` | One file per rule group: `org` (#1–4), `bills` (#5–6), `returns` (#5(b), #7), `stock` (#7–8 and the bill batch), `summaries` (#9 and the complete batches), `audit` (#10), `catalog` (#11), `expenses` (#12), `isolation` (#13), `budget` (the caps) |
| `scripts/lib/core.js` | What `firebase/` reads from `packages/core`: permission sets, `Limits`, and the override PIN hash |
| `scripts/budget.mjs` | `npm run budget`: prints the measured headroom of each cap case |

## Actors
| Key | uid | Role | Location | Active |
|---|---|---|---|---|
| `admin` | `admin` | ADMIN | all | yes |
| `smPtb` | `sm-ptb` | STORE_MANAGER | PTB | yes |
| `smMnj` | `sm-mnj` | STORE_MANAGER | MNJ | yes |
| `disabled` | `sm-ptb-disabled` | STORE_MANAGER | PTB | no |
| `cashierPtb` | `cashier-ptb` | CASHIER: `catalog.view`, `bill.create`, `device.register` (the matrix's future column) | PTB | yes |
| `counterPtb` | `counter-ptb` | STOCK_COUNTER: `catalog.view`, `stock.adjust` (no `stock.move`) | PTB | yes |
| `noProfile` | `no-profile` | signed in, no `users` doc | — | — |
| `anonymous` | — | not signed in | — | — |

The two partial roles exist only in the tests, so each permission-gated rule can be shown to need its own permission (QA-034). For a single permission, `t.withPermissions('<actor>', [...])` gives that actor a one-off role holding exactly those.

Both fixture locations start with `nextDeviceNo: 0` and use the offline override PIN `24681357`.

## Rules budget
Firestore stops a rule evaluation after **1000 evaluated expressions** per document, and allows **10 access calls** (`get`, `exists`, `getAfter`, `existsAfter`) per document and 20 per batch. The list caps (D-030) keep every batch inside both, and `test/budget.test.js` holds the line:

- the largest batches are accepted as complete batches: a 15-line bill with 4 payments, a return that brings all 15 products into `returnedQty` with 4 refunds (as a first return, and as a second one over 15 products already returned), and a 20-line PRODUCE creating its 20 stock docs; a 16-line bill is denied;
- each of them still passes with **200 more expressions and 2 more access calls** appended to its tightest rules, so a rules change that eats into the headroom fails CI before it fails at a counter.

Neither count is visible from outside, so the probes measure headroom directly: they load a copy of the rules with padding appended to one rule (`&& <n comparisons>`, or `&& <k exists() calls>`), and search for the most padding with which the batch is still accepted. A calibration run on an empty rule gives how many comparisons make up 1000 expressions. To print the numbers, with an emulator running:

```bash
npm run budget
```

Measured on the emulator (BE-6):

| Case | Rule | Expressions used | Headroom |
|---|---|---|---|
| Bill, 15 lines, 4 payments | bill create | ~653 / 1000 | ~35% |
| Return of all 15 products, 4 refunds (first or second return) | bill update (#5(b)) | ~719 / 1000 | ~28% |
| The same | return create | ~347 / 1000 | ~65% |
| PRODUCE, 20 lines, 20 new stock docs | movement create | ~316 / 1000 | ~68% |
| The same | stock create | ~260 / 1000 | ~74% |

Access calls per document are at most 4 (the user and role docs, plus the doc a rule checks before and after the batch: the return, movement, audit or bill) and at most 8 distinct per batch (the complete return batch), against 10 and 20. The emulator doesn't count a call already made for an earlier document in the same batch, so the spare calls `npm run budget` reports depend on the order it evaluates documents in; the lowest it reports is 6 (a PRODUCE stock doc).

Production is assumed to count like the emulator; nobody guarantees it (CR-001).

