import 'package:nexus_core/nexus_core.dart';

/// Customers are created by `SalesService.createBill` (D-037), never
/// directly, so this has reads only.
abstract interface class CustomerRepository {
  /// Customers at [locationId] whose mobile number starts with [phonePrefix]
  /// (at least 3 digits), for the billing form's suggestions. Served from the
  /// local cache when offline. At most 10.
  Stream<List<Customer>> watchByPhone(String locationId, String phonePrefix);

  /// Every customer at [locationId], most recent first. At most [limit].
  Stream<List<Customer>> watchAll(String locationId, {int limit = 200});

  /// Every location's customers, for the Admin (`report.all`).
  Stream<List<Customer>> watchAllLocations({int limit = 500});
}
