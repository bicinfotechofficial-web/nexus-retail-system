import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_admin/fakes/fake_repositories.dart';
import 'package:nexus_admin/reports/report_aggregator.dart';
import 'package:nexus_admin/reports/report_period.dart';
import 'package:nexus_core/nexus_core.dart';

void main() {
  group('several locations combined', () {
    // Three locations on one day, figures in paise.
    const ptb = Summary(
      billCount: 40,
      cancelCount: 1,
      returnCount: 2,
      grossSales: Money(1250000),
      discounts: Money(25050),
      roundOff: Money(50),
      netSales: Money(1225000),
      returns: Money(18000),
      cancelled: Money(45000),
      byMode: {PaymentMode.cash: Money(600000), PaymentMode.upi: Money(562000)},
      byProduct: {
        'bf1kg': ProductTally(qty: 5, amount: Money(318000)),
        'vegpuff': ProductTally(qty: 60, amount: Money(147000)),
      },
    );
    const mnj = Summary(
      billCount: 25,
      returnCount: 1,
      grossSales: Money(810000),
      discounts: Money(10000),
      roundOff: Money(-25),
      netSales: Money(799975),
      returns: Money(6000),
      byMode: {
        PaymentMode.cash: Money(400000),
        PaymentMode.card: Money(393975),
      },
      byProduct: {
        'bf1kg': ProductTally(qty: 3, amount: Money(195000)),
        'rv1kg': ProductTally(qty: 4, amount: Money(320000)),
      },
    );
    const kkd = Summary(
      billCount: 10,
      cancelCount: 2,
      grossSales: Money(300000),
      netSales: Money(300000),
      cancelled: Money(70000),
      byMode: {PaymentMode.wallet: Money(230000)},
      byProduct: {'vegpuff': ProductTally(qty: 20, amount: Money(50000))},
    );

    test('adds every field', () {
      final r = ReportAggregator.build({'PTB': ptb, 'MNJ': mnj, 'KKD': kkd});
      final t = r.total;
      expect(t.billCount, 75); // 40 + 25 + 10
      expect(t.cancelCount, 3); // 1 + 0 + 2
      expect(t.returnCount, 3); // 2 + 1 + 0
      expect(t.grossSales, const Money(2360000)); // ₹23,600
      expect(t.discounts, const Money(35050)); // ₹350.50
      expect(t.roundOff, const Money(25)); // 50 − 25
      expect(t.netSales, const Money(2324975)); // ₹23,249.75
      expect(t.returns, const Money(24000)); // ₹240
      expect(t.cancelled, const Money(115000)); // ₹1,150
      // 23,249.75 − 240 − 1,150 = 21,859.75
      expect(t.netRevenue, const Money(2185975));
      expect(t.netRevenue.format(), '₹21,859.75');
    });

    test('merges payment modes and products by key', () {
      final r = ReportAggregator.build({'PTB': ptb, 'MNJ': mnj, 'KKD': kkd});
      expect(r.byMode, [
        (PaymentMode.cash, const Money(1000000)),
        (PaymentMode.upi, const Money(562000)),
        (PaymentMode.card, const Money(393975)),
        (PaymentMode.wallet, const Money(230000)),
        (PaymentMode.other, Money.zero),
      ]);
      final top = r.topProducts();
      expect(top.map((p) => p.productId), ['bf1kg', 'rv1kg', 'vegpuff']);
      expect(top[0].qty, 8);
      expect(top[0].amount, const Money(513000));
      expect(top[2].qty, 80);
      expect(top[2].amount, const Money(197000));
      expect(r.topProducts(1).single.productId, 'bf1kg');
    });

    test('keeps each location and sorts them by code', () {
      final r = ReportAggregator.build({'PTB': ptb, 'MNJ': mnj, 'KKD': kkd});
      expect(r.byLocation.keys, ['KKD', 'MNJ', 'PTB']);
      expect(r.byLocation['MNJ']!.netRevenue, const Money(793975));
    });

    test('no locations gives zeros', () {
      final r = ReportAggregator.build({});
      expect(r.total.netRevenue, Money.zero);
      expect(r.topProducts(), isEmpty);
    });
  });

  group('a year from 12 months', () {
    // Month m (1..12): m × 10 bills, ₹1,000·m net sales, ₹10·m returns,
    // ₹5·m cancelled, ₹300 expenses, m cakes for ₹650·m.
    Summary month(int m) => Summary(
      billCount: 10 * m,
      returnCount: m,
      cancelCount: 1,
      grossSales: Money.rupees(1100 * m),
      discounts: Money.rupees(100 * m),
      netSales: Money.rupees(1000 * m),
      returns: Money.rupees(10 * m),
      cancelled: Money.rupees(5 * m),
      byMode: {PaymentMode.cash: Money.rupees(985 * m)},
      byProduct: {'bf1kg': ProductTally(qty: m, amount: Money.rupees(650 * m))},
      expenses: Money.rupees(300),
      byExpenseCategory: {ExpenseCategory.rent: Money.rupees(300)},
    );
    final months = {
      for (var m = 1; m <= 12; m++)
        '2026-${m.toString().padLeft(2, '0')}': month(m),
    };

    test('matches hand-computed totals', () {
      final y = ReportAggregator.annual('2026', months);
      // Σ m for m = 1..12 is 78.
      expect(y.billCount, 780);
      expect(y.returnCount, 78);
      expect(y.cancelCount, 12);
      expect(y.grossSales, Money.rupees(85800));
      expect(y.discounts, Money.rupees(7800));
      expect(y.netSales, Money.rupees(78000));
      expect(y.returns, Money.rupees(780));
      expect(y.cancelled, Money.rupees(390));
      expect(y.netRevenue, Money.rupees(76830)); // 78,000 − 780 − 390
      expect(y.expenses, Money.rupees(3600));
      expect(y.profit, Money.rupees(73230));
      expect(y.byMode[PaymentMode.cash], Money.rupees(76830));
      expect(y.byProduct['bf1kg']!.qty, 78);
      expect(y.byProduct['bf1kg']!.amount, Money.rupees(50700));
      expect(y.byExpenseCategory[ExpenseCategory.rent], Money.rupees(3600));
    });

    test('months without a doc count as zero', () {
      final firstHalf = {
        for (final e in months.entries)
          if (e.key.compareTo('2026-06') <= 0) e.key: e.value,
      };
      // Σ m for m = 1..6 is 21.
      expect(
        ReportAggregator.annual('2026', firstHalf).netSales,
        Money.rupees(21000),
      );
      expect(ReportAggregator.annual('2026', {}).billCount, 0);
    });

    test('rejects a month from another year', () {
      expect(
        () => ReportAggregator.annual('2026', {...months, '2025-12': month(1)}),
        throwsArgumentError,
      );
      expect(() => ReportAggregator.monthsOf('26'), throwsFormatException);
      expect(ReportAggregator.monthsOf('2026'), hasLength(12));
      expect(ReportAggregator.monthsOf('2026').last, '2026-12');
    });

    test(
      'loadReport adds 12 months per location, then the locations',
      () async {
        final repo = FakeSummaryRepository(
          dailyDocs: const {},
          monthlyDocs: {
            'PTB': {...months, '2025-12': month(12), '2027-01': month(1)},
            'MNJ': {'2026-03': month(3)},
          },
        );
        final r = await loadReport(
          repo,
          const ReportPeriod(ReportKind.annual, '2026'),
          ['PTB', 'MNJ'],
        );
        expect(r.byLocation['PTB']!.netSales, Money.rupees(78000));
        expect(r.byLocation['MNJ']!.netSales, Money.rupees(3000));
        expect(r.total.netSales, Money.rupees(81000));
        expect(r.total.netRevenue, Money.rupees(76830 + 2955));
      },
    );
  });

  group('ReportPeriod', () {
    test('steps across month and year boundaries', () {
      const jan = ReportPeriod(ReportKind.monthly, '2026-01');
      expect(jan.shift(-1).key, '2025-12');
      expect(jan.shift(12).key, '2027-01');
      expect(
        const ReportPeriod(ReportKind.daily, '2026-03-01').shift(-1).key,
        '2026-02-28',
      );
      expect(
        const ReportPeriod(ReportKind.annual, '2026').shift(-1).key,
        '2025',
      );
    });

    test('knows when it is in the future', () {
      expect(
        const ReportPeriod(ReportKind.monthly, '2026-10').isAfter('2026-09-26'),
        isTrue,
      );
      expect(
        const ReportPeriod(ReportKind.annual, '2026').isAfter('2026-09-26'),
        isFalse,
      );
    });
  });
}
