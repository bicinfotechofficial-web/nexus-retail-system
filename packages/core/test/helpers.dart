import 'package:nexus_core/nexus_core.dart';

final DateTime t0 = DateTime.utc(2026, 9, 25, 6);

/// Builds a saved bill from calculator output, as the data layer would.
Bill billFrom(
  BillTotals t, {
  List<Payment>? payments,
  Map<String, int> returnedQty = const {},
  BillStatus status = BillStatus.completed,
  String businessDate = '2026-09-25',
  int seq = 1,
}) {
  final id = Ids.billId('D01', seq);
  return Bill(
    id: id,
    billNo: Ids.billNo('PTB', id),
    deviceId: 'D01',
    seq: seq,
    lines: t.lines,
    subtotal: t.subtotal,
    discount: t.discount,
    taxableValue: t.taxableValue,
    taxLines: t.taxLines,
    roundOff: t.roundOff,
    total: t.total,
    payments: payments ?? [Payment(mode: PaymentMode.cash, amount: t.total)],
    status: status,
    returnedQty: returnedQty,
    servedBy: const ServedBy(uid: 'u1', name: 'SM'),
    businessDate: businessDate,
    clientCreatedAt: t0,
    createdBy: 'u1',
  );
}

CartLine line(String id, int qty, int pricePaise) => CartLine(
  productId: id,
  name: 'Item $id',
  qty: qty,
  unitPrice: Money(pricePaise),
);

/// A copy of [b] with more returned.
Bill withReturned(Bill b, Map<String, int> more) => billFrom(
  BillTotals(
    lines: b.lines,
    subtotal: b.subtotal,
    discount: b.discount,
    taxableValue: b.taxableValue,
    taxLines: b.taxLines,
    roundOff: b.roundOff,
    total: b.total,
  ),
  payments: b.payments,
  returnedQty: {
    for (final k in {...b.returnedQty.keys, ...more.keys})
      k: (b.returnedQty[k] ?? 0) + (more[k] ?? 0),
  },
  status: b.status,
  businessDate: b.businessDate,
  seq: b.seq,
);
