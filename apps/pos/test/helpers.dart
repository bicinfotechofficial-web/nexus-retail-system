import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';
import 'package:nexus_pos/app/app.dart';
import 'package:nexus_pos/app/phone_store.dart';
import 'package:nexus_pos/fakes/fake_backend.dart';

/// 10:30 IST on 2026-09-26, as a UTC instant.
final DateTime testNow = DateTime.utc(2026, 9, 26, 5);

/// A device clock the test moves by hand.
final class TestClock {
  TestClock([DateTime? start]) : now = start ?? testNow;

  DateTime now;

  DateTime call() => now;

  void advance(Duration d) => now = now.add(d);
}

FakeBackend fakeBackend({
  SessionContext? session,
  SyncStatus syncStatus = const Online(),
  TestClock? clock,
  PhoneStore? phoneStore,
}) => FakeBackend(
  session: session,
  syncStatus: syncStatus,
  now: clock?.call ?? () => testNow,
  phoneStore: phoneStore,
);

/// A Store Manager session whose role has only [permissions].
SessionContext sessionWith(
  List<String> permissions, {
  Location location = Seed.location,
}) => SessionContext(
  user: Seed.storeManager,
  role: Role(
    id: 'CUSTOM',
    name: 'Custom',
    permissions: permissions,
    allLocations: false,
  ),
  location: location,
);

/// Pumps the whole app on a portrait phone screen (360 × 780 dp).
Future<FakeBackend> pumpPos(WidgetTester tester, {FakeBackend? backend}) async {
  final b = backend ?? fakeBackend();
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(overrides: b.overrides, child: const PosApp()),
  );
  await tester.pumpAndSettle();
  return b;
}

Future<void> tapKey(WidgetTester tester, String key) async {
  final f = find.byKey(Key(key));
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

/// Taps the widget with [text], scrolling it into view first.
Future<void> tapText(WidgetTester tester, String text) async {
  final f = find.text(text);
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> enterKey(WidgetTester tester, String key, String text) async {
  final f = find.byKey(Key(key));
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.enterText(f, text);
  await tester.pumpAndSettle();
}

/// The text of the [Text] under [key], or of the Text itself.
String textOf(WidgetTester tester, String key) {
  final f = find.byKey(Key(key));
  final own = tester.widget(f);
  if (own is Text) return own.data ?? '';
  return tester
      .widgetList<Text>(find.descendant(of: f, matching: find.byType(Text)))
      .map((t) => t.data ?? '')
      .join(' ');
}

bool isEnabled(WidgetTester tester, String key) {
  final w = tester.widget<ButtonStyleButton>(find.byKey(Key(key)));
  return w.onPressed != null;
}

/// A made-up customer on WhatsApp at the same number.
BillCustomer testCustomer({
  String name = 'Test Customer',
  String phone = '9876543210',
  String? whatsapp = '9876543210',
}) => BillCustomer(name: name, phone: phone, whatsapp: whatsapp);

/// Opens the payment page for one Black Forest 500 g (₹450.00), on a fresh
/// backend unless [backend] is given.
Future<FakeBackend> openPaymentPage(
  WidgetTester tester, {
  FakeBackend? backend,
}) async {
  final b = await pumpPos(tester, backend: backend);
  await tapKey(tester, 'product-bf-500');
  await tapKey(tester, 'charge');
  expect(find.widgetWithText(AppBar, 'Payment'), findsOneWidget);
  return b;
}

/// Fills the Customer section on the payment page: a valid name and mobile,
/// WhatsApp the same as the mobile.
Future<void> fillCustomer(
  WidgetTester tester, {
  String name = 'Test Customer',
  String phone = '9876543210',
}) async {
  await enterKey(tester, 'customer-name', name);
  await enterKey(tester, 'customer-phone', phone);
}

/// Fills the customer, then Review and Confirm: the whole way from the
/// payment page to the saved bill.
Future<void> saveWithReview(WidgetTester tester, {bool fill = true}) async {
  if (fill) await fillCustomer(tester);
  await tapKey(tester, 'save');
  await tapKey(tester, 'confirm');
}

/// Saves a bill of [items] (productId → qty from the seed catalog) through
/// the fake service, paid in full with [mode], at [at] (default: now).
Future<Bill> addBill(
  FakeBackend b,
  Map<String, int> items, {
  DateTime? at,
  PaymentMode mode = PaymentMode.cash,
  DiscountInput? discount,
  BillCustomer? customer,
}) {
  final cart = [
    for (final e in items.entries)
      () {
        final p = Seed.products.firstWhere((p) => p.id == e.key);
        return CartLine(
          productId: p.id,
          name: p.name,
          qty: e.value,
          unitPrice: p.price!,
        );
      }(),
  ];
  final total = BillCalculator.compute(
    cart,
    discount: discount,
    maxDiscountPct: Seed.location.maxDiscountPct,
  ).total;
  return b.sales.createBillAt(
    NewBill(
      cart: cart,
      discount: discount,
      payments: [Payment(mode: mode, amount: total)],
      customer: customer ?? testCustomer(),
    ),
    at ?? testNow,
  );
}

/// Opens a drawer destination by its label.
Future<void> openNav(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('Open navigation menu'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('nav-$label')));
  await tester.pumpAndSettle();
}

/// Pumps the app, opens Bills and then the bill [billId].
Future<void> openBill(WidgetTester tester, FakeBackend b, String billId) async {
  await pumpPos(tester, backend: b);
  await openNav(tester, 'Bills');
  await tapKey(tester, 'bill-$billId');
}

/// Chooses [label] in the dropdown under [key], scrolling its menu.
Future<void> pick(WidgetTester tester, String key, String label) async {
  await tapKey(tester, key);
  final menu = find.byType(Scrollable).last;
  final item = find.descendant(of: menu, matching: find.text(label));
  await tester.dragUntilVisible(item, menu, const Offset(0, -100));
  await tester.pumpAndSettle();
  await tester.tap(item.last);
  await tester.pumpAndSettle();
}
