import 'package:nexus_core/nexus_core.dart';

/// Which period a report covers.
enum ReportKind {
  daily('Daily'),
  monthly('Monthly'),
  annual('Annual');

  const ReportKind(this.label);
  final String label;
}

/// A product's share of a report's sales.
final class TopProduct {
  const TopProduct({
    required this.productId,
    required this.qty,
    required this.amount,
  });

  final String productId;
  final int qty;

  /// Net of the bill discount (D-024).
  final Money amount;
}

/// A finished report: one summary per location and their sum.
final class Report {
  const Report({required this.byLocation, required this.total});

  /// Location code → that location's summary for the period.
  final Map<String, Summary> byLocation;

  /// The sum of [byLocation] with `Summary.+`.
  final Summary total;

  /// Every payment mode in a fixed order, zero where there were none.
  List<(PaymentMode, Money)> get byMode => [
    for (final m in PaymentMode.values) (m, total.byMode[m] ?? Money.zero),
  ];

  /// The best sellers by net amount, then quantity, then product ID.
  List<TopProduct> topProducts([int limit = 10]) {
    final all = [
      for (final e in total.byProduct.entries)
        if (e.value.qty != 0 || !e.value.amount.isZero)
          TopProduct(
            productId: e.key,
            qty: e.value.qty,
            amount: e.value.amount,
          ),
    ];
    all.sort((a, b) {
      final byAmount = b.amount.paise.compareTo(a.amount.paise);
      if (byAmount != 0) return byAmount;
      final byQty = b.qty.compareTo(a.qty);
      if (byQty != 0) return byQty;
      return a.productId.compareTo(b.productId);
    });
    return all.take(limit).toList();
  }
}

/// Report arithmetic over summary docs (D-014). Pure, so it is unit-tested
/// without a data layer. Reports never read bills.
abstract final class ReportAggregator {
  /// The sum of [summaries] with `Summary.+`; an empty list gives zeros.
  static Summary combine(Iterable<Summary> summaries) =>
      summaries.fold(const Summary(), (a, b) => a + b);

  /// `2026` → `2026-01` … `2026-12`.
  static List<String> monthsOf(String year) {
    if (!RegExp(r'^\d{4}$').hasMatch(year)) {
      throw FormatException('Not a YYYY year', year);
    }
    return [
      for (var m = 1; m <= 12; m++) '$year-${m.toString().padLeft(2, '0')}',
    ];
  }

  /// A year's summary: the sum of its 12 monthly summaries. [monthly] maps
  /// `YYYY-MM` to a summary; months with no doc count as zero. Throws
  /// [ArgumentError] if a key is not a month of [year], so a wrong query
  /// can't quietly add another year's months.
  static Summary annual(String year, Map<String, Summary> monthly) {
    final months = monthsOf(year).toSet();
    for (final key in monthly.keys) {
      if (!months.contains(key)) {
        throw ArgumentError.value(key, 'monthly', 'is not a month of $year');
      }
    }
    return combine(monthly.values);
  }

  /// Combines one summary per location into a [Report].
  static Report build(Map<String, Summary> byLocation) {
    final sorted = Map.fromEntries(
      byLocation.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
    return Report(byLocation: sorted, total: combine(sorted.values));
  }
}
