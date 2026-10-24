/// QA-11: pre-orders end to end (D-043, PLAN section O), on a model of the
/// server that accepts or rejects whole batches the way 04-PERMISSIONS #18
/// and #19 do, and devices that queue batches while offline and send them
/// in order when they sync (03-SYNC).
///
/// What the emulator rules suites already pin (`firebase/test/orders.test.js`)
/// is not repeated field by field here. These scenarios check what only
/// shows across days, devices and the summaries: an order taken offline and
/// delivered after sync, two phones delivering the same order, a delivery
/// racing a cancellation, the IST day boundary, and that the advance totals
/// in the summaries match the orders.
library;

import 'dart:math';

import 'package:nexus_core/nexus_core.dart';
import 'package:test/test.dart';

const String loc = 'PTB';
const String customCake = 'CUSTOM-CAKE';
const ServedBy manager = ServedBy(uid: 'uid-sm-ptb', name: 'Store Manager');

/// 2026-09-26 23:59:59 IST, one second before the business day turns.
final DateTime lastSecondOf26 = DateTime.utc(2026, 9, 26, 18, 29, 59);

/// 2026-09-27 00:00:00 IST.
final DateTime midnightInto27 = DateTime.utc(2026, 9, 26, 18, 30);

/// 10:00 IST on [businessDate].
DateTime morningOf(String businessDate) =>
    BusinessDate.startOf(businessDate).add(const Duration(hours: 10));

PreOrder newOrder({
  required String deviceId,
  required int seq,
  required DateTime at,
  required String dueDate,
  Money price = const Money(120000),
  Money advance = const Money(50000),
}) {
  final id = Ids.orderId(deviceId, seq);
  return PreOrder(
    id: id,
    orderNo: Ids.orderNo(loc, id),
    deviceId: deviceId,
    seq: seq,
    customer: BillCustomer(name: 'Anu', phone: '9847000001'),
    dueDate: dueDate,
    description: 'Chocolate truffle, 1 kg, "Happy birthday Anu"',
    price: price,
    advance: advance,
    advanceMode: advance.isPositive ? PaymentMode.upi : null,
    status: OrderStatus.open,
    servedBy: manager,
    businessDate: BusinessDate.of(at),
    clientCreatedAt: at,
    createdBy: manager.uid,
  );
}

/// [o] with its status moved on, the way the deliver and cancel batches
/// update the document.
PreOrder moved(
  PreOrder o,
  OrderStatus status, {
  String? billId,
  DateTime? deliveredAt,
  OrderCancel? cancel,
}) => PreOrder(
  id: o.id,
  orderNo: o.orderNo,
  deviceId: o.deviceId,
  seq: o.seq,
  customer: o.customer,
  dueDate: o.dueDate,
  dueTime: o.dueTime,
  description: o.description,
  price: o.price,
  advance: o.advance,
  advanceMode: o.advanceMode,
  status: status,
  billId: billId ?? o.billId,
  deliveredAt: deliveredAt ?? o.deliveredAt,
  cancel: cancel ?? o.cancel,
  servedBy: o.servedBy,
  businessDate: o.businessDate,
  clientCreatedAt: o.clientCreatedAt,
  createdBy: o.createdBy,
);

/// The delivery bill (D-043 (c)): one CUSTOM-CAKE line at the agreed price,
/// an ADVANCE entry for the advance when there was one, then [balance] (the
/// part paid now, in counter modes only).
Bill deliveryBill(
  PreOrder o, {
  required String deviceId,
  required int seq,
  required DateTime at,
  List<Payment>? balance,
}) {
  final t = BillCalculator.compute([
    CartLine(
      productId: customCake,
      name: 'Custom cake',
      qty: 1,
      unitPrice: o.price,
    ),
  ]);
  final rest = t.total - o.advance;
  final id = Ids.billId(deviceId, seq);
  return Bill(
    id: id,
    billNo: '$loc-$id',
    deviceId: deviceId,
    seq: seq,
    lines: t.lines,
    subtotal: t.subtotal,
    taxableValue: t.taxableValue,
    roundOff: t.roundOff,
    total: t.total,
    payments: [
      if (o.advance.isPositive)
        Payment(mode: PaymentMode.advance, amount: o.advance),
      ...?balance,
      if (balance == null && rest.isPositive)
        Payment(mode: PaymentMode.cash, amount: rest),
    ],
    status: BillStatus.completed,
    servedBy: manager,
    businessDate: BusinessDate.of(at),
    clientCreatedAt: at,
    createdBy: manager.uid,
    orderId: o.id,
  );
}

OrderCancel cancelOf(String reason, Money refunded, DateTime at) => OrderCancel(
  reason: reason,
  by: manager.uid,
  at: at,
  businessDate: BusinessDate.of(at),
  refunded: refunded,
);

/// One atomic batch, as a device sends it.
sealed class Batch {
  const Batch();
}

final class CreateOrder extends Batch {
  const CreateOrder(this.order);
  final PreOrder order;
}

final class Deliver extends Batch {
  const Deliver(this.orderId, this.bill);
  final String orderId;
  final Bill bill;
}

final class CancelOrder extends Batch {
  const CancelOrder(this.orderId, this.cancel);
  final String orderId;
  final OrderCancel cancel;
}

final class CancelBill extends Batch {
  const CancelBill(this.billId, this.cancel);
  final String billId;
  final BillCancel cancel;
}

/// The server: documents plus the daily summaries, and the accept-or-reject
/// decision of 04-PERMISSIONS #18 and #19 for each batch, all or nothing.
final class OrderServer {
  final Map<String, PreOrder> orders = {};
  final Map<String, Bill> bills = {};
  final Map<String, Summary> daily = {};

  void _count(String businessDate, Summary delta) =>
      daily[businessDate] = (daily[businessDate] ?? const Summary()) + delta;

  /// Applies [b], or returns why it was rejected and changes nothing.
  String? apply(Batch b) {
    switch (b) {
      case CreateOrder(:final order):
        if (orders.containsKey(order.id)) return 'order exists';
        if (order.advance > order.price) return 'advance above the price';
        orders[order.id] = order;
        _count(order.businessDate, SummaryDeltas.forOrderCreated(order));
      case Deliver(:final orderId, :final bill):
        final o = orders[orderId];
        if (o == null) return 'no such order';
        if (o.status != OrderStatus.open) return 'order is ${o.status.wire}';
        if (bills.containsKey(bill.id)) return 'bill exists';
        if (bill.orderId != orderId) return 'bill names another order';
        final adv = bill.payments.where((p) => p.mode == PaymentMode.advance);
        final ok = o.advance.isZero
            ? adv.isEmpty
            : adv.length == 1 && adv.single.amount == o.advance;
        if (!ok) return 'ADVANCE entry does not match the order';
        final paid = bill.payments.fold(Money.zero, (s, p) => s + p.amount);
        if (paid != bill.total) return 'payments do not add up';
        bills[bill.id] = bill;
        orders[orderId] = moved(
          o,
          OrderStatus.delivered,
          billId: bill.id,
          deliveredAt: bill.clientCreatedAt,
        );
        _count(bill.businessDate, SummaryDeltas.forBill(bill));
      case CancelOrder(:final orderId, :final cancel):
        final o = orders[orderId];
        if (o == null) return 'no such order';
        if (o.status != OrderStatus.open) return 'order is ${o.status.wire}';
        if (cancel.reason.trim().isEmpty) return 'no reason';
        if (cancel.refunded.isNegative || cancel.refunded > o.advance) {
          return 'refund outside 0 to the advance';
        }
        if (cancel.refunded.paise % 100 != 0) return 'refund not whole rupees';
        orders[orderId] = moved(o, OrderStatus.cancelled, cancel: cancel);
        _count(cancel.businessDate, SummaryDeltas.forOrderCancelled(cancel));
      case CancelBill(:final billId, :final cancel):
        final bill = bills[billId];
        if (bill == null) return 'no such bill';
        if (bill.orderId != null) return 'bill delivers an order';
        _count(cancel.businessDate, SummaryDeltas.forCancel(bill));
    }
    return null;
  }

  Summary on(String businessDate) => daily[businessDate] ?? const Summary();
}

/// A POS: what it last saw of the server, and the batches it hasn't sent.
final class Device {
  Device(this.id, this.server) {
    _refresh();
  }

  final String id;
  final OrderServer server;
  final List<Batch> queue = [];
  final List<String> syncErrors = [];
  bool online = true;
  int _orderSeq = 0;
  int _billSeq = 0;

  /// The orders as this phone sees them, its own pending writes included.
  late Map<String, PreOrder> orders;

  void _refresh() => orders = Map.of(server.orders);

  void _send(Batch b, void Function() local) {
    local();
    if (online) {
      final why = server.apply(b);
      if (why != null) syncErrors.add(why);
      _refresh();
    } else {
      queue.add(b);
    }
  }

  PreOrder takeOrder({
    required DateTime at,
    required String dueDate,
    Money price = const Money(120000),
    Money advance = const Money(50000),
  }) {
    final o = newOrder(
      deviceId: id,
      seq: ++_orderSeq,
      at: at,
      dueDate: dueDate,
      price: price,
      advance: advance,
    );
    _send(CreateOrder(o), () => orders[o.id] = o);
    return o;
  }

  /// Delivers from this phone's own view, as the POS does (an order shows
  /// as open until a sync says otherwise). Returns null when the phone
  /// itself sees the order as closed.
  Bill? deliver(String orderId, DateTime at, {List<Payment>? balance}) {
    final o = orders[orderId];
    if (o == null || o.status != OrderStatus.open) return null;
    final bill = deliveryBill(
      o,
      deviceId: id,
      seq: ++_billSeq,
      at: at,
      balance: balance,
    );
    _send(
      Deliver(orderId, bill),
      () => orders[orderId] = moved(o, OrderStatus.delivered, billId: bill.id),
    );
    return bill;
  }

  /// Refuses on the phone what `OrderValidator` refuses, like the POS.
  String? cancel(String orderId, String reason, Money refund, DateTime at) {
    final o = orders[orderId];
    if (o == null || o.status != OrderStatus.open) return 'not open here';
    final problem = OrderValidator.refundError(refund, o.advance);
    if (problem != null) return problem;
    final c = cancelOf(reason, refund, at);
    _send(
      CancelOrder(orderId, c),
      () => orders[orderId] = moved(o, OrderStatus.cancelled, cancel: c),
    );
    return null;
  }

  void goOffline() => online = false;

  /// Back online: the queue goes up in order, each batch on its own, and a
  /// rejected batch becomes a sync error (03-SYNC §6).
  void sync() {
    online = true;
    for (final b in queue) {
      final why = server.apply(b);
      if (why != null) syncErrors.add(why);
    }
    queue.clear();
    _refresh();
  }
}

Money sum(Iterable<Money> xs) => xs.fold(Money.zero, (a, b) => a + b);

void main() {
  late OrderServer server;
  late Device d1;
  late Device d2;

  setUp(() {
    server = OrderServer();
    d1 = Device('D01', server);
    d2 = Device('D02', server);
  });

  group('QA-11 O-1: an order taken offline, delivered after sync', () {
    test('gives one bill and one DELIVERED order, each day counted once', () {
      d1.goOffline();
      final o = d1.takeOrder(
        at: morningOf('2026-09-24'),
        dueDate: '2026-09-27',
      );
      expect(server.orders, isEmpty, reason: 'nothing reaches the server');
      expect(d1.orders[o.id]!.status, OrderStatus.open);
      d1.sync();

      final bill = d1.deliver(o.id, morningOf('2026-09-27'))!;
      expect(d1.syncErrors, isEmpty);
      expect(server.bills.keys, [bill.id]);
      expect(server.orders[o.id]!.status, OrderStatus.delivered);
      expect(server.orders[o.id]!.billId, bill.id);

      // The advance on the day it was taken, the sale on the delivery day.
      expect(server.on('2026-09-24').advanceReceived, o.advance);
      expect(server.on('2026-09-24').netSales, Money.zero);
      final day = server.on('2026-09-27');
      expect(day.netSales, o.price);
      expect(day.billCount, 1);
      expect(day.byMode[PaymentMode.advance], o.advance);
      expect(day.byMode[PaymentMode.cash], o.price - o.advance);
      expect(day.advanceReceived, Money.zero);
      expect(bill.lines.single.productId, customCake);
      expect(bill.lines.single.qty, 1);
    });

    test('taken and delivered while still offline: the queue keeps the order '
        'first, so both batches are accepted', () {
      d1.goOffline();
      final o = d1.takeOrder(
        at: morningOf('2026-09-26'),
        dueDate: '2026-09-26',
      );
      d1.deliver(o.id, morningOf('2026-09-26').add(const Duration(hours: 6)));
      expect(server.orders, isEmpty);
      d1.sync();
      expect(d1.syncErrors, isEmpty);
      expect(server.orders[o.id]!.status, OrderStatus.delivered);
      expect(server.bills, hasLength(1));
    });

    test('delivered from the other phone at the store', () {
      final o = d1.takeOrder(
        at: morningOf('2026-09-25'),
        dueDate: '2026-09-26',
      );
      d2.sync();
      final bill = d2.deliver(o.id, morningOf('2026-09-26'))!;
      expect(bill.id, startsWith('D02-'));
      expect(server.orders[o.id]!.billId, bill.id);
    });

    test('paid in full ahead: the bill is one ADVANCE payment', () {
      final o = d1.takeOrder(
        at: morningOf('2026-09-25'),
        dueDate: '2026-09-26',
        advance: const Money(120000),
      );
      final bill = d1.deliver(o.id, morningOf('2026-09-26'))!;
      expect(bill.payments, hasLength(1));
      expect(bill.payments.single.mode, PaymentMode.advance);
      expect(server.on('2026-09-26').byMode.keys, [PaymentMode.advance]);
    });

    test('no advance: no ADVANCE entry, the whole price paid now', () {
      final o = d1.takeOrder(
        at: morningOf('2026-09-25'),
        dueDate: '2026-09-26',
        advance: Money.zero,
      );
      final bill = d1.deliver(o.id, morningOf('2026-09-26'))!;
      expect(bill.payments.map((p) => p.mode), [PaymentMode.cash]);
      expect(server.on('2026-09-25').advanceReceived, Money.zero);
    });
  });

  group('QA-11 O-2: two phones deliver the same order', () {
    test('both offline: the first to sync makes the bill, the second batch is '
        'rejected whole and shows as a sync error', () {
      final o = d1.takeOrder(
        at: morningOf('2026-09-25'),
        dueDate: '2026-09-26',
      );
      d2.sync();
      d1.goOffline();
      d2.goOffline();
      final b1 = d1.deliver(o.id, morningOf('2026-09-26'))!;
      final b2 = d2.deliver(
        o.id,
        morningOf('2026-09-26').add(const Duration(minutes: 5)),
      )!;
      expect(b1.id, isNot(b2.id));

      d2.sync();
      d1.sync();
      expect(d2.syncErrors, isEmpty);
      expect(d1.syncErrors, ['order is DELIVERED']);
      expect(server.bills.keys, [b2.id], reason: 'one bill, no orphan');
      expect(server.orders[o.id]!.billId, b2.id);

      final day = server.on('2026-09-26');
      expect(day.billCount, 1);
      expect(day.netSales, o.price);
      expect(day.byMode[PaymentMode.advance], o.advance);
      // The phone that lost sees the truth after the sync.
      expect(d1.orders[o.id]!.billId, b2.id);
    });

    test('the second phone online after the first: it sees DELIVERED and '
        'offers no delivery', () {
      final o = d1.takeOrder(
        at: morningOf('2026-09-25'),
        dueDate: '2026-09-26',
      );
      d1.deliver(o.id, morningOf('2026-09-26'));
      d2.sync();
      expect(d2.deliver(o.id, morningOf('2026-09-26')), isNull);
      expect(server.bills, hasLength(1));
    });

    test('a double tap on one phone sends one delivery', () {
      final o = d1.takeOrder(
        at: morningOf('2026-09-25'),
        dueDate: '2026-09-26',
      );
      d1.goOffline();
      expect(d1.deliver(o.id, morningOf('2026-09-26')), isNotNull);
      expect(d1.deliver(o.id, morningOf('2026-09-26')), isNull);
      d1.sync();
      expect(server.bills, hasLength(1));
      expect(d1.syncErrors, isEmpty);
    });
  });

  group('QA-11 O-3: cancel with a refund', () {
    for (final (name, refund) in [
      ('the full advance', const Money(50000)),
      ('part of it', const Money(20000)),
      ('none of it', Money.zero),
    ]) {
      test('refunds $name on the cancel day; the shop keeps the rest', () {
        final o = d1.takeOrder(
          at: morningOf('2026-09-24'),
          dueDate: '2026-09-27',
        );
        expect(
          d1.cancel(
            o.id,
            'Customer changed plans',
            refund,
            morningOf('2026-09-25'),
          ),
          isNull,
        );
        final c = server.orders[o.id]!;
        expect(c.status, OrderStatus.cancelled);
        expect(c.cancel!.refunded, refund);
        expect(server.on('2026-09-24').advanceReceived, o.advance);
        expect(server.on('2026-09-25').advanceRefunded, refund);
        expect(server.on('2026-09-24').advanceRefunded, Money.zero);
        expect(server.bills, isEmpty, reason: 'no sale is ever counted');
        expect(o.advance - c.cancel!.refunded, o.advance - refund);
      });
    }

    test('a refund above the advance or below zero is refused on the phone, '
        'and the server refuses it too', () {
      final o = d1.takeOrder(
        at: morningOf('2026-09-24'),
        dueDate: '2026-09-27',
      );
      final at = morningOf('2026-09-25');
      expect(d1.cancel(o.id, 'x', const Money(50100), at), isNotNull);
      expect(d1.cancel(o.id, 'x', const Money(-100), at), isNotNull);
      expect(server.orders[o.id]!.status, OrderStatus.open);
      expect(
        server.apply(CancelOrder(o.id, cancelOf('x', const Money(60000), at))),
        'refund outside 0 to the advance',
      );
      expect(
        server.apply(CancelOrder(o.id, cancelOf(' ', Money.zero, at))),
        'no reason',
      );
    });

    test('offline: a cancel on one phone and a delivery on the other; '
        'whichever syncs first stands, the other is rejected', () {
      final o = d1.takeOrder(
        at: morningOf('2026-09-24'),
        dueDate: '2026-09-26',
      );
      d2.sync();
      d1.goOffline();
      d2.goOffline();
      d1.cancel(
        o.id,
        'Ordered twice',
        const Money(50000),
        morningOf('2026-09-26'),
      );
      d2.deliver(o.id, morningOf('2026-09-26'));

      d1.sync();
      d2.sync();
      expect(server.orders[o.id]!.status, OrderStatus.cancelled);
      expect(server.bills, isEmpty);
      expect(d2.syncErrors, ['order is CANCELLED']);
      expect(server.on('2026-09-26').advanceRefunded, o.advance);
      expect(server.on('2026-09-26').netSales, Money.zero);
    });

    test('a delivered order cannot be cancelled', () {
      final o = d1.takeOrder(
        at: morningOf('2026-09-24'),
        dueDate: '2026-09-26',
      );
      d1.deliver(o.id, morningOf('2026-09-26'));
      expect(
        d1.cancel(o.id, 'late', Money.zero, morningOf('2026-09-26')),
        'not open here',
      );
      expect(
        server.apply(
          CancelOrder(
            o.id,
            cancelOf('late', Money.zero, morningOf('2026-09-26')),
          ),
        ),
        'order is DELIVERED',
      );
    });
  });

  group('QA-11 O-4: the delivery bill cannot be cancelled, only returned', () {
    test('cancelBlocker says deliversOrder on the same day, and the server '
        'rejects the cancel batch', () {
      final o = d1.takeOrder(
        at: morningOf('2026-09-24'),
        dueDate: '2026-09-26',
      );
      final bill = d1.deliver(o.id, morningOf('2026-09-26'))!;
      expect(cancelBlocker(bill, '2026-09-26'), CancelBlocker.deliversOrder);
      final cancel = BillCancel(
        reason: 'Wrong cake',
        by: manager.uid,
        at: morningOf('2026-09-26'),
        businessDate: '2026-09-26',
      );
      expect(
        server.apply(CancelBill(bill.id, cancel)),
        'bill delivers an order',
      );
      expect(server.on('2026-09-26').cancelCount, 0);
    });

    test('an ordinary bill of the same day still cancels', () {
      final t = BillCalculator.compute([
        CartLine(
          productId: 'P1',
          name: 'Puff',
          qty: 1,
          unitPrice: const Money(2000),
        ),
      ]);
      final plain = Bill(
        id: 'D01-000009',
        billNo: 'PTB-D01-000009',
        deviceId: 'D01',
        seq: 9,
        lines: t.lines,
        subtotal: t.subtotal,
        taxableValue: t.taxableValue,
        roundOff: t.roundOff,
        total: t.total,
        payments: [Payment(mode: PaymentMode.cash, amount: t.total)],
        status: BillStatus.completed,
        servedBy: manager,
        businessDate: '2026-09-26',
        clientCreatedAt: morningOf('2026-09-26'),
        createdBy: manager.uid,
      );
      expect(cancelBlocker(plain, '2026-09-26'), isNull);
    });
  });

  group('QA-11 O-5: the IST day boundary', () {
    test('an order at 23:59:59 IST is that day; a delivery a second after '
        'midnight is the next', () {
      final o = d1.takeOrder(at: lastSecondOf26, dueDate: '2026-09-27');
      expect(o.businessDate, '2026-09-26');
      final bill = d1.deliver(o.id, midnightInto27)!;
      expect(bill.businessDate, '2026-09-27');
      expect(server.on('2026-09-26').advanceReceived, o.advance);
      expect(server.on('2026-09-26').netSales, Money.zero);
      expect(server.on('2026-09-27').netSales, o.price);
      expect(server.on('2026-09-27').advanceReceived, Money.zero);
    });

    test('taken offline before midnight and synced after: the order keeps '
        'its own day, not the sync day', () {
      d1.goOffline();
      final o = d1.takeOrder(at: lastSecondOf26, dueDate: '2026-09-28');
      d1.sync();
      expect(server.orders[o.id]!.businessDate, '2026-09-26');
      expect(server.on('2026-09-26').advanceReceived, o.advance);
      expect(server.on('2026-09-27').advanceReceived, Money.zero);
    });

    test('a cancel just after midnight refunds on the new day', () {
      final o = d1.takeOrder(at: lastSecondOf26, dueDate: '2026-09-28');
      d1.cancel(o.id, 'Not needed', const Money(50000), midnightInto27);
      expect(server.on('2026-09-26').advanceRefunded, Money.zero);
      expect(server.on('2026-09-27').advanceRefunded, o.advance);
    });

    test('the reminder buckets turn over at IST midnight, not UTC', () {
      String today(DateTime at) => BusinessDate.of(at);
      final before = today(lastSecondOf26);
      final after = today(midnightInto27);
      expect(OrderValidator.dueState('2026-09-27', before), OrderDue.tomorrow);
      expect(OrderValidator.dueState('2026-09-27', after), OrderDue.today);
      expect(OrderValidator.dueState('2026-09-26', after), OrderDue.overdue);
      expect(OrderValidator.dueState('2026-09-29', after), OrderDue.later);
      // 05:29 UTC on the 27th is still the 27th in IST; 18:30 UTC is the 28th.
      expect(today(DateTime.utc(2026, 9, 27, 5, 29)), '2026-09-27');
      expect(today(DateTime.utc(2026, 9, 27, 18, 30)), '2026-09-28');
    });

    test('a due date before today is refused when taking an order', () {
      expect(
        OrderValidator.dueDateError('2026-09-26', '2026-09-27'),
        isNotNull,
      );
      expect(OrderValidator.dueDateError('2026-09-27', '2026-09-27'), isNull);
    });
  });

  group('QA-11 O-6: permissions per role (seeded roles, 04 role matrix)', () {
    test(
      'the Store Manager has order.manage; the rules scope it to the store',
      () {
        expect(
          SeedRoles.storeManagerPermissions,
          contains(Permission.orderManage),
        );
        expect(SeedRoles.adminPermissions, contains(Permission.orderManage));
        expect(SeedRoles.adminPermissions, contains(Permission.reportAll));
        // Store scope, the all-stores query, another store, a disabled user and
        // a role without the permission: firebase/test/orders.test.js
        // ("denies another store, a role without order.manage ...", "denies the
        // all-stores query to a Store Manager").
      },
    );

    test('only catalog.manage can make CUSTOM-CAKE open-priced, and the '
        'Store Manager does not have it', () {
      expect(
        SeedRoles.storeManagerPermissions,
        isNot(contains(Permission.catalogManage)),
      );
      expect(SeedRoles.adminPermissions, contains(Permission.catalogManage));
    });
  });

  group('QA-11 O-7: advance totals match the orders', () {
    // A fixed seed, like P-01: three phones over five days taking, delivering
    // and cancelling orders, going offline and syncing at random.
    for (final seed in [1, 7, 42, 2026]) {
      test('seed $seed', () {
        final rnd = Random(seed);
        final s = OrderServer();
        final phones = [
          for (final id in ['D01', 'D02', 'D03']) Device(id, s),
        ];
        const days = [
          '2026-09-22',
          '2026-09-23',
          '2026-09-24',
          '2026-09-25',
          '2026-09-26',
        ];
        for (final day in days) {
          final start = BusinessDate.startOf(day);
          for (var step = 0; step < 40; step++) {
            final at = start.add(Duration(minutes: 10 + step * 35));
            final p = phones[rnd.nextInt(phones.length)];
            switch (rnd.nextInt(10)) {
              case 0:
                p.goOffline();
              case 1:
                p.sync();
              case 2 || 3 || 4:
                final price = Money.rupees(300 + rnd.nextInt(30) * 50);
                final advance = Money.rupees(
                  rnd.nextBool() ? 0 : rnd.nextInt(price.paise ~/ 100 + 1),
                );
                p.takeOrder(
                  at: at,
                  dueDate: BusinessDate.addDays(day, rnd.nextInt(4)),
                  price: price,
                  advance: advance,
                );
              case 5 || 6 || 7:
                final open = [
                  for (final o in p.orders.values)
                    if (o.status == OrderStatus.open) o,
                ];
                if (open.isEmpty) break;
                p.deliver(open[rnd.nextInt(open.length)].id, at);
              default:
                final open = [
                  for (final o in p.orders.values)
                    if (o.status == OrderStatus.open) o,
                ];
                if (open.isEmpty) break;
                final o = open[rnd.nextInt(open.length)];
                final refund = Money.rupees(
                  rnd.nextInt(o.advance.paise ~/ 100 + 1),
                );
                p.cancel(o.id, 'Changed plans', refund, at);
            }
          }
        }
        for (final p in phones) {
          p.sync();
        }

        final orders = s.orders.values.toList();
        // The run must exercise what it checks: deliveries, cancellations
        // and offline conflicts the server turned away.
        expect(s.bills, isNotEmpty);
        expect(
          orders.where((o) => o.status == OrderStatus.cancelled),
          isNotEmpty,
        );
        expect(phones.expand((p) => p.syncErrors), isNotEmpty);

        // Every DELIVERED order has exactly one bill, and every delivery
        // bill names a DELIVERED order that points back at it.
        final billsByOrder = <String, List<Bill>>{};
        for (final b in s.bills.values) {
          (billsByOrder[b.orderId!] ??= []).add(b);
        }
        for (final o in orders) {
          final mine = billsByOrder[o.id] ?? const <Bill>[];
          if (o.status == OrderStatus.delivered) {
            expect(mine, hasLength(1), reason: o.id);
            expect(o.billId, mine.single.id);
          } else {
            expect(mine, isEmpty, reason: o.id);
          }
          if (o.cancel case final c?) {
            expect(c.refunded <= o.advance, isTrue);
          }
        }

        final allDays = {...days, ...s.daily.keys};
        for (final day in allDays) {
          final sum0 = s.on(day);
          expect(
            sum0.advanceReceived,
            sum([
              for (final o in orders)
                if (o.businessDate == day) o.advance,
            ]),
            reason: 'advanceReceived on $day',
          );
          expect(
            sum0.advanceRefunded,
            sum([
              for (final o in orders)
                if (o.cancel?.businessDate == day) o.cancel!.refunded,
            ]),
            reason: 'advanceRefunded on $day',
          );
          final delivered = [
            for (final b in s.bills.values)
              if (b.businessDate == day) s.orders[b.orderId]!,
          ];
          expect(
            sum0.byMode[PaymentMode.advance] ?? Money.zero,
            sum(delivered.map((o) => o.advance)),
            reason: 'ADVANCE on the delivery bills of $day',
          );
          expect(
            sum0.netSales,
            sum(delivered.map((o) => o.price)),
            reason: 'sales on $day are the delivered orders',
          );
        }

        // What the shop still holds: advances of open orders plus what it
        // kept from cancelled ones equals received − refunded − credited.
        final total = s.daily.values.fold(const Summary(), (a, b) => a + b);
        final held = sum([
          for (final o in orders)
            if (o.status == OrderStatus.open)
              o.advance
            else if (o.status == OrderStatus.cancelled)
              o.advance - o.cancel!.refunded,
        ]);
        expect(
          total.advanceReceived -
              total.advanceRefunded -
              (total.byMode[PaymentMode.advance] ?? Money.zero),
          held,
        );
      });
    }
  });
}
