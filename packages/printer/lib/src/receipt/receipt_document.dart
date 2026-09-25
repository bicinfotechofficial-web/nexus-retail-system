import 'package:nexus_core/nexus_core.dart';

/// What a bill receipt says, in print order (BRD §4.1), with no layout.
///
/// Built from a saved [Bill] and its [Location] by [ReceiptDocument.fromBill].
/// The layout engine (PR-2) turns it into lines of text and decides every
/// label, width and alignment; this model decides only *what* appears.
/// Internal to the package: the POS app goes through `PrinterService`.
final class ReceiptDocument {
  const ReceiptDocument({
    required this.header,
    required this.billNo,
    required this.issuedAt,
    required this.lines,
    required this.subtotal,
    required this.roundOff,
    required this.total,
    required this.payments,
    required this.servedBy,
    required this.footer,
    this.reprint = false,
    this.cancellation,
    this.discount,
    this.cashTendered,
    this.change,
    this.gst,
  });

  /// Maps a saved bill to its receipt. Pure: the same bill always gives the
  /// same document.
  ///
  /// [reprint] adds the "REPRINT" marker. A cancelled bill always carries a
  /// [cancellation], whether or not it is a reprint.
  factory ReceiptDocument.fromBill(
    Bill bill,
    Location location, {
    bool reprint = false,
  }) {
    final check = BillCalculator.checkPayments(
      bill.total,
      bill.payments,
      cashTendered: bill.cashTendered,
    );
    return ReceiptDocument(
      header: ReceiptHeader.of(location),
      reprint: reprint,
      cancellation: bill.status == BillStatus.cancelled
          ? ReceiptCancellation(reason: bill.cancel?.reason)
          : null,
      billNo: bill.billNo,
      issuedAt: bill.clientCreatedAt,
      lines: [
        for (final l in bill.lines)
          ReceiptLine(
            name: l.name,
            qty: l.qty,
            unitPrice: l.unitPrice,
            amount: l.lineTotal,
          ),
      ],
      subtotal: bill.subtotal,
      discount: bill.discount,
      roundOff: bill.roundOff,
      total: bill.total,
      payments: List.unmodifiable(bill.payments),
      cashTendered: check.change == null ? null : bill.cashTendered,
      change: check.change,
      gst: bill.taxLines.isEmpty
          ? null
          : GstBlock(
              gstin: location.gstin,
              taxableValue: bill.taxableValue,
              lines: List.unmodifiable(bill.taxLines),
            ),
      servedBy: bill.servedBy.name,
      footer: location.receiptFooter,
    );
  }

  final ReceiptHeader header;

  /// Prints a "REPRINT" marker under the header.
  final bool reprint;

  /// Present only for a cancelled bill; prints the "CANCELLED" banner.
  final ReceiptCancellation? cancellation;

  /// `PTB-D01-000123` (D-003).
  final String billNo;

  /// When the bill was made, as an instant. Printed in IST: see [issuedAtIst].
  final DateTime issuedAt;

  final List<ReceiptLine> lines;

  /// Σ line amounts.
  final Money subtotal;

  /// Null when there is no discount.
  final Discount? discount;

  /// Always printed as its own line, even when zero (D-010). May be
  /// negative.
  final Money roundOff;

  /// Whole rupees. Printed in double height.
  final Money total;

  /// One line per payment, in the order they were taken.
  final List<Payment> payments;

  /// Present only when cash was tendered and [change] could be worked out.
  final Money? cashTendered;

  /// Tendered minus the cash payments. Present exactly when [cashTendered]
  /// is.
  final Money? change;

  /// Present only when the bill has tax lines (D-013). Null for every MVP
  /// bill.
  final GstBlock? gst;

  /// The Store Manager's display name.
  final String servedBy;

  /// The location's `receiptFooter`.
  final String footer;

  bool get isCancelled => cancellation != null;

  /// [issuedAt] shifted to IST. Read its wall-clock fields (year … minute)
  /// for printing; they are the same whatever the device's time zone.
  DateTime get issuedAtIst => toIst(issuedAt);
}

/// What a return slip says, in print order (BRD §4.1), with no layout.
final class ReturnSlipDocument {
  const ReturnSlipDocument({
    required this.header,
    required this.returnId,
    required this.originalBillNo,
    required this.issuedAt,
    required this.lines,
    required this.refundTotal,
    required this.refunds,
    required this.reason,
    required this.footer,
  });

  /// Maps a saved return to its slip. [bill] is the bill it was made
  /// against.
  factory ReturnSlipDocument.fromReturn(
    SaleReturn ret,
    Bill bill,
    Location location,
  ) {
    assert(ret.billId == bill.id, 'return ${ret.id} is not for ${bill.id}');
    return ReturnSlipDocument(
      header: ReceiptHeader.of(location),
      returnId: ret.id,
      originalBillNo: ret.billNo,
      issuedAt: ret.clientCreatedAt,
      lines: [
        for (final l in ret.lines)
          ReturnSlipLine(name: l.name, qty: l.qty, amount: l.amount),
      ],
      refundTotal: ret.refundTotal,
      refunds: List.unmodifiable(ret.refunds),
      reason: ret.reason,
      footer: location.receiptFooter,
    );
  }

  final ReceiptHeader header;

  /// `D01-R000007` (D-024 f).
  final String returnId;

  /// The bill the goods came from, e.g. `PTB-D01-000123`.
  final String originalBillNo;

  /// When the return was made, as an instant. Printed in IST.
  final DateTime issuedAt;

  final List<ReturnSlipLine> lines;

  /// Whole rupees. Can differ from Σ line amounts by under ₹1 (D-024 d).
  final Money refundTotal;

  /// One line per refund mode.
  final List<Payment> refunds;

  final String reason;

  /// The location's `receiptFooter`.
  final String footer;

  DateTime get issuedAtIst => toIst(issuedAt);
}

/// The location block at the top of every slip.
final class ReceiptHeader {
  const ReceiptHeader({
    required this.name,
    required this.address,
    required this.phone,
  });

  factory ReceiptHeader.of(Location location) => ReceiptHeader(
    name: location.name,
    address: location.address,
    phone: location.phone,
  );

  final String name;

  /// May contain newlines; the layout engine keeps them.
  final String address;
  final String phone;
}

/// A "CANCELLED" banner. [reason] is the Store Manager's reason, when the
/// bill carries one.
final class ReceiptCancellation {
  const ReceiptCancellation({this.reason});

  final String? reason;
}

/// One product line: name, qty × unit price, and the line amount.
final class ReceiptLine {
  const ReceiptLine({
    required this.name,
    required this.qty,
    required this.unitPrice,
    required this.amount,
  });

  final String name;
  final int qty;
  final Money unitPrice;

  /// qty × unit price, as saved on the bill.
  final Money amount;
}

/// One returned line: name, qty, and its prorated refund (D-024 c).
final class ReturnSlipLine {
  const ReturnSlipLine({
    required this.name,
    required this.qty,
    required this.amount,
  });

  final String name;
  final int qty;
  final Money amount;
}

/// The GST breakup, printed only when a bill has tax lines (D-013).
final class GstBlock {
  const GstBlock({required this.taxableValue, required this.lines, this.gstin});

  /// The location's GSTIN, when it has one.
  final String? gstin;

  /// subtotal − discount.
  final Money taxableValue;

  /// One per rate, never empty.
  final List<TaxLine> lines;
}

/// [instant] with its wall-clock fields moved to IST (D-022). The result is
/// a UTC `DateTime`, so formatting never picks up the device's own zone.
DateTime toIst(DateTime instant) => instant.toUtc().add(BusinessDate.istOffset);
