import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';

import '../../app/messages.dart';
import '../../app/providers.dart';
import '../../app/router.dart';
import '../../widgets/date_bar.dart';
import '../../widgets/pos_scaffold.dart';
import '../../widgets/print_panel.dart';
import '../../widgets/section_card.dart';
import '../../widgets/total_row.dart';

/// One bill: lines, totals, payments, returns, and the actions the session
/// may take on it: reprint, same-day cancel with a reason (D-009, D-025),
/// and return (POS-6, POS-7).
class BillDetailScreen extends ConsumerStatefulWidget {
  const BillDetailScreen({required this.billId, super.key});

  final String billId;

  @override
  ConsumerState<BillDetailScreen> createState() => _BillDetailScreenState();
}

class _BillDetailScreenState extends ConsumerState<BillDetailScreen> {
  /// Set when the reason is confirmed and cleared when the call ends, so a
  /// second confirm can't send a second cancel.
  bool _cancelling = false;
  String? _error;

  void _reload() {
    ref
      ..invalidate(billProvider(widget.billId))
      ..invalidate(returnsForBillProvider(widget.billId));
  }

  Future<void> _cancel(Bill bill) async {
    if (_cancelling) return;
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _CancelDialog(bill: bill),
    );
    if (reason == null || !mounted || _cancelling) return;
    setState(() {
      _cancelling = true;
      _error = null;
    });
    String? error;
    try {
      await ref
          .read(salesServiceProvider)
          .cancelBill(billId: bill.id, reason: reason);
    } on DataFailure catch (e) {
      error = Messages.failure(e);
    } catch (_) {
      error = Messages.failure(const DataFailure(FailureReason.unknown));
    }
    if (!mounted) return;
    setState(() {
      _cancelling = false;
      _error = error;
    });
    // Reload either way: a failed cancel may still have been written, or
    // the bill may have changed elsewhere.
    _reload();
    if (error == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${bill.billNo} cancelled.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bill = ref.watch(billProvider(widget.billId));
    return PosScaffold(
      title: 'Bill',
      showDrawer: false,
      body: switch (bill) {
        // A reload after a cancel or a return keeps showing the old value.
        AsyncValue(value: final b?) => _body(context, b),
        AsyncValue(hasValue: true) => const Center(
          child: Text("This bill couldn't be found.", key: Key('not-found')),
        ),
        AsyncError() => Center(
          child: TextButton(
            onPressed: _reload,
            child: const Text("Couldn't load the bill. Tap to retry."),
          ),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Widget _body(BuildContext context, Bill bill) {
    final theme = Theme.of(context);
    final session = ref.watch(sessionProvider).value;
    final location = session?.location;
    final today = BusinessDate.of(ref.read(clockProvider)());
    final blocker = cancelBlocker(bill, today);
    final cancelled = bill.status == BillStatus.cancelled;
    final returnable = ReturnCalculator.returnable(bill);
    final anyReturnable = returnable.values.any((q) => q > 0);
    final canReturn = session?.can(Permission.returnCreate) ?? false;
    final canCancel = session?.can(Permission.billCancel) ?? false;
    final returns = ref.watch(returnsForBillProvider(bill.id)).value ?? [];

    // Not lazy: the page is short, and every action is always built.
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            bill.billNo,
            key: const Key('detail-bill-no'),
            style: theme.textTheme.headlineSmall,
          ),
          Text(
            '${formatBusinessDate(bill.businessDate)} · '
            '${formatIstTime(bill.clientCreatedAt)} · ${bill.servedBy.name}',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          if (cancelled)
            Card(
              key: const Key('cancelled-banner'),
              color: theme.colorScheme.errorContainer,
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'CANCELLED'
                  '${bill.cancel == null ? '' : ': ${bill.cancel!.reason}'}',
                  style: TextStyle(
                    color: theme.colorScheme.onErrorContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          SectionCard(
            title: 'Items',
            children: [
              for (final l in bill.lines)
                TotalRow(
                  '${l.name} × ${l.qty}'
                  '${(bill.returnedQty[l.productId] ?? 0) > 0 ? ' (${bill.returnedQty[l.productId]} returned)' : ''}',
                  l.lineTotal.format(),
                ),
              const Divider(),
              TotalRow('Subtotal', bill.subtotal.format()),
              if (bill.discount != null)
                TotalRow('Discount', (-bill.discount!.amount).format()),
              TotalRow('Round-off', bill.roundOff.format()),
              TotalRow(
                'Total',
                bill.total.format(),
                key: const Key('detail-total'),
                style: theme.textTheme.titleLarge,
              ),
            ],
          ),
          SectionCard(
            title: 'Payment',
            children: [
              for (final p in bill.payments)
                TotalRow(Messages.paymentMode(p.mode), p.amount.format()),
              if (bill.cashTendered != null)
                TotalRow('Cash tendered', bill.cashTendered!.format()),
            ],
          ),
          if (returns.isNotEmpty)
            SectionCard(
              title: 'Returns',
              children: [
                for (final r in returns)
                  Padding(
                    key: Key('return-${r.id}'),
                    padding: const EdgeInsets.only(bottom: 4),
                    child: TotalRow(
                      '${r.id} · ${formatBusinessDate(r.businessDate)}\n'
                      '${r.lines.map((l) => '${l.name} × ${l.qty}').join(', ')}',
                      (-r.refundTotal).format(),
                    ),
                  ),
              ],
            ),
          SectionCard(
            title: 'Receipt',
            children: [
              if (location != null) ...[
                PrintPanel(
                  key: const Key('reprint'),
                  label: 'Reprint',
                  job: (printer, location, {required printedBefore}) =>
                      printer.printBill(bill, location, reprint: true),
                ),
                TextButton.icon(
                  key: const Key('view-receipt'),
                  onPressed: () => showReceiptPreview(
                    context,
                    ref
                        .read(printerServiceProvider)
                        .previewBill(bill, location, reprint: true),
                  ),
                  icon: const Icon(Icons.receipt_long),
                  label: const Text('Receipt preview'),
                ),
              ],
            ],
          ),
          if (canReturn)
            _Action(
              button: FilledButton.tonalIcon(
                key: const Key('start-return'),
                onPressed: !cancelled && anyReturnable
                    ? () => context.push(Routes.billReturn(bill.id))
                    : null,
                icon: const Icon(Icons.assignment_return),
                label: const Text('Return items'),
              ),
              why: cancelled
                  ? Messages.returnError(ReturnError.billNotCompleted)
                  : anyReturnable
                  ? null
                  : 'Everything on this bill has been returned.',
              whyKey: 'return-blocked',
            ),
          if (canCancel)
            _Action(
              button: OutlinedButton.icon(
                key: const Key('cancel-bill'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                ),
                onPressed: blocker == null && !_cancelling
                    ? () => _cancel(bill)
                    : null,
                icon: _cancelling
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.block),
                label: const Text('Cancel bill'),
              ),
              why: blocker == null ? null : Messages.cancelBlocker(blocker),
              whyKey: 'cancel-blocked',
            ),
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
    );
  }
}

/// Asks for the cancel reason, which is required. Pops with the trimmed
/// reason, or null when dismissed.
class _CancelDialog extends StatefulWidget {
  const _CancelDialog({required this.bill});

  final Bill bill;

  @override
  State<_CancelDialog> createState() => _CancelDialogState();
}

class _CancelDialogState extends State<_CancelDialog> {
  final _reason = TextEditingController();
  bool _done = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _confirm() {
    final r = _reason.text.trim();
    if (_done || r.isEmpty) return;
    _done = true;
    Navigator.of(context).pop(r);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Cancel ${widget.bill.billNo}?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This reverses the whole bill (${widget.bill.total.format()}) '
            "and puts the items back in stock. It can't be undone.",
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('cancel-reason'),
            controller: _reason,
            autofocus: true,
            maxLength: 200,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Reason (required)'),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('cancel-dismiss'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Keep bill'),
        ),
        FilledButton(
          key: const Key('cancel-confirm'),
          onPressed: _reason.text.trim().isEmpty ? null : _confirm,
          child: const Text('Cancel bill'),
        ),
      ],
    );
  }
}

/// A full-width action button with the reason it's unavailable below it.
class _Action extends StatelessWidget {
  const _Action({
    required this.button,
    required this.why,
    required this.whyKey,
  });

  final Widget button;
  final String? why;
  final String whyKey;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          button,
          if (why != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: Text(
                why!,
                key: Key(whyKey),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}
