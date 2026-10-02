import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';

import '../../app/messages.dart';
import '../../app/router.dart';
import '../../app/settings.dart';
import '../../widgets/pos_scaffold.dart';
import '../../widgets/section_card.dart';
import '../../widgets/total_row.dart';
import '../billing/cart.dart';
import 'submit.dart';

/// What the payment page hands to the review (D-035).
final class ReviewArgs {
  const ReviewArgs({
    required this.bill,
    required this.totals,
    required this.check,
    required this.maxDiscountPct,
    required this.onLocked,
  });

  final NewBill bill;
  final BillTotals totals;
  final PaymentCheck check;
  final int? maxDiscountPct;

  /// Called when a save failed so that it is unclear whether the bill was
  /// written. The payment page then stops offering another save.
  final void Function(String message) onLocked;
}

/// A read-only look at the bill before it is committed: Back returns to the
/// payment page with everything still entered, Confirm saves once. A bill
/// can't be edited afterwards, only cancelled the same day, so this is the
/// place to catch a wrong number or amount.
class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({required this.args, super.key});

  final ReviewArgs args;

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  /// Set on the first Confirm tap and never cleared on success.
  bool _saving = false;
  bool _locked = false;
  bool _dontShowAgain = false;
  String? _error;

  Future<void> _confirm() async {
    // Guard before any await: a second tap in the same frame still sees the
    // old, enabled button (03-SYNC §4).
    if (_saving || _locked) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final args = widget.args;
    final result = await submitBill(
      ref,
      args.bill,
      maxDiscountPct: args.maxDiscountPct,
    );
    if (!mounted) return;
    final bill = result.bill;
    if (bill == null) {
      setState(() {
        _saving = false;
        _locked = result.lock;
        _error = result.message;
      });
      if (result.lock) args.onLocked(result.message!);
      return;
    }
    if (_dontShowAgain) {
      await ref.read(reviewBeforeSaveProvider.notifier).set(false);
      if (!mounted) return;
    }
    context.go(Routes.billSaved, extra: bill);
    ref.read(cartProvider.notifier).clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final args = widget.args;
    final totals = args.totals;
    final customer = args.bill.customer;
    final change = args.check.change;
    final whatsapp = customer.whatsapp == null
        ? 'No WhatsApp'
        : customer.whatsapp == customer.phone
        ? 'Same as mobile'
        : customer.whatsapp!;
    return PopScope(
      canPop: !_saving,
      child: PosScaffold(
        title: 'Review bill',
        showDrawer: false,
        bottom: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _error!,
                    key: const Key('save-error'),
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              CheckboxListTile(
                key: const Key('dont-show-again'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _dontShowAgain,
                onChanged: _saving
                    ? null
                    : (v) => setState(() => _dontShowAgain = v ?? false),
                title: const Text("Don't show this review again"),
                subtitle: const Text('You can turn it back on in Settings.'),
              ),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('review-back'),
                      onPressed: _saving ? null : () => context.pop(),
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Back'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      key: const Key('confirm'),
                      onPressed: !_saving && !_locked ? _confirm : null,
                      icon: _saving
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check),
                      label: Text('Confirm ${totals.total.format()}'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionCard(
                title: 'Customer',
                children: [
                  TotalRow(
                    'Name',
                    customer.name,
                    key: const Key('review-customer-name'),
                  ),
                  TotalRow(
                    'Mobile',
                    customer.phone,
                    key: const Key('review-customer-phone'),
                  ),
                  TotalRow(
                    'WhatsApp',
                    whatsapp,
                    key: const Key('review-customer-whatsapp'),
                  ),
                ],
              ),
              SectionCard(
                title: 'Bill',
                children: [
                  for (final l in totals.lines)
                    TotalRow('${l.name} × ${l.qty}', l.lineTotal.format()),
                  const Divider(),
                  TotalRow('Subtotal', totals.subtotal.format()),
                  if (totals.discount != null)
                    TotalRow(
                      'Discount',
                      (-totals.discount!.amount).format(),
                      key: const Key('review-discount'),
                    ),
                  TotalRow(
                    'Round-off',
                    totals.roundOff.format(),
                    key: const Key('review-round-off'),
                  ),
                  TotalRow(
                    'Total',
                    totals.total.format(),
                    key: const Key('review-total'),
                    style: theme.textTheme.titleLarge,
                  ),
                ],
              ),
              SectionCard(
                title: 'Payment',
                children: [
                  for (final p in args.bill.payments)
                    TotalRow(Messages.paymentMode(p.mode), p.amount.format()),
                  if (args.bill.cashTendered != null)
                    TotalRow(
                      'Cash tendered',
                      args.bill.cashTendered!.format(),
                      key: const Key('review-tendered'),
                    ),
                  if (change != null)
                    TotalRow(
                      'Change to return',
                      change.format(),
                      key: const Key('review-change'),
                      style: theme.textTheme.titleLarge,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
