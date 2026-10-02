import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';

import 'plan_fixtures.dart';

const _billPath = 'locations/PTB/bills/D01-000007';

/// `locations/PTB/customers/{id}` of [Fx.customer].
final String _customerPath = 'locations/PTB/customers/${Fx.customer.id}';

Map<String, Object?> _stock(
  String productId,
  String name,
  int delta,
  String mid,
) => {
  'kind': 'FINISHED',
  'refId': productId,
  'name': name,
  'unit': 'PCS',
  'qty': Increment(delta),
  'lastMovementId': mid,
  'updatedAt': serverTimestamp,
};

Matcher _failure(FailureReason r) =>
    isA<DataFailure>().having((f) => f.reason, 'reason', r);

void main() {
  group('createBill', () {
    final planned = SalesPlans.createBill(
      ctx: Fx.sm(),
      seq: 7,
      input: Fx.newBill,
      servedByName: 'Store Manager PTB',
      maxDiscountPct: 20,
    );
    final plan = planned.plan;
    final bill = planned.value;

    test(
      'writes bill, stock, SALE movement, summaries, customer and device, in order',
      () {
        expect(plan.paths, [
          _billPath,
          'locations/PTB/stock/FG_cake-choco-1kg',
          'locations/PTB/stock/FG_puff-veg',
          'locations/PTB/movements/D01-000007',
          'locations/PTB/dailySummary/2026-09-26',
          'locations/PTB/monthlySummary/2026-09',
          _customerPath,
          'locations/PTB/devices/D01',
        ]);
        expect(plan.ops.map((o) => o.kind), [
          WriteKind.create,
          WriteKind.setMerge,
          WriteKind.setMerge,
          WriteKind.create,
          WriteKind.setMerge,
          WriteKind.setMerge,
          WriteKind.setMerge,
          WriteKind.update,
        ]);
      },
    );

    test('the bill has every total, soldQty and a server timestamp', () {
      expect(bill.id, 'D01-000007');
      expect(bill.billNo, 'PTB-D01-000007');
      expect(plan.opAt(_billPath)!.data, {
        'billNo': 'PTB-D01-000007',
        'deviceId': 'D01',
        'seq': 7,
        'lines': [
          {
            'productId': 'cake-choco-1kg',
            'name': 'Chocolate Cake 1 kg',
            'qty': 1,
            'unitPrice': 65000,
            'lineTotal': 65000,
          },
          {
            'productId': 'puff-veg',
            'name': 'Veg Puff',
            'qty': 2,
            'unitPrice': 2550,
            'lineTotal': 5100,
          },
        ],
        'subtotal': 70100,
        'discount': {'type': 'PCT', 'value': 10, 'amount': 7010},
        'taxableValue': 63090,
        'taxLines': <Object?>[],
        'roundOff': 10,
        'total': 63100,
        'payments': [
          {'mode': 'CASH', 'amount': 50000},
          {'mode': 'UPI', 'amount': 13100, 'ref': 'UPI-1'},
        ],
        'cashTendered': 50000,
        'status': 'COMPLETED',
        'cancel': null,
        'returnedQty': <String, int>{},
        'soldQty': {'cake-choco-1kg': 1, 'puff-veg': 2},
        'lastReturnId': null,
        'servedBy': {'uid': 'sm-ptb', 'name': 'Store Manager PTB'},
        'businessDate': '2026-09-26',
        'clientCreatedAt': Fx.now,
        'createdBy': 'sm-ptb',
        'customerId': Fx.customer.id,
        'customerName': 'Test Customer',
        'customerPhone': '9876543210',
        'customerWhatsapp': '9876543210',
        'serverCreatedAt': serverTimestamp,
      });
    });

    test(
      'the customer is written as set(merge) with the bill ID and total',
      () {
        expect(plan.opAt(_customerPath)!.kind, WriteKind.setMerge);
        expect(plan.opAt(_customerPath)!.data, {
          'name': 'Test Customer',
          'phone': '9876543210',
          'whatsapp': '9876543210',
          'lastBillAt': serverTimestamp,
          'billCount': const Increment(1),
          'totalSpend': const Increment(63100),
          'lastWriteRef': 'D01-000007',
        });
        expect(Fx.customer.id, startsWith('9876543210_'));
      },
    );

    test('stock goes down by each line qty, naming the SALE movement', () {
      expect(
        plan.opAt('locations/PTB/stock/FG_cake-choco-1kg')!.data,
        _stock('cake-choco-1kg', 'Chocolate Cake 1 kg', -1, 'D01-000007'),
      );
      expect(
        plan.opAt('locations/PTB/stock/FG_puff-veg')!.data,
        _stock('puff-veg', 'Veg Puff', -2, 'D01-000007'),
      );
    });

    test('the SALE movement shares the bill ID', () {
      expect(plan.opAt('locations/PTB/movements/D01-000007')!.data, {
        'type': 'SALE',
        'lines': [
          {'itemKey': 'FG_cake-choco-1kg', 'delta': -1},
          {'itemKey': 'FG_puff-veg', 'delta': -2},
        ],
        'reason': null,
        'note': null,
        'refId': 'D01-000007',
        'businessDate': '2026-09-26',
        'clientCreatedAt': Fx.now,
        'createdBy': 'sm-ptb',
        'deviceId': 'D01',
        'serverCreatedAt': serverTimestamp,
      });
    });

    test('every summary field is exact, on the daily and monthly doc', () {
      const expected = {
        'billCount': Increment(1),
        'grossSales': Increment(70100),
        'discounts': Increment(7010),
        'roundOff': Increment(10),
        'netSales': Increment(63100),
        'byMode': {'CASH': Increment(50000), 'UPI': Increment(13100)},
        'byProduct': {
          'cake-choco-1kg': {'qty': Increment(1), 'amount': Increment(58500)},
          'puff-veg': {'qty': Increment(2), 'amount': Increment(4590)},
        },
        'lastWriteRef': _billPath,
      };
      expect(
        plan.opAt('locations/PTB/dailySummary/2026-09-26')!.data,
        expected,
      );
      expect(plan.opAt('locations/PTB/monthlySummary/2026-09')!.data, expected);
    });

    test('a customer without WhatsApp overwrites it with null', () {
      final p = SalesPlans.createBill(
        ctx: Fx.sm(),
        seq: 8,
        input: NewBill(
          cart: Fx.newBill.cart,
          discount: Fx.newBill.discount,
          payments: Fx.newBill.payments,
          customer: BillCustomer(name: 'Test Customer', phone: '9876543210'),
        ),
        servedByName: 'SM',
      );
      final bill = p.plan.opAt('locations/PTB/bills/D01-000008')!.data;
      expect(bill['customerWhatsapp'], isNull);
      expect(bill.containsKey('customerWhatsapp'), isTrue);
      final c = p.plan.opAt(_customerPath)!.data;
      expect(c['whatsapp'], isNull);
      expect(c.containsKey('whatsapp'), isTrue);
    });

    test('the device records lastBillSeq', () {
      expect(plan.opAt('locations/PTB/devices/D01')!.data, {'lastBillSeq': 7});
    });

    test('a zero round-off and a free line leave those fields out', () {
      final p = SalesPlans.createBill(
        ctx: Fx.sm(),
        seq: 1,
        input: NewBill(
          customer: Fx.customer,
          cart: const [
            CartLine(
              productId: 'a',
              name: 'A',
              qty: 1,
              unitPrice: Money(10000),
            ),
            CartLine(
              productId: 'free',
              name: 'Free',
              qty: 1,
              unitPrice: Money.zero,
            ),
          ],
          payments: const [
            Payment(mode: PaymentMode.card, amount: Money(10000)),
          ],
        ),
        servedByName: 'SM',
      ).plan;
      expect(p.opAt('locations/PTB/dailySummary/2026-09-26')!.data, {
        'billCount': const Increment(1),
        'grossSales': const Increment(10000),
        'netSales': const Increment(10000),
        'byMode': {'CARD': const Increment(10000)},
        'byProduct': {
          'a': {'qty': const Increment(1), 'amount': const Increment(10000)},
          'free': {'qty': const Increment(1)},
        },
        'lastWriteRef': 'locations/PTB/bills/D01-000001',
      });
    });

    test('the business date is the IST date of the device clock', () {
      // 2026-09-30 20:00 UTC is 1 October in IST.
      final p = SalesPlans.createBill(
        ctx: Fx.sm(at: DateTime.utc(2026, 9, 30, 20)),
        seq: 8,
        input: Fx.newBill,
        servedByName: 'SM',
      );
      expect(p.value.businessDate, '2026-10-01');
      expect(
        p.plan.paths,
        containsAll([
          'locations/PTB/dailySummary/2026-10-01',
          'locations/PTB/monthlySummary/2026-10',
        ]),
      );
    });

    test('refuses bad payments, a bad cart, no device or no location', () {
      NewBill withPayments(List<Payment> p) => NewBill(
        cart: Fx.newBill.cart,
        discount: Fx.newBill.discount,
        payments: p,
        customer: Fx.customer,
      );
      expect(
        () => SalesPlans.createBill(
          ctx: Fx.sm(),
          seq: 1,
          input: withPayments(const [
            Payment(mode: PaymentMode.cash, amount: Money(60000)),
          ]),
          servedByName: 'SM',
        ),
        throwsA(_failure(FailureReason.ruleViolation)),
      );
      expect(
        () => SalesPlans.createBill(
          ctx: Fx.sm(),
          seq: 1,
          input: NewBill(
            cart: const [],
            payments: const [],
            customer: Fx.customer,
          ),
          servedByName: 'SM',
        ),
        throwsA(isA<BillValidationException>()),
      );
      expect(
        () => SalesPlans.createBill(
          ctx: Fx.sm(),
          seq: 1,
          input: Fx.newBill,
          servedByName: 'SM',
          maxDiscountPct: 5,
        ),
        throwsA(isA<BillValidationException>()),
      );
      expect(
        () => SalesPlans.createBill(
          ctx: PlanContext(uid: 'u', locationId: 'PTB', now: Fx.now),
          seq: 1,
          input: Fx.newBill,
          servedByName: 'SM',
        ),
        throwsA(_failure(FailureReason.deviceNotRegistered)),
      );
      expect(
        () => SalesPlans.createBill(
          ctx: PlanContext(uid: 'u', deviceId: 'D01', now: Fx.now),
          seq: 1,
          input: Fx.newBill,
          servedByName: 'SM',
        ),
        throwsA(_failure(FailureReason.notPermitted)),
      );
    });
  });

  group('cancelBill', () {
    final bill = Fx.bill();
    final planned = SalesPlans.cancelBill(
      ctx: Fx.sm(at: Fx.now.add(const Duration(hours: 1)), deviceId: 'D02'),
      bill: bill,
      reason: '  Customer changed order ',
    );
    final plan = planned.plan;
    final later = Fx.now.add(const Duration(hours: 1));

    test('writes bill, stock, CANCEL movement, summaries and audit', () {
      expect(plan.paths, [
        _billPath,
        'locations/PTB/stock/FG_cake-choco-1kg',
        'locations/PTB/stock/FG_puff-veg',
        'locations/PTB/movements/D01-000007-X',
        'locations/PTB/dailySummary/2026-09-26',
        'locations/PTB/monthlySummary/2026-09',
        'auditLog/PTB-D01-000007-X',
      ]);
      expect(planned.value.status, BillStatus.cancelled);
      expect(planned.value.cancel!.reason, 'Customer changed order');
    });

    test('the bill update changes only status and cancel', () {
      final op = plan.opAt(_billPath)!;
      expect(op.kind, WriteKind.update);
      expect(op.data, {
        'status': 'CANCELLED',
        'cancel': {
          'reason': 'Customer changed order',
          'by': 'sm-ptb',
          'at': later,
          'businessDate': '2026-09-26',
        },
      });
    });

    test(
      'restocks every line under the CANCEL movement, made on this device',
      () {
        expect(
          plan.opAt('locations/PTB/stock/FG_puff-veg')!.data,
          _stock('puff-veg', 'Veg Puff', 2, 'D01-000007-X'),
        );
        expect(plan.opAt('locations/PTB/movements/D01-000007-X')!.data, {
          'type': 'CANCEL',
          'lines': [
            {'itemKey': 'FG_cake-choco-1kg', 'delta': 1},
            {'itemKey': 'FG_puff-veg', 'delta': 2},
          ],
          'reason': 'Customer changed order',
          'note': null,
          'refId': 'D01-000007',
          'businessDate': '2026-09-26',
          'clientCreatedAt': later,
          'createdBy': 'sm-ptb',
          'deviceId': 'D02',
          'serverCreatedAt': serverTimestamp,
        });
      },
    );

    test('summaries reverse byMode and byProduct and add to cancelled', () {
      const expected = {
        'cancelCount': Increment(1),
        'cancelled': Increment(63100),
        'byMode': {'CASH': Increment(-50000), 'UPI': Increment(-13100)},
        'byProduct': {
          'cake-choco-1kg': {'qty': Increment(-1), 'amount': Increment(-58500)},
          'puff-veg': {'qty': Increment(-2), 'amount': Increment(-4590)},
        },
        'lastWriteRef': 'locations/PTB/movements/D01-000007-X',
      };
      expect(
        plan.opAt('locations/PTB/dailySummary/2026-09-26')!.data,
        expected,
      );
      expect(plan.opAt('locations/PTB/monthlySummary/2026-09')!.data, expected);
    });

    test('the audit has the cancel ID prefixed with the location (D-028)', () {
      expect(plan.opAt('auditLog/PTB-D01-000007-X')!.data, {
        'action': 'BILL_CANCEL',
        'entityPath': _billPath,
        'locationId': 'PTB',
        'before': {'status': 'COMPLETED'},
        'after': {'status': 'CANCELLED'},
        'reason': 'Customer changed order',
        'by': 'sm-ptb',
        'deviceId': 'D02',
        'clientAt': later,
        'at': serverTimestamp,
      });
    });

    test('refuses another day, a returned bill, and no reason', () {
      expect(
        () => SalesPlans.cancelBill(
          ctx: Fx.sm(at: Fx.now.add(const Duration(days: 1))),
          bill: bill,
          reason: 'x',
        ),
        throwsA(_failure(FailureReason.ruleViolation)),
      );
      final returned = SalesPlans.createReturn(
        ctx: Fx.sm(),
        seq: 1,
        bill: bill,
        qtyByProduct: {'puff-veg': 1},
        refunds: const [Payment(mode: PaymentMode.cash, amount: Money(2300))],
        reason: 'r',
      );
      expect(returned.value.refundTotal, const Money(2300));
      final afterReturn = Bill.fromMap(bill.id, {
        ...bill.toMap(),
        'returnedQty': {'puff-veg': 1},
        'lastReturnId': 'D01-R000001',
      });
      expect(
        () =>
            SalesPlans.cancelBill(ctx: Fx.sm(), bill: afterReturn, reason: 'x'),
        throwsA(_failure(FailureReason.ruleViolation)),
      );
      expect(
        () => SalesPlans.cancelBill(ctx: Fx.sm(), bill: bill, reason: '  '),
        throwsA(_failure(FailureReason.ruleViolation)),
      );
    });
  });

  group('createReturn', () {
    final bill = Fx.bill();
    const cash2300 = [Payment(mode: PaymentMode.cash, amount: Money(2300))];
    final planned = SalesPlans.createReturn(
      ctx: Fx.sm(),
      seq: 3,
      bill: bill,
      qtyByProduct: {'puff-veg': 1},
      refunds: cash2300,
      reason: 'Damaged',
    );
    final plan = planned.plan;
    const returnPath = 'locations/PTB/returns/D01-R000003';

    test(
      'writes return, bill, stock, movement, summaries, audit and device',
      () {
        expect(plan.paths, [
          returnPath,
          _billPath,
          'locations/PTB/stock/FG_puff-veg',
          'locations/PTB/movements/D01-R000003',
          'locations/PTB/dailySummary/2026-09-26',
          'locations/PTB/monthlySummary/2026-09',
          'auditLog/PTB-D01-R000003',
          'locations/PTB/devices/D01',
        ]);
      },
    );

    test(
      'the return is prorated from the line net and chained to the bill',
      () {
        // Puff line net ₹45.90 for 2; one is ₹22.95, refunded as ₹23.
        expect(plan.opAt(returnPath)!.data, {
          'billId': 'D01-000007',
          'billNo': 'PTB-D01-000007',
          'lines': [
            {
              'productId': 'puff-veg',
              'name': 'Veg Puff',
              'qty': 1,
              'amount': 2295,
            },
          ],
          'refundTotal': 2300,
          'refunds': [
            {'mode': 'CASH', 'amount': 2300},
          ],
          'reason': 'Damaged',
          'prevReturnId': null,
          'businessDate': '2026-09-26',
          'createdBy': 'sm-ptb',
          'deviceId': 'D01',
          'clientCreatedAt': Fx.now,
          'serverCreatedAt': serverTimestamp,
        });
      },
    );

    test('the bill update increments returnedQty by field path', () {
      final op = plan.opAt(_billPath)!;
      expect(op.kind, WriteKind.update);
      expect(op.data, {
        'returnedQty.puff-veg': const Increment(1),
        'lastReturnId': 'D01-R000003',
      });
    });

    test('stock, movement and device', () {
      expect(
        plan.opAt('locations/PTB/stock/FG_puff-veg')!.data,
        _stock('puff-veg', 'Veg Puff', 1, 'D01-R000003'),
      );
      expect(plan.opAt('locations/PTB/movements/D01-R000003')!.data, {
        'type': 'RETURN',
        'lines': [
          {'itemKey': 'FG_puff-veg', 'delta': 1},
        ],
        'reason': null,
        'note': null,
        'refId': 'D01-R000003',
        'businessDate': '2026-09-26',
        'clientCreatedAt': Fx.now,
        'createdBy': 'sm-ptb',
        'deviceId': 'D01',
        'serverCreatedAt': serverTimestamp,
      });
      expect(plan.opAt('locations/PTB/devices/D01')!.data, {
        'lastReturnSeq': 3,
      });
    });

    test('every summary field is exact', () {
      const expected = {
        'returnCount': Increment(1),
        'returns': Increment(2300),
        'byMode': {'CASH': Increment(-2300)},
        'byProduct': {
          'puff-veg': {'qty': Increment(-1), 'amount': Increment(-2295)},
        },
        'lastWriteRef': returnPath,
      };
      expect(
        plan.opAt('locations/PTB/dailySummary/2026-09-26')!.data,
        expected,
      );
      expect(plan.opAt('locations/PTB/monthlySummary/2026-09')!.data, expected);
    });

    test('the audit is {loc}-{returnId}', () {
      expect(plan.opAt('auditLog/PTB-D01-R000003')!.data, {
        'action': 'RETURN',
        'entityPath': returnPath,
        'locationId': 'PTB',
        'before': null,
        'after': {
          'billId': 'D01-000007',
          'refundTotal': 2300,
          'lines': {'puff-veg': 1},
        },
        'reason': 'Damaged',
        'by': 'sm-ptb',
        'deviceId': 'D01',
        'clientAt': Fx.now,
        'at': serverTimestamp,
      });
    });

    test('a second return names the first as prevReturnId (D-029)', () {
      final afterFirst = Bill.fromMap(bill.id, {
        ...bill.toMap(),
        'returnedQty': {'puff-veg': 1},
        'lastReturnId': 'D01-R000003',
      });
      final second = SalesPlans.createReturn(
        ctx: Fx.sm(),
        seq: 4,
        bill: afterFirst,
        qtyByProduct: {'puff-veg': 1, 'cake-choco-1kg': 1},
        refunds: const [
          Payment(mode: PaymentMode.upi, amount: Money(40000)),
          Payment(mode: PaymentMode.cash, amount: Money(20800)),
        ],
        reason: '',
      );
      // Cumulative (D-024 d): all of it is ₹630.90 → ₹631, less ₹23 = ₹608.
      expect(second.value.refundTotal, const Money(60800));
      expect(second.value.prevReturnId, 'D01-R000003');
      expect(second.plan.opAt(_billPath)!.data, {
        'returnedQty.cake-choco-1kg': const Increment(1),
        'returnedQty.puff-veg': const Increment(1),
        'lastReturnId': 'D01-R000004',
      });
      expect(second.plan.opAt('locations/PTB/dailySummary/2026-09-26')!.data, {
        'returnCount': const Increment(1),
        'returns': const Increment(60800),
        'byMode': {
          'UPI': const Increment(-40000),
          'CASH': const Increment(-20800),
        },
        'byProduct': {
          'cake-choco-1kg': {
            'qty': const Increment(-1),
            'amount': const Increment(-58500),
          },
          'puff-veg': {
            'qty': const Increment(-1),
            'amount': const Increment(-2295),
          },
        },
        'lastWriteRef': 'locations/PTB/returns/D01-R000004',
      });
      expect(
        second.plan.opAt('auditLog/PTB-D01-R000004')!.data['reason'],
        isNull,
      );
    });

    test('counts on the day it is processed, even in a new month (D-012)', () {
      final old = Fx.bill(at: DateTime.utc(2026, 9, 30, 6));
      final p = SalesPlans.createReturn(
        ctx: Fx.sm(at: DateTime.utc(2026, 10, 1, 6)),
        seq: 1,
        bill: old,
        qtyByProduct: {'cake-choco-1kg': 1},
        refunds: const [Payment(mode: PaymentMode.cash, amount: Money(58500))],
        reason: 'r',
      ).plan;
      expect(
        p.paths,
        containsAll([
          'locations/PTB/dailySummary/2026-10-01',
          'locations/PTB/monthlySummary/2026-10',
        ]),
      );
      expect(p.paths.where((x) => x.contains('2026-09')), isEmpty);
    });

    test('refuses a refund split that does not add up, and over-returns', () {
      expect(
        () => SalesPlans.createReturn(
          ctx: Fx.sm(),
          seq: 1,
          bill: bill,
          qtyByProduct: {'puff-veg': 1},
          refunds: const [Payment(mode: PaymentMode.cash, amount: Money(2295))],
          reason: 'r',
        ),
        throwsA(_failure(FailureReason.ruleViolation)),
      );
      expect(
        () => SalesPlans.createReturn(
          ctx: Fx.sm(),
          seq: 1,
          bill: bill,
          qtyByProduct: {'puff-veg': 3},
          refunds: cash2300,
          reason: 'r',
        ),
        throwsA(isA<ReturnValidationException>()),
      );
    });
  });

  group('customer record (D-037)', () {
    PlannedWrite<Bill> bill(int seq, BillCustomer who, {Money? pay}) {
      final total = pay ?? const Money(63100);
      return SalesPlans.createBill(
        ctx: Fx.sm(),
        seq: seq,
        input: NewBill(
          cart: Fx.newBill.cart,
          discount: Fx.newBill.discount,
          payments: [Payment(mode: PaymentMode.cash, amount: total)],
          customer: who,
        ),
        servedByName: 'SM',
      );
    }

    final who = BillCustomer(name: 'Test Customer', phone: '9876543210');

    Iterable<WriteOp> customerOps(WritePlan p) =>
        p.ops.where((o) => o.path.contains('/customers/'));

    test('every bill has exactly one customer op, under the bill location', () {
      final p = bill(1, who).plan;
      expect(customerOps(p), hasLength(1));
      expect(customerOps(p).single.path, 'locations/PTB/customers/${who.id}');
    });

    test(
      'two bills by the same customer share the id, and each increments',
      () {
        final first = bill(1, who).plan;
        final second = bill(2, who).plan;
        expect(customerOps(second).single.path, customerOps(first).single.path);
        final d = customerOps(second).single.data;
        expect(d['billCount'], const Increment(1));
        expect(d['totalSpend'], const Increment(63100));
        expect(d['lastWriteRef'], 'D01-000002');
        expect(customerOps(first).single.data['lastWriteRef'], 'D01-000001');
      },
    );

    test('the name\'s case and spacing do not change the id', () {
      final other = BillCustomer(
        name: '  test   CUSTOMER ',
        phone: '98765 43210',
      );
      expect(other.id, who.id);
      expect(
        customerOps(bill(3, other).plan).single.path,
        customerOps(bill(1, who).plan).single.path,
      );
    });

    test('a different name on the same phone is a different customer', () {
      final other = BillCustomer(name: 'Another Customer', phone: '9876543210');
      expect(other.id, isNot(who.id));
      expect(other.id, startsWith('9876543210_'));
      final p = bill(4, other).plan;
      expect(customerOps(p).single.path, 'locations/PTB/customers/${other.id}');
      expect(customerOps(p).single.data['name'], 'Another Customer');
    });

    test(
      'the increment follows the bill total, a whole-rupee paise amount',
      () {
        final p = bill(5, who, pay: const Money(63100)).plan;
        expect(
          customerOps(p).single.data['totalSpend'],
          const Increment(63100),
        );
      },
    );
  });
}
