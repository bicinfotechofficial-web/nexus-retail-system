import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MaxLengthEnforcement;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';

import '../../app/messages.dart';
import '../../app/providers.dart';
import '../../app/router.dart';
import '../../widgets/date_bar.dart';
import '../../widgets/pos_scaffold.dart';
import '../../widgets/section_card.dart';
import '../../widgets/total_row.dart';
import '../payment/customer_section.dart';

/// How far ahead an order can be due, in days (D-043).
const int orderMaxDaysAhead = 90;

/// Takes a pre-order (D-043): the customer (the bill's name, mobile and
/// WhatsApp rules, D-034), the due date and optional time, a free-text
/// description, the agreed price, the advance with how it was paid, and the
/// live balance. Every check is `OrderValidator` or `CustomerValidator`;
/// messages show for a field once it is touched, and for all after a Save
/// that found something wrong. Save is guarded against a double tap.
class NewOrderScreen extends ConsumerStatefulWidget {
  const NewOrderScreen({super.key});

  @override
  ConsumerState<NewOrderScreen> createState() => _NewOrderScreenState();
}

class _NewOrderScreenState extends ConsumerState<NewOrderScreen> {
  late final String _today;
  final CustomerForm _customer = CustomerForm();
  final _description = TextEditingController();
  final _price = TextEditingController();
  final _advance = TextEditingController();
  String? _dueDate;
  String? _dueTime;
  PaymentMode? _mode;
  bool _showErrors = false;

  /// Set on the first Save tap and cleared only by a failure that certainly
  /// wrote nothing.
  bool _saving = false;

  /// Set when a save failed so that it is unclear whether the order was
  /// written; saving again could then make a second order.
  bool _locked = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _today = BusinessDate.of(ref.read(clockProvider)());
  }

  @override
  void dispose() {
    _customer.dispose();
    _description.dispose();
    _price.dispose();
    _advance.dispose();
    super.dispose();
  }

  static Money? _tryMoney(String text) {
    final t = text.trim();
    if (t.isEmpty) return null;
    try {
      return Money.parse(t);
    } on FormatException {
      return null;
    }
  }

  static DateTime _local(String d) {
    final p = d.split('-').map(int.parse).toList();
    return DateTime(p[0], p[1], p[2]);
  }

  static String _key(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _local(_dueDate ?? _today),
      firstDate: _local(_today),
      lastDate: _local(BusinessDate.addDays(_today, orderMaxDaysAhead)),
    );
    if (picked != null) setState(() => _dueDate = _key(picked));
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 12, minute: 0),
    );
    if (picked != null) {
      setState(
        () => _dueTime =
            '${picked.hour.toString().padLeft(2, '0')}:'
            '${picked.minute.toString().padLeft(2, '0')}',
      );
    }
  }

  // The checks, each returning the message or null.

  String? get _customerError =>
      CustomerValidator.nameError(_customer.name.text) ??
      CustomerValidator.phoneError(_customer.phone.text) ??
      (_customer.choice == WhatsappChoice.different
          ? CustomerValidator.phoneError(_customer.whatsapp.text)
          : null);

  String? get _dateError => OrderValidator.dueDateError(_dueDate ?? '', _today);

  String? get _timeError => OrderValidator.dueTimeError(_dueTime);

  String? get _descriptionError =>
      OrderValidator.descriptionError(_description.text);

  Money? get _priceValue => _tryMoney(_price.text);

  String? get _priceError {
    if (_price.text.trim().isEmpty) {
      return OrderValidator.priceError(Money.zero);
    }
    final m = _priceValue;
    if (m == null) return 'Enter an amount, like 1200.';
    return OrderValidator.priceError(m);
  }

  Money? get _advanceValue =>
      _advance.text.trim().isEmpty ? Money.zero : _tryMoney(_advance.text);

  /// The mode that counts: none when there is no advance.
  PaymentMode? get _effectiveMode =>
      (_advanceValue?.isPositive ?? false) ? _mode : null;

  String? get _advanceError {
    final a = _advanceValue;
    if (a == null) return 'Enter an amount, like 500.';
    // Against the price once it is valid, so a missing price isn't blamed on
    // the advance.
    final price = _priceError == null ? _priceValue! : a;
    return OrderValidator.advanceError(a, price, _effectiveMode);
  }

  bool get _valid =>
      _customerError == null &&
      _dateError == null &&
      _timeError == null &&
      _descriptionError == null &&
      _priceError == null &&
      _advanceError == null;

  Future<void> _save() async {
    // Guard before any await: a second tap in the same frame still sees the
    // old, enabled button (03-SYNC §4).
    if (_saving || _locked) return;
    if (!_valid) {
      setState(() => _showErrors = true);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final input = NewOrder(
      customer: _customer.customer!,
      dueDate: _dueDate!,
      dueTime: _dueTime,
      description: OrderValidator.cleanDescription(_description.text),
      price: _priceValue!,
      advance: _advanceValue!,
      advanceMode: _effectiveMode,
    );
    PreOrder? order;
    String? error;
    var lock = false;
    try {
      order = await ref.read(orderServiceProvider).create(input);
    } on DataFailure catch (e) {
      error = Messages.failure(e);
      lock = e.reason == FailureReason.unknown;
    } on Object {
      error = Messages.failure(const DataFailure(FailureReason.unknown));
      lock = true;
    }
    if (!mounted) return;
    if (order == null) {
      setState(() {
        _saving = false;
        _locked = lock;
        _error = lock
            ? '$error\nThe order may have been saved. Check the Orders list '
                  'before entering it again.'
            : error;
      });
      return;
    }
    context.go(Routes.orderSaved, extra: order);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final price = _priceValue;
    final advance = _advanceValue;
    // The balance only needs a valid price and an advance within it; the mode
    // is asked for separately.
    final balance =
        price != null &&
            advance != null &&
            _priceError == null &&
            !advance.isNegative &&
            advance <= price
        ? (price - advance).format()
        : '—';
    final hasAdvance = advance?.isPositive ?? false;

    String? shown(bool touched, String? message) =>
        _showErrors || touched ? message : null;

    return PosScaffold(
      title: 'New order',
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
              key: const Key('save-order'),
              onPressed: _saving || _locked ? null : _save,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: const Text('Save order'),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CustomerSection(form: _customer, onChanged: () => setState(() {})),
            if (_showErrors && _customerError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12, left: 4),
                child: Text(
                  _customerError!,
                  key: const Key('order-customer-error'),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            SectionCard(
              title: 'Due',
              children: [
                OutlinedButton.icon(
                  key: const Key('order-due-date'),
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_today, size: 18),
                  label: Text(
                    _dueDate == null
                        ? 'Pick the delivery date'
                        : formatBusinessDate(_dueDate!),
                  ),
                ),
                if (shown(_dueDate != null, _dateError) case final m?)
                  _FieldError(m, const Key('order-date-error')),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const Key('order-due-time'),
                        onPressed: _pickTime,
                        icon: const Icon(Icons.schedule, size: 18),
                        label: Text(_dueTime ?? 'Add a time (optional)'),
                      ),
                    ),
                    if (_dueTime != null)
                      IconButton(
                        key: const Key('order-due-time-clear'),
                        tooltip: 'Remove the time',
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => _dueTime = null),
                      ),
                  ],
                ),
              ],
            ),
            SectionCard(
              title: 'Cake',
              children: [
                TextField(
                  key: const Key('order-description-input'),
                  controller: _description,
                  minLines: 3,
                  maxLines: 6,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  maxLength: Limits.orderDescriptionMax,
                  // The counter turns red past the limit and the message
                  // explains, instead of silently cutting the text.
                  maxLengthEnforcement: MaxLengthEnforcement.none,
                  decoration: InputDecoration(
                    labelText: 'Description',
                    helperText:
                        'Flavour, layers, weight, the message on the cake',
                    alignLabelWithHint: true,
                    errorText: shown(
                      _description.text.isNotEmpty,
                      _descriptionError,
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ),
            SectionCard(
              title: 'Price and advance',
              children: [
                TextField(
                  key: const Key('order-price-input'),
                  controller: _price,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Agreed price (₹)',
                    errorText: shown(_price.text.isNotEmpty, _priceError),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('order-advance-input'),
                  controller: _advance,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Advance paid (₹)',
                    helperText: 'Leave empty when nothing was paid',
                    errorText: shown(_advance.text.isNotEmpty, _advanceError),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                if (hasAdvance) ...[
                  const SizedBox(height: 12),
                  Text('Paid by', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final m in PaymentMode.selectable)
                        ChoiceChip(
                          key: Key('order-mode-${m.wire}'),
                          label: Text(Messages.paymentMode(m)),
                          selected: _mode == m,
                          onSelected: (_) => setState(() => _mode = m),
                        ),
                    ],
                  ),
                ],
                const Divider(height: 24),
                TotalRow(
                  'Balance to collect',
                  balance,
                  key: const Key('order-balance'),
                  style: theme.textTheme.titleLarge,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldError extends StatelessWidget {
  const _FieldError(this.message, Key key) : super(key: key);

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4, left: 4),
    child: Text(
      message,
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    ),
  );
}
