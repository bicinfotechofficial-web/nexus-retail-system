import 'dart:async';

import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';

/// In-memory [AuthService]. [accounts] maps an email to its password and
/// the session it opens.
final class FakeAuthService implements AuthService {
  FakeAuthService(this.accounts);

  final Map<String, ({String password, SessionContext session})> accounts;
  final _controller = StreamController<SessionContext?>.broadcast();
  SessionContext? _current;

  @override
  SessionContext? get current => _current;

  @override
  Stream<SessionContext?> get session => _controller.stream;

  @override
  Future<SessionContext> signIn({
    required String email,
    required String password,
  }) async {
    final account = accounts[email.trim().toLowerCase()];
    if (account == null || account.password != password) {
      throw const DataFailure(FailureReason.invalidCredentials);
    }
    if (!account.session.user.active) {
      throw const DataFailure(FailureReason.userDisabled);
    }
    _set(account.session);
    return account.session;
  }

  @override
  Future<void> signOut() async => _set(null);

  void _set(SessionContext? s) {
    _current = s;
    _controller.add(s);
  }
}

/// A value that tests and fakes can change, with streams that emit the
/// current value on listen and every change after it.
final class Watched<T> {
  Watched(this._value);

  T _value;
  final _changes = StreamController<T>.broadcast();

  T get value => _value;

  set value(T v) {
    _value = v;
    _changes.add(v);
  }

  Stream<R> watch<R>(R Function(T value) select) => Stream.multi((c) {
    c.add(select(_value));
    final sub = _changes.stream.listen((v) => c.add(select(v)));
    c.onCancel = sub.cancel;
  });
}

final class FakeLocationRepository implements LocationRepository {
  FakeLocationRepository(List<Location> locations)
    : store = Watched(List.unmodifiable(locations));

  final Watched<List<Location>> store;

  List<Location> get locations => store.value;

  Location? byCode(String code) =>
      locations.where((l) => l.code == code).firstOrNull;

  /// Replaces the location with the same code, or adds it.
  void put(Location location) {
    final next = <Location>[
      for (final l in locations)
        if (l.code != location.code) l,
      location,
    ]..sort((a, b) => a.code.compareTo(b.code));
    store.value = List.unmodifiable(next);
  }

  @override
  Stream<List<Location>> watchLocations() => store.watch((v) => v);

  @override
  Stream<Location?> watchLocation(String locationId) =>
      store.watch((v) => v.where((l) => l.code == locationId).firstOrNull);
}

/// Summaries keyed by location, then by `YYYY-MM-DD` or `YYYY-MM`.
/// The maps are copied, so the fakes can add to them (expense increments).
final class FakeSummaryRepository implements SummaryRepository {
  FakeSummaryRepository({
    required Map<String, Map<String, Summary>> dailyDocs,
    required Map<String, Map<String, Summary>> monthlyDocs,
  }) : dailyDocs = _copy(dailyDocs),
       monthlyDocs = _copy(monthlyDocs);

  final Map<String, Map<String, Summary>> dailyDocs;
  final Map<String, Map<String, Summary>> monthlyDocs;

  static Map<String, Map<String, Summary>> _copy(
    Map<String, Map<String, Summary>> docs,
  ) => {for (final e in docs.entries) e.key: Map.of(e.value)};

  /// Adds [delta] to a monthly doc, as `FieldValue.increment` would; a
  /// missing doc starts from zero.
  void incrementMonthly(String locationId, String monthKey, Summary delta) {
    final docs = monthlyDocs.putIfAbsent(locationId, () => {});
    docs[monthKey] = (docs[monthKey] ?? const Summary()) + delta;
  }

  @override
  Stream<Summary> watchDaily(String locationId, String businessDate) =>
      Stream.value(dailyDocs[locationId]?[businessDate] ?? const Summary());

  @override
  Future<Map<String, Summary>> daily(
    String locationId,
    String from,
    String to,
  ) async => _range(dailyDocs[locationId], from, to);

  @override
  Future<Map<String, Summary>> monthly(
    String locationId,
    String fromMonth,
    String toMonth,
  ) async => _range(monthlyDocs[locationId], fromMonth, toMonth);

  // Keys are ISO dates or months, so string order is date order.
  static Map<String, Summary> _range(
    Map<String, Summary>? docs,
    String from,
    String to,
  ) => {
    for (final e in (docs ?? const <String, Summary>{}).entries)
      if (e.key.compareTo(from) >= 0 && e.key.compareTo(to) <= 0)
        e.key: e.value,
  };
}

final class FakeStockRepository implements StockRepository {
  FakeStockRepository(this.stock, {this.movements = const {}});

  /// Location code → its stock docs.
  final Map<String, List<StockItem>> stock;

  /// Location code → its stock movements, any date.
  final Map<String, List<Movement>> movements;

  @override
  Stream<List<Movement>> watchMovements(
    String locationId,
    String businessDate,
  ) => Stream.value(
    [
      for (final m in movements[locationId] ?? const <Movement>[])
        if (m.businessDate == businessDate) m,
    ]..sort((a, b) => b.clientCreatedAt.compareTo(a.clientCreatedAt)),
  );

  @override
  Stream<List<StockItem>> watchStock(String locationId) =>
      Stream.value(stock[locationId] ?? const []);

  @override
  Stream<List<StockItem>> watchLowStock(String locationId) => Stream.value([
    for (final s in stock[locationId] ?? const <StockItem>[])
      if (s.isLow) s,
  ]);
}

final class FakeCatalogRepository implements CatalogRepository {
  FakeCatalogRepository({
    List<Product> products = const [],
    List<RawMaterial> materials = const [],
  }) : productStore = Watched(List.unmodifiable(products)),
       materialStore = Watched(List.unmodifiable(materials));

  final Watched<List<Product>> productStore;
  final Watched<List<RawMaterial>> materialStore;

  List<Product> get products => productStore.value;
  List<RawMaterial> get materials => materialStore.value;

  Product? byId(String id) => products.where((p) => p.id == id).firstOrNull;

  /// Replaces the product with the same ID, or adds it.
  void put(Product product) {
    final replaced = [
      for (final p in products) p.id == product.id ? product : p,
    ];
    if (byId(product.id) == null) replaced.add(product);
    productStore.value = List.unmodifiable(replaced);
  }

  void addMaterial(RawMaterial material) {
    materialStore.value = List.unmodifiable([...materials, material]);
  }

  @override
  Stream<List<Product>> watchAll() => productStore.watch((v) => v);

  @override
  Stream<List<Product>> watchPending() => productStore.watch(
    (v) => [
      for (final p in v)
        if (p.status == ProductStatus.pending) p,
    ],
  );

  @override
  Stream<List<Product>> watchSellable(String locationId) => productStore.watch(
    (v) => [
      for (final p in v)
        if (p.isSellableAt(locationId)) p,
    ]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)),
  );

  @override
  Stream<List<RawMaterial>> watchRawMaterials() =>
      materialStore.watch((v) => v);

  @override
  Stream<List<Product>> watchMySuggestions(String locationId, String uid) =>
      productStore.watch(
        (v) => [
          for (final p in v)
            if (p.createdBy == uid && p.scope == locationId) p,
        ]..sort((a, b) => _when(b).compareTo(_when(a))),
      );

  static DateTime _when(Product p) =>
      p.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}

/// Bills by location. Seed them with [FakeBackend.seedBills]; the customers
/// the Admin lists are built from the same bills ([FakeCustomerRepository]).
final class FakeSalesRepository implements SalesRepository {
  FakeSalesRepository(Map<String, List<Bill>> bills)
    : bills = {for (final e in bills.entries) e.key: List.of(e.value)};

  /// Location code → its bills.
  final Map<String, List<Bill>> bills;

  @override
  Stream<List<Bill>> watchBills(String locationId, String businessDate) =>
      Stream.value(
        [
          for (final b in bills[locationId] ?? const <Bill>[])
            if (b.businessDate == businessDate) b,
        ]..sort((a, b) => b.clientCreatedAt.compareTo(a.clientCreatedAt)),
      );

  @override
  Future<Bill?> getBill(String locationId, String billId) async =>
      (bills[locationId] ?? const <Bill>[])
          .where((b) => b.id == billId)
          .firstOrNull;

  @override
  Future<Bill?> findByBillNo(String billNo) async => [
    for (final l in bills.values) ...l,
  ].where((b) => b.billNo == billNo).firstOrNull;

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

/// Customers by location, as the bills' batches would have written them
/// (D-037): one record per mobile and name, with the bill count and the
/// total as billed.
final class FakeCustomerRepository implements CustomerRepository {
  FakeCustomerRepository(this.customers);

  /// Builds the records from [bills], skipping bills with no customer.
  factory FakeCustomerRepository.fromBills(Map<String, List<Bill>> bills) {
    final result = <String, List<Customer>>{};
    for (final e in bills.entries) {
      final byId = <String, Customer>{};
      final ordered = [...e.value]
        ..sort((a, b) => a.clientCreatedAt.compareTo(b.clientCreatedAt));
      for (final b in ordered) {
        final c = b.customer;
        if (c == null) continue;
        final before = byId[c.id];
        byId[c.id] = Customer(
          id: c.id,
          name: c.name,
          phone: c.phone,
          whatsapp: c.whatsapp,
          locationId: e.key,
          lastBillAt: b.clientCreatedAt,
          billCount: (before?.billCount ?? 0) + 1,
          totalSpend: (before?.totalSpend ?? Money.zero) + b.total,
          lastWriteRef: b.id,
        );
      }
      result[e.key] = byId.values.toList();
    }
    return FakeCustomerRepository(result);
  }

  /// Location code → its customers.
  final Map<String, List<Customer>> customers;

  static List<Customer> _recentFirst(Iterable<Customer> list, int limit) =>
      ([...list]..sort(
            (a, b) => (b.lastBillAt ?? DateTime(0)).compareTo(
              a.lastBillAt ?? DateTime(0),
            ),
          ))
          .take(limit)
          .toList();

  @override
  Stream<List<Customer>> watchByPhone(String locationId, String phonePrefix) =>
      Stream.value([
        for (final c in customers[locationId] ?? const <Customer>[])
          if (c.phone.startsWith(phonePrefix)) c,
      ]);

  @override
  Stream<List<Customer>> watchAll(String locationId, {int limit = 200}) =>
      Stream.value(_recentFirst(customers[locationId] ?? const [], limit));

  @override
  Stream<List<Customer>> watchAllLocations({int limit = 500}) => Stream.value(
    _recentFirst([for (final l in customers.values) ...l], limit),
  );
}
