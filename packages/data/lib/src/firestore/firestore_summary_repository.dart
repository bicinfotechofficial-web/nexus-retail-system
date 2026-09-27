import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nexus_core/nexus_core.dart';

import '../api/reports.dart';
import '../convert/firestore_values.dart';
import 'failure_mapping.dart';

/// [SummaryRepository] over `dailySummary/{YYYY-MM-DD}` and
/// `monthlySummary/{YYYY-MM}`. Doc IDs are ISO dates and months, so a doc ID
/// range is a date range; no index is needed.
final class FirestoreSummaryRepository implements SummaryRepository {
  FirestoreSummaryRepository(this._db);

  final FirebaseFirestore _db;

  /// A day without a doc yet (no sales) reads as an empty [Summary].
  @override
  Stream<Summary> watchDaily(String locationId, String businessDate) => _db
      .doc(FirestorePaths.dailySummary(locationId, businessDate))
      .snapshots()
      .map((s) => modelOrNull(s, Summary.fromMap) ?? const Summary())
      .mapFirestoreErrors();

  @override
  Future<Map<String, Summary>> daily(
    String locationId,
    String from,
    String to,
  ) => _range(FirestorePaths.dailySummaries(locationId), from, to);

  @override
  Future<Map<String, Summary>> monthly(
    String locationId,
    String fromMonth,
    String toMonth,
  ) => _range(FirestorePaths.monthlySummaries(locationId), fromMonth, toMonth);

  /// Docs with IDs in [from]..[to], both inclusive, in ID order.
  Future<Map<String, Summary>> _range(String path, String from, String to) =>
      guardFirestore(() async {
        if (from.compareTo(to) > 0) return const {};
        final s = await _db
            .collection(path)
            .where(FieldPath.documentId, isGreaterThanOrEqualTo: from)
            .where(FieldPath.documentId, isLessThanOrEqualTo: to)
            .orderBy(FieldPath.documentId)
            .get();
        return {
          for (final d in s.docs)
            d.id: Summary.fromMap(d.id, plainFromFirestore(d.data())),
        };
      });
}
