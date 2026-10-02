import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nexus_core/nexus_core.dart';

import '../api/customers.dart';
import '../convert/firestore_values.dart';
import '../plans/plan_support.dart';
import 'failure_mapping.dart';

/// [CustomerRepository] over `locations/{loc}/customers` (D-037). Read only:
/// customers are written by the bill batch.
///
/// The listeners are served from the Firestore cache while offline, which
/// holds the customers this device has listened to or written (a bill's own
/// customer record is in the cache with its pending write).
final class FirestoreCustomerRepository implements CustomerRepository {
  FirestoreCustomerRepository(this._db, {DateTime Function()? clock})
    : _now = clock ?? DateTime.now;

  final FirebaseFirestore _db;
  final DateTime Function() _now;

  /// Shortest prefix [watchByPhone] searches for.
  static const int minPrefixDigits = 3;

  /// Most suggestions [watchByPhone] returns.
  static const int maxSuggestions = 10;

  /// `phone >= prefix` and `phone < prefix + U+F8FF`, ordered by phone (the
  /// automatic single-field index), at most [maxSuggestions]. A prefix that
  /// isn't at least [minPrefixDigits] digits (after trimming) gives an empty
  /// list without asking Firestore. Several names on one phone come back
  /// together, by customer ID.
  @override
  Stream<List<Customer>> watchByPhone(String locationId, String phonePrefix) {
    final p = phonePrefix.trim();
    if (p.length < minPrefixDigits || !_digits.hasMatch(p)) {
      return Stream.value(const <Customer>[]);
    }
    return _db
        .collection(customersPath(locationId))
        .where('phone', isGreaterThanOrEqualTo: p)
        .where('phone', isLessThan: '$p')
        .orderBy('phone')
        .limit(maxSuggestions)
        .snapshots()
        .map(_toCustomers)
        .mapFirestoreErrors();
  }

  /// Most recent first by `lastBillAt` (single-field index, automatic).
  @override
  Stream<List<Customer>> watchAll(String locationId, {int limit = 200}) => _db
      .collection(customersPath(locationId))
      .orderBy('lastBillAt', descending: true)
      .limit(limit)
      .snapshots()
      .map(_toCustomers)
      .mapFirestoreErrors();

  /// A collection-group query over every location's `customers`, most
  /// recent first. Needs the collection-group index on `lastBillAt`
  /// (`firestore.indexes.json`) and `report.all` (rule #14). Each
  /// customer carries its `locationId`. A person who bought at two locations
  /// appears twice.
  @override
  Stream<List<Customer>> watchAllLocations({int limit = 500}) => _db
      .collectionGroup('customers')
      .orderBy('lastBillAt', descending: true)
      .limit(limit)
      .snapshots()
      .map(_toCustomers)
      .mapFirestoreErrors();

  /// Each customer also gets its `locationId`, read from the document path
  /// (`locations/{loc}/customers/{id}`), which is what tells the Admin's
  /// all-locations list which store a record belongs to.
  List<Customer> _toCustomers(QuerySnapshot<Map<String, dynamic>> s) => [
    for (final d in s.docs)
      Customer.fromMap(d.id, {
        ...plainFromFirestore(
          d.data(),
          serverTimestampFields: Customer.serverTimestampFields,
          hasPendingWrites: d.metadata.hasPendingWrites,
          now: _now,
        ),
        'locationId': d.reference.parent.parent?.id,
      }),
  ];

  static final RegExp _digits = RegExp(r'^[0-9]+$');
}
