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

final class FakeLocationRepository implements LocationRepository {
  FakeLocationRepository(this.locations);

  final List<Location> locations;

  @override
  Stream<List<Location>> watchLocations() => Stream.value(locations);

  @override
  Stream<Location?> watchLocation(String locationId) =>
      Stream.value(locations.where((l) => l.code == locationId).firstOrNull);
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
  FakeCatalogRepository({this.products = const [], this.materials = const []});

  final List<Product> products;
  final List<RawMaterial> materials;

  @override
  Stream<List<Product>> watchAll() => Stream.value(products);

  @override
  Stream<List<Product>> watchPending() => Stream.value([
    for (final p in products)
      if (p.status == ProductStatus.pending) p,
  ]);

  @override
  Stream<List<Product>> watchSellable(String locationId) => Stream.value([
    for (final p in products)
      if (p.isSellableAt(locationId)) p,
  ]);

  @override
  Stream<List<RawMaterial>> watchRawMaterials() => Stream.value(materials);
}
