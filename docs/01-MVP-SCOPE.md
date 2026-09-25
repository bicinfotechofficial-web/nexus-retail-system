# MVP Scope — Pilot Release

**Target:** one pilot store (Pattambi or Manjeri), with Android POS devices and the admin web console.
**Baseline:** Caramel Cottage BRD v3. Deviations are listed in `00-DECISIONS.md`.

## In scope

### POS app (Android)
- Login, and device registration on first run
- Catalog browsing and a cart. Bill-level discount (flat or %), round-off, split payment (Cash, UPI, Card, Wallet, Other)
- Bill saved offline-first, then printed on a Bluetooth thermal printer. Reprint of any past bill
- Same-day bill cancellation with a reason
- Returns against a prior bill (full or partial), with mixed refund modes
- Stock operations: Stock In (raw), Stock Out / Wastage (raw), Produce (raw consumed → finished added, multi-line), Wastage (finished), Adjust (enter a physical count)
- Low-stock thresholds per item for the SM's own location, plus an in-app low-stock list and badge
- Suggest a local special (pending until an Admin approves it)
- Offline indicator, sync-health screen, warning and block at the offline limit, Admin PIN override
- Day summary screen: today's sales, sales by payment mode, returns

### Admin web
- Locations: create and edit (code, name, address, offline limit, override PIN, discount cap)
- Users: create a Store Manager for a location, disable a user
- Catalog: products, prices, active flag, approving pending suggestions. Raw materials list
- Stock view for each location, plus a low-stock list across all locations
- Reports: daily, monthly and annual sales per location and for all locations combined. Sales by payment mode, returns, discounts, gross vs net
- Expenses: log, edit and list (rent, salaries, utilities, other) per location and date
- Financials: sales − expenses per month and location
- Audit log viewer, filterable by location, user, action and date
- Device list per location, with last seen time

## Out of scope (MVP)
- iOS build. The code stays platform-neutral, but it won't be tested or shipped
- GST calculation (the model is ready for it, see D-013)
- Year-on-year comparison UI. The data is there through the monthly summaries, and this is the first thing added after the pilot
- Push notifications, cold backup, recipe/BOM auto-deduction, store-wide bill sequence
- Multiple languages (English only)
- Barcode scanning, customer records, loyalty

## Acceptance for pilot sign-off
1. Two devices at the same location bill offline at the same time, then sync, with zero duplicate bill numbers and stock that is exactly correct.
2. Killing the app or rebooting the phone mid-bill never produces a duplicate bill or a double stock deduction.
3. A Store Manager cannot read or write another location's data (verified with rules tests, not just the UI).
4. A printed receipt matches the saved bill, as read back from the server, in every printed field: location name, address and phone; bill number; date and time; each line's name, qty, price and total; subtotal; discount; round-off; total; payments with cash tendered and change; the GST block when present; served by; and the footer.
5. The admin's daily totals equal the sum of the bills and returns for that day.
6. At the offline limit, billing is blocked, and an Admin PIN allows billing for the next 2 hours.
