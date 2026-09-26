import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_admin/fakes/fake_backend.dart';
import 'package:nexus_admin/fakes/fake_repositories.dart';
import 'package:nexus_core/nexus_core.dart';

import 'helpers.dart';

/// Hand-built summaries, so every figure below is known.
FakeBackend _backend() {
  final seeded = FakeBackend.seeded(today: testToday);
  return FakeBackend(
    auth: seeded.auth,
    locations: seeded.locations,
    catalog: seeded.catalog,
    stock: seeded.stock,
    summaries: FakeSummaryRepository(
      dailyDocs: {
        'PTB': {
          testToday: const Summary(
            billCount: 10,
            returnCount: 1,
            grossSales: Money.rupees(5000),
            discounts: Money.rupees(100),
            netSales: Money.rupees(4900),
            returns: Money.rupees(200),
            byMode: {
              PaymentMode.cash: Money.rupees(3000),
              PaymentMode.upi: Money.rupees(1700),
            },
            byProduct: {
              'bf1kg': ProductTally(qty: 4, amount: Money.rupees(2600)),
              'vegpuff': ProductTally(qty: 50, amount: Money.rupees(1100)),
            },
          ),
        },
        'MNJ': {
          testToday: const Summary(
            billCount: 5,
            cancelCount: 1,
            grossSales: Money.rupees(2000),
            netSales: Money.rupees(2000),
            cancelled: Money.rupees(300),
            byMode: {PaymentMode.card: Money.rupees(1700)},
            byProduct: {
              'rv1kg': ProductTally(qty: 2, amount: Money.rupees(1600)),
            },
          ),
        },
      },
      monthlyDocs: {
        'PTB': {
          '2025-12': const Summary(netSales: Money.rupees(70000)),
          '2026-08': const Summary(netSales: Money.rupees(90000)),
          '2026-09': const Summary(netSales: Money.rupees(100000)),
        },
        'MNJ': {'2026-09': const Summary(netSales: Money.rupees(50000))},
        // Kottakkal closed in August; its history stays (QA-031).
        'KTL': {
          '2026-07': const Summary(netSales: Money.rupees(40000)),
          '2026-08': const Summary(
            netSales: Money.rupees(30000),
            returns: Money.rupees(500),
          ),
        },
      },
    ),
  );
}

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

Future<void> _openReports(WidgetTester tester) async {
  await pumpAdmin(tester, _backend());
  await signIn(tester);
  await tester.tap(
    find.descendant(
      of: find.byType(NavigationRail),
      matching: find.text('Reports'),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

Future<void> _tapTooltip(WidgetTester tester, String tooltip) async {
  await tester.tap(find.byTooltip(tooltip));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('daily report for all locations, per location and combined', (
    tester,
  ) async {
    await _openReports(tester);

    expect(find.text('26 Sep 2026'), findsOneWidget);
    expect(_text(tester, 'PTB-gross'), '₹5,000.00');
    expect(_text(tester, 'PTB-discounts'), '-₹100.00');
    expect(_text(tester, 'PTB-net-sales'), '₹4,900.00');
    expect(_text(tester, 'MNJ-cancelled'), '-₹300.00 (1)');

    expect(_text(tester, 'total-gross'), '₹7,000.00');
    expect(_text(tester, 'total-discounts'), '-₹100.00');
    expect(_text(tester, 'total-net-sales'), '₹6,900.00');
    expect(_text(tester, 'total-returns'), '-₹200.00 (1)');
    expect(_text(tester, 'total-cancelled'), '-₹300.00 (1)');
    // 6,900 − 200 − 300.
    expect(_text(tester, 'total-net-revenue'), '₹6,400.00');
    expect(_text(tester, 'total-bills'), '15');
    // The headline "Sales" is net revenue (QA-013).
    expect(_text(tester, 'report-sales'), '₹6,400.00');

    expect(_text(tester, 'mode-CASH'), '₹3,000.00');
    expect(_text(tester, 'mode-UPI'), '₹1,700.00');
    expect(_text(tester, 'mode-CARD'), '₹1,700.00');
    expect(_text(tester, 'mode-WALLET'), '₹0.00');

    expect(_text(tester, 'top-0'), 'Black Forest 1 kg');
    expect(_text(tester, 'top-1'), 'Red Velvet 1 kg');
    expect(_text(tester, 'top-2'), 'Veg Puff');

    // Today is the latest day.
    final next = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.chevron_right),
        matching: find.byType(IconButton),
      ),
    );
    expect(next.onPressed, isNull);

    await _tapTooltip(tester, 'Previous');
    expect(find.text('25 Sep 2026'), findsOneWidget);
    expect(_text(tester, 'total-net-sales'), '₹0.00');
    expect(find.text('No sales in this period.'), findsOneWidget);
  });

  testWidgets('monthly and annual reports read monthly summaries', (
    tester,
  ) async {
    await _openReports(tester);

    await _tapText(tester, 'Monthly');
    expect(_text(tester, 'report-period'), 'September 2026');
    expect(_text(tester, 'PTB-net-sales'), '₹1,00,000.00');
    expect(_text(tester, 'total-net-sales'), '₹1,50,000.00');

    await _tapTooltip(tester, 'Previous');
    expect(_text(tester, 'report-period'), 'August 2026');
    // PTB 90,000 + the closed KTL's 30,000.
    expect(_text(tester, 'total-net-sales'), '₹1,20,000.00');

    // Annual 2026 = its months only: PTB 90,000 + 1,00,000, MNJ 50,000,
    // KTL 40,000 + 30,000.
    await _tapText(tester, 'Annual');
    expect(_text(tester, 'report-period'), '2026');
    expect(_text(tester, 'PTB-net-sales'), '₹1,90,000.00');
    expect(_text(tester, 'MNJ-net-sales'), '₹50,000.00');
    expect(_text(tester, 'KTL-net-sales'), '₹70,000.00');
    expect(_text(tester, 'total-net-sales'), '₹3,10,000.00');

    await _tapTooltip(tester, 'Previous');
    expect(_text(tester, 'report-period'), '2025');
    expect(_text(tester, 'total-net-sales'), '₹70,000.00');
  });

  testWidgets('a single location shows only its own figures', (tester) async {
    await _openReports(tester);

    await tester.tap(find.byKey(const Key('location-switcher')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manjeri (MNJ)').last);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('PTB-net-sales')), findsNothing);
    expect(find.byKey(const Key('MNJ-net-sales')), findsNothing);
    expect(_text(tester, 'total-net-sales'), '₹2,000.00');
    expect(_text(tester, 'total-net-revenue'), '₹1,700.00');
    expect(_text(tester, 'top-0'), 'Red Velvet 1 kg');
  });

  testWidgets('a deactivated location keeps its history (QA-031)', (
    tester,
  ) async {
    await _openReports(tester);
    await _tapText(tester, 'Monthly');
    await _tapTooltip(tester, 'Previous');

    // In "All locations", as its own column, marked inactive.
    expect(find.text('KTL (inactive)'), findsOneWidget);
    expect(_text(tester, 'KTL-net-sales'), '₹30,000.00');
    expect(_text(tester, 'KTL-net-revenue'), '₹29,500.00');

    // And on its own, from the switcher.
    await tester.tap(find.byKey(const Key('location-switcher')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kottakkal (KTL) (inactive)').last);
    await tester.pumpAndSettle();
    expect(_text(tester, 'total-net-sales'), '₹30,000.00');
    expect(_text(tester, 'report-sales'), '₹29,500.00');

    // Last year's figure doesn't change when a store closes.
    await _tapText(tester, 'Annual');
    expect(_text(tester, 'total-net-sales'), '₹70,000.00');
  });
}
