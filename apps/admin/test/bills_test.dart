import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_admin/fakes/fake_backend.dart';

import 'helpers.dart';

Future<void> _openBills(WidgetTester tester, FakeBackend backend) async {
  await pumpAdmin(tester, backend);
  await signIn(tester);
  await tester.tap(find.byIcon(Icons.point_of_sale_outlined));
  await tester.pumpAndSettle();
}

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

void main() {
  late FakeBackend backend;
  setUp(() => backend = FakeBackend.seeded(today: testToday));

  testWidgets('the bills list shows each bill\'s customer', (tester) async {
    await _openBills(tester, backend);

    // Five bills across PTB and MNJ.
    expect(find.byKey(const Key('bills-table')), findsOneWidget);
    expect(_text(tester, 'bill-customer-D01-000001'), isNotEmpty);
    // PTB D02-000003: a customer who is not on WhatsApp.
    expect(_text(tester, 'bill-customer-D02-000003'), 'Sample Buyer');
    expect(_text(tester, 'bill-mobile-D02-000003'), '9123456780');
    expect(_text(tester, 'bill-whatsapp-D02-000003'), 'No WhatsApp');
    // MNJ's customer has a different WhatsApp number.
    expect(find.text('Another Customer'), findsOneWidget);
    expect(find.text('9000011111'), findsOneWidget);
  });

  testWidgets('a bill from before customers were recorded shows a dash', (
    tester,
  ) async {
    await _openBills(tester, backend);

    expect(_text(tester, 'bill-customer-D02-000004'), '—');
    expect(_text(tester, 'bill-mobile-D02-000004'), '—');
    expect(_text(tester, 'bill-whatsapp-D02-000004'), '—');

    await tester.tap(find.text('PTB-D02-000004'));
    await tester.pumpAndSettle();
    expect(_text(tester, 'detail-name'), '—');
    expect(_text(tester, 'detail-mobile'), '—');
    expect(_text(tester, 'detail-whatsapp'), '—');
  });

  testWidgets('the bill detail shows the customer, read only', (tester) async {
    await _openBills(tester, backend);

    await tester.tap(find.text('PTB-D01-000002'));
    await tester.pumpAndSettle();
    expect(_text(tester, 'detail-name'), 'Test Customer');
    expect(_text(tester, 'detail-mobile'), '9876543210');
    expect(_text(tester, 'detail-whatsapp'), '9876543210');
    expect(_text(tester, 'detail-total'), '₹240.00');
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.byKey(const Key('detail-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('detail-name')), findsNothing);
  });

  testWidgets('the location switcher and the day narrow the list', (
    tester,
  ) async {
    await _openBills(tester, backend);

    await tester.tap(find.byKey(const Key('location-switcher')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manjeri (MNJ)').last);
    await tester.pumpAndSettle();
    expect(find.text('MNJ-D01-000007'), findsOneWidget);
    expect(find.text('PTB-D01-000001'), findsNothing);

    await tester.tap(find.byKey(const Key('bills-prev')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('bills-empty')), findsOneWidget);
  });
}
