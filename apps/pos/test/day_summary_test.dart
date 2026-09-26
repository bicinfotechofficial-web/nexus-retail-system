import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_pos/fakes/fake_backend.dart';

import 'helpers.dart';

void main() {
  testWidgets('headline Sales is net revenue, with counts, modes, returns '
      'and cancellations', (tester) async {
    final b = fakeBackend();
    await addBill(
      b,
      {'ct-1k': 1},
      at: testNow.subtract(const Duration(days: 1)),
      mode: PaymentMode.card,
    );
    await addBill(b, {'bf-500': 1});
    final toCancel = await addBill(b, {'rv-pastry': 2}, mode: PaymentMode.upi);
    final toReturn = await addBill(b, {'veg-puff': 4});
    await b.sales.cancelBill(billId: toCancel.id, reason: 'Duplicate');
    await b.sales.createReturn(
      billId: toReturn.id,
      qtyByProduct: {'veg-puff': 1},
      refunds: const [Payment(mode: PaymentMode.cash, amount: Money(2500))],
      reason: 'Stale',
    );

    await pumpPos(tester, backend: b);
    await openNav(tester, 'Day summary');

    // Billed 450 + 160 + 100 = 710, less the 25 return and the 160 cancel.
    final s = await b.summaries.watchDaily(Seed.locationId, '2026-09-26').first;
    expect(s.netRevenue, const Money(52500));
    expect(textOf(tester, 'summary-sales'), '₹525.00');
    expect(textOf(tester, 'summary-bill-count'), startsWith('3 bills'));
    expect(textOf(tester, 'summary-billed'), contains('₹710.00'));
    expect(textOf(tester, 'summary-returns'), contains('1 return'));
    expect(textOf(tester, 'summary-returns'), contains('-₹25.00'));
    expect(textOf(tester, 'summary-cancelled'), contains('1 bill'));
    expect(textOf(tester, 'summary-cancelled'), contains('-₹160.00'));
    // Cash 450 + 100 − 25; UPI was cancelled out, so it isn't listed.
    expect(textOf(tester, 'summary-mode-CASH'), contains('₹525.00'));
    expect(find.byKey(const Key('summary-mode-UPI')), findsNothing);

    await tapKey(tester, 'date-prev');
    expect(textOf(tester, 'summary-sales'), '₹950.00');
    expect(textOf(tester, 'summary-mode-CARD'), contains('₹950.00'));
  });

  testWidgets('updates live and shows zeros on a quiet day', (tester) async {
    final b = fakeBackend();
    await pumpPos(tester, backend: b);
    await openNav(tester, 'Day summary');
    expect(textOf(tester, 'summary-sales'), '₹0.00');
    expect(find.text('No payments.'), findsOneWidget);

    await addBill(b, {'brownie': 2}, mode: PaymentMode.upi);
    await tester.pumpAndSettle();
    expect(textOf(tester, 'summary-sales'), '₹145.00');
    expect(textOf(tester, 'summary-mode-UPI'), contains('₹145.00'));
  });
}
