import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_admin/fakes/fake_backend.dart';
import 'package:nexus_admin/fakes/fake_repositories.dart';

import 'helpers.dart';

Future<void> _openCustomers(WidgetTester tester, FakeBackend backend) async {
  await pumpAdmin(tester, backend);
  await signIn(tester);
  await tester.tap(find.text('Customers'));
  await tester.pumpAndSettle();
}

Future<void> _pickLocation(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(const Key('location-switcher')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

List<String> _rowKeys(WidgetTester tester) => [
  for (final r
      in tester
          .widget<DataTable>(find.byKey(const Key('customers-table')))
          .rows)
    (r.key! as ValueKey<String>).value,
];

void main() {
  late FakeBackend backend;
  setUp(() => backend = FakeBackend.seeded(today: testToday));

  testWidgets('lists customers across locations with their totals', (
    tester,
  ) async {
    await _openCustomers(tester, backend);

    expect(find.text('3 of 3 customers'), findsOneWidget);
    // Two PTB bills of Rs 80 and Rs 240 for the same name and mobile.
    expect(find.text('Test Customer'), findsOneWidget);
    expect(find.text('9876543210'), findsNWidgets(2));
    expect(find.text('₹320.00'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    // A customer without WhatsApp, a different WhatsApp number, a location.
    expect(find.text('No WhatsApp'), findsOneWidget);
    expect(find.text('9000011111'), findsOneWidget);
    expect(find.text('MNJ'), findsOneWidget);
    expect(find.text('26 Sep 2026'), findsWidgets);
    // The bill without a customer adds no record.
    expect(_rowKeys(tester), hasLength(3));
  });

  testWidgets('search filters by name or mobile', (tester) async {
    await _openCustomers(tester, backend);

    await tester.enterText(find.byKey(const Key('customer-search')), 'another');
    await tester.pumpAndSettle();
    expect(find.text('1 of 3 customers'), findsOneWidget);
    expect(find.text('Another Customer'), findsOneWidget);
    expect(find.text('Test Customer'), findsNothing);

    await tester.enterText(find.byKey(const Key('customer-search')), '91234');
    await tester.pumpAndSettle();
    expect(find.text('Sample Buyer'), findsOneWidget);
    expect(find.text('1 of 3 customers'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('customer-search')), 'nobody');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('customers-empty')), findsOneWidget);
  });

  testWidgets('the location switcher narrows the list to one location', (
    tester,
  ) async {
    await _openCustomers(tester, backend);

    await _pickLocation(tester, 'Manjeri (MNJ)');
    expect(find.text('1 of 1 customers'), findsOneWidget);
    expect(find.text('Another Customer'), findsOneWidget);
    expect(find.text('Test Customer'), findsNothing);

    await _pickLocation(tester, 'Pattambi (PTB)');
    expect(find.text('2 of 2 customers'), findsOneWidget);
    expect(find.text('Another Customer'), findsNothing);

    await _pickLocation(tester, 'All locations');
    expect(find.text('3 of 3 customers'), findsOneWidget);
  });

  testWidgets('a Store Manager has no Customers entry and is refused there', (
    tester,
  ) async {
    await pumpAdmin(tester, backend);
    await signIn(tester, email: FakeBackend.storeManagerEmail);
    expect(find.text('Customers'), findsNothing);

    await goTo(tester, '/customers');
    expect(
      find.text('You do not have permission to view this page.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('customers-table')), findsNothing);
  });

  test('the fake customers are built from the bills', () async {
    final repo = FakeCustomerRepository.fromBills(
      FakeBackend.seedBills(testToday),
    );
    final all = await repo.watchAllLocations().first;
    expect(all.map((c) => c.billCount).fold<int>(0, (a, b) => a + b), 4);
    expect(all.every((c) => c.locationId != null), isTrue);
  });
}
