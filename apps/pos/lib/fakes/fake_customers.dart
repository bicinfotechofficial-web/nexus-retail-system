import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';

import 'latest.dart';

/// Customers in memory. Like the real service, a bill's customer is created
/// on its first bill and only counted after that (D-037); the POS never
/// writes customers directly.
final class FakeCustomerRepository implements CustomerRepository {
  final Latest<Map<String, Map<String, Customer>>> _byLocation = Latest(
    const {},
  );

  /// Every customer saved at [locationId].
  List<Customer> all(String locationId) =>
      List.unmodifiable(_byLocation.value[locationId]?.values ?? const []);

  /// What `SalesService.createBill` does in the same batch as the bill.
  void recordBill(
    String locationId,
    BillCustomer customer, {
    required Money total,
    required String billId,
    required DateTime at,
  }) {
    final byLocation = {..._byLocation.value};
    final mine = {...?byLocation[locationId]};
    final before = mine[customer.id];
    mine[customer.id] = Customer(
      id: customer.id,
      name: customer.name,
      phone: customer.phone,
      whatsapp: customer.whatsapp,
      locationId: locationId,
      lastBillAt: at,
      billCount: (before?.billCount ?? 0) + 1,
      totalSpend: (before?.totalSpend ?? Money.zero) + total,
      lastWriteRef: billId,
    );
    byLocation[locationId] = mine;
    _byLocation.value = byLocation;
  }

  static List<Customer> _recentFirst(Iterable<Customer> list) =>
      list.toList()..sort((a, b) {
        final byTime = (b.lastBillAt ?? DateTime(0)).compareTo(
          a.lastBillAt ?? DateTime(0),
        );
        return byTime != 0 ? byTime : a.name.compareTo(b.name);
      });

  @override
  Stream<List<Customer>> watchByPhone(String locationId, String phonePrefix) =>
      _byLocation.stream.map(
        (m) => _recentFirst(
          (m[locationId]?.values ?? const <Customer>[]).where(
            (c) => c.phone.startsWith(phonePrefix),
          ),
        ).take(10).toList(),
      );

  @override
  Stream<List<Customer>> watchAll(String locationId, {int limit = 200}) =>
      _byLocation.stream.map(
        (m) => _recentFirst(
          m[locationId]?.values ?? const <Customer>[],
        ).take(limit).toList(),
      );

  @override
  Stream<List<Customer>> watchAllLocations({int limit = 500}) =>
      _byLocation.stream.map(
        (m) =>
            _recentFirst(m.values.expand((l) => l.values)).take(limit).toList(),
      );
}
