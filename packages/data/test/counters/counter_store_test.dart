import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';

/// A store whose writes complete only when the test says so, and which
/// records what reached "disk".
final class _SlowStore implements DurableStore {
  final Map<String, Object> disk = {};
  final List<Completer<void>> pending = [];

  @override
  Object? read(String key) => disk[key];

  @override
  Future<void> write(String key, Object value) async {
    final c = Completer<void>();
    pending.add(c);
    await c.future;
    disk[key] = value;
  }
}

final class _FailingStore implements DurableStore {
  _FailingStore(this.disk);
  final Map<String, Object> disk;
  bool fail = true;

  @override
  Object? read(String key) => disk[key];

  @override
  Future<void> write(String key, Object value) async {
    if (fail) throw const FileSystemException('disk full');
    disk[key] = value;
  }
}

Device _device(String code, {int bill = 0, int movement = 0, int ret = 0}) =>
    Device(
      code: code,
      label: 'Counter',
      registeredBy: 'sm-ptb',
      lastBillSeq: bill,
      lastMovementSeq: movement,
      lastReturnSeq: ret,
      retired: false,
    );

void main() {
  test('numbers start at 1 and go up, per device and per kind', () async {
    final s = CounterStore(MemoryDurableStore());
    expect(await s.next('D01', SeqKind.bill), 1);
    expect(await s.next('D01', SeqKind.bill), 2);
    expect(await s.next('D01', SeqKind.movement), 1);
    expect(await s.next('D01', SeqKind.returned), 1);
    expect(await s.next('D02', SeqKind.bill), 1);
    expect(s.current('D01', SeqKind.bill), 2);
  });

  test('persists and flushes before returning the number', () async {
    final store = _SlowStore();
    final s = CounterStore(store);
    int? got;
    unawaited(s.next('D01', SeqKind.bill).then((n) => got = n));
    await pumpEventQueue();
    expect(got, isNull, reason: 'returned before the write completed');
    expect(store.disk, isEmpty);
    store.pending.single.complete();
    await pumpEventQueue();
    expect(got, 1);
    expect(store.disk[CounterStore.key('D01', SeqKind.bill)], 1);
  });

  test('overlapping calls (a double tap) never get the same number, and the '
      'writes land in order', () async {
    final store = _SlowStore();
    final s = CounterStore(store);
    final a = s.next('D01', SeqKind.bill);
    final b = s.next('D01', SeqKind.bill);
    await pumpEventQueue();
    // One write at a time: the second starts after the first is on disk.
    expect(store.pending, hasLength(1));
    store.pending.first.complete();
    await pumpEventQueue();
    expect(store.pending, hasLength(2));
    store.pending.last.complete();
    expect({await a, await b}, {1, 2});
    expect(store.disk[CounterStore.key('D01', SeqKind.bill)], 2);
  });

  test('kill after allocate: the number is skipped, never reused', () async {
    final disk = <String, Object>{};
    final before = CounterStore(MemoryDurableStore(disk));
    expect(await before.next('D01', SeqKind.bill), 1);
    final allocated = await before.next('D01', SeqKind.bill);
    expect(allocated, 2);
    // The app dies here: bill 2's plan was never built or committed, so the
    // device doc still says lastBillSeq 1.

    final after = CounterStore(MemoryDurableStore(disk));
    await after.recover(_device('D01', bill: 1));
    final next = await after.next('D01', SeqKind.bill);
    expect(next, 3);
    expect(Ids.billId('D01', next), isNot(Ids.billId('D01', allocated)));
  });

  test(
    'a failed write returns no number, and that number is skipped',
    () async {
      final disk = <String, Object>{};
      final store = _FailingStore(disk);
      final s = CounterStore(store);
      await expectLater(
        s.next('D01', SeqKind.movement),
        throwsA(isA<FileSystemException>()),
      );
      store.fail = false;
      expect(await s.next('D01', SeqKind.movement), 2);
    },
  );

  test('recovery takes max(local, device.last*Seq) for each counter', () async {
    final disk = <String, Object>{};
    final s = CounterStore(MemoryDurableStore(disk));
    for (var i = 0; i < 5; i++) {
      await s.next('D01', SeqKind.bill);
    }
    await s.next('D01', SeqKind.returned);
    // Server: bills behind (offline writes not synced yet), movements and
    // returns ahead (local data lost).
    await s.recover(_device('D01', bill: 3, movement: 41, ret: 7));
    expect(s.current('D01', SeqKind.bill), 5);
    expect(s.current('D01', SeqKind.movement), 41);
    expect(s.current('D01', SeqKind.returned), 7);
    expect(await s.next('D01', SeqKind.bill), 6);
    expect(await s.next('D01', SeqKind.movement), 42);
    expect(await s.next('D01', SeqKind.returned), 8);
    // The recovered values are on disk too.
    final restarted = CounterStore(MemoryDurableStore(disk));
    expect(restarted.current('D01', SeqKind.movement), 42);
  });

  test(
    'cleared local data on the same device recovers from the device doc',
    () async {
      final s = CounterStore(MemoryDurableStore());
      await s.recover(_device('D01', bill: 123));
      expect(await s.next('D01', SeqKind.bill), 124);
    },
  );

  test(
    'reinstall: a new store and a new device code start a new series',
    () async {
      final old = CounterStore(MemoryDurableStore());
      final used = {
        for (var i = 0; i < 3; i++)
          Ids.billId('D01', await old.next('D01', SeqKind.bill)),
      };
      // Reinstall: the store is empty and registration gave D02 (D-004).
      final fresh = CounterStore(MemoryDurableStore());
      await fresh.recover(_device('D02'));
      final first = Ids.billId('D02', await fresh.next('D02', SeqKind.bill));
      expect(first, 'D02-000001');
      expect(used, isNot(contains(first)));
    },
  );

  test('refuses an unregistered device and stops at Ids.maxSeq', () async {
    final s = CounterStore(
      MemoryDurableStore({CounterStore.key('D01', SeqKind.bill): Ids.maxSeq}),
    );
    await expectLater(s.next('D01', SeqKind.bill), throwsA(isA<DataFailure>()));
    await expectLater(
      s.next('', SeqKind.bill),
      throwsA(
        isA<DataFailure>().having(
          (f) => f.reason,
          'reason',
          FailureReason.deviceNotRegistered,
        ),
      ),
    );
  });

  group('HiveDurableStore', () {
    late Directory dir;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('counters');
      Hive.init(dir.path);
    });
    tearDown(() async {
      await Hive.close();
      dir.deleteSync(recursive: true);
    });

    test('a number survives closing and reopening the box', () async {
      final store = await HiveDurableStore.open(name: 'counters_test');
      final s = CounterStore(store);
      expect(await s.next('D01', SeqKind.bill), 1);
      expect(await s.next('D01', SeqKind.bill), 2);
      await store.close();

      final reopened = await HiveDurableStore.open(name: 'counters_test');
      final again = CounterStore(reopened);
      expect(again.current('D01', SeqKind.bill), 2);
      expect(await again.next('D01', SeqKind.bill), 3);
      await reopened.write('device.id', 'D01');
      expect(reopened.read('device.id'), 'D01');
    });
  });
}
