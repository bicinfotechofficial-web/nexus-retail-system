# Agent Plan

## How the team works
- **Central agent** (orchestrator): owns `docs/`, `packages/core`, integration, merging and final review. It is the only writer of contracts.
- **Build agents** each own one directory. They may read everything, but they write **only inside their own directory**.
- Contract gaps and disagreements go into `docs/CHANGE-REQUESTS.md` (what, why, the options). A build agent never works around a contract. The central agent decides, updates `00-DECISIONS.md`, and tells every agent affected.
- Every agent works on its own branch (`agent/<name>`). The central agent merges into `main` after review and tests.
- Bicy approves: the Phase 0 contracts, anything marked **Proposed**, and pilot sign-off.

## Repository conventions (all agents)
- Every commit is authored as **Bicy** (`bicinfotechofficial-web@users.noreply.github.com`). Commits carry no co-author or tool-attribution trailers.
- No personal names in code, docs, comments, seed data or commit messages. Refer to the owner as **Bicy**, and use role names ("Admin", "Store Manager") everywhere else.

## Repository layout
```
nexus-retail-system/
  docs/                    central
  packages/core/           central     pure Dart: models, money, bill/return calculators, validation, permission constants, Firestore paths
  packages/data/           backend     Firestore repositories and the batch builders for each business operation (§2 of the sync doc)
  packages/printer/        printer     ReceiptDocument → ESC/POS bytes, Bluetooth transport
  apps/pos/                pos         Flutter Android app
  apps/admin/              admin       Flutter Web app
  firebase/                backend     firestore.rules, indexes, firebase.json, rules tests (Node + emulator), seed script
  test/e2e/                qa          scenario tests on the emulator
```

## Phases
| Phase | Days | Who | Exit gate |
|---|---|---|---|
| 0 — Contracts | 1–2 | Central | Bicy approves `docs/`. `packages/core` compiles, with unit tests for money, bill and return calculators |
| 1 — Parallel build | 3–10 | Backend, POS, Printer, Admin, QA | Each agent's definition of done (below) |
| 2 — Integration | 11–13 | Central + QA | Pilot acceptance tests (`01-MVP-SCOPE.md`) pass on the emulator |
| 3 — Device pilot | 14+ | Bicy | Real printer and phone check, release APK installed at the pilot store |

The Printer agent starts **on day 1**, alongside Phase 0. It is the riskiest piece because of the hardware, and it depends only on the `ReceiptDocument` interface.

## Agent briefs
The full, self-contained briefs each agent works from are in [`docs/agents/`](agents/README.md). The summaries below are the scope; the briefs add the task order, contracts (D-026) and working rules.


### Backend — `firebase/`, `packages/data/`
- Firestore rules implementing every item in `04-PERMISSIONS.md`, and indexes.
- A rules test suite (`@firebase/rules-unit-testing`) with at least one allow test and one deny test for every rule, plus the cross-location isolation test.
- `packages/data`: a repository for each aggregate, plus a batch builder for each operation in the sync doc §2, including summary increments and audit docs.
- Device registration transaction, counter store (Hive), and the sync-health ledger and pass (sync doc §3, §6).
- Seed script: roles, one admin user, locations PTB and MNJ, 10 sample products, 5 raw materials.
- **Done when:** rules tests are green on the emulator, and a Dart integration test creates a bill, return and cancellation on the emulator with the summaries correct.

### POS app — `apps/pos/`
- Riverpod + go_router, Material 3, designed for a phone held in portrait at the counter.
- Screens: Login → Device setup → Billing (the home screen: product grid with search and categories, cart) → Payment (split) → Receipt preview / print → Bills list (reprint, cancel, return) → Stock (operations, low-stock list, thresholds) → Suggest product → Day summary → Sync health.
- Offline banner, billing block and PIN override (sync doc §7).
- Uses only `packages/data` for writes and `packages/printer` for printing.
- **Done when:** widget tests cover the billing flow, and the app builds a debug APK.

### Printer — `packages/printer/`
- `ReceiptDocument` (header, lines, totals, payments, footer, optional GST block) → ESC/POS bytes, for 48 and 32 columns.
- Bluetooth Classic transport: scan for paired devices, connect, print, handle reconnects, with Android 12+ permissions. Remember the chosen printer for each device.
- Receipt layout per BRD §4.1 and D-010, D-013. Also a plain-text renderer, used for the preview screen and for golden tests.
- **Done when:** golden tests pass for a normal bill, a discounted and split bill, a return slip, and 58/80 mm. A small test-print screen is ready for Bicy to run on the real printer.

### Admin web — `apps/admin/`
- Flutter Web, with a responsive side-nav layout.
- Screens: Login, Dashboard (today across locations, low stock), Locations, Users, Devices, Catalog (including the approval queue), Raw materials, Stock by location, Reports (daily/monthly/annual, filtered by location or all), Expenses, Financials, Audit log.
- Creating users through a secondary Firebase App (D-018).
- **Done when:** widget tests pass for reports aggregation and the catalog approval, and `flutter build web` succeeds.

### QA — `test/e2e/`
- Writes tests **from the contracts, not from the implementation**, starting on day 3.
- Scenario matrix: two devices billing offline at the same location, kill mid-batch, duplicate submit, return beyond sold qty, cancel on the next day (denied), cross-location access (denied), disabled user's queued writes, summary equals the sum of the docs, and stock totals after concurrent PRODUCE and SALE.
- Reviews every agent's branch before merge, and files defects as issues in `docs/QA-FINDINGS.md`.

### Central
- Phase 0: these docs plus `packages/core`.
- During Phase 1: answer change requests within the same working session, and keep `00-DECISIONS.md` current.
- Phase 2: merge, run all suites, fix integration gaps, and prepare the release APK and a setup guide for Bicy (Firebase project, seed, install).

## What Bicy must do
1. Create the Firebase project (Spark plan), enable Email/Password Auth and Firestore (region `asia-south1`, Mumbai), and share the web config.
2. Grant push access to this repo, if it isn't set up already.
3. Phase 3: install the APK, pair the thermal printer, and run the test-print screen.
