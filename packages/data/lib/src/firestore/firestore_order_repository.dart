import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nexus_core/nexus_core.dart';

import '../api/orders.dart';
import '../convert/firestore_values.dart';
import '../convert/order_ordering.dart';
import '../plans/order_plans.dart';
import 'failure_mapping.dart';

/// [OrderRepository] over `locations/{loc}/orders` (D-043). Served from the
/// Firestore cache while offline, which holds the orders this device has
/// listened to or written, so an order taken offline is on the list at once.
///
/// - `watchOpen`: `status == OPEN` ordered by `dueDate` (index `orders:
///   status, dueDate`), then by `dueTime` here, orders with no time last.
/// - `watchClosed`: delivered and cancelled orders, newest first by the
///   day they were taken (`clientCreatedAt`; index `orders: status,
///   clientCreatedAt DESC`).
/// - `watchAllLocations`: a collection-group query on `orders`, ordered by
///   `dueDate` (the collection-group index, rule #18 with `report.all`).
final class FirestoreOrderRepository implements OrderRepository {
  FirestoreOrderRepository(this._db, {DateTime Function()? clock})
    : _now = clock ?? DateTime.now;

  final FirebaseFirestore _db;
  final DateTime Function() _now;

  @override
  Stream<List<PreOrder>> watchOpen(String locationId) => _db
      .collection(FirestorePaths.orders(locationId))
      .where('status', isEqualTo: OrderStatus.open.wire)
      .orderBy('dueDate')
      .snapshots()
      .map((s) => soonestDueFirst(_orders(s)))
      .mapFirestoreErrors();

  @override
  Stream<List<PreOrder>> watchClosed(String locationId, {int limit = 50}) => _db
      .collection(FirestorePaths.orders(locationId))
      .where(
        'status',
        whereIn: [OrderStatus.delivered.wire, OrderStatus.cancelled.wire],
      )
      .orderBy('clientCreatedAt', descending: true)
      .limit(limit)
      .snapshots()
      .map((s) => newestFirst(_orders(s)))
      .mapFirestoreErrors();

  @override
  Future<PreOrder?> getOrder(String locationId, String orderId) =>
      guardFirestore(() async {
        final snap = await _db
            .doc(FirestorePaths.order(locationId, orderId))
            .get(estimateServerTimestamps);
        final order = modelOrNull(
          snap,
          PreOrder.fromMap,
          serverTimestampFields: PreOrder.serverTimestampFields,
          now: _now,
        );
        return order == null
            ? null
            : OrderPlans.copyOrder(order, locationId: locationId);
      });

  @override
  Stream<List<PreOrder>> watchAllLocations({
    OrderStatus? status,
    String? dueFrom,
    String? dueTo,
    int limit = 300,
  }) {
    Query<Map<String, dynamic>> q = _db.collectionGroup('orders');
    if (status != null) q = q.where('status', isEqualTo: status.wire);
    if (dueFrom != null) {
      q = q.where('dueDate', isGreaterThanOrEqualTo: dueFrom);
    }
    if (dueTo != null) q = q.where('dueDate', isLessThanOrEqualTo: dueTo);
    return q
        .orderBy('dueDate')
        .limit(limit)
        .snapshots()
        .map((s) => soonestDueFirst(_orders(s)))
        .mapFirestoreErrors();
  }

  /// Each order also gets its `locationId`, read from the document path
  /// (`locations/{loc}/orders/{id}`), which is what tells the Admin's
  /// all-stores list which store an order belongs to.
  List<PreOrder> _orders(QuerySnapshot<Map<String, dynamic>> s) => [
    for (final d in s.docs)
      OrderPlans.copyOrder(
        PreOrder.fromMap(
          d.id,
          plainFromFirestore(
            d.data(),
            serverTimestampFields: PreOrder.serverTimestampFields,
            hasPendingWrites: d.metadata.hasPendingWrites,
            now: _now,
          ),
        ),
        locationId: d.reference.parent.parent?.id,
      ),
  ];
}
