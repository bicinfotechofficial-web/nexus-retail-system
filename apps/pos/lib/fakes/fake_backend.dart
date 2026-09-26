import 'package:flutter_riverpod/misc.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';

import '../app/providers.dart';
import 'fake_data.dart';
import 'fake_printer.dart';
import 'fake_stock.dart';
import 'seed.dart';

export 'fake_data.dart';
export 'fake_printer.dart';
export 'fake_stock.dart';
export 'seed.dart';

/// Every fake, wired together, plus the provider overrides that install
/// them. Used by `FAKE_DATA=true` and by the widget tests.
final class FakeBackend {
  FakeBackend({
    SessionContext? session,
    bool signedIn = true,
    SyncStatus syncStatus = const Online(),
    DateTime Function()? now,
    bool registered = true,
  }) : auth = FakeAuthService(
         session ?? (signedIn ? FakeAuthService.storeManagerSession : null),
       ),
       device = FakeDeviceService(registered ? Seed.deviceId : null),
       _now = now ?? DateTime.now {
    sync = FakeSyncService(syncStatus, _now)..lastSyncAt = _now();
    offline = FakeOfflineGuard(
      now: _now,
      lastSyncAt: () => sync.lastSyncAt,
      location: () => auth.current?.location,
    );
    sync.onSynced = offline.synced;
    device.onRegistered = sync.markSynced;
    auth.onSignedIn = sync.markSynced;
    sales = FakeSalesService(
      auth: auth,
      bills: bills,
      summaries: summaries,
      now: _now,
    );
    catalogService = FakeCatalogService(auth: auth, catalog: catalog);
    stock = FakeStock(auth: auth, catalog: catalog, now: _now)
      ..seed(Seed.locationId, Seed.stock);
  }

  final DateTime Function() _now;
  final FakeAuthService auth;
  final FakeCatalogRepository catalog = FakeCatalogRepository();
  final FakeSalesRepository bills = FakeSalesRepository();
  final FakeSummaryRepository summaries = FakeSummaryRepository();
  late final FakeSalesService sales;
  late final FakeStock stock;
  late final FakeCatalogService catalogService;
  late final FakeSyncService sync;
  late final FakeOfflineGuard offline;
  final FakeDeviceService device;
  final FakePrinterService printer = FakePrinterService();

  List<Override> get overrides => [
    authServiceProvider.overrideWithValue(auth),
    catalogRepositoryProvider.overrideWithValue(catalog),
    salesServiceProvider.overrideWithValue(sales),
    salesRepositoryProvider.overrideWithValue(bills),
    summaryRepositoryProvider.overrideWithValue(summaries),
    syncServiceProvider.overrideWithValue(sync),
    offlineGuardProvider.overrideWithValue(offline),
    deviceServiceProvider.overrideWithValue(device),
    printerServiceProvider.overrideWithValue(printer),
    catalogServiceProvider.overrideWithValue(catalogService),
    stockRepositoryProvider.overrideWithValue(stock),
    stockServiceProvider.overrideWithValue(stock),
    clockProvider.overrideWithValue(_now),
  ];

  /// A few bills from today and yesterday, one returned and one cancelled,
  /// so `FAKE_DATA=true` opens on something to look at. Written through the
  /// fake service, so summaries match.
  Future<void> seedDemo() async {
    // The demo history belongs to the Store Manager, even on a first run.
    final before = auth.current;
    auth.current = FakeAuthService.storeManagerSession;
    try {
      await _seedBills();
    } finally {
      auth.current = before;
    }
  }

  Future<void> _seedBills() async {
    final now = _now();
    final today = BusinessDate.of(now);
    final yesterday = BusinessDate.addDays(today, -1);
    DateTime at(String date, int hour, int minute) =>
        BusinessDate.startOf(date).add(Duration(hours: hour, minutes: minute));
    CartLine line(String id, int qty) {
      final p = Seed.products.firstWhere((p) => p.id == id);
      return CartLine(
        productId: p.id,
        name: p.name,
        qty: qty,
        unitPrice: p.price!,
      );
    }

    Future<Bill> bill(DateTime when, List<CartLine> cart, PaymentMode mode) {
      final total = BillCalculator.compute(cart).total;
      return sales.createBillAt(
        NewBill(
          cart: cart,
          payments: [Payment(mode: mode, amount: total)],
        ),
        when,
      );
    }

    final returned = await bill(at(yesterday, 11, 5), [
      line('bf-500', 1),
      line('veg-puff', 4),
    ], PaymentMode.cash);
    await bill(at(yesterday, 17, 40), [line('ct-1k', 1)], PaymentMode.upi);
    // Earlier today, but never before midnight IST.
    DateTime ago(Duration d) {
      final t = now.subtract(d);
      return t.isBefore(BusinessDate.startOf(today)) ? now : t;
    }

    final toCancel = await bill(ago(const Duration(hours: 2)), [
      line('rv-pastry', 2),
    ], PaymentMode.cash);
    await bill(ago(const Duration(hours: 1)), [
      line('bs-500', 1),
      line('cookies', 1),
    ], PaymentMode.card);
    await bill(ago(const Duration(minutes: 20)), [
      line('brownie', 2),
      line('cc-muffin', 3),
    ], PaymentMode.upi);
    final ret = ReturnCalculator.compute(returned, {'veg-puff': 1});
    await sales.createReturn(
      billId: returned.id,
      qtyByProduct: {'veg-puff': 1},
      refunds: [Payment(mode: PaymentMode.cash, amount: ret.refundTotal)],
      reason: 'Stale item',
    );
    await sales.cancelBill(
      billId: toCancel.id,
      reason: 'Customer changed mind',
    );
    sales.cancelCalls.clear();
    sales.returnCalls.clear();
  }
}
