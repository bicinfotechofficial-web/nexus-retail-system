import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';

import '../write/support.dart';
import 'docs.dart';

final DateTime _at = DateTime.utc(2026, 9, 26, 4, 30);

void main() {
  late FakeFirebaseFirestore db;

  setUp(() => db = FakeFirebaseFirestore());

  group('FirestoreStaffRepository', () {
    late FirestoreStaffRepository repo;
    setUp(() => repo = FirestoreStaffRepository(db, clock: () => _at));

    Future<void> member(
      String loc,
      String id,
      String name, {
      bool active = true,
    }) => put(
      db,
      FirestorePaths.staffMember(loc, id),
      {'name': name, 'role': 'Baker', 'active': active, 'createdBy': 'admin'},
      serverTimes: {'createdAt': _at},
    );

    test('lists a store by name with its locationId from the path', () async {
      await member('PTB', 'b', 'Bina');
      await member('PTB', 'a', 'asha');
      await member('PTB', 'c', 'Chitra', active: false);
      await member('MNJ', 'z', 'Zed');
      final all = await repo.watchAll('PTB').first;
      expect(all.map((m) => m.name), ['asha', 'Bina', 'Chitra']);
      expect(all.map((m) => m.locationId), everyElement('PTB'));
      expect(all.first.createdAt!.toUtc(), _at);
      final active = await repo.watchActive('PTB').first;
      expect(active.map((m) => m.id), ['a', 'b']);
      expect((await repo.watchActive('MNJ').first).single.locationId, 'MNJ');
    });
  });

  group('FirestoreAttendanceRepository', () {
    late FirestoreAttendanceRepository repo;
    setUp(() => repo = FirestoreAttendanceRepository(db, clock: () => _at));

    Future<void> mark(
      String loc,
      String date,
      String staff,
      AttendanceStatus status, {
      String? note,
    }) {
      final r = AttendanceRecord(
        staffId: staff,
        staffName: 'Name $staff',
        businessDate: date,
        status: status,
        note: note,
        markedBy: const ServedBy(uid: 'sm-ptb', name: 'Store Manager PTB'),
        deviceId: 'D01',
      );
      return put(
        db,
        FirestorePaths.attendanceDoc(loc, r.id),
        r.toMap(),
        serverTimes: {'editedAt': _at},
      );
    }

    test('watchDay reads one day of one store, with its location', () async {
      await mark('PTB', '2026-09-26', 's1', AttendanceStatus.present);
      await mark(
        'PTB',
        '2026-09-26',
        's2',
        AttendanceStatus.halfDay,
        note: 'Noon',
      );
      await mark('PTB', '2026-09-25', 's1', AttendanceStatus.absent);
      await mark('MNJ', '2026-09-26', 's9', AttendanceStatus.present);
      final day = await repo.watchDay('PTB', '2026-09-26').first;
      expect(day.map((r) => r.staffId).toSet(), {'s1', 's2'});
      expect(day.map((r) => r.locationId), everyElement('PTB'));
      expect(day.firstWhere((r) => r.staffId == 's2').note, 'Noon');
      expect(day.first.editedAt!.toUtc(), _at);
      expect(day.first.id, '2026-09-26_${day.first.staffId}');
    });

    test('watchMonth covers the whole month and nothing of the next', () async {
      await mark('PTB', '2026-09-01', 's1', AttendanceStatus.present);
      await mark('PTB', '2026-09-30', 's1', AttendanceStatus.present);
      await mark('PTB', '2026-10-01', 's1', AttendanceStatus.present);
      await mark('PTB', '2026-08-31', 's1', AttendanceStatus.present);
      final month = await repo.watchMonth('PTB', '2026-09').first;
      expect(month.map((r) => r.businessDate).toSet(), {
        '2026-09-01',
        '2026-09-30',
      });
    });

    test(
      'watchDayAllLocations reads the collection group, each with its store',
      () async {
        await mark('PTB', '2026-09-26', 's1', AttendanceStatus.present);
        await mark('MNJ', '2026-09-26', 's9', AttendanceStatus.absent);
        await mark('MNJ', '2026-09-25', 's9', AttendanceStatus.absent);
        final day = await repo.watchDayAllLocations('2026-09-26').first;
        expect(
          {for (final r in day) r.staffId: r.locationId},
          {'s1': 'PTB', 's9': 'MNJ'},
        );
      },
    );
  });

  group('FirestoreOrderRepository', () {
    late FirestoreOrderRepository repo;
    setUp(() => repo = FirestoreOrderRepository(db, clock: () => _at));

    Future<PreOrder> order(
      String loc,
      int seq,
      String due, {
      OrderStatus status = OrderStatus.open,
      DateTime? created,
    }) async {
      final base = OrderPlans.create(
        ctx: PlanContext(
          uid: 'sm-ptb',
          locationId: loc,
          deviceId: 'D01',
          now: created ?? _at,
        ),
        seq: seq,
        input: NewOrder(
          customer: testCustomer,
          dueDate: due,
          description: 'Cake $seq',
          price: const Money(100000),
          advance: Money.zero,
        ),
        servedByName: 'Store Manager PTB',
      ).value;
      await put(
        db,
        FirestorePaths.order(loc, base.id),
        {...base.toMap(), 'status': status.wire},
        serverTimes: {'serverCreatedAt': _at},
      );
      return base;
    }

    test(
      'watchOpen lists open orders, soonest due first, with the location',
      () async {
        await order('PTB', 1, '2026-10-02');
        await order('PTB', 2, '2026-09-28');
        await order('PTB', 3, '2026-09-27', status: OrderStatus.delivered);
        await order('MNJ', 4, '2026-09-29');
        final open = await repo.watchOpen('PTB').first;
        expect(open.map((o) => o.id), ['D01-O000002', 'D01-O000001']);
        expect(open.map((o) => o.locationId), everyElement('PTB'));
      },
    );

    test(
      'watchClosed lists delivered and cancelled, newest first, to the limit',
      () async {
        await order(
          'PTB',
          1,
          '2026-09-28',
          status: OrderStatus.delivered,
          created: _at,
        );
        await order(
          'PTB',
          2,
          '2026-09-28',
          status: OrderStatus.cancelled,
          created: _at.add(const Duration(hours: 1)),
        );
        await order('PTB', 3, '2026-09-28');
        final closed = await repo.watchClosed('PTB').first;
        expect(closed.map((o) => o.id), ['D01-O000002', 'D01-O000001']);
        expect((await repo.watchClosed('PTB', limit: 1).first), hasLength(1));
      },
    );

    test('getOrder returns one order with its location, or null', () async {
      await order('PTB', 1, '2026-09-28');
      final o = await repo.getOrder('PTB', 'D01-O000001');
      expect(o!.locationId, 'PTB');
      expect(o.description, 'Cake 1');
      expect(await repo.getOrder('PTB', 'D01-O000099'), isNull);
      expect(await repo.getOrder('MNJ', 'D01-O000001'), isNull);
    });

    test(
      'watchAllLocations spans stores and filters by status and due date',
      () async {
        await order('PTB', 1, '2026-09-28');
        await order('MNJ', 2, '2026-09-27');
        await order('MNJ', 3, '2026-10-30');
        await order('PTB', 4, '2026-09-26', status: OrderStatus.cancelled);
        final all = await repo.watchAllLocations().first;
        expect(all.map((o) => o.id), [
          'D01-O000004',
          'D01-O000002',
          'D01-O000001',
          'D01-O000003',
        ]);
        expect({for (final o in all) o.id: o.locationId}['D01-O000002'], 'MNJ');
        final open = await repo
            .watchAllLocations(
              status: OrderStatus.open,
              dueFrom: '2026-09-27',
              dueTo: '2026-09-30',
            )
            .first;
        expect(open.map((o) => o.id), ['D01-O000002', 'D01-O000001']);
        expect(await repo.watchAllLocations(limit: 2).first, hasLength(2));
      },
    );
  });

  group('FirestoreStaffService', () {
    late Harness h;
    late ManualNetworkMonitor network;
    late FirestoreStaffService service;

    setUp(() {
      h = Harness(session: adminSession, deviceId: null);
      network = ManualNetworkMonitor();
      service = FirestoreStaffService(
        env: h.env,
        firestore: db,
        committer: h.committer,
        network: network,
      );
    });

    test(
      'create uses a Firestore auto ID and writes the five keys once',
      () async {
        final m = await service.create(
          locationId: 'PTB',
          name: ' Asha  K ',
          role: 'Baker',
        );
        expect(m.id, hasLength(20));
        expect(m.name, 'Asha K');
        final plan = h.committer.plans.single;
        expect(plan.paths, ['locations/PTB/staff/${m.id}']);
        expect(plan.ops.single.kind, WriteKind.create);
        expect(plan.ops.single.data.keys.toSet(), {
          'name',
          'role',
          'active',
          'createdBy',
          'createdAt',
        });
        // Online writes keep out of the offline sync ledger and device counters.
        expect(h.ledger.entries, isEmpty);
      },
    );

    test('update changes only the named fields', () async {
      await service.update(locationId: 'PTB', staffId: 'abc', active: false);
      final data = h.committer.plans.single.ops.single.data;
      expect(data['active'], false);
      expect(data.keys.toSet(), {'active', 'updatedBy', 'updatedAt'});
    });

    test(
      'offline: refused with DataFailure(offline), nothing written, no ID used',
      () async {
        network.online = false;
        await expectLater(
          service.create(locationId: 'PTB', name: 'Asha'),
          failsWith(FailureReason.offline),
        );
        await expectLater(
          service.update(locationId: 'PTB', staffId: 'abc', active: false),
          failsWith(FailureReason.offline),
        );
        expect(h.committer.plans, isEmpty);
      },
    );

    test(
      'needs staff.manage: a Store Manager is refused, even at their own store',
      () async {
        final sm = Harness();
        final s = FirestoreStaffService(
          env: sm.env,
          firestore: db,
          committer: sm.committer,
          network: network,
        );
        await expectLater(
          s.create(locationId: 'PTB', name: 'Asha'),
          failsWith(FailureReason.notPermitted),
        );
        expect(sm.committer.plans, isEmpty);
      },
    );

    test('a bad name is refused before the network is asked', () async {
      network.online = false;
      await expectLater(
        service.create(locationId: 'PTB', name: '  '),
        failsWith(FailureReason.ruleViolation),
      );
    });

    test('a rules rejection surfaces as the committer reported it', () async {
      h.committer.failWith = const DataFailure(FailureReason.notPermitted);
      await expectLater(
        service.update(locationId: 'PTB', staffId: 'abc', name: 'New'),
        failsWith(FailureReason.notPermitted),
      );
    });
  });
}
