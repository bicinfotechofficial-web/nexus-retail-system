import 'dart:async';
import 'dart:core' as core show override;
import 'dart:core';

import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';

import 'seed.dart';

/// In-memory implementations of the `nexus_data` interfaces the POS uses.
/// Same signatures as the real ones, so swapping them is a provider change.

/// A stream that replays its latest value to every new listener.
final class _Latest<T> {
  _Latest(this._value);

  T _value;
  final StreamController<T> _changes = StreamController<T>.broadcast();

  T get value => _value;

  set value(T v) {
    _value = v;
    _changes.add(v);
  }

  Stream<T> get stream async* {
    yield _value;
    yield* _changes.stream;
  }

  Future<void> close() => _changes.close();
}

final class FakeAuthService implements AuthService {
  FakeAuthService([SessionContext? initial])
    : _session = _Latest(
        initial ??
            const SessionContext(
              user: Seed.storeManager,
              role: Seed.storeManagerRole,
              location: Seed.location,
            ),
      );

  final _Latest<SessionContext?> _session;

  @override
  Stream<SessionContext?> get session => _session.stream;

  @override
  SessionContext? get current => _session.value;

  /// Replaces the session, e.g. to change permissions in a test.
  set current(SessionContext? value) => _session.value = value;

  @override
  Future<SessionContext> signIn({
    required String email,
    required String password,
  }) async {
    const s = SessionContext(
      user: Seed.storeManager,
      role: Seed.storeManagerRole,
      location: Seed.location,
    );
    _session.value = s;
    return s;
  }

  @override
  Future<void> signOut() async => _session.value = null;
}

final class FakeCatalogRepository implements CatalogRepository {
  FakeCatalogRepository([List<Product>? products])
    : _products = _Latest(products ?? Seed.products);

  final _Latest<List<Product>> _products;

  set products(List<Product> value) => _products.value = value;

  @override
  Stream<List<Product>> watchSellable(String locationId) =>
      _products.stream.map(
        (all) =>
            all.where((p) => p.isSellableAt(locationId)).toList()
              ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)),
      );

  @override
  Stream<List<Product>> watchAll() => _products.stream;

  @override
  Stream<List<Product>> watchPending() => _products.stream.map(
    (all) => all.where((p) => p.status == ProductStatus.pending).toList(),
  );

  @override
  Stream<List<RawMaterial>> watchRawMaterials() => Stream.value(const []);
}

/// Creates bills in memory with `BillCalculator`, like the real service.
final class FakeSalesService implements SalesService {
  FakeSalesService({
    required this.auth,
    required this.bills,
    DateTime Function()? now,
    this.deviceId = Seed.deviceId,
  }) : _now = now ?? DateTime.now;

  final FakeAuthService auth;
  final FakeSalesRepository bills;
  final String deviceId;
  final DateTime Function() _now;
  int _seq = 0;

  /// Every [createBill] call, including failed ones.
  final List<NewBill> createCalls = [];

  /// When set, the next [createBill] throws it instead of saving.
  Exception? failNext;

  /// When set, [createBill] waits for it before saving.
  Completer<void>? gate;

  @override
  Future<Bill> createBill(NewBill input) async {
    createCalls.add(input);
    final g = gate;
    if (g != null) await g.future;
    final failure = failNext;
    if (failure != null) {
      failNext = null;
      throw failure;
    }
    final session = auth.current;
    final location = session?.location;
    if (session == null || location == null) {
      throw const DataFailure(FailureReason.noProfile);
    }
    if (!session.canAt(Permission.billCreate, location.code)) {
      throw const DataFailure(FailureReason.notPermitted);
    }
    final totals = BillCalculator.compute(
      input.cart,
      discount: input.discount,
      maxDiscountPct: location.maxDiscountPct,
    );
    final check = BillCalculator.checkPayments(
      totals.total,
      input.payments,
      cashTendered: input.cashTendered,
    );
    if (!check.isValid) {
      throw DataFailure(
        FailureReason.ruleViolation,
        check.errors.map((e) => e.name).join(','),
      );
    }
    _seq++;
    final id = Ids.billId(deviceId, _seq);
    final now = _now();
    final bill = Bill(
      id: id,
      billNo: Ids.billNo(location.code, id),
      deviceId: deviceId,
      seq: _seq,
      lines: totals.lines,
      subtotal: totals.subtotal,
      discount: totals.discount,
      taxableValue: totals.taxableValue,
      taxLines: totals.taxLines,
      roundOff: totals.roundOff,
      total: totals.total,
      payments: input.payments,
      cashTendered: input.cashTendered,
      status: BillStatus.completed,
      servedBy: ServedBy(uid: session.user.uid, name: session.user.name),
      businessDate: BusinessDate.of(now),
      clientCreatedAt: now,
      createdBy: session.user.uid,
    );
    bills.add(location.code, bill);
    return bill;
  }

  @override
  Future<Bill> cancelBill({required String billId, required String reason}) =>
      throw const DataFailure(FailureReason.unknown, 'not in the fake yet');

  @override
  Future<SaleReturn> createReturn({
    required String billId,
    required Map<String, int> qtyByProduct,
    required List<Payment> refunds,
    required String reason,
  }) => throw const DataFailure(FailureReason.unknown, 'not in the fake yet');
}

final class FakeSalesRepository implements SalesRepository {
  final Map<String, List<Bill>> _byLocation = {};
  final StreamController<void> _changes = StreamController<void>.broadcast();

  List<Bill> all(String locationId) =>
      List.unmodifiable(_byLocation[locationId] ?? const <Bill>[]);

  void add(String locationId, Bill bill) {
    (_byLocation[locationId] ??= []).add(bill);
    _changes.add(null);
  }

  List<Bill> _day(String locationId, String businessDate) =>
      all(locationId).where((b) => b.businessDate == businessDate).toList()
        ..sort((a, b) => b.clientCreatedAt.compareTo(a.clientCreatedAt));

  @override
  Stream<List<Bill>> watchBills(String locationId, String businessDate) async* {
    yield _day(locationId, businessDate);
    yield* _changes.stream.map((_) => _day(locationId, businessDate));
  }

  @override
  Future<Bill?> getBill(String locationId, String billId) async {
    for (final b in all(locationId)) {
      if (b.id == billId) return b;
    }
    return null;
  }

  @override
  Future<Bill?> findByBillNo(String billNo) async {
    for (final list in _byLocation.values) {
      for (final b in list) {
        if (b.billNo == billNo) return b;
      }
    }
    return null;
  }

  @override
  Stream<List<SaleReturn>> watchReturns(
    String locationId,
    String businessDate,
  ) => Stream.value(const []);

  @override
  Future<List<SaleReturn>> returnsForBill(
    String locationId,
    String billId,
  ) async => const [];
}

final class FakeSyncService implements SyncService {
  FakeSyncService([SyncStatus initial = const Online()])
    : _status = _Latest(initial);

  final _Latest<SyncStatus> _status;

  /// Emits a new status to the app-bar chip.
  void emit(SyncStatus value) => _status.value = value;

  @override
  Stream<SyncStatus> get status => _status.stream;

  @override
  Stream<List<SyncError>> get errors => Stream.value(const []);

  @override
  DateTime? lastSyncAt;

  int syncNowCalls = 0;

  @override
  Future<void> syncNow() async {
    syncNowCalls++;
    lastSyncAt = DateTime.now();
  }
}

final class FakeOfflineGuard implements OfflineGuard {
  FakeOfflineGuard({this.pin = '1234'});

  final String pin;
  final _Latest<OfflineState> _state = _Latest(const WithinLimit());

  void emit(OfflineState value) => _state.value = value;

  // `@override` would name the `override` method below, so use dart:core's.
  @core.override
  Stream<OfflineState> get state => _state.stream;

  @core.override
  Future<bool> override(String pin) async {
    if (pin != this.pin) return false;
    _state.value = const WithinLimit();
    return true;
  }
}

final class FakeDeviceService implements DeviceService {
  FakeDeviceService([this.deviceId = Seed.deviceId]);

  @override
  String? deviceId;

  @override
  Future<Device> register({
    required String locationId,
    required String label,
  }) async {
    deviceId = Seed.deviceId;
    return Device(
      code: Seed.deviceId,
      label: label,
      registeredBy: Seed.userId,
      lastBillSeq: 0,
      retired: false,
    );
  }

  @override
  Stream<List<Device>> watchDevices(String locationId) => Stream.value(const [
    Device(
      code: Seed.deviceId,
      label: 'Counter 1',
      registeredBy: Seed.userId,
      lastBillSeq: 0,
      retired: false,
    ),
  ]);

  @override
  Future<void> retire({
    required String locationId,
    required String deviceId,
  }) async {}
}
