import 'package:nexus_core/nexus_core.dart';

/// A small, realistic seed for running the POS without Firebase
/// (`--dart-define=FAKE_DATA=true`) and for widget tests. Prices are paise.
abstract final class Seed {
  static const String locationId = 'PTB';
  static const String deviceId = 'D01';
  static const String userId = 'sm-ptb-1';

  static const Location location = Location(
    code: locationId,
    name: 'Caramel Cottage Pattambi',
    address: 'Main Road, Pattambi, Kerala',
    phone: '0466 000 0000',
    overridePinHash: 'c2FsdA==\$aGFzaA==',
    receiptFooter: 'Thank you! Visit caramelcottage.in',
    nextDeviceNo: 2,
    active: true,
    maxDiscountPct: 10,
  );

  static const Role storeManagerRole = Role(
    id: SeedRoles.storeManagerId,
    name: 'Store Manager',
    permissions: SeedRoles.storeManagerPermissions,
    allLocations: false,
  );

  static const AppUser storeManager = AppUser(
    uid: userId,
    name: 'PTB Store Manager',
    email: 'sm.ptb@example.com',
    roleId: SeedRoles.storeManagerId,
    locationId: locationId,
    active: true,
    createdBy: 'seed',
  );

  static List<Product> get products => [
    _p('bf-500', 'Black Forest 500 g', 'Cakes', 45000, 1),
    _p('bf-1k', 'Black Forest 1 kg', 'Cakes', 85000, 2),
    _p('rv-500', 'Red Velvet 500 g', 'Cakes', 55000, 3),
    _p('bs-500', 'Butterscotch 500 g', 'Cakes', 42000, 4),
    _p('ct-1k', 'Chocolate Truffle 1 kg', 'Cakes', 95000, 5),
    _p('plum-400', 'Plum Cake 400 g', 'Cakes', 22000, 6),
    _p('bf-pastry', 'Black Forest Pastry', 'Pastries', 6000, 10),
    _p('rv-pastry', 'Red Velvet Pastry', 'Pastries', 8000, 11),
    _p('pa-pastry', 'Pineapple Pastry', 'Pastries', 5500, 12),
    _p('brownie', 'Walnut Brownie', 'Pastries', 7250, 13),
    _p('cc-muffin', 'Choco Chip Muffin', 'Pastries', 4500, 14),
    _p('veg-puff', 'Veg Puff', 'Snacks', 2500, 20),
    _p('egg-puff', 'Egg Puff', 'Snacks', 3000, 21),
    _p('chk-puff', 'Chicken Puff', 'Snacks', 4000, 22),
    _p('cookies', 'Butter Cookies 200 g', 'Cookies', 12000, 30),
    _p('cc-cookies', 'Choco Chip Cookies 200 g', 'Cookies', 14000, 31),
    // Not sellable at PTB: a pending suggestion and another store's special.
    const Product(
      id: 'jack-cake',
      name: 'Jackfruit Cake 500 g',
      category: 'Cakes',
      scope: locationId,
      status: ProductStatus.pending,
      sortOrder: 7,
      createdBy: userId,
      proposedPrice: Money(48000),
    ),
    _p('mnj-special', 'Manjeri Special 500 g', 'Cakes', 50000, 8, scope: 'MNJ'),
  ];

  static Product _p(
    String id,
    String name,
    String category,
    int paise,
    int sortOrder, {
    String scope = Product.globalScope,
  }) => Product(
    id: id,
    name: name,
    category: category,
    price: Money(paise),
    scope: scope,
    status: ProductStatus.active,
    sortOrder: sortOrder,
    createdBy: 'seed',
  );
}
