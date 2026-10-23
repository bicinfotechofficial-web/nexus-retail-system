import 'package:nexus_core/nexus_core.dart';
import 'package:test/test.dart';

void main() {
  final at = DateTime.utc(2026, 10, 20, 4);
  final customer = BillCustomer(name: 'Anita', phone: '9876543210');

  PreOrder open({Money? price, Money? advance}) => PreOrder(
    id: 'D01-O000007',
    orderNo: 'PTB-D01-O000007',
    deviceId: 'D01',
    seq: 7,
    customer: customer,
    dueDate: '2026-10-23',
    dueTime: '16:30',
    description: '3 layer chocolate, 2 kg, "Happy Birthday Riya"',
    price: price ?? const Money.rupees(2400),
    advance: advance ?? const Money.rupees(1000),
    advanceMode: PaymentMode.upi,
    status: OrderStatus.open,
    servedBy: const ServedBy(uid: 'u1', name: 'Manager'),
    businessDate: '2026-10-20',
    clientCreatedAt: at,
    createdBy: 'u1',
  );

  group('Ids', () {
    test('order ID and number', () {
      expect(Ids.orderId('D01', 7), 'D01-O000007');
      expect(Ids.orderNo('PTB', 'D01-O000007'), 'PTB-D01-O000007');
      expect(() => Ids.orderId('X1', 7), throwsArgumentError);
    });
  });

  group('PaymentMode', () {
    test('ADVANCE is a mode but never selectable', () {
      expect(PaymentMode.fromWire('ADVANCE'), PaymentMode.advance);
      expect(PaymentMode.selectable, isNot(contains(PaymentMode.advance)));
      expect(PaymentMode.selectable, hasLength(5));
    });
  });

  group('PreOrder', () {
    test('round trip through the stored map', () {
      final o = open();
      final stored = {...o.toMap(), 'serverCreatedAt': at};
      final back = PreOrder.fromMap(o.id, stored);
      expect(back.toMap(), o.toMap());
      expect(back.customer.id, customer.id);
      expect(back.balance, const Money.rupees(1400));
      expect(back.isOpen, isTrue);
      expect(back.advanceMode, PaymentMode.upi);
      expect(back.dueTime, '16:30');
    });

    test('a cancelled order keeps its cancel details', () {
      final map = {
        ...open().toMap(),
        'status': 'CANCELLED',
        'cancel': {
          'reason': 'Customer changed plan',
          'by': 'u1',
          'at': at,
          'businessDate': '2026-10-21',
          'refunded': 50000,
        },
      };
      final o = PreOrder.fromMap('D01-O000007', map);
      expect(o.status, OrderStatus.cancelled);
      expect(o.cancel!.refunded, const Money.rupees(500));
      expect(o.cancelId, 'D01-O000007-X');
    });

    test('a delivered order links its bill', () {
      final map = {
        ...open().toMap(),
        'status': 'DELIVERED',
        'billId': 'D01-000321',
        'deliveredAt': at,
      };
      final o = PreOrder.fromMap('D01-O000007', map);
      expect(o.status, OrderStatus.delivered);
      expect(o.billId, 'D01-000321');
      expect(o.deliveredAt, at);
    });

    test('an order with no customer is rejected', () {
      final map = {...open().toMap()}
        ..removeWhere((k, _) => k.startsWith('customer'));
      expect(() => PreOrder.fromMap('x', map), throwsFormatException);
    });

    test('no advance means no mode', () {
      final o = open(advance: Money.zero);
      expect(o.balance, o.price);
    });
  });

  group('Bill.orderId', () {
    test('reads back from a stored bill', () {
      final bill = Bill.fromMap('D01-000321', {
        'billNo': 'PTB-D01-000321',
        'deviceId': 'D01',
        'seq': 321,
        'lines': [
          {
            'productId': 'CUSTOM-CAKE',
            'name': 'Custom cake',
            'qty': 1,
            'unitPrice': 240000,
            'lineTotal': 240000,
          },
        ],
        'subtotal': 240000,
        'taxableValue': 240000,
        'taxLines': <Object?>[],
        'roundOff': 0,
        'total': 240000,
        'payments': [
          {'mode': 'ADVANCE', 'amount': 100000},
          {'mode': 'CASH', 'amount': 140000},
        ],
        'status': 'COMPLETED',
        'returnedQty': <String, Object?>{},
        'servedBy': {'uid': 'u1', 'name': 'Manager'},
        'orderId': 'D01-O000007',
        'businessDate': '2026-10-23',
        'clientCreatedAt': at,
        'createdBy': 'u1',
      });
      expect(bill.orderId, 'D01-O000007');
      expect(bill.payments.first.mode, PaymentMode.advance);
    });
  });

  group('OrderValidator', () {
    test('description', () {
      expect(OrderValidator.descriptionError('  '), isNotNull);
      expect(OrderValidator.descriptionError('3 layer'), isNull);
      expect(OrderValidator.descriptionError('x' * 501), isNotNull);
      expect(OrderValidator.cleanDescription('  a   b \n  c  '), 'a b\nc');
    });

    test('due date and time', () {
      expect(OrderValidator.dueDateError('2026-10-20', '2026-10-20'), isNull);
      expect(
        OrderValidator.dueDateError('2026-10-19', '2026-10-20'),
        isNotNull,
      );
      expect(
        OrderValidator.dueDateError('2026-02-30', '2026-10-20'),
        isNotNull,
      );
      expect(OrderValidator.dueTimeError(null), isNull);
      expect(OrderValidator.dueTimeError('09:05'), isNull);
      expect(OrderValidator.dueTimeError('24:00'), isNotNull);
      expect(OrderValidator.dueTimeError('9:5'), isNotNull);
    });

    test('price and advance', () {
      expect(OrderValidator.priceError(Money.zero), isNotNull);
      expect(OrderValidator.priceError(const Money(150050)), isNotNull);
      expect(OrderValidator.priceError(const Money.rupees(2400)), isNull);
      const price = Money.rupees(2400);
      expect(OrderValidator.advanceError(Money.zero, price, null), isNull);
      expect(
        OrderValidator.advanceError(
          const Money.rupees(1000),
          price,
          PaymentMode.cash,
        ),
        isNull,
      );
      expect(
        OrderValidator.advanceError(const Money.rupees(1000), price, null),
        isNotNull,
      );
      expect(
        OrderValidator.advanceError(
          const Money.rupees(1000),
          price,
          PaymentMode.advance,
        ),
        isNotNull,
      );
      expect(
        OrderValidator.advanceError(
          const Money.rupees(2500),
          price,
          PaymentMode.cash,
        ),
        isNotNull,
      );
      expect(
        OrderValidator.advanceError(
          const Money.rupees(2400),
          price,
          PaymentMode.cash,
        ),
        isNull,
      );
      expect(
        OrderValidator.advanceError(Money.zero, price, PaymentMode.cash),
        isNotNull,
      );
      expect(
        OrderValidator.advanceError(const Money(-100), price, null),
        isNotNull,
      );
      expect(
        OrderValidator.advanceError(
          const Money(100050),
          price,
          PaymentMode.cash,
        ),
        isNotNull,
      );
    });

    test('refund', () {
      const adv = Money.rupees(1000);
      expect(OrderValidator.refundError(Money.zero, adv), isNull);
      expect(OrderValidator.refundError(adv, adv), isNull);
      expect(
        OrderValidator.refundError(const Money.rupees(1001), adv),
        isNotNull,
      );
      expect(OrderValidator.refundError(const Money(-100), adv), isNotNull);
      expect(OrderValidator.refundError(const Money(10050), adv), isNotNull);
    });

    test('due state', () {
      expect(
        OrderValidator.dueState('2026-10-19', '2026-10-20'),
        OrderDue.overdue,
      );
      expect(
        OrderValidator.dueState('2026-10-20', '2026-10-20'),
        OrderDue.today,
      );
      expect(
        OrderValidator.dueState('2026-10-21', '2026-10-20'),
        OrderDue.tomorrow,
      );
      expect(
        OrderValidator.dueState('2026-10-22', '2026-10-20'),
        OrderDue.later,
      );
      expect(
        OrderValidator.dueState('2026-11-01', '2026-10-31'),
        OrderDue.tomorrow,
      );
    });
  });

  group('Summary advance fields', () {
    test('default to zero, add up and round trip', () {
      final empty = Summary.fromMap('2026-10-20', {});
      expect(empty.advanceReceived, Money.zero);
      final a = Summary(
        advanceReceived: const Money.rupees(1000),
        advanceRefunded: const Money.rupees(100),
      );
      final b = Summary(advanceReceived: const Money.rupees(500));
      final sum = a + b;
      expect(sum.advanceReceived, const Money.rupees(1500));
      expect(sum.advanceRefunded, const Money.rupees(100));
      expect(
        Summary.fromMap('x', sum.toMap()).advanceReceived,
        const Money.rupees(1500),
      );
    });
  });

  group('Product.openPrice', () {
    test('defaults to false and round trips', () {
      final p = Product.fromMap('CUSTOM-CAKE', {
        'name': 'Custom cake',
        'category': 'Cakes',
        'price': 0,
        'unit': 'PCS',
        'scope': 'GLOBAL',
        'status': 'ACTIVE',
        'openPrice': true,
        'sortOrder': 99,
        'createdBy': 'u1',
      });
      expect(p.openPrice, isTrue);
      expect(p.toMap()['openPrice'], isTrue);
      final plain = Product.fromMap('x', {
        'name': 'X',
        'category': 'C',
        'unit': 'PCS',
        'scope': 'GLOBAL',
        'status': 'ACTIVE',
        'createdBy': 'u1',
      });
      expect(plain.openPrice, isFalse);
    });
  });

  group('Device.lastOrderSeq', () {
    test('defaults to 0', () {
      final d = Device.fromMap('D01', {
        'code': 'D01',
        'label': 'x',
        'registeredBy': 'u',
      });
      expect(d.lastOrderSeq, 0);
    });
  });

  group('summary deltas and cancel for orders', () {
    test('an order adds its advance; a cancellation its refund', () {
      final d = SummaryDeltas.forOrderCreated(open());
      expect(SummaryDeltas.increments(d), {'advanceReceived': 100000});
      final c = SummaryDeltas.forOrderCancelled(
        OrderCancel(
          reason: 'x',
          by: 'u1',
          at: at,
          businessDate: '2026-10-21',
          refunded: const Money.rupees(500),
        ),
      );
      expect(SummaryDeltas.increments(c), {'advanceRefunded': 50000});
      expect(
        SummaryDeltas.increments(
          SummaryDeltas.forOrderCreated(open(advance: Money.zero)),
        ),
        isEmpty,
      );
    });

    test('a delivery bill cannot be cancelled', () {
      final bill = Bill.fromMap('D01-000321', {
        'billNo': 'PTB-D01-000321',
        'deviceId': 'D01',
        'seq': 321,
        'lines': [
          {
            'productId': 'CUSTOM-CAKE',
            'name': 'Custom cake',
            'qty': 1,
            'unitPrice': 240000,
            'lineTotal': 240000,
          },
        ],
        'subtotal': 240000,
        'taxableValue': 240000,
        'taxLines': <Object?>[],
        'roundOff': 0,
        'total': 240000,
        'payments': [
          {'mode': 'ADVANCE', 'amount': 100000},
          {'mode': 'CASH', 'amount': 140000},
        ],
        'status': 'COMPLETED',
        'returnedQty': <String, Object?>{},
        'servedBy': {'uid': 'u1', 'name': 'Manager'},
        'orderId': 'D01-O000007',
        'businessDate': '2026-10-23',
        'clientCreatedAt': at,
        'createdBy': 'u1',
      });
      expect(cancelBlocker(bill, '2026-10-23'), CancelBlocker.deliversOrder);
    });
  });
}
