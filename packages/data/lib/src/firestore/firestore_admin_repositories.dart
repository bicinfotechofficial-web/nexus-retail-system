import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nexus_core/nexus_core.dart';

import '../api/admin.dart';
import '../convert/firestore_values.dart';
import 'failure_mapping.dart';

/// [LocationRepository] over `locations`.
final class FirestoreLocationRepository implements LocationRepository {
  FirestoreLocationRepository(this._db);

  final FirebaseFirestore _db;

  /// Every location, active or not, by code. Needs `location.manage`-style
  /// access to all of them (Admin); a Store Manager uses [watchLocation].
  @override
  Stream<List<Location>> watchLocations() => _db
      .collection(FirestorePaths.locations)
      .snapshots()
      .map(
        (s) =>
            modelsOf(s, Location.fromMap)
              ..sort((a, b) => a.code.compareTo(b.code)),
      )
      .mapFirestoreErrors();

  @override
  Stream<Location?> watchLocation(String locationId) => _db
      .doc(FirestorePaths.location(locationId))
      .snapshots()
      .map((s) => modelOrNull(s, Location.fromMap))
      .mapFirestoreErrors();
}

/// [UserRepository] over `users` (`user.manage`).
final class FirestoreUserRepository implements UserRepository {
  FirestoreUserRepository(this._db, {DateTime Function()? clock})
    : _now = clock ?? DateTime.now;

  final FirebaseFirestore _db;
  final DateTime Function() _now;

  /// All users, or those of one location, by name. Single-field index only.
  @override
  Stream<List<AppUser>> watchUsers({String? locationId}) {
    Query<Map<String, dynamic>> q = _db.collection(FirestorePaths.users);
    if (locationId != null) q = q.where('locationId', isEqualTo: locationId);
    return q
        .snapshots()
        .map(
          (s) =>
              modelsOf(
                s,
                AppUser.fromMap,
                serverTimestampFields: AppUser.serverTimestampFields,
                now: _now,
              )..sort((a, b) {
                final c = a.name.toLowerCase().compareTo(b.name.toLowerCase());
                return c != 0 ? c : a.uid.compareTo(b.uid);
              }),
        )
        .mapFirestoreErrors();
  }
}

/// [ExpenseRepository] over `expenses` (`expense.manage`).
final class FirestoreExpenseRepository implements ExpenseRepository {
  FirestoreExpenseRepository(this._db, {DateTime Function()? clock})
    : _now = clock ?? DateTime.now;

  final FirebaseFirestore _db;
  final DateTime Function() _now;

  /// Newest `date` first. A month is the `date` range `YYYY-MM-01` to
  /// `YYYY-MM-31` (string order is date order). With a location the query
  /// uses the `locationId ASC, date DESC` index; without one, the automatic
  /// `date` index.
  @override
  Stream<List<Expense>> watchExpenses({String? locationId, String? monthKey}) {
    if (monthKey != null && !BusinessDate.isValidMonth(monthKey)) {
      throw ArgumentError.value(monthKey, 'monthKey', 'not YYYY-MM');
    }
    Query<Map<String, dynamic>> q = _db.collection(FirestorePaths.expenses);
    if (locationId != null) q = q.where('locationId', isEqualTo: locationId);
    if (monthKey != null) {
      q = q
          .where('date', isGreaterThanOrEqualTo: '$monthKey-01')
          .where('date', isLessThanOrEqualTo: '$monthKey-31');
    }
    return q
        .orderBy('date', descending: true)
        .snapshots()
        .map(
          (s) => modelsOf(
            s,
            Expense.fromMap,
            serverTimestampFields: Expense.serverTimestampFields,
            now: _now,
          ),
        )
        .mapFirestoreErrors();
  }
}
