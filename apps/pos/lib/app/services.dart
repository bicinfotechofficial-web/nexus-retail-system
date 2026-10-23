import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:nexus_data/nexus_data.dart';
import 'package:nexus_printer/nexus_printer.dart';

import 'order_slip.dart';
import 'phone_store.dart';
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
    required this.customers,
    required this.phoneStore,
    required this.receiptSharer,
    this.staffRepo,
    this.attendanceRepo,
    this.attendance,
    this.orderRepo,
    this.orders,
    this.orderSlips,
  });

  /// The `nexus_data` Firestore implementations from the composition root,
  /// and the Bluetooth printer.
  factory PosServices.fromBackend(NexusBackend b, PrinterService printer) =>
      PosServices(
        customers: b.customers,
        phoneStore: const SharedPrefsPhoneStore(),
        receiptSharer: const SharePlusReceiptSharer(),
        staffRepo: b.staffRepo,
        attendanceRepo: b.attendanceRepo,
        attendance: b.attendance,
        orderRepo: b.orderRepo,
        orders: b.orders,
        orderSlips: PrinterOrderSlipActions(
          printer,
          const SharePlusReceiptSharer(),
        ),
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

  /// Shares the receipt image through the share sheet (D-036b, D-041).
  final ReceiptSharer receiptSharer;

  /// Staff, attendance and pre-orders (D-042, D-043). The real backend
  /// always fills these; the `FAKE_DATA` backend leaves them out, and the
  /// widget tests install their own fakes.
  final StaffRepository? staffRepo;
  final AttendanceRepository? attendanceRepo;
  final AttendanceService? attendance;
  final OrderRepository? orderRepo;
  final OrderService? orders;
  final OrderSlipActions? orderSlips;

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
    receiptSharerProvider.overrideWithValue(receiptSharer),
    if (staffRepo case final v?) staffRepositoryProvider.overrideWithValue(v),
    if (attendanceRepo case final v?)
      attendanceRepositoryProvider.overrideWithValue(v),
    if (attendance case final v?)
      attendanceServiceProvider.overrideWithValue(v),
    if (orderRepo case final v?) orderRepositoryProvider.overrideWithValue(v),
    if (orders case final v?) orderServiceProvider.overrideWithValue(v),
    if (orderSlips case final v?) orderSlipActionsProvider.overrideWithValue(v),
  ];
}
