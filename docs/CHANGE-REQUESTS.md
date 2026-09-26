# Change Requests

Build agents add requests here. The central agent decides each one and records the outcome in `00-DECISIONS.md`.

| ID | Raised by | Contract section | Problem | Options | Decision |
|---|---|---|---|---|---|
| CR-001 | Backend (BE-3) | 04-PERMISSIONS budget note, #5(b), #6; D-030 | The access-call budget isn't the only limit. Firestore also stops a rule evaluation after **1000 evaluated expressions** (per document, not shared across a batch; measured on the emulator), and unrolled per-line checks use it up fast: about 20–35 per entry, plus about 250–450 fixed. Measured with the BE-3 rules: the largest bill (20 lines, 4 payments) uses about 870 of 1000, and the largest return update (a bill whose 20 products all end up in `returnedQty`) about 920. To fit, the rules check only what #6 lists per line and payment (`soldQty` per line, the payment sum); line arithmetic, positive quantities and payment modes and signs are left to `BillCalculator`, like D-031. Headroom on the return update is about 8%, and nobody guarantees production counts exactly like the emulator. | (a) Accept as is: BE-6 tests both maximum cases, so a change in counting fails CI. (b) Lower the per-bill product cap for returns, e.g. 15 lines per bill (about 25% headroom on both). (c) Keep 20, but drop the per-line `soldQty` check at bill create (then `soldQty` is trusted like the summaries; it only needs to be honest for D-029's conflict rule), which leaves the bill at about 45%. Backend suggests (a) now, and (b) if BE-6 or the pilot shows the return near the limit. | |

## Review notes from the central agent
Answers to questions raised in agent reports.

- **PR-1 (Printer):** all four choices confirmed. (1) The round-off line always prints, ₹0.00 included (D-010). (2) The cancel reason prints with the CANCELLED banner. (3) The GSTIN prints only inside the GST block. (4) Return slips have no "served by" line.
- **AD-2 / AD-8 (Admin):** the headline "Sales" figure is net revenue (`Summary.netRevenue`); see QA-013 and 02-DATA-MODEL summaries. Keep the round-off line in reports. Store Managers may keep read access to their own location's dashboard and reports.
- **BE-1 (Backend):** vitest 4 confirmed, to stay on Node 20. The rules contract in 04-PERMISSIONS was revised after the QA review (D-028 to D-031): BE-2 to BE-6 build against the new version, and the fixtures need `soldQty` on bills.
- **POS-5 (POS):** the double-tap flag and the "may have been saved, check today's bills first" handling of unknown failures are right. The new `BillError.tooManyLines` case is in `apps/pos/lib/app/messages.dart`, added at merge.
