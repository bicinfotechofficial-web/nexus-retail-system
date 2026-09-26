import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';

import '../../app/messages.dart';
import '../../app/providers.dart';
import '../../widgets/pos_scaffold.dart';
import '../../widgets/print_panel.dart';
import '../../widgets/section_card.dart';
import '../../widgets/total_row.dart';

class _RefundRow {
  _RefundRow(this.mode, String amount)
    : amount = TextEditingController(text: amount);

  PaymentMode mode;
  final TextEditingController amount;
}

/// A return against one bill (POS-8): quantities capped by
/// `ReturnCalculator.returnable`, the refund from `ReturnCalculator.compute`,
/// a refund split checked with `checkRefunds`, and a required reason. Save
/// disables on the first tap and calls `createReturn` once, then the return
/// slip prints.
class ReturnScreen extends ConsumerWidget {
  const ReturnScreen({required this.billId, super.key});

  final String billId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // While the bill reloads after Save, the previous value is kept, so the
    // form (and its saved state) stays; the form itself keeps the bill it
    // opened with.
    final bill = ref.watch(billProvider(billId));
    return switch (bill) {
      AsyncValue(value: final b?) => _ReturnForm(bill: b),
      AsyncValue(hasValue: true) => const PosScaffold(
        title: 'Return',
        showDrawer: false,
        body: Center(child: Text("This bill couldn't be found.")),
      ),
      AsyncError() => const PosScaffold(
        title: 'Return',
        showDrawer: false,
        body: Center(child: Text("Couldn't load the bill. Go back and retry.")),
      ),
      _ => const PosScaffold(
        title: 'Return',
        showDrawer: false,
        body: Center(child: CircularProgressIndicator()),
      ),
    };
  }
}

class _ReturnForm extends ConsumerStatefulWidget {
  const _ReturnForm({required this.bill});

  final Bill bill;

  @override
  ConsumerState<_ReturnForm> createState() => _ReturnFormState();
}

class _ReturnFormState extends ConsumerState<_ReturnForm> {
  /// The bill as it was when the form opened. Later reloads don't change it.
  late final Bill _bill = widget.bill;
  late final Map<String, int> _returnable = ReturnCalculator.returnable(_bill);
  final Map<String, int> _qty = {};
  final List<_RefundRow> _rows = [];
  final _reason = TextEditingController();

  /// While false, the single refund row follows the refund total.
  bool _amountsEdited = false;
  bool _saving = false;

  /// Set when a save failed in a way that leaves it unclear whether the
  /// return was written.
  bool _locked = false;
  String? _error;
  SaleReturn? _saved;

  @override
  void initState() {
    super.initState();
    final mode = _bill.payments.isEmpty
        ? PaymentMode.cash
        : _bill.payments.first.mode;
    _rows.add(_RefundRow(mode, ''));
  }

  @override
  void dispose() {
    _reason.dispose();
    for (final r in _rows) {
      r.amount.dispose();
    }
    super.dispose();
  }

  static String _plain(Money m) => m.format(symbol: '');

  static Money? _tryMoney(String text) {
    final t = text.trim();
    if (t.isEmpty) return null;
    try {
      return Money.parse(t);
    } on FormatException {
      return null;
    }
  }

  _Form _form() {
    final wanted = {
      for (final e in _qty.entries)
        if (e.value > 0) e.key: e.value,
    };
    ReturnTotals? totals;
    String? returnError;
    if (wanted.isNotEmpty) {
      try {
        totals = ReturnCalculator.compute(_bill, wanted);
      } on ReturnValidationException catch (e) {
        returnError = Messages.returnError(e.error);
      }
    }
    // A zero refund (possible after rounding) takes no refund entries.
    final refunds = totals == null || totals.refundTotal.isZero
        ? const <Payment>[]
        : [
            for (final r in _rows)
              Payment(
                mode: r.mode,
                amount: _tryMoney(r.amount.text) ?? Money.zero,
              ),
          ];
    final refundErrors = totals == null
        ? const <RefundError>{}
        : ReturnCalculator.checkRefunds(totals.refundTotal, refunds);
    return _Form(
      wanted: wanted,
      totals: totals,
      returnError: returnError,
      refunds: refunds,
      refundErrors: refundErrors,
      reason: _reason.text.trim(),
    );
  }

  /// Keeps a single, untouched refund row equal to the refund total.
  void _followTotal() {
    if (_amountsEdited || _rows.length != 1) return;
    final total = _form().totals?.refundTotal;
    _rows.single.amount.text = total == null ? '' : _plain(total);
  }

  void _setQty(String productId, int qty) {
    final max = _returnable[productId] ?? 0;
    setState(() {
      _qty[productId] = qty.clamp(0, max);
      _followTotal();
    });
  }

  void _addRow(_Form form) {
    final used = _rows.map((r) => r.mode).toSet();
    final mode = PaymentMode.values.firstWhere(
      (m) => !used.contains(m),
      orElse: () => PaymentMode.other,
    );
    var remaining = form.totals?.refundTotal ?? Money.zero;
    for (final r in form.refunds) {
      remaining -= r.amount;
    }
    setState(() {
      _amountsEdited = true;
      _rows.add(
        _RefundRow(mode, remaining.isPositive ? _plain(remaining) : ''),
      );
    });
  }

  void _removeRow(int i) {
    setState(() {
      _amountsEdited = true;
      _rows.removeAt(i).amount.dispose();
    });
  }

  Future<void> _save(_Form form) async {
    // Guard before any await: a second tap in the same frame still sees the
    // old, enabled button (03-SYNC §4).
    if (_saving || _locked || !form.canSave) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final SaleReturn ret;
    try {
      ret = await ref
          .read(salesServiceProvider)
          .createReturn(
            billId: _bill.id,
            qtyByProduct: form.wanted,
            refunds: form.refunds,
            reason: form.reason,
          );
    } on ReturnValidationException catch (e) {
      _failed(Messages.returnError(e.error));
      return;
    } on DataFailure catch (e) {
      _failed(Messages.failure(e), lock: e.reason == FailureReason.unknown);
      return;
    } catch (_) {
      _failed(
        Messages.failure(const DataFailure(FailureReason.unknown)),
        lock: true,
      );
      return;
    }
    if (!mounted) return;
    setState(() => _saved = ret);
    ref
      ..invalidate(billProvider(_bill.id))
      ..invalidate(returnsForBillProvider(_bill.id));
  }

  void _failed(String message, {bool lock = false}) {
    if (!mounted) return;
    setState(() {
      _saving = false;
      _locked = lock;
      _error = lock
          ? '$message\nThe return may have been saved. Go back and check '
                "this bill's returns before trying again."
          : message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final saved = _saved;
    if (saved != null) return _savedView(context, saved);
    final theme = Theme.of(context);
    final form = _form();
    final totals = form.totals;

    return PosScaffold(
      title: 'Return · ${_bill.billNo}',
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
                  key: const Key('return-error'),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            FilledButton.icon(
              key: const Key('save-return'),
              onPressed: form.canSave && !_saving && !_locked
                  ? () => _save(form)
                  : null,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: Text(
                totals == null
                    ? 'Save return'
                    : 'Refund ${totals.refundTotal.format()}',
              ),
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
              title: 'Items to return',
              children: [
                for (final l in _bill.lines) _lineRow(theme, l),
                if (form.returnError != null)
                  Text(
                    form.returnError!,
                    key: const Key('return-calc-error'),
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
              ],
            ),
            if (totals != null) ...[
              SectionCard(
                title: 'Refund',
                children: [
                  for (final l in totals.lines)
                    TotalRow('${l.name} × ${l.qty}', l.amount.format()),
                  const Divider(),
                  TotalRow(
                    'Refund total',
                    totals.refundTotal.format(),
                    key: const Key('refund-total'),
                    style: theme.textTheme.titleLarge,
                  ),
                  if (!totals.refundTotal.isZero) ...[
                    const SizedBox(height: 8),
                    ..._refundRows(form),
                  ],
                ],
              ),
              SectionCard(
                title: 'Reason',
                children: [
                  TextField(
                    key: const Key('return-reason'),
                    controller: _reason,
                    maxLength: 200,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Reason (required)',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _lineRow(ThemeData theme, BillLine l) {
    final max = _returnable[l.productId] ?? 0;
    final qty = _qty[l.productId] ?? 0;
    final returned = _bill.returnedQty[l.productId] ?? 0;
    return Padding(
      key: Key('ret-line-${l.productId}'),
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.name),
                Text(
                  max == 0
                      ? 'All ${l.qty} returned'
                      : 'Sold ${l.qty}'
                            '${returned > 0 ? ', $returned returned' : ''}'
                            ' · up to $max',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            key: Key('ret-minus-${l.productId}'),
            tooltip: 'One less',
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: qty > 0 ? () => _setQty(l.productId, qty - 1) : null,
          ),
          SizedBox(
            width: 32,
            child: Text(
              '$qty',
              key: Key('ret-qty-${l.productId}'),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
          ),
          IconButton(
            key: Key('ret-plus-${l.productId}'),
            tooltip: 'One more',
            icon: const Icon(Icons.add_circle_outline),
            onPressed: qty < max ? () => _setQty(l.productId, qty + 1) : null,
          ),
        ],
      ),
    );
  }

  List<Widget> _refundRows(_Form form) {
    final theme = Theme.of(context);
    return [
      for (var i = 0; i < _rows.length; i++)
        Padding(
          key: ObjectKey(_rows[i]),
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              SizedBox(
                width: 132,
                child: DropdownButtonFormField<PaymentMode>(
                  key: Key('refund-mode-$i'),
                  isExpanded: true,
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 16,
                    ),
                  ),
                  initialValue: _rows[i].mode,
                  items: [
                    for (final m in PaymentMode.values)
                      DropdownMenuItem(
                        value: m,
                        child: Text(Messages.paymentMode(m)),
                      ),
                  ],
                  onChanged: (m) {
                    if (m != null) setState(() => _rows[i].mode = m);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  key: Key('refund-amount-$i'),
                  controller: _rows[i].amount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Refund (₹)'),
                  onChanged: (_) => setState(() => _amountsEdited = true),
                ),
              ),
              if (_rows.length > 1)
                IconButton(
                  key: Key('refund-remove-$i'),
                  tooltip: 'Remove refund',
                  icon: const Icon(Icons.close),
                  onPressed: () => _removeRow(i),
                ),
            ],
          ),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: const Key('add-refund'),
          onPressed: _rows.length < Limits.maxRefunds
              ? () => _addRow(form)
              : null,
          icon: const Icon(Icons.add),
          label: const Text('Split refund'),
        ),
      ),
      for (final e in form.refundErrors)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            Messages.refundError(e),
            key: Key('refund-error-${e.name}'),
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ),
    ];
  }

  Widget _savedView(BuildContext context, SaleReturn ret) {
    final theme = Theme.of(context);
    final location = ref.watch(sessionProvider).value?.location;
    return PosScaffold(
      title: 'Return saved',
      showDrawer: false,
      bottom: Padding(
        padding: const EdgeInsets.all(12),
        child: FilledButton(
          key: const Key('return-done'),
          onPressed: () => context.pop(),
          child: const Text('Back to bill'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Icon(Icons.check_circle, size: 64, color: Color(0xFF1E6B2A)),
          const SizedBox(height: 8),
          Text(
            ret.id,
            key: const Key('return-id'),
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
          Text(
            'Against ${ret.billNo}',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          TotalRow(
            'Refund',
            ret.refundTotal.format(),
            key: const Key('saved-refund'),
            style: theme.textTheme.titleLarge,
          ),
          for (final r in ret.refunds)
            TotalRow(Messages.paymentMode(r.mode), r.amount.format()),
          const SizedBox(height: 24),
          PrintPanel(
            label: 'Print return slip',
            autoStart: true,
            savedWhat: 'return',
            job: (printer, location, {required printedBefore}) =>
                printer.printReturn(ret, _bill, location),
          ),
          if (location != null) ...[
            const SizedBox(height: 24),
            Text('Return slip preview', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            ReceiptPreview(
              ref
                  .read(printerServiceProvider)
                  .previewReturn(ret, _bill, location),
            ),
          ],
        ],
      ),
    );
  }
}

final class _Form {
  const _Form({
    required this.wanted,
    required this.totals,
    required this.returnError,
    required this.refunds,
    required this.refundErrors,
    required this.reason,
  });

  final Map<String, int> wanted;
  final ReturnTotals? totals;
  final String? returnError;
  final List<Payment> refunds;
  final Set<RefundError> refundErrors;
  final String reason;

  bool get canSave =>
      totals != null &&
      returnError == null &&
      refundErrors.isEmpty &&
      reason.isNotEmpty;
}
