import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus_core/nexus_core.dart';

import '../data/providers.dart';

/// Every product in any status, by category, then sort order, then name.
final allProductsProvider = StreamProvider<List<Product>>(
  (ref) => ref
      .watch(catalogRepositoryProvider)
      .watchAll()
      .map((l) => [...l]..sort(compareProducts)),
);

/// PENDING suggestions awaiting approval (D-008).
final pendingProductsProvider = StreamProvider<List<Product>>(
  (ref) => ref.watch(catalogRepositoryProvider).watchPending(),
);

final rawMaterialsProvider = StreamProvider<List<RawMaterial>>(
  (ref) => ref
      .watch(catalogRepositoryProvider)
      .watchRawMaterials()
      .map((l) => [...l]..sort((a, b) => a.name.compareTo(b.name))),
);

int compareProducts(Product a, Product b) {
  final c = a.category.compareTo(b.category);
  if (c != 0) return c;
  final s = a.sortOrder.compareTo(b.sortOrder);
  return s != 0 ? s : a.name.compareTo(b.name);
}

/// A new product ID: `p` plus the time and a random suffix in base 36. It is
/// a safe key (`Ids.isSafeKey`), so it can be a map key in summaries.
String newProductId({DateTime? now, Random? random}) {
  final t = (now ?? DateTime.now()).millisecondsSinceEpoch.toRadixString(36);
  final r = (random ?? Random.secure())
      .nextInt(1 << 20)
      .toRadixString(36)
      .padLeft(4, '0');
  return 'p$t$r';
}

String productStatusLabel(ProductStatus s) => switch (s) {
  ProductStatus.active => 'Active',
  ProductStatus.pending => 'Pending approval',
  ProductStatus.inactive => 'Inactive',
};

String scopeLabel(String scope) =>
    scope == Product.globalScope ? 'All locations' : scope;

String unitLabel(StockUnit u) => switch (u) {
  StockUnit.g => 'Grams (g)',
  StockUnit.ml => 'Millilitres (ml)',
  StockUnit.pcs => 'Pieces (pcs)',
};

/// Parses a rupee amount typed by the Admin. Null when it isn't a positive
/// amount.
Money? parsePositiveMoney(String text) {
  try {
    final m = Money.parse(text.trim());
    return m.isPositive ? m : null;
  } on FormatException {
    return null;
  }
}
