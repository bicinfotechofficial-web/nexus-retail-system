# Task Breakdown

Each task has an owner, the tasks it depends on, a size (S ≤ half a day, M ≈ 1 day, L ≈ 2 days of agent work plus review) and a check that decides when it is done.
Status: `TODO` / `WIP` / `REVIEW` / `DONE` / `BLOCKED`. Agents update only the status column of their own rows. The central agent owns everything else in this file.

---

## Owner (Bicy)
| ID | Task | Needs | Done when | Status |
|---|---|---|---|---|
| B-1 | Review and approve the Phase 0 docs, and answer the Proposed decisions (D-003, D-007, D-008, D-009, D-010, D-020) | — | Every Proposed row is Locked or changed | DONE |
| B-2 | Create the Firebase project on the Spark plan: Auth Email/Password, Firestore **Standard** edition in `asia-south1`, a registered web app | — | Web config shared with the central agent (see `FIREBASE-PROJECT.md`) | DONE |
| B-3 | Install on your machine: Flutter SDK (stable), Android Studio + SDK, Node 20+, Java 21, Firebase CLI, FlutterFire CLI (see `docs/SETUP-FIREBASE.md` §1) | — | `flutter doctor` shows no errors for Android | DONE |
| B-4 | Send the pilot printer's model name and paper width | — | Recorded in D-020 | TODO |
| B-5 | Run `flutterfire configure` in `apps/pos` and `apps/admin`, using the commands in `docs/SETUP-FIREBASE.md` §3 | B-2, B-3, C-4 | `firebase_options.dart` committed | DONE |
| B-6 | Device pilot: install the APK, pair the printer, run the test-print screen and the pilot checklist | Phase 2 | Checklist signed off | TODO |

## Central
| ID | Task | Needs | Size | Done when | Status |
|---|---|---|---|---|---|
| C-1 | Phase 0 contracts (docs 00–05) | — | L | Committed | DONE |
| C-2 | Monorepo scaffold: pub workspace, `analysis_options.yaml`, the four workspace packages (`packages/core`, `packages/data`, `packages/printer`, `test/e2e`) and two apps as empty shells, CI script `tool/check.sh` (boundaries, format, analyze, test) | B-1 | S | `tool/check.sh` passes on an empty scaffold | DONE |
| C-3 | `packages/core`: enums, models with `toMap`/`fromMap` for every collection in 02-DATA-MODEL, `Money` (paise), `FirestorePaths`, permission constants, `BillCalculator` (subtotal, discount, round-off, payment validation), `ReturnCalculator` (proration, max returnable), `BusinessDate` (IST), plus `SummaryDeltas` (the summary increments for each operation) | C-2 | L | ≥ 95% line coverage on the calculators. Every rounding edge case is tested | DONE |
| C-4 | Firebase wiring: `firebase/firebase.json`, `.firebaserc`, emulator config (demo project), placeholder rules and indexes, and the setup guide for B-5 (`docs/SETUP-FIREBASE.md`) | B-2, C-2 | S | `firebase emulators:start` runs locally | DONE |
| C-5 | Launch Phase 1 agents with their briefs and task IDs: data and printer API contracts (D-026), shared rules and briefs in `docs/agents/` | C-3 | S | All agents WIP | WIP |
| C-6 | Handle change requests and keep 00-DECISIONS current | ongoing | — | CHANGE-REQUESTS has no open row older than one working session | TODO |
| C-7 | Integration: merge the agent branches, fix the seams, run every suite | Phase 1 | L | All suites green on `main` | TODO |
| C-8 | Release build: signed release APK, admin web build, pilot setup guide (seed, first admin login, device registration, printer pairing) | C-7 | M | APK and guide delivered to Bicy | TODO |
| C-9 | BRD v4: fold in D-003 and every other deviation | B-1 | S | `docs/requirements/BRD-v4.md` committed | DONE |

## Backend — `firebase/`, `packages/data/`
| ID | Task | Needs | Size | Done when | Status |
|---|---|---|---|---|---|
| BE-1 | Rules test harness (Node, `@firebase/rules-unit-testing`, emulator) with fixtures for Admin, SM@PTB, SM@MNJ, a disabled user and an anonymous user | C-4 | S | An example test runs green | TODO |
| BE-2 | Rules: helper functions, default deny, `roles`, `users`, `locations`, `devices` (04-PERMISSIONS #1–4) | BE-1 | M | Allow and deny tests for each rule | TODO |
| BE-3 | Rules: `bills` create, validation, cancel, returnedQty (#5–6) | BE-2 | L | Tests include a duplicate create (denied), a next-day cancel (denied) and a bad payment sum (denied) | TODO |
| BE-4 | Rules: `returns`, `movements`, `stock` with `lastMovementId` (#7–8) | BE-2 | M | Tests include a qty change without a movement (denied) | TODO |
| BE-5 | Rules: summaries with `lastWriteRef`, `auditLog`, `products`, `rawMaterials`, `expenses` (#9–12) | BE-3, BE-4 | M | Tests include a summary increment without a new doc (denied) | TODO |
| BE-6 | Cross-location isolation suite (#13) plus a test that the largest batch (a return) stays within the rules `get()` limit | BE-5 | S | Green | TODO |
| BE-7 | `firestore.indexes.json` per 02-DATA-MODEL | BE-5 | S | Deploys to the emulator | TODO |
| BE-8 | `packages/data`: a `CounterStore` (Hive) for bill, movement and return sequences, with persist-before-use and recovery from `lastBillSeq` | C-3 | M | Unit tests cover kill-after-allocate and reinstall | TODO |
| BE-9 | `DeviceRegistrationService`: a transaction on `nextDeviceNo` that creates the device doc | BE-8 | S | Emulator test: two concurrent registrations get D01 and D02 | TODO |
| BE-10 | Batch builders: `createBill`, `cancelBill`, `createReturn`, `recordMovement` (IN, OUT, WASTAGE, PRODUCE), `adjustStock`, `upsertExpense`, `setThreshold`, `suggestProduct`, `approveProduct` | C-3, BE-8 | L | Emulator tests: every batch is accepted by the rules and every summary field is exact | TODO |
| BE-11 | Read repositories: catalog, stock (with a low-stock stream), bills (paged by date), returns, summaries (day, month, year), audit (filtered), users, devices, expenses | C-3 | M | Emulator tests | TODO |
| BE-12 | `SyncService`: pending-write ledger, sync pass (03-SYNC §6), `lastSyncAt`, `lastSeenAt` throttling, a status stream (online / syncing n / offline since) | BE-10 | M | Tests with the emulator stopped and restarted | TODO |
| BE-13 | `OfflineGuard`: warn and block state, PIN verification (PBKDF2), extension, queued `OFFLINE_OVERRIDE` audit doc | BE-12 | S | Unit tests with a fake clock | TODO |
| BE-14 | Seed script: roles, one admin user, locations PTB and MNJ with PINs, 10 products, 5 raw materials | BE-5 | S | Running it twice changes nothing | TODO |

## Printer — `packages/printer/`
| ID | Task | Needs | Size | Done when | Status |
|---|---|---|---|---|---|
| PR-1 | `ReceiptDocument` model (header, meta, lines, totals, discount, round-off, payments, optional GST block, footer) plus a `ReturnSlipDocument` | 02-DATA-MODEL | S | Reviewed by the central agent | TODO |
| PR-2 | Text layout engine: 48 or 32 columns, left/right alignment, wrapping of long product names, money formatting ₹1,234.00 | PR-1 | M | Golden text tests pass | TODO |
| PR-3 | ESC/POS encoder: init, bold, double height for the total, alignment, feed, cut, plus a code-page check for the ₹ glyph with a fallback to "Rs." | PR-2 | M | Byte-level golden tests | TODO |
| PR-4 | Bluetooth Classic transport: permissions for Android 12+ and older, list paired devices, connect, write in chunks, timeout and reconnect, remember the printer | PR-3 | L | Works against a fake transport in tests. A real device is Bicy's check | TODO |
| PR-5 | `PrinterService` facade (`print(ReceiptDocument)`, status stream) plus a test-print screen widget | PR-4 | S | Widget test | TODO |
| PR-6 | Golden set: normal bill, discount + split payment, return slip, cancelled-bill reprint (a "CANCELLED" banner), 58 mm and 80 mm | PR-3 | S | Goldens committed | TODO |

## POS app — `apps/pos/`
| ID | Task | Needs | Size | Done when | Status |
|---|---|---|---|---|---|
| POS-1 | App shell: Riverpod, go_router, theme (Caramel Cottage colours), app-bar sync chip, permission-aware navigation | C-3 | M | Builds a debug APK | TODO |
| POS-2 | Login plus prefetch of the user, role, location, catalog and raw materials. Handles a disabled user | BE-11 | S | Widget tests | TODO |
| POS-3 | Device setup (first run): register, name the device, pick a printer | BE-9, PR-5 | S | Widget tests | TODO |
| POS-4 | Billing screen: product grid, categories, search, cart with qty ± and remove, running total | POS-1 | L | Widget tests | TODO |
| POS-5 | Payment screen: discount (flat or %, cap check), round-off shown, split payment editor, cash tendered and change, save → print | POS-4, BE-10 | L | Tests: sum mismatch blocks Save, and a double tap saves once | TODO |
| POS-6 | Receipt preview and print, reprint, print-failure handling (the bill is saved already, so offer a retry) | PR-5, POS-5 | S | Widget test | TODO |
| POS-7 | Bills list for today and earlier dates, bill detail, same-day cancel with a reason | BE-11 | M | Widget tests | TODO |
| POS-8 | Return flow: pick a bill, choose lines and qty (capped), refund split, print the return slip | POS-7 | M | Widget tests | TODO |
| POS-9 | Stock hub: current stock (negatives in red), Stock In, Stock Out/Wastage, Produce (multi-line), Adjust (physical count), threshold editing, low-stock list and badge | BE-10, BE-11 | L | Widget tests for each operation | TODO |
| POS-10 | Suggest a local special | BE-10 | S | Widget test | TODO |
| POS-11 | Day summary: totals, by mode, returns, cancellations | BE-11 | S | Widget test | TODO |
| POS-12 | Offline banner, billing block screen, PIN override, sync-health screen with sync errors | BE-12, BE-13 | M | Widget tests with a fake clock | TODO |

## Admin web — `apps/admin/`
| ID | Task | Needs | Size | Done when | Status |
|---|---|---|---|---|---|
| AD-1 | Shell: login, responsive side nav, location switcher (All or a single location), permission guard | C-3 | M | `flutter build web` succeeds | REVIEW |
| AD-2 | Dashboard: today's sales per location and in total, bill count, returns, low-stock count per location | BE-11 | M | Widget test | REVIEW |
| AD-3 | Locations CRUD, including setting the PIN (hashed on the client), offline limit and discount cap | BE-11 | M | Widget test | TODO |
| AD-4 | Users: create a Store Manager through the secondary Firebase App, assign a location, disable | BE-11 | M | Emulator test that the admin stays signed in | TODO |
| AD-5 | Devices list: last seen, retire | BE-11 | S | Widget test | TODO |
| AD-6 | Catalog: products CRUD, price change (audited), approval queue, raw materials | BE-10 | M | Widget tests | TODO |
| AD-7 | Stock view by location, plus a low-stock table across locations | BE-11 | S | Widget test | TODO |
| AD-8 | Reports: daily, monthly and annual. Gross, discount, net, returns, cancellations, by mode, top products. One location or all combined | BE-11 | L | Aggregation unit tests | REVIEW |
| AD-9 | Expenses: create, edit and list by location, category and month | BE-10 | M | Widget test | TODO |
| AD-10 | Financials: sales − expenses per month and location | AD-8, AD-9 | S | Unit test | TODO |
| AD-11 | Audit log viewer with filters, showing a before/after diff | BE-11 | M | Widget test | TODO |

## QA — `test/e2e/`
| ID | Task | Needs | Size | Done when | Status |
|---|---|---|---|---|---|
| QA-1 | Scenario test plan from 01-MVP-SCOPE acceptance and 03-SYNC, reviewed by the central agent | C-1 | S | `test/e2e/PLAN.md` | TODO |
| QA-2 | Two devices billing offline at the same location (two emulator clients with the network disabled), then sync. Check: no duplicate IDs and exact stock | BE-10, BE-12 | M | Green | TODO |
| QA-3 | Kill mid-batch and duplicate submit. Check: one bill and a single deduction | BE-10 | M | Green | TODO |
| QA-4 | Denied paths: next-day cancel, over-return, cross-location, a disabled user's queued writes | BE-6, BE-10 | M | Green | TODO |
| QA-5 | Reconciliation: for random bills, returns and cancels, the summary equals the sum of the docs, for each day and month | BE-10 | M | Property test green | TODO |
| QA-6 | Concurrent PRODUCE + SALE + ADJUST stock totals | BE-10 | S | Green | TODO |
| QA-7 | Review every agent branch before merge, and log findings in `docs/QA-FINDINGS.md` | ongoing | — | No open P1 finding at merge | TODO |
| QA-8 | Pilot checklist for B-6 (a device-side manual script) | Phase 2 | S | Checklist committed | TODO |

---

## Critical path
B-1 → C-2 → C-3 → BE-8 → BE-10 → BE-12 → POS-5 / POS-12 → QA-2 → C-7 → C-8 → B-6

The Printer track (PR-1…PR-6) runs in parallel from day 1 and must reach PR-5 before POS-3 and POS-6.
