import 'package:nexus_core/nexus_core.dart';

/// Receipt fixtures shared by the model, layout and golden tests. Totals
/// come from the core calculators, so they match what the POS saves.

/// 2026-09-25 14:35 IST.
final DateTime billTime = DateTime.utc(2026, 9, 25, 9, 5);

/// 2026-09-26 11:02 IST, the day after [billTime] (D-012).
final DateTime returnTime = DateTime.utc(2026, 9, 26, 5, 32);

const Location pilotLocation = Location(
  code: 'PTB',
  name: 'Caramel Cottage',
  address: '12 Baker Street, Pattambi, Palakkad 679303',
  phone: '+91 98470 00000',
  overridePinHash: 'c2FsdA==\$aGFzaA==',
  receiptFooter: 'Thank you! Visit caramelcottage.in',
  nextDeviceNo: 2,
  active: true,
);

const ServedBy storeManager = ServedBy(uid: 'sm-1', name: 'Store Manager');

const CartLine blackForest1kg = CartLine(
  productId: 'p-bf-1kg',
  name: 'Black Forest 1 kg',
  qty: 1,
  unitPrice: Money.rupees(850),
);

const CartLine redVelvetJar = CartLine(
  productId: 'p-rv-jar',
  name: 'Red Velvet Jar Cake with Cream Cheese Frosting',
  qty: 2,
  unitPrice: Money(14950),
);

const CartLine plumCake = CartLine(
  productId: 'p-plum-500',
  name: 'Plum Cake 500 g',
  qty: 3,
  unitPrice: Money(24999),
);

Bill _bill(
  BillTotals t, {
  required int seq,
  required List<Payment> payments,
  Money? cashTendered,
  List<TaxLine>? taxLines,
  BillStatus status = BillStatus.completed,
  BillCancel? cancel,
}) {
  final id = Ids.billId('D01', seq);
  return Bill(
    id: id,
    billNo: Ids.billNo(pilotLocation.code, id),
    deviceId: 'D01',
    seq: seq,
    lines: t.lines,
    subtotal: t.subtotal,
    discount: t.discount,
    taxableValue: t.taxableValue,
    taxLines: taxLines ?? t.taxLines,
    roundOff: t.roundOff,
    total: t.total,
    payments: payments,
    cashTendered: cashTendered,
    status: status,
    cancel: cancel,
    servedBy: storeManager,
    businessDate: BusinessDate.of(billTime),
    clientCreatedAt: billTime,
    createdBy: storeManager.uid,
  );
}

/// Two lines, no discount, paid in cash with change.
Bill normalBill() {
  final t = BillCalculator.compute([blackForest1kg, redVelvetJar]);
  return _bill(
    t,
    seq: 123,
    payments: [Payment(mode: PaymentMode.cash, amount: t.total)],
    cashTendered: const Money.rupees(1200),
  );
}

/// 10% off, a non-zero round-off, split across UPI and cash.
Bill discountedSplitBill() {
  final t = BillCalculator.compute([
    blackForest1kg,
    redVelvetJar,
    plumCake,
  ], discount: const DiscountInput.percent(10));
  const upi = Money.rupees(1000);
  return _bill(
    t,
    seq: 124,
    payments: [
      const Payment(mode: PaymentMode.upi, amount: upi, ref: '426912345678'),
      Payment(mode: PaymentMode.cash, amount: t.total - upi),
    ],
    cashTendered: t.total - upi + const Money.rupees(50),
  );
}

/// [normalBill], cancelled the same day (D-009).
Bill cancelledBill() {
  final b = normalBill();
  return _bill(
    BillCalculator.compute([blackForest1kg, redVelvetJar]),
    seq: b.seq,
    payments: b.payments,
    cashTendered: b.cashTendered,
    status: BillStatus.cancelled,
    cancel: BillCancel(
      reason: 'Wrong item billed',
      by: storeManager.uid,
      at: billTime.add(const Duration(minutes: 10)),
      businessDate: b.businessDate,
    ),
  );
}

/// [normalBill] with a GST breakup, for when GST is switched on (D-013).
Bill gstBill() {
  final t = BillCalculator.compute([blackForest1kg]);
  return _bill(
    t,
    seq: 125,
    payments: [Payment(mode: PaymentMode.card, amount: t.total)],
    taxLines: [
      TaxLine(
        rate: 5,
        taxable: t.taxableValue,
        cgst: const Money(2125),
        sgst: const Money(2125),
      ),
    ],
  );
}

/// One Plum Cake and one Red Velvet Jar back from [discountedSplitBill].
SaleReturn partialReturn(Bill bill) {
  final t = ReturnCalculator.compute(bill, {
    plumCake.productId: 1,
    redVelvetJar.productId: 1,
  });
  return SaleReturn(
    id: Ids.returnId('D01', 7),
    billId: bill.id,
    billNo: bill.billNo,
    lines: t.lines,
    refundTotal: t.refundTotal,
    refunds: [Payment(mode: PaymentMode.cash, amount: t.refundTotal)],
    reason: 'Damaged in transit',
    businessDate: BusinessDate.of(returnTime),
    createdBy: storeManager.uid,
    deviceId: 'D01',
    clientCreatedAt: returnTime,
  );
}
