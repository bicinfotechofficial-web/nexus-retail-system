import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:hive_ce/hive_ce.dart';

import '../api/device.dart';
import '../api/failures.dart';
import '../api/reports.dart';
import '../api/sales.dart';
import '../api/stock.dart';
import '../api/sync.dart';
import '../backend.dart';
import '../counters/durable_store.dart';
import '../firestore/firebase_auth_service.dart';
import '../plans/write_plan.dart';
import '../sync/connectivity.dart';
import '../sync/sync_ledger.dart';
import '../write/plan_committer.dart';

/// Where the Firebase emulators run, as seen from the device.
final class EmulatorHost {
  const EmulatorHost({
    required this.host,
    this.firestorePort = 8080,
    this.authPort = 9099,
  });

  final String host;
  final int firestorePort;
  final int authPort;
}

/// Remembers the last plan committed through it, for
/// [NexusTestDevice.reapplyLastPlan].
final class RecordingPlanCommitter implements PlanCommitter {
  RecordingPlanCommitter(this._inner);

  final PlanCommitter _inner;
  WritePlan? lastPlan;

  @override
  Future<CommittedPlan> commit(WritePlan plan) async {
    final committed = await _inner.commit(plan);
    lastPlan = plan;
    return committed;
  }
}

/// One simulated POS install for the device scenarios (QA-043): the full
/// `nexus_data` stack ([NexusBackend]) on a **named** [FirebaseApp] pointed
/// at the emulators, with its own Firestore persistence, counter store,
/// sync ledger and saved session, plus the hooks the scenarios need.
///
/// Two devices in one process are two named apps and share nothing but the
/// emulator. The local stores are Hive boxes named after the app, so a
/// [restart] finds its own.
///
/// "Network" is this app's Firestore network (`disableNetwork` /
/// `enableNetwork`) together with the sync service's network monitor, so
/// the status chip says Offline too. Firebase Auth keeps its own
/// connection: sign in while online.
final class NexusTestDevice {
  NexusTestDevice._(this.app, this.backend, this._target, this._recorder);

  final FirebaseApp app;

  /// Everything, for scenarios that need more than the getters below.
  final NexusBackend backend;
  final EmulatorHost _target;
  final RecordingPlanCommitter _recorder;
  bool _offline = false;
  bool _disposed = false;

  /// Opens a device on [app] against [target].
  ///
  /// With [freshInstall] (the default) it starts as a new install: this
  /// app's Firestore persistence (`clearPersistence()`), counter store,
  /// ledger and saved session are wiped first. Without it, the device
  /// continues from what is on disk, as a cold start would.
  ///
  /// [hiveDir] defaults to the app support directory. The device is signed
  /// out (fresh) and unregistered; sign in with `auth.signIn` and register
  /// with `devices.register`.
  static Future<NexusTestDevice> open(
    FirebaseApp app, {
    required EmulatorHost target,
    bool freshInstall = true,
    String? hiveDir,
  }) => _open(
    app,
    target: target,
    fresh: freshInstall,
    offline: false,
    hiveDir: hiveDir,
  );

  static String _prefix(FirebaseApp app) =>
      'qa-${app.name.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '-')}-';

  static Future<NexusTestDevice> _open(
    FirebaseApp app, {
    required EmulatorHost target,
    required bool fresh,
    required bool offline,
    String? hiveDir,
  }) async {
    final prefix = _prefix(app);
    final network = ManualNetworkMonitor(online: !offline);
    late RecordingPlanCommitter recorder;
    final backend = await NexusBackend.firebase(
      app: app,
      boxPrefix: prefix,
      hiveDir: hiveDir,
      network: network,
      observeLifecycle: false,
      wrapCommitter: (_, base) => recorder = RecordingPlanCommitter(base),
      configure: (db, auth) async {
        db.useFirestoreEmulator(target.host, target.firestorePort);
        await auth.useAuthEmulator(target.host, target.authPort);
        if (fresh) {
          await db.clearPersistence();
          await auth.signOut();
          await _wipeBoxes(prefix);
        }
        if (offline) await db.disableNetwork();
      },
    );
    final d = NexusTestDevice._(app, backend, target, recorder)
      .._offline = offline;
    return d;
  }

  /// Deletes this device's Hive boxes (before they are opened).
  static Future<void> _wipeBoxes(String prefix) async {
    for (final name in [
      '$prefix${HiveDurableStore.defaultBox}',
      '$prefix${HiveSyncLedger.defaultBox}',
    ]) {
      try {
        await Hive.deleteBoxFromDisk(name);
      } on Object {
        // Not there yet.
      }
    }
  }

  FirebaseFirestore get firestore => backend.firestore;
  FirebaseAuth get firebaseAuth => backend.firebaseAuth;

  FirebaseAuthService get auth => backend.auth;
  DeviceService get devices => backend.devices;
  SalesService get sales => backend.sales;
  SalesRepository get salesRepo => backend.salesRepo;
  StockService get stock => backend.stock;
  StockRepository get stockRepo => backend.stockRepo;
  SummaryRepository get summaries => backend.summaries;
  SyncService get sync => backend.sync;
  OfflineGuard get offlineGuard => backend.offlineGuard;

  /// Whether [goOffline] is in force.
  bool get isOffline => _offline;

  /// `disableNetwork()` on this device's Firestore instance. Writes go on
  /// being committed to the local cache and queue for the server.
  Future<void> goOffline() async {
    await firestore.disableNetwork();
    _offline = true;
    (backend.network as ManualNetworkMonitor).online = false;
  }

  /// `enableNetwork()` on this device's Firestore instance. The sync
  /// service starts a pass by itself, as on a real reconnect; `syncNow()`
  /// waits for it and runs one more.
  Future<void> goOnline() async {
    await firestore.enableNetwork();
    _offline = false;
    (backend.network as ManualNetworkMonitor).online = true;
  }

  /// A process kill and restart: stops every service, closes the local
  /// stores and `terminate()`s Firestore, then reopens the same app on the
  /// same persistence, counter store, ledger and saved session, in the same
  /// network state. Queued writes are the ones the SDK kept; nothing is
  /// re-submitted. Use the returned device; this one is dead.
  Future<NexusTestDevice> restart() async {
    await _shutDown();
    return _open(app, target: _target, fresh: false, offline: _offline);
  }

  /// Commits the last plan this device committed (a bill, cancel, return
  /// or stock operation) again, unchanged, through the same adapter and
  /// into the ledger, as a retry after a crash or a double submit would
  /// (03-SYNC §4). Same doc IDs, same increments. If the server rejects it
  /// before it is even queued (online, the first copy already there), that
  /// is the expected outcome and not an error here.
  Future<void> reapplyLastPlan() async {
    final plan = _recorder.lastPlan;
    if (plan == null) throw StateError('nothing committed yet');
    try {
      await backend.env.write(plan, label: 'Re-applied plan');
    } on DataFailure {
      // Rejected at once; the first copy stands.
    }
  }

  /// Stops listeners, terminates Firestore and deletes the app.
  Future<void> dispose() async {
    if (_disposed) return;
    await _shutDown();
    await app.delete();
  }

  Future<void> _shutDown() async {
    if (_disposed) return;
    _disposed = true;
    await backend.dispose();
    await firestore.terminate();
  }
}
