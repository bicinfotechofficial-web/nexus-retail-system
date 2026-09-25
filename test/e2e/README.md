# End-to-end scenarios

Owner: QA. Scenario tests are written from the contracts in `docs/`, not from the implementation. The scenario list, with layers and dependencies, is in [PLAN.md](PLAN.md); open contract issues are in `docs/QA-FINDINGS.md`.

This package is pure Dart and depends only on `nexus_core`.

- `test/summary_reconciliation_test.dart`: QA-5, the summary-equals-the-documents property (PLAN P-01), with a fixed seed. `test/support/shop_sim.dart` models what the batches write until the backend's `WritePlan` builders land.

Run it with `dart test` in this directory. `tool/check.sh` skips this package; `tool/check.sh --e2e` runs it together with the emulator suites (C-4).
