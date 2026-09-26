import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus_core/nexus_core.dart';

import '../common/dialogs.dart';
import '../common/format.dart';
import '../data/providers.dart';
import 'financials.dart';

/// Financials for a year and a comma-separated list of location codes.
/// Auto-disposed, so it is read again after an expense is saved.
final financialsProvider = FutureProvider.autoDispose
    .family<Financials, (String year, String codes)>((ref, key) {
      final thisMonth = BusinessDate.monthOf(ref.watch(todayProvider));
      return loadFinancials(
        ref.watch(summaryRepositoryProvider),
        FinancialsAggregator.monthsToShow(key.$1, thisMonth),
        key.$2.split(','),
      );
    });

/// The year on screen. Starts at the current IST year.
final financialsYearProvider = NotifierProvider<FinancialsYearNotifier, String>(
  FinancialsYearNotifier.new,
);

class FinancialsYearNotifier extends Notifier<String> {
  @override
  String build() => BusinessDate.yearOf(ref.watch(todayProvider));

  void set(String year) => state = year;
}

/// Sales (net revenue) − expenses = profit, per month and location and
/// combined, for the locations in scope, deactivated ones included.
class FinancialsScreen extends ConsumerWidget {
  const FinancialsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locations = ref.watch(scopeLocationsProvider);
    if (locations.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final year = ref.watch(financialsYearProvider);
    final thisYear = BusinessDate.yearOf(ref.watch(todayProvider));
    final codes = locations.map((l) => l.code).join(',');
    final async = ref.watch(financialsProvider((year, codes)));
    final notifier = ref.read(financialsYearProvider.notifier);
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Financials', style: theme.textTheme.headlineSmall),
        Text(
          'Sales (net revenue) less expenses, from the monthly summaries.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Previous year',
              icon: const Icon(Icons.chevron_left),
              onPressed: () => notifier.set('${int.parse(year) - 1}'),
            ),
            Text(
              year,
              key: const Key('financials-year'),
              style: theme.textTheme.titleMedium,
            ),
            IconButton(
              tooltip: 'Next year',
              icon: const Icon(Icons.chevron_right),
              onPressed: year.compareTo(thisYear) >= 0
                  ? null
                  : () => notifier.set('${int.parse(year) + 1}'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        switch (async) {
          AsyncData(:final value) => _Body(
            financials: value,
            locations: locations,
          ),
          AsyncError(:final error) => Text(
            'Could not load financials: ${failureMessage(error)}',
          ),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ],
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.financials, required this.locations});

  final Financials financials;
  final List<Location> locations;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = financials;
    final total = f.total;
    final multi = locations.length > 1;
    final byCode = {for (final l in locations) l.code: l};
    String header(String code) {
      final l = byCode[code];
      return l == null || l.active ? code : '$code (inactive)';
    }

    Widget money(Money m, String key, {bool bold = false}) => Text(
      m.format(),
      key: Key(key),
      style: TextStyle(
        color: m.isNegative ? theme.colorScheme.error : null,
        fontWeight: bold ? FontWeight.bold : null,
      ),
    );

    List<DataCell> figures(Summary s, String key, {bool bold = false}) => [
      DataCell(money(s.netRevenue, '$key-sales', bold: bold)),
      DataCell(money(s.expenses, '$key-expenses', bold: bold)),
      DataCell(money(s.profit, '$key-profit', bold: bold)),
    ];

    const figureColumns = [
      DataColumn(label: Text('Sales'), numeric: true),
      DataColumn(label: Text('Expenses'), numeric: true),
      DataColumn(label: Text('Profit'), numeric: true),
    ];
    const bold = TextStyle(fontWeight: FontWeight.bold);

    if (f.months.isEmpty) {
      return const Text('This year has not started yet.');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _Kpi('Sales', money(total.netRevenue, 'kpi-sales')),
            _Kpi('Expenses', money(total.expenses, 'kpi-expenses')),
            _Kpi('Profit', money(total.profit, 'kpi-profit')),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          multi ? 'By month, all locations in view' : 'By month',
          style: theme.textTheme.titleMedium,
        ),
        _scroll(
          DataTable(
            key: const Key('financials-by-month'),
            columns: const [
              DataColumn(label: Text('Month')),
              ...figureColumns,
            ],
            rows: [
              for (final m in f.months)
                DataRow(
                  cells: [
                    DataCell(Text(formatMonthKey(m))),
                    ...figures(f.month(m), 'fin-$m'),
                  ],
                ),
              DataRow(
                cells: [
                  const DataCell(Text('Total', style: bold)),
                  ...figures(total, 'fin-total', bold: true),
                ],
              ),
            ],
          ),
        ),
        if (multi) ...[
          const SizedBox(height: 24),
          Text('By location', style: theme.textTheme.titleMedium),
          _scroll(
            DataTable(
              key: const Key('financials-by-location'),
              columns: const [
                DataColumn(label: Text('Location')),
                ...figureColumns,
              ],
              rows: [
                for (final code in f.locations)
                  DataRow(
                    cells: [
                      DataCell(Text(header(code))),
                      ...figures(f.location(code), 'fin-loc-$code'),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Profit by month and location',
            style: theme.textTheme.titleMedium,
          ),
          _scroll(
            DataTable(
              key: const Key('financials-matrix'),
              columns: [
                const DataColumn(label: Text('Month')),
                for (final code in f.locations)
                  DataColumn(label: Text(header(code)), numeric: true),
                const DataColumn(label: Text('Total'), numeric: true),
              ],
              rows: [
                for (final m in f.months)
                  DataRow(
                    cells: [
                      DataCell(Text(formatMonthKey(m))),
                      for (final code in f.locations)
                        DataCell(
                          money(f.cell(code, m).profit, 'fin-$m-$code-profit'),
                        ),
                      DataCell(money(f.month(m).profit, 'fin-$m-all-profit')),
                    ],
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),
        Text('Expenses by category', style: theme.textTheme.titleMedium),
        _scroll(
          DataTable(
            columns: const [
              DataColumn(label: Text('Category')),
              DataColumn(label: Text('Amount'), numeric: true),
            ],
            rows: [
              for (final c in ExpenseCategory.values)
                DataRow(
                  cells: [
                    DataCell(Text(expenseCategoryLabel(c))),
                    DataCell(
                      money(
                        total.byExpenseCategory[c] ?? Money.zero,
                        'fin-cat-${c.wire}',
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  static Widget _scroll(Widget child) =>
      SingleChildScrollView(scrollDirection: Axis.horizontal, child: child);
}

class _Kpi extends StatelessWidget {
  const _Kpi(this.label, this.value);

  final String label;
  final Widget value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 200,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              DefaultTextStyle.merge(
                style: theme.textTheme.titleLarge,
                child: value,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
