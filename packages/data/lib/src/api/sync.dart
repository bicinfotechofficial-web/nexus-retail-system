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

  /// The end of the last sync pass in which `waitForPendingWrites` finished
  /// and every ledger entry was resolved, either confirmed or moved to
  /// [errors]. A sync error does not hold it back. It is first set by an
  /// interactive online sign-in or device registration (not by restoring a
  /// saved session), and it is persisted across restarts (03-SYNC §6).
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

/// At 80% of the limit, or during a PIN override: show the amber banner.
/// [billingStopsIn] counts down to the limit or to the override's end.
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

  /// Checks [pin] against the location's cached hash. On success, billing
  /// is allowed until `now + overrideExtensionHours`, however long the
  /// device has been offline, and an OFFLINE_OVERRIDE audit entry is queued
  /// with ID `Ids.overrideAuditId` (D-016). Returns false for a wrong PIN.
  Future<bool> override(String pin);
}
