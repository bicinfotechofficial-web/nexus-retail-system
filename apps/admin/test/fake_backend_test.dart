import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_admin/fakes/fake_backend.dart';
import 'package:nexus_admin/reports/report_aggregator.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';

void main() {
  final backend = FakeBackend.seeded(today: '2026-09-26');
  final daily = backend.summaries.dailyDocs;
  final monthly = backend.summaries.monthlyDocs;

  test('seeds PTB and MNJ from 1 July to today', () {
    expect(daily.keys, unorderedEquals(['PTB', 'MNJ']));
    for (final days in daily.values) {
      expect(days.keys.first, '2026-07-01');
      expect(days.keys.last, '2026-09-26');
      expect(days, hasLength(31 + 31 + 26));
    }
    expect(monthly['PTB']!.keys, ['2026-07', '2026-08', '2026-09']);
  });

  test('a month is the sum of its days, plus expenses', () {
    for (final loc in ['PTB', 'MNJ']) {
      for (final e in monthly[loc]!.entries) {
        final days = ReportAggregator.combine([
          for (final d in daily[loc]!.entries)
            if (BusinessDate.monthOf(d.key) == e.key) d.value,
        ]);
        expect(e.value.netSales, days.netSales, reason: '$loc ${e.key}');
        expect(e.value.billCount, days.billCount);
        expect(e.value.netRevenue, days.netRevenue);
        expect(e.value.expenses.isPositive, isTrue);
        expect(days.expenses, Money.zero);
      }
    }
  });

  test('each day is internally consistent', () {
    for (final days in daily.values) {
      for (final s in days.values) {
        final modes = s.byMode.values.fold(Money.zero, (a, b) => a + b);
        expect(modes, s.netRevenue);
        expect(s.netSales.isWholeRupees, isTrue);
        // A cancelled bill stays in gross and net sales (SummaryDelta).
        expect(s.grossSales - s.discounts + s.roundOff, s.netSales);
        expect(s.netRevenue.isNegative, isFalse);
      }
    }
  });

  test('is deterministic and has low stock at both locations', () async {
    final again = FakeBackend.seeded(today: '2026-09-26');
    expect(
      again.summaries.dailyDocs['MNJ']!['2026-08-15']!.netSales,
      daily['MNJ']!['2026-08-15']!.netSales,
    );
    expect(await backend.stock.watchLowStock('PTB').first, hasLength(2));
    expect(await backend.stock.watchLowStock('MNJ').first, hasLength(1));
  });

  test('signs in the Admin and the Store Manager, rejects others', () async {
    final admin = await backend.auth.signIn(
      email: FakeBackend.adminEmail,
      password: FakeBackend.demoPassword,
    );
    expect(admin.can(Permission.reportAll), isTrue);
    final sm = await backend.auth.signIn(
      email: FakeBackend.storeManagerEmail,
      password: FakeBackend.demoPassword,
    );
    expect(sm.can(Permission.reportAll), isFalse);
    expect(sm.canAt(Permission.reportOwn, 'PTB'), isTrue);
    expect(sm.canAt(Permission.reportOwn, 'MNJ'), isFalse);
    await expectLater(
      backend.auth.signIn(email: 'x@y.z', password: 'nope'),
      throwsA(isA<DataFailure>()),
    );
  });
}
