import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus_core/nexus_core.dart';

import '../common/format.dart';
import '../data/providers.dart';
import 'report_aggregator.dart';
import 'report_period.dart';

/// The period on screen. Starts at today.
final reportPeriodProvider =
    NotifierProvider<ReportPeriodNotifier, ReportPeriod>(
      ReportPeriodNotifier.new,
    );

class ReportPeriodNotifier extends Notifier<ReportPeriod> {
  @override
  ReportPeriod build() =>
      ReportPeriod.containing(ReportKind.daily, ref.watch(todayProvider));

  void set(ReportPeriod period) => state = period;

  /// Switches the kind, keeping the period that contains the current one.
  void setKind(ReportKind kind) {
    final today = ref.read(todayProvider);
    final anchor = switch (state.kind) {
      ReportKind.daily => state.key,
      ReportKind.monthly => '${state.key}-01',
      ReportKind.annual => '${state.key}-01-01',
    };
    // Going from a year or month to days, stay within today.
    final date = anchor.compareTo(today) > 0 ? today : anchor;
    state = ReportPeriod.containing(kind, date);
  }
}

/// A report for a period and a comma-separated list of location codes.
final reportProvider = FutureProvider.family<Report, (ReportPeriod, String)>(
  (ref, key) => loadReport(
    ref.watch(summaryRepositoryProvider),
    key.$1,
    key.$2.split(','),
  ),
);

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locations = ref.watch(scopeLocationsProvider);
    if (locations.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final period = ref.watch(reportPeriodProvider);
    final today = ref.watch(todayProvider);
    final codes = locations.map((l) => l.code).join(',');
    final report = ref.watch(reportProvider((period, codes)));
    final names = ref.watch(productNamesProvider).value ?? const {};
    final notifier = ref.read(reportPeriodProvider.notifier);
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Reports', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 16),
        Wrap(
          spacing: 16,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SegmentedButton<ReportKind>(
              segments: [
                for (final k in ReportKind.values)
                  ButtonSegment(value: k, label: Text(k.label)),
              ],
              selected: {period.kind},
              onSelectionChanged: (s) => notifier.setKind(s.single),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Previous',
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => notifier.set(period.shift(-1)),
                ),
                if (period.kind == ReportKind.daily)
                  TextButton.icon(
                    key: const Key('report-period'),
                    icon: const Icon(Icons.calendar_today_outlined, size: 18),
                    label: Text(period.label),
                    onPressed: () =>
                        _pickDate(context, notifier, period, today),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      period.label,
                      key: const Key('report-period'),
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                IconButton(
                  tooltip: 'Next',
                  icon: const Icon(Icons.chevron_right),
                  onPressed: period.shift(1).isAfter(today)
                      ? null
                      : () => notifier.set(period.shift(1)),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 24),
        switch (report) {
          AsyncData(:final value) => _ReportBody(
            report: value,
            locations: locations,
            productNames: names,
          ),
          AsyncError(:final error) => Text('Could not load the report: $error'),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ],
    );
  }

  Future<void> _pickDate(
    BuildContext context,
    ReportPeriodNotifier notifier,
    ReportPeriod period,
    String today,
  ) async {
    DateTime asDate(String d) {
      final p = d.split('-').map(int.parse).toList();
      return DateTime(p[0], p[1], p[2]);
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: asDate(period.key),
      firstDate: DateTime(2024),
      lastDate: asDate(today),
    );
    if (picked == null) return;
    final key =
        '${picked.year.toString().padLeft(4, '0')}-'
        '${picked.month.toString().padLeft(2, '0')}-'
        '${picked.day.toString().padLeft(2, '0')}';
    notifier.set(ReportPeriod(ReportKind.daily, key));
  }
}

class _ReportBody extends StatelessWidget {
  const _ReportBody({
    required this.report,
    required this.locations,
    required this.productNames,
  });

  final Report report;
  final List<Location> locations;
  final Map<String, String> productNames;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final multi = locations.length > 1;
    final columns = <(String, Summary)>[
      if (multi)
        for (final l in locations) (l.code, report.byLocation[l.code]!),
      ('total', report.total),
    ];

    DataRow line(String id, String label, String Function(Summary) value) =>
        DataRow(
          cells: [
            DataCell(Text(label)),
            for (final (col, s) in columns)
              DataCell(Text(value(s), key: Key('$col-$id'))),
          ],
        );

    final top = report.topProducts();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Sales', style: theme.textTheme.titleMedium),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: [
              const DataColumn(label: Text('')),
              for (final (col, _) in columns)
                DataColumn(
                  numeric: true,
                  label: Text(
                    col != 'total'
                        ? col
                        : (multi ? 'Total' : locations.single.code),
                  ),
                ),
            ],
            rows: [
              line('gross', 'Gross sales', (s) => s.grossSales.format()),
              line('discounts', 'Discounts', (s) => (-s.discounts).format()),
              line('round-off', 'Round-off', (s) => s.roundOff.format()),
              line('net-sales', 'Net sales', (s) => s.netSales.format()),
              line(
                'returns',
                'Returns',
                (s) => '${(-s.returns).format()} (${s.returnCount})',
              ),
              line(
                'cancelled',
                'Cancellations',
                (s) => '${(-s.cancelled).format()} (${s.cancelCount})',
              ),
              line('net-revenue', 'Net revenue', (s) => s.netRevenue.format()),
              line('bills', 'Bills', (s) => '${s.billCount}'),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text('By payment mode', style: theme.textTheme.titleMedium),
        DataTable(
          columns: const [
            DataColumn(label: Text('Mode')),
            DataColumn(label: Text('Net received'), numeric: true),
          ],
          rows: [
            for (final (mode, amount) in report.byMode)
              DataRow(
                cells: [
                  DataCell(Text(paymentModeLabel(mode))),
                  DataCell(
                    Text(amount.format(), key: Key('mode-${mode.wire}')),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 24),
        Text('Top products', style: theme.textTheme.titleMedium),
        if (top.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('No sales in this period.'),
          )
        else
          DataTable(
            columns: const [
              DataColumn(label: Text('#'), numeric: true),
              DataColumn(label: Text('Product')),
              DataColumn(label: Text('Qty'), numeric: true),
              DataColumn(label: Text('Net amount'), numeric: true),
            ],
            rows: [
              for (var i = 0; i < top.length; i++)
                DataRow(
                  cells: [
                    DataCell(Text('${i + 1}')),
                    DataCell(
                      Text(
                        productNames[top[i].productId] ?? top[i].productId,
                        key: Key('top-$i'),
                      ),
                    ),
                    DataCell(Text('${top[i].qty}')),
                    DataCell(Text(top[i].amount.format())),
                  ],
                ),
            ],
          ),
      ],
    );
  }
}
