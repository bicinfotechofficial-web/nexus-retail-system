import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';

import '../../app/messages.dart';
import '../../app/providers.dart';
import '../../app/router.dart';
import '../../widgets/pos_scaffold.dart';
import '../../widgets/total_row.dart';
import '../billing/cart.dart';

enum _DiscountKind { none, flat, percent }

class _PaymentRow {
  _PaymentRow(this.mode, String amount)
    : amount = TextEditingController(text: amount);

  PaymentMode mode;
  final TextEditingController amount;
}

/// Discount, round-off, split payment, cash tendered and change, then Save
/// (POS-5). Every amount comes from `BillCalculator`; Save is enabled only
/// when `checkPayments(...).isValid`, and disables on the first tap
/// (03-SYNC §4).
class PaymentScreen extends ConsumerStatefulWidget {
  const PaymentScreen({super.key});

  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  /// The cart can't change on this screen, so it's read once. Clearing it
  /// after Save doesn't disturb the page while it animates away.
  late final List<CartLine> _cart;
  late final Location? _location;

  _DiscountKind _discountKind = _DiscountKind.none;
  final _discount = TextEditingController();
  final _tendered = TextEditingController();
  final List<_PaymentRow> _rows = [];

  /// While false, the single payment row follows the bill total.
  bool _amountsEdited = false;

  /// Set on the first Save tap and never cleared on success.
  bool _saving = false;

  /// Set when a save failed in a way that leaves it unclear whether the bill
  /// was written; retrying could then create a second bill.
  bool _locked = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cart = ref.read(cartProvider);
    _location = ref.read(sessionProvider).value?.location;
    final total = _form().totals?.total ?? Money.zero;
    _rows.add(_PaymentRow(PaymentMode.cash, _plain(total)));
  }

  @override
  void dispose() {
    _discount.dispose();
    _tendered.dispose();
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

  /// Everything derived from the current inputs.
  _Form _form() {
    final cap = _location?.maxDiscountPct;
    String? discountError;
    DiscountInput? discount;
    final text = _discount.text.trim();
    if (text.isNotEmpty) {
      switch (_discountKind) {
        case _DiscountKind.none:
          break;
        case _DiscountKind.flat:
          final m = _tryMoney(text);
          if (m == null) {
            discountError = 'Enter an amount, like 50 or 49.50.';
          } else {
            discount = DiscountInput.flat(m);
          }
        case _DiscountKind.percent:
          final pct = int.tryParse(text);
          if (pct == null) {
            discountError = 'Enter a whole percentage, like 5.';
          } else {
            discount = DiscountInput.percent(pct);
          }
      }
    }

    BillTotals? totals;
    if (_cart.isNotEmpty) {
      try {
        totals = BillCalculator.compute(
          _cart,
          discount: discount,
          maxDiscountPct: cap,
        );
      } on BillValidationException catch (e) {
        discountError = Messages.billError(e.error, maxDiscountPct: cap);
        discount = null;
        totals = BillCalculator.compute(_cart, maxDiscountPct: cap);
      }
    }
    if (discountError != null) discount = null;

    final payments = [
      for (final r in _rows)
        Payment(mode: r.mode, amount: _tryMoney(r.amount.text) ?? Money.zero),
    ];
    final tenderedText = _tendered.text.trim();
    final hasCash = _rows.any((r) => r.mode == PaymentMode.cash);
    final tendered = hasCash ? _tryMoney(tenderedText) : null;
    final tenderedError = hasCash && tenderedText.isNotEmpty && tendered == null
        ? 'Enter an amount, like 500.'
        : null;
    final check = totals == null
        ? null
        : BillCalculator.checkPayments(
            totals.total,
            payments,
            cashTendered: tendered,
          );
    return _Form(
      discount: discount,
      discountError: discountError,
      totals: totals,
      payments: payments,
      tendered: tendered,
      tenderedError: tenderedError,
      check: check,
    );
  }

  /// Keeps a single, untouched payment row equal to the bill total.
  void _followTotal() {
    if (_amountsEdited || _rows.length != 1) return;
    final total = _form().totals?.total;
    if (total != null) _rows.single.amount.text = _plain(total);
  }

  void _onDiscountChanged() {
    setState(_followTotal);
  }

  void _addRow(_Form form) {
    final used = _rows.map((r) => r.mode).toSet();
    final mode = PaymentMode.values.firstWhere(
      (m) => !used.contains(m),
      orElse: () => PaymentMode.other,
    );
    final remaining = form.check?.remaining ?? Money.zero;
    setState(() {
      _amountsEdited = true;
      _rows.add(
        _PaymentRow(mode, remaining.isPositive ? _plain(remaining) : ''),
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
    if (_saving || _locked) return;
    final totals = form.totals;
    if (totals == null || !form.canSave) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final Bill bill;
    try {
      bill = await ref
          .read(salesServiceProvider)
          .createBill(
            NewBill(
              cart: _cart,
              discount: form.discount,
              payments: form.payments,
              cashTendered: form.tendered,
            ),
          );
    } on BillValidationException catch (e) {
      _failed(
        Messages.billError(e.error, maxDiscountPct: _location?.maxDiscountPct),
      );
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
    context.go(Routes.billSaved, extra: bill);
    ref.read(cartProvider.notifier).clear();
  }

  void _failed(String message, {bool lock = false}) {
    if (!mounted) return;
    setState(() {
      _saving = false;
      _locked = lock;
      _error = lock
          ? "$message\nThe bill may have been saved. Check today's bills "
                'before billing these items again.'
          : message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final form = _form();
    final totals = form.totals;
    final location = _location;
    final theme = Theme.of(context);
    if (totals == null || location == null) {
      return const PosScaffold(
        title: 'Payment',
        showDrawer: false,
        body: Center(child: Text('The cart is empty.')),
      );
    }
    final check = form.check!;
    final cap = location.maxDiscountPct;
    final hasCash = _rows.any((r) => r.mode == PaymentMode.cash);

    return PosScaffold(
      title: 'Payment',
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
            FilledButton.icon(
              key: const Key('save'),
              onPressed: form.canSave && !_saving && !_locked
                  ? () => _save(form)
                  : null,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: Text('Save ${totals.total.format()}'),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Section(
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
                    key: const Key('discount-amount'),
                  ),
                TotalRow(
                  'Round-off',
                  totals.roundOff.format(),
                  key: const Key('round-off'),
                ),
                TotalRow(
                  'Total',
                  totals.total.format(),
                  key: const Key('total'),
                  style: theme.textTheme.titleLarge,
                ),
              ],
            ),
            _Section(
              title: 'Discount',
              children: [
                SegmentedButton<_DiscountKind>(
                  segments: const [
                    ButtonSegment(
                      value: _DiscountKind.none,
                      label: Text('None'),
                    ),
                    ButtonSegment(
                      value: _DiscountKind.flat,
                      label: Text('₹ Flat'),
                    ),
                    ButtonSegment(
                      value: _DiscountKind.percent,
                      label: Text('% Off'),
                    ),
                  ],
                  selected: {_discountKind},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) {
                    _discountKind = s.single;
                    _discount.clear();
                    _onDiscountChanged();
                  },
                ),
                if (_discountKind != _DiscountKind.none) ...[
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('discount-input'),
                    controller: _discount,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: _discountKind == _DiscountKind.flat
                          ? 'Discount (₹)'
                          : 'Discount (%)',
                      helperText: cap == null
                          ? null
                          : 'Up to $cap% at this store',
                      errorText: form.discountError,
                    ),
                    onChanged: (_) => _onDiscountChanged(),
                  ),
                ],
              ],
            ),
            _Section(
              title: 'Payment',
              children: [
                for (var i = 0; i < _rows.length; i++)
                  Padding(
                    key: ObjectKey(_rows[i]),
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      key: Key('payment-row-$i'),
                      children: [
                        SizedBox(
                          width: 132,
                          child: DropdownButtonFormField<PaymentMode>(
                            key: Key('payment-mode-$i'),
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
                            key: Key('payment-amount-$i'),
                            controller: _rows[i].amount,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Amount (₹)',
                            ),
                            onChanged: (_) =>
                                setState(() => _amountsEdited = true),
                          ),
                        ),
                        if (_rows.length > 1)
                          IconButton(
                            key: Key('payment-remove-$i'),
                            tooltip: 'Remove payment',
                            icon: const Icon(Icons.close),
                            onPressed: () => _removeRow(i),
                          ),
                      ],
                    ),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const Key('add-payment'),
                    onPressed: _rows.length < BillCalculator.maxPayments
                        ? () => _addRow(form)
                        : null,
                    icon: const Icon(Icons.add),
                    label: const Text('Split payment'),
                  ),
                ),
                TotalRow('Paid', check.paid.format(), key: const Key('paid')),
                if (!check.remaining.isZero)
                  TotalRow(
                    check.remaining.isNegative ? 'Over by' : 'Remaining',
                    (check.remaining.isNegative
                            ? -check.remaining
                            : check.remaining)
                        .format(),
                    key: const Key('remaining'),
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                for (final e in check.errors)
                  if (e != PaymentError.tenderedTooLow &&
                      e != PaymentError.tenderedWithoutCash)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        Messages.paymentError(e),
                        key: Key('payment-error-${e.name}'),
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
              ],
            ),
            if (hasCash)
              _Section(
                title: 'Cash',
                children: [
                  TextField(
                    key: const Key('cash-tendered'),
                    controller: _tendered,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Cash tendered (₹)',
                      errorText:
                          form.tenderedError ??
                          (check.errors.contains(PaymentError.tenderedTooLow)
                              ? Messages.paymentError(
                                  PaymentError.tenderedTooLow,
                                )
                              : null),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  if (check.change != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: TotalRow(
                        'Change to return',
                        check.change!.format(),
                        key: const Key('change'),
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

final class _Form {
  const _Form({
    required this.discount,
    required this.discountError,
    required this.totals,
    required this.payments,
    required this.tendered,
    required this.tenderedError,
    required this.check,
  });

  final DiscountInput? discount;
  final String? discountError;
  final BillTotals? totals;
  final List<Payment> payments;
  final Money? tendered;
  final String? tenderedError;
  final PaymentCheck? check;

  bool get canSave =>
      totals != null &&
      discountError == null &&
      tenderedError == null &&
      (check?.isValid ?? false);
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}
