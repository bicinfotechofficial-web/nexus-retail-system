import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:nexus_data/nexus_data.dart';
import 'package:nexus_printer/nexus_printer.dart';

import 'phone_store.dart';
import 'providers.dart';
import 'share.dart';

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
    required this.customers,
    required this.phoneStore,
    required this.linkLauncher,
    required this.receiptSharer,
  });

  /// The `nexus_data` Firestore implementations from the composition root,
  /// and the Bluetooth printer.
  factory PosServices.fromBackend(NexusBackend b, PrinterService printer) =>
      PosServices(
        customers: b.customers,
        phoneStore: const SharedPrefsPhoneStore(),
        linkLauncher: const UrlLinkLauncher(),
        receiptSharer: const SharePlusReceiptSharer(),
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
  final CustomerRepository customers;

  /// Settings kept on this phone (review before saving, last seen
  /// suggestion decisions).
  final PhoneStore phoneStore;

  /// Opens the WhatsApp link (D-036a), and shares the receipt image
  /// (D-036b).
  final LinkLauncher linkLauncher;
  final ReceiptSharer receiptSharer;

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
    customerRepositoryProvider.overrideWithValue(customers),
    phoneStoreProvider.overrideWithValue(phoneStore),
    linkLauncherProvider.overrideWithValue(linkLauncher),
    receiptSharerProvider.overrideWithValue(receiptSharer),
  ];
}
