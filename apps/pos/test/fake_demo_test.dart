import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_pos/fakes/fake_backend.dart';

import 'helpers.dart';

void main() {
  testWidgets('FAKE_DATA demo seed: bills, a cancel, a return, summaries', (
    tester,
  ) async {
    final b = fakeBackend();
    await b.seedDemo();
    expect(b.sales.cancelCalls, isEmpty);
    expect(b.sales.returnCalls, isEmpty);

    final today = await b.bills.watchBills(Seed.locationId, '2026-09-26').first;
    expect(today, hasLength(3));
    expect(today.where((x) => x.status == BillStatus.cancelled), hasLength(1));
    final yesterday = await b.bills
        .watchBills(Seed.locationId, '2026-09-25')
        .first;
    expect(yesterday, hasLength(2));
    expect(yesterday.where((x) => x.returnedQty.isNotEmpty), hasLength(1));

    await pumpPos(tester, backend: b);
    await openNav(tester, 'Bills');
    expect(find.byType(ListTile), findsNWidgets(3));
    await openNav(tester, 'Day summary');
    final s = await b.summaries.watchDaily(Seed.locationId, '2026-09-26').first;
    expect(textOf(tester, 'summary-sales'), s.netRevenue.format());
    expect(s.cancelCount, 1);
  });
}
