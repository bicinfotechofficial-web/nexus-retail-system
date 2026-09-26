import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus_core/nexus_core.dart';

import '../common/dialogs.dart';
import '../common/format.dart';
import '../data/providers.dart';
import 'expense_form.dart';

/// A month's expenses at one location, or all when the location is null.
final expensesProvider =
    StreamProvider.family<List<Expense>, (String? locationId, String month)>(
      (ref, key) => ref
          .watch(expenseRepositoryProvider)
          .watchExpenses(locationId: key.$1, monthKey: key.$2),
    );

/// The month on screen. Starts at the current IST month.
final expenseMonthProvider = NotifierProvider<ExpenseMonthNotifier, String>(
  ExpenseMonthNotifier.new,
);

class ExpenseMonthNotifier extends Notifier<String> {
  @override
  String build() => BusinessDate.monthOf(ref.watch(todayProvider));

  void set(String month) => state = month;
}

/// Expenses for a month, by the switcher's location and a category, newest
/// first, with create and edit (`expense.manage`).
class ExpensesScreen extends ConsumerStatefulWidget {
  const ExpensesScreen({super.key});

  @override
  ConsumerState<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends ConsumerState<ExpensesScreen> {
  ExpenseCategory? _category;

  Future<void> _edit(Expense? existing, String? locationId) async {
    final saved = await showExpenseForm(
      context,
      existing: existing,
      locationId: locationId,
    );
    if (saved == null || !mounted) return;
    showMessage(
      context,
      '${existing == null ? 'Added' : 'Saved'} ${saved.amount.format()} '
      '${expenseCategoryLabel(saved.category).toLowerCase()} for '
      '${saved.locationId}, ${formatBusinessDate(saved.date)}.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final month = ref.watch(expenseMonthProvider);
    final thisMonth = BusinessDate.monthOf(ref.watch(todayProvider));
    final locationId = ref.watch(selectedLocationProvider);
    final locations = {
      for (final l in ref.watch(locationsProvider).value ?? const <Location>[])
        l.code: l,
    };
    final async = ref.watch(expensesProvider((locationId, month)));
    final notifier = ref.read(expenseMonthProvider.notifier);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Expenses', style: theme.textTheme.headlineSmall),
            ),
            FilledButton.icon(
              key: const Key('expense-add'),
              icon: const Icon(Icons.add),
              label: const Text('Add expense'),
              onPressed: () => _edit(null, locationId),
            ),
          ],
        ),
        Text(
          locationId == null
              ? 'All locations'
              : locations[locationId] == null
              ? locationId
              : locationLabel(locations[locationId]!),
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 16,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Previous month',
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => notifier.set(addMonths(month, -1)),
                ),
                Text(
                  formatMonthKey(month),
                  key: const Key('expense-month'),
                  style: theme.textTheme.titleMedium,
                ),
                IconButton(
                  tooltip: 'Next month',
                  icon: const Icon(Icons.chevron_right),
                  onPressed: month.compareTo(thisMonth) >= 0
                      ? null
                      : () => notifier.set(addMonths(month, 1)),
                ),
              ],
            ),
            SizedBox(
              width: 200,
              child: DropdownButtonFormField<ExpenseCategory?>(
                key: const Key('expense-category-filter'),
                initialValue: _category,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Category'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All')),
                  for (final c in ExpenseCategory.values)
                    DropdownMenuItem(
                      value: c,
                      child: Text(expenseCategoryLabel(c)),
                    ),
                ],
                onChanged: (v) => setState(() => _category = v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        switch (async) {
          AsyncData(:final value) => _ExpenseTable(
            expenses: [
              for (final e in value)
                if (_category == null || e.category == _category) e,
            ],
            showLocation: locationId == null,
            onEdit: (e) => _edit(e, null),
          ),
          AsyncError(:final error) => Text(
            'Could not load expenses: ${failureMessage(error)}',
          ),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ],
    );
  }
}

class _ExpenseTable extends StatelessWidget {
  const _ExpenseTable({
    required this.expenses,
    required this.showLocation,
    required this.onEdit,
  });

  final List<Expense> expenses;
  final bool showLocation;
  final void Function(Expense) onEdit;

  @override
  Widget build(BuildContext context) {
    if (expenses.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text('No expenses in this month.', key: Key('expenses-empty')),
      );
    }
    final sorted = [...expenses]
      ..sort((a, b) {
        final byDate = b.date.compareTo(a.date);
        return byDate != 0 ? byDate : a.id.compareTo(b.id);
      });
    final total = sorted.fold(Money.zero, (a, e) => a + e.amount);
    const bold = TextStyle(fontWeight: FontWeight.bold);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        key: const Key('expense-table'),
        columns: [
          const DataColumn(label: Text('Date')),
          if (showLocation) const DataColumn(label: Text('Location')),
          const DataColumn(label: Text('Category')),
          const DataColumn(label: Text('Note')),
          const DataColumn(label: Text('Amount'), numeric: true),
          const DataColumn(label: Text('')),
        ],
        rows: [
          for (final e in sorted)
            DataRow(
              key: ValueKey('expense-${e.id}'),
              cells: [
                DataCell(Text(formatBusinessDate(e.date))),
                if (showLocation) DataCell(Text(e.locationId)),
                DataCell(Text(expenseCategoryLabel(e.category))),
                DataCell(
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 280),
                    child: Text(e.note, overflow: TextOverflow.ellipsis),
                  ),
                ),
                DataCell(
                  Text(e.amount.format(), key: Key('expense-amount-${e.id}')),
                ),
                DataCell(
                  IconButton(
                    key: Key('expense-edit-${e.id}'),
                    tooltip: 'Edit',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => onEdit(e),
                  ),
                ),
              ],
            ),
          DataRow(
            cells: [
              const DataCell(Text('Total', style: bold)),
              if (showLocation) const DataCell(Text('')),
              const DataCell(Text('')),
              DataCell(Text('${sorted.length} expenses')),
              DataCell(
                Text(
                  total.format(),
                  key: const Key('expenses-total'),
                  style: bold,
                ),
              ),
              const DataCell(Text('')),
            ],
          ),
        ],
      ),
    );
  }
}
