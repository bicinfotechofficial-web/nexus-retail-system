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
import 'preorder_fakes.dart';
import 'seed.dart';

export 'fake_customers.dart';
export 'fake_data.dart';
export 'fake_printer.dart';
export 'fake_share.dart';
export 'fake_stock.dart';
export 'preorder_fakes.dart';
export 'seed.dart';

/// Made-up customers for the demo bills: name, mobile, WhatsApp.
const List<(String, String, String?)> _demoCustomers = [
  ('Test Customer', '9876543210', '9876543210'),
  ('Sample Buyer', '9123456780', null),
  ('Demo Visitor', '9988776655', '9812345678'),
];

/// Made-up staff for the demo roster: ID, name, role.
const List<(String, String, String)> _demoStaff = [
  ('staff-1', 'Staff One', 'Baker'),
  ('staff-2', 'Staff Two', 'Counter'),
  ('staff-3', 'Staff Three', 'Helper'),
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
    ReceiptSharer? receiptSharer,
    ReceiptImageRenderer? renderer,
  }) : phoneStore = phoneStore ?? MemoryPhoneStore(),
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

  /// What the receipt image share uses. The fakes record their calls, unless
  /// `FAKE_DATA` on a real phone passes the real ones.
  final FakeReceiptSharer fakeShares = FakeReceiptSharer();
  final FakeReceiptRenderer fakeRenders = FakeReceiptRenderer();
  final ReceiptSharer? _receiptSharer;
  final ReceiptImageRenderer? _renderer;

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
    receiptSharer: receiptSharer,
  );

  /// The same overrides as the real backend's, plus the fake clock.
  List<Override> get overrides => [
    ...services.overrides,
    clockProvider.overrideWithValue(_now),
    receiptImageRendererProvider.overrideWithValue(renderer),
  ];

  /// Staff, attendance and pre-orders for `FAKE_DATA=true` (D-042, D-043).
  /// The widget tests make their own [PreorderFakes] instead.
  late final PreorderFakes preorders = PreorderFakes(this, now: _now);

  /// [overrides] plus [preorders], for `FAKE_DATA=true`.
  List<Override> get demoOverrides => [...overrides, ...preorders.overrides];

  /// A few bills from today and yesterday, one returned and one cancelled,
  /// so `FAKE_DATA=true` opens on something to look at. Written through the
  /// fake service, so summaries match.
  Future<void> seedDemo() async {
    // The demo history belongs to the Store Manager, even on a first run.
    final before = auth.current;
    auth.current = FakeAuthService.storeManagerSession;
    try {
      await _seedBills();
      _seedPreorders();
    } finally {
      auth.current = before;
    }
  }

  /// A small roster with yesterday marked, and open orders due yesterday,
  /// today, tomorrow and later, so the banner and every group show.
  void _seedPreorders() {
    final today = BusinessDate.of(_now());
    final yesterday = BusinessDate.addDays(today, -1);
    final roster = [
      for (final (id, name, role) in _demoStaff)
        StaffMember(id: id, name: name, role: role, active: true),
    ];
    preorders.staff.all = roster;
    final user = FakeAuthService.storeManagerSession.user;
    for (final (i, s) in roster.indexed) {
      preorders.attendance.put(
        AttendanceRecord(
          staffId: s.id,
          staffName: s.name,
          businessDate: yesterday,
          status: i == 2 ? AttendanceStatus.halfDay : AttendanceStatus.present,
          markedBy: ServedBy(uid: user.uid, name: user.name),
          deviceId: Seed.deviceId,
          locationId: Seed.locationId,
        ),
      );
    }
    preorders.orders
      ..add(dueDate: yesterday, dueTime: '18:00', customer: 'Sample Buyer')
      ..add(dueDate: today, dueTime: '16:30')
      ..add(
        dueDate: BusinessDate.addDays(today, 1),
        customer: 'Demo Visitor',
        description: 'Red velvet, 2 kg, two layers\nWrite "Happy Anniversary"',
        price: 2400,
        advance: 1000,
      )
      ..add(
        dueDate: BusinessDate.addDays(today, 3),
        description: 'Pineapple, 500 g, no message',
        price: 550,
        advance: 0,
      );
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
