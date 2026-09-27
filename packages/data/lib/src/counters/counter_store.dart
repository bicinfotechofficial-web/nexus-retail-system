import 'package:nexus_core/nexus_core.dart';

import '../api/failures.dart';
import 'durable_store.dart';

/// The three per-device sequences (03-SYNC §3).
enum SeqKind {
  /// Bill numbers: `D01-000123`. Recovered from `lastBillSeq`.
  bill,

  /// Stock movements: `D01-M000042`. Recovered from `lastMovementSeq`.
  movement,

  /// Returns: `D01-R000007`. Recovered from `lastReturnSeq`.
  returned;

  int lastUsedOn(Device d) => switch (this) {
    bill => d.lastBillSeq,
    movement => d.lastMovementSeq,
    returned => d.lastReturnSeq,
  };
}

/// Per-device sequence counters (BE-8, 03-SYNC §3, D-003).
///
/// [next] increments the counter and **persists and flushes it before it
/// returns** the number, so the plan is only built for a number already on
/// disk. If the app dies after that, the number is skipped, never used
/// twice. Counters are keyed by device code, so a new code (a reinstall,
/// D-004) starts its own series.
final class CounterStore {
  CounterStore(this._store);

  final DurableStore _store;

  /// Numbers handed out in this process but maybe not yet on disk. Read and
  /// bumped synchronously, so two overlapping [next] calls never get the
  /// same number.
  final Map<String, int> _handedOut = {};

  /// Writes run one at a time, in order, so a slower earlier write can
  /// never land after a later one and put a counter back.
  Future<void> _writes = Future.value();

  Future<void> _write(String k, int n) {
    final done = _writes.then((_) => _store.write(k, n));
    _writes = done.catchError((Object _) {});
    return done;
  }

  static String key(String deviceId, SeqKind kind) =>
      'seq.$deviceId.${kind.name}';

  /// The last number handed out for [kind] on [deviceId]; 0 before the first.
  int current(String deviceId, SeqKind kind) {
    final k = key(deviceId, kind);
    final stored = _store.read(k);
    final onDisk = stored is int ? stored : 0;
    final inMemory = _handedOut[k] ?? 0;
    return onDisk > inMemory ? onDisk : inMemory;
  }

  /// Allocates the next number: bumps it, writes and flushes it, then
  /// returns it. Throws `DataFailure(ruleViolation)` past `Ids.maxSeq`. If
  /// the write fails, the number is not returned and is skipped.
  Future<int> next(String deviceId, SeqKind kind) async {
    if (!Ids.isDeviceCode(deviceId)) {
      throw const DataFailure(FailureReason.deviceNotRegistered);
    }
    final n = current(deviceId, kind) + 1;
    if (n > Ids.maxSeq) {
      throw DataFailure(
        FailureReason.ruleViolation,
        '${kind.name} numbers for $deviceId are used up',
      );
    }
    final k = key(deviceId, kind);
    _handedOut[k] = n;
    await _write(k, n);
    return n;
  }

  /// On app start: each counter becomes `max(local, device.last*Seq)`, from
  /// the device doc in the cache or on the server (03-SYNC §3.4). Local
  /// numbers ahead of the doc (allocated, or written offline) are kept.
  Future<void> recover(Device device) async {
    for (final kind in SeqKind.values) {
      final remote = kind.lastUsedOn(device);
      if (remote > current(device.code, kind)) {
        final k = key(device.code, kind);
        _handedOut[k] = remote;
        await _write(k, remote);
      }
    }
  }
}
