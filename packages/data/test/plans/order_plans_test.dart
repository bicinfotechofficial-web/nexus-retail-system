import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';

import 'plan_fixtures.dart';

const _orderPath = 'locations/PTB/orders/D01-O000004';
const _billPath = 'locations/PTB/bills/D01-000007';

TypeMatcher<DataFailure> _failure(FailureReason r) =>
    isA<DataFailure>().having((f) => f.reason, 'reason', r);

NewOrder _input({
  Money price = const Money(150000),
  Money advance = const Money(50000),
  PaymentMode? mode = PaymentMode.upi,
  String dueDate = '2026-09-28',
  String? dueTime = '16:30',
  String description = '  Two layer   truffle, 1.5 kg\n  "Happy Birthday Anu" ',
}) => NewOrder(
  customer: Fx.customer,
  dueDate: dueDate,
  dueTime: dueTime,
  description: description,
  price: price,
  advance: advance,
  advanceMode: advance.isZero ? null : mode,
);

PlannedWrite<PreOrder> _create([NewOrder? input, PlanContext? ctx]) =>
    OrderPlans.create(
      ctx: ctx ?? Fx.sm(),
      seq: 4,
      input: input ?? _input(),
      servedByName: 'Store Manager PTB',
    );

/// The order as the server holds it after [_create], for the later plans.
PreOrder _stored({NewOrder? input}) => PreOrder.fromMap('D01-O000004', {
  ..._create(input).value.toMap(),
  'serverCreatedAt': Fx.now,
});

void main() {
  group('OrderPlans.create', () {
    final planned = _create();
    final plan = planned.plan;
    final order = planned.value;

    test(
      'writes the order, lastOrderSeq and both advance summaries, in order',
      () {
        expect(plan.paths, [
          _orderPath,
          'locations/PTB/devices/D01',
          'locations/PTB/dailySummary/2026-09-26',
          'locations/PTB/monthlySummary/2026-09',
        ]);
        expect(plan.ops.map((o) => o.kind), [
          WriteKind.create,
          WriteKind.update,
          WriteKind.setMerge,
          WriteKind.setMerge,
        ]);
      },
    );

    test('the order carries the customer fields, an OPEN status and no '
        'delivery stamp', () {
      expect(order.id, 'D01-O000004');
      expect(order.orderNo, 'PTB-D01-O000004');
      expect(plan.opAt(_orderPath)!.data, {
        'orderNo': 'PTB-D01-O000004',
        'deviceId': 'D01',
        'seq': 4,
        'customerId': Fx.customer.id,
        'customerName': 'Test Customer',
        'customerPhone': '9876543210',
        'customerWhatsapp': '9876543210',
        'dueDate': '2026-09-28',
        'dueTime': '16:30',
        'description': 'Two layer truffle, 1.5 kg\n"Happy Birthday Anu"',
        'price': 150000,
        'advance': 50000,
        'advanceMode': 'UPI',
        'status': 'OPEN',
        'billId': null,
        'servedBy': {'uid': 'sm-ptb', 'name': 'Store Manager PTB'},
        'businessDate': '2026-09-26',
        'clientCreatedAt': Fx.now,
        'createdBy': 'sm-ptb',
        'serverCreatedAt': serverTimestamp,
      });
    });

    test(
      'lastOrderSeq is the order number, and the summaries name the order',
      () {
        expect(plan.opAt('locations/PTB/devices/D01')!.data, {
          'lastOrderSeq': 4,
        });
        for (final path in [
          'locations/PTB/dailySummary/2026-09-26',
          'locations/PTB/monthlySummary/2026-09',
        ]) {
          expect(plan.opAt(path)!.data, {
            'advanceReceived': const Increment(50000),
            'lastWriteRef': _orderPath,
          });
        }
      },
    );

    test('no advance: no summary write and no advance mode', () {
      final p = _create(_input(advance: Money.zero));
      expect(p.plan.paths, [_orderPath, 'locations/PTB/devices/D01']);
      expect(p.plan.opAt(_orderPath)!.data['advanceMode'], isNull);
      expect(p.value.advance, Money.zero);
    });

    test('an advance equal to the price, and no time, are fine', () {
      final p = _create(_input(advance: const Money(150000), dueTime: null));
      expect(p.plan.opAt(_orderPath)!.data['dueTime'], isNull);
      expect(p.value.balance, Money.zero);
    });

    test('never touches stock or the customer record', () {
      expect(
        plan.paths.where(
          (p) => p.contains('/stock/') || p.contains('/customers/'),
        ),
        isEmpty,
      );
    });

    test('the date is the business date in IST', () {
      final late = Fx.sm(at: DateTime.utc(2026, 9, 26, 23, 30));
      final p = _create(_input(dueDate: '2026-09-27'), late);
      expect(p.value.businessDate, '2026-09-27');
      expect(p.plan.paths, contains('locations/PTB/dailySummary/2026-09-27'));
    });

    test('refuses what the validator refuses, with its message', () {
      void refused(NewOrder o, String message) => expect(
        () => _create(o),
        throwsA(
          _failure(
            FailureReason.ruleViolation,
          ).having((f) => f.detail, 'detail', contains(message)),
        ),
      );
      refused(_input(description: '  '), 'Describe');
      refused(_input(description: 'd' * 501), 'At most 500');
      refused(_input(dueDate: '2026-09-25'), 'passed');
      refused(_input(dueDate: 'soon'), 'delivery date');
      refused(_input(dueTime: '4pm'), 'time');
      refused(_input(price: Money.zero, advance: Money.zero), 'price');
      refused(_input(price: const Money(150050)), 'whole rupees');
      refused(_input(advance: const Money(150100)), 'more than the price');
      refused(_input(advance: const Money(25050)), 'whole rupees');
      refused(
        NewOrder(
          customer: Fx.customer,
          dueDate: '2026-09-28',
          description: 'cake',
          price: const Money(100000),
          advance: const Money(10000),
        ),
        'how the advance was paid',
      );
      refused(_input(mode: PaymentMode.advance), 'how the advance was paid');
    });

    test(
      'a description of exactly 500 characters, and an order due today, pass',
      () {
        expect(
          _create(_input(description: 'd' * 500)).value.description,
          hasLength(500),
        );
        expect(_create(_input(dueDate: Fx.today)).value.dueDate, Fx.today);
      },
    );

    test('needs a location and a registered device', () {
      expect(
        () => _create(null, Fx.admin()),
        throwsA(_failure(FailureReason.notPermitted)),
      );
      expect(
        () => _create(
          null,
          PlanContext(uid: 'sm-ptb', locationId: 'PTB', now: Fx.now),
        ),
        throwsA(_failure(FailureReason.deviceNotRegistered)),
      );
    });
  });

  group('OrderPlans.deliver', () {
    final order = _stored();
    final later = Fx.sm(
      at: Fx.now.add(const Duration(days: 2)),
      deviceId: 'D02',
    );

    PlannedWrite<Bill> deliver({
      PreOrder? o,
      List<Payment>? payments,
      Money? cashTendered,
      PlanContext? ctx,
    }) => OrderPlans.deliver(
      ctx: ctx ?? later,
      seq: 7,
      order: o ?? order,
      payments:
          payments ??
          const [Payment(mode: PaymentMode.cash, amount: Money(100000))],
      cashTendered: cashTendered,
      servedByName: 'Store Manager PTB',
    );

    final planned = deliver();
    final bill = planned.value;
    const deliveryBillPath = 'locations/PTB/bills/D02-000007';
    const orderOnDelivery = 'locations/PTB/orders/D01-O000004';

    test(
      'is one bill from the same builder as createBill, plus the order update',
      () {
        expect(planned.plan.paths, [
          deliveryBillPath,
          'locations/PTB/stock/FG_CUSTOM-CAKE',
          'locations/PTB/movements/D02-000007',
          'locations/PTB/dailySummary/2026-09-28',
          'locations/PTB/monthlySummary/2026-09',
          'locations/PTB/customers/${Fx.customer.id}',
          'locations/PTB/devices/D02',
          orderOnDelivery,
        ]);
        // The same plan createBill makes for the same cart and payments, apart
        // from the order link.
        final ordinary = SalesPlans.createBill(
          ctx: later,
          seq: 7,
          servedByName: 'Store Manager PTB',
          input: NewBill(
            cart: [
              CartLine(
                productId: 'CUSTOM-CAKE',
                name: 'Custom cake',
                qty: 1,
                unitPrice: order.price,
              ),
            ],
            payments: const [
              Payment(mode: PaymentMode.advance, amount: Money(50000)),
              Payment(mode: PaymentMode.cash, amount: Money(100000)),
            ],
            customer: Fx.customer,
          ),
        );
        expect(planned.plan.paths.take(7), ordinary.plan.paths);
        for (var i = 0; i < 7; i++) {
          final a = Map<String, Object?>.of(planned.plan.ops[i].data);
          final b = Map<String, Object?>.of(ordinary.plan.ops[i].data)
            ..remove('orderId');
          a.remove('orderId');
          expect(a, b, reason: planned.plan.ops[i].path);
        }
      },
    );

    test('the bill sells CUSTOM-CAKE once at the order price, with the ADVANCE '
        'entry first and the order id', () {
      expect(bill.orderId, 'D01-O000004');
      expect(bill.lines.single.productId, 'CUSTOM-CAKE');
      expect(bill.lines.single.qty, 1);
      expect(bill.lines.single.unitPrice, const Money(150000));
      expect(bill.total, const Money(150000));
      expect(bill.customer!.id, Fx.customer.id);
      expect(bill.businessDate, '2026-09-28');
      final data = planned.plan.opAt(deliveryBillPath)!.data;
      expect(data['orderId'], 'D01-O000004');
      expect(data['payments'], [
        {'mode': 'ADVANCE', 'amount': 50000},
        {'mode': 'CASH', 'amount': 100000},
      ]);
      expect(data['soldQty'], {'CUSTOM-CAKE': 1});
      expect(data['customerId'], Fx.customer.id);
    });

    test('the order update changes only status, billId and deliveredAt', () {
      final op = planned.plan.opAt(orderOnDelivery)!;
      expect(op.kind, WriteKind.update);
      expect(op.data, {
        'status': 'DELIVERED',
        'billId': 'D02-000007',
        'deliveredAt': serverTimestamp,
      });
    });

    test('the sale is counted on the delivery day, with ADVANCE as its own '
        'byMode key', () {
      final daily = planned.plan.opAt('locations/PTB/dailySummary/2026-09-28')!;
      expect(daily.data, {
        'billCount': const Increment(1),
        'grossSales': const Increment(150000),
        'netSales': const Increment(150000),
        'byMode': {
          'ADVANCE': const Increment(50000),
          'CASH': const Increment(100000),
        },
        'byProduct': {
          'CUSTOM-CAKE': {
            'qty': const Increment(1),
            'amount': const Increment(150000),
          },
        },
        'lastWriteRef': deliveryBillPath,
      });
      // No advance counted again: that was done on the day it was taken.
      expect(daily.data.containsKey('advanceReceived'), isFalse);
    });

    test(
      'stock goes down by one CUSTOM-CAKE in the delivery SALE movement',
      () {
        final stock = planned.plan.opAt('locations/PTB/stock/FG_CUSTOM-CAKE')!;
        expect(stock.data['qty'], const Increment(-1));
        expect(stock.data['lastMovementId'], 'D02-000007');
        final mv = planned.plan.opAt('locations/PTB/movements/D02-000007')!;
        expect(mv.data['type'], 'SALE');
        expect(mv.data['refId'], 'D02-000007');
      },
    );

    test('the customer record is merged as for any bill', () {
      final c = planned.plan.opAt('locations/PTB/customers/${Fx.customer.id}')!;
      expect(c.kind, WriteKind.setMerge);
      expect(c.data['billCount'], const Increment(1));
      expect(c.data['totalSpend'], const Increment(150000));
      expect(c.data['lastWriteRef'], 'D02-000007');
    });

    test(
      'an order paid in full in advance delivers with one ADVANCE payment',
      () {
        final full = _stored(input: _input(advance: const Money(150000)));
        final p = deliver(o: full, payments: const []);
        expect(p.plan.opAt(deliveryBillPath)!.data['payments'], [
          {'mode': 'ADVANCE', 'amount': 150000},
        ]);
      },
    );

    test('an order with no advance has no ADVANCE entry', () {
      final none = _stored(input: _input(advance: Money.zero));
      final p = deliver(
        o: none,
        payments: const [
          Payment(mode: PaymentMode.cash, amount: Money(50000)),
          Payment(mode: PaymentMode.upi, amount: Money(100000)),
        ],
      );
      expect(
        (p.plan.opAt(deliveryBillPath)!.data['payments']! as List).length,
        2,
      );
    });

    test('cash tendered is checked against the cash part of the balance', () {
      expect(
        deliver(cashTendered: const Money(200000)).value.cashTendered,
        const Money(200000),
      );
      expect(
        () => deliver(cashTendered: const Money(90000)),
        throwsA(_failure(FailureReason.ruleViolation)),
      );
    });

    test('payments that miss the balance, or use ADVANCE, are refused', () {
      for (final bad in [
        const <Payment>[],
        const [Payment(mode: PaymentMode.cash, amount: Money(90000))],
        const [Payment(mode: PaymentMode.cash, amount: Money(110000))],
        const [Payment(mode: PaymentMode.advance, amount: Money(100000))],
      ]) {
        expect(
          () => deliver(payments: bad),
          throwsA(_failure(FailureReason.ruleViolation)),
        );
      }
    });

    test('at most three balance payments fit beside the ADVANCE entry', () {
      List<Payment> split(int n) => [
        for (var i = 0; i < n - 1; i++)
          const Payment(mode: PaymentMode.cash, amount: Money(10000)),
        Payment(mode: PaymentMode.upi, amount: Money(100000 - (n - 1) * 10000)),
      ];
      expect(deliver(payments: split(3)).plan.ops, isNotEmpty);
      expect(
        () => deliver(payments: split(4)),
        throwsA(_failure(FailureReason.ruleViolation)),
      );
    });

    test('an order that is not OPEN is refused', () {
      final done = OrderPlans.copyOrder(
        order,
        status: OrderStatus.delivered,
        billId: 'D01-000001',
      );
      final cancelled = OrderPlans.copyOrder(
        order,
        status: OrderStatus.cancelled,
      );
      for (final o in [done, cancelled]) {
        expect(
          () => deliver(o: o),
          throwsA(_failure(FailureReason.ruleViolation)),
        );
      }
    });
  });

  group('OrderPlans.cancel', () {
    final order = _stored();
    final laterCtx = Fx.sm(at: Fx.now.add(const Duration(days: 1)));
    const auditPath = 'auditLog/PTB-D01-O000004-X';

    PlannedWrite<PreOrder> cancel({
      Money refund = const Money(30000),
      String reason = '  Customer changed plans ',
      PreOrder? o,
    }) => OrderPlans.cancel(
      ctx: laterCtx,
      order: o ?? order,
      reason: reason,
      refund: refund,
    );

    final planned = cancel();

    test(
      'the order update, the ORDER_CANCEL audit and both refund summaries',
      () {
        expect(planned.plan.paths, [
          _orderPath,
          auditPath,
          'locations/PTB/dailySummary/2026-09-27',
          'locations/PTB/monthlySummary/2026-09',
        ]);
        expect(planned.plan.ops.map((o) => o.kind), [
          WriteKind.update,
          WriteKind.create,
          WriteKind.setMerge,
          WriteKind.setMerge,
        ]);
      },
    );

    test(
      'the update sets status CANCELLED and the cancel map, nothing else',
      () {
        expect(planned.plan.opAt(_orderPath)!.data, {
          'status': 'CANCELLED',
          'cancel': {
            'reason': 'Customer changed plans',
            'by': 'sm-ptb',
            'at': laterCtx.now,
            'businessDate': '2026-09-27',
            'refunded': 30000,
          },
        });
      },
    );

    test('the audit is {loc}-{orderId}-X, ORDER_CANCEL, at the location', () {
      final a = planned.plan.opAt(auditPath)!.data;
      expect(a['action'], 'ORDER_CANCEL');
      expect(a['entityPath'], _orderPath);
      expect(a['locationId'], 'PTB');
      expect(a['by'], 'sm-ptb');
      expect(a['deviceId'], 'D01');
      expect(a['reason'], 'Customer changed plans');
      expect(a['before'], {'status': 'OPEN'});
      expect(a['after'], {'status': 'CANCELLED', 'refunded': 30000});
      expect(a['at'], serverTimestamp);
      expect(
        auditPath,
        FirestorePaths.audit(Ids.auditId('PTB', order.cancelId)),
      );
    });

    test(
      'advanceRefunded is counted on the cancellation day, naming the audit',
      () {
        for (final path in [
          'locations/PTB/dailySummary/2026-09-27',
          'locations/PTB/monthlySummary/2026-09',
        ]) {
          expect(planned.plan.opAt(path)!.data, {
            'advanceRefunded': const Increment(30000),
            'lastWriteRef': auditPath,
          });
        }
      },
    );

    test(
      'a refund of zero writes no summary, and the whole advance may go back',
      () {
        final none = cancel(refund: Money.zero);
        expect(none.plan.paths, [_orderPath, auditPath]);
        final all = cancel(refund: const Money(50000));
        expect(
          all.plan
              .opAt('locations/PTB/dailySummary/2026-09-27')!
              .data['advanceRefunded'],
          const Increment(50000),
        );
      },
    );

    test('the cancelled order is returned with its cancel record', () {
      final c = planned.value;
      expect(c.status, OrderStatus.cancelled);
      expect(c.cancel!.refunded, const Money(30000));
      expect(c.cancel!.reason, 'Customer changed plans');
      expect(c.id, order.id);
    });

    test('refuses a refund above the advance or in part rupees, no reason, a '
        'long reason, or an order that is not OPEN', () {
      for (final bad in [
        () => cancel(refund: const Money(50100)),
        () => cancel(refund: const Money(25050)),
        () => cancel(refund: const Money(-100)),
        () => cancel(reason: '   '),
        () => cancel(reason: 'r' * (Limits.orderReasonMax + 1)),
        () => cancel(
          o: OrderPlans.copyOrder(order, status: OrderStatus.delivered),
        ),
        () => cancel(
          o: OrderPlans.copyOrder(order, status: OrderStatus.cancelled),
        ),
      ]) {
        expect(bad, throwsA(_failure(FailureReason.ruleViolation)));
      }
      expect(
        cancel(reason: 'r' * Limits.orderReasonMax).value.cancel!.reason,
        hasLength(Limits.orderReasonMax),
      );
    });

    test('an order with no advance cancels with a zero refund only', () {
      final none = _stored(input: _input(advance: Money.zero));
      expect(cancel(o: none, refund: Money.zero).plan.paths, hasLength(2));
      expect(
        () => cancel(o: none, refund: const Money(100)),
        throwsA(_failure(FailureReason.ruleViolation)),
      );
    });
  });

  test('the bill id used by the delivery fixtures is D01-000007', () {
    expect(_billPath, 'locations/PTB/bills/D01-000007');
  });
}
