import '../enums.dart';
import '../map_reader.dart';
import '../money.dart';

/// `products/{productId}`. Each sellable size is its own product (D-007).
final class Product {
  const Product({
    required this.id,
    required this.name,
    required this.category,
    required this.scope,
    required this.status,
    required this.sortOrder,
    required this.createdBy,
    this.price,
    this.proposedPrice,
    this.unit = StockUnit.pcs,
    this.gstRate,
    this.recipe,
    this.createdAt,
    this.updatedAt,
  });

  factory Product.fromMap(String id, Map<String, Object?> map) {
    final r = MapReader(map, 'product $id');
    final price = r.integerOrNull('price');
    final proposed = r.integerOrNull('proposedPrice');
    return Product(
      id: id,
      name: r.string('name'),
      category: r.string('category'),
      price: price == null ? null : Money(price),
      proposedPrice: proposed == null ? null : Money(proposed),
      unit: r.enumValue('unit', StockUnit.fromWire),
      gstRate: r.integerOrNull('gstRate'),
      scope: r.string('scope'),
      status: r.enumValue('status', ProductStatus.fromWire),
      recipe: r.objectsOrNull('recipe', RecipeLine._fromReader),
      sortOrder: r.integerOr('sortOrder', 0),
      createdBy: r.string('createdBy'),
      createdAt: r.dateTimeOrNull('createdAt'),
      updatedAt: r.dateTimeOrNull('updatedAt'),
    );
  }

  /// [scope] value for products sold at every location.
  static const String globalScope = 'GLOBAL';

  static const Set<String> serverTimestampFields = {'createdAt', 'updatedAt'};

  final String id;
  final String name;
  final String category;

  /// Null while PENDING (D-008).
  final Money? price;

  /// Set by the Store Manager when suggesting.
  final Money? proposedPrice;
  final StockUnit unit;

  /// Reserved for GST (D-013).
  final int? gstRate;

  /// [globalScope], or a location code for a local special.
  final String scope;
  final ProductStatus status;

  /// Reserved for BOM.
  final List<RecipeLine>? recipe;
  final int sortOrder;
  final String createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Can be put on a bill at [locationId]: active, priced and in scope.
  bool isSellableAt(String locationId) =>
      status == ProductStatus.active &&
      price != null &&
      (scope == globalScope || scope == locationId);

  Map<String, Object?> toMap() => {
    'name': name,
    'category': category,
    'price': price?.paise,
    'proposedPrice': proposedPrice?.paise,
    'unit': unit.wire,
    'gstRate': gstRate,
    'scope': scope,
    'status': status.wire,
    'recipe': recipe?.map((l) => l.toMap()).toList(),
    'sortOrder': sortOrder,
    'createdBy': createdBy,
  };
}

final class RecipeLine {
  const RecipeLine({required this.materialId, required this.qty});

  static RecipeLine _fromReader(MapReader r) =>
      RecipeLine(materialId: r.string('materialId'), qty: r.integer('qty'));

  final String materialId;

  /// Base units (D-006).
  final int qty;

  Map<String, Object?> toMap() => {'materialId': materialId, 'qty': qty};
}
