import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_pos/fakes/fake_backend.dart';

import 'helpers.dart';

/// POS-15: typing a mobile offers the saved customers for it (D-037).
Future<void> seedCustomer(
  FakeBackend b,
  String name,
  String phone,
  String? whatsapp,
) => addBill(b, {
  'veg-puff': 1,
}, customer: BillCustomer(name: name, phone: phone, whatsapp: whatsapp));

String fieldText(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(Key(key))).controller!.text;

String idOf(String name, String phone) => CustomerId.of(phone, name);

void main() {
  testWidgets('suggestions start at 3 digits and narrow as you type', (
    tester,
  ) async {
    final b = fakeBackend();
    await seedCustomer(b, 'Test Customer', '9876543210', '9876543210');
    await seedCustomer(b, 'Sample Buyer', '9876501234', null);
    await seedCustomer(b, 'Demo Visitor', '9123456780', '9123456780');
    await openPaymentPage(tester, backend: b);

    await enterKey(tester, 'customer-phone', '98');
    expect(find.byKey(const Key('customer-suggestions')), findsNothing);

    await enterKey(tester, 'customer-phone', '987');
    expect(find.byKey(const Key('customer-suggestions')), findsOneWidget);
    expect(
      find.byKey(
        Key('customer-suggestion-${idOf('Test Customer', '9876543210')}'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        Key('customer-suggestion-${idOf('Sample Buyer', '9876501234')}'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        Key('customer-suggestion-${idOf('Demo Visitor', '9123456780')}'),
      ),
      findsNothing,
    );

    await enterKey(tester, 'customer-phone', '98765432');
    expect(find.text('Test Customer'), findsOneWidget);
    expect(find.text('Sample Buyer'), findsNothing);
  });

  testWidgets('shows at most 10 suggestions', (tester) async {
    final b = fakeBackend();
    for (var i = 0; i < 12; i++) {
      await seedCustomer(b, 'Test Customer $i', '98765432${10 + i}', null);
    }
    await openPaymentPage(tester, backend: b);
    await enterKey(tester, 'customer-phone', '9876');
    expect(
      find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith(
              'customer-suggestion-',
            ),
      ),
      findsNWidgets(10),
    );
  });

  testWidgets('only this location\'s customers are offered', (tester) async {
    final b = fakeBackend();
    await seedCustomer(b, 'Test Customer', '9876543210', null);
    b.customers.recordBill(
      'MNJ',
      BillCustomer(name: 'Other Store Buyer', phone: '9876599999'),
      total: const Money(10000),
      billId: 'D09-000001',
      at: testNow,
    );
    await openPaymentPage(tester, backend: b);
    await enterKey(tester, 'customer-phone', '987');
    expect(find.text('Test Customer'), findsOneWidget);
    expect(find.text('Other Store Buyer'), findsNothing);
  });

  testWidgets('picking one fills name, mobile and Same as mobile', (
    tester,
  ) async {
    final b = fakeBackend();
    await seedCustomer(b, 'Test Customer', '9876543210', '9876543210');
    await openPaymentPage(tester, backend: b);
    await enterKey(tester, 'customer-phone', '987');
    await tapKey(
      tester,
      'customer-suggestion-${idOf('Test Customer', '9876543210')}',
    );
    expect(fieldText(tester, 'customer-name'), 'Test Customer');
    expect(fieldText(tester, 'customer-phone'), '9876543210');
    expect(find.byKey(const Key('customer-whatsapp')), findsNothing);
    // The list closes, and the bill can be reviewed straight away.
    expect(find.byKey(const Key('customer-suggestions')), findsNothing);
    await tapKey(tester, 'save');
    await tapKey(tester, 'confirm');
    final c = b.sales.createCalls.single.customer;
    expect(
      (c.name, c.phone, c.whatsapp),
      ('Test Customer', '9876543210', '9876543210'),
    );
  });

  testWidgets('picking one with no WhatsApp selects No WhatsApp', (
    tester,
  ) async {
    final b = fakeBackend();
    await seedCustomer(b, 'Sample Buyer', '9876501234', null);
    await openPaymentPage(tester, backend: b);
    await enterKey(tester, 'customer-phone', '98765');
    await tapKey(
      tester,
      'customer-suggestion-${idOf('Sample Buyer', '9876501234')}',
    );
    expect(fieldText(tester, 'customer-name'), 'Sample Buyer');
    await tapKey(tester, 'save');
    await tapKey(tester, 'confirm');
    expect(b.sales.createCalls.single.customer.whatsapp, isNull);
  });

  testWidgets('picking one with another WhatsApp selects Different number', (
    tester,
  ) async {
    final b = fakeBackend();
    await seedCustomer(b, 'Demo Visitor', '9123456780', '9988776655');
    await openPaymentPage(tester, backend: b);
    await enterKey(tester, 'customer-phone', '912');
    await tapKey(
      tester,
      'customer-suggestion-${idOf('Demo Visitor', '9123456780')}',
    );
    expect(fieldText(tester, 'customer-name'), 'Demo Visitor');
    expect(fieldText(tester, 'customer-phone'), '9123456780');
    expect(find.byKey(const Key('customer-whatsapp')), findsOneWidget);
    expect(fieldText(tester, 'customer-whatsapp'), '9988776655');
    await tapKey(tester, 'save');
    await tapKey(tester, 'confirm');
    expect(b.sales.createCalls.single.customer.whatsapp, '9988776655');
  });

  testWidgets('the same mobile with two names offers both', (tester) async {
    final b = fakeBackend();
    await seedCustomer(b, 'Test Customer', '9876543210', null);
    await seedCustomer(b, 'Sample Buyer', '9876543210', null);
    await openPaymentPage(tester, backend: b);
    await enterKey(tester, 'customer-phone', '9876543210');
    expect(find.text('Test Customer'), findsOneWidget);
    expect(find.text('Sample Buyer'), findsOneWidget);
  });

  testWidgets('a bill saved here becomes a suggestion for the next one', (
    tester,
  ) async {
    final b = await openPaymentPage(tester);
    await saveWithReview(tester);
    expect(b.customers.all('PTB').single.billCount, 1);
    await tapKey(tester, 'new-bill');
    await tapKey(tester, 'product-bf-500');
    await tapKey(tester, 'charge');
    await enterKey(tester, 'customer-phone', '987');
    expect(find.text('Test Customer'), findsOneWidget);
  });
}
