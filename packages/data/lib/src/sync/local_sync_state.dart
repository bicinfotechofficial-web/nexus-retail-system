import 'dart:async';

import '../counters/durable_store.dart';

/// The sync and offline-limit times that must survive restarts and reboots
/// (03-SYNC §6–7, QA-025): `lastSyncAt`, the end of an active PIN override,
/// and when `lastSeenAt` was last written. Kept in the device's durable
/// store next to the counters and flushed on every write. Nothing here
/// changes on app start or when a saved session is restored.
final class LocalSyncState {
  LocalSyncState(this._store);

  static const String lastSyncKey = 'sync.lastSyncAt';
  static const String overrideUntilKey = 'sync.overrideUntil';
  static const String overrideAtKey = 'sync.overrideAt';
  static const String lastSeenKey = 'sync.lastSeenWrittenAt';

  final DurableStore _store;
  final _changes = StreamController<void>.broadcast(sync: true);

  /// Emits after every change.
  Stream<void> get changes => _changes.stream;

  DateTime? _read(String key) {
    final v = _store.read(key);
    return v is int && v > 0
        ? DateTime.fromMillisecondsSinceEpoch(v, isUtc: true)
        : null;
  }

  Future<void> _write(String key, DateTime? value) async {
    await _store.write(key, value?.toUtc().millisecondsSinceEpoch ?? 0);
    _changes.add(null);
  }

  DateTime? get lastSyncAt => _read(lastSyncKey);

  /// Always the latest event's time, even if the device clock went back
  /// (a clock corrected backwards must not leave it in the future).
  Future<void> setLastSyncAt(DateTime at) => _write(lastSyncKey, at);

  /// The end of the active PIN override, or null.
  DateTime? get overrideUntil => _read(overrideUntilKey);

  /// When the active override was granted.
  DateTime? get overrideAt => _read(overrideAtKey);

  Future<void> setOverride({
    required DateTime at,
    required DateTime until,
  }) async {
    await _store.write(overrideAtKey, at.toUtc().millisecondsSinceEpoch);
    await _write(overrideUntilKey, until);
  }

  Future<void> clearOverride() async {
    await _store.write(overrideAtKey, 0);
    await _write(overrideUntilKey, null);
  }

  DateTime? get lastSeenWrittenAt => _read(lastSeenKey);

  Future<void> setLastSeenWrittenAt(DateTime at) => _write(lastSeenKey, at);
}
