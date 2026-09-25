import 'bill_calculator.dart';
import 'enums.dart';
import 'limits.dart';
import 'models/sales.dart';
import 'money.dart';

/// The lines and refund total of one return.
final class ReturnTotals {
  const ReturnTotals({required this.lines, required this.refundTotal});

  final List<ReturnLine> lines;

  /// Whole rupees.
  final Money refundTotal;
}

enum ReturnError {
  /// Cancelled bills can't be returned against.
  billNotCompleted,
  emptyReturn,
  nonPositiveQty,
  productNotOnBill,

  /// More than sold minus already returned.
  exceedsReturnable,
}

enum RefundError { noRefunds, tooManyRefunds, nonPositiveAmount, sumMismatch }

final class ReturnValidationException implements Exception {
  const ReturnValidationException(this.error, this.detail);

  final ReturnError error;
  final String detail;

  @override
  String toString() => 'ReturnValidationException(${error.name}): $detail';
}

/// Return arithmetic (D-012, D-024).
///
/// Amounts are **cumulative**: a line's refund is the value of everything
/// returned so far minus the value returned before, and the same for the
/// rupee-rounded refund total. So however a bill is returned, in one go or
/// in parts, the refunds add up to exactly the bill total and never more.
abstract final class ReturnCalculator {
  /// Sold minus already returned, for [productId]; 0 when not on the bill.
  static int maxReturnable(Bill bill, String productId) {
    for (final l in bill.lines) {
      if (l.productId == productId) {
        return l.qty - (bill.returnedQty[productId] ?? 0);
      }
    }
    return 0;
  }

  /// productId → qty that can still be returned, for every bill line.
  static Map<String, int> returnable(Bill bill) => {
    for (final l in bill.lines) l.productId: maxReturnable(bill, l.productId),
  };

  /// Works out a return of [qtyByProduct] against [bill].
  ///
  /// Throws [ReturnValidationException] when the return isn't allowed.
  static ReturnTotals compute(Bill bill, Map<String, int> qtyByProduct) {
    if (bill.status != BillStatus.completed) {
      throw ReturnValidationException(ReturnError.billNotCompleted, bill.id);
    }
    final wanted = {
      for (final e in qtyByProduct.entries)
        if (e.value != 0) e.key: e.value,
    };
    if (wanted.isEmpty) {
      throw const ReturnValidationException(ReturnError.emptyReturn, '');
    }
    final onBill = {for (final l in bill.lines) l.productId};
    for (final e in wanted.entries) {
      if (e.value < 0) {
        throw ReturnValidationException(
          ReturnError.nonPositiveQty,
          '${e.key}: ${e.value}',
        );
      }
      if (!onBill.contains(e.key)) {
        throw ReturnValidationException(ReturnError.productNotOnBill, e.key);
      }
      final max = maxReturnable(bill, e.key);
      if (e.value > max) {
        throw ReturnValidationException(
          ReturnError.exceedsReturnable,
          '${e.key}: ${e.value} > $max',
        );
      }
    }

    final nets = BillCalculator.lineNetAmounts(bill);
    final lines = <ReturnLine>[];
    var valueBefore = 0;
    var valueAfter = 0;
    for (var i = 0; i < bill.lines.length; i++) {
      final line = bill.lines[i];
      final before = bill.returnedQty[line.productId] ?? 0;
      final qty = wanted[line.productId] ?? 0;
      final valBefore = _valueOf(nets[i], before, line.qty);
      final valAfter = _valueOf(nets[i], before + qty, line.qty);
      valueBefore += valBefore;
      valueAfter += valAfter;
      if (qty > 0) {
        lines.add(
          ReturnLine(
            productId: line.productId,
            name: line.name,
            qty: qty,
            amount: Money(valAfter - valBefore),
          ),
        );
      }
    }
    final refund =
        Money(valueAfter).roundToRupee() - Money(valueBefore).roundToRupee();
    return ReturnTotals(lines: List.unmodifiable(lines), refundTotal: refund);
  }

  /// The value of [returned] of [sold] units of a line whose net share of
  /// the bill is [lineNet], rounded to the paise.
  static int _valueOf(Money lineNet, int returned, int sold) => returned == sold
      ? lineNet.paise
      : divideRounded(lineNet.paise * returned, sold);

  /// Checks a refund split against [refundTotal]. Any mix of modes is
  /// allowed (BRD §4.6).
  static Set<RefundError> checkRefunds(
    Money refundTotal,
    List<Payment> refunds,
  ) {
    final errors = <RefundError>{};
    if (refunds.isEmpty && refundTotal.isPositive) {
      errors.add(RefundError.noRefunds);
    }
    if (refunds.length > Limits.maxRefunds) {
      errors.add(RefundError.tooManyRefunds);
    }
    var sum = Money.zero;
    for (final r in refunds) {
      if (!r.amount.isPositive) errors.add(RefundError.nonPositiveAmount);
      sum += r.amount;
    }
    if (sum != refundTotal) errors.add(RefundError.sumMismatch);
    return errors;
  }
}
