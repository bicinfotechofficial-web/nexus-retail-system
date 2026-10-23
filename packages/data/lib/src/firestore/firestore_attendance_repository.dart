import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nexus_core/nexus_core.dart';

import '../api/attendance.dart';
import '../convert/firestore_values.dart';
import 'failure_mapping.dart';

/// [AttendanceRepository] over `locations/{loc}/attendance` (D-042). Served
/// from the Firestore cache while offline, which holds the days this device
/// has listened to or written.
///
/// A day is `businessDate ==`; a month is a range on `businessDate`
/// (`YYYY-MM-01` to `YYYY-MM-31`), both single-field queries; all-locations
/// is a collection-group query on `businessDate` (the override in
/// `firestore.indexes.json`, rule #16 with `report.all`). Results are
/// sorted here, by date then name, so no composite index is needed.
final class FirestoreAttendanceRepository implements AttendanceRepository {
  FirestoreAttendanceRepository(this._db, {DateTime Function()? clock})
    : _now = clock ?? DateTime.now;

  final FirebaseFirestore _db;
  final DateTime Function() _now;

  @override
  Stream<List<AttendanceRecord>> watchDay(String locationId, String date) => _db
      .collection(FirestorePaths.attendance(locationId))
      .where('businessDate', isEqualTo: date)
      .snapshots()
      .map(_records)
      .mapFirestoreErrors();

  @override
  Stream<List<AttendanceRecord>> watchMonth(
    String locationId,
    String monthKey,
  ) => _db
      .collection(FirestorePaths.attendance(locationId))
      .where('businessDate', isGreaterThanOrEqualTo: '$monthKey-01')
      .where('businessDate', isLessThanOrEqualTo: '$monthKey-31')
      .snapshots()
      .map(_records)
      .mapFirestoreErrors();

  /// One day across every location. Each record carries its `locationId`.
  @override
  Stream<List<AttendanceRecord>> watchDayAllLocations(String date) => _db
      .collectionGroup('attendance')
      .where('businessDate', isEqualTo: date)
      .snapshots()
      .map(_records)
      .mapFirestoreErrors();

  /// Each record also gets its `locationId`, read from the document path
  /// (`locations/{loc}/attendance/{id}`), which is what tells the Admin's
  /// all-stores view which store a mark belongs to.
  List<AttendanceRecord> _records(QuerySnapshot<Map<String, dynamic>> s) =>
      [
        for (final d in s.docs)
          _withLocation(
            AttendanceRecord.fromMap(
              d.id,
              plainFromFirestore(
                d.data(),
                serverTimestampFields: AttendanceRecord.serverTimestampFields,
                hasPendingWrites: d.metadata.hasPendingWrites,
                now: _now,
              ),
            ),
            d.reference.parent.parent?.id,
          ),
      ]..sort((a, b) {
        final byDate = a.businessDate.compareTo(b.businessDate);
        if (byDate != 0) return byDate;
        final byName = a.staffName.toLowerCase().compareTo(
          b.staffName.toLowerCase(),
        );
        return byName != 0 ? byName : a.staffId.compareTo(b.staffId);
      });

  static AttendanceRecord _withLocation(AttendanceRecord r, String? loc) =>
      AttendanceRecord(
        staffId: r.staffId,
        staffName: r.staffName,
        businessDate: r.businessDate,
        status: r.status,
        note: r.note,
        markedBy: r.markedBy,
        deviceId: r.deviceId,
        editedAt: r.editedAt,
        locationId: loc,
      );
}
