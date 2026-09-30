import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_data/nexus_data.dart';

import '../write/support.dart';

/// The server as a sync pass sees it.
final class FakeSyncBackend implements SyncBackend {
  final Set<String> server = {};
  final Set<String> denied = {};
  bool reachable = true;
  Future<void> Function() wait = () async {};
  int waits = 0;
  int pings = 0;
  final List<String> checked = [];
  final List<DeviceRef> touches = [];

  @override
  Future<void> waitForPendingWrites() {
    waits++;
    return wait();
  }

  @override
  Future<void> ping(String uid) async {
    pings++;
    if (!reachable) throw const DataFailure(FailureReason.offline);
  }

  @override
  Future<DocCheck> check(String path) async {
    if (!reachable) throw const DataFailure(FailureReason.offline);
    checked.add(path);
    if (denied.contains(path)) return DocCheck.denied;
    return server.contains(path) ? DocCheck.exists : DocCheck.missing;
  }

  @override
  Future<void> touchLastSeen(String locationId, String deviceId) async =>
      touches.add((locationId: locationId, deviceId: deviceId));
}

final class Rig {
  Rig({
    Map<String, Object>? disk,
    LedgerDisk? ledgerDisk,
    bool online = true,
    FakeClock? clock,
  }) : store = MemoryDurableStore(disk),
       ledger = MemorySyncLedger(ledgerDisk),
       network = ManualNetworkMonitor(online: online),
       clock = clock ?? FakeClock() {
    state = LocalSyncState(store);
    sync = FirestoreSyncService(
      backend: backend,
      ledger: ledger,
      state: state,
      network: network,
      uid: () => uid,
      device: () => (locationId: 'PTB', deviceId: 'D01'),
      clock: this.clock.call,
    );
  }

  final MemoryDurableStore store;
  final MemorySyncLedger ledger;
  final ManualNetworkMonitor network;
  final FakeClock clock;
  final FakeSyncBackend backend = FakeSyncBackend();
  final signIns = StreamController<void>.broadcast(sync: true);
  late final LocalSyncState state;
  late final FirestoreSyncService sync;
  String? uid = 'sm-ptb';

  Future<void> start() => sync.start(interactiveSignIns: signIns.stream);

  Future<void> close() async {
    await sync.dispose();
    await signIns.close();
  }

  Future<void> add(
    String path, {
    String uid = 'sm-ptb',
    LedgerCheck check = LedgerCheck.serverGet,
  }) => ledger.addAll([
    LedgerEntry(
      path: path,
      uid: uid,
      createdAt: clock.now,
      label: 'Label of $path',
      check: check,
    ),
  ]);
}

const String b1 = 'locations/PTB/bills/D01-000001';
const String m1 = 'locations/PTB/movements/D01-000001';
const String b2 = 'locations/PTB/bills/D01-000002';

void main() {
  group('sync pass', () {
    late Rig r;

    setUp(() async {
      r = Rig();
      await r.start();
      await settle(); // The start-up pass (nothing to do).
    });

    tearDown(() => r.close());

    test('all confirmed: the ledger empties, lastSyncAt = now, lastSeenAt '
        'touched', () async {
      await r.add(b1);
      await r.add(m1);
      r.backend.server.addAll([b1, m1]);
      r.clock.advance(const Duration(minutes: 1));
      await r.sync.syncNow();
      expect(r.ledger.entries, isEmpty);
      expect(await r.sync.errors.first, isEmpty);
      expect(r.sync.lastSyncAt, r.clock.now);
      expect(r.backend.checked, [b1, m1]);
      expect(r.backend.touches, [(locationId: 'PTB', deviceId: 'D01')]);
      expect(await r.sync.status.first, isA<Online>());
    });

    test('one rejected: a SyncError with its label, the rest confirmed, and '
        'lastSyncAt still moves', () async {
      await r.add(b1);
      await r.add(b2);
      r.backend.server.add(b1);
      r.clock.advance(const Duration(minutes: 3));
      await r.sync.syncNow();
      final errors = await r.sync.errors.first;
      expect(errors.map((e) => e.path), [b2]);
      expect(errors.single.detail, contains('Label of $b2'));
      expect(errors.single.detail, contains('rejected'));
      expect(errors.single.at, r.clock.now);
      expect(r.ledger.entries, isEmpty);
      expect(r.sync.lastSyncAt, r.clock.now);
      // A second pass doesn't report it again.
      await r.sync.syncNow();
      expect(await r.sync.errors.first, hasLength(1));
    });

    test('unreadable (a disabled user, S8-2) is a sync error too', () async {
      await r.add(b1);
      r.backend.denied.add(b1);
      await r.sync.syncNow();
      expect(
        (await r.sync.errors.first).single.detail,
        contains('permission denied'),
      );
      expect(r.sync.lastSyncAt, isNotNull);
    });

    test('only the signed-in user\'s entries are checked (Firestore queues '
        'writes per user)', () async {
      await r.add(b1, uid: 'someone-else');
      await r.add(b2);
      r.backend.server.add(b2);
      await r.sync.syncNow();
      expect(r.backend.checked, [b2]);
      expect(r.ledger.entries.single.path, b1);
      expect(await r.sync.errors.first, isEmpty);
      expect(await r.sync.status.first, isA<Online>());
    });

    test('server unreachable: nothing resolved, lastSyncAt unchanged, status '
        'Offline — even with an empty ledger (QA-025)', () async {
      final before = r.sync.lastSyncAt; // From the start-up pass.
      r.clock.advance(const Duration(minutes: 5));
      r.backend.reachable = false;
      await r.sync.syncNow();
      expect(r.sync.lastSyncAt, before);
      expect(await r.sync.status.first, isA<Offline>());

      await r.add(b1);
      await r.sync.syncNow();
      expect(r.ledger.entries, hasLength(1));
      expect(r.sync.lastSyncAt, before);

      r.backend
        ..reachable = true
        ..server.add(b1);
      await r.sync.syncNow();
      expect(r.sync.lastSyncAt, r.clock.now);
      expect(await r.sync.status.first, isA<Online>());
    });

    test('ack entries: resolved by the batch\'s own outcome, or taken as '
        'landed when it is unknown (after a restart)', () async {
      const ovr1 = 'auditLog/PTB-D01-OVR-1';
      const ovr2 = 'auditLog/PTB-D01-OVR-2';
      const ovr3 = 'auditLog/PTB-D01-OVR-3';
      for (final p in [ovr1, ovr2, ovr3]) {
        await r.add(p, check: LedgerCheck.ack);
      }
      r.sync
        ..observeAck([ovr1], Future.value())
        ..observeAck([
          ovr2,
        ], Future.error(const DataFailure(FailureReason.notPermitted)));
      await r.sync.syncNow();
      expect(r.backend.checked, isEmpty, reason: 'no audit reads');
      expect((await r.sync.errors.first).map((e) => e.path), [ovr2]);
      expect(r.ledger.entries, isEmpty);
    });

    test('lastSeenAt at most every 5 minutes', () async {
      for (var i = 0; i < 4; i++) {
        await r.sync.syncNow();
        r.clock.advance(const Duration(minutes: 2));
      }
      // Passes at 0, 2, 4, 6 min (and the start-up one at 0).
      expect(r.backend.touches, hasLength(2));
      expect(r.state.lastSeenWrittenAt, t0.add(const Duration(minutes: 6)));
    });

    test('no pass while signed out', () async {
      final before = r.sync.lastSyncAt;
      r.clock.advance(const Duration(minutes: 5));
      r.uid = null;
      await r.sync.syncNow();
      expect(r.sync.lastSyncAt, before);
    });
  });

  test('waitForPendingWrites timing out after 30 s leaves everything '
      'pending and lastSyncAt alone', () {
    fakeAsync((fa) {
      final r = Rig();
      r.backend.wait = never;
      unawaited(r.start());
      fa.flushMicrotasks();
      unawaited(r.add(b1));
      var done = false;
      // The start-up pass is stuck too; syncNow waits for it (30 s), then
      // its own pass times out after another 30 s.
      unawaited(r.sync.syncNow().then((_) => done = true));
      fa.elapse(const Duration(seconds: 59));
      expect(done, isFalse);
      fa.elapse(const Duration(seconds: 2));
      fa.flushMicrotasks();
      expect(done, isTrue);
      expect(r.sync.lastSyncAt, isNull);
      expect(r.ledger.entries, hasLength(1));
      expect(r.backend.pings, 0);
      unawaited(r.close());
    });
  });

  group('lastSyncAt (03-SYNC §6.4, QA-025)', () {
    test('an interactive sign-in sets it; restoring a session and starting '
        'the app don\'t', () async {
      final r = Rig(online: false);
      await r.start();
      await settle();
      expect(r.sync.lastSyncAt, isNull, reason: 'app start, restored session');
      r.clock.advance(const Duration(minutes: 7));
      r.signIns.add(null);
      await settle();
      expect(r.sync.lastSyncAt, r.clock.now);
      await r.close();
    });

    test('registration (markSynced) sets it', () async {
      final r = Rig(online: false);
      await r.sync.markSynced();
      expect(r.sync.lastSyncAt, t0);
    });

    test('persisted: a restarted service reads it back and doesn\'t move it '
        'while offline', () async {
      final disk = <String, Object>{};
      final first = Rig(disk: disk);
      await first.start();
      await first.sync.syncNow();
      final synced = first.sync.lastSyncAt;
      expect(synced, isNotNull);
      await first.close();

      final clock = FakeClock(t0.add(const Duration(hours: 3)));
      final restarted = Rig(disk: disk, online: false, clock: clock);
      restarted.backend.reachable = false;
      await restarted.start();
      await restarted.sync.syncNow();
      expect(restarted.sync.lastSyncAt, synced);
      final status = await restarted.sync.status.first;
      expect((status as Offline).since, synced);
      await restarted.close();
    });

    test('the ledger and sync errors survive a restart too', () async {
      final ledgerDisk = LedgerDisk();
      final first = Rig(ledgerDisk: ledgerDisk);
      await first.add(b1);
      await first.add(b2);
      first.backend.server.add(b1);
      first.backend.reachable = false;
      await first.sync.syncNow();

      final second = Rig(ledgerDisk: ledgerDisk);
      expect(second.ledger.entries.map((e) => e.path), [b1, b2]);
      second.backend.server.add(b1);
      await second.sync.syncNow();
      final third = Rig(ledgerDisk: ledgerDisk);
      expect(third.ledger.errors.single.path, b2);
    });
  });

  group('status and triggers', () {
    test('Offline(since) → network back → a pass runs by itself → Syncing(n) '
        'while entries are pending → Online', () async {
      final r = Rig(online: false);
      await r.start();
      final seen = <SyncStatus>[];
      final sub = r.sync.status.listen(seen.add);
      await settle();
      expect(seen.single, isA<Offline>());
      expect((seen.single as Offline).since, t0);

      await r.add(b1);
      await settle();
      expect(seen.last, isA<Offline>(), reason: 'still offline');

      r.backend.server.add(b1);
      r.network.online = true;
      await settle();
      expect(r.backend.waits, 1);
      expect(seen.whereType<Syncing>().single.pending, 1);
      expect(seen.last, isA<Online>());
      expect(r.ledger.entries, isEmpty);

      r.clock.advance(const Duration(minutes: 1));
      r.network.online = false;
      await settle();
      expect((seen.last as Offline).since, r.clock.now);
      await sub.cancel();
      await r.close();
    });

    test('every 2 minutes while online, not while offline; and on app '
        'resume', () {
      fakeAsync((fa) {
        final r = Rig();
        unawaited(r.start());
        fa.flushMicrotasks();
        expect(r.backend.waits, 1, reason: 'the start-up pass');
        fa.elapse(const Duration(minutes: 2));
        expect(r.backend.waits, 2);
        fa.elapse(const Duration(minutes: 4));
        expect(r.backend.waits, 4);
        r.network.online = false;
        fa.elapse(const Duration(minutes: 6));
        expect(r.backend.waits, 4);
        r.network.online = true; // Regained: one pass at once.
        fa.flushMicrotasks();
        expect(r.backend.waits, 5);
        r.sync.appResumed();
        fa.flushMicrotasks();
        expect(r.backend.waits, 6);
        unawaited(r.close());
      });
    });

    test('syncNow during a pass waits for it, then runs another', () async {
      final r = Rig();
      final gate = Completer<void>();
      r.backend.wait = () => gate.future;
      await r.start(); // Start-up pass, stuck in waitForPendingWrites.
      r.backend.wait = () async {};
      var done = false;
      final now = r.sync.syncNow().then((_) => done = true);
      await settle();
      expect(done, isFalse);
      gate.complete();
      await now;
      expect(r.backend.waits, 2);
      await r.close();
    });
  });
}
