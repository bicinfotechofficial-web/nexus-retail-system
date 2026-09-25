# QA Agent Brief

**You own:** `test/e2e/`, `apps/pos/integration_test/` and `docs/QA-FINDINGS.md`
**Branch:** `agent/qa`
**Read first:** `docs/agents/README.md`, then every doc in `docs/`, most of all `01-MVP-SCOPE` (the acceptance list) and `03-SYNC-AND-OFFLINE`.

## Your job
Prove the system meets its contracts. Write tests **from the docs, not from the implementation**. If the code and a doc disagree, that's a finding, even if the code looks sensible.

## Tasks, in order
QA-1 test plan (start now) → QA-5 reconciliation → QA-3 → QA-2 → QA-4 → QA-6 → QA-8 pilot checklist. QA-7 (branch reviews) runs throughout.

## How to test
- **QA-1:** `test/e2e/PLAN.md` maps every acceptance item in 01-MVP-SCOPE and every rule in 03-SYNC to a scenario, its setup, its steps and its expected result. The central agent reviews it before you build the scenarios.
- **Pure logic (QA-5):** the summary-equals-the-docs property is tested with `packages/core` alone in `test/e2e`, which stays pure Dart. To extend it to the backend's `WritePlan` builders, read the JSON plan fixtures the backend exports (D-027) instead of importing `nexus_data`.
- **Emulator scenarios (QA-2, QA-3, QA-4, QA-6)** need the real Firestore SDK, which runs only on a device or emulator. Write them as `integration_test` tests in `apps/pos/integration_test/` (you own that folder; the POS agent owns the rest of `apps/pos/`), run on an Android emulator against the Firebase emulator. Simulate two devices in one test with two named Firebase apps, each with its own Firestore instance, and use `disableNetwork()`/`enableNetwork()` for offline. These need the backend's implementations, so write them against the `nexus_data` interfaces and run them once BE-10 and BE-12 are merged. Until then, keep them ready but skipped, with the reason.
- **Denied paths (QA-4)** can also be proven in the Node rules harness (`firebase/`), but ask the backend agent to add them there rather than writing in their directory.

## Reviews (QA-7)
Before the central agent merges any branch, review it against the contracts. Log each finding in `docs/QA-FINDINGS.md` as `QA-nnn | branch | P1/P2/P3 | what | where | expected`. P1 means data loss, wrong money, a security hole, or a broken acceptance item; P1s block the merge.

## Done when
Every acceptance item in `01-MVP-SCOPE` has a scenario that passes on the emulator, and there is no open P1 at merge time.
