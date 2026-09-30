import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:nexus_data/nexus_data.dart';
import 'package:nexus_printer/nexus_printer.dart';

import 'providers.dart';

/// Every data and printer interface the POS reads through a provider
/// (D-026), in one place, so the real backend and the fakes install the
/// same set of overrides.
final class PosServices {
  const PosServices({
    required this.auth,
    required this.devices,
    required this.catalogRepo,
    required this.catalog,
    required this.salesRepo,
    required this.sales,
    required this.summaries,
    required this.stockRepo,
    required this.stock,
    required this.sync,
    required this.offlineGuard,
    required this.printer,
  });

  /// The `nexus_data` Firestore implementations from the composition root,
  /// and the Bluetooth printer.
  factory PosServices.fromBackend(NexusBackend b, PrinterService printer) =>
      PosServices(
        auth: b.authService,
        devices: b.deviceService,
        catalogRepo: b.catalogRepo,
        catalog: b.catalog,
        salesRepo: b.salesRepo,
        sales: b.sales,
        summaries: b.summaries,
        stockRepo: b.stockRepo,
        stock: b.stock,
        sync: b.syncService,
        offlineGuard: b.guard,
        printer: printer,
      );

  final AuthService auth;
  final DeviceService devices;
  final CatalogRepository catalogRepo;
  final CatalogService catalog;
  final SalesRepository salesRepo;
  final SalesService sales;
  final SummaryRepository summaries;
  final StockRepository stockRepo;
  final StockService stock;
  final SyncService sync;
  final OfflineGuard offlineGuard;
  final PrinterService printer;

  /// One override for every provider in `providers.dart` that has no
  /// implementation of its own.
  List<Override> get overrides => [
    authServiceProvider.overrideWithValue(auth),
    deviceServiceProvider.overrideWithValue(devices),
    catalogRepositoryProvider.overrideWithValue(catalogRepo),
    catalogServiceProvider.overrideWithValue(catalog),
    salesRepositoryProvider.overrideWithValue(salesRepo),
    salesServiceProvider.overrideWithValue(sales),
    summaryRepositoryProvider.overrideWithValue(summaries),
    stockRepositoryProvider.overrideWithValue(stockRepo),
    stockServiceProvider.overrideWithValue(stock),
    syncServiceProvider.overrideWithValue(sync),
    offlineGuardProvider.overrideWithValue(offlineGuard),
    printerServiceProvider.overrideWithValue(printer),
  ];
}
