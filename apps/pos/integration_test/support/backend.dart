// The one seam between the device scenarios and the backend's Firestore
// implementations (BE-10 to BE-12). Every scenario gets its services from
// `openDevice` below and nowhere else, so wiring in the real
// implementations is a change to this file only.
//
// Until those implementations are merged, `openDevice` throws and every
// scenario is skipped with [backendSkip].

import 'package:firebase_core/firebase_core.dart';
import 'package:nexus_data/nexus_data.dart';

import 'emulator.dart';

/// Why the device scenarios are skipped.
const String backendPending = 'waits for BE-10/11/12';

/// The `skip:` value of every scenario in `integration_test/`. While the
/// implementations are being wired in, `--dart-define=RUN_DEVICE_SCENARIOS=true`
/// runs the scenarios anyway; once BE-10 to BE-12 are merged and
/// [openDevice] is implemented, make this null.
const String? backendSkip = bool.fromEnvironment('RUN_DEVICE_SCENARIOS')
    ? null
    : backendPending;

/// One simulated POS install: a named [FirebaseApp] with its own Firestore
/// instance, local persistence, counter store and sync ledger, and the
/// `nexus_data` services built on them.
///
/// Two devices in one test are two [TestDevice]s on two named apps. They
/// share nothing but the emulator.
abstract interface class TestDevice {
  /// The named app this device runs on.
  FirebaseApp get app;

  AuthService get auth;
  DeviceService get devices;
  SalesService get sales;
  SalesRepository get salesRepo;
  StockService get stock;
  StockRepository get stockRepo;
  SummaryRepository get summaries;
  SyncService get sync;

  /// `disableNetwork()` on this device's Firestore instance. Writes go on
  /// being committed to the local cache and queue for the server.
  Future<void> goOffline();

  /// `enableNetwork()` on this device's Firestore instance. The scenarios
  /// call `sync.syncNow()` after this, as the connectivity trigger would.
  Future<void> goOnline();

  /// A process kill and restart. Drops every service and the Firestore
  /// instance (`terminate()`), then reopens the same app on the same local
  /// persistence, counter store, ledger and saved session, and rebuilds
  /// the services, as a cold start would. The restarted device is in the
  /// same network state (offline stays offline). Its queued writes are the
  /// ones the SDK kept in its persistence; nothing is re-submitted by hand.
  Future<TestDevice> restart();

  /// Applies the last `WritePlan` this device committed (a bill, a cancel,
  /// a return or a stock operation) a second time, unchanged, through the
  /// same plan-to-batch adapter, as a retry after a crash or a duplicate
  /// submit would (03-SYNC §4, D-027). Same doc IDs, same increments. It
  /// goes into the ledger like any write.
  Future<void> reapplyLastPlan();

  /// Stops listeners and deletes the app.
  Future<void> dispose();
}

/// Opens a device on [app] against the emulator in [target].
///
/// With [freshInstall] (the default) the device starts as a new install:
/// its local persistence (`clearPersistence()`), counter store, ledger and
/// saved session are wiped first. The implementation must point this app's
/// Firestore at `target.host:target.firestorePort` and its Auth at
/// `target.host:target.authPort` before first use, with persistence on,
/// and key the counter store and ledger by `app.name` so two devices in one
/// process don't share them.
///
/// The device is signed out and unregistered; scenarios sign in with
/// `auth.signIn` and register with `devices.register`.
Future<TestDevice> openDevice(
  FirebaseApp app, {
  required EmulatorTarget target,
  bool freshInstall = true,
}) {
  throw UnimplementedError(backendPending);
}
