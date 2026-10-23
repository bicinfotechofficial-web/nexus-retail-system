import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_admin/fakes/fake_backend.dart';
import 'package:nexus_admin/fakes/fake_repositories.dart';
import 'package:nexus_admin/reports/report_aggregator.dart';
import 'package:nexus_core/nexus_core.dart';

import 'helpers.dart';

/// PTB billed Rs 3,000 today: Rs 1,000 in cash and a Rs 2,000 advance paid
/// earlier on a pre-order, which it delivered. It also took Rs 1,500 in new
/// advances and refunded Rs 200 of a cancelled order's. MNJ billed Rs 500
/// in cash and took Rs 300 in an advance.
const _ptbToday = Summary(
  billCount: 2,
  grossSales: Money.rupees(3000),
  netSales: Money.rupees(3000),
  byMode: {
    PaymentMode.cash: Money.rupees(1000),
    PaymentMode.advance: Money.rupees(2000),
  },
  advanceReceived: Money.rupees(1500),
  advanceRefunded: Money.rupees(200),
);
const _mnjToday = Summary(
  billCount: 1,
  grossSales: Money.rupees(500),
  netSales: Money.rupees(500),
  byMode: {PaymentMode.cash: Money.rupees(500)},
  advanceReceived: Money.rupees(300),
);

FakeBackend _backend() {
  final seeded = FakeBackend.seeded(today: testToday);
  return FakeBackend(
    auth: seeded.auth,
    locations: seeded.locations,
    catalog: seeded.catalog,
    stock: seeded.stock,
    summaries: FakeSummaryRepository(
      dailyDocs: {
        'PTB': {testToday: _ptbToday},
        'MNJ': {testToday: _mnjToday},
      },
      monthlyDocs: {
        'PTB': {
          '2026-09':
              _ptbToday +
              const Summary(
                netSales: Money.rupees(7000),
                byMode: {PaymentMode.upi: Money.rupees(7000)},
                advanceReceived: Money.rupees(2500),
              ),
        },
        'MNJ': {'2026-09': _mnjToday},
      },
    ),
  );
}

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

Future<void> _openReports(WidgetTester tester) async {
  await pumpAdmin(tester, _backend(), size: const Size(1400, 2400));
  await signIn(tester);
  await goTo(tester, '/reports');
}

void main() {
  group('the advance in the aggregated report', () {
    test('the payment modes add up to net revenue with ADVANCE in them', () {
      final report = ReportAggregator.build({
        'PTB': _ptbToday,
        'MNJ': _mnjToday,
      });
      expect(report.byMode.map((e) => e.$1), PaymentMode.values);
      final modes = {for (final e in report.byMode) e.$1: e.$2};
      expect(modes[PaymentMode.advance], const Money.rupees(2000));
      expect(modes[PaymentMode.cash], const Money.rupees(1500));
      final sum = report.byMode.fold(Money.zero, (s, e) => s + e.$2);
      expect(sum, report.total.netRevenue);
      expect(sum, const Money.rupees(3500));
    });

    test('advances are summed across stores and stay out of sales', () {
      final total = ReportAggregator.combine([_ptbToday, _mnjToday]);
      expect(total.advanceReceived, const Money.rupees(1800));
      expect(total.advanceRefunded, const Money.rupees(200));
      // Sales do not include money taken ahead.
      expect(total.netRevenue, const Money.rupees(3500));
    });

    test('a year adds the advances of its months', () {
      final year = ReportAggregator.annual('2026', {
        '2026-08': const Summary(advanceReceived: Money.rupees(400)),
        '2026-09': _ptbToday,
      });
      expect(year.advanceReceived, const Money.rupees(1900));
      expect(year.advanceRefunded, const Money.rupees(200));
    });
  });

  testWidgets('the daily report shows advances apart from sales', (
    tester,
  ) async {
    await _openReports(tester);

    // Sales are net revenue: 3,000 + 500, with no advance taken ahead in it.
    expect(_text(tester, 'report-sales'), '₹3,500.00');
    expect(_text(tester, 'total-net-revenue'), '₹3,500.00');
    expect(_text(tester, 'PTB-advance-received'), '₹1,500.00');
    expect(_text(tester, 'MNJ-advance-received'), '₹300.00');
    expect(_text(tester, 'total-advance-received'), '₹1,800.00');
    expect(_text(tester, 'PTB-advance-refunded'), '₹200.00');
    expect(_text(tester, 'MNJ-advance-refunded'), '₹0.00');
    expect(_text(tester, 'total-advance-refunded'), '₹200.00');
    expect(find.text('Advance received'), findsOneWidget);
    expect(find.text('Advance refunded'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('advance-help'))).data,
      contains('sale itself counts on the delivery day'),
    );
  });

  testWidgets('the payment-mode breakdown has Advance paid and still adds up', (
    tester,
  ) async {
    await _openReports(tester);

    expect(find.text('Advance paid'), findsOneWidget);
    expect(_text(tester, 'mode-ADVANCE'), '₹2,000.00');
    expect(_text(tester, 'mode-CASH'), '₹1,500.00');
    expect(_text(tester, 'mode-UPI'), '₹0.00');
    // Cash 1,500 + Advance paid 2,000 is the net revenue.
    expect(_text(tester, 'mode-total'), '₹3,500.00');
    expect(_text(tester, 'mode-total'), _text(tester, 'total-net-revenue'));
  });

  testWidgets('the monthly report carries the advance lines too', (
    tester,
  ) async {
    await _openReports(tester);
    await tester.tap(find.text('Monthly'));
    await tester.pumpAndSettle();

    expect(_text(tester, 'PTB-advance-received'), '₹4,000.00');
    expect(_text(tester, 'total-advance-received'), '₹4,300.00');
    expect(_text(tester, 'total-advance-refunded'), '₹200.00');
    // Net revenue 10,000 + 500; the modes still add up to it.
    expect(_text(tester, 'total-net-revenue'), '₹10,500.00');
    expect(_text(tester, 'mode-ADVANCE'), '₹2,000.00');
    expect(_text(tester, 'mode-total'), '₹10,500.00');
  });
}
