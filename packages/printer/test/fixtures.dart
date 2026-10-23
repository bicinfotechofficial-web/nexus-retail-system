import 'dart:typed_data';

import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_printer/nexus_printer.dart';

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

/// A GST bill, for when GST is switched on (D-013). Built by hand because
/// the calculator has no GST yet; it follows 02-DATA-MODEL:
/// `total = taxableValue + Σtax + roundOff`, here
/// ₹850.00 + ₹21.25 + ₹21.25 + ₹0.50 = ₹893 (QA-036).
Bill gstBill() {
  final t = BillCalculator.compute([blackForest1kg]);
  const cgst = Money(2125);
  const sgst = Money(2125);
  final beforeRounding = t.taxableValue + cgst + sgst;
  final total = beforeRounding.roundToRupee();
  return _bill(
    BillTotals(
      lines: t.lines,
      subtotal: t.subtotal,
      discount: t.discount,
      taxableValue: t.taxableValue,
      taxLines: [
        TaxLine(rate: 5, taxable: t.taxableValue, cgst: cgst, sgst: sgst),
      ],
      roundOff: total - beforeRounding,
      total: total,
    ),
    seq: 125,
    payments: [Payment(mode: PaymentMode.card, amount: total)],
  );
}

/// [pilotLocation] once it is GST-registered.
const Location gstLocation = Location(
  code: 'PTB',
  name: 'Caramel Cottage',
  address: '12 Baker Street, Pattambi, Palakkad 679303',
  phone: '+91 98470 00000',
  gstin: '32ABCDE1234F1Z5',
  overridePinHash: 'c2FsdA==\$aGFzaA==',
  receiptFooter: 'Thank you! Visit caramelcottage.in',
  nextDeviceNo: 2,
  active: true,
);

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

/// A bill that delivers an order (D-043): one custom-cake line, an ADVANCE
/// payment of the advance, and the balance paid in cash with change.
Bill deliveryBill() {
  const cake = CartLine(
    productId: 'CUSTOM-CAKE',
    name: 'Custom Cake',
    qty: 1,
    unitPrice: Money.rupees(2400),
  );
  final t = BillCalculator.compute([cake]);
  const advance = Money.rupees(1000);
  return _bill(
    t,
    seq: 126,
    payments: [
      const Payment(mode: PaymentMode.advance, amount: advance),
      Payment(mode: PaymentMode.cash, amount: t.total - advance),
    ],
    cashTendered: const Money.rupees(1500),
  );
}

/// 2026-10-23 16:20 IST.
final DateTime orderTime = DateTime.utc(2026, 10, 23, 10, 50);

PreOrder _order({
  required int seq,
  required String description,
  required Money price,
  required Money advance,
  PaymentMode? advanceMode,
  String dueDate = '2026-10-26',
  String? dueTime,
}) {
  final id = Ids.orderId('D01', seq);
  return PreOrder(
    id: id,
    orderNo: Ids.orderNo(pilotLocation.code, id),
    deviceId: 'D01',
    seq: seq,
    customer: BillCustomer(
      name: 'Anita Menon',
      phone: '9847012345',
      whatsapp: '9847012345',
    ),
    dueDate: dueDate,
    dueTime: dueTime,
    description: description,
    price: price,
    advance: advance,
    advanceMode: advanceMode,
    status: OrderStatus.open,
    servedBy: storeManager,
    businessDate: BusinessDate.of(orderTime),
    clientCreatedAt: orderTime,
    createdBy: storeManager.uid,
  );
}

/// Short description, UPI advance, a due time.
PreOrder normalOrder() => _order(
  seq: 7,
  description: 'Chocolate truffle, 2 kg, 2 layers. "Happy Birthday Riya"',
  price: const Money.rupees(2400),
  advance: const Money.rupees(1000),
  advanceMode: PaymentMode.upi,
  dueTime: '16:30',
);

/// A long description with line breaks, a cash advance, no due time.
PreOrder longDescriptionOrder() => _order(
  seq: 8,
  description:
      'Three tier wedding cake, vanilla sponge with strawberry filling and '
      'white chocolate ganache, about 5 kg.\n'
      'Message on top tier: "Rahul & Meera, 12-11-2026".\n'
      'Eggless. Fondant flowers in pale pink. No nuts, one guest is allergic.',
  price: const Money.rupees(7500),
  advance: const Money.rupees(2500),
  advanceMode: PaymentMode.cash,
  dueDate: '2026-11-12',
);

/// No advance taken: advance 0 and no mode.
PreOrder noAdvanceOrder() => _order(
  seq: 9,
  description: 'Pineapple cake, 1 kg',
  price: const Money.rupees(900),
  advance: Money.zero,
  dueTime: '09:00',
);

/// A synthetic brand logo drawn in code: a 800 x 300 image with a
/// transparent background, a brown disc shaded from light to dark, and a
/// dark bar with a gradient under it. It is not a real brand logo.
LogoBitmap syntheticLogo({int width = 800, int height = 300}) {
  final rgba = Uint8List(width * height * 4);
  final cx = width * 0.3;
  final cy = height * 0.5;
  final r = height * 0.42;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 4;
      final dx = x - cx;
      final dy = y - cy;
      final inDisc = dx * dx + dy * dy <= r * r;
      final inBar =
          x >= width * 0.55 &&
          x <= width * 0.95 &&
          y >= height * 0.4 &&
          y <= height * 0.6;
      if (inDisc) {
        final shade = (dx + r) / (2 * r); // 0 on the left, 1 on the right
        rgba[i] = (200 - 120 * shade).round();
        rgba[i + 1] = (120 - 80 * shade).round();
        rgba[i + 2] = (60 - 40 * shade).round();
        rgba[i + 3] = 255;
      } else if (inBar) {
        final g = 30 + ((x - width * 0.55) / (width * 0.4) * 150).round();
        rgba[i] = g;
        rgba[i + 1] = g;
        rgba[i + 2] = g;
        rgba[i + 3] = 255;
      }
    }
  }
  return LogoBitmap(width: width, height: height, rgba: rgba);
}

/// A [ReceiptLogo] that returns [bitmap].
final class FakeReceiptLogo implements ReceiptLogo {
  FakeReceiptLogo(this.bitmap);
  final LogoBitmap? bitmap;
  int loads = 0;

  @override
  Future<LogoBitmap?> load() async {
    loads++;
    return bitmap;
  }
}

/// A [ReceiptLogo] whose load throws, which a good logo never does.
final class ThrowingReceiptLogo implements ReceiptLogo {
  @override
  Future<LogoBitmap?> load() => throw StateError('decode failed');
}
