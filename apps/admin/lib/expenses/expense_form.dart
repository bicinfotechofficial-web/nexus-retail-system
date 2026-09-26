import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';

import '../common/dialogs.dart';
import '../common/format.dart';
import '../data/providers.dart';

/// Opens the expense form: a new one when [existing] is null. Returns the
/// saved expense, or null when cancelled.
Future<Expense?> showExpenseForm(
  BuildContext context, {
  Expense? existing,
  String? locationId,
}) => showDialog<Expense>(
  context: context,
  builder: (_) => ExpenseForm(existing: existing, locationId: locationId),
);

/// Create or edit an expense. [ExpenseService.save] adjusts the monthly
/// summary and writes the audit entry in the same batch.
class ExpenseForm extends ConsumerStatefulWidget {
  const ExpenseForm({this.existing, this.locationId, super.key});

  final Expense? existing;

  /// The location a new expense starts with, e.g. the switcher's.
  final String? locationId;

  @override
  ConsumerState<ExpenseForm> createState() => _ExpenseFormState();
}

class _ExpenseFormState extends ConsumerState<ExpenseForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late final TextEditingController _note;
  String? _location;
  late ExpenseCategory _category;
  late String _date;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _amount = TextEditingController(
      text: e == null ? '' : e.amount.format(symbol: ''),
    );
    _note = TextEditingController(text: e?.note ?? '');
    _location = e?.locationId ?? widget.locationId;
    _category = e?.category ?? ExpenseCategory.rent;
    _date = e?.date ?? ref.read(todayProvider);
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  static String? validateAmount(String? v) {
    final text = v?.trim() ?? '';
    if (text.isEmpty) return 'Enter the amount';
    final Money m;
    try {
      m = Money.parse(text);
    } on FormatException {
      return 'Enter rupees, with at most two decimals';
    }
    if (!m.isPositive) return 'The amount must be more than zero';
    return null;
  }

  Future<void> _pickDate() async {
    final today = ref.read(todayProvider);
    final latest = _date.compareTo(today) > 0 ? _date : today;
    final picked = await showDatePicker(
      context: context,
      initialDate: pickerDate(_date),
      // "Today" in the picker is the IST date, not the browser's.
      currentDate: pickerDate(today),
      firstDate: DateTime(2024),
      lastDate: pickerDate(latest),
    );
    if (picked != null) setState(() => _date = businessDateOfPicked(picked));
  }

  Future<void> _save() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final saved = await ref
          .read(expenseServiceProvider)
          .save(
            ExpenseInput(
              id: widget.existing?.id,
              locationId: _location!,
              category: _category,
              amount: Money.parse(_amount.text.trim()),
              date: _date,
              note: _note.text.trim(),
            ),
          );
      if (mounted) Navigator.of(context).pop(saved);
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = failureMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(locationsProvider).value ?? const <Location>[];
    // New expenses go to open locations; an edit keeps its own location
    // selectable even if it has since been deactivated.
    final locations = [
      for (final l in all)
        if (l.active || l.code == widget.existing?.locationId) l,
    ]..sort((a, b) => a.code.compareTo(b.code));
    if (_location != null && !locations.any((l) => l.code == _location)) {
      _location = null;
    }
    final editing = widget.existing != null;

    return AlertDialog(
      title: Text(editing ? 'Edit expense' : 'New expense'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  key: const Key('expense-location'),
                  initialValue: _location,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Location'),
                  items: [
                    for (final l in locations)
                      DropdownMenuItem(
                        value: l.code,
                        child: Text(locationLabel(l)),
                      ),
                  ],
                  validator: (v) => v == null ? 'Pick a location' : null,
                  onChanged: (v) => setState(() => _location = v),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<ExpenseCategory>(
                  key: const Key('expense-category'),
                  initialValue: _category,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: [
                    for (final c in ExpenseCategory.values)
                      DropdownMenuItem(
                        value: c,
                        child: Text(expenseCategoryLabel(c)),
                      ),
                  ],
                  onChanged: (v) => setState(() => _category = v!),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('expense-amount'),
                  controller: _amount,
                  decoration: const InputDecoration(
                    labelText: 'Amount',
                    prefixText: '₹ ',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: validateAmount,
                ),
                const SizedBox(height: 12),
                InputDecorator(
                  decoration: const InputDecoration(labelText: 'Date (IST)'),
                  child: InkWell(
                    key: const Key('expense-date'),
                    onTap: _saving ? null : _pickDate,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            formatBusinessDate(_date),
                            key: const Key('expense-date-text'),
                          ),
                        ),
                        const Icon(Icons.calendar_today_outlined, size: 18),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('expense-note'),
                  controller: _note,
                  decoration: const InputDecoration(
                    labelText: 'Note',
                    hintText: 'e.g. September rent',
                  ),
                  maxLength: 200,
                ),
                if (_error != null)
                  Text(
                    _error!,
                    key: const Key('expense-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('expense-save'),
          onPressed: _saving ? null : _save,
          child: Text(editing ? 'Save changes' : 'Add expense'),
        ),
      ],
    );
  }
}
