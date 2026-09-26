import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus_core/nexus_core.dart';

import '../common/format.dart';
import '../data/providers.dart';

/// A location's daily summary, live (D-014).
final dailySummaryProvider =
    StreamProvider.family<Summary, (String locationId, String businessDate)>(
      (ref, key) =>
          ref.watch(summaryRepositoryProvider).watchDaily(key.$1, key.$2),
    );

/// A location's items at or below their threshold (D-015).
final lowStockProvider = StreamProvider.family<List<StockItem>, String>(
  (ref, locationId) =>
      ref.watch(stockRepositoryProvider).watchLowStock(locationId),
);

/// Today at each location in scope, and the total across them.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(todayProvider);
    final locations = ref.watch(scopeLocationsProvider);
    if (locations.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final summaries = <String, Summary>{};
    final lowStock = <String, List<StockItem>>{};
    var loading = false;
    for (final l in locations) {
      final s = ref.watch(dailySummaryProvider((l.code, today)));
      final low = ref.watch(lowStockProvider(l.code));
      if (s.hasError || low.hasError) {
        return Center(
          child: Text('Could not load ${l.code}: ${s.error ?? low.error}'),
        );
      }
      final sv = s.value;
      final lv = low.value;
      if (sv == null || lv == null) {
        loading = true;
        continue;
      }
      summaries[l.code] = sv;
      lowStock[l.code] = lv;
    }
    if (loading) return const Center(child: CircularProgressIndicator());

    final total = summaries.values.fold(const Summary(), (a, b) => a + b);
    final lowTotal = lowStock.values.fold(0, (a, b) => a + b.length);
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Today', style: theme.textTheme.headlineSmall),
        Text(
          '${formatBusinessDate(today)} · '
          '${locations.length == 1 ? locations.single.name : 'All locations'}',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            // The headline "Sales" is net revenue (QA-013).
            _Kpi(
              key: const Key('kpi-net-revenue'),
              label: 'Sales',
              value: total.netRevenue.format(),
            ),
            _Kpi(
              key: const Key('kpi-net-sales'),
              label: 'Billed',
              value: total.netSales.format(),
            ),
            _Kpi(
              key: const Key('kpi-bills'),
              label: 'Bills',
              value: '${total.billCount}',
            ),
            _Kpi(
              key: const Key('kpi-returns'),
              label: 'Returns',
              value: '${total.returns.format()} (${total.returnCount})',
            ),
            _Kpi(
              key: const Key('kpi-low-stock'),
              label: 'Low-stock items',
              value: '$lowTotal',
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text('By location', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            key: const Key('dashboard-table'),
            columns: const [
              DataColumn(label: Text('Location')),
              DataColumn(label: Text('Sales'), numeric: true),
              DataColumn(label: Text('Billed'), numeric: true),
              DataColumn(label: Text('Bills'), numeric: true),
              DataColumn(label: Text('Returns'), numeric: true),
              DataColumn(label: Text('Cancelled'), numeric: true),
              DataColumn(label: Text('Low stock'), numeric: true),
            ],
            rows: [
              for (final l in locations)
                _row(
                  l.code,
                  '${l.name} (${l.code})',
                  summaries[l.code]!,
                  lowStock[l.code]!.length,
                ),
              if (locations.length > 1)
                _row('total', 'Total', total, lowTotal, bold: true),
            ],
          ),
        ),
        if (lowTotal > 0) ...[
          const SizedBox(height: 24),
          Text('Low stock', style: theme.textTheme.titleMedium),
          for (final l in locations)
            for (final item in lowStock[l.code]!)
              ListTile(
                dense: true,
                leading: const Icon(Icons.warning_amber_outlined),
                title: Text('${item.name} · ${l.code}'),
                subtitle: Text(
                  '${formatQty(item.qty, item.unit)} left, threshold '
                  '${formatQty(item.lowThreshold!, item.unit)}',
                ),
              ),
        ],
      ],
    );
  }

  /// Cells are keyed `<id>-<column>`, e.g. `PTB-bills`, for tests.
  static DataRow _row(
    String id,
    String label,
    Summary s,
    int low, {
    bool bold = false,
  }) {
    final style = bold ? const TextStyle(fontWeight: FontWeight.bold) : null;
    DataCell cell(String column, String text) =>
        DataCell(Text(text, key: Key('$id-$column'), style: style));
    return DataRow(
      key: ValueKey(id),
      cells: [
        cell('location', label),
        cell('net-revenue', s.netRevenue.format()),
        cell('net-sales', s.netSales.format()),
        cell('bills', '${s.billCount}'),
        cell('returns', '${s.returns.format()} (${s.returnCount})'),
        cell('cancelled', '${s.cancelled.format()} (${s.cancelCount})'),
        cell('low-stock', '$low'),
      ],
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({required this.label, required this.value, super.key});

  final String label;
  final String value;

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
              Text(value, style: theme.textTheme.titleLarge),
            ],
          ),
        ),
      ),
    );
  }
}
