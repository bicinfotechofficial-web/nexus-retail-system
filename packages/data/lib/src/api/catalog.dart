import 'package:nexus_core/nexus_core.dart';

abstract interface class CatalogRepository {
  /// Active, priced products sellable at [locationId], by `sortOrder`.
  Stream<List<Product>> watchSellable(String locationId);

  /// Every product in any status. Admin catalog screen.
  Stream<List<Product>> watchAll();

  /// PENDING suggestions awaiting approval (D-008).
  Stream<List<Product>> watchPending();

  Stream<List<RawMaterial>> watchRawMaterials();
}

abstract interface class CatalogService {
  /// A Store Manager's local special: PENDING, scoped to their location,
  /// with a proposed price (`catalog.suggest`).
  Future<Product> suggest({
    required String name,
    required String category,
    required Money proposedPrice,
  });

  /// Creates or edits a product (`catalog.manage`). A price change writes a
  /// PRICE_CHANGE audit entry in the same batch.
  Future<Product> save(Product product);

  /// Sets the price and makes a PENDING product ACTIVE, with a
  /// PRODUCT_APPROVE audit entry (`catalog.manage`).
  Future<Product> approve({required String productId, required Money price});

  /// `rawMaterial.create`.
  Future<RawMaterial> addRawMaterial({
    required String name,
    required StockUnit unit,
  });
}
