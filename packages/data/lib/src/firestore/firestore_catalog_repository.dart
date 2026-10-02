import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nexus_core/nexus_core.dart';

import '../api/catalog.dart';
import '../convert/firestore_values.dart';
import 'failure_mapping.dart';

/// [CatalogRepository] over `products` and `rawMaterials`.
///
/// `watchSellable` is also the prefetch of the active products (03-SYNC §8):
/// its listener keeps them in the cache for offline billing.
final class FirestoreCatalogRepository implements CatalogRepository {
  FirestoreCatalogRepository(this._db, {DateTime Function()? clock})
    : _now = clock ?? DateTime.now;

  final FirebaseFirestore _db;
  final DateTime Function() _now;

  CollectionReference<Map<String, dynamic>> get _products =>
      _db.collection(FirestorePaths.products);

  /// `status == ACTIVE` ordered by `sortOrder` (index: products
  /// `status ASC, sortOrder ASC`). Firestore can't express "price not null
  /// and scope is GLOBAL or this location" next to that, so the rest of
  /// `Product.isSellableAt` is applied here. The listener therefore also reads
  /// other locations' active specials (and unpriced active products, which
  /// shouldn't exist), and drops them; there are few of those.
  @override
  Stream<List<Product>> watchSellable(String locationId) => _products
      .where('status', isEqualTo: ProductStatus.active.wire)
      .orderBy('sortOrder')
      .snapshots()
      .map(
        (s) => [
          for (final p in _toProducts(s))
            if (p.isSellableAt(locationId)) p,
        ],
      )
      .mapFirestoreErrors();

  @override
  Stream<List<Product>> watchAll() =>
      _products.snapshots().map(_sorted).mapFirestoreErrors();

  @override
  Stream<List<Product>> watchPending() => _products
      .where('status', isEqualTo: ProductStatus.pending.wire)
      .snapshots()
      .map(_sorted)
      .mapFirestoreErrors();

  /// The user's own suggestions at [locationId] in any status, newest first
  /// (D-038). Two equality filters, so no composite index; sorted here by
  /// `createdAt` (a suggestion still waiting for its server time counts as
  /// created now, see `plainFromFirestore`). A Store Manager may read it:
  /// products need `catalog.view` (rule #11).
  @override
  Stream<List<Product>> watchMySuggestions(String locationId, String uid) =>
      _products
          .where('createdBy', isEqualTo: uid)
          .where('scope', isEqualTo: locationId)
          .snapshots()
          .map(
            (s) => _toProducts(s)
              ..sort((a, b) {
                final c = _stamp(b.createdAt).compareTo(_stamp(a.createdAt));
                return c != 0 ? c : b.id.compareTo(a.id);
              }),
          )
          .mapFirestoreErrors();

  /// Every raw material, active or not, by name.
  @override
  Stream<List<RawMaterial>> watchRawMaterials() => _db
      .collection(FirestorePaths.rawMaterials)
      .snapshots()
      .map(
        (s) =>
            modelsOf(s, RawMaterial.fromMap)
              ..sort((a, b) => _byName(a.name, b.name, a.id, b.id)),
      )
      .mapFirestoreErrors();

  List<Product> _toProducts(QuerySnapshot<Map<String, dynamic>> s) => modelsOf(
    s,
    Product.fromMap,
    serverTimestampFields: Product.serverTimestampFields,
    now: _now,
  );

  /// By `sortOrder`, then name, so the order is stable.
  List<Product> _sorted(QuerySnapshot<Map<String, dynamic>> s) =>
      _toProducts(s)..sort((a, b) {
        final c = a.sortOrder.compareTo(b.sortOrder);
        return c != 0 ? c : _byName(a.name, b.name, a.id, b.id);
      });
}

int _byName(String a, String b, String idA, String idB) {
  final c = a.toLowerCase().compareTo(b.toLowerCase());
  return c != 0 ? c : idA.compareTo(idB);
}

/// A missing `createdAt` (not yet confirmed and not estimated) sorts as the
/// newest.
DateTime _stamp(DateTime? at) => at ?? DateTime.utc(9999);
