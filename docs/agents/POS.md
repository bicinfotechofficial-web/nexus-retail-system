# POS App Agent Brief

**You own:** `apps/pos/`
**Branch:** `agent/pos`
**Read first:** `docs/agents/README.md`, then `01-MVP-SCOPE`, `00-DECISIONS`, `03-SYNC-AND-OFFLINE` (§6–8 drive the UI), `04-PERMISSIONS`, the `packages/data` API in `lib/src/api/`, and the printer API in `packages/printer/lib/src/api.dart`.

## What you deliver
The Android app a Store Manager uses at the counter: phone, portrait, one hand. It uses **only** the `nexus_data` interfaces for data and `PrinterService` for printing. It never imports `cloud_firestore` directly.

## Tasks, in order
POS-1 shell → POS-4 billing → POS-5 payment → POS-6 print → POS-7 bills list → POS-8 returns → POS-9 stock → POS-11 day summary → POS-12 offline → POS-2 login → POS-3 device setup → POS-10 suggest.

Build against fakes of the `nexus_data` and `nexus_printer` interfaces until the real implementations are merged; they have the same signatures. Write the fakes in your own test and dev code, and make it switchable at startup (`--dart-define=FAKE_DATA=true`) so the app also runs without Firebase.

## Screens and rules
- **Billing is the home screen:** product grid by category, search, and a cart with qty ± and remove. Totals come from `BillCalculator.compute` live, never your own arithmetic.
- **Payment:** flat or % discount, capped by the location's `maxDiscountPct`. Show the round-off line, a split-payment editor with up to 4 rows, and cash tendered with change. Drive **Save** from `BillCalculator.checkPayments(...).isValid`. **Save disables on the first tap** (03-SYNC §4), calls `SalesService.createBill` once, then prints.
- **Print failure:** the bill is saved already, so show a retry, not an error.
- **Cancel:** same day only. Hide or disable it when `cancelBlocker(bill, today)` isn't null, and say why.
- **Returns:** quantities are capped with `ReturnCalculator.returnable(bill)`, the refund total comes from `ReturnCalculator.compute`, and the refund split must match it.
- **Stock:** show negative quantities in red. Keep one screen per operation. Adjust takes a physical count.
- **Sync chip** in the app bar: ● Online / ◐ Syncing (n) / ○ Offline since HH:MM, from `SyncService.status`.
- **Offline:** an amber banner on `NearLimit`, and a blocking screen for billing only on `BillingBlocked`, with Retry sync and Admin PIN override. Stock operations and viewing keep working.
- **Permissions:** show an action only when `session.can(permission)` is true. Never check role names (D-017).
- **Theme:** Material 3, Caramel Cottage colours (warm caramel primary on a cream background), large tap targets.

## Suggested packages
`flutter_riverpod`, `go_router`, `firebase_core` (only to call `Firebase.initializeApp` with `DefaultFirebaseOptions`), `intl` for time formatting. In tests: `mocktail`, `fake_async`.

## Done when
- Widget tests cover the whole billing flow: cart → discount → split payment → save → print, including a sum mismatch blocking Save and a double tap saving once.
- Every screen has a widget test.
- `flutter build apk --debug` succeeds.
