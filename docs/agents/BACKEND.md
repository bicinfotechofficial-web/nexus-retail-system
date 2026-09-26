# Backend Agent Brief

**You own:** `firebase/` and `packages/data/`, except `packages/data/lib/src/api/`, which is the contract you implement.
**Branch:** `agent/backend`
**Read first:** `docs/agents/README.md`, then `00-DECISIONS`, `02-DATA-MODEL`, `03-SYNC-AND-OFFLINE`, `04-PERMISSIONS`, and the public API of `packages/core` (`lib/nexus_core.dart`).

## What you deliver
1. **Firestore security rules** that enforce every item in `04-PERMISSIONS.md`, with a Node test suite on the emulator.
2. **`packages/data`**: Firestore implementations of every interface in `lib/src/api/`, plus the counter store, device registration, sync pass and offline guard.
3. **A seed script** for the pilot.

## Tasks, in order
Task details and done checks are in `06-TASKS.md`.

| Track | Tasks |
|---|---|
| Rules | BE-1 harness → BE-2 → BE-3 → BE-4 → BE-5 → BE-6 → BE-7 indexes |
| Data | BE-8 counters → BE-9 registration → BE-10 batch builders → BE-11 repositories → BE-12 sync → BE-13 offline guard |
| Seed | BE-14, after BE-5 |

Run the Rules and Data tracks side by side. BE-10 is on the critical path, because the POS payment screen (POS-5) needs it, so push it for review as soon as it's green.

## How to build it
- **Batch builders produce a plan, not a batch.** Each operation in 03-SYNC §2 is a pure function that returns a `WritePlan`: an ordered list of `{path, kind: create | update | setMerge, data}`, with increments and server timestamps as sentinel values. It uses `BillCalculator`, `ReturnCalculator`, `SummaryDeltas`, `Ids` and `FirestorePaths` from core, and contains no Firestore types. A thin adapter turns a plan into a `WriteBatch`. This makes every business rule unit-testable with plain `flutter test`.
- **Plan fixtures (D-027):** a Dart test writes one JSON file per plan type to `firebase/test/fixtures/plans/<name>.json`, as `{"uid": "...", "ops": [{"path": "...", "kind": "create|update|setMerge", "data": {...}}]}`. Sentinels are `{"__op": "increment", "by": n}` and `{"__op": "serverTimestamp"}`, and `DateTime` values are ISO-8601 strings with `{"__op": "timestamp"}` wrapping. Commit the fixtures: QA's pure-Dart tests read them too.
- **Prove the rules accept the plans.** Have a Dart test export a JSON fixture for each plan type (bill, cancel, return, each stock operation, expense create/edit). Your Node rules suite applies each fixture to the emulator as the right user and asserts it's accepted, plus the tampered variants that must be denied. This covers BE-10's "every batch is accepted by the rules" check.
- **Summaries:** use `SummaryDeltas.increments()` for the field paths and set `lastWriteRef` to the new doc's path, which rule #9 checks.
- **Timestamps:** models carry `DateTime`. Convert Firestore `Timestamp` values to `DateTime` before calling `fromMap`, and fill each model's `serverTimestampFields` with `FieldValue.serverTimestamp()`.
- **Counters (BE-8):** allocate, persist and flush, and only then build the plan (03-SYNC §3). Test that killing the app after allocation skips a number rather than reusing one.
- **Rules budget:** the largest batch (a return) must stay within the 10 `get()` calls allowed per evaluation, which BE-6 tests. Keep the helper `get()`s to `me()` and `role()`.
- **Offline override PIN:** PBKDF2-SHA256, 100k iterations, stored as `salt$hash` in base64 (02-DATA-MODEL).

## Suggested packages
`firebase_core`, `cloud_firestore`, `firebase_auth`, `hive_ce` + `hive_ce_flutter` for the counter store and ledger, `cryptography` for PBKDF2, `connectivity_plus`. In tests: `mocktail`, `fake_async`. For rules tests in `firebase/`: `@firebase/rules-unit-testing`, `vitest` or `jest`, with `npm test` running the suite against a running emulator. `tool/check.sh --e2e` calls that.

## Done when
- The rules suite is green on the emulator, with at least one allow and one deny test per rule, plus the cross-location suite.
- Every plan builder has unit tests, including exact summary values, and every plan type is accepted by the rules as a fixture.
- Every interface in `src/api/` has an implementation exported from `nexus_data.dart`.
- The seed script is idempotent: running it twice changes nothing.
