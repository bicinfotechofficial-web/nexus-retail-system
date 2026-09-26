import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_admin/fakes/fake_backend.dart';
import 'package:nexus_admin/fakes/fake_repositories.dart';
import 'package:nexus_admin/financials/financials.dart';
import 'package:nexus_admin/financials/financials_screen.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';

import 'helpers.dart';

const _rent = ExpenseCategory.rent;
const _salary = ExpenseCategory.salary;
const _utilities = ExpenseCategory.utilities;

Summary _month({
  required int netSales,
  int returns = 0,
  int cancelled = 0,
  Map<ExpenseCategory, int> expenses = const {},
}) => Summary(
  netSales: Money.rupees(netSales),
  returns: Money.rupees(returns),
  cancelled: Money.rupees(cancelled),
  expenses: Money.rupees(expenses.values.fold(0, (a, b) => a + b)),
  byExpenseCategory: {
    for (final e in expenses.entries) e.key: Money.rupees(e.value),
  },
);

/// Three locations; KTL closed after July. In rupees:
///
/// | loc | month | sales (net revenue)        | expenses | profit  |
/// |-----|-------|----------------------------|----------|---------|
/// | PTB | Jul   | 1,00,000 − 2,000 − 1,000 = 97,000 | 60,000 | 37,000 |
/// | PTB | Aug   | 80,000                     | 95,000   | −15,000 |
/// | MNJ | Aug   | 50,000 − 500 = 49,500      | 30,000   | 19,500  |
/// | MNJ | Sep   | 40,000                     | 20,000   | 20,000  |
/// | KTL | Jul   | 30,000 − 300 = 29,700      | 25,000   | 4,700   |
final Map<String, Map<String, Summary>> _monthly = {
  'PTB': {
    '2026-07': _month(
      netSales: 100000,
      returns: 2000,
      cancelled: 1000,
      expenses: {_rent: 35000, _salary: 25000},
    ),
    '2026-08': _month(
      netSales: 80000,
      expenses: {_rent: 35000, _salary: 60000},
    ),
  },
  'MNJ': {
    '2026-08': _month(netSales: 50000, returns: 500, expenses: {_rent: 30000}),
    '2026-09': _month(netSales: 40000, expenses: {_utilities: 20000}),
  },
  'KTL': {
    '2026-07': _month(
      netSales: 30000,
      cancelled: 300,
      expenses: {_rent: 25000},
    ),
  },
};

const _q3 = ['2026-07', '2026-08', '2026-09'];

({Money sales, Money expenses, Money profit}) _fig(Summary s) =>
    (sales: s.netRevenue, expenses: s.expenses, profit: s.profit);

({Money sales, Money expenses, Money profit}) _rupees(
  int sales,
  int expenses,
  int profit,
) => (
  sales: Money.rupees(sales),
  expenses: Money.rupees(expenses),
  profit: Money.rupees(profit),
);

void main() {
  group('FinancialsAggregator', () {
    final f = FinancialsAggregator.build(months: _q3, monthly: _monthly);

    test('cells are each location-month, zero where there is no doc', () {
      expect(f.locations, ['KTL', 'MNJ', 'PTB']);
      expect(_fig(f.cell('PTB', '2026-07')), _rupees(97000, 60000, 37000));
      expect(_fig(f.cell('PTB', '2026-08')), _rupees(80000, 95000, -15000));
      expect(_fig(f.cell('MNJ', '2026-08')), _rupees(49500, 30000, 19500));
      expect(_fig(f.cell('KTL', '2026-07')), _rupees(29700, 25000, 4700));
      expect(_fig(f.cell('KTL', '2026-09')), _rupees(0, 0, 0));
      expect(_fig(f.cell('XYZ', '2026-07')), _rupees(0, 0, 0));
    });

    test('each month combines every location, the closed one included', () {
      // Jul: PTB 97,000 + KTL 29,700; expenses 60,000 + 25,000.
      expect(_fig(f.month('2026-07')), _rupees(126700, 85000, 41700));
      // Aug: PTB 80,000 + MNJ 49,500; expenses 95,000 + 30,000.
      expect(_fig(f.month('2026-08')), _rupees(129500, 125000, 4500));
      expect(_fig(f.month('2026-09')), _rupees(40000, 20000, 20000));
    });

    test('each location combines its months', () {
      expect(_fig(f.location('PTB')), _rupees(177000, 155000, 22000));
      expect(_fig(f.location('MNJ')), _rupees(89500, 50000, 39500));
      expect(_fig(f.location('KTL')), _rupees(29700, 25000, 4700));
    });

    test('the grand total agrees by month and by location', () {
      expect(_fig(f.total), _rupees(296200, 230000, 66200));
      final byLocation = [for (final l in f.locations) f.location(l).profit];
      expect(byLocation.fold(Money.zero, (a, b) => a + b), f.total.profit);
      // Rent: 35,000 + 35,000 + 30,000 + 25,000.
      expect(f.total.byExpenseCategory[_rent], Money.rupees(125000));
      expect(f.total.byExpenseCategory[_salary], Money.rupees(85000));
    });

    test('rejects a month outside the period', () {
      expect(
        () => FinancialsAggregator.build(
          months: const ['2026-08'],
          monthly: _monthly,
        ),
        throwsArgumentError,
      );
    });

    test('a location with no docs still gets zeros', () {
      final g = FinancialsAggregator.build(
        months: _q3,
        monthly: {'PTB': const {}},
      );
      expect(g.locations, ['PTB']);
      expect(_fig(g.total), _rupees(0, 0, 0));
    });

    test('monthsToShow stops at the current month', () {
      expect(FinancialsAggregator.monthsToShow('2026', '2026-03'), [
        '2026-01',
        '2026-02',
        '2026-03',
      ]);
      expect(
        FinancialsAggregator.monthsToShow('2025', '2026-03'),
        hasLength(12),
      );
      expect(FinancialsAggregator.monthsToShow('2027', '2026-03'), isEmpty);
    });

    test('loadFinancials reads the monthly summaries of the months', () async {
      final repo = FakeSummaryRepository(
        dailyDocs: const {},
        monthlyDocs: {
          ..._monthly,
          // Outside the period asked for: must not be read.
          'PTB': {..._monthly['PTB']!, '2025-12': _month(netSales: 999)},
        },
      );
      final loaded = await loadFinancials(repo, _q3, ['PTB', 'MNJ', 'KTL']);
      expect(_fig(loaded.total), _rupees(296200, 230000, 66200));
    });

    test('an expense saved through the service shows up in profit', () async {
      final backend = FakeBackend.seeded(today: testToday);
      final before = await loadFinancials(backend.summaries, _q3, ['MNJ']);
      await backend.expenses.save(
        ExpenseInput(
          locationId: 'MNJ',
          category: ExpenseCategory.other,
          amount: const Money(12345),
          date: '2026-08-10',
          note: 'Repairs',
        ),
      );
      final after = await loadFinancials(backend.summaries, _q3, ['MNJ']);
      expect(
        after.month('2026-08').profit,
        before.month('2026-08').profit - const Money(12345),
      );
      expect(
        after.month('2026-08').netRevenue,
        before.month('2026-08').netRevenue,
      );
      expect(after.month('2026-09').profit, before.month('2026-09').profit);
    });
  });

  group('Financials screen', () {
    FakeBackend backend() {
      final seeded = FakeBackend.seeded(today: testToday);
      return FakeBackend(
        auth: seeded.auth,
        locations: seeded.locations,
        catalog: seeded.catalog,
        stock: seeded.stock,
        summaries: FakeSummaryRepository(
          dailyDocs: const {},
          monthlyDocs: _monthly,
        ),
      );
    }

    String text(WidgetTester tester, String key) =>
        tester.widget<Text>(find.byKey(Key(key))).data!;

    Future<void> open(
      WidgetTester tester,
      FakeBackend b, {
      String email = FakeBackend.adminEmail,
    }) async {
      await pumpAdmin(tester, b);
      await signIn(tester, email: email);
      await goTo(tester, '/financials');
    }

    testWidgets('by month, by location and the profit matrix', (tester) async {
      await open(tester, backend());

      expect(text(tester, 'financials-year'), '2026');
      expect(text(tester, 'kpi-sales'), '₹2,96,200.00');
      expect(text(tester, 'kpi-expenses'), '₹2,30,000.00');
      expect(text(tester, 'kpi-profit'), '₹66,200.00');

      // January to September; nothing after the current month.
      expect(text(tester, 'fin-2026-01-profit'), '₹0.00');
      expect(find.byKey(const Key('fin-2026-10-profit')), findsNothing);
      expect(text(tester, 'fin-2026-07-sales'), '₹1,26,700.00');
      expect(text(tester, 'fin-2026-08-profit'), '₹4,500.00');
      expect(text(tester, 'fin-total-profit'), '₹66,200.00');

      expect(text(tester, 'fin-loc-PTB-profit'), '₹22,000.00');
      expect(text(tester, 'fin-loc-KTL-sales'), '₹29,700.00');
      expect(find.text('KTL (inactive)'), findsNWidgets(2));

      expect(text(tester, 'fin-2026-08-PTB-profit'), '-₹15,000.00');
      expect(text(tester, 'fin-2026-07-KTL-profit'), '₹4,700.00');
      expect(text(tester, 'fin-2026-07-all-profit'), '₹41,700.00');
      expect(text(tester, 'fin-cat-RENT'), '₹1,25,000.00');

      // A loss is shown in the error colour.
      final error = Theme.of(
        tester.element(find.byType(FinancialsScreen)),
      ).colorScheme.error;
      final loss = tester.widget<Text>(
        find.byKey(const Key('fin-2026-08-PTB-profit')),
      );
      expect(loss.style?.color, error);
    });

    testWidgets('a single location, and an earlier year', (tester) async {
      await open(tester, backend());

      await tester.tap(find.byKey(const Key('location-switcher')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pattambi (PTB)').last);
      await tester.pumpAndSettle();
      expect(text(tester, 'kpi-profit'), '₹22,000.00');
      expect(find.byKey(const Key('financials-by-location')), findsNothing);
      expect(find.byKey(const Key('financials-matrix')), findsNothing);

      final next = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.chevron_right),
          matching: find.byType(IconButton),
        ),
      );
      expect(next.onPressed, isNull);

      await tester.tap(find.byTooltip('Previous year'));
      await tester.pumpAndSettle();
      expect(text(tester, 'financials-year'), '2025');
      expect(text(tester, 'fin-2025-12-profit'), '₹0.00');
      expect(text(tester, 'kpi-profit'), '₹0.00');
    });

    testWidgets('a saved expense lowers the profit shown', (tester) async {
      final b = backend();
      await open(tester, b);
      expect(text(tester, 'fin-2026-09-profit'), '₹20,000.00');

      await b.expenses.save(
        ExpenseInput(
          locationId: 'MNJ',
          category: ExpenseCategory.other,
          amount: Money.rupees(1500),
          date: '2026-09-20',
          note: 'Repairs',
        ),
      );
      await goTo(tester, '/expenses');
      await goTo(tester, '/financials');
      expect(text(tester, 'fin-2026-09-profit'), '₹18,500.00');
      expect(text(tester, 'fin-2026-09-expenses'), '₹21,500.00');
    });

    testWidgets('a Store Manager sees only their own location', (tester) async {
      await open(tester, backend(), email: FakeBackend.storeManagerEmail);
      expect(text(tester, 'kpi-profit'), '₹22,000.00');
      expect(find.byKey(const Key('financials-matrix')), findsNothing);
    });
  });
}
