import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexus_core/nexus_core.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../widgets/pos_scaffold.dart';
import 'stock_common.dart';

/// The stock hub (POS-9): current stock at this location with negatives in
/// red, the low-stock list, and one button per operation the role may use.
class StockScreen extends ConsumerStatefulWidget {
  const StockScreen({super.key});

  @override
  ConsumerState<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends ConsumerState<StockScreen> {
  bool _lowOnly = false;

  /// Null shows finished goods and raw materials together (D-039).
  StockKind? _kind;

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider).value;
    bool can(String p) => session?.can(p) ?? false;
    final stock = ref.watch(stockProvider);
    final low = ref.watch(lowStockProvider).value ?? const <StockItem>[];

    final actions = <(String, String, IconData, String)>[
      if (can(Permission.stockMove)) ...[
        ('op-in', 'Stock In', Icons.move_to_inbox, Routes.stockIn),
        ('op-out', 'Stock Out', Icons.outbox, Routes.stockOut),
        ('op-wastage', 'Wastage', Icons.delete_sweep, Routes.stockWastage),
        ('op-produce', 'Produce', Icons.bakery_dining, Routes.stockProduce),
      ],
      if (can(Permission.stockAdjust))
        ('op-adjust', 'Adjust', Icons.fact_check, Routes.stockAdjust),
      ('op-history', 'History', Icons.history, Routes.stockHistory),
    ];

    return PosScaffold(
      title: 'Stock',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (actions.isNotEmpty)
            SizedBox(
              height: 64,
              // One row that scrolls sideways keeps the list tall on a phone.
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
                child: Row(
                  children: [
                    for (final (key, label, icon, path) in actions)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilledButton.tonalIcon(
                          key: Key(key),
                          onPressed: () => context.push(path),
                          icon: Icon(icon),
                          label: Text(label),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: SegmentedButton<StockKind?>(
              segments: const [
                ButtonSegment(
                  value: null,
                  label: Text('All', key: Key('kind-all')),
                ),
                ButtonSegment(
                  value: StockKind.finished,
                  label: Text('Finished goods', key: Key('kind-finished')),
                ),
                ButtonSegment(
                  value: StockKind.raw,
                  label: Text('Raw materials', key: Key('kind-raw')),
                ),
              ],
              selected: {_kind},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _kind = s.single),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: SegmentedButton<bool>(
              segments: [
                const ButtonSegment(
                  value: false,
                  label: Text('All', key: Key('tab-all')),
                ),
                ButtonSegment(
                  value: true,
                  label: Text(
                    'Low stock (${low.length})',
                    key: const Key('tab-low'),
                  ),
                ),
              ],
              selected: {_lowOnly},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _lowOnly = s.single),
            ),
          ),
          Expanded(
            child: stock.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text("Couldn't load stock.\n$e")),
              data: (all) {
                final shown = [
                  for (final i in _lowOnly ? low : all)
                    if (_kind == null || i.kind == _kind) i,
                ];
                if (shown.isEmpty) {
                  return Center(
                    child: Text(
                      _lowOnly
                          ? 'Nothing is running low.'
                          : _kind == null
                          ? 'No stock recorded here yet.'
                          : 'No ${_kind == StockKind.raw ? 'raw materials' : 'finished goods'} here yet.',
                    ),
                  );
                }
                return ListView.separated(
                  key: const Key('stock-list'),
                  itemCount: shown.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) => _StockTile(
                    item: shown[i],
                    onTap: can(Permission.stockThreshold)
                        ? () => context.push(
                            Routes.stockThreshold(shown[i].itemKey),
                          )
                        : null,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Why a quantity can be below zero (D-039).
const String negativeStockNote =
    'Negative means cakes were sold before they were recorded as made. '
    'Record Produce or Adjust to correct it.';

class _StockTile extends StatelessWidget {
  const _StockTile({required this.item, required this.onTap});

  final StockItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final negative = item.qty < 0;
    final threshold = item.lowThreshold;
    return ListTile(
      key: Key('stock-${item.itemKey}'),
      onTap: onTap,
      leading: Icon(
        item.isLow ? Icons.warning_amber : Icons.inventory_2_outlined,
        color: item.isLow ? const Color(0xFFB26A00) : null,
      ),
      title: Text(item.name),
      isThreeLine: negative,
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            [
              if (item.kind == StockKind.raw) 'Raw material' else 'Finished',
              if (threshold != null)
                'alert at ${formatQty(threshold, item.unit)}',
            ].join(' · '),
          ),
          if (negative)
            Text(
              negativeStockNote,
              key: Key('negative-note-${item.itemKey}'),
              style: theme.textTheme.bodySmall,
            ),
        ],
      ),
      trailing: Text(
        formatQty(item.qty, item.unit),
        key: Key('qty-${item.itemKey}'),
        style: theme.textTheme.titleMedium?.copyWith(
          color: negative ? theme.colorScheme.error : null,
          fontWeight: negative ? FontWeight.w700 : null,
        ),
      ),
    );
  }
}
