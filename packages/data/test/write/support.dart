import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';

/// 2026-09-26 10:00 IST.
final DateTime t0 = DateTime.utc(2026, 9, 26, 4, 30);

/// A movable clock.
final class FakeClock {
  FakeClock([DateTime? start]) : now = start ?? t0;
  DateTime now;
  DateTime call() => now;
  void advance(Duration d) => now = now.add(d);
}

/// Records every plan; can fail, and can run a check at commit time.
final class FakeCommitter implements PlanCommitter {
  final List<WritePlan> plans = [];

  /// Thrown by the next commits instead of committing.
  Object? failWith;

  /// Runs when a plan reaches the committer, before anything is recorded.
  void Function(WritePlan plan)? onCommit;

  /// The server outcome handed out with each commit.
  Future<void> Function(WritePlan plan) ack = (_) => Future.value();

  @override
  Future<CommittedPlan> commit(WritePlan plan) async {
    onCommit?.call(plan);
    final f = failWith;
    if (f != null) return Future.error(f);
    plans.add(plan);
    final a = ack(plan)..ignore();
    return CommittedPlan(plan, a);
  }
}

/// [WriteReads] from maps.
final class FakeReads implements WriteReads {
  final Map<String, Bill> bills = {};
  final Map<String, StockItem> stock = {};
  final Map<String, Product> products = {};
  final Map<String, RawMaterial> materials = {};
  final Map<String, Expense> expenses = {};
  final Map<String, Location> locations = {};
  final Map<String, Device> devices = {};
  int deviceReads = 0;

  @override
  Future<Bill?> bill(String locationId, String billId) async =>
      bills[FirestorePaths.bill(locationId, billId)];

  @override
  Future<StockItem?> stockItem(String locationId, String itemKey) async =>
      stock[FirestorePaths.stockItem(locationId, itemKey)];

  @override
  Future<Product?> product(String productId) async => products[productId];

  @override
  Future<RawMaterial?> rawMaterial(String materialId) async =>
      materials[materialId];

  @override
  Future<Expense?> expense(String expenseId) async => expenses[expenseId];

  @override
  Future<Location?> location(String locationId) async => locations[locationId];

  @override
  Future<Device?> device(String locationId, String deviceId) async {
    deviceReads++;
    return devices[FirestorePaths.device(locationId, deviceId)];
  }
}

Role smRole({List<String> except = const []}) => Role(
  id: SeedRoles.storeManagerId,
  name: 'Store Manager',
  permissions: [
    for (final p in SeedRoles.storeManagerPermissions)
      if (!except.contains(p)) p,
  ],
  allLocations: false,
);

const Role adminRole = Role(
  id: SeedRoles.adminId,
  name: 'Admin',
  permissions: SeedRoles.adminPermissions,
  allLocations: true,
);

Location ptb({
  String pinHash = 'c2FsdA==\$aGFzaA==',
  int limitHours = 5,
  int extensionHours = 2,
  int? maxDiscountPct,
}) => Location(
  code: 'PTB',
  name: 'Store PTB',
  address: 'Main Road',
  phone: '0000000000',
  overridePinHash: pinHash,
  receiptFooter: 'Thank you!',
  nextDeviceNo: 1,
  active: true,
  offlineLimitHours: limitHours,
  overrideExtensionHours: extensionHours,
  maxDiscountPct: maxDiscountPct,
);

SessionContext smSession({
  List<String> except = const [],
  bool active = true,
  Location? location,
}) => SessionContext(
  user: AppUser(
    uid: 'sm-ptb',
    name: 'Store Manager PTB',
    email: 'sm@example.com',
    roleId: SeedRoles.storeManagerId,
    locationId: 'PTB',
    active: active,
    createdBy: 'admin',
  ),
  role: smRole(except: except),
  location: location ?? ptb(),
);

const SessionContext adminSession = SessionContext(
  user: AppUser(
    uid: 'admin',
    name: 'Admin',
    email: 'admin@example.com',
    roleId: SeedRoles.adminId,
    locationId: null,
    active: true,
    createdBy: 'seed',
  ),
  role: adminRole,
  location: null,
);

/// A write pipeline on fakes. [disk] is the device's durable store: build
/// a second harness on the same disk to simulate a restart.
final class Harness {
  Harness({
    SessionContext? session,
    this.deviceId = 'D01',
    Map<String, Object>? disk,
    LedgerDisk? ledgerDisk,
    FakeClock? clock,
  }) : session = session ?? smSession(),
       store = MemoryDurableStore(disk),
       reads = FakeReads(),
       committer = FakeCommitter(),
       clock = clock ?? FakeClock() {
    ledger = MemorySyncLedger(ledgerDisk);
    counters = CounterStore(store);
    env = WriteEnv(
      session: () => this.session,
      deviceId: () => deviceId,
      counters: counters,
      committer: committer,
      ledger: ledger,
      reads: reads,
      clock: this.clock.call,
      ids: IdGenerator(clock: this.clock.call),
    );
  }

  SessionContext? session;
  String? deviceId;
  final MemoryDurableStore store;
  final FakeReads reads;
  final FakeCommitter committer;
  final FakeClock clock;
  late final MemorySyncLedger ledger;
  late final CounterStore counters;
  late final WriteEnv env;

  OfflineState offline = const WithinLimit();

  late final FirestoreSalesService sales = FirestoreSalesService(
    env,
    offline: () => offline,
  );
  late final FirestoreStockService stock = FirestoreStockService(env);

  List<String> get ledgerPaths => [for (final e in ledger.entries) e.path];
}

Matcher failsWith(FailureReason reason) =>
    throwsA(isA<DataFailure>().having((f) => f.reason, 'reason', reason));

const CartLine cake = CartLine(
  productId: 'cake-choco-1kg',
  name: 'Chocolate Cake 1 kg',
  qty: 1,
  unitPrice: Money(65000),
);
const CartLine puff = CartLine(
  productId: 'puff-veg',
  name: 'Veg Puff',
  qty: 2,
  unitPrice: Money(2550),
);

/// The customer on every test bill.
final BillCustomer testCustomer = BillCustomer(
  name: 'Test Customer',
  phone: '9876543210',
);

/// ₹701, paid in cash.
final NewBill cashBill = NewBill(
  cart: const [cake, puff],
  payments: const [Payment(mode: PaymentMode.cash, amount: Money(70100))],
  customer: testCustomer,
);

/// Lets pending microtasks and zero-delay timers run.
Future<void> settle() => pumpEventQueue();

/// A future that never completes, for a server that never answers.
Future<void> never() => Completer<void>().future;
