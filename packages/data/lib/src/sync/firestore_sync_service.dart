import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nexus_core/nexus_core.dart';

import '../api/failures.dart';
import '../api/sync.dart';
import '../firestore/failure_mapping.dart';
import '../plans/offline_plans.dart';
import '../write/plan_committer.dart';
import 'connectivity.dart';
import 'local_sync_state.dart';
import 'sync_ledger.dart';

/// What a server read of a ledger entry found.
enum DocCheck {
  exists,
  missing,

  /// The rules deny the read: the doc may be at another location, or the
  /// user was disabled. Either way it can't be confirmed.
  denied,
}

/// The Firestore calls a sync pass makes. Implementations throw
/// `DataFailure(offline)` when the server can't be reached.
abstract interface class SyncBackend {
  /// `waitForPendingWrites()`: every write queued so far (by this user,
  /// including earlier app sessions) was accepted or rejected.
  Future<void> waitForPendingWrites();

  /// One server read that proves the server is reachable now. A pass with
  /// nothing in the ledger and nothing pending would otherwise "finish"
  /// offline and move `lastSyncAt` without any contact (QA-025).
  Future<void> ping(String uid);

  /// A server read of [path] (`Source.server`).
  Future<DocCheck> check(String path);

  /// Sets `lastSeenAt` on the device doc to the server time. Committed
  /// locally; not awaited on the server.
  Future<void> touchLastSeen(String locationId, String deviceId);
}

/// [SyncBackend] on a [FirebaseFirestore] instance.
final class FirestoreSyncBackend implements SyncBackend {
  FirestoreSyncBackend(this.db, this.committer);

  final FirebaseFirestore db;
  final PlanCommitter committer;

  static const GetOptions _server = GetOptions(source: Source.server);

  @override
  Future<void> waitForPendingWrites() =>
      guardFirestore(db.waitForPendingWrites);

  @override
  Future<void> ping(String uid) async {
    try {
      await db.doc(FirestorePaths.user(uid)).get(_server);
    } on FirebaseException catch (e) {
      final f = failureFromFirestore(e);
      // A denial is still an answer from the server.
      if (f.reason != FailureReason.notPermitted) throw f;
    }
  }

  @override
  Future<DocCheck> check(String path) async {
    try {
      final s = await db.doc(path).get(_server);
      return s.exists ? DocCheck.exists : DocCheck.missing;
    } on FirebaseException catch (e) {
      final f = failureFromFirestore(e);
      if (f.reason == FailureReason.notPermitted) return DocCheck.denied;
      if (f.reason == FailureReason.notFound) return DocCheck.missing;
      throw f.reason == FailureReason.unknown
          ? DataFailure(FailureReason.offline, f.detail)
          : f;
    }
  }

  @override
  Future<void> touchLastSeen(String locationId, String deviceId) async {
    await committer.commit(
      OfflinePlans.lastSeen(locationId: locationId, deviceId: deviceId),
    );
  }
}

/// This install's location and device code.
typedef DeviceRef = ({String locationId, String deviceId});

/// [SyncService] (BE-12, 03-SYNC §6).
///
/// **Sync pass**, one at a time: `waitForPendingWrites` (at most
/// [pendingTimeout]); a server read that proves the server answers
/// ([SyncBackend.ping]); then a server read of every ledger entry of the
/// signed-in user. Found → removed; missing or unreadable → a [SyncError]
/// (with the entry's label, since the rejected doc is gone from the cache
/// too) and removed. When all of that finished, `lastSyncAt = now`
/// (persisted) and, at most every [lastSeenEvery], `lastSeenAt` on the
/// device doc. A timeout or an unreachable server ends the pass early and
/// leaves `lastSyncAt` alone.
///
/// **`lastSyncAt`** also moves on an interactive online sign-in
/// ([markSynced], wired to `FirebaseAuthService.interactiveSignIns`) and on
/// device registration. Restoring a session at start-up does not move it;
/// nor does starting the app. It is read from and written to the durable
/// store, so it survives restarts (QA-025).
///
/// **Triggers:** the network coming back, [appResumed], every [interval]
/// while online, and [syncNow].
///
/// **Status:** Offline(since) while the network is down or the last pass
/// couldn't reach the server; Syncing(n) while the user has n unconfirmed
/// ledger entries; Online otherwise.
final class FirestoreSyncService implements SyncService {
  FirestoreSyncService({
    required SyncBackend backend,
    required SyncLedger ledger,
    required LocalSyncState state,
    required NetworkMonitor network,
    required String? Function() uid,
    required DeviceRef? Function() device,
    DateTime Function()? clock,
    this.pendingTimeout = const Duration(seconds: 30),
    this.interval = const Duration(minutes: 2),
    this.lastSeenEvery = const Duration(minutes: 5),
    this.ackWait = const Duration(seconds: 2),
  }) : _backend = backend,
       _ledger = ledger,
       _state = state,
       _network = network,
       _uid = uid,
       _device = device,
       _now = clock ?? DateTime.now;

  final SyncBackend _backend;
  final SyncLedger _ledger;
  final LocalSyncState _state;
  final NetworkMonitor _network;
  final String? Function() _uid;
  final DeviceRef? Function() _device;
  final DateTime Function() _now;

  final Duration pendingTimeout;
  final Duration interval;
  final Duration lastSeenEvery;

  /// How long a pass waits for a batch's own acknowledgement
  /// ([LedgerCheck.ack]) after `waitForPendingWrites` finished.
  final Duration ackWait;

  final _statusOut = StreamController<SyncStatus>.broadcast(sync: true);
  final List<StreamSubscription<Object?>> _subs = [];
  Timer? _timer;

  bool _networkUp = true;
  bool _serverReachable = true;
  DateTime? _offlineSince;
  SyncStatus? _last;
  Future<void>? _running;
  bool _disposed = false;

  /// Server outcomes of batches committed in this process, by ledger path:
  /// '' when accepted, the error otherwise.
  final Map<String, Future<String>> _acks = {};

  /// Starts the triggers. [interactiveSignIns] is
  /// `FirebaseAuthService.interactiveSignIns`.
  Future<void> start({Stream<void>? interactiveSignIns}) async {
    _networkUp = await _network.isOnline();
    if (!_networkUp) _offlineSince = _state.lastSyncAt ?? _now();
    _subs
      ..add(_network.changes.listen(_onNetwork))
      ..add(_ledger.changes.listen((_) => _emit()));
    if (interactiveSignIns != null) {
      _subs.add(interactiveSignIns.listen((_) => unawaited(markSynced())));
    }
    _timer = Timer.periodic(interval, (_) {
      if (_networkUp) unawaited(_trigger());
    });
    _emit();
    if (_networkUp) unawaited(_trigger());
  }

  Future<void> dispose() async {
    _disposed = true;
    _timer?.cancel();
    for (final s in _subs) {
      await s.cancel();
    }
    await _statusOut.close();
  }

  /// The app came back to the foreground.
  void appResumed() => unawaited(_trigger());

  /// An interactive online sign-in or a registration: the device was just
  /// in contact with the server (03-SYNC §6.4).
  Future<void> markSynced() async {
    _serverReachable = true;
    await _state.setLastSyncAt(_now());
    _emit();
  }

  /// Emits whenever `lastSyncAt` or the override changes.
  Stream<void> get lastSyncChanges => _state.changes;

  /// Called for each local commit with the ledger paths it added.
  void observeAck(List<String> paths, Future<void> serverAck) {
    if (paths.isEmpty) return;
    final outcome = serverAck.then<String>(
      (_) => '',
      onError: (Object e) => e is DataFailure ? e.toString() : '$e',
    );
    for (final p in paths) {
      _acks[p] = outcome;
    }
  }

  @override
  DateTime? get lastSyncAt => _state.lastSyncAt;

  @override
  Stream<SyncStatus> get status => Stream.multi((c) {
    c.add(_compute());
    final sub = _statusOut.stream.listen(c.add);
    c.onCancel = sub.cancel;
  });

  @override
  Stream<List<SyncError>> get errors => Stream.multi((c) {
    c.add(_ledger.errors);
    final sub = _ledger.changes.listen((_) => c.add(_ledger.errors));
    c.onCancel = sub.cancel;
  });

  /// Runs a pass now. If one is already running, waits for it and then
  /// runs another, so every write made before this call is covered.
  @override
  Future<void> syncNow() async {
    final running = _running;
    if (running != null) await running;
    await _trigger();
  }

  void _onNetwork(bool up) {
    if (up == _networkUp) return;
    _networkUp = up;
    if (!up) {
      _offlineSince ??= _now();
    } else {
      _serverReachable = true;
    }
    _emit();
    if (up) unawaited(_trigger());
  }

  Future<void> _trigger() {
    final running = _running;
    if (running != null) return running;
    final pass = _pass().whenComplete(() {
      _running = null;
      _emit();
    });
    return _running = pass;
  }

  int get _pending {
    final uid = _uid();
    if (uid == null) return 0;
    return _ledger.entries.where((e) => e.uid == uid).length;
  }

  SyncStatus _compute() {
    if (!_networkUp || !_serverReachable) {
      return Offline(_offlineSince ?? _now());
    }
    final n = _pending;
    return n > 0 ? Syncing(n) : const Online();
  }

  void _emit() {
    if (_disposed) return;
    final next = _compute();
    if (next is Offline) {
      _offlineSince ??= next.since;
    } else {
      _offlineSince = null;
    }
    if (_same(next, _last)) return;
    _last = next;
    _statusOut.add(next);
  }

  static bool _same(SyncStatus a, SyncStatus? b) => switch ((a, b)) {
    (Online(), Online()) => true,
    (Syncing(pending: final x), Syncing(pending: final y)) => x == y,
    (Offline(since: final x), Offline(since: final y)) => x == y,
    _ => false,
  };

  void _unreachable() {
    if (_serverReachable) {
      _serverReachable = false;
      _offlineSince ??= _now();
    }
  }

  Future<void> _pass() async {
    final uid = _uid();
    if (uid == null || _disposed) return;
    try {
      await _backend.waitForPendingWrites().timeout(pendingTimeout);
    } on TimeoutException {
      return; // Still pending: not finished.
    } on DataFailure catch (f) {
      if (f.reason == FailureReason.offline) _unreachable();
      return;
    } on Object {
      return; // E.g. rejected because the user changed: not finished.
    }
    try {
      await _backend.ping(uid);
    } on Object {
      _unreachable();
      return;
    }
    _serverReachable = true;
    _emit();

    for (final e in _ledger.entries) {
      if (e.uid != uid) continue;
      final String? problem;
      if (e.check == LedgerCheck.ack) {
        problem = await _ackProblem(e.path);
      } else {
        final DocCheck found;
        try {
          found = await _backend.check(e.path);
        } on Object {
          _unreachable();
          return;
        }
        problem = switch (found) {
          DocCheck.exists => null,
          DocCheck.missing => 'not on the server: the server rejected it',
          DocCheck.denied =>
            "can't be read back (permission denied): the server rejected it "
                'or the user was disabled',
        };
      }
      if (problem != null) {
        final label = e.label.isEmpty ? e.path : e.label;
        if (!_ledger.errors.any((x) => x.path == e.path)) {
          await _ledger.addError(
            SyncError(path: e.path, detail: '$label: $problem', at: _now()),
          );
        }
      }
      await _ledger.remove(e.path);
      _acks.removeWhere((path, _) => path == e.path);
    }

    final now = _now();
    await _state.setLastSyncAt(now);
    await _touchLastSeen(now);
  }

  /// For [LedgerCheck.ack] entries: the batch's error, or null when it was
  /// accepted or its outcome isn't known in this process (then
  /// `waitForPendingWrites` finishing is all there is to go on).
  Future<String?> _ackProblem(String path) async {
    final outcome = _acks[path];
    if (outcome == null) return null;
    try {
      final r = await outcome.timeout(ackWait);
      return r.isEmpty ? null : 'rejected by the server ($r)';
    } on TimeoutException {
      return null;
    }
  }

  Future<void> _touchLastSeen(DateTime now) async {
    final d = _device();
    if (d == null) return;
    final last = _state.lastSeenWrittenAt;
    if (last != null && now.difference(last) < lastSeenEvery) return;
    try {
      await _backend.touchLastSeen(d.locationId, d.deviceId);
      await _state.setLastSeenWrittenAt(now);
    } on Object {
      // Best effort; tried again on the next pass.
    }
  }
}
