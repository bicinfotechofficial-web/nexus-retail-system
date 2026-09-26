import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';

import 'fake_repositories.dart';
import 'fake_services.dart';

/// In-memory [ExpenseRepository] and [ExpenseService]. Like the real one, a
/// save adjusts the monthly summaries with `SummaryDeltas.forExpense` and
/// writes an EXPENSE_CREATE or EXPENSE_UPDATE audit entry.
final class FakeExpenses implements ExpenseRepository, ExpenseService {
  FakeExpenses({
    required this.summaries,
    required this.locations,
    required this.audit,
    this.auth,
    this.clock,
    List<Expense> expenses = const [],
  }) : store = Watched(List.unmodifiable(expenses));

  final FakeSummaryRepository summaries;
  final FakeLocationRepository locations;
  final FakeAuditTrail audit;
  final AuthService? auth;
  final DateTime Function()? clock;
  final Watched<List<Expense>> store;
  int _nextId = 1;

  List<Expense> get expenses => store.value;

  Expense? byId(String id) => expenses.where((e) => e.id == id).firstOrNull;

  /// Adds [expense] to the store and to its monthly summary, without an
  /// audit entry: seed data that was already there.
  void seed(Expense expense) {
    store.value = List.unmodifiable([...expenses, expense]);
    _apply(SummaryDeltas.forExpense(after: expense));
  }

  @override
  Stream<List<Expense>> watchExpenses({String? locationId, String? monthKey}) =>
      store.watch(
        (v) => [
          for (final e in v)
            if ((locationId == null || e.locationId == locationId) &&
                (monthKey == null || BusinessDate.monthOf(e.date) == monthKey))
              e,
        ]..sort((a, b) => b.date.compareTo(a.date)),
      );

  @override
  Future<Expense> save(ExpenseInput input) async {
    if (!input.amount.isPositive) {
      throw const DataFailure(FailureReason.ruleViolation, 'amount');
    }
    if (!BusinessDate.isValid(input.date)) {
      throw DataFailure(FailureReason.ruleViolation, 'date ${input.date}');
    }
    if (locations.byCode(input.locationId) == null) {
      throw const DataFailure(FailureReason.notFound);
    }
    final before = input.id == null ? null : byId(input.id!);
    if (input.id != null && before == null) {
      throw const DataFailure(FailureReason.notFound);
    }
    final now = (clock ?? DateTime.now)();
    final by = auth?.current?.user.uid ?? 'unknown';
    var id = input.id;
    while (id == null || (before == null && byId(id) != null)) {
      id = 'e${_nextId++}';
    }
    final after = Expense(
      id: id,
      locationId: input.locationId,
      category: input.category,
      amount: input.amount,
      date: input.date,
      note: input.note,
      createdBy: before?.createdBy ?? by,
      createdAt: before?.createdAt ?? now,
      updatedAt: now,
    );
    store.value = List.unmodifiable([
      for (final e in expenses)
        if (e.id != id) e,
      after,
    ]);
    _apply(SummaryDeltas.forExpense(after: after, before: before));
    audit.add(
      before == null ? AuditAction.expenseCreate : AuditAction.expenseUpdate,
      id,
      id: Ids.expenseAuditId(id, now),
      entityPath: FirestorePaths.expense(id),
      locationId: after.locationId,
      before: before?.toMap(),
      after: after.toMap(),
      by: by,
    );
    return after;
  }

  void _apply(List<ExpenseDelta> deltas) {
    for (final d in deltas) {
      summaries.incrementMonthly(d.locationId, d.monthKey, d.delta);
    }
  }
}
