# Admin Web Agent Brief

**You own:** `apps/admin/`
**Branch:** `agent/admin`
**Read first:** `docs/agents/README.md`, then `01-MVP-SCOPE` (the Admin web section), `00-DECISIONS` (D-014, D-018), `02-DATA-MODEL` (summaries), `04-PERMISSIONS`, and the `packages/data` API in `lib/src/api/`.

## What you deliver
The Flutter Web console the Admin uses from a laptop. It is online only (03-SYNC §9) and uses **only** the `nexus_data` interfaces.

## Tasks, in order
AD-1 shell → AD-2 dashboard → AD-8 reports → AD-6 catalog → AD-3 locations → AD-4 users → AD-5 devices → AD-7 stock → AD-9 expenses → AD-10 financials → AD-11 audit log.

Build against fakes of the `nexus_data` interfaces until the real implementations are merged, and make them switchable at startup (`--dart-define=FAKE_DATA=true`).

## Screens and rules
- **Layout:** responsive side nav, and a location switcher in the top bar: "All locations" or a single one.
- **Reports** read summary docs only (D-014), never bills. "All locations" adds up the per-location summaries with `Summary.+`. Show gross, discount, net, returns, cancellations, net revenue (`Summary.netRevenue`), by payment mode, and top products. Daily, monthly and annual views; annual is the sum of its 12 monthly summaries.
- **Financials:** `Summary.profit` per month and location. Expenses come from the monthly summary.
- **Catalog:** an approval queue for PENDING suggestions. Approving sets the price. A price change is audited by the data layer.
- **Locations:** the override PIN is entered twice and passed to `LocationService.save(newPin:)`. Never display or store it yourself.
- **Users:** create a Store Manager with `UserService.createStoreManager`, which keeps the Admin signed in (D-018). Disabling asks for confirmation.
- **Audit log:** filters by location, user, action and date range, with a before/after diff.
- **Money** is shown with `Money.format()`, and dates are IST.
- **Permissions:** gate screens with `session.can(...)`, never role names.

## Suggested packages
`flutter_riverpod`, `go_router`, `firebase_core`, `intl`, and a chart library if one earns its place (`fl_chart`). In tests: `mocktail`.

## Done when
- Unit tests cover report aggregation: several locations combined, and a year from 12 months, both matching hand-computed totals.
- Widget tests cover the catalog approval flow and every screen.
- `flutter build web` succeeds.
