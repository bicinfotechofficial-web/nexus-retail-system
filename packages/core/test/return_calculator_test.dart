import 'dart:math';

import 'package:nexus_core/nexus_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

Matcher throwsReturn(ReturnError e) => throwsA(
  isA<ReturnValidationException>().having((x) => x.error, 'error', e),
);

void main() {
  // ₹450 × 2 + ₹120 = ₹1,020, 10% off → ₹918.
  final bill = billFrom(
    BillCalculator.compute([
      line('BF', 2, 45000),
      line('CUP', 1, 12000),
    ], discount: const DiscountInput.percent(10)),
  );

  group('maxReturnable', () {
    test('sold minus already returned', () {
      expect(ReturnCalculator.maxReturnable(bill, 'BF'), 2);
      expect(
        ReturnCalculator.maxReturnable(withReturned(bill, {'BF': 1}), 'BF'),
        1,
      );
      expect(ReturnCalculator.maxReturnable(bill, 'NOPE'), 0);
      expect(ReturnCalculator.returnable(withReturned(bill, {'CUP': 1})), {
        'BF': 2,
        'CUP': 0,
      });
    });
  });

  group('compute', () {
    test('full return refunds exactly the bill total', () {
      final r = ReturnCalculator.compute(bill, {'BF': 2, 'CUP': 1});
      expect(r.refundTotal, bill.total);
      expect(
        r.lines.fold(Money.zero, (a, l) => a + l.amount),
        const Money(91800),
      );
    });

    test('one unit is prorated by the discount', () {
      final r = ReturnCalculator.compute(bill, {'BF': 1});
      expect(r.lines.single.qty, 1);
      expect(r.lines.single.name, 'Item BF');
      expect(r.lines.single.amount, const Money(40500)); // ₹450 less 10%
      expect(r.refundTotal, const Money(40500));
    });

    test('parts add up to the whole, whatever the order', () {
      final first = ReturnCalculator.compute(bill, {'BF': 1});
      final b2 = withReturned(bill, {'BF': 1});
      final second = ReturnCalculator.compute(b2, {'CUP': 1});
      final b3 = withReturned(b2, {'CUP': 1});
      final third = ReturnCalculator.compute(b3, {'BF': 1});
      expect(
        first.refundTotal + second.refundTotal + third.refundTotal,
        bill.total,
      );
    });

    test('rupee rounding never over-refunds across partial returns', () {
      // ₹1.49 × 3 = ₹4.47, billed at ₹4. Rounding each one-unit return on
      // its own would refund ₹1 + ₹1 + ₹1 = ₹3; the cumulative method gives
      // ₹1 + ₹2 + ₹1 = ₹4.
      final b = billFrom(BillCalculator.compute([line('X', 3, 149)]));
      expect(b.total, const Money(400));
      var current = b;
      var refunded = Money.zero;
      for (var i = 0; i < 3; i++) {
        final r = ReturnCalculator.compute(current, {'X': 1});
        refunded += r.refundTotal;
        expect(r.refundTotal.isWholeRupees, isTrue);
        current = withReturned(current, {'X': 1});
      }
      expect(refunded, b.total);
    });

    test('zero quantities are ignored', () {
      final r = ReturnCalculator.compute(bill, {'BF': 1, 'CUP': 0});
      expect(r.lines.map((l) => l.productId), ['BF']);
    });

    test('a zero-value bill refunds nothing', () {
      final free = billFrom(
        BillCalculator.compute([line('F', 2, 0)]),
        payments: const [],
      );
      final r = ReturnCalculator.compute(free, {'F': 2});
      expect(r.refundTotal, Money.zero);
      expect(r.lines.single.amount, Money.zero);
    });

    group('refused', () {
      test('cancelled bill', () {
        final c = billFrom(
          BillCalculator.compute([line('A', 1, 100)]),
          status: BillStatus.cancelled,
        );
        expect(
          () => ReturnCalculator.compute(c, {'A': 1}),
          throwsReturn(ReturnError.billNotCompleted),
        );
      });
      test('nothing to return', () {
        expect(
          () => ReturnCalculator.compute(bill, {}),
          throwsReturn(ReturnError.emptyReturn),
        );
        expect(
          () => ReturnCalculator.compute(bill, {'BF': 0}),
          throwsReturn(ReturnError.emptyReturn),
        );
      });
      test('negative qty', () {
        expect(
          () => ReturnCalculator.compute(bill, {'BF': -1}),
          throwsReturn(ReturnError.nonPositiveQty),
        );
      });
      test('product not on the bill', () {
        expect(
          () => ReturnCalculator.compute(bill, {'NOPE': 1}),
          throwsReturn(ReturnError.productNotOnBill),
        );
      });
      test('more than sold, or than is left', () {
        expect(
          () => ReturnCalculator.compute(bill, {'BF': 3}),
          throwsReturn(ReturnError.exceedsReturnable),
        );
        expect(
          () => ReturnCalculator.compute(withReturned(bill, {'BF': 2}), {
            'BF': 1,
          }),
          throwsReturn(ReturnError.exceedsReturnable),
        );
      });
      test('the exception names the problem', () {
        expect(
          const ReturnValidationException(
            ReturnError.emptyReturn,
            '',
          ).toString(),
          contains('emptyReturn'),
        );
      });
    });

    test('property: any sequence of partial returns refunds exactly the '
        'total, and never more along the way', () {
      final rnd = Random(2026);
      for (var i = 0; i < 3000; i++) {
        final n = 1 + rnd.nextInt(5);
        final cart = [
          for (var j = 0; j < n; j++)
            line('P$j', 1 + rnd.nextInt(6), rnd.nextInt(80000)),
        ];
        final subtotal = cart.fold(0, (a, c) => a + c.qty * c.unitPrice.paise);
        final d = rnd.nextBool()
            ? DiscountInput.percent(rnd.nextInt(60))
            : DiscountInput.flat(Money(rnd.nextInt(subtotal ~/ 2 + 1)));
        var current = billFrom(BillCalculator.compute(cart, discount: d));
        final original = current;
        var refunded = Money.zero;
        var lineAmounts = Money.zero;
        while (ReturnCalculator.returnable(current).values.any((q) => q > 0)) {
          final left = ReturnCalculator.returnable(current);
          final pick = <String, int>{
            for (final e in left.entries)
              if (e.value > 0 && rnd.nextBool())
                e.key: 1 + rnd.nextInt(e.value),
          };
          if (pick.isEmpty) continue;
          final r = ReturnCalculator.compute(current, pick);
          expect(r.refundTotal.isWholeRupees, isTrue);
          expect(r.refundTotal.isNegative, isFalse);
          refunded += r.refundTotal;
          lineAmounts += r.lines.fold(Money.zero, (a, l) => a + l.amount);
          expect(refunded <= original.total, isTrue);
          current = withReturned(current, pick);
        }
        expect(refunded, original.total);
        expect(lineAmounts, original.total - original.roundOff);
      }
    });
  });

  group('checkRefunds', () {
    Payment p(PaymentMode m, int paise) =>
        Payment(mode: m, amount: Money(paise));
    test('any mix that adds up', () {
      expect(
        ReturnCalculator.checkRefunds(const Money(40000), [
          p(PaymentMode.cash, 10000),
          p(PaymentMode.upi, 30000),
        ]),
        isEmpty,
      );
    });
    test('mismatch, missing and non-positive', () {
      expect(
        ReturnCalculator.checkRefunds(const Money(40000), [
          p(PaymentMode.cash, 1),
        ]),
        {RefundError.sumMismatch},
      );
      expect(ReturnCalculator.checkRefunds(const Money(100), []), {
        RefundError.noRefunds,
        RefundError.sumMismatch,
      });
      expect(
        ReturnCalculator.checkRefunds(const Money(100), [
          p(PaymentMode.cash, 100),
          p(PaymentMode.upi, 0),
        ]),
        {RefundError.nonPositiveAmount},
      );
      expect(ReturnCalculator.checkRefunds(Money.zero, []), isEmpty);
      expect(
        ReturnCalculator.checkRefunds(const Money(500), [
          for (var i = 0; i < 5; i++) p(PaymentMode.cash, 100),
        ]),
        {RefundError.tooManyRefunds},
      );
    });
  });
}
