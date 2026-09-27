import 'package:hive_ce/hive_ce.dart';

/// A small local key-value store whose writes are on disk when they
/// complete (03-SYNC §3). Behind an interface so the counter logic is
/// tested without a device.
abstract interface class DurableStore {
  /// The stored value, or null.
  Object? read(String key);

  /// Stores [value] and flushes it to disk before completing.
  Future<void> write(String key, Object value);
}

/// [DurableStore] on a Hive box (`hive_ce`). The app calls `Hive.init` (or
/// `Hive.initFlutter`) once before [open].
final class HiveDurableStore implements DurableStore {
  HiveDurableStore(this._box);

  /// The box the POS keeps its device code and counters in.
  static const String defaultBox = 'device';

  static Future<HiveDurableStore> open({String name = defaultBox}) async =>
      HiveDurableStore(await Hive.openBox<Object>(name));

  final Box<Object> _box;

  @override
  Object? read(String key) => _box.get(key);

  @override
  Future<void> write(String key, Object value) async {
    await _box.put(key, value);
    await _box.flush();
  }

  Future<void> close() => _box.close();
}

/// An in-memory [DurableStore], for tests and previews. [disk] survives
/// "restarts": build a new store on the same map to simulate one.
final class MemoryDurableStore implements DurableStore {
  MemoryDurableStore([Map<String, Object>? disk]) : disk = disk ?? {};

  final Map<String, Object> disk;

  @override
  Object? read(String key) => disk[key];

  @override
  Future<void> write(String key, Object value) async => disk[key] = value;
}
