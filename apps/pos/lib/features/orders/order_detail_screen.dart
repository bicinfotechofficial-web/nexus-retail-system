import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MaxLengthEnforcement;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';

import '../../app/messages.dart';
import '../../app/providers.dart';
import '../../app/router.dart';
import '../../widgets/pos_scaffold.dart';
import '../../widgets/section_card.dart';
import '../../widgets/total_row.dart';
import 'order_summary.dart';

/// One pre-order in full (D-043): the whole description and the amounts,
/// with **Deliver** (the bill flow for the balance) and **Cancel** (a reason
/// and how much of the advance goes back) while it is open.
class OrderDetailScreen extends ConsumerWidget {
  const OrderDetailScreen({required this.orderId, super.key});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(orderProvider(orderId));
    final order = async.value;
    return PosScaffold(
      title: 'Order',
      showDrawer: false,
      body: async.hasError
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  Messages.anyError(async.error!),
                  key: const Key('order-error'),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : async.isLoading
          ? const Center(child: CircularProgressIndicator())
          : order == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  "That order couldn't be found.",
                  key: Key('order-missing'),
                ),
              ),
            )
          : _Body(order: order),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.order});

  final PreOrder order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final session = ref.watch(sessionProvider).value;
    final canManage = session?.can(Permission.orderManage) ?? false;
    final cancel = order.cancel;
    // A short page: build every part, so none is skipped as off screen.
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            order.orderNo,
            key: const Key('order-no'),
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 4),
          Text(
            switch (order.status) {
              OrderStatus.open => 'Open',
              OrderStatus.delivered => 'Delivered',
              OrderStatus.cancelled => 'Cancelled',
            },
            key: const Key('order-status'),
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              color: order.status == OrderStatus.cancelled
                  ? theme.colorScheme.error
                  : null,
            ),
          ),
          const SizedBox(height: 12),
          OrderSummary(order: order),
          if (cancel != null)
            SectionCard(
              title: 'Cancelled',
              children: [
                Text(cancel.reason, key: const Key('order-cancel-reason')),
                const SizedBox(height: 4),
                TotalRow(
                  'Refunded',
                  cancel.refunded.format(),
                  key: const Key('order-refunded'),
                ),
                TotalRow(
                  'Kept by the shop',
                  (order.advance - cancel.refunded).format(),
                  key: const Key('order-kept'),
                ),
              ],
            ),
          if (order.billId != null)
            SectionCard(
              title: 'Delivered',
              children: [
                Text('Bill ${order.billId}', key: const Key('order-bill')),
                if (session?.can(Permission.reportOwn) ?? false)
                  TextButton.icon(
                    key: const Key('view-bill'),
                    onPressed: () => context.push(Routes.bill(order.billId!)),
                    icon: const Icon(Icons.receipt_long),
                    label: const Text('View bill'),
                  ),
              ],
            ),
          if (order.isOpen && canManage) ...[
            const SizedBox(height: 4),
            OrderSlipButtons(order: order),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('deliver'),
              onPressed: () =>
                  context.push(Routes.deliver(order.id), extra: order),
              icon: const Icon(Icons.cake),
              label: Text(
                order.balance.isZero
                    ? 'Deliver (nothing to collect)'
                    : 'Deliver and collect ${order.balance.format()}',
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('cancel-order'),
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
              onPressed: () async {
                final cancelled = await showDialog<PreOrder>(
                  context: context,
                  builder: (_) => CancelOrderDialog(order: order),
                );
                if (cancelled != null && context.mounted) {
                  ref.invalidate(orderProvider(order.id));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Order cancelled.')),
                  );
                }
              },
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('Cancel order'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Asks for a reason (1 to [Limits.orderReasonMax] characters) and, when an
/// advance was paid, how much goes back to the customer: 0 up to the advance
/// in whole rupees. The shop keeps the rest (D-043). Pops the cancelled
/// order, or null when the manager keeps the order.
class CancelOrderDialog extends ConsumerStatefulWidget {
  const CancelOrderDialog({required this.order, super.key});

  final PreOrder order;

  @override
  ConsumerState<CancelOrderDialog> createState() => _CancelOrderDialogState();
}

class _CancelOrderDialogState extends ConsumerState<CancelOrderDialog> {
  final _reason = TextEditingController();
  final _refund = TextEditingController();
  bool _showErrors = false;
  bool _busy = false;
  bool _locked = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    _refund.dispose();
    super.dispose();
  }

  bool get _hasAdvance => widget.order.advance.isPositive;

  String? get _reasonError {
    final r = _reason.text.trim();
    if (r.isEmpty) return 'Enter a reason.';
    if (r.length > Limits.orderReasonMax) {
      return 'At most ${Limits.orderReasonMax} characters.';
    }
    return null;
  }

  Money? get _refundValue {
    if (!_hasAdvance) return Money.zero;
    final t = _refund.text.trim();
    if (t.isEmpty) return null;
    try {
      return Money.parse(t);
    } on FormatException {
      return null;
    }
  }

  String? get _refundError {
    if (!_hasAdvance) return null;
    if (_refund.text.trim().isEmpty) return 'Enter the refund, 0 if none.';
    final m = _refundValue;
    if (m == null) return 'Enter an amount, like 500.';
    return OrderValidator.refundError(m, widget.order.advance);
  }

  Future<void> _confirm() async {
    // Guard before any await, so a double tap cancels once.
    if (_busy || _locked) return;
    if (_reasonError != null || _refundError != null) {
      setState(() => _showErrors = true);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    PreOrder? cancelled;
    String? error;
    var lock = false;
    try {
      cancelled = await ref
          .read(orderServiceProvider)
          .cancel(
            orderId: widget.order.id,
            reason: _reason.text.trim(),
            refund: _refundValue!,
          );
    } on DataFailure catch (e) {
      error = Messages.failure(e);
      lock = e.reason == FailureReason.unknown;
    } on Object {
      error = Messages.failure(const DataFailure(FailureReason.unknown));
      lock = true;
    }
    if (!mounted) return;
    if (cancelled != null) {
      Navigator.of(context).pop(cancelled);
      return;
    }
    setState(() {
      _busy = false;
      _locked = lock;
      _error = lock
          ? '$error\nThe order may have been cancelled. Close this and '
                'check it before trying again.'
          : error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final o = widget.order;
    return AlertDialog(
      title: const Text('Cancel order'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('${o.orderNo} · ${o.customer.name}'),
            const SizedBox(height: 12),
            TextField(
              key: const Key('cancel-reason'),
              controller: _reason,
              maxLength: Limits.orderReasonMax,
              maxLengthEnforcement: MaxLengthEnforcement.none,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Reason',
                errorText: _showErrors || _reason.text.isNotEmpty
                    ? _reasonError
                    : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (_hasAdvance) ...[
              const SizedBox(height: 8),
              Text(
                'Advance paid: ${o.advance.format()}. Hand back all, some or '
                'none of it; the shop keeps the rest.',
                key: const Key('cancel-advance-note'),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('cancel-refund'),
                controller: _refund,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Refund to the customer (₹)',
                  errorText: _showErrors || _refund.text.isNotEmpty
                      ? _refundError
                      : null,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  key: const Key('cancel-error'),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('cancel-keep'),
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Keep order'),
        ),
        FilledButton(
          key: const Key('cancel-confirm'),
          onPressed: _busy || _locked ? null : _confirm,
          child: const Text('Cancel order'),
        ),
      ],
    );
  }
}
