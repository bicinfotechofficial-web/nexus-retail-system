import 'package:nexus_core/nexus_core.dart';

abstract interface class LocationRepository {
  Stream<List<Location>> watchLocations();
  Stream<Location?> watchLocation(String locationId);
}

abstract interface class LocationService {
  /// Creates or edits a location, with a LOCATION_UPDATE audit entry.
  ///
  /// Creating a location writes `nextDeviceNo: 0`; editing one never writes
  /// `nextDeviceNo`, which only device registration changes (D-004, QA-006,
  /// QA-035). A non-null [newPin]
  /// must be at least `Limits.minOverridePinDigits` digits, otherwise this
  /// throws `DataFailure(ruleViolation)`; it is hashed on the client
  /// (PBKDF2, 02-DATA-MODEL) and replaces `overridePinHash`. A new location
  /// needs a PIN.
  Future<Location> save(Location location, {String? newPin});
}

abstract interface class UserRepository {
  Stream<List<AppUser>> watchUsers({String? locationId});
}

abstract interface class UserService {
  /// Creates the Auth account through a secondary Firebase app, so the
  /// Admin stays signed in, then the `users/{uid}` doc (D-018). Online only.
  Future<AppUser> createStoreManager({
    required String name,
    required String email,
    required String password,
    required String locationId,
  });

  /// False disables every operation for the user (USER_DISABLE audit).
  Future<void> setActive(String uid, {required bool active});
}

final class ExpenseInput {
  const ExpenseInput({
    required this.locationId,
    required this.category,
    required this.amount,
    required this.date,
    required this.note,
    this.id,
  });

  /// Null creates a new expense.
  final String? id;
  final String locationId;
  final ExpenseCategory category;
  final Money amount;

  /// `YYYY-MM-DD`.
  final String date;
  final String note;
}

abstract interface class ExpenseRepository {
  /// Expenses of [monthKey] (`YYYY-MM`), for one location or all.
  Stream<List<Expense>> watchExpenses({String? locationId, String? monthKey});
}

abstract interface class ExpenseService {
  /// Creates or edits, adjusting the monthly summary with
  /// `SummaryDeltas.forExpense` in the same batch.
  Future<Expense> save(ExpenseInput input);
}
