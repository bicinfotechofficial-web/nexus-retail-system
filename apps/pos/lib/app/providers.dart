import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';
import 'package:nexus_printer/nexus_printer.dart';

/// The data and printer interfaces the app builds against (D-026). Each is
/// overridden at startup: with fakes under `FAKE_DATA=true`, and with the
/// `nexus_data` and `nexus_printer` implementations once they are merged.
Never _notConfigured(String what) => throw UnimplementedError(
  '$what has no implementation yet. Run with --dart-define=FAKE_DATA=true.',
);

final authServiceProvider = Provider<AuthService>(
  (ref) => _notConfigured('AuthService'),
);
final catalogRepositoryProvider = Provider<CatalogRepository>(
  (ref) => _notConfigured('CatalogRepository'),
);
final salesServiceProvider = Provider<SalesService>(
  (ref) => _notConfigured('SalesService'),
);
final salesRepositoryProvider = Provider<SalesRepository>(
  (ref) => _notConfigured('SalesRepository'),
);
final summaryRepositoryProvider = Provider<SummaryRepository>(
  (ref) => _notConfigured('SummaryRepository'),
);
final syncServiceProvider = Provider<SyncService>(
  (ref) => _notConfigured('SyncService'),
);
final offlineGuardProvider = Provider<OfflineGuard>(
  (ref) => _notConfigured('OfflineGuard'),
);
final deviceServiceProvider = Provider<DeviceService>(
  (ref) => _notConfigured('DeviceService'),
);
final printerServiceProvider = Provider<PrinterService>(
  (ref) => _notConfigured('PrinterService'),
);
final catalogServiceProvider = Provider<CatalogService>(
  (ref) => _notConfigured('CatalogService'),
);
final stockRepositoryProvider = Provider<StockRepository>(
  (ref) => _notConfigured('StockRepository'),
);
final stockServiceProvider = Provider<StockService>(
  (ref) => _notConfigured('StockService'),
);

/// The device clock. Tests override it.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// The signed-in user, role and location. Null when signed out.
final sessionProvider = StreamProvider<SessionContext?>(
  (ref) => ref.watch(authServiceProvider).session,
);

final syncStatusProvider = StreamProvider<SyncStatus>(
  (ref) => ref.watch(syncServiceProvider).status,
);

/// Products sellable at the session's location, in `sortOrder`.
final sellableProductsProvider = StreamProvider<List<Product>>((ref) {
  final locationId = ref.watch(
    sessionProvider.select((s) => s.value?.location?.code),
  );
  if (locationId == null) return Stream.value(const []);
  return ref.watch(catalogRepositoryProvider).watchSellable(locationId);
});

/// The session's location code, or null (signed out, or an all-locations
/// role with no own store).
final locationCodeProvider = Provider<String?>(
  (ref) => ref.watch(sessionProvider.select((s) => s.value?.location?.code)),
);

/// Bills of one business day at the session's location, newest first.
final billsForDayProvider = StreamProvider.autoDispose
    .family<List<Bill>, String>((ref, businessDate) {
      final loc = ref.watch(locationCodeProvider);
      if (loc == null) return Stream.value(const []);
      return ref.watch(salesRepositoryProvider).watchBills(loc, businessDate);
    });

/// One bill at the session's location. Invalidate it after a cancel or a
/// return to reload.
final billProvider = FutureProvider.autoDispose.family<Bill?, String>((
  ref,
  billId,
) {
  final loc = ref.watch(locationCodeProvider);
  if (loc == null) return Future.value();
  return ref.watch(salesRepositoryProvider).getBill(loc, billId);
});

/// The returns already made against a bill, newest first.
final returnsForBillProvider = FutureProvider.autoDispose
    .family<List<SaleReturn>, String>((ref, billId) {
      final loc = ref.watch(locationCodeProvider);
      if (loc == null) return Future.value(const []);
      return ref.watch(salesRepositoryProvider).returnsForBill(loc, billId);
    });

/// The daily summary of one business day at the session's location.
final dailySummaryProvider = StreamProvider.autoDispose.family<Summary, String>(
  (ref, businessDate) {
    final loc = ref.watch(locationCodeProvider);
    if (loc == null) return Stream.value(const Summary());
    return ref.watch(summaryRepositoryProvider).watchDaily(loc, businessDate);
  },
);

/// Every stock doc at the session's location. Quantities may be negative.
final stockProvider = StreamProvider<List<StockItem>>((ref) {
  final loc = ref.watch(locationCodeProvider);
  if (loc == null) return Stream.value(const []);
  return ref.watch(stockRepositoryProvider).watchStock(loc);
});

/// Items at or below their threshold at the session's location (D-015).
final lowStockProvider = StreamProvider<List<StockItem>>((ref) {
  final loc = ref.watch(locationCodeProvider);
  if (loc == null) return Stream.value(const []);
  return ref.watch(stockRepositoryProvider).watchLowStock(loc);
});

final rawMaterialsProvider = StreamProvider<List<RawMaterial>>(
  (ref) => ref.watch(catalogRepositoryProvider).watchRawMaterials(),
);

final offlineStateProvider = StreamProvider<OfflineState>(
  (ref) => ref.watch(offlineGuardProvider).state,
);

final syncErrorsProvider = StreamProvider<List<SyncError>>(
  (ref) => ref.watch(syncServiceProvider).errors,
);

/// The offline state, with a [NearLimit] countdown pinned to a deadline on
/// the device clock when it arrives, so the banner keeps counting down
/// between emissions and every screen shows the same time.
final class OfflineView {
  const OfflineView(this.state, this.deadline);

  final OfflineState state;

  /// When billing stops, for [NearLimit]; null otherwise.
  final DateTime? deadline;

  bool get blocked => state is BillingBlocked;
}

final offlineViewProvider = Provider<OfflineView>((ref) {
  final state = ref.watch(offlineStateProvider).value ?? const WithinLimit();
  final deadline = state is NearLimit
      ? ref.read(clockProvider)().add(state.billingStopsIn)
      : null;
  return OfflineView(state, deadline);
});

/// PENDING suggestions from the session's location, awaiting approval.
final pendingSuggestionsProvider = StreamProvider<List<Product>>((ref) {
  final loc = ref.watch(locationCodeProvider);
  if (loc == null) return Stream.value(const []);
  return ref
      .watch(catalogRepositoryProvider)
      .watchPending()
      .map((all) => all.where((p) => p.scope == loc).toList());
});
