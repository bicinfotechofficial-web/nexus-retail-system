# Firestore rules, indexes, tests and seed

`firestore.rules` enforces `docs/04-PERMISSIONS.md`. The suite under `test/` proves it on the Firestore emulator (BE-1 to BE-6), checks `firestore.indexes.json` (BE-7) and runs the seed script (BE-14).

## Running the tests
Once, and after `package-lock.json` changes:

```bash
cd firebase
npm ci
```

Then either start the emulator yourself and run the suite against it (what `tool/check.sh --e2e` does):

```bash
firebase emulators:start --only firestore,auth   # terminal 1
npm test                                          # terminal 2 (npm run test:watch to re-run on save)
```

or let the Firebase CLI start and stop an emulator around one run:

```bash
npm run test:emulator
```

The tests use the `demo-caramel-cottage` project and **clear its Firestore data before every test**, so don't keep hand-made emulator data you care about while they run. The budget probes use `demo-caramel-cottage-budget` and the seed tests `demo-caramel-cottage-seed` (Firestore and Auth), and clear those too. The emulator addresses come from `FIRESTORE_EMULATOR_HOST` and `FIREBASE_AUTH_EMULATOR_HOST` if they are set, otherwise from `firebase.json`. The seed tests need the Auth emulator as well as Firestore. The rules are read from `firestore.rules` on disk at the start of each test file, so there's no need to restart the emulator after editing them.

## Layout
| Path | What it is |
|---|---|
| `test/support/fixtures.js` | Roles, locations and the test actors. Roles are parsed from `packages/core/lib/src/permissions.dart`, so they can't drift from the app's permission sets |
| `test/support/env.js` | `useRulesEnv()`: one test environment per file, and a clean, seeded database before each test. `t.db('<actor>')` gives a client acting as that actor with the rules on; `t.arrange(fn)` writes setup state with the rules off; `t.withPermissions(actor, perms)` narrows an actor's role |
| `test/support/builders.js` | Doc builders (`makeBill`, `makeReturn`, `makeMovement`, `stockWrite`, `makeAudit`, `summaryWrite`, ...) with consistent arithmetic, so a test only spells out the field it tampers with |
| `test/support/batches.js` | Whole business batches (bill, cancel, return, stock operation), with or without summaries and audit, until BE-10's plan fixtures replace them |
| `test/support/caps.js` | The largest batches the list caps allow (D-030), with the caps read from `Limits` in `packages/core` |
| `test/support/budget.js` | Probes that measure how far a rule is from Firestore's evaluation limits (see "Rules budget") |
| `test/*.test.js` | One file per rule group: `org` (#1–4), `bills` (#5–6), `returns` (#5(b), #7), `stock` (#7–8 and the bill batch), `summaries` (#9 and the complete batches), `audit` (#10), `catalog` (#11), `expenses` (#12), `isolation` (#13), `budget` (the caps), plus `indexes` (BE-7) and `seed` (BE-14) |
| `scripts/lib/core.js` | What `firebase/` reads from `packages/core`: permission sets, `Limits`, and the override PIN hash |
| `scripts/seed.mjs` | The seed script (see "Seeding") |
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
- each of them still passes with **200 more expressions and 2 more access calls** appended to its tightest rules, so a rules change that eats into the headroom fails CI before it fails at a counter;
- the probes bite: the largest return's bill update is denied with 400 more expressions, or with 11 more access calls (one over the per-document limit on their own, because the emulator's per-document count depends on the order it evaluates a batch in; see below).

Neither count is visible from outside, so the probes measure headroom directly: they load a copy of the rules with padding appended to one rule (`&& <n comparisons>`, or `&& <k exists() calls>`), and search for the most padding with which the batch is still accepted. A calibration run on an empty rule gives how many comparisons make up 1000 expressions. To print the numbers, with an emulator running:

```bash
npm run budget
```

Measured on the emulator (BE-6, re-measured after QA-038 to QA-040):

| Case | Rule | Expressions used | Headroom |
|---|---|---|---|
| Bill, 15 lines, 4 payments | bill create | ~653 / 1000 | ~35% |
| Return of all 15 products, 4 refunds (first or second return) | bill update (#5(b)) | ~719 / 1000 | ~28% |
| The same | return create | ~362 / 1000 (first), ~367 (second) | ~63% |
| PRODUCE, 20 lines, 20 new stock docs | movement create | ~342 / 1000 | ~66% |
| The same | stock create | ~260 / 1000 | ~74% |

Access calls per document are at most 4 (the user and role docs, plus the doc a rule checks before and after the batch: the return, movement, audit or bill; a SALE, RETURN or CANCEL movement checks its bill or return) and at most 8 distinct per batch (the complete return batch), against 10 and 20. The emulator doesn't count a call already made for an earlier document in the same batch, so the spare calls `npm run budget` reports depend on the order it evaluates documents in; the lowest it reports is 6 (a PRODUCE stock doc). Which order an emulator uses changes from one start to the next, so a test must never depend on a document's calls being counted: with the summaries evaluated before it, the return's bill update counts none of its own.

Production is assumed to count like the emulator; nobody guarantees it (CR-001).

## Indexes
`firestore.indexes.json` holds the composite indexes of 02-DATA-MODEL and the queries behind `packages/data/lib/src/api/`:

| Collection | Index | Query |
|---|---|---|
| `bills` | `businessDate DESC, clientCreatedAt DESC` | A day's bills newest first (`watchBills`), and bills paged by date |
| `returns` | `businessDate DESC, clientCreatedAt DESC` | A day's returns (`watchReturns`) |
| `returns` | `billId ASC, clientCreatedAt ASC` | The returns of one bill (`returnsForBill`) |
| `auditLog` | `locationId ASC, at DESC`; `action ASC, at DESC`; `by ASC, at DESC` | `AuditQuery` by location, action or user, newest first, with a date range. Two or three of these filters together are served by index merging, so they need no index of their own |
| `expenses` | `locationId ASC, date DESC` | One location's expenses for a month (`watchExpenses`) |
| `products` | `status ASC, sortOrder ASC` | Pending suggestions (`watchPending`) |
| `products` | `status ASC, scope ASC, sortOrder ASC` | Sellable products: ACTIVE, scope `GLOBAL` or the location (`watchSellable`) |

`findByBillNo` needs no index: a bill number is `{loc}-{billId}`, which names the doc. Single-field queries (users by location, expenses of a month across locations, all products by `sortOrder`) use Firestore's automatic indexes, and summaries are read by doc ID.

The emulator serves every query without indexes and doesn't read the file, so `test/indexes.test.js` checks it instead: it passes the Firebase CLI's own validation (the step `firebase deploy --only firestore:indexes` runs before calling the API), it holds exactly the indexes above, and each of those queries runs on the emulator under the rules as the user who makes it. Deploy with `firebase deploy --only firestore:indexes --project prod`; Firestore builds the indexes in a few minutes.

## Seeding
`scripts/seed.mjs` sets up a fresh project: the `ADMIN` and `STORE_MANAGER` roles (permissions read from `packages/core/lib/src/permissions.dart`), one Admin (the Auth account and `users/{uid}`), the locations PTB (Pattambi) and MNJ (Manjeri) with `nextDeviceNo: 0`, the default limits and a hashed override PIN, 10 sample products (cakes and pastries, ACTIVE, GLOBAL, prices in paise) and 5 raw materials.

It is **idempotent**: it creates what is missing and leaves everything that exists alone, so running it twice changes nothing, and an Admin's later edits (a location's phone, a price) are never overwritten. Roles are the exception: only this script writes them (02-DATA-MODEL), so a role that differs from `permissions.dart` is brought back in line. `test/seed.test.js` runs it twice on the emulator and checks that no doc and no Auth account changed.

Inputs come from environment variables, or a prompt when one is needed and missing. Nothing is hard-coded:

| Variable | Used |
|---|---|
| `SEED_ADMIN_EMAIL` | Always: the Admin's sign-in email |
| `SEED_ADMIN_PASSWORD` | Only when the Admin's Auth account is created. At least 8 characters |
| `SEED_OVERRIDE_PIN` | Only when a location is created: its offline override PIN, at least 8 digits (`Limits.minOverridePinDigits`). Both locations get it, each with its own salt; change it per store in the admin console |

The PIN is stored as PBKDF2-SHA256 over the PIN's UTF-8 bytes, 100,000 iterations, a 16-byte random salt and a 32-byte key, as `base64(salt)$base64(key)` (02-DATA-MODEL).

**On the emulator** (the default: project `demo-caramel-cottage`, addresses from `FIRESTORE_EMULATOR_HOST` and `FIREBASE_AUTH_EMULATOR_HOST`, else `firebase.json`). Start the Firestore and Auth emulators, then:

```bash
npm run seed                                  # prompts for the email, password and PIN
npm run seed -- --project demo-anything       # any other demo- project
```

**On production**, only with both flags, with no emulator variables set, and with credentials for the project (for example `GOOGLE_APPLICATION_CREDENTIALS` pointing at a service-account key, which never goes into the repo):

```bash
npm run seed -- --project caramel-cottage-retail --yes-really
```

Any other project ID is refused. The script prints one line per doc (`created`, `updated` or `unchanged`) and a total.
