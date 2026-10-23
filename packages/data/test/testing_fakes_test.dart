// The in-memory fakes of the staff, attendance and order interfaces
// (lib/testing.dart), which the apps' tests build on. They run the real plan
// builders, so what they accept and refuse matches the real services.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';
import 'package:nexus_data/testing.dart';

import 'write/support.dart';

NewOrder _order({Money advance = const Money(50000)}) => NewOrder(
  customer: testCustomer,
  dueDate: '2026-09-28',
  description: 'Truffle',
  price: const Money(150000),
  advance: advance,
  advanceMode: advance.isZero ? null : PaymentMode.cash,
);

void main() {
  final now = DateTime.utc(2026, 9, 26, 4, 30);
  SessionContext? session = smSession();

  setUp(() => session = smSession());

  group('FakeStaffRepository and FakeStaffService', () {
    test('the Admin creates, edits and deactivates; watchers follow', () async {
      session = adminSession;
      final repo = FakeStaffRepository();
      final svc = FakeStaffService(
        repo,
        session: () => session,
        now: () => now,
      );
      final seen = <int>[];
      final sub = repo.watchActive('PTB').listen((l) => seen.add(l.length));
      final m = await svc.create(
        locationId: 'PTB',
        name: 'Asha',
        role: 'Baker',
      );
      await svc.update(locationId: 'PTB', staffId: m.id, name: 'Asha K');
      expect((await repo.watchAll('PTB').first).single.name, 'Asha K');
      await svc.update(locationId: 'PTB', staffId: m.id, active: false);
      await pumpEventQueue();
      expect(await repo.watchActive('PTB').first, isEmpty);
      expect(seen.last, 0);
      expect(seen, contains(1));
      expect((await repo.watchAll('PTB').first).single.locationId, 'PTB');
      expect(svc.createCalls, [('PTB', 'Asha', 'Baker')]);
      await sub.cancel();
    });

    test('a Store Manager is refused, and failNext is thrown once', () async {
      final repo = FakeStaffRepository();
      final svc = FakeStaffService(
        repo,
        session: () => session,
        now: () => now,
      );
      await expectLater(
        svc.create(locationId: 'PTB', name: 'Asha'),
        failsWith(FailureReason.notPermitted),
      );
      session = adminSession;
      svc.failNext = const DataFailure(FailureReason.offline);
      await expectLater(
        svc.create(locationId: 'PTB', name: 'Asha'),
        failsWith(FailureReason.offline),
      );
      await svc.create(locationId: 'PTB', name: 'Asha');
      await expectLater(
        svc.create(locationId: 'PTB', name: ' '),
        failsWith(FailureReason.ruleViolation),
      );
    });
  });

  group('FakeAttendanceRepository and FakeAttendanceService', () {
    test(
      'marks, overwrites and reads by day, month and across stores',
      () async {
        final repo = FakeAttendanceRepository();
        final svc = FakeAttendanceService(
          repo,
          session: () => session,
          now: () => now,
        );
        const asha = AttendanceMark(
          staffId: 's1',
          staffName: 'Asha',
          status: AttendanceStatus.present,
        );
        await svc.mark('2026-09-26', [asha]);
        await svc.mark('2026-09-26', [
          const AttendanceMark(
            staffId: 's1',
            staffName: 'Asha',
            status: AttendanceStatus.absent,
            note: 'Sick',
          ),
        ]);
        await svc.mark('2026-09-25', [asha]);
        final day = await repo.watchDay('PTB', '2026-09-26').first;
        expect(day.single.status, AttendanceStatus.absent);
        expect(day.single.note, 'Sick');
        expect(day.single.locationId, 'PTB');
        expect(await repo.watchMonth('PTB', '2026-09').first, hasLength(2));
        expect(
          await repo.watchDayAllLocations('2026-09-26').first,
          hasLength(1),
        );
        expect(svc.markCalls, hasLength(3));
      },
    );

    test(
      'refuses the window, duplicates, long notes and missing permission',
      () async {
        final repo = FakeAttendanceRepository();
        final svc = FakeAttendanceService(
          repo,
          session: () => session,
          now: () => now,
        );
        const m = AttendanceMark(
          staffId: 's1',
          staffName: 'Asha',
          status: AttendanceStatus.present,
        );
        await expectLater(
          svc.mark('2026-09-10', [m]),
          failsWith(FailureReason.ruleViolation),
        );
        await expectLater(
          svc.mark('2026-09-26', [m, m]),
          failsWith(FailureReason.ruleViolation),
        );
        session = smSession(except: [Permission.attendanceMark]);
        await expectLater(
          svc.mark('2026-09-26', [m]),
          failsWith(FailureReason.notPermitted),
        );
        expect(await repo.watchDay('PTB', '2026-09-26').first, isEmpty);
      },
    );
  });

  group('FakeOrderRepository and FakeOrderService', () {
    test(
      'create, deliver and cancel move an order through its states',
      () async {
        final repo = FakeOrderRepository();
        final bills = <Bill>[];
        final svc = FakeOrderService(
          repo,
          session: () => session,
          now: () => now,
          onBill: (_, b) => bills.add(b),
        );
        final a = await svc.create(_order());
        final b = await svc.create(_order(advance: Money.zero));
        expect([a.id, b.id], ['D01-O000001', 'D01-O000002']);
        expect(await repo.watchOpen('PTB').first, hasLength(2));

        final bill = await svc.deliver(
          orderId: a.id,
          payments: const [
            Payment(mode: PaymentMode.cash, amount: Money(100000)),
          ],
        );
        expect(bill.orderId, a.id);
        expect(bills.single.id, bill.id);
        expect(bill.payments.first.mode, PaymentMode.advance);
        expect(
          (await repo.getOrder('PTB', a.id))!.status,
          OrderStatus.delivered,
        );

        final c = await svc.cancel(
          orderId: b.id,
          reason: 'No show',
          refund: Money.zero,
        );
        expect(c.status, OrderStatus.cancelled);
        expect(await repo.watchOpen('PTB').first, isEmpty);
        expect(await repo.watchClosed('PTB').first, hasLength(2));
        expect(await repo.watchAllLocations().first, hasLength(2));
        expect(svc.deliverCalls.single.$1, a.id);
        expect(svc.cancelCalls.single.$2, 'No show');
      },
    );

    test('refuses what the real service refuses', () async {
      final repo = FakeOrderRepository();
      final svc = FakeOrderService(
        repo,
        session: () => session,
        now: () => now,
      );
      await expectLater(
        svc.deliver(orderId: 'D01-O000009', payments: const []),
        failsWith(FailureReason.notFound),
      );
      final o = await svc.create(_order());
      await expectLater(
        svc.deliver(
          orderId: o.id,
          payments: const [Payment(mode: PaymentMode.cash, amount: Money(1))],
        ),
        failsWith(FailureReason.ruleViolation),
      );
      await expectLater(
        svc.cancel(orderId: o.id, reason: 'x', refund: const Money(99900)),
        failsWith(FailureReason.ruleViolation),
      );
      svc.failNext = const DataFailure(FailureReason.offline);
      await expectLater(svc.create(_order()), failsWith(FailureReason.offline));
      session = smSession(except: [Permission.orderManage]);
      await expectLater(
        svc.create(_order()),
        failsWith(FailureReason.notPermitted),
      );
      session = smSession(except: [Permission.billCreate]);
      await expectLater(
        svc.deliver(orderId: o.id, payments: const []),
        failsWith(FailureReason.notPermitted),
      );
    });
  });
}
