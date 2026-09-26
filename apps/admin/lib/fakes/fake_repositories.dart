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
final class FakeSummaryRepository implements SummaryRepository {
  FakeSummaryRepository({required this.dailyDocs, required this.monthlyDocs});

  final Map<String, Map<String, Summary>> dailyDocs;
  final Map<String, Map<String, Summary>> monthlyDocs;

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
  FakeStockRepository(this.stock);

  /// Location code → its stock docs.
  final Map<String, List<StockItem>> stock;

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
}
