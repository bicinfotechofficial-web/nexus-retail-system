import 'dart:math';

import 'package:nexus_core/nexus_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

Matcher throwsBill(BillError e) =>
    throwsA(isA<BillValidationException>().having((x) => x.error, 'error', e));

void main() {
  group('compute', () {
    test('plain bill: subtotal, no discount, no round-off', () {
      final t = BillCalculator.compute([
        line('A', 2, 45000),
        line('B', 1, 12000),
      ]);
      expect(t.subtotal, const Money(102000));
      expect(t.discount, isNull);
      expect(t.taxableValue, const Money(102000));
      expect(t.taxLines, isEmpty);
      expect(t.roundOff, Money.zero);
      expect(t.total, const Money(102000));
      expect(t.lines.map((l) => l.lineTotal), [
        const Money(90000),
        const Money(12000),
      ]);
    });

    test('round-off: 49 paise rounds down, 50 paise rounds up (D-010)', () {
      final down = BillCalculator.compute([line('A', 1, 10049)]);
      expect(down.roundOff, const Money(-49));
      expect(down.total, const Money(10000));

      final up = BillCalculator.compute([line('A', 1, 10050)]);
      expect(up.roundOff, const Money(50));
      expect(up.total, const Money(10100));

      final justUp = BillCalculator.compute([line('A', 1, 10051)]);
      expect(justUp.roundOff, const Money(49));
      expect(justUp.total, const Money(10100));
    });

    test('percentage discount rounds half up to the paise', () {
      // 10% of ₹3.35 = 33.5 paise → 34.
      final t = BillCalculator.compute([
        line('A', 1, 335),
      ], discount: const DiscountInput.percent(10));
      expect(t.discount!.amount, const Money(34));
      expect(t.discount!.type, DiscountType.pct);
      expect(t.discount!.value, 10);
      expect(t.taxableValue, const Money(301));
      expect(t.total, const Money(300));
      expect(t.roundOff, const Money(-1));

      // 10% of ₹3.34 = 33.4 paise → 33.
      final t2 = BillCalculator.compute([
        line('A', 1, 334),
      ], discount: const DiscountInput.percent(10));
      expect(t2.discount!.amount, const Money(33));
    });

    test('flat discount', () {
      final t = BillCalculator.compute([
        line('A', 1, 50000),
      ], discount: DiscountInput.flat(const Money(2550)));
      expect(t.discount!.amount, const Money(2550));
      expect(t.discount!.value, 2550);
      expect(t.taxableValue, const Money(47450));
      expect(t.total, const Money(47500));
      expect(t.roundOff, const Money(50));
    });

    test('100% and full flat discount give a zero bill', () {
      final pct = BillCalculator.compute([
        line('A', 1, 999),
      ], discount: const DiscountInput.percent(100));
      expect(pct.total, Money.zero);
      final flat = BillCalculator.compute([
        line('A', 1, 999),
      ], discount: DiscountInput.flat(const Money(999)));
      expect(flat.total, Money.zero);
      expect(flat.roundOff, Money.zero);
    });

    test('a discount that works out to zero is dropped', () {
      expect(
        BillCalculator.compute([
          line('A', 1, 4),
        ], discount: const DiscountInput.percent(10)).discount,
        isNull,
      );
      expect(
        BillCalculator.compute([
          line('A', 1, 400),
        ], discount: DiscountInput.flat(Money.zero)).discount,
        isNull,
      );
    });

    group('cap (maxDiscountPct)', () {
      final cart = [line('A', 1, 100000)];
      test('exactly at the cap is allowed', () {
        expect(
          BillCalculator.compute(
            cart,
            discount: const DiscountInput.percent(10),
            maxDiscountPct: 10,
          ).discount!.amount,
          const Money(10000),
        );
        expect(
          BillCalculator.compute(
            cart,
            discount: DiscountInput.flat(const Money(10000)),
            maxDiscountPct: 10,
          ).total,
          const Money(90000),
        );
      });
      test('one paisa over the cap is refused, flat or percent', () {
        expect(
          () => BillCalculator.compute(
            cart,
            discount: DiscountInput.flat(const Money(10001)),
            maxDiscountPct: 10,
          ),
          throwsBill(BillError.discountOverCap),
        );
        expect(
          () => BillCalculator.compute(
            cart,
            discount: const DiscountInput.percent(11),
            maxDiscountPct: 10,
          ),
          throwsBill(BillError.discountOverCap),
        );
      });
      test('a cap of 0 refuses any discount', () {
        expect(
          () => BillCalculator.compute(
            cart,
            discount: DiscountInput.flat(const Money(1)),
            maxDiscountPct: 0,
          ),
          throwsBill(BillError.discountOverCap),
        );
      });
      test('no cap by default', () {
        expect(
          BillCalculator.compute(
            cart,
            discount: const DiscountInput.percent(90),
          ).total,
          const Money(10000),
        );
      });
    });

    group('invalid carts', () {
      test('empty', () {
        expect(
          () => BillCalculator.compute([]),
          throwsBill(BillError.emptyCart),
        );
      });
      test('zero or negative qty', () {
        expect(
          () => BillCalculator.compute([line('A', 0, 100)]),
          throwsBill(BillError.nonPositiveQty),
        );
        expect(
          () => BillCalculator.compute([line('A', -1, 100)]),
          throwsBill(BillError.nonPositiveQty),
        );
      });
      test('negative price', () {
        expect(
          () => BillCalculator.compute([line('A', 1, -1)]),
          throwsBill(BillError.negativePrice),
        );
      });
      test('the same product twice', () {
        expect(
          () => BillCalculator.compute([line('A', 1, 100), line('A', 2, 100)]),
          throwsBill(BillError.duplicateProduct),
        );
      });
      test('negative discount', () {
        expect(
          () => BillCalculator.compute([
            line('A', 1, 100),
          ], discount: const DiscountInput.percent(-1)),
          throwsBill(BillError.negativeDiscount),
        );
      });
      test('over 100%', () {
        expect(
          () => BillCalculator.compute([
            line('A', 1, 100),
          ], discount: const DiscountInput.percent(101)),
          throwsBill(BillError.percentOver100),
        );
      });
      test('flat discount above the subtotal', () {
        expect(
          () => BillCalculator.compute([
            line('A', 1, 100),
          ], discount: DiscountInput.flat(const Money(101))),
          throwsBill(BillError.discountExceedsSubtotal),
        );
      });
      test('the exception names the problem', () {
        expect(
          const BillValidationException(BillError.emptyCart, 'x').toString(),
          contains('emptyCart'),
        );
      });
    });

    test('property: every random bill is internally consistent', () {
      final rnd = Random(42);
      for (var i = 0; i < 5000; i++) {
        final n = 1 + rnd.nextInt(6);
        final cart = [
          for (var j = 0; j < n; j++)
            line('P$j', 1 + rnd.nextInt(5), rnd.nextInt(200000)),
        ];
        final subtotal = cart.fold(0, (a, c) => a + c.qty * c.unitPrice.paise);
        DiscountInput? d;
        switch (rnd.nextInt(3)) {
          case 0:
            d = DiscountInput.percent(rnd.nextInt(101));
          case 1:
            d = DiscountInput.flat(Money(rnd.nextInt(subtotal + 1)));
        }
        final t = BillCalculator.compute(cart, discount: d);
        expect(t.subtotal.paise, subtotal);
        expect(t.taxableValue, t.subtotal - (t.discount?.amount ?? Money.zero));
        expect(t.total.isWholeRupees, isTrue);
        expect(t.total, t.taxableValue + t.roundOff);
        expect(t.roundOff.paise, inInclusiveRange(-49, 50));
        expect(t.total.isNegative, isFalse);
        expect(t.lines.fold(Money.zero, (a, l) => a + l.lineTotal), t.subtotal);
      }
    });
  });

  group('checkPayments', () {
    const total = Money(50000);
    Payment p(PaymentMode m, int paise) =>
        Payment(mode: m, amount: Money(paise));

    test('exact single payment', () {
      final c = BillCalculator.checkPayments(total, [
        p(PaymentMode.upi, 50000),
      ]);
      expect(c.isValid, isTrue);
      expect(c.paid, total);
      expect(c.remaining, Money.zero);
      expect(c.change, isNull);
    });

    test('split with cash tendered gives change', () {
      final c = BillCalculator.checkPayments(total, [
        p(PaymentMode.cash, 20000),
        p(PaymentMode.upi, 30000),
      ], cashTendered: const Money(50000));
      expect(c.isValid, isTrue);
      expect(c.change, const Money(30000));
    });

    test('tendered exactly the cash part gives zero change', () {
      final c = BillCalculator.checkPayments(total, [
        p(PaymentMode.cash, 50000),
      ], cashTendered: total);
      expect(c.change, Money.zero);
    });

    test('sum mismatch shows what is left, both ways', () {
      final under = BillCalculator.checkPayments(total, [
        p(PaymentMode.cash, 40000),
      ]);
      expect(under.errors, {PaymentError.sumMismatch});
      expect(under.remaining, const Money(10000));
      final over = BillCalculator.checkPayments(total, [
        p(PaymentMode.cash, 60000),
      ]);
      expect(over.remaining, const Money(-10000));
    });

    test('no payments for a non-zero total', () {
      expect(BillCalculator.checkPayments(total, []).errors, {
        PaymentError.noPayments,
        PaymentError.sumMismatch,
      });
    });

    test('a zero bill needs no payment', () {
      expect(BillCalculator.checkPayments(Money.zero, []).isValid, isTrue);
    });

    test('at most 4 payments', () {
      final four = List.generate(4, (_) => p(PaymentMode.card, 12500));
      expect(BillCalculator.checkPayments(total, four).isValid, isTrue);
      final five = List.generate(5, (_) => p(PaymentMode.card, 10000));
      expect(
        BillCalculator.checkPayments(total, five).errors,
        contains(PaymentError.tooManyPayments),
      );
    });

    test('zero or negative amounts', () {
      expect(
        BillCalculator.checkPayments(total, [
          p(PaymentMode.cash, 50000),
          p(PaymentMode.upi, 0),
        ]).errors,
        {PaymentError.nonPositiveAmount},
      );
    });

    test('tendered without cash, and tendered too low', () {
      expect(
        BillCalculator.checkPayments(total, [
          p(PaymentMode.upi, 50000),
        ], cashTendered: total).errors,
        {PaymentError.tenderedWithoutCash},
      );
      final low = BillCalculator.checkPayments(total, [
        p(PaymentMode.cash, 50000),
      ], cashTendered: const Money(49999));
      expect(low.errors, {PaymentError.tenderedTooLow});
      expect(low.change, isNull);
    });
  });

  group('allocate', () {
    test('parts add up exactly and ties go to the earlier line', () {
      // ₹1.00 over three equal lines: 34 + 33 + 33.
      expect(
        BillCalculator.allocate([
          const Money(100),
          const Money(100),
          const Money(100),
        ], const Money(100)),
        [const Money(34), const Money(33), const Money(33)],
      );
    });

    test('the largest remainder gets the spare paisa', () {
      // 90/100 and 10/100 of 99 paise: 89.1 and 9.9 → 89 and 10.
      expect(
        BillCalculator.allocate([
          const Money(90),
          const Money(10),
        ], const Money(99)),
        [const Money(89), const Money(10)],
      );
    });

    test('zero weights', () {
      expect(BillCalculator.allocate([Money.zero, Money.zero], Money.zero), [
        Money.zero,
        Money.zero,
      ]);
      expect(
        () => BillCalculator.allocate([Money.zero], const Money(1)),
        throwsArgumentError,
      );
    });

    test('rejects negative inputs', () {
      expect(
        () => BillCalculator.allocate([const Money(1)], const Money(-1)),
        throwsArgumentError,
      );
      expect(
        () => BillCalculator.allocate([
          const Money(-1),
          const Money(2),
        ], const Money(1)),
        throwsArgumentError,
      );
    });

    test('property: exact sum, each part within 1 paisa of its share', () {
      final rnd = Random(7);
      for (var i = 0; i < 5000; i++) {
        final weights = [
          for (var j = 0; j < 1 + rnd.nextInt(8); j++)
            Money(rnd.nextInt(100000)),
        ];
        final sum = weights.fold(0, (a, m) => a + m.paise);
        if (sum == 0) continue;
        final net = Money(rnd.nextInt(sum + 1));
        final parts = BillCalculator.allocate(weights, net);
        expect(parts.fold(0, (a, m) => a + m.paise), net.paise);
        for (var j = 0; j < weights.length; j++) {
          final exact = weights[j].paise * net.paise / sum;
          expect((parts[j].paise - exact).abs(), lessThan(1));
        }
      }
    });
  });

  group('cancelBlocker (D-009, D-025)', () {
    final bill = billFrom(BillCalculator.compute([line('A', 2, 10000)]));
    test('same day, completed, no returns: allowed', () {
      expect(cancelBlocker(bill, '2026-09-25'), isNull);
    });
    test('next day: blocked', () {
      expect(cancelBlocker(bill, '2026-09-26'), CancelBlocker.differentDay);
    });
    test('already cancelled: blocked', () {
      final c = billFrom(
        BillCalculator.compute([line('A', 1, 100)]),
        status: BillStatus.cancelled,
      );
      expect(cancelBlocker(c, '2026-09-25'), CancelBlocker.notCompleted);
    });
    test('has returns: blocked', () {
      expect(
        cancelBlocker(withReturned(bill, {'A': 1}), '2026-09-25'),
        CancelBlocker.hasReturns,
      );
    });
  });
}
