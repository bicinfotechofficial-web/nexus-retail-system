import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus_core/nexus_core.dart';

import '../../app/providers.dart';
import '../../widgets/date_bar.dart';
import '../../widgets/pos_scaffold.dart';
import 'stock_common.dart';

enum MovementDirection { all, inbound, outbound }

/// A movement is In when the sum of its line deltas is above zero and Out
/// when it is below (D-039). A movement that nets to zero is neither.
MovementDirection? directionOf(Movement m) {
  final sum = m.lines.fold(0, (n, l) => n + l.delta);
  if (sum > 0) return MovementDirection.inbound;
  if (sum < 0) return MovementDirection.outbound;
  return null;
}

String movementLabel(MovementType t) => switch (t) {
  MovementType.stockIn => 'Stock In',
  MovementType.stockOutRaw => 'Stock Out',
  MovementType.wastageRaw => 'Wastage (raw)',
  MovementType.wastageFg => 'Wastage (finished)',
  MovementType.produce => 'Produce',
  MovementType.adjust => 'Adjust',
  MovementType.sale => 'Sale',
  MovementType.returned => 'Return',
  MovementType.cancel => 'Bill cancelled',
};

/// `+500 g`, `-2 pcs`.
String signedQty(int delta, StockUnit unit) =>
    '${delta > 0 ? '+' : ''}${formatQty(delta, unit)}';

/// The day's stock movements with an In / Out / All filter and a date
/// (POS-18, D-039). Works from the cache offline.
class StockHistoryScreen extends ConsumerStatefulWidget {
  const StockHistoryScreen({super.key});

  @override
  ConsumerState<StockHistoryScreen> createState() => _StockHistoryScreenState();
}

class _StockHistoryScreenState extends ConsumerState<StockHistoryScreen> {
  /// Null follows today, so it rolls over at midnight IST.
  String? _date;
  MovementDirection _direction = MovementDirection.all;

  @override
  Widget build(BuildContext context) {
    final today = BusinessDate.of(ref.read(clockProvider)());
    final date = _date ?? today;
    final movements = ref.watch(movementsForDayProvider(date));
    final stock = ref.watch(stockProvider).value ?? const <StockItem>[];
    final byKey = {for (final i in stock) i.itemKey: i};
    return PosScaffold(
      title: 'Stock history',
      showDrawer: false,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DateBar(
            date: date,
            today: today,
            onChanged: (d) => setState(() => _date = d == today ? null : d),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: SegmentedButton<MovementDirection>(
              segments: const [
                ButtonSegment(
                  value: MovementDirection.all,
                  label: Text('All', key: Key('history-all')),
                ),
                ButtonSegment(
                  value: MovementDirection.inbound,
                  label: Text('In', key: Key('history-in')),
                ),
                ButtonSegment(
                  value: MovementDirection.outbound,
                  label: Text('Out', key: Key('history-out')),
                ),
              ],
              selected: {_direction},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _direction = s.single),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: switch (movements) {
              AsyncData(:final value) => _list([
                for (final m in value)
                  if (_direction == MovementDirection.all ||
                      directionOf(m) == _direction)
                    m,
              ], byKey),
              AsyncError() => const Center(
                child: Text("Couldn't load the history. Please try again."),
              ),
              _ => const Center(child: CircularProgressIndicator()),
            },
          ),
        ],
      ),
    );
  }

  Widget _list(List<Movement> shown, Map<String, StockItem> byKey) {
    if (shown.isEmpty) {
      return Center(
        child: Text(switch (_direction) {
          MovementDirection.all => 'No stock movements on this day.',
          MovementDirection.inbound => 'No stock came in on this day.',
          MovementDirection.outbound => 'No stock went out on this day.',
        }, key: const Key('no-movements')),
      );
    }
    return ListView.separated(
      key: const Key('movement-list'),
      itemCount: shown.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) =>
          _MovementTile(movement: shown[i], byKey: byKey),
    );
  }
}

class _MovementTile extends StatelessWidget {
  const _MovementTile({required this.movement, required this.byKey});

  final Movement movement;
  final Map<String, StockItem> byKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = movement;
    final direction = directionOf(m);
    final extra = m.reason ?? m.note;
    return ListTile(
      key: Key('movement-${m.id}'),
      leading: Icon(switch (direction) {
        MovementDirection.inbound => Icons.south_west,
        MovementDirection.outbound => Icons.north_east,
        _ => Icons.swap_horiz,
      }),
      title: Row(
        children: [
          Text(
            formatIstTime(m.clientCreatedAt),
            key: Key('movement-time-${m.id}'),
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              movementLabel(m.type),
              key: Key('movement-type-${m.id}'),
              style: theme.textTheme.titleSmall,
            ),
          ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final l in m.lines)
            Builder(
              builder: (context) {
                final item = byKey[l.itemKey];
                final name = item?.name ?? l.itemKey;
                final qty = item == null
                    ? '${l.delta > 0 ? '+' : ''}${l.delta}'
                    : signedQty(l.delta, item.unit);
                return Row(
                  children: [
                    Expanded(child: Text(name)),
                    Text(
                      qty,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: l.delta < 0 ? theme.colorScheme.error : null,
                      ),
                    ),
                  ],
                );
              },
            ),
          if (extra != null && extra.isNotEmpty)
            Text(extra, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
