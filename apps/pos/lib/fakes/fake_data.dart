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

/// Creates bills, cancellations and returns in memory with the real core
/// calculators (`BillCalculator`, `cancelBlocker`, `ReturnCalculator`,
/// `SummaryDeltas`), like the real service.
final class FakeSalesService implements SalesService {
  FakeSalesService({
    required this.auth,
    required this.bills,
    required this.summaries,
    DateTime Function()? now,
    this.deviceId = Seed.deviceId,
  }) : _now = now ?? DateTime.now;

  final FakeAuthService auth;
  final FakeSalesRepository bills;
  final FakeSummaryRepository summaries;
  final String deviceId;
  final DateTime Function() _now;
  int _seq = 0;
  int _returnSeq = 0;

  /// Every [createBill] call, including failed ones.
  final List<NewBill> createCalls = [];

  /// Every [cancelBill] call as (billId, reason), including failed ones.
  final List<(String, String)> cancelCalls = [];

  /// Every [createReturn] call's bill ID, including failed ones.
  final List<String> returnCalls = [];

  /// When set, the next [createBill], [cancelBill] or [createReturn] throws
  /// it instead of saving.
  Exception? failNext;

  /// When set, every write waits for it before saving.
  Completer<void>? gate;

  Future<void> _before() async {
    final g = gate;
    if (g != null) await g.future;
    final failure = failNext;
    if (failure != null) {
      failNext = null;
      throw failure;
    }
  }

  (SessionContext, Location) _session(String permission) {
    final session = auth.current;
    final location = session?.location;
    if (session == null || location == null) {
      throw const DataFailure(FailureReason.noProfile);
    }
    if (!session.canAt(permission, location.code)) {
      throw const DataFailure(FailureReason.notPermitted);
    }
    return (session, location);
  }

  @override
  Future<Bill> createBill(NewBill input) async {
    createCalls.add(input);
    await _before();
    return createBillAt(input, _now());
  }

  /// [createBill] at a given time, without the call log, gate or failure.
  /// Seeds earlier days for the demo and the tests.
  Future<Bill> createBillAt(NewBill input, DateTime at) async {
    final (session, location) = _session(Permission.billCreate);
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
      businessDate: BusinessDate.of(at),
      clientCreatedAt: at,
      createdBy: session.user.uid,
    );
    bills.put(location.code, bill);
    summaries.apply(
      location.code,
      bill.businessDate,
      SummaryDeltas.forBill(bill),
    );
    return bill;
  }

  @override
  Future<Bill> cancelBill({
    required String billId,
    required String reason,
  }) async {
    cancelCalls.add((billId, reason));
    await _before();
    final (session, location) = _session(Permission.billCancel);
    final bill = await bills.getBill(location.code, billId);
    if (bill == null) throw DataFailure(FailureReason.notFound, billId);
    if (reason.trim().isEmpty) {
      throw const DataFailure(FailureReason.ruleViolation, 'reason');
    }
    final now = _now();
    final blocker = cancelBlocker(bill, BusinessDate.of(now));
    if (blocker != null) {
      throw DataFailure(FailureReason.ruleViolation, blocker.name);
    }
    final cancelled = _copy(
      bill,
      status: BillStatus.cancelled,
      cancel: BillCancel(
        reason: reason.trim(),
        by: session.user.uid,
        at: now,
        businessDate: bill.businessDate,
      ),
    );
    bills.put(location.code, cancelled);
    summaries.apply(
      location.code,
      bill.businessDate,
      SummaryDeltas.forCancel(bill),
    );
    return cancelled;
  }

  @override
  Future<SaleReturn> createReturn({
    required String billId,
    required Map<String, int> qtyByProduct,
    required List<Payment> refunds,
    required String reason,
  }) async {
    returnCalls.add(billId);
    await _before();
    final (session, location) = _session(Permission.returnCreate);
    final bill = await bills.getBill(location.code, billId);
    if (bill == null) throw DataFailure(FailureReason.notFound, billId);
    final totals = ReturnCalculator.compute(bill, qtyByProduct);
    final refundErrors = ReturnCalculator.checkRefunds(
      totals.refundTotal,
      refunds,
    );
    if (refundErrors.isNotEmpty) {
      throw DataFailure(
        FailureReason.ruleViolation,
        refundErrors.map((e) => e.name).join(','),
      );
    }
    if (reason.trim().isEmpty) {
      throw const DataFailure(FailureReason.ruleViolation, 'reason');
    }
    _returnSeq++;
    final now = _now();
    final ret = SaleReturn(
      id: Ids.returnId(deviceId, _returnSeq),
      billId: bill.id,
      billNo: bill.billNo,
      lines: totals.lines,
      refundTotal: totals.refundTotal,
      refunds: refunds,
      reason: reason.trim(),
      businessDate: BusinessDate.of(now),
      createdBy: session.user.uid,
      deviceId: deviceId,
      clientCreatedAt: now,
    );
    final returned = {...bill.returnedQty};
    for (final l in ret.lines) {
      returned[l.productId] = (returned[l.productId] ?? 0) + l.qty;
    }
    bills
      ..addReturn(location.code, ret)
      ..put(
        location.code,
        _copy(bill, returnedQty: returned, lastReturnId: ret.id),
      );
    summaries.apply(
      location.code,
      ret.businessDate,
      SummaryDeltas.forReturn(ret),
    );
    return ret;
  }

  static Bill _copy(
    Bill b, {
    BillStatus? status,
    BillCancel? cancel,
    Map<String, int>? returnedQty,
    String? lastReturnId,
  }) => Bill(
    id: b.id,
    billNo: b.billNo,
    deviceId: b.deviceId,
    seq: b.seq,
    lines: b.lines,
    subtotal: b.subtotal,
    discount: b.discount,
    taxableValue: b.taxableValue,
    taxLines: b.taxLines,
    roundOff: b.roundOff,
    total: b.total,
    payments: b.payments,
    cashTendered: b.cashTendered,
    status: status ?? b.status,
    cancel: cancel ?? b.cancel,
    returnedQty: returnedQty ?? b.returnedQty,
    lastReturnId: lastReturnId ?? b.lastReturnId,
    servedBy: b.servedBy,
    businessDate: b.businessDate,
    clientCreatedAt: b.clientCreatedAt,
    serverCreatedAt: b.serverCreatedAt,
    createdBy: b.createdBy,
  );
}

final class FakeSalesRepository implements SalesRepository {
  final Map<String, Map<String, Bill>> _byLocation = {};
  final Map<String, List<SaleReturn>> _returns = {};
  final StreamController<void> _changes = StreamController<void>.broadcast();

  List<Bill> all(String locationId) =>
      List.unmodifiable(_byLocation[locationId]?.values ?? const <Bill>[]);

  /// Adds [bill], or replaces the one with its ID (a cancel or a return).
  void put(String locationId, Bill bill) {
    (_byLocation[locationId] ??= {})[bill.id] = bill;
    _changes.add(null);
  }

  void addReturn(String locationId, SaleReturn ret) {
    (_returns[locationId] ??= []).add(ret);
    _changes.add(null);
  }

  List<Bill> _day(String locationId, String businessDate) =>
      all(locationId).where((b) => b.businessDate == businessDate).toList()
        ..sort((a, b) => b.clientCreatedAt.compareTo(a.clientCreatedAt));

  List<SaleReturn> _returnsWhere(
    String locationId,
    bool Function(SaleReturn) test,
  ) =>
      (_returns[locationId] ?? const <SaleReturn>[]).where(test).toList()
        ..sort((a, b) => b.clientCreatedAt.compareTo(a.clientCreatedAt));

  @override
  Stream<List<Bill>> watchBills(String locationId, String businessDate) async* {
    yield _day(locationId, businessDate);
    yield* _changes.stream.map((_) => _day(locationId, businessDate));
  }

  @override
  Future<Bill?> getBill(String locationId, String billId) async =>
      _byLocation[locationId]?[billId];

  @override
  Future<Bill?> findByBillNo(String billNo) async {
    for (final bills in _byLocation.values) {
      for (final b in bills.values) {
        if (b.billNo == billNo) return b;
      }
    }
    return null;
  }

  @override
  Stream<List<SaleReturn>> watchReturns(
    String locationId,
    String businessDate,
  ) async* {
    bool today(SaleReturn r) => r.businessDate == businessDate;
    yield _returnsWhere(locationId, today);
    yield* _changes.stream.map((_) => _returnsWhere(locationId, today));
  }

  @override
  Future<List<SaleReturn>> returnsForBill(
    String locationId,
    String billId,
  ) async => _returnsWhere(locationId, (r) => r.billId == billId);
}

/// Daily summaries kept by adding `SummaryDeltas`, as the real batches do
/// with increments. A day with no activity reads as an empty summary.
final class FakeSummaryRepository implements SummaryRepository {
  final Map<(String, String), Summary> _daily = {};
  final StreamController<void> _changes = StreamController<void>.broadcast();

  void apply(String locationId, String businessDate, Summary delta) {
    final k = (locationId, businessDate);
    _daily[k] = (_daily[k] ?? const Summary()) + delta;
    _changes.add(null);
  }

  Summary _day(String locationId, String businessDate) =>
      _daily[(locationId, businessDate)] ?? const Summary();

  @override
  Stream<Summary> watchDaily(String locationId, String businessDate) async* {
    yield _day(locationId, businessDate);
    yield* _changes.stream.map((_) => _day(locationId, businessDate));
  }

  @override
  Future<Map<String, Summary>> daily(
    String locationId,
    String from,
    String to,
  ) async => {
    for (final e in _daily.entries)
      if (e.key.$1 == locationId &&
          e.key.$2.compareTo(from) >= 0 &&
          e.key.$2.compareTo(to) <= 0)
        e.key.$2: e.value,
  };

  @override
  Future<Map<String, Summary>> monthly(
    String locationId,
    String fromMonth,
    String toMonth,
  ) async {
    final out = <String, Summary>{};
    for (final e in _daily.entries) {
      if (e.key.$1 != locationId) continue;
      final m = BusinessDate.monthOf(e.key.$2);
      if (m.compareTo(fromMonth) < 0 || m.compareTo(toMonth) > 0) continue;
      out[m] = (out[m] ?? const Summary()) + e.value;
    }
    return out;
  }
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
