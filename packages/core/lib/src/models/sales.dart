import '../enums.dart';
import '../map_reader.dart';
import '../money.dart';

/// `locations/{loc}/bills/{billId}`. Never edited, except the cancellation
/// and `returnedQty` updates the rules allow (D-009).
final class Bill {
  const Bill({
    required this.id,
    required this.billNo,
    required this.deviceId,
    required this.seq,
    required this.lines,
    required this.subtotal,
    required this.taxableValue,
    required this.roundOff,
    required this.total,
    required this.payments,
    required this.status,
    required this.servedBy,
    required this.businessDate,
    required this.clientCreatedAt,
    required this.createdBy,
    this.discount,
    this.taxLines = const [],
    this.cashTendered,
    this.cancel,
    this.returnedQty = const {},
    this.lastReturnId,
    this.serverCreatedAt,
  });

  factory Bill.fromMap(String id, Map<String, Object?> map) {
    final r = MapReader(map, 'bill $id');
    final tendered = r.integerOrNull('cashTendered');
    return Bill(
      id: id,
      billNo: r.string('billNo'),
      deviceId: r.string('deviceId'),
      seq: r.integer('seq'),
      lines: r.objects('lines', BillLine.fromReader),
      subtotal: Money(r.integer('subtotal')),
      discount: switch (r.childOrNull('discount')) {
        final d? => Discount.fromReader(d),
        null => null,
      },
      taxableValue: Money(r.integer('taxableValue')),
      taxLines: r.objects('taxLines', TaxLine.fromReader),
      roundOff: Money(r.integer('roundOff')),
      total: Money(r.integer('total')),
      payments: r.objects('payments', Payment.fromReader),
      cashTendered: tendered == null ? null : Money(tendered),
      status: r.enumValue('status', BillStatus.fromWire),
      cancel: switch (r.childOrNull('cancel')) {
        final c? => BillCancel.fromReader(c),
        null => null,
      },
      returnedQty: r.intMap('returnedQty'),
      lastReturnId: r.stringOrNull('lastReturnId'),
      servedBy: ServedBy.fromReader(r.child('servedBy')),
      businessDate: r.string('businessDate'),
      clientCreatedAt: r.dateTime('clientCreatedAt'),
      serverCreatedAt: r.dateTimeOrNull('serverCreatedAt'),
      createdBy: r.string('createdBy'),
    );
  }

  static const Set<String> serverTimestampFields = {'serverCreatedAt'};

  /// `D01-000123`.
  final String id;

  /// `PTB-D01-000123`.
  final String billNo;
  final String deviceId;
  final int seq;
  final List<BillLine> lines;

  /// Σ lineTotal.
  final Money subtotal;
  final Discount? discount;

  /// subtotal − discount.
  final Money taxableValue;

  /// Empty in the MVP (D-013).
  final List<TaxLine> taxLines;

  /// May be negative.
  final Money roundOff;

  /// Always whole rupees.
  final Money total;
  final List<Payment> payments;
  final Money? cashTendered;
  final BillStatus status;
  final BillCancel? cancel;

  /// productId → qty returned so far. Only returns write it, and never a 0.
  final Map<String, int> returnedQty;

  /// The return that last raised [returnedQty], written in the same batch;
  /// the rules require it to be a new return doc (04-PERMISSIONS #5).
  final String? lastReturnId;
  final ServedBy servedBy;
  final String businessDate;
  final DateTime clientCreatedAt;
  final DateTime? serverCreatedAt;
  final String createdBy;

  Money get discountAmount => discount?.amount ?? Money.zero;

  /// productId → qty sold. Written with the bill so the rules can cap
  /// `returnedQty` without looping over `lines` (04-PERMISSIONS #5, D-029).
  Map<String, int> get soldQty => {for (final l in lines) l.productId: l.qty};

  Map<String, Object?> toMap() => {
    'billNo': billNo,
    'deviceId': deviceId,
    'seq': seq,
    'lines': lines.map((l) => l.toMap()).toList(),
    'subtotal': subtotal.paise,
    'discount': discount?.toMap(),
    'taxableValue': taxableValue.paise,
    'taxLines': taxLines.map((t) => t.toMap()).toList(),
    'roundOff': roundOff.paise,
    'total': total.paise,
    'payments': payments.map((p) => p.toMap()).toList(),
    'cashTendered': cashTendered?.paise,
    'status': status.wire,
    'cancel': cancel?.toMap(),
    'returnedQty': returnedQty,
    'soldQty': soldQty,
    'lastReturnId': lastReturnId,
    'servedBy': servedBy.toMap(),
    'businessDate': businessDate,
    'clientCreatedAt': clientCreatedAt,
    'createdBy': createdBy,
  };
}

final class BillLine {
  const BillLine({
    required this.productId,
    required this.name,
    required this.qty,
    required this.unitPrice,
    required this.lineTotal,
  });

  factory BillLine.fromReader(MapReader r) => BillLine(
    productId: r.string('productId'),
    name: r.string('name'),
    qty: r.integer('qty'),
    unitPrice: Money(r.integer('unitPrice')),
    lineTotal: Money(r.integer('lineTotal')),
  );

  final String productId;

  /// Copied at the time of sale.
  final String name;
  final int qty;

  /// Copied at the time of sale.
  final Money unitPrice;
  final Money lineTotal;

  Map<String, Object?> toMap() => {
    'productId': productId,
    'name': name,
    'qty': qty,
    'unitPrice': unitPrice.paise,
    'lineTotal': lineTotal.paise,
  };
}

final class Discount {
  const Discount({
    required this.type,
    required this.value,
    required this.amount,
  });

  factory Discount.fromReader(MapReader r) => Discount(
    type: r.enumValue('type', DiscountType.fromWire),
    value: r.integer('value'),
    amount: Money(r.integer('amount')),
  );

  final DiscountType type;

  /// Paise for FLAT, a whole percentage for PCT.
  final int value;

  /// The paise actually taken off.
  final Money amount;

  Map<String, Object?> toMap() => {
    'type': type.wire,
    'value': value,
    'amount': amount.paise,
  };
}

/// Reserved for GST (D-013).
final class TaxLine {
  const TaxLine({
    required this.rate,
    required this.taxable,
    required this.cgst,
    required this.sgst,
  });

  factory TaxLine.fromReader(MapReader r) => TaxLine(
    rate: r.integer('rate'),
    taxable: Money(r.integer('taxable')),
    cgst: Money(r.integer('cgst')),
    sgst: Money(r.integer('sgst')),
  );

  final int rate;
  final Money taxable;
  final Money cgst;
  final Money sgst;

  Money get tax => cgst + sgst;

  Map<String, Object?> toMap() => {
    'rate': rate,
    'taxable': taxable.paise,
    'cgst': cgst.paise,
    'sgst': sgst.paise,
  };
}

/// A bill payment or a return refund.
final class Payment {
  const Payment({required this.mode, required this.amount, this.ref});

  factory Payment.fromReader(MapReader r) => Payment(
    mode: r.enumValue('mode', PaymentMode.fromWire),
    amount: Money(r.integer('amount')),
    ref: r.stringOrNull('ref'),
  );

  final PaymentMode mode;
  final Money amount;

  /// e.g. a UPI transaction reference.
  final String? ref;

  Map<String, Object?> toMap() => {
    'mode': mode.wire,
    'amount': amount.paise,
    if (ref != null) 'ref': ref,
  };
}

final class BillCancel {
  const BillCancel({
    required this.reason,
    required this.by,
    required this.at,
    required this.businessDate,
  });

  factory BillCancel.fromReader(MapReader r) => BillCancel(
    reason: r.string('reason'),
    by: r.string('by'),
    at: r.dateTime('at'),
    businessDate: r.string('businessDate'),
  );

  final String reason;
  final String by;
  final DateTime at;

  /// Must equal the bill's own business date (D-009).
  final String businessDate;

  Map<String, Object?> toMap() => {
    'reason': reason,
    'by': by,
    'at': at,
    'businessDate': businessDate,
  };
}

final class ServedBy {
  const ServedBy({required this.uid, required this.name});

  factory ServedBy.fromReader(MapReader r) =>
      ServedBy(uid: r.string('uid'), name: r.string('name'));

  final String uid;
  final String name;

  Map<String, Object?> toMap() => {'uid': uid, 'name': name};
}

/// `locations/{loc}/returns/{returnId}`. Named to avoid the `return`
/// keyword.
final class SaleReturn {
  const SaleReturn({
    required this.id,
    required this.billId,
    required this.billNo,
    required this.lines,
    required this.refundTotal,
    required this.refunds,
    required this.reason,
    required this.businessDate,
    required this.createdBy,
    required this.deviceId,
    required this.clientCreatedAt,
    this.prevReturnId,
    this.serverCreatedAt,
  });

  factory SaleReturn.fromMap(String id, Map<String, Object?> map) {
    final r = MapReader(map, 'return $id');
    return SaleReturn(
      id: id,
      billId: r.string('billId'),
      billNo: r.string('billNo'),
      lines: r.objects('lines', ReturnLine.fromReader),
      refundTotal: Money(r.integer('refundTotal')),
      refunds: r.objects('refunds', Payment.fromReader),
      reason: r.string('reason'),
      businessDate: r.string('businessDate'),
      createdBy: r.string('createdBy'),
      deviceId: r.string('deviceId'),
      clientCreatedAt: r.dateTime('clientCreatedAt'),
      prevReturnId: r.stringOrNull('prevReturnId'),
      serverCreatedAt: r.dateTimeOrNull('serverCreatedAt'),
    );
  }

  static const Set<String> serverTimestampFields = {'serverCreatedAt'};

  final String id;
  final String billId;
  final String billNo;
  final List<ReturnLine> lines;

  /// Whole rupees.
  final Money refundTotal;
  final List<Payment> refunds;
  final String reason;

  /// The bill's `lastReturnId` when this return was worked out, or null for
  /// the first return. The rules reject the return if the bill has had
  /// another return since, because its refund was computed from an out of
  /// date `returnedQty` (D-029, QA-024).
  final String? prevReturnId;

  /// The day the return is processed (D-012).
  final String businessDate;
  final String createdBy;
  final String deviceId;
  final DateTime clientCreatedAt;
  final DateTime? serverCreatedAt;

  Map<String, Object?> toMap() => {
    'billId': billId,
    'billNo': billNo,
    'lines': lines.map((l) => l.toMap()).toList(),
    'refundTotal': refundTotal.paise,
    'refunds': refunds.map((p) => p.toMap()).toList(),
    'reason': reason,
    'prevReturnId': prevReturnId,
    'businessDate': businessDate,
    'createdBy': createdBy,
    'deviceId': deviceId,
    'clientCreatedAt': clientCreatedAt,
  };
}

final class ReturnLine {
  const ReturnLine({
    required this.productId,
    required this.name,
    required this.qty,
    required this.amount,
  });

  factory ReturnLine.fromReader(MapReader r) => ReturnLine(
    productId: r.string('productId'),
    name: r.string('name'),
    qty: r.integer('qty'),
    amount: Money(r.integer('amount')),
  );

  final String productId;
  final String name;
  final int qty;

  /// This line's prorated share of the bill's net amount (D-024).
  final Money amount;

  Map<String, Object?> toMap() => {
    'productId': productId,
    'name': name,
    'qty': qty,
    'amount': amount.paise,
  };
}
