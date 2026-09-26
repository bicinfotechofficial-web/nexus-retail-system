import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';

import '../reports/report_aggregator.dart';

/// Sales, expenses and profit per month and location, and combined, read
/// from monthly summaries only (D-014). For every cell, total and grand
/// total, `netRevenue` is the sales, `expenses` the expenses and
/// `Summary.profit` (net revenue − expenses) the profit.
final class Financials {
  const Financials._(this.months, this.locations, this._cells);

  /// `YYYY-MM`, in order.
  final List<String> months;

  /// Location codes, in order.
  final List<String> locations;

  // location → month → summary, with a zero summary where there's no doc.
  final Map<String, Map<String, Summary>> _cells;

  /// One location's month.
  Summary cell(String location, String month) =>
      _cells[location]?[month] ?? const Summary();

  /// A month across every location.
  Summary month(String month) =>
      ReportAggregator.combine([for (final l in locations) cell(l, month)]);

  /// A location across every month.
  Summary location(String location) =>
      ReportAggregator.combine([for (final m in months) cell(location, m)]);

  /// Every location and month.
  Summary get total =>
      ReportAggregator.combine([for (final m in months) month(m)]);
}

/// The pure arithmetic behind the Financials page, unit-tested on its own.
abstract final class FinancialsAggregator {
  /// [monthly] maps a location code to its monthly summaries (`YYYY-MM` →
  /// summary). A month without a doc counts as zero; a location in
  /// [monthly] with no docs at all still gets a column. Throws
  /// [ArgumentError] for a month outside [months], so a wrong query can't
  /// quietly add another period.
  static Financials build({
    required List<String> months,
    required Map<String, Map<String, Summary>> monthly,
  }) {
    final allowed = months.toSet();
    for (final e in monthly.entries) {
      for (final key in e.value.keys) {
        if (!allowed.contains(key)) {
          throw ArgumentError.value(
            key,
            'monthly[${e.key}]',
            'is not one of the months asked for',
          );
        }
      }
    }
    final locations = monthly.keys.toList()..sort();
    return Financials._(List.unmodifiable(months), locations, {
      for (final l in locations) l: Map.unmodifiable(monthly[l]!),
    });
  }

  /// The months of [year] a page shows: all 12 for a past year, up to and
  /// including [currentMonth] for the current one, none for a future one.
  static List<String> monthsToShow(String year, String currentMonth) => [
    for (final m in ReportAggregator.monthsOf(year))
      if (m.compareTo(currentMonth) <= 0) m,
  ];
}

/// Reads each location's monthly summaries for [months] and aggregates
/// them. Never reads bills or expense docs.
Future<Financials> loadFinancials(
  SummaryRepository repo,
  List<String> months,
  List<String> locationIds,
) async {
  if (months.isEmpty) {
    return FinancialsAggregator.build(
      months: months,
      monthly: {for (final l in locationIds) l: const {}},
    );
  }
  final docs = await Future.wait(
    locationIds.map((l) => repo.monthly(l, months.first, months.last)),
  );
  return FinancialsAggregator.build(
    months: months,
    monthly: {
      for (var i = 0; i < locationIds.length; i++) locationIds[i]: docs[i],
    },
  );
}
