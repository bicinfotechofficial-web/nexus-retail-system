import 'bill_calculator.dart';
import 'business_date.dart';
import 'enums.dart';
import 'models/admin.dart';
import 'models/sales.dart';
import 'models/summary.dart';
import 'money.dart';

/// The summary increments for each business operation (03-SYNC §2, D-014).
///
/// Each result is a [Summary] holding signed deltas. The same delta goes to
/// the daily and the monthly doc of the operation's business date; the data
/// package turns it into `FieldValue.increment` calls with
/// [SummaryDeltas.increments].
abstract final class SummaryDeltas {
  /// A new, completed bill.
  static Summary forBill(Bill bill) => Summary(
    billCount: 1,
    grossSales: bill.subtotal,
    discounts: bill.discountAmount,
    roundOff: bill.roundOff,
    netSales: bill.total,
    byMode: _byMode(bill.payments, 1),
    byProduct: _byProduct(bill, 1),
  );

  /// A same-day cancellation. `netSales` stays; `cancelled` records it, so
  /// net revenue = netSales − returns − cancelled.
  static Summary forCancel(Bill bill) => Summary(
    cancelCount: 1,
    cancelled: bill.total,
    byMode: _byMode(bill.payments, -1),
    byProduct: _byProduct(bill, -1),
  );

  /// A return, counted on the day it is processed (D-012).
  static Summary forReturn(SaleReturn ret) => Summary(
    returnCount: 1,
    returns: ret.refundTotal,
    byMode: _byMode(ret.refunds, -1),
    byProduct: {
      for (final l in ret.lines)
        l.productId: ProductTally(qty: -l.qty, amount: -l.amount),
    },
  );

  /// The monthly-summary increments for creating ([before] null) or editing
  /// an expense. An edit that moves the expense to another month or
  /// location gives two deltas.
  static List<ExpenseDelta> forExpense({
    required Expense after,
    Expense? before,
  }) {
    final deltas = <ExpenseDelta>[];
    if (before != null) deltas.add(_expense(before, -1));
    deltas.add(_expense(after, 1));
    // Merge deltas that land on the same monthly doc.
    final merged = <(String, String), Summary>{};
    for (final d in deltas) {
      final k = (d.locationId, d.monthKey);
      merged[k] = (merged[k] ?? const Summary()) + d.delta;
    }
    return [
      for (final e in merged.entries)
        ExpenseDelta(locationId: e.key.$1, monthKey: e.key.$2, delta: e.value),
    ];
  }

  static ExpenseDelta _expense(Expense e, int sign) => ExpenseDelta(
    locationId: e.locationId,
    monthKey: BusinessDate.monthOf(e.date),
    delta: Summary(
      expenses: e.amount.times(sign),
      byExpenseCategory: {e.category: e.amount.times(sign)},
    ),
  );

  /// Field-path → delta for `FieldValue.increment`, e.g.
  /// `{'billCount': 1, 'byMode.CASH': 50000, 'byProduct.P1.qty': 2}`.
  /// Zero deltas are left out, so an unchanged field isn't touched.
  static Map<String, int> increments(Summary d) {
    final out = <String, int>{};
    void put(String k, int v) {
      if (v != 0) out[k] = (out[k] ?? 0) + v;
    }

    put('billCount', d.billCount);
    put('cancelCount', d.cancelCount);
    put('returnCount', d.returnCount);
    put('grossSales', d.grossSales.paise);
    put('discounts', d.discounts.paise);
    put('roundOff', d.roundOff.paise);
    put('netSales', d.netSales.paise);
    put('returns', d.returns.paise);
    put('cancelled', d.cancelled.paise);
    for (final e in d.byMode.entries) {
      put('byMode.${e.key.wire}', e.value.paise);
    }
    for (final e in d.byProduct.entries) {
      put('byProduct.${e.key}.qty', e.value.qty);
      put('byProduct.${e.key}.amount', e.value.amount.paise);
    }
    put('expenses', d.expenses.paise);
    for (final e in d.byExpenseCategory.entries) {
      put('byExpenseCategory.${e.key.wire}', e.value.paise);
    }
    return out;
  }

  static Map<PaymentMode, Money> _byMode(List<Payment> payments, int sign) {
    final out = <PaymentMode, Money>{};
    for (final p in payments) {
      out[p.mode] = (out[p.mode] ?? Money.zero) + p.amount.times(sign);
    }
    return out;
  }

  static Map<String, ProductTally> _byProduct(Bill bill, int sign) {
    final nets = BillCalculator.lineNetAmounts(bill);
    return {
      for (var i = 0; i < bill.lines.length; i++)
        bill.lines[i].productId: ProductTally(
          qty: bill.lines[i].qty * sign,
          amount: nets[i].times(sign),
        ),
    };
  }
}

/// A monthly-summary delta for one location and month.
final class ExpenseDelta {
  const ExpenseDelta({
    required this.locationId,
    required this.monthKey,
    required this.delta,
  });

  final String locationId;

  /// `YYYY-MM`.
  final String monthKey;
  final Summary delta;
}
