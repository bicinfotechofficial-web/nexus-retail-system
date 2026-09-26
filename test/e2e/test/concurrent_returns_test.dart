/// D-029 conflicts between two offline devices, worked by hand: which batch
/// the rules accept (the model in `ShopSim`, from 04-PERMISSIONS #5), and
/// what that does to the money (D-024 d).
///
/// The last group is QA-024: two stale returns that both stay within
/// `soldQty` are both accepted, and their cumulative rounding was worked
/// out from the same `returnedQty`, so the bill can be refunded more than
/// its total. It is skipped until the contract closes that case.
library;

import 'package:nexus_core/nexus_core.dart';
import 'package:test/test.dart';

import 'support/shop_sim.dart';

const String loc = 'PTB';

/// A ₹5 bill of 3 × ₹1.67: net 501 paise, rounded to 500.
Bill threeUnitBill() {
  final t = BillCalculator.compute([
    CartLine(
      productId: 'P_PUFF',
      name: 'Veg puff',
      qty: 3,
      unitPrice: Money(167),
    ),
  ]);
  return Bill(
    id: 'D01-000001',
    billNo: 'PTB-D01-000001',
    deviceId: 'D01',
    seq: 1,
    lines: t.lines,
    subtotal: t.subtotal,
    taxableValue: t.taxableValue,
    roundOff: t.roundOff,
    total: t.total,
    payments: [Payment(mode: PaymentMode.cash, amount: t.total)],
    status: BillStatus.completed,
    servedBy: const ServedBy(uid: 'uid-sm-ptb', name: 'Store Manager'),
    businessDate: '2026-09-27',
    clientCreatedAt: DateTime.utc(2026, 9, 27, 4),
    createdBy: 'uid-sm-ptb',
  );
}

/// The bill doc after a return of [qty] units with ID [returnId], as the
/// return batch's increments would leave it.
Map<String, Object?> returned(
  Map<String, Object?> doc,
  int qty,
  String returnId,
) {
  final was = (doc['returnedQty']! as Map).cast<String, int>();
  return {
    ...doc,
    'returnedQty': {...was, 'P_PUFF': (was['P_PUFF'] ?? 0) + qty},
    'lastReturnId': returnId,
  };
}

Map<String, Object?> cancelled(Map<String, Object?> doc) => {
  ...doc,
  'status': BillStatus.cancelled.wire,
  'cancel': {
    'reason': 'Customer changed order',
    'by': 'uid-sm-ptb',
    'at': DateTime.utc(2026, 9, 27, 5),
    'businessDate': doc['businessDate'],
  },
};

void main() {
  final bill = threeUnitBill();
  final created = bill.toMap();

  test('the bill itself passes the create rule', () {
    expect(bill.total, Money(500));
    expect(ShopSim.serverAcceptsBillCreate(loc, bill.id, created), isTrue);
  });

  group('cancel vs return, first to sync wins (D-029)', () {
    test('return syncs first: the stale cancel is rejected', () {
      final afterReturn = returned(created, 1, 'D02-R000001');
      expect(
        ShopSim.serverAcceptsReturn(created, afterReturn, newReturn: true),
        isTrue,
      );
      expect(
        ShopSim.serverAcceptsCancel(afterReturn, cancelled(afterReturn)),
        isFalse,
      );
    });

    test('cancel syncs first: the stale return is rejected', () {
      final afterCancel = cancelled(created);
      expect(ShopSim.serverAcceptsCancel(created, afterCancel), isTrue);
      expect(
        ShopSim.serverAcceptsReturn(
          afterCancel,
          returned(afterCancel, 1, 'D02-R000001'),
          newReturn: true,
        ),
        isFalse,
      );
    });

    test('a return that reuses lastReturnId is rejected', () {
      final first = returned(created, 1, 'D02-R000001');
      expect(
        ShopSim.serverAcceptsReturn(
          first,
          returned(first, 1, 'D02-R000001'),
          newReturn: true,
        ),
        isFalse,
      );
    });
  });

  group('stale returns and soldQty (D-029)', () {
    test('a stale return past soldQty is rejected', () {
      final all = returned(created, 3, 'D01-R000001');
      expect(
        ShopSim.serverAcceptsReturn(created, all, newReturn: true),
        isTrue,
      );
      expect(
        ShopSim.serverAcceptsReturn(
          all,
          returned(all, 1, 'D02-R000001'),
          newReturn: true,
        ),
        isFalse,
      );
    });

    test('two stale returns within soldQty are both accepted', () {
      final a = returned(created, 1, 'D01-R000001');
      final b = returned(a, 1, 'D02-R000001');
      expect(ShopSim.serverAcceptsReturn(created, a, newReturn: true), isTrue);
      expect(ShopSim.serverAcceptsReturn(a, b, newReturn: true), isTrue);
    });
  });

  group('QA-024: refunds of stale returns within soldQty', () {
    // Devices A and B both saw returnedQty {} and each returned 1 unit;
    // both sync. A third return of the last unit is then made online.
    final a = ReturnCalculator.compute(bill, {'P_PUFF': 1});
    final b = ReturnCalculator.compute(bill, {'P_PUFF': 1});
    final merged = Bill.fromMap(bill.id, returned(created, 2, 'D02-R000001'));
    final c = ReturnCalculator.compute(merged, {'P_PUFF': 1});
    final refunded = a.refundTotal + b.refundTotal + c.refundTotal;

    test('what happens today: ₹2 + ₹2 + ₹2 on a ₹5 bill', () {
      expect(
        [a.refundTotal, b.refundTotal, c.refundTotal],
        [Money(200), Money(200), Money(200)],
      );
      expect(refunded, Money(600));
    });

    test(
      'a bill is never refunded more than its total (D-024 d)',
      () => expect(refunded <= bill.total, isTrue),
      skip: 'QA-024: stale returns within soldQty over-refund',
    );
  });
}
