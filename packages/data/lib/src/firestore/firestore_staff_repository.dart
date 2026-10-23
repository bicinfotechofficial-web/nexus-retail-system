import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nexus_core/nexus_core.dart';

import '../api/staff.dart';
import '../convert/firestore_values.dart';
import 'failure_mapping.dart';

/// [StaffRepository] over `locations/{loc}/staff` (D-042). Served from the
/// Firestore cache while offline, which holds the roster this device has
/// listened to.
///
/// Both lists are sorted here by name (letter case ignored), so no
/// composite index is needed: a store's roster is a handful of documents.
final class FirestoreStaffRepository implements StaffRepository {
  FirestoreStaffRepository(this._db, {DateTime Function()? clock})
    : _now = clock ?? DateTime.now;

  final FirebaseFirestore _db;
  final DateTime Function() _now;

  @override
  Stream<List<StaffMember>> watchActive(String locationId) => _db
      .collection(FirestorePaths.staff(locationId))
      .where('active', isEqualTo: true)
      .snapshots()
      .map((s) => _byName(_members(s, locationId)))
      .mapFirestoreErrors();

  @override
  Stream<List<StaffMember>> watchAll(String locationId) => _db
      .collection(FirestorePaths.staff(locationId))
      .snapshots()
      .map((s) => _byName(_members(s, locationId)))
      .mapFirestoreErrors();

  /// Each member also gets its `locationId`, read from the document path
  /// (`locations/{loc}/staff/{id}`).
  List<StaffMember> _members(
    QuerySnapshot<Map<String, dynamic>> s,
    String locationId,
  ) => [
    for (final d in s.docs)
      _withLocation(
        StaffMember.fromMap(
          d.id,
          plainFromFirestore(
            d.data(),
            serverTimestampFields: StaffMember.serverTimestampFields,
            hasPendingWrites: d.metadata.hasPendingWrites,
            now: _now,
          ),
        ),
        d.reference.parent.parent?.id ?? locationId,
      ),
  ];

  static StaffMember _withLocation(StaffMember m, String locationId) =>
      StaffMember(
        id: m.id,
        name: m.name,
        role: m.role,
        active: m.active,
        locationId: locationId,
        createdBy: m.createdBy,
        createdAt: m.createdAt,
        updatedBy: m.updatedBy,
        updatedAt: m.updatedAt,
      );

  static List<StaffMember> _byName(List<StaffMember> list) =>
      list..sort((a, b) {
        final c = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        return c != 0 ? c : a.id.compareTo(b.id);
      });
}
