import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexus_core/nexus_core.dart';

import '../../app/destinations.dart';
import '../../app/providers.dart';
import 'due_counts.dart';

/// The banner on the home screen when orders are due soon (D-043), such as
/// "2 orders due today, 1 tomorrow, 1 overdue". Tapping it opens the Orders
/// screen; the cross hides it until the app is opened again. Reminders live
/// in the app only: no push and no phone notification.
class OrderBanner extends ConsumerWidget {
  const OrderBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider).value;
    if (session == null ||
        !session.can(Permission.orderManage) ||
        ref.watch(orderBannerDismissedProvider)) {
      return const SizedBox.shrink();
    }
    final counts = watchDueCounts(ref);
    final message = counts.message;
    if (message == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final urgent = counts.overdue > 0;
    final color = urgent ? scheme.errorContainer : scheme.tertiaryContainer;
    final onColor = urgent
        ? scheme.onErrorContainer
        : scheme.onTertiaryContainer;
    return Material(
      color: color,
      child: InkWell(
        key: const Key('order-banner'),
        onTap: () => context.go(Destinations.orders.path),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
          child: Row(
            children: [
              Icon(Icons.event_note, color: onColor, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  key: const Key('order-banner-text'),
                  style: TextStyle(color: onColor, fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                key: const Key('order-banner-dismiss'),
                tooltip: 'Hide until the app is opened again',
                icon: Icon(Icons.close, color: onColor),
                onPressed: () =>
                    ref.read(orderBannerDismissedProvider.notifier).dismiss(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The Orders entry in the home screen's app bar, with the count of orders
/// due soon (overdue, today and tomorrow) as a badge.
class OrdersAction extends ConsumerWidget {
  const OrdersAction({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider).value;
    if (session == null || !session.can(Permission.orderManage)) {
      return const SizedBox.shrink();
    }
    final due = watchDueCounts(ref).attention;
    return IconButton(
      key: const Key('orders-entry'),
      tooltip: 'Orders',
      onPressed: () => context.go(Destinations.orders.path),
      icon: Badge(
        key: const Key('orders-entry-badge'),
        isLabelVisible: due > 0,
        label: Text('$due'),
        child: const Icon(Icons.event_note),
      ),
    );
  }
}
