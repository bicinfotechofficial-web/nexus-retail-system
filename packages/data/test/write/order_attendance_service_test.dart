import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';

import 'support.dart';

NewOrder _newOrder({Money advance = const Money(50000)}) => NewOrder(
  customer: testCustomer,
  dueDate: '2026-09-28',
  dueTime: '16:30',
  description: 'Two layer truffle',
  price: const Money(150000),
  advance: advance,
  advanceMode: advance.isZero ? null : PaymentMode.upi,
);

const String _order1 = 'locations/PTB/orders/D01-O000001';

/// The order as the server will hold it, so deliver and cancel can read it.
void _serverHolds(Harness h, PreOrder o) {
  h.reads.orders[FirestorePaths.order('PTB', o.id)] = o;
}

void main() {
  group('OrderService.create', () {
    test(
      'numbers D01-O000001 from its own counter, ledgers the order',
      () async {
        final h = Harness();
        final o = await h.orders.create(_newOrder());
        expect(o.id, 'D01-O000001');
        expect(h.counters.current('D01', SeqKind.order), 1);
        expect(h.counters.current('D01', SeqKind.bill), 0);
        final plan = h.committer.plans.single;
        expect(plan.opAt(_order1)!.kind, WriteKind.create);
        expect(plan.opAt('locations/PTB/devices/D01')!.data, {
          'lastOrderSeq': 1,
        });
        expect(h.ledgerPaths, [_order1]);
        expect(h.ledger.entries.single.label, contains('PTB-D01-O000001'));
        expect((await h.orders.create(_newOrder())).id, 'D01-O000002');
      },
    );

    test(
      'needs order.manage, a device and a valid order: no number taken',
      () async {
        final h = Harness(session: smSession(except: [Permission.orderManage]));
        await expectLater(
          h.orders.create(_newOrder()),
          failsWith(FailureReason.notPermitted),
        );
        final noDevice = Harness(deviceId: null);
        await expectLater(
          noDevice.orders.create(_newOrder()),
          failsWith(FailureReason.deviceNotRegistered),
        );
        final bad = Harness();
        await expectLater(
          bad.orders.create(_newOrder(advance: const Money(160000))),
          failsWith(FailureReason.ruleViolation),
        );
        for (final x in [h, noDevice, bad]) {
          expect(x.committer.plans, isEmpty);
          expect(x.ledger.entries, isEmpty);
        }
      },
    );

    test(
      'works offline: the order counter is durable across a restart',
      () async {
        final disk = <String, Object>{};
        final h = Harness(disk: disk);
        await h.orders.create(_newOrder());
        final again = Harness(disk: disk);
        expect((await again.orders.create(_newOrder())).id, 'D01-O000002');
      },
    );
  });

  group('OrderService.deliver', () {
    test(
      'writes one bill from the bill counter plus the order update',
      () async {
        final h = Harness();
        final o = await h.orders.create(_newOrder());
        _serverHolds(h, o);
        final bill = await h.orders.deliver(
          orderId: o.id,
          payments: const [
            Payment(mode: PaymentMode.cash, amount: Money(100000)),
          ],
        );
        expect(bill.id, 'D01-000001');
        expect(bill.orderId, o.id);
        expect(h.counters.current('D01', SeqKind.bill), 1);
        expect(h.counters.current('D01', SeqKind.order), 1);
        final plan = h.committer.plans.last;
        expect(
          plan.opAt('locations/PTB/bills/D01-000001')!.kind,
          WriteKind.create,
        );
        expect(plan.opAt(_order1)!.data['status'], 'DELIVERED');
        expect(plan.opAt('locations/PTB/devices/D01')!.data, {
          'lastBillSeq': 1,
        });
        expect(bill.payments.first.mode, PaymentMode.advance);
        expect(h.ledgerPaths, contains('locations/PTB/bills/D01-000001'));
      },
    );

    test(
      'an unknown order, a missing permission and blocked billing are refused',
      () async {
        final h = Harness();
        await expectLater(
          h.orders.deliver(orderId: 'D01-O000009', payments: const []),
          failsWith(FailureReason.notFound),
        );
        final o = await h.orders.create(_newOrder());
        _serverHolds(h, o);
        h.offline = const BillingBlocked();
        await expectLater(
          h.orders.deliver(
            orderId: o.id,
            payments: const [
              Payment(mode: PaymentMode.cash, amount: Money(100000)),
            ],
          ),
          failsWith(FailureReason.billingBlocked),
        );
        final noBill = Harness(
          session: smSession(except: [Permission.billCreate]),
        );
        _serverHolds(noBill, o);
        await expectLater(
          noBill.orders.deliver(orderId: o.id, payments: const []),
          failsWith(FailureReason.notPermitted),
        );
        expect(h.counters.current('D01', SeqKind.bill), 0);
      },
    );

    test(
      'payments that miss the balance, or name ADVANCE, are refused',
      () async {
        final h = Harness();
        final o = await h.orders.create(_newOrder());
        _serverHolds(h, o);
        for (final bad in [
          const [Payment(mode: PaymentMode.cash, amount: Money(90000))],
          const [Payment(mode: PaymentMode.advance, amount: Money(100000))],
        ]) {
          await expectLater(
            h.orders.deliver(orderId: o.id, payments: bad),
            failsWith(FailureReason.ruleViolation),
          );
        }
        expect(h.counters.current('D01', SeqKind.bill), 0);
      },
    );
  });

  group('OrderService.cancel', () {
    test(
      'writes the update and the ORDER_CANCEL audit, ledgering the audit',
      () async {
        final h = Harness();
        final o = await h.orders.create(_newOrder());
        _serverHolds(h, o);
        final c = await h.orders.cancel(
          orderId: o.id,
          reason: 'Changed plans',
          refund: const Money(30000),
        );
        expect(c.status, OrderStatus.cancelled);
        final plan = h.committer.plans.last;
        expect(plan.paths, contains('auditLog/PTB-D01-O000001-X'));
        expect(h.ledgerPaths.last, 'auditLog/PTB-D01-O000001-X');
        expect(h.counters.current('D01', SeqKind.order), 1);
      },
    );

    test(
      'an unknown order, no permission and a refund above the advance fail',
      () async {
        final h = Harness();
        await expectLater(
          h.orders.cancel(
            orderId: 'D01-O000009',
            reason: 'x',
            refund: Money.zero,
          ),
          failsWith(FailureReason.notFound),
        );
        final o = await h.orders.create(_newOrder());
        _serverHolds(h, o);
        await expectLater(
          h.orders.cancel(
            orderId: o.id,
            reason: 'x',
            refund: const Money(60000),
          ),
          failsWith(FailureReason.ruleViolation),
        );
        final no = Harness(
          session: smSession(except: [Permission.orderManage]),
        );
        await expectLater(
          no.orders.cancel(orderId: o.id, reason: 'x', refund: Money.zero),
          failsWith(FailureReason.notPermitted),
        );
      },
    );
  });

  group('AttendanceService.mark', () {
    List<AttendanceMark> marks(int n) => [
      for (var i = 1; i <= n; i++)
        AttendanceMark(
          staffId: 's$i',
          staffName: 'Staff $i',
          status: AttendanceStatus.present,
        ),
    ];

    test(
      'chunks at Limits.maxAttendanceBatch, one plan each, nothing read',
      () async {
        final h = Harness();
        await h.attendance.mark(
          '2026-09-26',
          marks(Limits.maxAttendanceBatch + 1),
        );
        expect(h.committer.plans.map((p) => p.ops.length), [
          Limits.maxAttendanceBatch,
          1,
        ]);
        expect(h.reads.deviceReads, 0);
        expect(h.ledgerPaths.length, Limits.maxAttendanceBatch + 1);
        expect(h.ledgerPaths.first, 'locations/PTB/attendance/2026-09-26_s1');
      },
    );

    test(
      'an empty list writes nothing; a mark again just overwrites',
      () async {
        final h = Harness();
        await h.attendance.mark('2026-09-26', const []);
        expect(h.committer.plans, isEmpty);
        await h.attendance.mark('2026-09-26', marks(1));
        await h.attendance.mark('2026-09-26', marks(1));
        expect(h.committer.plans.length, 2);
      },
    );

    test(
      'the 7-day window, the future and duplicate staff are refused before any write',
      () async {
        final h = Harness();
        await h.attendance.mark('2026-09-19', marks(1)); // exactly 7 days back
        await expectLater(
          h.attendance.mark('2026-09-18', marks(1)),
          failsWith(FailureReason.ruleViolation),
        );
        await expectLater(
          h.attendance.mark('2026-09-27', marks(1)),
          failsWith(FailureReason.ruleViolation),
        );
        await expectLater(
          h.attendance.mark('2026-09-26', [...marks(2), ...marks(1)]),
          failsWith(FailureReason.ruleViolation),
        );
        expect(h.committer.plans.length, 1);
      },
    );

    test(
      'a bad mark in a later chunk stops everything: no half-marked day',
      () async {
        final h = Harness();
        final many = [
          ...marks(Limits.maxAttendanceBatch),
          AttendanceMark(
            staffId: 'late',
            staffName: 'Late',
            status: AttendanceStatus.absent,
            note: 'x' * 101,
          ),
        ];
        await expectLater(
          h.attendance.mark('2026-09-26', many),
          failsWith(FailureReason.ruleViolation),
        );
        expect(h.committer.plans, isEmpty);
      },
    );

    test('needs attendance.mark and a device', () async {
      final h = Harness(
        session: smSession(except: [Permission.attendanceMark]),
      );
      await expectLater(
        h.attendance.mark('2026-09-26', marks(1)),
        failsWith(FailureReason.notPermitted),
      );
      final nd = Harness(deviceId: null);
      await expectLater(
        nd.attendance.mark('2026-09-26', marks(1)),
        failsWith(FailureReason.deviceNotRegistered),
      );
    });
  });
}
