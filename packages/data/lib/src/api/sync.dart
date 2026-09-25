/// Connection and sync health (03-SYNC §6), shown in the app-bar chip.
sealed class SyncStatus {
  const SyncStatus();
}

final class Online extends SyncStatus {
  const Online();
}

final class Syncing extends SyncStatus {
  const Syncing(this.pending);

  /// Ledger entries not yet confirmed on the server.
  final int pending;
}

final class Offline extends SyncStatus {
  const Offline(this.since);
  final DateTime since;
}

/// A write the server rejected (03-SYNC §6.3). Always a bug to report.
final class SyncError {
  const SyncError({required this.path, required this.detail, required this.at});

  final String path;
  final String detail;
  final DateTime at;
}

abstract interface class SyncService {
  Stream<SyncStatus> get status;
  Stream<List<SyncError>> get errors;

  /// When the ledger was last fully confirmed, or null if never.
  DateTime? get lastSyncAt;

  /// Runs a sync pass now (the Retry button).
  Future<void> syncNow();
}

/// The offline limit (03-SYNC §7, D-016).
sealed class OfflineState {
  const OfflineState();
}

final class WithinLimit extends OfflineState {
  const WithinLimit();
}

/// At 80% of the limit: show the amber banner.
final class NearLimit extends OfflineState {
  const NearLimit(this.billingStopsIn);
  final Duration billingStopsIn;
}

/// At the limit: new billing is blocked until a sync or a PIN override.
final class BillingBlocked extends OfflineState {
  const BillingBlocked();
}

abstract interface class OfflineGuard {
  Stream<OfflineState> get state;

  /// Checks [pin] against the location's cached hash. On success, extends
  /// the limit by `overrideExtensionHours` and queues an OFFLINE_OVERRIDE
  /// audit entry. Returns false for a wrong PIN.
  Future<bool> override(String pin);
}
