import 'dart:math';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';

import '../data/providers.dart';
import 'fake_expenses.dart';
import 'fake_repositories.dart';
import 'fake_services.dart';

/// In-memory fakes of every `nexus_data` interface the console uses,
/// selected with `--dart-define=FAKE_DATA=true`.
final class FakeBackend {
  FakeBackend({
    required this.auth,
    required this.locations,
    required this.summaries,
    required this.stock,
    required this.catalog,
    FakeUserRepository? users,
    FakeDeviceService? devices,
    FakeAuditTrail? audit,
    List<Expense> expenses = const [],
  }) : users = users ?? FakeUserRepository(const []),
       devices = devices ?? FakeDeviceService(const {}, locations),
       audit = audit ?? FakeAuditTrail() {
    this.expenses = FakeExpenses(
      summaries: summaries,
      locations: locations,
      audit: this.audit,
      auth: auth,
    );
    expenses.forEach(this.expenses.seed);
    catalogService = FakeCatalogService(catalog, auth, this.audit);
    locationService = FakeLocationService(locations, this.audit);
    userService = FakeUserService(
      users: this.users,
      auth: auth,
      locations: locations,
      storeManagerRole: storeManagerRole,
      audit: this.audit,
    );
  }

  /// Two open locations (PTB, MNJ) and one closed in August (KTL), an Admin
  /// and Store Managers, a catalog with two PENDING suggestions, three
  /// devices per open location, daily and monthly summaries from the 1st of
  /// the month two months before [today] up to [today] (KTL only until it
  /// closed), each month's expenses (fed into the monthly summaries with
  /// `SummaryDeltas.forExpense`), stock with a few low and one negative
  /// item, and audit entries of every action. Deterministic for a given
  /// [seed].
  factory FakeBackend.seeded({required String today, int seed = 42}) {
    final daily = <String, Map<String, Summary>>{};
    final monthly = <String, Map<String, Summary>>{};
    final expenses = <Expense>[];
    final rng = Random(seed);
    final dates = _dates(today).toList();
    for (final loc in seedLocations) {
      final scale = switch (loc.code) {
        'PTB' => 10,
        'MNJ' => 7,
        _ => 5,
      };
      // A closed location has history up to its closing day only.
      final last = loc.active ? today : BusinessDate.addDays(dates.first, 44);
      final days = <String, Summary>{};
      for (final date in dates) {
        if (date.compareTo(last) > 0) break;
        days[date] = _day(rng, scale);
      }
      daily[loc.code] = days;
      final months = <String, Summary>{};
      for (final e in days.entries) {
        final key = BusinessDate.monthOf(e.key);
        months[key] = (months[key] ?? const Summary()) + e.value;
      }
      monthly[loc.code] = months;
      for (final month in months.keys) {
        expenses.addAll(_expenses(rng, scale, loc.code, month, last));
      }
    }
    final locations = FakeLocationRepository(seedLocations);
    final mnjManager = SessionContext(
      user: const AppUser(
        uid: 'sm-MNJ',
        name: 'Store Manager MNJ',
        email: 'manager.mnj@caramelcottage.in',
        roleId: SeedRoles.storeManagerId,
        locationId: 'MNJ',
        active: true,
        createdBy: 'admin-0001',
      ),
      role: storeManagerRole,
      location: seedLocations.firstWhere((l) => l.code == 'MNJ'),
    );
    const relief = AppUser(
      uid: 'sm-PTB-relief',
      name: 'Relief Store Manager PTB',
      email: 'relief.ptb@caramelcottage.in',
      roleId: SeedRoles.storeManagerId,
      locationId: 'PTB',
      active: false,
      createdBy: 'admin-0001',
    );
    return FakeBackend(
      auth: FakeAuthService({
        adminEmail: (password: demoPassword, session: adminSession()),
        storeManagerEmail: (
          password: demoPassword,
          session: storeManagerSession('PTB'),
        ),
        mnjManager.user.email: (password: demoPassword, session: mnjManager),
      }),
      locations: locations,
      summaries: FakeSummaryRepository(dailyDocs: daily, monthlyDocs: monthly),
      stock: FakeStockRepository(_seedStock),
      catalog: FakeCatalogRepository(
        products: [...seedProducts, ..._seedCatalogExtras],
        materials: _seedMaterials,
      ),
      users: FakeUserRepository([
        adminSession().user,
        storeManagerSession('PTB').user,
        mnjManager.user,
        relief,
      ]),
      devices: FakeDeviceService(_seedDevices(today), locations),
      audit: FakeAuditTrail(seeded: _seedAudit(today)),
      expenses: expenses,
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
  final FakeUserRepository users;
  final FakeDeviceService devices;
  final FakeAuditTrail audit;
  late final FakeExpenses expenses;
  late final FakeCatalogService catalogService;
  late final FakeLocationService locationService;

  /// Replaceable, so a test can swap in a failing service.
  late UserService userService;

  List<Override> get overrides => [
    authServiceProvider.overrideWithValue(auth),
    locationRepositoryProvider.overrideWithValue(locations),
    summaryRepositoryProvider.overrideWithValue(summaries),
    stockRepositoryProvider.overrideWithValue(stock),
    catalogRepositoryProvider.overrideWithValue(catalog),
    catalogServiceProvider.overrideWithValue(catalogService),
    locationServiceProvider.overrideWithValue(locationService),
    userRepositoryProvider.overrideWithValue(users),
    userServiceProvider.overrideWithValue(userService),
    deviceServiceProvider.overrideWithValue(devices),
    expenseRepositoryProvider.overrideWithValue(expenses),
    expenseServiceProvider.overrideWithValue(expenses),
    auditRepositoryProvider.overrideWithValue(audit),
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

  static Location location(String code, String name, {bool active = true}) =>
      Location(
        code: code,
        name: name,
        address: '$name, Kerala',
        phone: '0466 000 0000',
        overridePinHash: 'fake\$fake',
        receiptFooter: 'Thank you! Visit caramelcottage.in',
        nextDeviceNo: 3,
        active: active,
      );

  static final List<Location> seedLocations = [
    location('PTB', 'Pattambi'),
    location('MNJ', 'Manjeri'),
    location('KTL', 'Kottakkal', active: false),
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

  /// Two Store Manager suggestions awaiting approval and a retired product.
  static final List<Product> _seedCatalogExtras = [
    Product(
      id: 'sugplum',
      name: 'Plum Cake 500 g',
      category: 'Cakes',
      scope: 'MNJ',
      status: ProductStatus.pending,
      sortOrder: 0,
      createdBy: 'sm-MNJ',
      proposedPrice: Money.rupees(420),
    ),
    Product(
      id: 'sugpudding',
      name: 'Tender Coconut Pudding',
      category: 'Desserts',
      scope: 'PTB',
      status: ProductStatus.pending,
      sortOrder: 0,
      createdBy: 'sm-PTB',
      proposedPrice: Money.rupees(110),
    ),
    Product(
      id: 'fruitcake',
      name: 'Fruit Cake 1 kg',
      category: 'Cakes',
      scope: Product.globalScope,
      status: ProductStatus.inactive,
      sortOrder: 0,
      createdBy: 'seed',
      price: Money.rupees(700),
    ),
  ];

  /// D01 to D03 at each location (`nextDeviceNo` is 3), one retired.
  static Map<String, List<Device>> _seedDevices(String today) {
    final start = BusinessDate.startOf(today);
    Device device(
      String code,
      String label,
      String by,
      int billSeq, {
      Duration? seenAgo,
      bool retired = false,
    }) => Device(
      code: code,
      label: label,
      registeredBy: by,
      lastBillSeq: billSeq,
      retired: retired,
      registeredAt: start.subtract(const Duration(days: 60)),
      lastSeenAt: seenAgo == null
          ? null
          : start.add(const Duration(hours: 11)).subtract(seenAgo),
    );
    return {
      'PTB': [
        device('D01', 'Counter 1', 'sm-PTB', 1840, seenAgo: Duration.zero),
        device(
          'D02',
          'Counter 2',
          'sm-PTB',
          905,
          seenAgo: const Duration(minutes: 40),
        ),
        device(
          'D03',
          'Old counter tablet',
          'sm-PTB',
          212,
          seenAgo: const Duration(days: 20),
          retired: true,
        ),
      ],
      'MNJ': [
        device('D01', 'Counter 1', 'sm-MNJ', 1322, seenAgo: Duration.zero),
        device(
          'D02',
          'Back office',
          'sm-MNJ',
          77,
          seenAgo: const Duration(days: 3),
        ),
        device('D03', 'Spare phone', 'sm-MNJ', 0),
      ],
    };
  }

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
      // Sold offline past the last count; negative until the next adjust.
      _item(
        StockKind.finished,
        'chocpastry',
        'Chocolate Pastry',
        StockUnit.pcs,
        -3,
        5,
      ),
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

  /// A month's rent, salaries, utilities and sundries at [loc], dated no
  /// later than [last] (today, or the day a closed location shut).
  static List<Expense> _expenses(
    Random rng,
    int scale,
    String loc,
    String month,
    String last,
  ) {
    String on(int day) {
      final d = '$month-${day.toString().padLeft(2, '0')}';
      return d.compareTo(last) > 0 ? last : d;
    }

    Expense e(String kind, ExpenseCategory c, int rupees, int day, String n) =>
        Expense(
          id: 'seed-$loc-$month-$kind',
          locationId: loc,
          category: c,
          amount: Money.rupees(rupees),
          date: on(day),
          note: n,
          createdBy: 'admin-0001',
        );

    return [
      e('rent', ExpenseCategory.rent, 3500 * scale, 1, 'Shop rent'),
      e('salary', ExpenseCategory.salary, 6000 * scale, 1, 'Staff salaries'),
      e(
        'power',
        ExpenseCategory.utilities,
        600 * scale + 50 * rng.nextInt(40),
        12,
        'Electricity',
      ),
      e(
        'other',
        ExpenseCategory.other,
        100 + 100 * rng.nextInt(50),
        20,
        'Packaging and sundries',
      ),
    ];
  }

  /// A few weeks of audit history with at least one entry of each action.
  static List<AuditEntry> _seedAudit(String today) {
    final start = BusinessDate.startOf(today);
    var n = 0;
    AuditEntry entry(
      AuditAction action,
      String? loc,
      String entityPath,
      String by,
      Duration ago, {
      Map<String, Object?>? before,
      Map<String, Object?>? after,
      String? reason,
      String? deviceId,
    }) {
      final at = start.add(const Duration(hours: 10)).subtract(ago);
      return AuditEntry(
        id: 'seed-audit-${n++}',
        action: action,
        entityPath: entityPath,
        locationId: loc,
        before: before,
        after: after,
        reason: reason,
        by: by,
        deviceId: deviceId,
        at: at,
        clientAt: at,
      );
    }

    const day = Duration(days: 1);
    return [
      entry(
        AuditAction.locationUpdate,
        'KTL',
        FirestorePaths.location('KTL'),
        'admin-0001',
        day * 40,
        before: {'name': 'Kottakkal', 'active': true},
        after: {'name': 'Kottakkal', 'active': false},
      ),
      entry(
        AuditAction.userCreate,
        'MNJ',
        FirestorePaths.user('sm-MNJ'),
        'admin-0001',
        day * 30,
        after: {'email': 'manager.mnj@caramelcottage.in', 'active': true},
      ),
      entry(
        AuditAction.userDisable,
        'PTB',
        FirestorePaths.user('sm-PTB-relief'),
        'admin-0001',
        day * 25,
        before: {'active': true},
        after: {'active': false},
      ),
      entry(
        AuditAction.productApprove,
        null,
        FirestorePaths.product('cupcake6'),
        'admin-0001',
        day * 21,
        before: {'status': 'PENDING', 'price': null, 'proposedPrice': 22000},
        after: {'status': 'ACTIVE', 'price': 24000, 'proposedPrice': 22000},
      ),
      entry(
        AuditAction.priceChange,
        null,
        FirestorePaths.product('bf1kg'),
        'admin-0001',
        day * 14,
        before: {'price': 60000},
        after: {'price': 65000},
      ),
      entry(
        AuditAction.expenseCreate,
        'PTB',
        FirestorePaths.expense('seed-PTB-power'),
        'admin-0001',
        day * 12,
        after: {'category': 'UTILITIES', 'amount': 620000, 'note': 'Power'},
      ),
      entry(
        AuditAction.expenseUpdate,
        'PTB',
        FirestorePaths.expense('seed-PTB-power'),
        'admin-0001',
        day * 11,
        before: {'category': 'UTILITIES', 'amount': 620000, 'note': 'Power'},
        after: {
          'category': 'UTILITIES',
          'amount': 640000,
          'note': 'Electricity',
        },
      ),
      entry(
        AuditAction.thresholdChange,
        'MNJ',
        FirestorePaths.stockItem('MNJ', 'RM_cream'),
        'sm-MNJ',
        day * 9,
        before: {'lowThreshold': 2000},
        after: {'lowThreshold': 3000},
        deviceId: 'D01',
      ),
      entry(
        AuditAction.stockAdjust,
        'PTB',
        FirestorePaths.movement('PTB', 'D01-M000041'),
        'sm-PTB',
        day * 6,
        before: {'RM_flour': 5200},
        after: {'RM_flour': 4000},
        reason: 'Monthly count',
        deviceId: 'D01',
      ),
      entry(
        AuditAction.wastage,
        'MNJ',
        FirestorePaths.movement('MNJ', 'D01-M000017'),
        'sm-MNJ',
        day * 4,
        after: {'FG_rv1kg': -1},
        reason: 'Dropped while boxing',
        deviceId: 'D01',
      ),
      entry(
        AuditAction.offlineOverride,
        'MNJ',
        FirestorePaths.device('MNJ', 'D02'),
        'sm-MNJ',
        day * 3,
        after: {'extensionHours': 24},
        reason: 'Internet down at the shop',
        deviceId: 'D02',
      ),
      entry(
        AuditAction.billCancel,
        'PTB',
        FirestorePaths.bill('PTB', 'D02-000901'),
        'sm-PTB',
        day * 2,
        before: {'status': 'COMPLETED', 'total': 70000},
        after: {'status': 'CANCELLED', 'total': 70000},
        reason: 'Wrong cake billed',
        deviceId: 'D02',
      ),
      entry(
        AuditAction.returned,
        'PTB',
        FirestorePaths.saleReturn('PTB', 'D01-R000007'),
        'sm-PTB',
        const Duration(hours: 5),
        after: {'refundTotal': 6000, 'lines': 1},
        reason: 'Pastry was stale',
        deviceId: 'D01',
      ),
    ];
  }
}
