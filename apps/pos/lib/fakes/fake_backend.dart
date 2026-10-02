import 'package:flutter_riverpod/misc.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';
import 'package:nexus_printer/nexus_printer.dart';

import '../app/phone_store.dart';
import '../app/providers.dart';
import '../app/services.dart';
import '../app/share.dart';
import 'fake_customers.dart';
import 'fake_data.dart';
import 'fake_printer.dart';
import 'fake_share.dart';
import 'fake_stock.dart';
import 'seed.dart';

export 'fake_customers.dart';
export 'fake_data.dart';
export 'fake_printer.dart';
export 'fake_share.dart';
export 'fake_stock.dart';
export 'seed.dart';

/// Made-up customers for the demo bills: name, mobile, WhatsApp.
const List<(String, String, String?)> _demoCustomers = [
  ('Test Customer', '9876543210', '9876543210'),
  ('Sample Buyer', '9123456780', null),
  ('Demo Visitor', '9988776655', '9812345678'),
];

/// Every fake, wired together, plus the provider overrides that install
/// them. Used by `FAKE_DATA=true` and by the widget tests.
final class FakeBackend {
  FakeBackend({
    SessionContext? session,
    bool signedIn = true,
    SyncStatus syncStatus = const Online(),
    DateTime Function()? now,
    bool registered = true,
    PhoneStore? phoneStore,
    LinkLauncher? linkLauncher,
    ReceiptSharer? receiptSharer,
    ReceiptImageRenderer? renderer,
  }) : phoneStore = phoneStore ?? MemoryPhoneStore(),
       _linkLauncher = linkLauncher,
       _receiptSharer = receiptSharer,
       _renderer = renderer,
       auth = FakeAuthService(
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
      customers: customers,
      now: _now,
    );
    catalogService = FakeCatalogService(
      auth: auth,
      catalog: catalog,
      now: _now,
    );
    stock = FakeStock(auth: auth, catalog: catalog, now: _now)
      ..seed(Seed.locationId, Seed.stock);
  }

  final DateTime Function() _now;
  final FakeAuthService auth;
  final FakeCatalogRepository catalog = FakeCatalogRepository();
  final FakeSalesRepository bills = FakeSalesRepository();
  final FakeSummaryRepository summaries = FakeSummaryRepository();
  final FakeCustomerRepository customers = FakeCustomerRepository();
  late final FakeSalesService sales;
  late final FakeStock stock;
  late final FakeCatalogService catalogService;
  late final FakeSyncService sync;
  late final FakeOfflineGuard offline;
  final FakeDeviceService device;
  final FakePrinterService printer = FakePrinterService();

  /// Settings on the phone. Pass the same store to a second backend to
  /// restart the app on the same phone.
  final PhoneStore phoneStore;

  /// What the WhatsApp buttons use. The fakes record their calls, unless
  /// `FAKE_DATA` on a real phone passes the real ones.
  final FakeLinkLauncher fakeLinks = FakeLinkLauncher();
  final FakeReceiptSharer fakeShares = FakeReceiptSharer();
  final FakeReceiptRenderer fakeRenders = FakeReceiptRenderer();
  final LinkLauncher? _linkLauncher;
  final ReceiptSharer? _receiptSharer;
  final ReceiptImageRenderer? _renderer;

  LinkLauncher get linkLauncher => _linkLauncher ?? fakeLinks;
  ReceiptSharer get receiptSharer => _receiptSharer ?? fakeShares;
  ReceiptImageRenderer get renderer => _renderer ?? fakeRenders.call;

  /// The fakes under the same interfaces the real backend fills.
  PosServices get services => PosServices(
    auth: auth,
    devices: device,
    catalogRepo: catalog,
    catalog: catalogService,
    salesRepo: bills,
    sales: sales,
    summaries: summaries,
    stockRepo: stock,
    stock: stock,
    sync: sync,
    offlineGuard: offline,
    printer: printer,
    customers: customers,
    phoneStore: phoneStore,
    linkLauncher: linkLauncher,
    receiptSharer: receiptSharer,
  );

  /// The same overrides as the real backend's, plus the fake clock.
  List<Override> get overrides => [
    ...services.overrides,
    clockProvider.overrideWithValue(_now),
    receiptImageRendererProvider.overrideWithValue(renderer),
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

    var n = 0;
    BillCustomer nextCustomer() {
      final c = _demoCustomers[n++ % _demoCustomers.length];
      return BillCustomer(name: c.$1, phone: c.$2, whatsapp: c.$3);
    }

    Future<Bill> bill(DateTime when, List<CartLine> cart, PaymentMode mode) {
      final total = BillCalculator.compute(cart).total;
      return sales.createBillAt(
        NewBill(
          cart: cart,
          payments: [Payment(mode: mode, amount: total)],
          customer: nextCustomer(),
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
