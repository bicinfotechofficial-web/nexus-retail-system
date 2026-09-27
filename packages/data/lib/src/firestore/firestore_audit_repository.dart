import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nexus_core/nexus_core.dart';

import '../api/reports.dart';
import '../convert/firestore_values.dart';
import 'failure_mapping.dart';

/// [AuditRepository] over `auditLog`. Admin only, online (03-SYNC §9).
final class FirestoreAuditRepository implements AuditRepository {
  FirestoreAuditRepository(this._db);

  final FirebaseFirestore _db;

  /// Every filter runs on the server, so [AuditQuery.limit] counts matching
  /// entries: equality on `locationId`, `by` and `action`, a range on `at`
  /// with both ends inclusive, newest first. Each combination of equality
  /// filters needs an `auditLog` composite index of those fields (ASC) plus
  /// `at DESC`: seven in all. With no equality filter the automatic `at`
  /// index serves.
  @override
  Future<List<AuditEntry>> query(AuditQuery q) => guardFirestore(() async {
    if (q.limit <= 0) return const [];
    Query<Map<String, dynamic>> query = _db.collection(FirestorePaths.auditLog);
    if (q.locationId != null) {
      query = query.where('locationId', isEqualTo: q.locationId);
    }
    if (q.userId != null) query = query.where('by', isEqualTo: q.userId);
    if (q.action != null) {
      query = query.where('action', isEqualTo: q.action!.wire);
    }
    if (q.from != null) {
      query = query.where(
        'at',
        isGreaterThanOrEqualTo: Timestamp.fromDate(q.from!),
      );
    }
    if (q.to != null) {
      query = query.where('at', isLessThanOrEqualTo: Timestamp.fromDate(q.to!));
    }
    final s = await query
        .orderBy('at', descending: true)
        .limit(q.limit)
        .get(estimateServerTimestamps);
    return modelsOf(
      s,
      AuditEntry.fromMap,
      serverTimestampFields: AuditEntry.serverTimestampFields,
    );
  });
}
