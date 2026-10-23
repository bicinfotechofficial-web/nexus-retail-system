import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus_core/nexus_core.dart';

import '../../app/messages.dart';
import '../../app/providers.dart';
import '../../widgets/print_panel.dart';
import '../../widgets/section_card.dart';
import 'due_counts.dart';

/// The seeded open-price product a delivery bills (D-043), and the name the
/// delivery page shows for it.
const String customCakeProductId = 'CUSTOM-CAKE';
const String customCakeName = 'Custom cake';

/// The order's customer, due date, description and amounts: the same facts
/// on the saved page and the detail page (D-043).
class OrderSummary extends ConsumerWidget {
  const OrderSummary({required this.order, super.key});

  final PreOrder order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = order.customer;
    final today = BusinessDate.of(ref.read(clockProvider)());
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          title: 'Customer',
          children: [
            _Fact('Name', c.name, key: const Key('order-customer')),
            _Fact('Mobile', c.phone, key: const Key('order-phone')),
            _Fact(
              'WhatsApp',
              c.whatsapp == null
                  ? 'No WhatsApp'
                  : c.whatsapp == c.phone
                  ? 'Same as mobile'
                  : c.whatsapp!,
              key: const Key('order-whatsapp'),
            ),
          ],
        ),
        SectionCard(
          title: 'Cake',
          children: [
            _Fact(
              'Due',
              order.status == OrderStatus.open
                  ? dueLabel(order, today)
                  : '${shortDate(order.dueDate)}, '
                        '${order.dueTime ?? 'no time set'}',
              key: const Key('order-due'),
            ),
            const SizedBox(height: 4),
            Text(
              order.description,
              key: const Key('order-description'),
              style: theme.textTheme.bodyLarge,
            ),
          ],
        ),
        SectionCard(
          title: 'Amounts',
          children: [
            _Fact(
              'Agreed price',
              order.price.format(),
              key: const Key('order-price'),
            ),
            _Fact(
              order.advanceMode == null
                  ? 'Advance paid'
                  : 'Advance paid (${Messages.paymentMode(order.advanceMode!)})',
              order.advance.format(),
              key: const Key('order-advance'),
            ),
            const Divider(),
            _Fact(
              'Balance to collect',
              order.balance.format(),
              key: const Key('order-balance'),
              style: theme.textTheme.titleMedium,
            ),
          ],
        ),
      ],
    );
  }
}

/// Print and share the advance slip of an order (D-043), through the
/// `OrderSlipActions` seam. The order is already saved, so a printer fault
/// offers a retry, and a share that fails only shows a message.
class OrderSlipButtons extends ConsumerStatefulWidget {
  const OrderSlipButtons({required this.order, super.key});

  final PreOrder order;

  @override
  ConsumerState<OrderSlipButtons> createState() => _OrderSlipButtonsState();
}

class _OrderSlipButtonsState extends ConsumerState<OrderSlipButtons> {
  bool _sharing = false;
  String? _problem;

  Future<void> _share() async {
    if (_sharing) return;
    final location = ref.read(sessionProvider).value?.location;
    if (location == null) {
      setState(() => _problem = 'No store is set for this login.');
      return;
    }
    setState(() {
      _sharing = true;
      _problem = null;
    });
    String? problem;
    try {
      await ref
          .read(orderSlipActionsProvider)
          .shareImage(widget.order, location);
    } on Object {
      problem = "Couldn't share the slip image. Please try again.";
    }
    if (!mounted) return;
    setState(() {
      _sharing = false;
      _problem = problem;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PrintPanel(
          label: 'Print advance slip',
          savedWhat: 'order',
          noun: 'slip',
          job: (printer, location, {required printedBefore}) =>
              ref.read(orderSlipActionsProvider).print(widget.order, location),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const Key('share-slip'),
          onPressed: _sharing ? null : _share,
          icon: _sharing
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.image_outlined),
          label: const Text('Share slip image'),
        ),
        if (_problem != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _problem!,
              key: const Key('slip-problem'),
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }
}

/// A label on the left and its value on the right, the value wrapping when
/// it is long (a date and time, a WhatsApp number).
class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value, {this.style, super.key});

  final String label;
  final String value;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: style),
          const SizedBox(width: 12),
          Expanded(
            child: Text(value, textAlign: TextAlign.end, style: style),
          ),
        ],
      ),
    );
  }
}
