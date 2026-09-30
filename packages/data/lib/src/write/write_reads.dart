import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nexus_core/nexus_core.dart';

import '../api/sales.dart';
import '../convert/firestore_values.dart';
import '../firestore/failure_mapping.dart';

/// The single-doc reads the write services make before building a plan.
/// Null means the doc doesn't exist (or isn't in the cache while offline).
abstract interface class WriteReads {
  /// The bill to cancel or return against.
  Future<Bill?> bill(String locationId, String billId);

  /// A stock doc: the device's view of `qty` for an Adjust (03-SYNC §5),
  /// and the item's name and unit.
  Future<StockItem?> stockItem(String locationId, String itemKey);

  Future<Product?> product(String productId);
  Future<RawMaterial?> rawMaterial(String materialId);
  Future<Expense?> expense(String expenseId);
  Future<Location?> location(String locationId);

  /// This install's device doc, to recover the counters (03-SYNC §3.4).
  Future<Device?> device(String locationId, String deviceId);
}

/// [WriteReads] on Firestore with the default source: the server when it
/// is reachable (so a return is worked out from the bill's latest
/// `lastReturnId`, D-029), otherwise the local cache. Either way the result
/// includes this device's own pending writes. Bills come from the sales
/// repository, the same read the bill screens use.
final class FirestoreWriteReads implements WriteReads {
  FirestoreWriteReads(this._db, this._sales, {DateTime Function()? clock})
    : _now = clock ?? DateTime.now;

  final FirebaseFirestore _db;
  final SalesRepository _sales;
  final DateTime Function() _now;

  Future<T?> _get<T>(
    String path,
    T Function(String id, Map<String, Object?> map) fromMap, {
    Set<String> serverTimestampFields = const {},
  }) => guardFirestore(() async {
    final DocumentSnapshot<Map<String, dynamic>> snap;
    try {
      snap = await _db.doc(path).get(estimateServerTimestamps);
    } on FirebaseException catch (e) {
      // Offline and not in the cache.
      if (e.code == 'unavailable') return null;
      rethrow;
    }
    return modelOrNull(
      snap,
      fromMap,
      serverTimestampFields: serverTimestampFields,
      now: _now,
    );
  });

  @override
  Future<Bill?> bill(String locationId, String billId) =>
      _sales.getBill(locationId, billId);

  @override
  Future<StockItem?> stockItem(String locationId, String itemKey) => _get(
    FirestorePaths.stockItem(locationId, itemKey),
    StockItem.fromMap,
    serverTimestampFields: StockItem.serverTimestampFields,
  );

  @override
  Future<Product?> product(String productId) => _get(
    FirestorePaths.product(productId),
    Product.fromMap,
    serverTimestampFields: Product.serverTimestampFields,
  );

  @override
  Future<RawMaterial?> rawMaterial(String materialId) =>
      _get(FirestorePaths.rawMaterial(materialId), RawMaterial.fromMap);

  @override
  Future<Expense?> expense(String expenseId) => _get(
    FirestorePaths.expense(expenseId),
    Expense.fromMap,
    serverTimestampFields: Expense.serverTimestampFields,
  );

  @override
  Future<Location?> location(String locationId) =>
      _get(FirestorePaths.location(locationId), Location.fromMap);

  @override
  Future<Device?> device(String locationId, String deviceId) => _get(
    FirestorePaths.device(locationId, deviceId),
    Device.fromMap,
    serverTimestampFields: Device.serverTimestampFields,
  );
}
