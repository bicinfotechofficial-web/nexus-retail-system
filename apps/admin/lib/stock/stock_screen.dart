import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus_core/nexus_core.dart';

import '../common/format.dart';
import '../data/providers.dart';

/// Every stock doc at a location, live.
final stockProvider = StreamProvider.family<List<StockItem>, String>(
  (ref, locationId) =>
      ref.watch(stockRepositoryProvider).watchStock(locationId),
);

/// Which items the per-location tables show.
enum StockFilter {
  all('All items'),
  raw('Raw materials'),
  finished('Finished goods');

  const StockFilter(this.label);
  final String label;

  bool matches(StockItem item) => switch (this) {
    StockFilter.all => true,
    StockFilter.raw => item.kind == StockKind.raw,
    StockFilter.finished => item.kind == StockKind.finished,
  };
}

/// An item at or below its threshold, at a location.
typedef LowStockRow = ({Location location, StockItem item});

/// The low items across [stock] (location code → items), by location code
/// and then item name. Low means at or below the threshold (D-015), which
/// includes every negative item that has one.
List<LowStockRow> lowStockAcross(
  List<Location> locations,
  Map<String, List<StockItem>> stock,
) => [
  for (final l in [...locations]..sort((a, b) => a.code.compareTo(b.code)))
    for (final item in _byName(stock[l.code] ?? const []))
      if (item.isLow) (location: l, item: item),
];

List<StockItem> _byName(List<StockItem> items) =>
    [...items]..sort((a, b) => a.name.compareTo(b.name));

String _kindLabel(StockKind kind) =>
    kind == StockKind.raw ? 'Raw material' : 'Finished good';

/// Stock levels at each location in scope, and the low items across them.
/// Read only: thresholds are set from the POS by each location (D-015).
class StockScreen extends ConsumerStatefulWidget {
  const StockScreen({super.key});

  @override
  ConsumerState<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends ConsumerState<StockScreen> {
  StockFilter _filter = StockFilter.all;

  @override
  Widget build(BuildContext context) {
    if (ref.watch(scopeLocationsProvider).isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    // Current levels, so a deactivated location only when picked on its own.
    final locations = ref.watch(currentLocationsProvider);
    if (locations.isEmpty) {
      return const Center(child: Text('No active locations.'));
    }
    final stock = <String, List<StockItem>>{};
    for (final l in locations) {
      final async = ref.watch(stockProvider(l.code));
      if (async.hasError) {
        return Center(
          child: Text('Could not load stock at ${l.code}: ${async.error}'),
        );
      }
      final items = async.value;
      if (items == null) {
        return const Center(child: CircularProgressIndicator());
      }
      stock[l.code] = items;
    }
    final theme = Theme.of(context);
    final low = lowStockAcross(locations, stock);
    final multi = locations.length > 1;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Stock', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          'Quantities in base units. A negative quantity means more was sold '
          'or used than was recorded in; the next count at the shop '
          'corrects it.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 24),
        Text(
          multi ? 'Low stock across all locations' : 'Low stock',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (low.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Nothing is at or below its threshold.',
              key: Key('low-stock-empty'),
            ),
          )
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              key: const Key('low-stock-table'),
              columns: const [
                DataColumn(label: Text('Location')),
                DataColumn(label: Text('Item')),
                DataColumn(label: Text('Type')),
                DataColumn(label: Text('Quantity'), numeric: true),
                DataColumn(label: Text('Threshold'), numeric: true),
              ],
              rows: [
                for (final r in low)
                  DataRow(
                    key: ValueKey('low-${r.location.code}-${r.item.itemKey}'),
                    cells: [
                      DataCell(Text(r.location.code)),
                      DataCell(Text(r.item.name)),
                      DataCell(Text(_kindLabel(r.item.kind))),
                      DataCell(
                        _Qty(
                          item: r.item,
                          textKey: Key(
                            'low-qty-${r.location.code}-${r.item.itemKey}',
                          ),
                        ),
                      ),
                      DataCell(
                        Text(formatQty(r.item.lowThreshold!, r.item.unit)),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('By location', style: theme.textTheme.titleMedium),
            SegmentedButton<StockFilter>(
              key: const Key('stock-filter'),
              segments: [
                for (final f in StockFilter.values)
                  ButtonSegment(value: f, label: Text(f.label)),
              ],
              selected: {_filter},
              onSelectionChanged: (s) => setState(() => _filter = s.single),
            ),
          ],
        ),
        for (final l in locations)
          _LocationStock(
            location: l,
            items: [
              for (final i in _byName(stock[l.code]!))
                if (_filter.matches(i)) i,
            ],
          ),
      ],
    );
  }
}

class _LocationStock extends StatelessWidget {
  const _LocationStock({required this.location, required this.items});

  final Location location;
  final List<StockItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final code = location.code;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(locationLabel(location), style: theme.textTheme.titleSmall),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('No stock recorded.'),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                key: Key('stock-table-$code'),
                columns: const [
                  DataColumn(label: Text('Item')),
                  DataColumn(label: Text('Type')),
                  DataColumn(label: Text('Quantity'), numeric: true),
                  DataColumn(label: Text('Threshold'), numeric: true),
                  DataColumn(label: Text('Status')),
                ],
                rows: [
                  for (final i in items)
                    DataRow(
                      key: ValueKey('stock-$code-${i.itemKey}'),
                      cells: [
                        DataCell(Text(i.name)),
                        DataCell(Text(_kindLabel(i.kind))),
                        DataCell(
                          _Qty(item: i, textKey: Key('qty-$code-${i.itemKey}')),
                        ),
                        DataCell(
                          Text(
                            i.lowThreshold == null
                                ? '—'
                                : formatQty(i.lowThreshold!, i.unit),
                            key: Key('threshold-$code-${i.itemKey}'),
                          ),
                        ),
                        DataCell(_Status(item: i, code: code)),
                      ],
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A quantity, in the error colour when it is below zero.
class _Qty extends StatelessWidget {
  const _Qty({required this.item, required this.textKey});

  final StockItem item;
  final Key textKey;

  @override
  Widget build(BuildContext context) {
    final negative = item.qty < 0;
    return Text(
      formatQty(item.qty, item.unit),
      key: textKey,
      style: negative
          ? TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontWeight: FontWeight.bold,
            )
          : null,
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.item, required this.code});

  final StockItem item;
  final String code;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, color) = item.qty < 0
        ? ('Below zero', scheme.error)
        : item.isLow
        ? ('Low', scheme.tertiary)
        : ('', scheme.onSurface);
    if (label.isEmpty) return const SizedBox.shrink();
    return Text(
      label,
      key: Key('status-$code-${item.itemKey}'),
      style: TextStyle(color: color, fontWeight: FontWeight.w600),
    );
  }
}
