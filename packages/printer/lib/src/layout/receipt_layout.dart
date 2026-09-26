import 'package:nexus_core/nexus_core.dart';

import '../api.dart';
import '../receipt/receipt_document.dart';
import 'line_builder.dart';
import 'print_line.dart';

/// Lays out receipts and return slips as lines of exactly
/// [PaperWidth.columns] characters (BRD §4.1). The plain-text preview and
/// the ESC/POS encoder (PR-3) both start from these lines.
final class ReceiptLayout {
  const ReceiptLayout(this.width, {this.currencySymbol = '₹'});

  final PaperWidth width;

  /// `₹`, or `Rs.` when the printer's code page has no ₹ glyph (PR-3).
  final String currencySymbol;

  int get columns => width.columns;

  List<PrintLine> bill(ReceiptDocument doc) {
    final b = LineBuilder(columns);
    _header(b, doc.header);

    if (doc.isCancelled) {
      b.banner('CANCELLED');
      if (doc.cancellation!.reason case final reason?) {
        b.left('Reason: $reason');
      }
    }
    if (doc.reprint) b.center('REPRINT', bold: true);
    if (doc.isCancelled || doc.reprint) b.rule();

    b.left('Bill No: ${doc.billNo}');
    b.left('Date: ${_dateTime(doc.issuedAtIst)}');
    b.rule();

    for (final line in doc.lines) {
      b.left(line.name);
      b.row(
        '${line.qty} x ${_money(line.unitPrice)}',
        _money(line.amount),
        indent: 2,
      );
    }
    b.rule();

    b.row('Subtotal', _money(doc.subtotal));
    if (doc.discount case final d?) {
      final label = d.type == DiscountType.pct
          ? 'Discount (${d.value}%)'
          : 'Discount';
      b.row(label, _money(-d.amount));
    }
    b.row('Round off', _signed(doc.roundOff));
    b.rule('=');
    b.row('TOTAL', _money(doc.total), bold: true, doubleHeight: true);
    b.rule('=');

    _payments(b, doc.payments);
    if (doc.change case final change?) {
      b.row('Cash tendered', _money(doc.cashTendered!));
      b.row('Change', _money(change));
    }

    if (doc.gst case final gst?) {
      b.rule();
      if (gst.gstin case final gstin?) b.left('GSTIN: $gstin');
      b.row('Taxable value', _money(gst.taxableValue));
      for (final t in gst.lines) {
        final half = _halfRate(t.rate);
        b.row('CGST $half%', _money(t.cgst));
        b.row('SGST $half%', _money(t.sgst));
      }
    }

    b.rule();
    b.left('Served by: ${doc.servedBy}');
    _footer(b, doc.footer);
    return b.build();
  }

  List<PrintLine> returnSlip(ReturnSlipDocument doc) {
    final b = LineBuilder(columns);
    _header(b, doc.header);

    b.center('RETURN SLIP', bold: true);
    b.rule();
    b.left('Return No: ${doc.returnId}');
    b.left('Bill No: ${doc.originalBillNo}');
    b.left('Date: ${_dateTime(doc.issuedAtIst)}');
    b.rule();

    for (final line in doc.lines) {
      b.left(line.name);
      b.row('Qty ${line.qty}', _money(line.amount), indent: 2);
    }
    b.rule('=');
    b.row('REFUND', _money(doc.refundTotal), bold: true, doubleHeight: true);
    b.rule('=');

    _payments(b, doc.refunds);
    b.rule();
    b.left('Reason: ${doc.reason}');
    _footer(b, doc.footer);
    return b.build();
  }

  void _header(LineBuilder b, ReceiptHeader h) {
    b.center(h.name, bold: true);
    b.center(h.address);
    b.center('Ph: ${h.phone}');
    b.rule();
  }

  void _payments(LineBuilder b, List<Payment> payments) {
    for (final p in payments) {
      b.row(_modeLabel(p.mode), _money(p.amount));
      if (p.ref case final ref? when ref.isNotEmpty) {
        b.left('Ref: $ref', indent: 2);
      }
    }
  }

  void _footer(LineBuilder b, String footer) {
    if (footer.trim().isEmpty) return;
    b.blank();
    b.center(footer);
  }

  String _money(Money m) => m.format(symbol: currencySymbol);

  /// Round-off shows its sign either way: `+₹0.30`, `-₹0.07`, `₹0.00`.
  String _signed(Money m) => m.isPositive ? '+${_money(m)}' : _money(m);
}

String _modeLabel(PaymentMode mode) => switch (mode) {
  PaymentMode.cash => 'Cash',
  PaymentMode.upi => 'UPI',
  PaymentMode.card => 'Card',
  PaymentMode.wallet => 'Wallet',
  PaymentMode.other => 'Other',
};

/// `25-09-2026 14:35`, from IST wall-clock fields.
String _dateTime(DateTime ist) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(ist.day)}-${two(ist.month)}-${ist.year} '
      '${two(ist.hour)}:${two(ist.minute)}';
}

/// CGST and SGST are each half the GST rate: 5 → `2.5`, 18 → `9`.
String _halfRate(int rate) => rate.isEven ? '${rate ~/ 2}' : '${rate ~/ 2}.5';
