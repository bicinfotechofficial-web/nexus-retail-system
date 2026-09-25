import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';

import '../common/format.dart';
import 'report_aggregator.dart';

/// A report period: a business date, a `YYYY-MM` month or a `YYYY` year.
final class ReportPeriod {
  const ReportPeriod(this.kind, this.key);

  /// The period of [kind] that contains [today] (`YYYY-MM-DD`).
  factory ReportPeriod.containing(ReportKind kind, String today) =>
      ReportPeriod(kind, switch (kind) {
        ReportKind.daily => today,
        ReportKind.monthly => BusinessDate.monthOf(today),
        ReportKind.annual => BusinessDate.yearOf(today),
      });

  final ReportKind kind;
  final String key;

  /// The period [steps] later (negative for earlier).
  ReportPeriod shift(int steps) => ReportPeriod(kind, switch (kind) {
    ReportKind.daily => BusinessDate.addDays(key, steps),
    ReportKind.monthly => _addMonths(key, steps),
    ReportKind.annual => '${int.parse(key) + steps}',
  });

  /// True when this period starts after the one of the same kind that
  /// contains [today].
  bool isAfter(String today) =>
      key.compareTo(ReportPeriod.containing(kind, today).key) > 0;

  String get label => switch (kind) {
    ReportKind.daily => formatBusinessDate(key),
    ReportKind.monthly => formatMonthKey(key),
    ReportKind.annual => key,
  };

  static String _addMonths(String monthKey, int steps) {
    final p = monthKey.split('-').map(int.parse).toList();
    final index = p[0] * 12 + (p[1] - 1) + steps;
    final y = index ~/ 12;
    final m = index % 12 + 1;
    return '$y-${m.toString().padLeft(2, '0')}';
  }

  @override
  bool operator ==(Object other) =>
      other is ReportPeriod && other.kind == kind && other.key == key;

  @override
  int get hashCode => Object.hash(kind, key);
}

/// Reads the summary docs for [period] at each of [locationIds] and builds
/// the report. Daily and monthly read one doc per location; annual reads a
/// location's 12 monthly docs and adds them up. Never reads bills (D-014).
Future<Report> loadReport(
  SummaryRepository repo,
  ReportPeriod period,
  List<String> locationIds,
) async {
  Future<Summary> one(String loc) async {
    switch (period.kind) {
      case ReportKind.daily:
        final docs = await repo.daily(loc, period.key, period.key);
        return docs[period.key] ?? const Summary();
      case ReportKind.monthly:
        final docs = await repo.monthly(loc, period.key, period.key);
        return docs[period.key] ?? const Summary();
      case ReportKind.annual:
        final months = ReportAggregator.monthsOf(period.key);
        final docs = await repo.monthly(loc, months.first, months.last);
        return ReportAggregator.annual(period.key, docs);
    }
  }

  final summaries = await Future.wait(locationIds.map(one));
  return ReportAggregator.build({
    for (var i = 0; i < locationIds.length; i++) locationIds[i]: summaries[i],
  });
}
