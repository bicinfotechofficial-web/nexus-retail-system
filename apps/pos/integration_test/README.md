# Device scenarios (QA-2, QA-3, QA-4, QA-6)

End-to-end scenarios from `test/e2e/PLAN.md` that need the real Firestore SDK with offline persistence, so they run on an Android emulator against the Firebase emulator. QA owns this folder.

| File | PLAN scenarios |
|---|---|
| `qa2_offline_billing_test.dart` | A1-1 (two devices, 20 + 20 offline bills, sync), A1-2 (both sell the last piece) |
| `qa3_kill_and_retry_test.dart` | A2-2 (kill after the local commit), A2-3 (restart with a queue), A2-4 (the same plan applied twice, for a bill, cancel, return, stock in and adjust, with and without a restart) |
| `qa4_denied_paths_test.dart` | C-2 (next-day cancel, online and offline), M-6 (over-return on the device), A1-7 (two offline returns past the sold qty), A3-4 (another location through the SDK), S8-2 / S6-2 (a user disabled while offline) |
| `qa6_concurrent_stock_test.dart` | S5-4 (concurrent PRODUCE, SALE and ADJUST, synced in either order) |

## How they work
- **Two devices** are two named `FirebaseApp`s in one process, each with its own Firestore instance, persistence, counter store and sync ledger. **Offline** is `disableNetwork()` / `enableNetwork()` on that instance. **A kill** is `terminate()` and reopening the same app on the same persistence.
- The scenarios use the devices only through the `nexus_data` interfaces. They get them from `support/backend.dart`, the one file that knows about the backend's implementations.
- The harness seeds the emulator and checks results directly over the emulators' REST APIs with the `owner` token, which bypasses the rules (`support/emulator.dart`, `support/fixtures.dart`). After each scenario it checks the stock oracle (every `qty` equals the sum of its movement deltas) and the summary oracle (each daily and monthly summary equals `SummaryDeltas` over that period's bills, cancellations and returns) in `support/oracle.dart`.

## Status
Every scenario is **skipped** with `waits for BE-10/11/12`. The Firestore implementations aren't merged yet, and `openDevice` in `support/backend.dart` throws `UnimplementedError`. To enable them:
1. Implement `openDevice` and `TestDevice` in `support/backend.dart` with the backend's classes. Besides the services, a device needs `goOffline` / `goOnline` (network toggle), `restart` (terminate and reopen on the same persistence, counter store and ledger), and `reapplyLastPlan` (apply the last `WritePlan` again through the same adapter, D-027).
2. Point each app's Firestore and Auth at the emulator in `openDevice`. The Auth emulator is plain HTTP, and Android 9+ blocks cleartext traffic unless the debug build allows it (`android:usesCleartextTraffic="true"` in `android/app/src/debug/AndroidManifest.xml`, owned by the POS agent).
3. Set `backendSkip` to `null` in `support/backend.dart`. Before that, `--dart-define=RUN_DEVICE_SCENARIOS=true` runs them anyway.

## Running them (Windows, Git Bash)
You need an Android emulator (API 28 or newer) that is running and shows up in `flutter devices`, plus Node, Java 21 and the Firebase CLI from docs/SETUP-FIREBASE.md.

Terminal 1, from the repo root. This starts the Firestore and Auth emulators for `demo-caramel-cottage`:

```bash
cd firebase
firebase emulators:start --only firestore,auth --project demo-caramel-cottage
```

Terminal 2, from the repo root:

```bash
cd apps/pos
flutter test integration_test --dart-define=USE_EMULATOR=true
```

To run a single file, name it, for example `flutter test integration_test/qa6_concurrent_stock_test.dart --dart-define=USE_EMULATOR=true`. With more than one device attached, add `-d emulator-5554` (the ID from `flutter devices`).

The Android emulator reaches the host's Firebase emulator at `10.0.2.2`, which is the default. For a physical phone on the same Wi-Fi network, start the emulators with `"host": "0.0.0.0"` for Firestore and Auth (a local change to `firebase/firebase.json`, not committed), and add `--dart-define=EMULATOR_HOST=<the PC's LAN IP>`.

Each scenario **empties the emulator** (all documents and Auth users) before seeding it. Don't point the tests at an emulator whose data you want to keep. They refuse to start without `USE_EMULATOR=true`, and they always use the `demo-caramel-cottage` project ID, so they can't reach the real project.

`tool/check.sh` doesn't run these, because it has no device. It only analyses them, and `flutter analyze` must stay clean.
