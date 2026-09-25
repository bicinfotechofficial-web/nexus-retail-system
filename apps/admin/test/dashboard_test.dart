import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_admin/fakes/fake_backend.dart';
import 'package:nexus_admin/fakes/fake_repositories.dart';
import 'package:nexus_core/nexus_core.dart';

import 'helpers.dart';

StockItem _stock(String id, int qty, int? threshold) => StockItem(
  itemKey: 'RM_$id',
  kind: StockKind.raw,
  refId: id,
  name: id,
  unit: StockUnit.g,
  qty: qty,
  lowThreshold: threshold,
);

/// Hand-built data for [testToday], so every figure below is known.
FakeBackend _backend() {
  final seeded = FakeBackend.seeded(today: testToday);
  return FakeBackend(
    auth: seeded.auth,
    locations: seeded.locations,
    catalog: seeded.catalog,
    summaries: FakeSummaryRepository(
      dailyDocs: {
        'PTB': {
          testToday: const Summary(
            billCount: 12,
            returnCount: 1,
            cancelCount: 1,
            netSales: Money.rupees(5400),
            returns: Money.rupees(200),
            cancelled: Money.rupees(300),
          ),
          // Yesterday must not show up on today's dashboard.
          '2026-09-25': const Summary(
            billCount: 99,
            netSales: Money.rupees(99999),
          ),
        },
        'MNJ': {
          testToday: const Summary(billCount: 8, netSales: Money(310050)),
        },
      },
      monthlyDocs: const {},
    ),
    stock: FakeStockRepository({
      'PTB': [
        _stock('flour', 100, 500),
        _stock('sugar', 500, 500),
        _stock('cream', 900, 500),
      ],
      'MNJ': [_stock('eggs', 0, 10), _stock('butter', 50, null)],
    }),
  );
}

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

void main() {
  testWidgets('shows today per location and the total across them', (
    tester,
  ) async {
    await pumpAdmin(tester, _backend());
    await signIn(tester);

    expect(find.text('26 Sep 2026 · All locations'), findsOneWidget);

    expect(_text(tester, 'PTB-net-sales'), '₹5,400.00');
    expect(_text(tester, 'PTB-bills'), '12');
    expect(_text(tester, 'PTB-returns'), '₹200.00 (1)');
    expect(_text(tester, 'PTB-cancelled'), '₹300.00 (1)');
    expect(_text(tester, 'PTB-net-revenue'), '₹4,900.00');
    expect(_text(tester, 'PTB-low-stock'), '2');

    expect(_text(tester, 'MNJ-net-sales'), '₹3,100.50');
    expect(_text(tester, 'MNJ-bills'), '8');
    expect(_text(tester, 'MNJ-returns'), '₹0.00 (0)');
    expect(_text(tester, 'MNJ-net-revenue'), '₹3,100.50');
    expect(_text(tester, 'MNJ-low-stock'), '1');

    // 5,400 + 3,100.50 = 8,500.50; net revenue 8,500.50 − 200 − 300.
    expect(_text(tester, 'total-net-sales'), '₹8,500.50');
    expect(_text(tester, 'total-bills'), '20');
    expect(_text(tester, 'total-returns'), '₹200.00 (1)');
    expect(_text(tester, 'total-net-revenue'), '₹8,000.50');
    expect(_text(tester, 'total-low-stock'), '3');

    expect(find.text('₹8,500.50'), findsNWidgets(2)); // KPI card and total
    expect(find.text('flour · PTB'), findsOneWidget);
    expect(find.text('eggs · MNJ'), findsOneWidget);
    expect(find.text('cream · PTB'), findsNothing);
  });

  testWidgets('a single location hides the other one and the total', (
    tester,
  ) async {
    await pumpAdmin(tester, _backend());
    await signIn(tester);

    await tester.tap(find.byKey(const Key('location-switcher')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manjeri (MNJ)').last);
    await tester.pumpAndSettle();

    expect(find.text('26 Sep 2026 · Manjeri'), findsOneWidget);
    expect(find.byKey(const Key('MNJ-bills')), findsOneWidget);
    expect(find.byKey(const Key('PTB-bills')), findsNothing);
    expect(find.byKey(const Key('total-bills')), findsNothing);
  });

  testWidgets('a Store Manager sees only their own location', (tester) async {
    await pumpAdmin(tester, _backend());
    await signIn(tester, email: FakeBackend.storeManagerEmail);

    expect(_text(tester, 'PTB-bills'), '12');
    expect(find.byKey(const Key('MNJ-bills')), findsNothing);
  });
}
