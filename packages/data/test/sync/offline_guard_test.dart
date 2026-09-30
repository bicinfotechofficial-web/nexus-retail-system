import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';

import '../write/support.dart';

const String pin = '24681357';

void main() {
  late String pinHash;

  setUpAll(() async {
    pinHash = await PinHasher().hash(pin, salt: List.filled(16, 7));
  });

  /// A guard on [h]'s store and write pipeline, with the location's PIN.
  LocalOfflineGuard guardFor(
    Harness h, {
    int limitHours = 5,
    LocalSyncState? state,
  }) {
    h.session = smSession(
      location: ptb(pinHash: pinHash, limitHours: limitHours),
    );
    return LocalOfflineGuard(
      syncState: state ?? LocalSyncState(h.store),
      session: () => h.session,
      env: h.env,
      clock: h.clock.call,
    );
  }

  Future<void> syncedAt(Harness h, DateTime at) =>
      LocalSyncState(h.store).setLastSyncAt(at);

  group('limits (D-016)', () {
    test('no lastSyncAt yet: within the limit', () {
      expect(guardFor(Harness()).evaluate(), isA<WithinLimit>());
    });

    test('NearLimit from 80%, counting down; BillingBlocked at 100%', () async {
      final h = Harness();
      final g = guardFor(h);
      await syncedAt(h, t0);
      h.clock.advance(const Duration(hours: 3, minutes: 59));
      expect(g.evaluate(), isA<WithinLimit>());
      h.clock.advance(const Duration(minutes: 1)); // 4 h = 80% of 5 h
      expect(
        (g.evaluate() as NearLimit).billingStopsIn,
        const Duration(hours: 1),
      );
      h.clock.advance(const Duration(minutes: 45));
      expect(
        (g.evaluate() as NearLimit).billingStopsIn,
        const Duration(minutes: 15),
      );
      h.clock.advance(const Duration(minutes: 15));
      expect(g.evaluate(), isA<BillingBlocked>());
      h.clock.advance(const Duration(days: 2));
      expect(g.evaluate(), isA<BillingBlocked>());
    });

    test('the location\'s own offlineLimitHours applies', () async {
      final h = Harness();
      final g = guardFor(h, limitHours: 10);
      await syncedAt(h, t0);
      h.clock.advance(const Duration(hours: 7));
      expect(g.evaluate(), isA<WithinLimit>());
      h.clock.advance(const Duration(hours: 1));
      expect(g.evaluate(), isA<NearLimit>());
      h.clock.advance(const Duration(hours: 2));
      expect(g.evaluate(), isA<BillingBlocked>());
    });

    test('a sync resets it', () async {
      final h = Harness();
      final g = guardFor(h);
      await syncedAt(h, t0);
      h.clock.advance(const Duration(hours: 6));
      expect(g.evaluate(), isA<BillingBlocked>());
      await syncedAt(h, h.clock.now);
      expect(g.evaluate(), isA<WithinLimit>());
    });

    test('blocks new bills through the sales service, not cancels', () async {
      final h = Harness();
      final g = guardFor(h);
      final sales = FirestoreSalesService(h.env, offline: g.evaluate);
      await syncedAt(h, t0);
      final bill = await sales.createBill(cashBill);
      h.reads.bills[FirestorePaths.bill('PTB', bill.id)] = bill;
      h.clock.advance(const Duration(hours: 5));
      await expectLater(
        sales.createBill(cashBill),
        failsWith(FailureReason.billingBlocked),
      );
      await sales.cancelBill(billId: bill.id, reason: 'Wrong cake');
    });
  });

  group('PIN override', () {
    late Harness h;
    late LocalOfflineGuard g;

    setUp(() async {
      h = Harness();
      g = guardFor(h);
      await syncedAt(h, t0);
      h.clock.advance(const Duration(hours: 6)); // Blocked for an hour.
    });

    test(
      'the right PIN allows billing until now + 2 h, counting down, and '
      'queues the OFFLINE_OVERRIDE audit through a plan and the ledger',
      () async {
        expect(await g.override(pin), isTrue);
        final at = h.clock.now;
        expect(
          (g.evaluate() as NearLimit).billingStopsIn,
          const Duration(hours: 2),
        );

        final op = h.committer.plans.single.ops.single;
        expect(op.path, 'auditLog/${Ids.overrideAuditId('PTB', 'D01', at)}');
        expect(op.kind, WriteKind.create);
        expect(op.data['action'], 'OFFLINE_OVERRIDE');
        expect(op.data['locationId'], 'PTB');
        expect(op.data['entityPath'], 'locations/PTB/devices/D01');
        expect(op.data['by'], 'sm-ptb');
        expect(op.data['deviceId'], 'D01');
        expect(op.data['clientAt'], at);
        expect(op.data['at'], serverTimestamp);
        expect(op.data['after'], {
          'billingAllowedUntil': at.add(const Duration(hours: 2)),
        });
        final entry = h.ledger.entries.single;
        expect(entry.path, op.path);
        expect(entry.check, LedgerCheck.ack);

        final sales = FirestoreSalesService(h.env, offline: g.evaluate);
        expect((await sales.createBill(cashBill)).seq, 1);

        h.clock.advance(const Duration(minutes: 90));
        expect(
          (g.evaluate() as NearLimit).billingStopsIn,
          const Duration(minutes: 30),
        );
        h.clock.advance(const Duration(minutes: 30));
        expect(g.evaluate(), isA<BillingBlocked>(), reason: 'override over');
        await expectLater(
          sales.createBill(cashBill),
          failsWith(FailureReason.billingBlocked),
        );
      },
    );

    test('survives a restart (QA-025)', () async {
      expect(await g.override(pin), isTrue);
      final restarted = LocalOfflineGuard(
        syncState: LocalSyncState(MemoryDurableStore(h.store.disk)),
        session: () => h.session,
        env: h.env,
        clock: h.clock.call,
      );
      expect(restarted.evaluate(), isA<NearLimit>());
    });

    test('can be repeated, each with its own audit', () async {
      expect(await g.override(pin), isTrue);
      h.clock.advance(const Duration(hours: 2));
      expect(g.evaluate(), isA<BillingBlocked>());
      expect(await g.override(pin), isTrue);
      expect(g.evaluate(), isA<NearLimit>());
      expect(h.committer.plans, hasLength(2));
      expect(
        h.committer.plans.map((p) => p.ops.single.path).toSet(),
        hasLength(2),
      );
    });

    test('a sync during the override ends it: the normal rule applies from '
        'the new lastSyncAt', () async {
      expect(await g.override(pin), isTrue);
      h.clock.advance(const Duration(minutes: 10));
      await syncedAt(h, h.clock.now);
      expect(g.evaluate(), isA<WithinLimit>());
      h.clock.advance(const Duration(hours: 5));
      expect(g.evaluate(), isA<BillingBlocked>());
    });

    test('a wrong PIN, or one that is not 8+ digits, returns false and '
        'changes nothing', () async {
      for (final wrong in ['13572468', '1234', '2468135x', '']) {
        expect(await g.override(wrong), isFalse, reason: wrong);
      }
      expect(g.evaluate(), isA<BillingBlocked>());
      expect(h.committer.plans, isEmpty);
      expect(h.ledger.entries, isEmpty);
      expect(LocalSyncState(h.store).overrideUntil, isNull);
    });

    test('a malformed stored hash never matches', () async {
      h.session = smSession(location: ptb(pinHash: 'not-a-hash'));
      expect(await g.override(pin), isFalse);
    });

    test('needs bill.create at the location and a registered device', () async {
      h.session = smSession(
        except: [Permission.billCreate],
        location: ptb(pinHash: pinHash),
      );
      await expectLater(g.override(pin), failsWith(FailureReason.notPermitted));
      h
        ..session = smSession(location: ptb(pinHash: pinHash))
        ..deviceId = null;
      await expectLater(
        g.override(pin),
        failsWith(FailureReason.deviceNotRegistered),
      );
      h.session = null;
      await expectLater(g.override(pin), failsWith(FailureReason.notPermitted));
      expect(h.committer.plans, isEmpty);
    });

    test('if the audit can\'t be committed, no override is granted', () async {
      h.committer.failWith = const DataFailure(FailureReason.unknown);
      await expectLater(g.override(pin), failsWith(FailureReason.unknown));
      expect(g.evaluate(), isA<BillingBlocked>());
    });
  });

  test('the state stream emits the current state, then changes: the '
      'countdown every minute, a sync, an override', () {
    fakeAsync((fa) {
      final h = Harness();
      final state = LocalSyncState(h.store);
      final g = guardFor(h, state: state);
      unawaited(state.setLastSyncAt(t0));
      fa.flushMicrotasks();
      final seen = <OfflineState>[];
      final sub = g.state.listen(seen.add);
      fa.flushMicrotasks();
      expect(seen.single, isA<WithinLimit>());

      h.clock.advance(const Duration(hours: 4, seconds: 10));
      fa.elapse(const Duration(seconds: 30));
      expect(
        (seen.last as NearLimit).billingStopsIn,
        const Duration(minutes: 59, seconds: 50),
      );
      h.clock.advance(const Duration(seconds: 20));
      fa.elapse(const Duration(seconds: 30));
      expect(seen, hasLength(2), reason: 'same minute: no new event');
      h.clock.advance(const Duration(minutes: 1));
      fa.elapse(const Duration(seconds: 30));
      expect(seen, hasLength(3));

      unawaited(state.setLastSyncAt(h.clock.now));
      fa.flushMicrotasks();
      expect(seen.last, isA<WithinLimit>());
      unawaited(sub.cancel());
    });
  });
}
