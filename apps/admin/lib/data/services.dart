import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:nexus_data/nexus_data.dart';

import 'providers.dart';

/// Every `nexus_data` interface the console reads through a provider
/// (D-026), in one place, so the real backend and the fakes install the
/// same set of overrides.
final class AdminServices {
  const AdminServices({
    required this.auth,
    required this.locationRepo,
    required this.locations,
    required this.summaries,
    required this.stockRepo,
    required this.catalogRepo,
    required this.salesRepo,
    required this.customerRepo,
    required this.catalog,
    required this.userRepo,
    required this.users,
    required this.devices,
    required this.expenseRepo,
    required this.expenses,
    required this.audit,
  });

  /// The Firestore implementations from the composition root.
  factory AdminServices.fromBackend(NexusBackend b) => AdminServices(
    auth: b.authService,
    locationRepo: b.locationRepo,
    locations: b.locations,
    summaries: b.summaries,
    stockRepo: b.stockRepo,
    catalogRepo: b.catalogRepo,
    salesRepo: b.salesRepo,
    customerRepo: b.customers,
    catalog: b.catalog,
    userRepo: b.userRepo,
    users: b.users,
    devices: b.deviceService,
    expenseRepo: b.expenseRepo,
    expenses: b.expenses,
    audit: b.audit,
  );

  final AuthService auth;
  final LocationRepository locationRepo;
  final LocationService locations;
  final SummaryRepository summaries;
  final StockRepository stockRepo;
  final CatalogRepository catalogRepo;
  final SalesRepository salesRepo;
  final CustomerRepository customerRepo;
  final CatalogService catalog;
  final UserRepository userRepo;
  final UserService users;
  final DeviceService devices;
  final ExpenseRepository expenseRepo;
  final ExpenseService expenses;
  final AuditRepository audit;

  /// One override for every provider in `providers.dart` that has no
  /// implementation of its own.
  List<Override> get overrides => [
    authServiceProvider.overrideWithValue(auth),
    locationRepositoryProvider.overrideWithValue(locationRepo),
    locationServiceProvider.overrideWithValue(locations),
    summaryRepositoryProvider.overrideWithValue(summaries),
    stockRepositoryProvider.overrideWithValue(stockRepo),
    catalogRepositoryProvider.overrideWithValue(catalogRepo),
    salesRepositoryProvider.overrideWithValue(salesRepo),
    customerRepositoryProvider.overrideWithValue(customerRepo),
    catalogServiceProvider.overrideWithValue(catalog),
    userRepositoryProvider.overrideWithValue(userRepo),
    userServiceProvider.overrideWithValue(users),
    deviceServiceProvider.overrideWithValue(devices),
    expenseRepositoryProvider.overrideWithValue(expenseRepo),
    expenseServiceProvider.overrideWithValue(expenses),
    auditRepositoryProvider.overrideWithValue(audit),
  ];
}
