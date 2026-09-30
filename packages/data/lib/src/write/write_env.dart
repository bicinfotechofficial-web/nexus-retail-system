import 'dart:async';
import 'dart:math';

import 'package:nexus_core/nexus_core.dart';

import '../api/failures.dart';
import '../api/session.dart';
import '../counters/counter_store.dart';
import '../plans/plan_support.dart';
import '../plans/write_plan.dart';
import '../sync/sync_ledger.dart';
import 'plan_committer.dart';
import 'write_reads.dart';

/// New IDs for docs whose ID the service assigns (a suggested product, a
/// raw material, an expense): a prefix, the time in base 36 and a random
/// suffix, so they pass `Ids.isSafeKey` and sort roughly by creation.
final class IdGenerator {
  IdGenerator({Random? random, DateTime Function()? clock})
    : _random = random ?? Random.secure(),
      _now = clock ?? DateTime.now;

  final Random _random;
  final DateTime Function() _now;

  static const String _alphabet = '0123456789abcdefghijklmnopqrstuvwxyz';

  String next(String prefix) {
    final time = _now().millisecondsSinceEpoch.toRadixString(36);
    final suffix = List.generate(
      5,
      (_) => _alphabet[_random.nextInt(_alphabet.length)],
    ).join();
    return '$prefix$time$suffix';
  }
}

/// What every write service composes (BE-10's runtime half): the session
/// and permission checks, the device code, counter allocation, the pure
/// plan builders, the committer and the sync ledger.
///
/// The order for a numbered write is fixed: permission → device → input
/// check (the plan built once as a dry run, so bad input never uses up a
/// number) → allocate (persisted and flushed, 03-SYNC §3) → build → commit
/// locally → ledger.
final class WriteEnv {
  WriteEnv({
    required SessionContext? Function() session,
    required String? Function() deviceId,
    required this.counters,
    required this.committer,
    required this.ledger,
    required this.reads,
    DateTime Function()? clock,
    IdGenerator? ids,
    this.onCommitted,
  }) : _session = session,
       _deviceId = deviceId,
       now = clock ?? DateTime.now,
       ids = ids ?? IdGenerator(clock: clock);

  final SessionContext? Function() _session;
  final String? Function() _deviceId;
  final CounterStore counters;
  final PlanCommitter committer;
  final SyncLedger ledger;
  final WriteReads reads;
  final DateTime Function() now;
  final IdGenerator ids;

  /// Told about every local commit and the ledger paths it added, so the
  /// sync service can watch the batch's server acknowledgement
  /// ([LedgerCheck.ack]).
  final void Function(List<String> paths, Future<void> serverAck)? onCommitted;

  /// Devices whose counters were recovered in this process.
  final Set<String> _recovered = {};

  SessionContext requireSession() {
    final s = _session();
    if (s == null) {
      throw const DataFailure(FailureReason.notPermitted, 'signed out');
    }
    return s;
  }

  /// The signed-in user's own location, where they have [permission]
  /// (04-PERMISSIONS `canAt`); otherwise `DataFailure(notPermitted)`.
  String requireAtOwnLocation(String permission) {
    final s = requireSession();
    final loc = s.location?.code ?? s.user.locationId;
    if (loc == null || !s.canAt(permission, loc)) {
      throw DataFailure(FailureReason.notPermitted, permission);
    }
    return loc;
  }

  /// [permission] at [locationId].
  SessionContext requireAt(String permission, String locationId) {
    final s = requireSession();
    if (!s.canAt(permission, locationId)) {
      throw DataFailure(
        FailureReason.notPermitted,
        '$permission at $locationId',
      );
    }
    return s;
  }

  /// [permission] anywhere (global actions such as `catalog.manage`).
  SessionContext require(String permission) {
    final s = requireSession();
    if (!s.can(permission)) {
      throw DataFailure(FailureReason.notPermitted, permission);
    }
    return s;
  }

  String requireDevice() {
    final d = _deviceId();
    if (d == null || !Ids.isDeviceCode(d)) {
      throw const DataFailure(FailureReason.deviceNotRegistered);
    }
    return d;
  }

  PlanContext context(
    SessionContext s, {
    String? locationId,
    required DateTime at,
  }) => PlanContext(
    uid: s.user.uid,
    locationId: locationId ?? s.location?.code ?? s.user.locationId,
    deviceId: _deviceId(),
    now: at,
  );

  /// A numbered write: builds the plan once with the next number as a dry
  /// run (pure, nothing is stored), then allocates the number for real,
  /// which is on disk before [build] runs again, and writes the plan.
  Future<T> numbered<T>({
    required String locationId,
    required String deviceId,
    required SeqKind kind,
    required PlannedWrite<T> Function(int seq) build,
    required String Function(T value) label,
  }) async {
    await _recoverOnce(locationId, deviceId);
    final probe = counters.current(deviceId, kind) + 1;
    if (probe <= Ids.maxSeq) build(probe);
    final seq = await counters.next(deviceId, kind);
    final planned = build(seq);
    await write(planned.plan, label: label(planned.value));
    return planned.value;
  }

  /// Commits [plan] locally and records its new docs in the ledger.
  ///
  /// Once the batch is committed this never throws: the write has happened,
  /// and an error here would make the UI offer a retry that writes it
  /// twice. A ledger write that fails only costs the verification.
  Future<CommittedPlan> write(
    WritePlan plan, {
    String label = '',
    bool includeAudit = false,
  }) async {
    final uid = requireSession().user.uid;
    final committed = await committer.commit(plan);
    try {
      final at = now();
      final paths = ledgerPaths(plan, includeAudit: includeAudit);
      onCommitted?.call(paths, committed.serverAck);
      await ledger.addAll([
        for (final path in paths)
          LedgerEntry(
            path: path,
            uid: uid,
            createdAt: at,
            label: label,
            check: _isAudit(path) ? LedgerCheck.ack : LedgerCheck.serverGet,
          ),
      ]);
    } on Object {
      // See above.
    }
    return committed;
  }

  static bool _isAudit(String path) =>
      path.startsWith('${FirestorePaths.auditLog}/');

  /// The docs of [plan] the ledger verifies: every doc it creates. Audit
  /// docs only with [includeAudit] (an override, whose audit is its only
  /// doc), and then by the batch's acknowledgement, since a Store Manager
  /// can't read `auditLog` back (04-PERMISSIONS #10). Otherwise the entity
  /// the audit describes is verified instead.
  static List<String> ledgerPaths(
    WritePlan plan, {
    bool includeAudit = false,
  }) => [
    for (final op in plan.ops)
      if (op.kind == WriteKind.create && (includeAudit || !_isAudit(op.path)))
        op.path,
  ];

  /// Counters become `max(local, device.last*Seq)` once per process, before
  /// the first number is handed out (03-SYNC §3.4). The device doc comes
  /// from the server or the cache; if neither has it, the local counters
  /// stand.
  Future<void> _recoverOnce(String locationId, String deviceId) async {
    if (_recovered.contains(deviceId)) return;
    try {
      final d = await reads
          .device(locationId, deviceId)
          .timeout(const Duration(seconds: 10));
      if (d != null) await counters.recover(d);
      _recovered.add(deviceId);
    } on TimeoutException {
      // Try again on the next write.
    } on DataFailure {
      // Unreadable now; the local counters stand. Try again next time.
    }
  }
}
