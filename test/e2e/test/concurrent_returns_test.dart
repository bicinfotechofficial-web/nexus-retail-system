/// D-029 conflicts between two offline devices, worked by hand: which batch
/// the rules accept (the model in `ShopSim`, from 04-PERMISSIONS #5), and
/// what that does to the money (D-024 d).
///
/// The last group is QA-024: two stale returns that both stay within
/// `soldQty` would each work out their cumulative rounding from the same
/// `returnedQty` and refund the bill more than its total. Rule #5(b) now
/// requires the return's `prevReturnId` to equal the bill's `lastReturnId`
/// (D-029), so the second is rejected and redone from the fresh bill.
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
        ShopSim.serverAcceptsReturn(
          created,
          afterReturn,
          newReturn: true,
          prevReturnId: null,
        ),
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
          prevReturnId: null,
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
          prevReturnId: 'D02-R000001',
        ),
        isFalse,
      );
    });
  });

  group('stale returns and soldQty (D-029)', () {
    test('a return past soldQty is rejected, even when it is not stale', () {
      final all = returned(created, 3, 'D01-R000001');
      expect(
        ShopSim.serverAcceptsReturn(
          created,
          all,
          newReturn: true,
          prevReturnId: null,
        ),
        isTrue,
      );
      expect(
        ShopSim.serverAcceptsReturn(
          all,
          returned(all, 1, 'D02-R000001'),
          newReturn: true,
          prevReturnId: 'D01-R000001',
        ),
        isFalse,
      );
    });

    test('a second return worked out from the current bill is accepted', () {
      final a = returned(created, 1, 'D01-R000001');
      expect(
        ShopSim.serverAcceptsReturn(
          created,
          a,
          newReturn: true,
          prevReturnId: null,
        ),
        isTrue,
      );
      expect(
        ShopSim.serverAcceptsReturn(
          a,
          returned(a, 1, 'D02-R000001'),
          newReturn: true,
          prevReturnId: 'D01-R000001',
        ),
        isTrue,
      );
    });

    test(
      'a stale return within soldQty is rejected (prevReturnId, QA-024)',
      () {
        final a = returned(created, 1, 'D01-R000001');
        // B saw the bill before A's return: its prevReturnId is null.
        expect(
          ShopSim.serverAcceptsReturn(
            a,
            returned(a, 1, 'D02-R000001'),
            newReturn: true,
            prevReturnId: null,
          ),
          isFalse,
        );
      },
    );
  });

  group('QA-024: refunds of two offline returns within soldQty', () {
    // Devices A and B both saw returnedQty {} and each returned 1 unit
    // offline. A syncs first; B's return is rejected (stale prevReturnId),
    // and B redoes it from the bill as the server now holds it. The last
    // unit is then returned online.
    final a = ReturnCalculator.compute(bill, {'P_PUFF': 1});
    final staleB = ReturnCalculator.compute(bill, {'P_PUFF': 1});
    final afterA = returned(created, 1, 'D01-R000001');
    final b = ReturnCalculator.compute(Bill.fromMap(bill.id, afterA), {
      'P_PUFF': 1,
    });
    final afterB = returned(afterA, 1, 'D02-R000002');
    final c = ReturnCalculator.compute(Bill.fromMap(bill.id, afterB), {
      'P_PUFF': 1,
    });

    test('without the prevReturnId rule it would be ₹2 + ₹2 + ₹2', () {
      expect(a.refundTotal, Money(200));
      expect(staleB.refundTotal, Money(200));
    });

    test('the stale return is rejected, the redone one is accepted', () {
      expect(
        ShopSim.serverAcceptsReturn(
          afterA,
          returned(afterA, 1, 'D02-R000001'),
          newReturn: true,
          prevReturnId: null,
        ),
        isFalse,
      );
      expect(
        ShopSim.serverAcceptsReturn(
          afterA,
          afterB,
          newReturn: true,
          prevReturnId: 'D01-R000001',
        ),
        isTrue,
      );
    });

    test('a bill is never refunded more than its total (D-024 d)', () {
      expect(
        [a.refundTotal, b.refundTotal, c.refundTotal],
        [Money(200), Money(100), Money(200)],
      );
      expect(a.refundTotal + b.refundTotal + c.refundTotal, bill.total);
    });
  });
}
