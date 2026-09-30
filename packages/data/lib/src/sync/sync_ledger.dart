import 'dart:async';

import 'package:hive_ce/hive_ce.dart';

import '../api/sync.dart';

/// How the sync pass decides that a ledger entry landed.
enum LedgerCheck {
  /// A server read of the doc (03-SYNC §6.2). For bills, returns,
  /// movements and the other docs the writer may read back.
  serverGet,

  /// The batch's own server acknowledgement, for docs the writer can't read
  /// back, such as an OFFLINE_OVERRIDE audit written by a Store Manager
  /// without `audit.view`. If the app was restarted in between, the entry
  /// is taken as landed once `waitForPendingWrites` finishes.
  ack,
}

/// One doc written on this device and not yet confirmed on the server.
final class LedgerEntry {
  const LedgerEntry({
    required this.path,
    required this.uid,
    required this.createdAt,
    this.label = '',
    this.check = LedgerCheck.serverGet,
  });

  factory LedgerEntry.fromMap(Map<Object?, Object?> m) => LedgerEntry(
    path: m['path']! as String,
    uid: m['uid']! as String,
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      m['createdAt']! as int,
      isUtc: true,
    ),
    label: (m['label'] as String?) ?? '',
    check: LedgerCheck.values.firstWhere(
      (c) => c.name == m['check'],
      orElse: () => LedgerCheck.serverGet,
    ),
  );

  /// The doc's path from the database root.
  final String path;

  /// Who wrote it. Firestore queues writes per user, so only the signed-in
  /// user's entries can be verified.
  final String uid;
  final DateTime createdAt;

  /// What the Store Manager needs to re-enter it if the server rejects it,
  /// e.g. the bill number, total and lines. Kept here because a rejected
  /// write is also removed from the local cache.
  final String label;
  final LedgerCheck check;

  Map<String, Object?> toMap() => {
    'path': path,
    'uid': uid,
    'createdAt': createdAt.toUtc().millisecondsSinceEpoch,
    'label': label,
    'check': check.name,
  };
}

/// The local pending-write ledger (03-SYNC §6), and the sync errors it has
/// produced. Both survive restarts.
abstract interface class SyncLedger {
  /// Entries in the order they were added. One entry per path: adding a
  /// path again keeps the first entry.
  List<LedgerEntry> get entries;

  /// Adds [entries] and flushes them to disk before completing.
  Future<void> addAll(Iterable<LedgerEntry> entries);

  Future<void> remove(String path);

  /// Server rejections, oldest first.
  List<SyncError> get errors;

  Future<void> addError(SyncError error);

  /// Emits after every change to [entries] or [errors].
  Stream<void> get changes;
}

/// [SyncLedger] in memory. [LedgerDisk] survives "restarts" in tests: build
/// a new ledger on the same disk to simulate one.
final class MemorySyncLedger implements SyncLedger {
  MemorySyncLedger([LedgerDisk? disk]) : disk = disk ?? LedgerDisk();

  final LedgerDisk disk;
  final _changes = StreamController<void>.broadcast(sync: true);

  @override
  List<LedgerEntry> get entries => List.unmodifiable(disk.entries.values);

  @override
  Future<void> addAll(Iterable<LedgerEntry> entries) async {
    for (final e in entries) {
      disk.entries.putIfAbsent(e.path, () => e);
    }
    _changes.add(null);
  }

  @override
  Future<void> remove(String path) async {
    if (disk.entries.remove(path) != null) _changes.add(null);
  }

  @override
  List<SyncError> get errors => List.unmodifiable(disk.errors);

  @override
  Future<void> addError(SyncError error) async {
    disk.errors.add(error);
    _changes.add(null);
  }

  @override
  Stream<void> get changes => _changes.stream;
}

/// The state of a [MemorySyncLedger] that outlives it.
final class LedgerDisk {
  final Map<String, LedgerEntry> entries = {};
  final List<SyncError> errors = [];
}

/// [SyncLedger] on a Hive box (`pending` by default, 03-SYNC §6). Entries
/// are keyed by path; errors live under one key. Every write is flushed.
final class HiveSyncLedger implements SyncLedger {
  HiveSyncLedger._(this._box);

  static const String defaultBox = 'pending';
  static const String _errorsKey = '__errors__';

  /// Sync errors kept on the device; the oldest are dropped beyond this.
  static const int maxErrors = 500;

  static Future<HiveSyncLedger> open({String name = defaultBox}) async =>
      HiveSyncLedger._(await Hive.openBox<Object>(name));

  final Box<Object> _box;
  final _changes = StreamController<void>.broadcast(sync: true);

  @override
  List<LedgerEntry> get entries {
    final out = [
      for (final k in _box.keys)
        if (k != _errorsKey)
          if (_box.get(k) case final Map<Object?, Object?> m)
            LedgerEntry.fromMap(m),
    ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return out;
  }

  @override
  Future<void> addAll(Iterable<LedgerEntry> entries) async {
    var added = false;
    for (final e in entries) {
      if (_box.containsKey(e.path)) continue;
      await _box.put(e.path, e.toMap());
      added = true;
    }
    if (!added) return;
    await _box.flush();
    _changes.add(null);
  }

  @override
  Future<void> remove(String path) async {
    if (!_box.containsKey(path)) return;
    await _box.delete(path);
    await _box.flush();
    _changes.add(null);
  }

  @override
  List<SyncError> get errors {
    final raw = _box.get(_errorsKey);
    if (raw is! List) return const [];
    return [
      for (final m in raw.whereType<Map<Object?, Object?>>())
        SyncError(
          path: m['path']! as String,
          detail: m['detail']! as String,
          at: DateTime.fromMillisecondsSinceEpoch(m['at']! as int, isUtc: true),
        ),
    ];
  }

  @override
  Future<void> addError(SyncError error) async {
    final all = [...errors, error];
    final kept = all.length > maxErrors
        ? all.sublist(all.length - maxErrors)
        : all;
    await _box.put(_errorsKey, [
      for (final e in kept)
        {
          'path': e.path,
          'detail': e.detail,
          'at': e.at.toUtc().millisecondsSinceEpoch,
        },
    ]);
    await _box.flush();
    _changes.add(null);
  }

  @override
  Stream<void> get changes => _changes.stream;

  Future<void> close() => _box.close();
}
