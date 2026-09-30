import 'dart:async';
import 'dart:core' as core show override;
import 'dart:core';

import 'package:nexus_core/nexus_core.dart';

import '../api/failures.dart';
import '../api/session.dart';
import '../api/sync.dart';
import '../plans/offline_plans.dart';
import '../plans/pin_hasher.dart';
import '../write/write_env.dart';
import 'local_sync_state.dart';

/// [OfflineGuard] (BE-13, 03-SYNC §7, D-016), worked out on the device from
/// the persisted `lastSyncAt` and override end, the device clock, and the
/// session's cached location.
///
/// - `elapsed = now − lastSyncAt`, `limit = offlineLimitHours` (default 5).
/// - `elapsed ≥ 0.8 × limit`: [NearLimit], counting down to the limit.
/// - `elapsed ≥ limit`: [BillingBlocked].
/// - During a PIN override: [NearLimit] counting down to the override's end,
///   and [BillingBlocked] again after it unless a sync happened meanwhile.
///   A sync after the override was granted ends it: the normal rule
///   applies again from the new `lastSyncAt`.
/// - No `lastSyncAt` yet (before registration): [WithinLimit].
///
/// [state] emits the current state on listen, then every change, re-checked
/// every [tick] and whenever `lastSyncAt`, the override or the session
/// changes.
final class LocalOfflineGuard implements OfflineGuard {
  LocalOfflineGuard({
    required LocalSyncState syncState,
    required SessionContext? Function() session,
    required WriteEnv env,
    PinHasher? hasher,
    DateTime Function()? clock,
    this.tick = const Duration(seconds: 30),
    Stream<Object?>? sessionChanges,
  }) : _sync = syncState,
       _session = session,
       _env = env,
       _hasher = hasher ?? PinHasher(),
       _now = clock ?? DateTime.now,
       _sessionChanges = sessionChanges;

  final LocalSyncState _sync;
  final SessionContext? Function() _session;
  final WriteEnv _env;
  final PinHasher _hasher;
  final DateTime Function() _now;
  final Stream<Object?>? _sessionChanges;
  final Duration tick;

  /// The state right now. The sales service checks it before every bill.
  OfflineState evaluate() {
    final now = _now();
    final loc = _session()?.location;
    final limit = Duration(
      hours: loc?.offlineLimitHours ?? Location.defaultOfflineLimitHours,
    );
    final last = _sync.lastSyncAt;
    final until = _activeOverrideEnd(now, last);
    if (until != null) {
      final normalEnd = last?.add(limit);
      if (normalEnd == null || !normalEnd.isAfter(until)) {
        return NearLimit(until.difference(now));
      }
    }
    if (last == null) return const WithinLimit();
    final elapsed = now.difference(last);
    if (elapsed >= limit) return const BillingBlocked();
    if (elapsed * 5 >= limit * 4) return NearLimit(limit - elapsed);
    return const WithinLimit();
  }

  /// The override's end while it is in force: granted, not yet over, and
  /// not superseded by a later sync.
  DateTime? _activeOverrideEnd(DateTime now, DateTime? last) {
    final until = _sync.overrideUntil;
    if (until == null || !now.isBefore(until)) return null;
    final at = _sync.overrideAt;
    if (last != null && at != null && last.isAfter(at)) return null;
    return until;
  }

  // `@override` would name the `override` method below.
  @core.override
  Stream<OfflineState> get state => Stream.multi((c) {
    OfflineState? last;
    void emit() {
      final next = evaluate();
      if (last != null && _same(next, last!)) return;
      last = next;
      c.add(next);
    }

    emit();
    final timer = Timer.periodic(tick, (_) => emit());
    final subs = [
      _sync.changes.listen((_) => emit()),
      if (_sessionChanges != null) _sessionChanges.listen((_) => emit()),
    ];
    c.onCancel = () async {
      timer.cancel();
      for (final s in subs) {
        await s.cancel();
      }
    };
  });

  /// Equal states; a countdown counts as changed once a minute has passed,
  /// which is the banner's resolution.
  static bool _same(OfflineState a, OfflineState b) => switch ((a, b)) {
    (WithinLimit(), WithinLimit()) => true,
    (BillingBlocked(), BillingBlocked()) => true,
    (NearLimit(billingStopsIn: final x), NearLimit(billingStopsIn: final y)) =>
      x.inMinutes == y.inMinutes,
    _ => false,
  };

  /// Checks [pin] against the cached location's `overridePinHash`. On a
  /// match, queues the OFFLINE_OVERRIDE audit (a plan committed locally and
  /// added to the ledger) and then stores the override's end, so billing
  /// works until `now + overrideExtensionHours`. A PIN that is wrong, or
  /// not the right shape, returns false and changes nothing.
  ///
  /// Throws `DataFailure(notPermitted)` when signed out or without
  /// `bill.create` at the location (the audit needs it), and
  /// `DataFailure(deviceNotRegistered)` before registration.
  @core.override
  Future<bool> override(String pin) async {
    final s = _session();
    final loc = s?.location;
    if (s == null || loc == null) {
      throw const DataFailure(FailureReason.notPermitted, 'no location');
    }
    if (!s.canAt(Permission.billCreate, loc.code)) {
      throw const DataFailure(FailureReason.notPermitted, 'bill.create');
    }
    _env.requireDevice();
    try {
      PinHasher.checkPin(pin);
    } on DataFailure {
      return false;
    }
    if (!await _hasher.verify(pin, loc.overridePinHash)) return false;

    final now = _now();
    final until = now.add(Duration(hours: loc.overrideExtensionHours));
    final plan = OfflinePlans.override(
      ctx: _env.context(s, locationId: loc.code, at: now),
      until: until,
      lastSyncAt: _sync.lastSyncAt,
    );
    await _env.write(
      plan,
      label: 'Offline override at ${loc.code} until ${until.toIso8601String()}',
      includeAudit: true,
    );
    await _sync.setOverride(at: now, until: until);
    return true;
  }
}
