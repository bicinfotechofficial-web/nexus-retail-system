import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:hive_ce/hive_ce.dart';
import 'package:path_provider/path_provider.dart';

import 'api/admin.dart';
import 'api/catalog.dart';
import 'api/customers.dart';
import 'api/device.dart';
import 'api/reports.dart';
import 'api/sales.dart';
import 'api/session.dart';
import 'api/stock.dart';
import 'api/sync.dart';
import 'counters/counter_store.dart';
import 'counters/durable_store.dart';
import 'firestore/device_service.dart';
import 'firestore/firebase_auth_service.dart';
import 'firestore/firestore_admin_repositories.dart';
import 'firestore/firestore_audit_repository.dart';
import 'firestore/firestore_catalog_repository.dart';
import 'firestore/firestore_customer_repository.dart';
import 'firestore/firestore_sales_repository.dart';
import 'firestore/firestore_stock_repository.dart';
import 'firestore/firestore_summary_repository.dart';
import 'firestore/firestore_user_service.dart';
import 'sync/connectivity.dart';
import 'sync/firestore_sync_service.dart';
import 'sync/local_offline_guard.dart';
import 'sync/local_sync_state.dart';
import 'sync/sync_ledger.dart';
import 'write/firestore_admin_services.dart';
import 'write/firestore_sales_service.dart';
import 'write/firestore_stock_service.dart';
import 'write/plan_committer.dart';
import 'write/write_env.dart';
import 'write/write_reads.dart';

/// Every `nexus_data` service and repository the apps use, built on one
/// Firebase app (D-026). The apps call [NexusBackend.firebase] once at
/// start-up and hand the fields to their providers; nothing else in the
/// apps touches Firestore.
///
/// ```dart
/// await Firebase.initializeApp(options: ...);
/// final backend = await NexusBackend.firebase();          // POS
/// final backend = await NexusBackend.firebase(admin: true); // console
/// ```
final class NexusBackend {
  NexusBackend._({
    required this.firestore,
    required this.firebaseAuth,
    required this.auth,
    required this.devices,
    required this.catalogRepo,
    required this.catalog,
    required this.salesRepo,
    required this.sales,
    required this.stockRepo,
    required this.stock,
    required this.customers,
    required this.summaries,
    required this.audit,
    required this.locationRepo,
    required this.locations,
    required this.userRepo,
    required this.users,
    required this.expenseRepo,
    required this.expenses,
    required this.sync,
    required this.offlineGuard,
    required this.env,
    required this.deviceStore,
    required this.ledger,
    required this.syncState,
    required this.network,
    required List<Future<void> Function()> onDispose,
  }) : _onDispose = onDispose;

  final FirebaseFirestore firestore;
  final FirebaseAuth firebaseAuth;

  /// Also exposes `interactiveSignIns`, which the sync service listens to.
  final FirebaseAuthService auth;
  final FirestoreDeviceService devices;
  final CatalogRepository catalogRepo;
  final CatalogService catalog;
  final SalesRepository salesRepo;
  final SalesService sales;
  final StockRepository stockRepo;
  final StockService stock;

  /// Customers, read only: bills write them (D-037).
  final CustomerRepository customers;
  final SummaryRepository summaries;
  final AuditRepository audit;
  final LocationRepository locationRepo;
  final LocationService locations;
  final UserRepository userRepo;
  final UserService users;
  final ExpenseRepository expenseRepo;
  final ExpenseService expenses;

  /// Call [FirestoreSyncService.appResumed] from a lifecycle observer if
  /// the backend was built with `observeLifecycle: false`.
  final FirestoreSyncService sync;
  final LocalOfflineGuard offlineGuard;

  /// The write pipeline the services share (the test support re-applies
  /// plans through it).
  final WriteEnv env;
  final DurableStore deviceStore;
  final SyncLedger ledger;
  final LocalSyncState syncState;
  final NetworkMonitor network;

  final List<Future<void> Function()> _onDispose;

  /// Firestore's cache size (03-SYNC §1).
  static const int cacheSizeBytes = 100 * 1024 * 1024;

  static bool _hiveReady = false;

  /// Builds everything on [app] (the default app when null).
  ///
  /// - POS (`admin: false`, the default): Firestore persistence on with a
  ///   100 MB cache, writes committed locally without waiting for the
  ///   server, the counters, `lastSyncAt` and override end in the Hive box
  ///   `{boxPrefix}device`, the ledger in `{boxPrefix}pending`, and the sync
  ///   service running (network changes, app resume, every 2 minutes).
  /// - Admin console (`admin: true`, online only, 03-SYNC §9): no Firestore
  ///   persistence on the web, writes wait for the server so the Admin sees
  ///   a rejection at once, local state in memory, and no sync passes.
  ///
  /// [configure] runs on the Firestore and Auth instances before anything
  /// else uses them (the emulator settings in tests), after Hive is
  /// initialised. [hiveDir] defaults to the app support directory.
  static Future<NexusBackend> firebase({
    FirebaseApp? app,
    bool admin = false,
    String boxPrefix = '',
    String? hiveDir,
    NetworkMonitor? network,
    DateTime Function()? clock,
    bool observeLifecycle = true,
    PlanCommitter Function(FirebaseFirestore db, PlanCommitter base)?
    wrapCommitter,
    Future<void> Function(FirebaseFirestore db, FirebaseAuth auth)? configure,
    SecondaryAuthFactory? secondaryAuth,
  }) async {
    final a = app ?? Firebase.app();
    final db = FirebaseFirestore.instanceFor(app: a);
    final fbAuth = FirebaseAuth.instanceFor(app: a);
    final persist = !admin && !kIsWeb;
    db.settings = Settings(
      persistenceEnabled: persist,
      cacheSizeBytes: persist ? cacheSizeBytes : null,
    );
    if (persist) await _initHive(hiveDir);
    await configure?.call(db, fbAuth);

    final DurableStore store;
    final SyncLedger ledger;
    final closers = <Future<void> Function()>[];
    if (persist) {
      final s = await HiveDurableStore.open(
        name: '$boxPrefix${HiveDurableStore.defaultBox}',
      );
      final l = await HiveSyncLedger.open(
        name: '$boxPrefix${HiveSyncLedger.defaultBox}',
      );
      store = s;
      ledger = l;
      closers.addAll([s.close, l.close]);
    } else {
      store = MemoryDurableStore();
      ledger = MemorySyncLedger();
    }

    final base = FirestorePlanCommitter(db, awaitServer: admin);
    return assemble(
      firestore: db,
      firebaseAuth: fbAuth,
      deviceStore: store,
      ledger: ledger,
      committer: wrapCommitter?.call(db, base) ?? base,
      network: network ?? PlatformNetworkMonitor(),
      clock: clock,
      runSync: !admin,
      observeLifecycle: observeLifecycle && !admin,
      secondaryAuth: secondaryAuth,
      onDispose: closers,
    );
  }

  /// Hive needs a directory once per process (not on the web).
  static Future<void> _initHive(String? dir) async {
    if (_hiveReady || kIsWeb) return;
    Hive.init(dir ?? (await getApplicationSupportDirectory()).path);
    _hiveReady = true;
  }

  /// Wires the services on given instances and stores. [firebase] uses it;
  /// tests and the test support can call it directly.
  static Future<NexusBackend> assemble({
    required FirebaseFirestore firestore,
    required FirebaseAuth firebaseAuth,
    required DurableStore deviceStore,
    required SyncLedger ledger,
    required PlanCommitter committer,
    required NetworkMonitor network,
    DateTime Function()? clock,
    bool runSync = true,
    bool observeLifecycle = true,
    SecondaryAuthFactory? secondaryAuth,
    List<Future<void> Function()> onDispose = const [],
  }) async {
    final db = firestore;
    final now = clock ?? DateTime.now;
    final auth = FirebaseAuthService(auth: firebaseAuth, firestore: db);
    final salesRepo = FirestoreSalesRepository(db, clock: now);
    final syncState = LocalSyncState(deviceStore);
    final counters = CounterStore(deviceStore);

    // Late: the device service and the write pipeline report to the sync
    // service, which needs the device service to find the device doc.
    late final FirestoreSyncService sync;
    final devices = FirestoreDeviceService(
      backend: FirestoreDeviceBackend(db),
      local: deviceStore,
      uid: () => firebaseAuth.currentUser?.uid,
      session: () => auth.current,
      onRegistered: (_) => sync.markSynced(),
      clock: now,
    );
    final env = WriteEnv(
      session: () => auth.current,
      deviceId: () => devices.deviceId,
      counters: counters,
      committer: committer,
      ledger: ledger,
      reads: FirestoreWriteReads(db, salesRepo, clock: now),
      clock: now,
      onCommitted: (paths, ack) => sync.observeAck(paths, ack),
    );
    sync = FirestoreSyncService(
      backend: FirestoreSyncBackend(db, committer),
      ledger: ledger,
      state: syncState,
      network: network,
      uid: () => firebaseAuth.currentUser?.uid,
      device: () {
        final d = devices.deviceId;
        final l = devices.locationId;
        return d == null || l == null ? null : (locationId: l, deviceId: d);
      },
      clock: now,
    );
    final guard = LocalOfflineGuard(
      syncState: syncState,
      session: () => auth.current,
      env: env,
      clock: now,
      sessionChanges: auth.session,
    );

    final disposers = <Future<void> Function()>[];
    if (runSync) {
      await sync.start(interactiveSignIns: auth.interactiveSignIns);
    }
    if (observeLifecycle) {
      final l = AppLifecycleListener(onResume: sync.appResumed);
      disposers.add(() async => l.dispose());
    }
    disposers
      ..add(sync.dispose)
      ..add(auth.dispose)
      ..addAll(onDispose);

    return NexusBackend._(
      firestore: db,
      firebaseAuth: firebaseAuth,
      auth: auth,
      devices: devices,
      catalogRepo: FirestoreCatalogRepository(db, clock: now),
      catalog: FirestoreCatalogService(env),
      salesRepo: salesRepo,
      sales: FirestoreSalesService(env, offline: guard.evaluate),
      stockRepo: FirestoreStockRepository(db, clock: now),
      stock: FirestoreStockService(env),
      customers: FirestoreCustomerRepository(db, clock: now),
      summaries: FirestoreSummaryRepository(db),
      audit: FirestoreAuditRepository(db),
      locationRepo: FirestoreLocationRepository(db),
      locations: FirestoreLocationService(env),
      userRepo: FirestoreUserRepository(db, clock: now),
      users: FirestoreUserService(
        auth: firebaseAuth,
        firestore: db,
        secondaryAuth: secondaryAuth,
        clock: now,
      ),
      expenseRepo: FirestoreExpenseRepository(db, clock: now),
      expenses: FirestoreExpenseService(env),
      sync: sync,
      offlineGuard: guard,
      env: env,
      deviceStore: deviceStore,
      ledger: ledger,
      syncState: syncState,
      network: network,
      onDispose: disposers,
    );
  }

  /// The [SyncService] and [OfflineGuard] under their contract types.
  SyncService get syncService => sync;
  OfflineGuard get guard => offlineGuard;
  AuthService get authService => auth;
  DeviceService get deviceService => devices;

  /// Stops timers and listeners and closes the local stores. The Firestore
  /// and Auth instances stay as they are.
  Future<void> dispose() async {
    for (final d in _onDispose) {
      try {
        await d();
      } on Object {
        // Keep going: the rest must still close.
      }
    }
  }
}
