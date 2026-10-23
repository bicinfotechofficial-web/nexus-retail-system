import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:nexus_core/nexus_core.dart';

import '../../app/destinations.dart';
import '../../widgets/pos_scaffold.dart';
import 'order_summary.dart';

/// Shown after an order is saved (D-043). The order is stored already, so the
/// advance slip is an optional follow-up: print it, share its image, or
/// just go on.
class OrderSavedScreen extends StatelessWidget {
  const OrderSavedScreen({required this.order, super.key});

  final PreOrder order;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PosScaffold(
      title: 'Order saved',
      showDrawer: false,
      bottom: Padding(
        padding: const EdgeInsets.all(12),
        child: FilledButton.icon(
          key: const Key('order-done'),
          onPressed: () => context.go(Destinations.orders.path),
          icon: const Icon(Icons.check),
          label: const Text('Done'),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.check_circle, size: 64, color: Color(0xFF1E6B2A)),
            const SizedBox(height: 8),
            Text(
              order.orderNo,
              key: const Key('order-no'),
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            OrderSlipButtons(order: order),
            const SizedBox(height: 16),
            OrderSummary(order: order),
          ],
        ),
      ),
    );
  }
}
