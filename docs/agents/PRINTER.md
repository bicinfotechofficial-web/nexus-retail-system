# Printer Agent Brief

**You own:** `packages/printer/`, except `lib/src/api.dart`, which is the contract you implement.
**Branch:** `agent/printer`
**Read first:** `docs/agents/README.md`, then `00-DECISIONS` (D-010, D-013, D-020), BRD §4.1 in `docs/requirements/BRD-v4.md` (receipt contents), and the `Bill`, `SaleReturn` and `Location` models in `packages/core`.

## What you deliver
An implementation of `PrinterService` (`lib/src/api.dart`) that turns a saved bill or return into a thermal receipt and sends it to a Bluetooth printer. The POS app calls only `PrinterService`. `ReceiptDocument`, the layout engine and the encoder are internal to your package.

## Tasks, in order
PR-1 → PR-2 → PR-3 → PR-4 → PR-5, with PR-6 (goldens) alongside PR-3. You are the riskiest track because of the hardware, so start immediately.

## Receipt content (BRD §4.1)
Location name, address and phone · bill number · date and time (IST) · lines (name, qty × price, line total) · subtotal · discount (flat or %, when present) · round-off (its own line, D-010) · total, in double height · payments, one line per mode, with cash tendered and change when present · GST block **only when `taxLines` is non-empty** (D-013) · served by · the location's `receiptFooter`. A cancelled bill prints a "CANCELLED" banner. A reprint says "REPRINT". A return slip shows the original bill number, returned lines, refund total and refund modes.

## How to build it
- **Plain text first.** PR-2's layout engine produces lines of exactly `PaperWidth.columns` characters, and `previewBill`/`previewReturn` return that text. Golden tests compare it; the ESC/POS encoder (PR-3) only adds commands around the same lines.
- **Money** comes from `Money.format()`, which uses Indian grouping (`₹1,23,456.00`). If the printer's code page has no ₹ glyph, fall back to `Rs.` (PR-3).
- **Width:** 80 mm (48 columns) is the default (D-020); 58 mm (32 columns) is a per-device setting. The pilot printer's model isn't known yet (B-4), so keep the transport free of any model-specific commands.
- **Long product names** wrap onto the next line. Amounts stay right-aligned.
- **Transport (PR-4):** Bluetooth Classic SPP. Handle Android 12+ permissions (`BLUETOOTH_CONNECT`, `BLUETOOTH_SCAN`) and older ones. Write in chunks, with a timeout and one reconnect attempt, and remember the chosen printer per device. Put the transport behind an interface so tests use a fake.
- **A failed print returns `PrintFailed`, never throws.** The bill is already saved.

## Suggested packages
A maintained Bluetooth Classic plugin that supports SPP on Android 12+. Evaluate `print_bluetooth_thermal` first, and record your choice and why in the PR-4 commit message. Also `permission_handler` and `shared_preferences`. Use `esc_pos_utils_plus` only if it saves real work; a small hand-written encoder is fine.

## Done when
- Goldens pass for: a normal bill, a discounted split-payment bill, a return slip, a cancelled-bill reprint, each at 58 mm and 80 mm.
- The encoder has byte-level golden tests.
- The transport works against a fake in tests.
- A test-print screen widget (PR-5) is ready for Bicy to run on the real printer (B-6).
