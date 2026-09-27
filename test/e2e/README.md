# End-to-end scenarios

Owner: QA. Scenario tests are written from the contracts in `docs/`, not from the implementation. The scenario list, with layers and dependencies, is in [PLAN.md](PLAN.md); the manual script for the device pilot is [PILOT-CHECKLIST.md](PILOT-CHECKLIST.md); open contract issues are in `docs/QA-FINDINGS.md`.

This package is pure Dart and depends only on `nexus_core`.

- `test/summary_reconciliation_test.dart`: QA-5, the summary-equals-the-documents property (PLAN P-01), with a fixed seed. It also checks the list limits (D-030), `soldQty`, `returnedQty ≤ soldQty` and "a bill with a return is never cancelled" across conflicting offline cancels and returns (D-029). `test/support/shop_sim.dart` models what the batches write, and a rules model of 04-PERMISSIONS #5–6.
- `test/plan_fixtures_test.dart`: QA-5 through the backend's `WritePlan` JSON fixtures in `firebase/test/fixtures/plans/` (PLAN P-03). `test/support/plan_store.dart` applies them to an in-memory store with Firestore's write semantics; the summaries must equal the docs, and every op is checked against 03-SYNC §2 and 02-DATA-MODEL.
- `test/pin_hash_parity_test.dart`: the override PIN hash is byte for byte the same in the Dart `PinHasher` (as exported in the location fixtures) and in `firebase/scripts/lib/core.js` (runs `node`, PLAN C-4).
- `test/concurrent_returns_test.dart`: the D-029 conflict cases worked by hand (PLAN A1-6, A1-7, A1-8), including two offline returns within `soldQty`, where the rule on `prevReturnId` rejects the stale one (QA-024).

Run it with `dart test` in this directory. `tool/check.sh` skips this package; `tool/check.sh --e2e` runs it together with the emulator suites (C-4).
