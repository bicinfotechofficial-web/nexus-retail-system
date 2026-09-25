import 'enums.dart';
import 'models/sales.dart';
import 'money.dart';

/// One product line in the cart, before any totals are worked out.
final class CartLine {
  const CartLine({
    required this.productId,
    required this.name,
    required this.qty,
    required this.unitPrice,
  });

  final String productId;
  final String name;
  final int qty;
  final Money unitPrice;
}

/// The discount the Store Manager entered (D-011).
final class DiscountInput {
  /// A flat amount off the bill.
  DiscountInput.flat(Money amount)
    : type = DiscountType.flat,
      value = amount.paise;

  /// A whole percentage off the bill.
  const DiscountInput.percent(int percent)
    : type = DiscountType.pct,
      value = percent;

  final DiscountType type;

  /// Paise for FLAT, a whole percentage for PCT.
  final int value;
}

/// Everything on a bill that follows from the cart and the discount.
final class BillTotals {
  const BillTotals({
    required this.lines,
    required this.subtotal,
    required this.discount,
    required this.taxableValue,
    required this.taxLines,
    required this.roundOff,
    required this.total,
  });

  final List<BillLine> lines;
  final Money subtotal;

  /// Null when there is no discount or it works out to zero.
  final Discount? discount;
  final Money taxableValue;

  /// Always empty in the MVP (D-013).
  final List<TaxLine> taxLines;
  final Money roundOff;
  final Money total;
}

enum BillError {
  emptyCart,
  nonPositiveQty,
  negativePrice,
  duplicateProduct,
  negativeDiscount,
  percentOver100,
  discountExceedsSubtotal,
  discountOverCap,
}

enum PaymentError {
  /// The total is above zero but no payment was entered.
  noPayments,

  /// More than [BillCalculator.maxPayments] entries.
  tooManyPayments,

  /// A payment of zero or less.
  nonPositiveAmount,

  /// The payments don't add up to the total.
  sumMismatch,

  /// Cash tendered was entered but there is no CASH payment.
  tenderedWithoutCash,

  /// Cash tendered is less than the CASH payment.
  tenderedTooLow,
}

final class BillValidationException implements Exception {
  const BillValidationException(this.error, this.detail);

  final BillError error;
  final String detail;

  @override
  String toString() => 'BillValidationException(${error.name}): $detail';
}

/// The result of checking a payment split. The payment screen shows
/// [remaining] and [change] live, and enables Save only when [isValid].
final class PaymentCheck {
  const PaymentCheck({
    required this.errors,
    required this.paid,
    required this.remaining,
    required this.change,
  });

  final Set<PaymentError> errors;

  /// Σ payments.
  final Money paid;

  /// total − paid. Negative when overpaid.
  final Money remaining;

  /// cashTendered − the CASH payments, or null when no cash was tendered.
  final Money? change;

  bool get isValid => errors.isEmpty;
}

/// Bill arithmetic: subtotal, discount, round-off and payment validation
/// (D-010, D-011, D-024). Pure functions; the same inputs always give the
/// same bill.
abstract final class BillCalculator {
  /// At most 4 payment entries per bill (04-PERMISSIONS #6).
  static const int maxPayments = 4;

  /// Works out every total for [cart].
  ///
  /// [maxDiscountPct] is the location's cap, or null for no cap. The cap
  /// applies to flat discounts too, measured as a share of the subtotal.
  ///
  /// Throws [BillValidationException] when the cart or discount is invalid.
  static BillTotals compute(
    List<CartLine> cart, {
    DiscountInput? discount,
    int? maxDiscountPct,
  }) {
    if (cart.isEmpty) {
      throw const BillValidationException(BillError.emptyCart, 'no lines');
    }
    final seen = <String>{};
    final lines = <BillLine>[];
    var subtotal = Money.zero;
    for (final c in cart) {
      if (c.qty <= 0) {
        throw BillValidationException(
          BillError.nonPositiveQty,
          '${c.productId}: qty ${c.qty}',
        );
      }
      if (c.unitPrice.isNegative) {
        throw BillValidationException(
          BillError.negativePrice,
          '${c.productId}: price ${c.unitPrice.paise}',
        );
      }
      // returnedQty is keyed by productId, so each product appears once.
      if (!seen.add(c.productId)) {
        throw BillValidationException(BillError.duplicateProduct, c.productId);
      }
      final lineTotal = c.unitPrice.times(c.qty);
      lines.add(
        BillLine(
          productId: c.productId,
          name: c.name,
          qty: c.qty,
          unitPrice: c.unitPrice,
          lineTotal: lineTotal,
        ),
      );
      subtotal += lineTotal;
    }

    final applied = _discount(subtotal, discount, maxDiscountPct);
    final taxable = subtotal - (applied?.amount ?? Money.zero);
    // No GST in the MVP (D-013): the pre-round total is the taxable value.
    final total = taxable.roundToRupee();
    return BillTotals(
      lines: List.unmodifiable(lines),
      subtotal: subtotal,
      discount: applied,
      taxableValue: taxable,
      taxLines: const [],
      roundOff: total - taxable,
      total: total,
    );
  }

  static Discount? _discount(Money subtotal, DiscountInput? d, int? cap) {
    if (d == null) return null;
    if (d.value < 0) {
      throw BillValidationException(
        BillError.negativeDiscount,
        'value ${d.value}',
      );
    }
    final Money amount;
    switch (d.type) {
      case DiscountType.pct:
        if (d.value > 100) {
          throw BillValidationException(
            BillError.percentOver100,
            '${d.value}%',
          );
        }
        amount = Money(divideRounded(subtotal.paise * d.value, 100));
      case DiscountType.flat:
        amount = Money(d.value);
        if (amount > subtotal) {
          throw BillValidationException(
            BillError.discountExceedsSubtotal,
            '${amount.paise} > ${subtotal.paise}',
          );
        }
    }
    if (amount.isZero) return null;
    if (cap != null && amount.paise * 100 > cap * subtotal.paise) {
      throw BillValidationException(
        BillError.discountOverCap,
        '${amount.paise} of ${subtotal.paise} is over $cap%',
      );
    }
    return Discount(type: d.type, value: d.value, amount: amount);
  }

  /// Checks a payment split against [total].
  static PaymentCheck checkPayments(
    Money total,
    List<Payment> payments, {
    Money? cashTendered,
  }) {
    final errors = <PaymentError>{};
    if (payments.isEmpty && total.isPositive) {
      errors.add(PaymentError.noPayments);
    }
    if (payments.length > maxPayments) errors.add(PaymentError.tooManyPayments);
    var paid = Money.zero;
    var cash = Money.zero;
    for (final p in payments) {
      if (!p.amount.isPositive) errors.add(PaymentError.nonPositiveAmount);
      paid += p.amount;
      if (p.mode == PaymentMode.cash) cash += p.amount;
    }
    if (paid != total) errors.add(PaymentError.sumMismatch);

    Money? change;
    if (cashTendered != null) {
      if (cash.isZero) {
        errors.add(PaymentError.tenderedWithoutCash);
      } else if (cashTendered < cash) {
        errors.add(PaymentError.tenderedTooLow);
      } else {
        change = cashTendered - cash;
      }
    }
    return PaymentCheck(
      errors: errors,
      paid: paid,
      remaining: total - paid,
      change: change,
    );
  }

  /// Splits [net] across lines in proportion to [lineTotals], so that the
  /// parts add up to [net] exactly (largest remainder; ties go to the
  /// earlier line). Used for per-product sales and return proration
  /// (D-024).
  static List<Money> allocate(List<Money> lineTotals, Money net) {
    final sum = lineTotals.fold<int>(0, (a, m) => a + m.paise);
    if (sum == 0) {
      if (!net.isZero) {
        throw ArgumentError('cannot allocate ${net.paise} over zero weights');
      }
      return List.filled(lineTotals.length, Money.zero);
    }
    if (net.isNegative) throw ArgumentError.value(net.paise, 'net');
    final base = <int>[];
    final remainders = <int>[];
    var allocated = 0;
    for (final t in lineTotals) {
      if (t.isNegative) throw ArgumentError.value(t.paise, 'lineTotals');
      final product = t.paise * net.paise;
      base.add(product ~/ sum);
      remainders.add(product % sum);
      allocated += product ~/ sum;
    }
    final order = List.generate(lineTotals.length, (i) => i)
      ..sort((a, b) {
        final byRemainder = remainders[b].compareTo(remainders[a]);
        return byRemainder != 0 ? byRemainder : a.compareTo(b);
      });
    for (var k = 0; k < net.paise - allocated; k++) {
      base[order[k]]++;
    }
    return [for (final b in base) Money(b)];
  }

  /// The bill's net amount (after discount and tax, before round-off) split
  /// across its lines. Index-aligned with `bill.lines`.
  static List<Money> lineNetAmounts(Bill bill) => allocate([
    for (final l in bill.lines) l.lineTotal,
  ], bill.total - bill.roundOff);
}

enum CancelBlocker {
  /// Already cancelled.
  notCompleted,

  /// Cancellation is same-day only; later, use a return (D-009).
  differentDay,

  /// A bill with returns can't be cancelled (D-025).
  hasReturns,
}

/// Whether a bill can still be cancelled on [today] (a business date).
/// Returns null when it can.
CancelBlocker? cancelBlocker(Bill bill, String today) {
  if (bill.status != BillStatus.completed) return CancelBlocker.notCompleted;
  if (bill.businessDate != today) return CancelBlocker.differentDay;
  if (bill.returnedQty.values.any((q) => q > 0)) {
    return CancelBlocker.hasReturns;
  }
  return null;
}
