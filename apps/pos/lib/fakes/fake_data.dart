import 'dart:async';
import 'dart:core' as core show override;
import 'dart:core';

import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';

import 'latest.dart';
import 'seed.dart';

/// In-memory implementations of the `nexus_data` interfaces the POS uses.
/// Same signatures as the real ones, so swapping them is a provider change.

final class FakeAuthService implements AuthService {
  FakeAuthService([SessionContext? initial])
    : _session = Latest(
        initial ??
            const SessionContext(
              user: Seed.storeManager,
              role: Seed.storeManagerRole,
              location: Seed.location,
            ),
      );

  final Latest<SessionContext?> _session;

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
    : _products = Latest(products ?? Seed.products);

  final Latest<List<Product>> _products;
  final Latest<List<RawMaterial>> _materials = Latest(Seed.rawMaterials);

  List<Product> get products => _products.value;
  set products(List<Product> value) => _products.value = value;

  List<RawMaterial> get rawMaterials => _materials.value;
  set rawMaterials(List<RawMaterial> value) => _materials.value = value;

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
  Stream<List<RawMaterial>> watchRawMaterials() => _materials.stream;
}

/// Catalog writes in memory. Only [suggest] is used by the POS; the rest
/// keep the interface complete.
final class FakeCatalogService implements CatalogService {
  FakeCatalogService({required this.auth, required this.catalog});

  final FakeAuthService auth;
  final FakeCatalogRepository catalog;
  int _n = 0;

  /// Every [suggest] call's name, including failed ones.
  final List<String> suggestCalls = [];

  /// When set, the next call throws it instead of saving.
  Exception? failNext;

  SessionContext _check(String permission) {
    final session = auth.current;
    if (session == null) throw const DataFailure(FailureReason.noProfile);
    if (!session.can(permission)) {
      throw const DataFailure(FailureReason.notPermitted);
    }
    final failure = failNext;
    if (failure != null) {
      failNext = null;
      throw failure;
    }
    return session;
  }

  @override
  Future<Product> suggest({
    required String name,
    required String category,
    required Money proposedPrice,
  }) async {
    suggestCalls.add(name);
    final session = _check(Permission.catalogSuggest);
    final location = session.location;
    if (location == null) throw const DataFailure(FailureReason.noProfile);
    if (name.trim().isEmpty || category.trim().isEmpty) {
      throw const DataFailure(FailureReason.ruleViolation, 'name, category');
    }
    if (!proposedPrice.isPositive) {
      throw const DataFailure(FailureReason.ruleViolation, 'proposedPrice');
    }
    _n++;
    final product = Product(
      id: 'local-${location.code}-$_n',
      name: name.trim(),
      category: category.trim(),
      scope: location.code,
      status: ProductStatus.pending,
      sortOrder: 1000 + _n,
      createdBy: session.user.uid,
      proposedPrice: proposedPrice,
    );
    catalog.products = [...catalog.products, product];
    return product;
  }

  @override
  Future<Product> save(Product product) async {
    _check(Permission.catalogManage);
    catalog.products = [
      ...catalog.products.where((p) => p.id != product.id),
      product,
    ];
    return product;
  }

  @override
  Future<Product> approve({
    required String productId,
    required Money price,
  }) async {
    _check(Permission.catalogManage);
    final p = catalog.products.where((p) => p.id == productId).firstOrNull;
    if (p == null) throw DataFailure(FailureReason.notFound, productId);
    final approved = Product(
      id: p.id,
      name: p.name,
      category: p.category,
      price: price,
      proposedPrice: p.proposedPrice,
      unit: p.unit,
      gstRate: p.gstRate,
      scope: p.scope,
      status: ProductStatus.active,
      recipe: p.recipe,
      sortOrder: p.sortOrder,
      createdBy: p.createdBy,
    );
    return save(approved);
  }

  @override
  Future<RawMaterial> addRawMaterial({
    required String name,
    required StockUnit unit,
  }) async {
    final session = _check(Permission.rawMaterialCreate);
    _n++;
    final m = RawMaterial(
      id: 'rm-$_n',
      name: name.trim(),
      unit: unit,
      active: true,
      createdBy: session.user.uid,
    );
    catalog.rawMaterials = [...catalog.rawMaterials, m];
    return m;
  }
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
  FakeSyncService([
    SyncStatus initial = const Online(),
    DateTime Function()? now,
  ]) : _status = Latest(initial),
       _now = now ?? DateTime.now;

  final Latest<SyncStatus> _status;
  final Latest<List<SyncError>> _errors = Latest(const []);
  final DateTime Function() _now;

  /// Whether a sync pass can reach the server. When false, [syncNow] leaves
  /// [lastSyncAt] where it was.
  bool online = true;

  /// Called after every sync pass that completed, e.g. to re-check the
  /// offline limit.
  void Function()? onSynced;

  /// Emits a new status to the app-bar chip.
  void emit(SyncStatus value) => _status.value = value;

  /// A write the server rejected (03-SYNC §6.3).
  void addError(SyncError error) => _errors.value = [..._errors.value, error];

  @override
  Stream<SyncStatus> get status => _status.stream;

  @override
  Stream<List<SyncError>> get errors => _errors.stream;

  @override
  DateTime? lastSyncAt;

  int syncNowCalls = 0;

  /// Marks a completed sync pass now: an interactive online sign-in and a
  /// registration do this too (03-SYNC §6).
  void markSynced() {
    lastSyncAt = _now();
    onSynced?.call();
  }

  @override
  Future<void> syncNow() async {
    syncNowCalls++;
    if (!online) return;
    emit(const Online());
    markSynced();
  }
}

/// The offline limit (03-SYNC §7) computed from [FakeSyncService.lastSyncAt]
/// and the injected clock, like the real guard. [evaluate] re-checks it;
/// tests call it after moving the clock.
final class FakeOfflineGuard implements OfflineGuard {
  FakeOfflineGuard({
    this.pin = defaultPin,
    DateTime Function()? now,
    DateTime? Function()? lastSyncAt,
    Location? Function()? location,
    this.deviceId = Seed.deviceId,
  }) : assert(pin.length >= Limits.minOverridePinDigits),
       _now = now ?? DateTime.now,
       _lastSyncAt = lastSyncAt ?? (() => null),
       _location = location ?? (() => Seed.location);

  /// 8 digits, the minimum a location may use (D-031, QA-030).
  static const String defaultPin = '24681357';

  final String pin;
  final String deviceId;
  final DateTime Function() _now;
  final DateTime? Function() _lastSyncAt;
  final Location? Function() _location;
  final Latest<OfflineState> _state = Latest(const WithinLimit());

  /// The end of the current PIN override, if any. Persisted by the real
  /// guard (QA-025).
  DateTime? overrideUntil;

  /// Every [override] call's PIN, right or wrong.
  final List<String> overrideCalls = [];

  /// The OFFLINE_OVERRIDE audit IDs queued by successful overrides.
  final List<String> auditIds = [];

  /// Emits [value] as is, bypassing the clock.
  void emit(OfflineState value) => _state.value = value;

  OfflineState get current => _state.value;

  /// Recomputes the state from the clock, the last sync and any override,
  /// and emits it.
  OfflineState evaluate() {
    final now = _now();
    final until = overrideUntil;
    final location = _location();
    final limit = Duration(
      hours: location?.offlineLimitHours ?? Location.defaultOfflineLimitHours,
    );
    final last = _lastSyncAt();
    final OfflineState next;
    if (until != null && now.isBefore(until)) {
      next = NearLimit(until.difference(now));
    } else if (last == null) {
      next = const WithinLimit();
    } else {
      final elapsed = now.difference(last);
      if (elapsed >= limit) {
        next = const BillingBlocked();
      } else if (elapsed * 5 >= limit * 4) {
        next = NearLimit(limit - elapsed);
      } else {
        next = const WithinLimit();
      }
    }
    _state.value = next;
    return next;
  }

  /// A sync pass completed: an override is no longer needed.
  void synced() {
    overrideUntil = null;
    evaluate();
  }

  // `@override` would name the `override` method below, so use dart:core's.
  @core.override
  Stream<OfflineState> get state => _state.stream;

  @core.override
  Future<bool> override(String pin) async {
    overrideCalls.add(pin);
    if (pin.length < Limits.minOverridePinDigits || pin != this.pin) {
      return false;
    }
    final now = _now();
    final location = _location();
    overrideUntil = now.add(
      Duration(
        hours:
            location?.overrideExtensionHours ??
            Location.defaultOverrideExtensionHours,
      ),
    );
    auditIds.add(
      Ids.overrideAuditId(location?.code ?? Seed.locationId, deviceId, now),
    );
    evaluate();
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
