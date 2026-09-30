/// Test support for the device scenarios (QA-043): the full `nexus_data`
/// stack on a **named** `FirebaseApp` pointed at the Firebase emulators,
/// with the per-device hooks the scenarios need. For `integration_test`
/// only; the apps never import it.
///
/// ## What a [NexusTestDevice] is
/// One simulated POS install: `NexusBackend.firebase` on its own named app,
/// with Firestore persistence on (100 MB cache), its own Hive boxes for the
/// counter store, `lastSyncAt`/override end and the sync ledger (named
/// after the app), its own saved Auth session, and a manual network monitor
/// in place of `connectivity_plus`. Services are the real ones:
/// `FirebaseAuthService`, `FirestoreDeviceService`, `FirestoreSalesService`,
/// `FirestoreStockService`, the repositories, `FirestoreSyncService` and
/// `LocalOfflineGuard`.
///
/// ## Hooks
/// - `goOffline()` / `goOnline()`: `disableNetwork()` / `enableNetwork()`
///   on the device's Firestore instance, plus the sync service's network
///   monitor (so `sync.status` says Offline). Going online starts a sync
///   pass by itself, as a real reconnect does; `sync.syncNow()` waits for it
///   and runs one more, so every earlier write is covered. Firebase Auth has
///   its own connection: sign in while online.
/// - `restart()`: stops the services, closes the Hive boxes, `terminate()`s
///   Firestore, and reopens the same app on the same persistence, boxes and
///   saved session, in the same network state. The restored session does
///   not move `lastSyncAt`. Use the returned device.
/// - `reapplyLastPlan()`: commits the last `WritePlan` again through the
///   same committer and adapter, and into the ledger. When the server
///   rejects it straight away (online, first copy already there) that is
///   swallowed, as it is the expected outcome.
/// - `dispose()`: stops everything, terminates Firestore and deletes the
///   app. A device replaced by `restart()` is already disposed.
///
/// ## Wiring `apps/pos/integration_test/support/backend.dart`
/// ```dart
/// import 'package:firebase_core/firebase_core.dart';
/// import 'package:nexus_data/testing.dart';
///
/// import 'emulator.dart';
///
/// const String? backendSkip = null;
///
/// typedef TestDevice = NexusTestDevice;
///
/// Future<TestDevice> openDevice(
///   FirebaseApp app, {
///   required EmulatorTarget target,
///   bool freshInstall = true,
/// }) => NexusTestDevice.open(
///   app,
///   target: EmulatorHost(
///     host: target.host,
///     firestorePort: target.firestorePort,
///     authPort: target.authPort,
///   ),
///   freshInstall: freshInstall,
/// );
/// ```
/// `NexusTestDevice` has every member the scenarios' `TestDevice` has (with
/// `auth` typed as `FirebaseAuthService`, an `AuthService`), plus `backend`
/// for everything else (`offlineGuard`, `ledger`, `syncState`, ...).
///
/// With `freshInstall` (the default) the app's persistence
/// (`clearPersistence()`), Hive boxes and saved session are wiped first;
/// call it before the app's Firestore instance is used for anything else.
/// The debug manifest must allow cleartext traffic for the Auth emulator
/// (QA-043 (a), POS agent).
library;

export 'src/testing/test_device.dart';
