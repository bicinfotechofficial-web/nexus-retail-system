import 'dart:math';

import 'package:nexus_core/nexus_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  final bill = billFrom(
    BillCalculator.compute([
      line('BF', 2, 45000),
      line('CUP', 1, 12050),
    ], discount: const DiscountInput.percent(10)),
    payments: const [
      Payment(mode: PaymentMode.cash, amount: Money(50000)),
      Payment(mode: PaymentMode.upi, amount: Money(41800)),
    ],
  );

  test('forBill', () {
    final d = SummaryDeltas.forBill(bill);
    expect(d.billCount, 1);
    expect(d.grossSales, bill.subtotal);
    expect(d.discounts, bill.discountAmount);
    expect(d.roundOff, bill.roundOff);
    expect(d.netSales, bill.total);
    expect(d.byMode, {
      PaymentMode.cash: const Money(50000),
      PaymentMode.upi: const Money(41800),
    });
    expect(d.byProduct['BF']!.qty, 2);
    final productSum = d.byProduct.values.fold(
      Money.zero,
      (a, t) => a + t.amount,
    );
    expect(productSum, bill.total - bill.roundOff);
  });

  test('forCancel reverses modes and products but keeps netSales', () {
    final sum = SummaryDeltas.forBill(bill) + SummaryDeltas.forCancel(bill);
    expect(sum.netSales, bill.total);
    expect(sum.cancelled, bill.total);
    expect(sum.cancelCount, 1);
    expect(sum.netRevenue, Money.zero);
    expect(sum.byMode.values.every((m) => m.isZero), isTrue);
    expect(
      sum.byProduct.values.every((t) => t.qty == 0 && t.amount.isZero),
      isTrue,
    );
  });

  test('forReturn subtracts refunds by mode and product', () {
    final r = ReturnCalculator.compute(bill, {'BF': 1});
    final ret = SaleReturn(
      id: 'D01-R000001',
      billId: bill.id,
      billNo: bill.billNo,
      lines: r.lines,
      refundTotal: r.refundTotal,
      refunds: [Payment(mode: PaymentMode.cash, amount: r.refundTotal)],
      reason: 'damaged',
      businessDate: '2026-09-26',
      createdBy: 'u1',
      deviceId: 'D01',
      clientCreatedAt: t0,
    );
    final d = SummaryDeltas.forReturn(ret);
    expect(d.returnCount, 1);
    expect(d.returns, r.refundTotal);
    expect(d.byMode, {PaymentMode.cash: -r.refundTotal});
    expect(d.byProduct['BF']!.qty, -1);
    expect(d.byProduct['BF']!.amount, -r.lines.single.amount);
  });

  test('increments uses dotted field paths and leaves out zeros', () {
    final inc = SummaryDeltas.increments(SummaryDeltas.forBill(bill));
    expect(inc['billCount'], 1);
    expect(inc['byMode.CASH'], 50000);
    expect(inc['byMode.UPI'], 41800);
    expect(inc['byProduct.BF.qty'], 2);
    expect(inc.containsKey('cancelCount'), isFalse);
    expect(inc.containsKey('byMode.CARD'), isFalse);
    final exp = SummaryDeltas.increments(
      const Summary(
        expenses: Money(500),
        byExpenseCategory: {ExpenseCategory.rent: Money(500)},
      ),
    );
    expect(exp, {'expenses': 500, 'byExpenseCategory.RENT': 500});
  });

  group('forExpense', () {
    Expense e(
      int amount, {
      String date = '2026-09-10',
      String loc = 'PTB',
      ExpenseCategory cat = ExpenseCategory.rent,
    }) => Expense(
      id: 'E1',
      locationId: loc,
      category: cat,
      amount: Money(amount),
      date: date,
      note: '',
      createdBy: 'u1',
    );

    test('create', () {
      final d = SummaryDeltas.forExpense(after: e(1000)).single;
      expect(d.locationId, 'PTB');
      expect(d.monthKey, '2026-09');
      expect(d.delta.expenses, const Money(1000));
      expect(d.delta.byExpenseCategory, {
        ExpenseCategory.rent: const Money(1000),
      });
    });

    test('edit in the same month increments by new − old', () {
      final d = SummaryDeltas.forExpense(
        before: e(1000),
        after: e(1500),
      ).single;
      expect(d.delta.expenses, const Money(500));
    });

    test('changing category moves the amount', () {
      final d = SummaryDeltas.forExpense(
        before: e(1000),
        after: e(1000, cat: ExpenseCategory.salary),
      ).single;
      expect(d.delta.expenses, Money.zero);
      expect(d.delta.byExpenseCategory, {
        ExpenseCategory.rent: const Money(-1000),
        ExpenseCategory.salary: const Money(1000),
      });
    });

    test('moving to another month or location touches both docs', () {
      final d = SummaryDeltas.forExpense(
        before: e(1000),
        after: e(1000, date: '2026-10-01', loc: 'MNJ'),
      );
      expect(
        d.map((x) => '${x.locationId} ${x.monthKey} ${x.delta.expenses.paise}'),
        ['PTB 2026-09 -1000', 'MNJ 2026-10 1000'],
      );
    });
  });

  test('Summary maths: netRevenue, profit and combining', () {
    const a = Summary(
      netSales: Money(10000),
      returns: Money(1000),
      cancelled: Money(2000),
      expenses: Money(3000),
      byProduct: {'X': ProductTally(qty: 1, amount: Money(10000))},
    );
    expect(a.netRevenue, const Money(7000));
    expect(a.profit, const Money(4000));
    final both = a + a;
    expect(both.netSales, const Money(20000));
    expect(both.byProduct['X']!.qty, 2);
    expect(-ProductTally.zero, isA<ProductTally>());
  });

  test('property: the summary equals the sum of the docs (QA-5)', () {
    final rnd = Random(99);
    for (var run = 0; run < 300; run++) {
      var summary = const Summary();
      var expectedNet = Money.zero;
      final modeTotals = <PaymentMode, Money>{};
      for (var i = 0; i < 20; i++) {
        final cart = [
          for (var j = 0; j < 1 + rnd.nextInt(4); j++)
            line(
              'P${rnd.nextInt(3)}$j',
              1 + rnd.nextInt(4),
              rnd.nextInt(60000),
            ),
        ];
        final t = BillCalculator.compute(
          cart,
          discount: DiscountInput.percent(rnd.nextInt(30)),
        );
        final mode = PaymentMode.values[rnd.nextInt(PaymentMode.values.length)];
        var b = billFrom(
          t,
          payments: [Payment(mode: mode, amount: t.total)],
        );
        summary += SummaryDeltas.forBill(b);
        expectedNet += b.total;
        modeTotals[mode] = (modeTotals[mode] ?? Money.zero) + b.total;

        switch (rnd.nextInt(3)) {
          case 0:
            summary += SummaryDeltas.forCancel(b);
            expectedNet -= b.total;
            modeTotals[mode] = modeTotals[mode]! - b.total;
          case 1:
            final pick = {b.lines.first.productId: 1};
            final r = ReturnCalculator.compute(b, pick);
            summary += SummaryDeltas.forReturn(
              SaleReturn(
                id: 'R',
                billId: b.id,
                billNo: b.billNo,
                lines: r.lines,
                refundTotal: r.refundTotal,
                refunds: [Payment(mode: mode, amount: r.refundTotal)],
                reason: '',
                businessDate: b.businessDate,
                createdBy: 'u1',
                deviceId: 'D01',
                clientCreatedAt: t0,
              ),
            );
            expectedNet -= r.refundTotal;
            modeTotals[mode] = modeTotals[mode]! - r.refundTotal;
            b = withReturned(b, pick);
        }
      }
      expect(summary.netRevenue, expectedNet);
      for (final m in PaymentMode.values) {
        expect(summary.byMode[m] ?? Money.zero, modeTotals[m] ?? Money.zero);
      }
      final byModeSum = summary.byMode.values.fold(Money.zero, (a, x) => a + x);
      expect(byModeSum, summary.netRevenue);
    }
  });
}
