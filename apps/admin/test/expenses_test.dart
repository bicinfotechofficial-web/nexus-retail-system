import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_admin/fakes/fake_backend.dart';
import 'package:nexus_admin/fakes/fake_repositories.dart';
import 'package:nexus_admin/shell/permission_guard.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';

import 'helpers.dart';

Expense _expense(
  String id,
  String loc,
  ExpenseCategory c,
  int rupees,
  String date,
  String note,
) => Expense(
  id: id,
  locationId: loc,
  category: c,
  amount: Money.rupees(rupees),
  date: date,
  note: note,
  createdBy: 'admin-0001',
);

/// Hand-built expenses, so every total below is known. The monthly
/// summaries start empty and are filled from these.
FakeBackend _backend() {
  final seeded = FakeBackend.seeded(today: testToday);
  return FakeBackend(
    auth: seeded.auth,
    locations: seeded.locations,
    catalog: seeded.catalog,
    stock: seeded.stock,
    users: seeded.users,
    summaries: FakeSummaryRepository(
      dailyDocs: const {},
      monthlyDocs: const {},
    ),
    expenses: [
      _expense(
        'rentP',
        'PTB',
        ExpenseCategory.rent,
        35000,
        '2026-09-01',
        'Rent',
      ),
      _expense(
        'powP',
        'PTB',
        ExpenseCategory.utilities,
        6200,
        '2026-09-12',
        'Power',
      ),
      _expense(
        'rentM',
        'MNJ',
        ExpenseCategory.rent,
        24500,
        '2026-09-02',
        'Rent',
      ),
      _expense(
        'salM',
        'MNJ',
        ExpenseCategory.salary,
        42000,
        '2026-09-25',
        'Staff',
      ),
      _expense(
        'augP',
        'PTB',
        ExpenseCategory.rent,
        35000,
        '2026-08-01',
        'Rent',
      ),
    ],
  );
}

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

List<String> _rowIds(WidgetTester tester) => [
  for (final r
      in tester.widget<DataTable>(find.byKey(const Key('expense-table'))).rows)
    if (r.key != null) (r.key! as ValueKey<String>).value,
];

Future<void> _open(WidgetTester tester, FakeBackend backend) async {
  await pumpAdmin(tester, backend);
  await signIn(tester);
  await goTo(tester, '/expenses');
}

Future<void> _pick(WidgetTester tester, Key dropdown, String item) async {
  await tester.tap(find.byKey(dropdown));
  await tester.pumpAndSettle();
  await tester.tap(find.text(item).last);
  await tester.pumpAndSettle();
}

Money _monthly(FakeBackend b, String loc, String month) =>
    b.summaries.monthlyDocs[loc]?[month]?.expenses ?? Money.zero;

void main() {
  testWidgets('lists the month by location and category, newest first', (
    tester,
  ) async {
    await _open(tester, _backend());

    expect(_text(tester, 'expense-month'), 'September 2026');
    expect(_rowIds(tester), [
      'expense-salM',
      'expense-powP',
      'expense-rentM',
      'expense-rentP',
    ]);
    // 35,000 + 6,200 + 24,500 + 42,000.
    expect(_text(tester, 'expenses-total'), '₹1,07,700.00');

    await _pick(tester, const Key('expense-category-filter'), 'Rent');
    expect(_rowIds(tester), ['expense-rentM', 'expense-rentP']);
    expect(_text(tester, 'expenses-total'), '₹59,500.00');

    await _pick(tester, const Key('location-switcher'), 'Pattambi (PTB)');
    expect(_rowIds(tester), ['expense-rentP']);
    expect(_text(tester, 'expenses-total'), '₹35,000.00');

    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();
    expect(_text(tester, 'expense-month'), 'August 2026');
    expect(_rowIds(tester), ['expense-augP']);

    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('expenses-empty')), findsOneWidget);
  });

  testWidgets('the current month is the latest', (tester) async {
    await _open(tester, _backend());
    final next = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.chevron_right),
        matching: find.byType(IconButton),
      ),
    );
    expect(next.onPressed, isNull);
  });

  testWidgets('adding an expense updates the list, summary and audit', (
    tester,
  ) async {
    final backend = _backend();
    await _open(tester, backend);
    expect(_monthly(backend, 'PTB', '2026-09'), Money.rupees(41200));

    await tester.tap(find.byKey(const Key('expense-add')));
    await tester.pumpAndSettle();
    // The date starts at today in IST.
    expect(_text(tester, 'expense-date-text'), '26 Sep 2026');

    await _pick(tester, const Key('expense-location'), 'Pattambi (PTB)');
    await _pick(tester, const Key('expense-category'), 'Utilities');
    await tester.enterText(find.byKey(const Key('expense-amount')), '1,250.50');
    await tester.enterText(find.byKey(const Key('expense-note')), 'Water');
    await tester.tap(find.byKey(const Key('expense-date')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('20'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(_text(tester, 'expense-date-text'), '20 Sep 2026');

    await tester.tap(find.byKey(const Key('expense-save')));
    await tester.pumpAndSettle();

    final saved = backend.expenses.expenses.last;
    expect(saved.locationId, 'PTB');
    expect(saved.category, ExpenseCategory.utilities);
    expect(saved.amount, const Money(125050));
    expect(saved.date, '2026-09-20');
    expect(saved.note, 'Water');
    expect(_text(tester, 'expense-amount-${saved.id}'), '₹1,250.50');
    expect(_text(tester, 'expenses-total'), '₹1,08,950.50');
    // SummaryDeltas.forExpense on PTB's September doc.
    expect(_monthly(backend, 'PTB', '2026-09'), const Money(4245050));
    expect(
      backend
          .summaries
          .monthlyDocs['PTB']!['2026-09']!
          .byExpenseCategory[ExpenseCategory.utilities],
      const Money(745050),
    );
    expect(backend.audit.actions, [AuditAction.expenseCreate]);
    expect(find.textContaining('Added ₹1,250.50 utilities'), findsOneWidget);
  });

  testWidgets('editing moves the amount between months', (tester) async {
    final backend = _backend();
    await _open(tester, backend);

    await tester.tap(find.byKey(const Key('expense-edit-powP')));
    await tester.pumpAndSettle();
    expect(find.text('Edit expense'), findsOneWidget);
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: find.byKey(const Key('expense-amount')),
              matching: find.byType(EditableText),
            ),
          )
          .controller
          .text,
      '6,200.00',
    );
    await tester.enterText(find.byKey(const Key('expense-amount')), '6400');
    await tester.tap(find.byKey(const Key('expense-date')));
    await tester.pumpAndSettle();
    // Back to August in the picker (on top of the screen's own button).
    await tester.tap(find.byTooltip('Previous month').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('30'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('expense-save')));
    await tester.pumpAndSettle();

    expect(backend.expenses.byId('powP')!.date, '2026-08-30');
    expect(_monthly(backend, 'PTB', '2026-09'), Money.rupees(35000));
    expect(_monthly(backend, 'PTB', '2026-08'), Money.rupees(41400));
    expect(backend.audit.actions, [AuditAction.expenseUpdate]);
    expect(find.byKey(const Key('expense-amount-powP')), findsNothing);
  });

  testWidgets('the amount must be a positive rupee value', (tester) async {
    final backend = _backend();
    await _open(tester, backend);
    await tester.tap(find.byKey(const Key('expense-add')));
    await tester.pumpAndSettle();
    await _pick(tester, const Key('expense-location'), 'Manjeri (MNJ)');

    Future<void> tryAmount(String text, String message) async {
      await tester.enterText(find.byKey(const Key('expense-amount')), text);
      await tester.tap(find.byKey(const Key('expense-save')));
      await tester.pumpAndSettle();
      expect(find.text(message), findsOneWidget, reason: text);
    }

    await tryAmount('', 'Enter the amount');
    await tryAmount('abc', 'Enter rupees, with at most two decimals');
    await tryAmount('12.345', 'Enter rupees, with at most two decimals');
    await tryAmount('0', 'The amount must be more than zero');
    expect(backend.audit.actions, isEmpty);
  });

  testWidgets('a new expense cannot go to a deactivated location', (
    tester,
  ) async {
    await _open(tester, _backend());
    await _pick(
      tester,
      const Key('location-switcher'),
      'Kottakkal (KTL) (inactive)',
    );
    await tester.tap(find.byKey(const Key('expense-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('expense-amount')), '100');
    await tester.tap(find.byKey(const Key('expense-save')));
    await tester.pumpAndSettle();
    expect(find.text('Pick a location'), findsOneWidget);

    // The switcher behind the dialog shows KTL; the form's menu doesn't.
    final before = find.text('Kottakkal (KTL) (inactive)').evaluate().length;
    final ptbBefore = find.text('Pattambi (PTB)').evaluate().length;
    await tester.tap(find.byKey(const Key('expense-location')));
    await tester.pumpAndSettle();
    expect(find.text('Kottakkal (KTL) (inactive)'), findsNWidgets(before));
    expect(
      find.text('Pattambi (PTB)').evaluate().length,
      greaterThan(ptbBefore),
    );
  });

  testWidgets('a failed save keeps the form open with the reason', (
    tester,
  ) async {
    final backend = _backend();
    backend.expenseService = _Offline();
    await pumpAdmin(tester, backend);
    await signIn(tester);
    await goTo(tester, '/expenses');
    await tester.tap(find.byKey(const Key('expense-add')));
    await tester.pumpAndSettle();
    await _pick(tester, const Key('expense-location'), 'Manjeri (MNJ)');
    await tester.enterText(find.byKey(const Key('expense-amount')), '100');
    await tester.tap(find.byKey(const Key('expense-save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('expense-error')), findsOneWidget);
    expect(find.text('New expense'), findsOneWidget);
  });

  testWidgets('needs expense.manage', (tester) async {
    await pumpAdmin(tester, _backend());
    await signIn(tester, email: FakeBackend.storeManagerEmail);
    expect(find.text('Expenses'), findsNothing);
    await goTo(tester, '/expenses');
    expect(find.byType(NotPermitted), findsOneWidget);
  });
}

final class _Offline implements ExpenseService {
  @override
  Future<Expense> save(ExpenseInput input) async =>
      throw const DataFailure(FailureReason.offline);
}
