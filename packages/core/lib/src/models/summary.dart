import '../enums.dart';
import '../map_reader.dart';
import '../money.dart';

/// `dailySummary/{YYYY-MM-DD}` and `monthlySummary/{YYYY-MM}`, same shape.
/// Written only through increments; see `SummaryDelta`. Missing fields read
/// as zero, because the first increment creates them.
final class Summary {
  const Summary({
    this.billCount = 0,
    this.cancelCount = 0,
    this.returnCount = 0,
    this.grossSales = Money.zero,
    this.discounts = Money.zero,
    this.roundOff = Money.zero,
    this.netSales = Money.zero,
    this.returns = Money.zero,
    this.cancelled = Money.zero,
    this.byMode = const {},
    this.byProduct = const {},
    this.expenses = Money.zero,
    this.byExpenseCategory = const {},
    this.lastWriteRef,
  });

  factory Summary.fromMap(String id, Map<String, Object?> map) {
    final r = MapReader(map, 'summary $id');
    Money m(String k) => Money(r.integerOr(k, 0));
    return Summary(
      billCount: r.integerOr('billCount', 0),
      cancelCount: r.integerOr('cancelCount', 0),
      returnCount: r.integerOr('returnCount', 0),
      grossSales: m('grossSales'),
      discounts: m('discounts'),
      roundOff: m('roundOff'),
      netSales: m('netSales'),
      returns: m('returns'),
      cancelled: m('cancelled'),
      byMode: {
        for (final e in r.intMap('byMode').entries)
          PaymentMode.fromWire(e.key): Money(e.value),
      },
      byProduct: r.objectMap('byProduct', ProductTally.fromReader),
      expenses: m('expenses'),
      byExpenseCategory: {
        for (final e in r.intMap('byExpenseCategory').entries)
          ExpenseCategory.fromWire(e.key): Money(e.value),
      },
      lastWriteRef: r.stringOrNull('lastWriteRef'),
    );
  }

  final int billCount;
  final int cancelCount;
  final int returnCount;

  /// Σ subtotal.
  final Money grossSales;
  final Money discounts;
  final Money roundOff;

  /// Σ total of completed bills (cancellations are not subtracted here).
  final Money netSales;

  /// Σ refundTotal.
  final Money returns;

  /// Σ total of bills cancelled that day.
  final Money cancelled;

  /// Net payments minus refunds, per mode.
  final Map<PaymentMode, Money> byMode;
  final Map<String, ProductTally> byProduct;

  /// Monthly only.
  final Money expenses;

  /// Monthly only.
  final Map<ExpenseCategory, Money> byExpenseCategory;
  final String? lastWriteRef;

  /// netSales − returns − cancelled (02-DATA-MODEL).
  Money get netRevenue => netSales - returns - cancelled;

  /// Net revenue − expenses. Meaningful on monthly summaries.
  Money get profit => netRevenue - expenses;

  /// Combines summaries, e.g. several locations or the months of a year.
  Summary operator +(Summary o) => Summary(
    billCount: billCount + o.billCount,
    cancelCount: cancelCount + o.cancelCount,
    returnCount: returnCount + o.returnCount,
    grossSales: grossSales + o.grossSales,
    discounts: discounts + o.discounts,
    roundOff: roundOff + o.roundOff,
    netSales: netSales + o.netSales,
    returns: returns + o.returns,
    cancelled: cancelled + o.cancelled,
    byMode: _mergeMoney(byMode, o.byMode),
    byProduct: {
      for (final k in {...byProduct.keys, ...o.byProduct.keys})
        k:
            (byProduct[k] ?? ProductTally.zero) +
            (o.byProduct[k] ?? ProductTally.zero),
    },
    expenses: expenses + o.expenses,
    byExpenseCategory: _mergeMoney(byExpenseCategory, o.byExpenseCategory),
  );

  Map<String, Object?> toMap() => {
    'billCount': billCount,
    'cancelCount': cancelCount,
    'returnCount': returnCount,
    'grossSales': grossSales.paise,
    'discounts': discounts.paise,
    'roundOff': roundOff.paise,
    'netSales': netSales.paise,
    'returns': returns.paise,
    'cancelled': cancelled.paise,
    'byMode': {for (final e in byMode.entries) e.key.wire: e.value.paise},
    'byProduct': {for (final e in byProduct.entries) e.key: e.value.toMap()},
    'expenses': expenses.paise,
    'byExpenseCategory': {
      for (final e in byExpenseCategory.entries) e.key.wire: e.value.paise,
    },
    'lastWriteRef': lastWriteRef,
  };
}

Map<K, Money> _mergeMoney<K>(Map<K, Money> a, Map<K, Money> b) => {
  for (final k in {...a.keys, ...b.keys})
    k: (a[k] ?? Money.zero) + (b[k] ?? Money.zero),
};

final class ProductTally {
  const ProductTally({required this.qty, required this.amount});

  factory ProductTally.fromReader(MapReader r) => ProductTally(
    qty: r.integerOr('qty', 0),
    amount: Money(r.integerOr('amount', 0)),
  );

  static const ProductTally zero = ProductTally(qty: 0, amount: Money.zero);

  final int qty;

  /// Net of the bill discount (D-024).
  final Money amount;

  ProductTally operator +(ProductTally o) =>
      ProductTally(qty: qty + o.qty, amount: amount + o.amount);

  ProductTally operator -() => ProductTally(qty: -qty, amount: -amount);

  Map<String, Object?> toMap() => {'qty': qty, 'amount': amount.paise};
}
