import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';

import 'live.dart';

/// A pre-order as the tests write it.
PreOrder order(
  String locationId,
  String id, {
  required String dueDate,
  String? dueTime,
  String customer = 'Test Customer',
  String phone = '9876543210',
  String description = 'Chocolate cake, 1 kg',
  int price = 1500,
  int advance = 500,
  OrderStatus status = OrderStatus.open,
  OrderCancel? cancel,
}) => PreOrder(
  id: id,
  orderNo: '$locationId-$id',
  deviceId: id.split('-').first,
  seq: 1,
  customer: BillCustomer(name: customer, phone: phone),
  dueDate: dueDate,
  dueTime: dueTime,
  description: description,
  price: Money.rupees(price),
  advance: Money.rupees(advance),
  advanceMode: advance == 0 ? null : PaymentMode.cash,
  status: status,
  cancel: cancel,
  servedBy: const ServedBy(uid: 'sm-1', name: 'Store Manager'),
  businessDate: '2026-09-20',
  clientCreatedAt: DateTime.utc(2026, 9, 20, 5),
  createdBy: 'sm-1',
  locationId: locationId,
);

OrderCancel cancelled({required String reason, required int refunded}) =>
    OrderCancel(
      reason: reason,
      by: 'sm-1',
      at: DateTime.utc(2026, 9, 22, 5),
      businessDate: '2026-09-22',
      refunded: Money.rupees(refunded),
    );

/// An in-memory `OrderRepository`. `watchAllLocations` applies the filters
/// like the real query and returns the orders soonest due first. The
/// [queries] list records each call's filters.
final class FakeOrderRepository implements OrderRepository {
  FakeOrderRepository(List<PreOrder> seed) : _orders = Live(List.of(seed));

  final Live<List<PreOrder>> _orders;
  final List<String> queries = [];

  @override
  Stream<List<PreOrder>> watchAllLocations({
    String? locationId,
    OrderStatus? status,
    String? dueFrom,
    String? dueTo,
    int limit = 300,
  }) {
    queries.add(
      '${status?.wire} $dueFrom $dueTo'
      '${locationId == null ? '' : ' @$locationId'}',
    );
    return _orders.watch(
      (l) =>
          [
            for (final o in l)
              if ((locationId == null || o.locationId == locationId) &&
                  (status == null || o.status == status) &&
                  (dueFrom == null || o.dueDate.compareTo(dueFrom) >= 0) &&
                  (dueTo == null || o.dueDate.compareTo(dueTo) <= 0))
                o,
          ]..sort((a, b) {
            final d = a.dueDate.compareTo(b.dueDate);
            return d != 0
                ? d
                : (a.dueTime ?? '99:99').compareTo(b.dueTime ?? '99:99');
          }),
    );
  }

  @override
  Stream<List<PreOrder>> watchOpen(String locationId) => _orders.watch(
    (l) => [
      for (final o in l)
        if (o.locationId == locationId && o.isOpen) o,
    ],
  );

  @override
  Stream<List<PreOrder>> watchClosed(String locationId, {int limit = 50}) =>
      _orders.watch(
        (l) => [
          for (final o in l)
            if (o.locationId == locationId && !o.isOpen) o,
        ],
      );

  @override
  Future<PreOrder?> getOrder(String locationId, String orderId) async {
    for (final o in _orders.value) {
      if (o.locationId == locationId && o.id == orderId) return o;
    }
    return null;
  }
}
