import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexus_core/nexus_core.dart';

import '../../app/messages.dart';
import '../../app/providers.dart';
import '../../app/router.dart';
import '../../widgets/pos_scaffold.dart';
import 'due_counts.dart';

/// Pre-orders (D-043): open orders grouped Overdue, Due today, Due tomorrow
/// and Later, soonest first, and a Recent tab with the delivered and
/// cancelled ones. The day is the business date from the app's clock.
class OrdersScreen extends ConsumerWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: PosScaffold(
        title: 'Orders',
        bottom: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            key: const Key('new-order'),
            onPressed: () => context.push(Routes.newOrder),
            icon: const Icon(Icons.add),
            label: const Text('New order'),
          ),
        ),
        body: const Column(
          children: [
            TabBar(
              tabs: [
                Tab(key: Key('tab-open'), text: 'Open'),
                Tab(key: Key('tab-recent'), text: 'Recent'),
              ],
            ),
            Expanded(
              child: TabBarView(children: [_OpenOrders(), _RecentOrders()]),
            ),
          ],
        ),
      ),
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed(this.error);

  final Object error;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        Messages.anyError(error),
        key: const Key('orders-error'),
        textAlign: TextAlign.center,
      ),
    ),
  );
}

class _OpenOrders extends ConsumerWidget {
  const _OpenOrders();

  static const _groups = [
    (OrderDue.overdue, 'overdue', 'Overdue'),
    (OrderDue.today, 'today', 'Due today'),
    (OrderDue.tomorrow, 'tomorrow', 'Due tomorrow'),
    (OrderDue.later, 'later', 'Later'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = ref.watch(openOrdersProvider);
    return open.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _Failed(e),
      data: (orders) {
        if (orders.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No open orders.',
                key: Key('orders-empty'),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        final today = BusinessDate.of(ref.read(clockProvider)());
        final theme = Theme.of(context);
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            for (final (due, key, label) in _groups)
              ..._group(
                theme,
                today,
                due,
                key,
                label,
                orders
                    .where(
                      (o) => OrderValidator.dueState(o.dueDate, today) == due,
                    )
                    .toList(),
                context,
              ),
          ],
        );
      },
    );
  }

  List<Widget> _group(
    ThemeData theme,
    String today,
    OrderDue due,
    String key,
    String label,
    List<PreOrder> orders,
    BuildContext context,
  ) {
    if (orders.isEmpty) return const [];
    final color = due == OrderDue.overdue ? theme.colorScheme.error : null;
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
        child: Text(
          '$label (${orders.length})',
          key: Key('group-$key'),
          style: theme.textTheme.titleSmall?.copyWith(color: color),
        ),
      ),
      for (final o in orders)
        Card(
          key: Key('order-${o.id}'),
          child: ListTile(
            onTap: () => context.push(Routes.order(o.id)),
            title: Text(
              dueLabel(o, today),
              key: Key('order-due-${o.id}'),
              style: TextStyle(fontWeight: FontWeight.w600, color: color),
            ),
            subtitle: Text(
              '${o.customer.name}\n${o.description.split('\n').first}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            isThreeLine: true,
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('Balance', style: theme.textTheme.labelSmall),
                Text(
                  o.balance.format(),
                  key: Key('order-balance-${o.id}'),
                  style: theme.textTheme.titleSmall,
                ),
              ],
            ),
          ),
        ),
    ];
  }
}

class _RecentOrders extends ConsumerWidget {
  const _RecentOrders();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final closed = ref.watch(closedOrdersProvider);
    final theme = Theme.of(context);
    return closed.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _Failed(e),
      data: (orders) {
        if (orders.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No delivered or cancelled orders yet.',
                key: Key('recent-empty'),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            for (final o in orders)
              Card(
                key: Key('recent-${o.id}'),
                child: ListTile(
                  onTap: () => context.push(Routes.order(o.id)),
                  title: Text('${o.customer.name} · ${o.orderNo}'),
                  subtitle: Text(
                    '${shortDate(o.dueDate)}\n'
                    '${o.description.split('\n').first}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  isThreeLine: true,
                  trailing: Text(
                    o.status == OrderStatus.delivered
                        ? 'Delivered'
                        : 'Cancelled',
                    key: Key('recent-status-${o.id}'),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: o.status == OrderStatus.cancelled
                          ? theme.colorScheme.error
                          : const Color(0xFF1E6B2A),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
