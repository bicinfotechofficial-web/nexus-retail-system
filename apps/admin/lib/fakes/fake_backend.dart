import 'dart:math';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';

import '../data/providers.dart';
import 'fake_repositories.dart';

/// In-memory fakes of every `nexus_data` interface the console uses,
/// selected with `--dart-define=FAKE_DATA=true`.
final class FakeBackend {
  FakeBackend({
    required this.auth,
    required this.locations,
    required this.summaries,
    required this.stock,
    required this.catalog,
  });

  /// Two locations (PTB, MNJ), an Admin and a Store Manager at PTB, and
  /// daily and monthly summaries from the 1st of the month two months
  /// before [today] up to [today]. Deterministic for a given [seed].
  factory FakeBackend.seeded({required String today, int seed = 42}) {
    final daily = <String, Map<String, Summary>>{};
    final monthly = <String, Map<String, Summary>>{};
    final rng = Random(seed);
    for (final loc in seedLocations) {
      final scale = loc.code == 'PTB' ? 10 : 7;
      final days = <String, Summary>{};
      for (final date in _dates(today)) {
        days[date] = _day(rng, scale);
      }
      daily[loc.code] = days;
      final months = <String, Summary>{};
      for (final e in days.entries) {
        final key = BusinessDate.monthOf(e.key);
        months[key] = (months[key] ?? const Summary()) + e.value;
      }
      monthly[loc.code] = {
        for (final e in months.entries) e.key: e.value + _expenses(rng, scale),
      };
    }
    return FakeBackend(
      auth: FakeAuthService({
        adminEmail: (password: demoPassword, session: adminSession()),
        storeManagerEmail: (
          password: demoPassword,
          session: storeManagerSession('PTB'),
        ),
      }),
      locations: FakeLocationRepository(seedLocations),
      summaries: FakeSummaryRepository(dailyDocs: daily, monthlyDocs: monthly),
      stock: FakeStockRepository(_seedStock),
      catalog: FakeCatalogRepository(
        products: seedProducts,
        materials: _seedMaterials,
      ),
    );
  }

  static const String adminEmail = 'admin@caramelcottage.in';
  static const String storeManagerEmail = 'manager.ptb@caramelcottage.in';
  static const String demoPassword = 'demo1234';

  final FakeAuthService auth;
  final FakeLocationRepository locations;
  final FakeSummaryRepository summaries;
  final FakeStockRepository stock;
  final FakeCatalogRepository catalog;

  List<Override> get overrides => [
    authServiceProvider.overrideWithValue(auth),
    locationRepositoryProvider.overrideWithValue(locations),
    summaryRepositoryProvider.overrideWithValue(summaries),
    stockRepositoryProvider.overrideWithValue(stock),
    catalogRepositoryProvider.overrideWithValue(catalog),
  ];

  static const Role adminRole = Role(
    id: SeedRoles.adminId,
    name: 'Admin',
    permissions: SeedRoles.adminPermissions,
    allLocations: true,
  );

  static const Role storeManagerRole = Role(
    id: SeedRoles.storeManagerId,
    name: 'Store Manager',
    permissions: SeedRoles.storeManagerPermissions,
    allLocations: false,
  );

  static SessionContext adminSession() => const SessionContext(
    user: AppUser(
      uid: 'admin-0001',
      name: 'Admin',
      email: adminEmail,
      roleId: SeedRoles.adminId,
      locationId: null,
      active: true,
      createdBy: 'seed',
    ),
    role: adminRole,
    location: null,
  );

  static SessionContext storeManagerSession(String locationId) =>
      SessionContext(
        user: AppUser(
          uid: 'sm-$locationId',
          name: 'Store Manager $locationId',
          email: storeManagerEmail,
          roleId: SeedRoles.storeManagerId,
          locationId: locationId,
          active: true,
          createdBy: 'admin-0001',
        ),
        role: storeManagerRole,
        location: seedLocations.firstWhere((l) => l.code == locationId),
      );

  static Location location(String code, String name) => Location(
    code: code,
    name: name,
    address: '$name, Kerala',
    phone: '0466 000 0000',
    overridePinHash: 'fake\$fake',
    receiptFooter: 'Thank you! Visit caramelcottage.in',
    nextDeviceNo: 3,
    active: true,
  );

  static final List<Location> seedLocations = [
    location('PTB', 'Pattambi'),
    location('MNJ', 'Manjeri'),
  ];

  static Product product(String id, String name, String category, int rupees) =>
      Product(
        id: id,
        name: name,
        category: category,
        scope: Product.globalScope,
        status: ProductStatus.active,
        sortOrder: 0,
        createdBy: 'seed',
        price: Money.rupees(rupees),
      );

  static final List<Product> seedProducts = [
    product('bf1kg', 'Black Forest 1 kg', 'Cakes', 650),
    product('bf500', 'Black Forest 500 g', 'Cakes', 350),
    product('rv1kg', 'Red Velvet 1 kg', 'Cakes', 800),
    product('pinepastry', 'Pineapple Pastry', 'Pastries', 60),
    product('chocpastry', 'Chocolate Pastry', 'Pastries', 70),
    product('vegpuff', 'Veg Puff', 'Snacks', 25),
    product('cupcake6', 'Cupcakes (box of 6)', 'Cupcakes', 240),
    product('brownie', 'Brownie', 'Snacks', 80),
  ];

  // Most a location sells of each product per day, at scale 10.
  static const Map<String, int> _dailyMax = {
    'bf1kg': 4,
    'bf500': 6,
    'rv1kg': 3,
    'pinepastry': 25,
    'chocpastry': 25,
    'vegpuff': 40,
    'cupcake6': 5,
    'brownie': 15,
  };

  static const List<RawMaterial> _seedMaterials = [
    RawMaterial(
      id: 'flour',
      name: 'Flour',
      unit: StockUnit.g,
      active: true,
      createdBy: 'seed',
    ),
    RawMaterial(
      id: 'cream',
      name: 'Whipping cream',
      unit: StockUnit.ml,
      active: true,
      createdBy: 'seed',
    ),
    RawMaterial(
      id: 'eggs',
      name: 'Eggs',
      unit: StockUnit.pcs,
      active: true,
      createdBy: 'seed',
    ),
  ];

  static StockItem _item(
    StockKind kind,
    String refId,
    String name,
    StockUnit unit,
    int qty,
    int? threshold,
  ) => StockItem(
    itemKey: '${kind == StockKind.raw ? 'RM' : 'FG'}_$refId',
    kind: kind,
    refId: refId,
    name: name,
    unit: unit,
    qty: qty,
    lowThreshold: threshold,
  );

  static final Map<String, List<StockItem>> _seedStock = {
    'PTB': [
      _item(StockKind.raw, 'flour', 'Flour', StockUnit.g, 4000, 5000),
      _item(StockKind.raw, 'cream', 'Whipping cream', StockUnit.ml, 9000, 3000),
      _item(StockKind.raw, 'eggs', 'Eggs', StockUnit.pcs, 24, 30),
      _item(
        StockKind.finished,
        'bf1kg',
        'Black Forest 1 kg',
        StockUnit.pcs,
        3,
        2,
      ),
      _item(StockKind.finished, 'vegpuff', 'Veg Puff', StockUnit.pcs, 60, null),
    ],
    'MNJ': [
      _item(StockKind.raw, 'flour', 'Flour', StockUnit.g, 12000, 5000),
      _item(StockKind.raw, 'cream', 'Whipping cream', StockUnit.ml, 2500, 3000),
      _item(StockKind.raw, 'eggs', 'Eggs', StockUnit.pcs, 90, 30),
      _item(
        StockKind.finished,
        'rv1kg',
        'Red Velvet 1 kg',
        StockUnit.pcs,
        2,
        1,
      ),
    ],
  };

  static Iterable<String> _dates(String today) sync* {
    final month = int.parse(today.substring(5, 7));
    var year = int.parse(today.substring(0, 4));
    var startMonth = month - 2;
    if (startMonth < 1) {
      startMonth += 12;
      year -= 1;
    }
    var d = '$year-${startMonth.toString().padLeft(2, '0')}-01';
    while (d.compareTo(today) <= 0) {
      yield d;
      d = BusinessDate.addDays(d, 1);
    }
  }

  /// One plausible day. Consistent with `SummaryDelta`: byMode adds up to
  /// net revenue, byProduct amounts are net of the discount, a cancelled
  /// bill stays in netSales and is reversed out of byMode and byProduct.
  static Summary _day(Random rng, int scale) {
    final prices = {for (final p in seedProducts) p.id: p.price!};
    final qty = <String, int>{};
    var gross = Money.zero;
    for (final e in _dailyMax.entries) {
      final q = rng.nextInt(e.value * scale ~/ 10 + 1);
      if (q == 0) continue;
      qty[e.key] = q;
      gross += prices[e.key]!.times(q);
    }
    if (gross.isZero) return const Summary();
    final discountPct = rng.nextInt(4);
    final discount = Money(divideRounded(gross.paise * discountPct, 100));
    final taxable = gross - discount;
    final net = taxable.roundToRupee();

    // Spread the discount over the products; the last one takes the rest.
    final byProduct = <String, ProductTally>{};
    var allocated = Money.zero;
    final ids = qty.keys.toList();
    for (var i = 0; i < ids.length; i++) {
      final line = prices[ids[i]]!.times(qty[ids[i]]!);
      final share = i == ids.length - 1
          ? discount - allocated
          : Money(divideRounded(discount.paise * line.paise, gross.paise));
      allocated += share;
      byProduct[ids[i]] = ProductTally(qty: qty[ids[i]]!, amount: line - share);
    }

    var billCount = max(1, qty.values.fold(0, (a, b) => a + b) ~/ 3);
    var grossSales = gross;
    var netSales = net;
    var cancelCount = 0;
    var cancelled = Money.zero;
    if (rng.nextInt(100) < 15) {
      cancelCount = 1;
      cancelled = Money.rupees(150 + 50 * rng.nextInt(10));
      billCount += 1;
      grossSales += cancelled;
      netSales += cancelled;
    }

    var returnCount = 0;
    var returns = Money.zero;
    if (rng.nextInt(100) < 20) {
      final id = ids[rng.nextInt(ids.length)];
      final t = byProduct[id]!;
      returnCount = 1;
      returns = Money(divideRounded(t.amount.paise, t.qty)).roundToRupee();
      byProduct[id] = ProductTally(qty: t.qty - 1, amount: t.amount - returns);
    }

    // Payments of the day's remaining sales, then refunds out of cash.
    final upi = Money(divideRounded(net.paise * 40, 100)).roundToRupee();
    final card = Money(divideRounded(net.paise * 10, 100)).roundToRupee();
    final wallet = Money(divideRounded(net.paise * 5, 100)).roundToRupee();
    final cash = net - upi - card - wallet - returns;

    return Summary(
      billCount: billCount,
      cancelCount: cancelCount,
      returnCount: returnCount,
      grossSales: grossSales,
      discounts: discount,
      roundOff: net - taxable,
      netSales: netSales,
      returns: returns,
      cancelled: cancelled,
      byMode: {
        PaymentMode.cash: cash,
        PaymentMode.upi: upi,
        PaymentMode.card: card,
        PaymentMode.wallet: wallet,
      },
      byProduct: byProduct,
    );
  }

  static Summary _expenses(Random rng, int scale) {
    final rent = Money.rupees(3500 * scale);
    final salary = Money.rupees(6000 * scale);
    final utilities = Money.rupees(600 * scale + 50 * rng.nextInt(40));
    final other = Money.rupees(100 * rng.nextInt(50));
    return Summary(
      expenses: rent + salary + utilities + other,
      byExpenseCategory: {
        ExpenseCategory.rent: rent,
        ExpenseCategory.salary: salary,
        ExpenseCategory.utilities: utilities,
        ExpenseCategory.other: other,
      },
    );
  }
}
