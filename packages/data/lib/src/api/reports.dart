import 'package:nexus_core/nexus_core.dart';

/// Pre-aggregated summaries (D-014). "All locations" is the sum of the
/// per-location summaries, done by the caller with `Summary.+`.
abstract interface class SummaryRepository {
  Stream<Summary> watchDaily(String locationId, String businessDate);

  /// businessDate → summary for each day in [from]..[to] that has one.
  Future<Map<String, Summary>> daily(String locationId, String from, String to);

  /// monthKey → summary for each month in [fromMonth]..[toMonth].
  Future<Map<String, Summary>> monthly(
    String locationId,
    String fromMonth,
    String toMonth,
  );
}

final class AuditQuery {
  const AuditQuery({
    this.locationId,
    this.userId,
    this.action,
    this.from,
    this.to,
    this.limit = 100,
  });

  final String? locationId;
  final String? userId;
  final AuditAction? action;
  final DateTime? from;
  final DateTime? to;
  final int limit;
}

abstract interface class AuditRepository {
  /// Newest first (`audit.view`).
  Future<List<AuditEntry>> query(AuditQuery query);
}
