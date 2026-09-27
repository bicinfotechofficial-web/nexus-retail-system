// PLAN.md F-1 and F-3 for the device scenarios, written straight to the
// emulator (rules off) before each scenario. Built from the `nexus_core`
// models, so the seed has exactly the shape the contracts define.

import 'package:nexus_core/nexus_core.dart';

import 'emulator.dart';

/// A signed-in identity used by the scenarios.
final class Actor {
  const Actor(this.key, this.email, this.name, this.roleId, this.locationId);

  final String key;
  final String email;
  final String name;
  final String roleId;
  final String? locationId;

  static const String password = 'qa-device-scenarios';
}

abstract final class Fx {
  static const String ptb = 'PTB';
  static const String mnj = 'MNJ';

  static const Actor admin = Actor(
    'admin',
    'admin@example.test',
    'Admin',
    SeedRoles.adminId,
    null,
  );
  static const Actor smPtb = Actor(
    'smPtb',
    'sm-ptb@example.test',
    'Store Manager PTB',
    SeedRoles.storeManagerId,
    ptb,
  );
  static const Actor smMnj = Actor(
    'smMnj',
    'sm-mnj@example.test',
    'Store Manager MNJ',
    SeedRoles.storeManagerId,
    mnj,
  );
  static const List<Actor> actors = [admin, smPtb, smMnj];

  /// Paise prices that don't divide evenly, so rounding shows (F-1).
  static const Product blackForest = Product(
    id: 'black-forest-1kg',
    name: 'Black Forest 1 kg',
    category: 'Cakes',
    price: Money(65000),
    scope: Product.globalScope,
    status: ProductStatus.active,
    sortOrder: 1,
    createdBy: 'seed',
  );
  static const Product vegPuff = Product(
    id: 'veg-puff',
    name: 'Veg Puff',
    category: 'Snacks',
    price: Money(2550),
    scope: Product.globalScope,
    status: ProductStatus.active,
    sortOrder: 2,
    createdBy: 'seed',
  );
  static const Product plumCake = Product(
    id: 'plum-cake',
    name: 'Plum Cake 500 g',
    category: 'Cakes',
    price: Money(9999),
    scope: Product.globalScope,
    status: ProductStatus.active,
    sortOrder: 3,
    createdBy: 'seed',
  );
  static const Product cookie = Product(
    id: 'butter-cookie',
    name: 'Butter Cookie',
    category: 'Snacks',
    price: Money(1875),
    scope: Product.globalScope,
    status: ProductStatus.active,
    sortOrder: 4,
    createdBy: 'seed',
  );
  static const Product cupcake = Product(
    id: 'cupcake',
    name: 'Cupcake (3 for ₹5)',
    category: 'Cakes',
    price: Money(167),
    scope: Product.globalScope,
    status: ProductStatus.active,
    sortOrder: 5,
    createdBy: 'seed',
  );
  static const List<Product> products = [
    blackForest,
    vegPuff,
    plumCake,
    cookie,
    cupcake,
  ];

  static const RawMaterial flour = RawMaterial(
    id: 'flour',
    name: 'Maida',
    unit: StockUnit.g,
    active: true,
    createdBy: 'seed',
  );
  static const RawMaterial milk = RawMaterial(
    id: 'milk',
    name: 'Milk',
    unit: StockUnit.ml,
    active: true,
    createdBy: 'seed',
  );
  static const RawMaterial eggs = RawMaterial(
    id: 'eggs',
    name: 'Eggs',
    unit: StockUnit.pcs,
    active: true,
    createdBy: 'seed',
  );
  static const List<RawMaterial> materials = [flour, milk, eggs];

  /// F-3 opening stock at PTB and MNJ, in base units.
  static const Map<String, int> opening = {
    'FG_black-forest-1kg': 10,
    'FG_veg-puff': 100,
    'FG_plum-cake': 20,
    'FG_butter-cookie': 200,
    'FG_cupcake': 30,
    'RM_flour': 10000,
    'RM_milk': 5000,
    'RM_eggs': 60,
  };

  /// The device code the harness writes seed documents as. Registration in
  /// these scenarios never gets this far (at most D02), so its IDs never
  /// clash with a device's.
  static const String seedDevice = 'D99';

  static CartLine line(Product p, int qty) =>
      CartLine(productId: p.id, name: p.name, qty: qty, unitPrice: p.price!);

  static Location location(String code, String name, {int? maxDiscountPct}) =>
      Location(
        code: code,
        name: name,
        address: '$name address',
        phone: '0000000000',
        // Not a real PBKDF2 hash: no scenario here uses the PIN override.
        overridePinHash: 'cWEtZml4dHVyZQ==\$cWEtZml4dHVyZQ==',
        receiptFooter: 'Thank you!',
        nextDeviceNo: 0,
        active: true,
        maxDiscountPct: maxDiscountPct,
      );
}

/// Writes F-1 (roles, users, locations, catalogue) and F-3 (opening stock)
/// to an emptied emulator. Returns uid by actor key.
Future<Map<String, String>> writeSeed(EmulatorAdmin admin) async {
  final now = DateTime.now().toUtc();
  final today = BusinessDate.of(now);

  for (final r in [
    const Role(
      id: SeedRoles.adminId,
      name: 'Admin',
      permissions: SeedRoles.adminPermissions,
      allLocations: true,
    ),
    const Role(
      id: SeedRoles.storeManagerId,
      name: 'Store Manager',
      permissions: SeedRoles.storeManagerPermissions,
      allLocations: false,
    ),
  ]) {
    await admin.set(FirestorePaths.role(r.id), r.toMap());
  }

  for (final l in [
    Fx.location(Fx.ptb, 'Pattambi'),
    Fx.location(Fx.mnj, 'Manjeri', maxDiscountPct: 20),
  ]) {
    await admin.set(FirestorePaths.location(l.code), l.toMap());
  }

  final uids = <String, String>{};
  for (final a in Fx.actors) {
    final uid = await admin.createAuthUser(a.email, Actor.password);
    uids[a.key] = uid;
    final user = AppUser(
      uid: uid,
      name: a.name,
      email: a.email,
      roleId: a.roleId,
      locationId: a.locationId,
      active: true,
      createdBy: 'seed',
    );
    await admin.set(FirestorePaths.user(uid), {
      ...user.toMap(),
      'createdAt': now,
    });
  }

  for (final p in Fx.products) {
    await admin.set(FirestorePaths.product(p.id), {
      ...p.toMap(),
      'createdAt': now,
      'updatedAt': now,
    });
  }
  for (final m in Fx.materials) {
    await admin.set(FirestorePaths.rawMaterial(m.id), m.toMap());
  }

  // Opening stock: one seed movement per location, and stock docs equal to
  // it, so the stock oracle (qty == Σ movement deltas) holds from the start.
  for (final loc in [Fx.ptb, Fx.mnj]) {
    final id = Ids.movementId(Fx.seedDevice, 1);
    final movement = Movement(
      id: id,
      type: MovementType.stockIn,
      lines: [
        for (final e in Fx.opening.entries)
          MovementLine(itemKey: e.key, delta: e.value),
      ],
      note: 'Opening stock (QA seed)',
      businessDate: today,
      clientCreatedAt: now,
      createdBy: 'seed',
      deviceId: Fx.seedDevice,
    );
    await admin.set(FirestorePaths.movement(loc, id), {
      ...movement.toMap(),
      'serverCreatedAt': now,
    });
    for (final e in Fx.opening.entries) {
      final raw = e.key.startsWith('RM_');
      final refId = e.key.substring(3);
      final name = raw
          ? Fx.materials.firstWhere((m) => m.id == refId).name
          : Fx.products.firstWhere((p) => p.id == refId).name;
      final unit = raw
          ? Fx.materials.firstWhere((m) => m.id == refId).unit
          : StockUnit.pcs;
      final item = StockItem(
        itemKey: e.key,
        kind: raw ? StockKind.raw : StockKind.finished,
        refId: refId,
        name: name,
        unit: unit,
        qty: e.value,
        lastMovementId: id,
      );
      await admin.set(FirestorePaths.stockItem(loc, e.key), {
        ...item.toMap(),
        'updatedAt': now,
      });
    }
  }
  return uids;
}

/// A COMPLETED bill written by the harness, for scenarios that need one the
/// device didn't make (e.g. yesterday's). Its summary increments are
/// seeded too, so the summary oracle still holds. Uses [Fx.seedDevice].
Future<Bill> seedBill(
  EmulatorAdmin admin, {
  required String locationId,
  required String businessDate,
  required String createdBy,
  required List<CartLine> cart,
  int seq = 1,
}) async {
  final totals = BillCalculator.compute(cart);
  final id = Ids.billId(Fx.seedDevice, seq);
  final at = BusinessDate.startOf(businessDate).add(const Duration(hours: 12));
  final bill = Bill(
    id: id,
    billNo: Ids.billNo(locationId, id),
    deviceId: Fx.seedDevice,
    seq: seq,
    lines: totals.lines,
    subtotal: totals.subtotal,
    discount: totals.discount,
    taxableValue: totals.taxableValue,
    taxLines: totals.taxLines,
    roundOff: totals.roundOff,
    total: totals.total,
    payments: [Payment(mode: PaymentMode.cash, amount: totals.total)],
    status: BillStatus.completed,
    servedBy: ServedBy(uid: createdBy, name: 'Seeded'),
    businessDate: businessDate,
    clientCreatedAt: at,
    serverCreatedAt: at,
    createdBy: createdBy,
  );
  await admin.set(FirestorePaths.bill(locationId, id), {
    ...bill.toMap(),
    'serverCreatedAt': at,
  });
  final delta = SummaryDeltas.forBill(bill).toMap()
    ..['lastWriteRef'] = FirestorePaths.bill(locationId, id);
  await admin.set(FirestorePaths.dailySummary(locationId, businessDate), delta);
  await admin.set(
    FirestorePaths.monthlySummary(
      locationId,
      BusinessDate.monthOf(businessDate),
    ),
    delta,
  );
  return bill;
}
