import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nexus_core/nexus_core.dart';

import '../api/stock.dart';
import '../convert/firestore_values.dart';
import 'failure_mapping.dart';

/// [StockRepository] over `locations/{loc}/stock`.
final class FirestoreStockRepository implements StockRepository {
  FirestoreStockRepository(this._db, {DateTime Function()? clock})
    : _now = clock ?? DateTime.now;

  final FirebaseFirestore _db;
  final DateTime Function() _now;

  /// Every stock doc, raw materials first, then by name. No index needed.
  @override
  Stream<List<StockItem>> watchStock(String locationId) => _db
      .collection(FirestorePaths.stock(locationId))
      .snapshots()
      .map(
        (s) =>
            modelsOf(
              s,
              StockItem.fromMap,
              serverTimestampFields: StockItem.serverTimestampFields,
              now: _now,
            )..sort((a, b) {
              final k = a.kind.index.compareTo(b.kind.index);
              if (k != 0) return k;
              final n = a.name.toLowerCase().compareTo(b.name.toLowerCase());
              return n != 0 ? n : a.itemKey.compareTo(b.itemKey);
            }),
      )
      .mapFirestoreErrors();

  /// Every movement of [businessDate], newest first by `clientCreatedAt`
  /// (ties by ID). One equality filter, sorted here, so no composite index;
  /// a day has few hundred movements at most. Reading needs `stock.move`,
  /// `stock.adjust` or `report.own` at the location (rule #7).
  @override
  Stream<List<Movement>> watchMovements(
    String locationId,
    String businessDate,
  ) => _db
      .collection(FirestorePaths.movements(locationId))
      .where('businessDate', isEqualTo: businessDate)
      .snapshots()
      .map(
        (s) =>
            modelsOf(
              s,
              Movement.fromMap,
              serverTimestampFields: Movement.serverTimestampFields,
              now: _now,
            )..sort((a, b) {
              final c = b.clientCreatedAt.compareTo(a.clientCreatedAt);
              return c != 0 ? c : b.id.compareTo(a.id);
            }),
      )
      .mapFirestoreErrors();

  /// [watchStock] filtered with `StockItem.isLow` (D-015). Firestore can't
  /// compare two fields of a doc, so this is done in the app.
  @override
  Stream<List<StockItem>> watchLowStock(String locationId) =>
      watchStock(locationId).map(
        (items) => [
          for (final i in items)
            if (i.isLow) i,
        ],
      );
}
