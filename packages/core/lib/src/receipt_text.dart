import 'enums.dart';
import 'models/sales.dart';
import 'money.dart';

/// The plain-text bill sent through WhatsApp (D-036). WhatsApp uses a
/// proportional font, so this is a simple list, not the columns of the
/// thermal slip. At most 15 lines (D-030) keeps it well under the length
/// that is safe in a `wa.me` link.
abstract final class WhatsappReceipt {
  /// Longest item name kept in the message.
  static const int maxNameLength = 40;

  /// A guard for callers: the text is built to stay below this.
  static const int maxLength = 1500;

  static String build({
    required String shopName,
    required String locationName,
    required Bill bill,
  }) {
    final b = StringBuffer()
      ..writeln('*$shopName* - $locationName')
      ..writeln('Bill ${bill.billNo}')
      ..writeln(_date(bill.businessDate));
    final who = bill.customer?.name;
    if (who != null) {
      b
        ..writeln()
        ..writeln('Hi $who, thank you for shopping with us!');
    }
    b.writeln();
    for (final l in bill.lines) {
      b.writeln('${_short(l.name)} x ${l.qty}  ${l.lineTotal.format()}');
    }
    b.writeln();
    b.writeln('Subtotal: ${bill.subtotal.format()}');
    if (bill.discountAmount != Money.zero) {
      b.writeln('Discount: -${bill.discountAmount.format()}');
    }
    for (final t in bill.taxLines) {
      b.writeln('GST ${t.rate}%: ${(t.cgst + t.sgst).format()}');
    }
    if (bill.roundOff != Money.zero) {
      b.writeln('Round off: ${bill.roundOff.format()}');
    }
    b.writeln('*Total: ${bill.total.format()}*');
    for (final p in bill.payments) {
      b.writeln('${_mode(p.mode)}: ${p.amount.format()}');
    }
    if (bill.status == BillStatus.cancelled) {
      b
        ..writeln()
        ..writeln('This bill was cancelled.');
    }
    return b.toString().trimRight();
  }

  /// `https://wa.me/91<number>?text=<text>`. [whatsapp] is ten digits.
  ///
  /// Built by hand so spaces become `%20` (a form-style `+` can show up as a
  /// plus sign in some WhatsApp versions).
  static Uri link(String whatsapp, String text) =>
      Uri.parse('https://wa.me/91$whatsapp?text=${Uri.encodeComponent(text)}');

  static String _short(String name) => name.length <= maxNameLength
      ? name
      : '${name.substring(0, maxNameLength - 1)}…';

  /// `2026-09-25` → `25-09-2026`.
  static String _date(String businessDate) {
    final p = businessDate.split('-');
    return p.length == 3 ? '${p[2]}-${p[1]}-${p[0]}' : businessDate;
  }

  static String _mode(PaymentMode m) => switch (m) {
    PaymentMode.cash => 'Cash',
    PaymentMode.upi => 'UPI',
    PaymentMode.card => 'Card',
    PaymentMode.wallet => 'Wallet',
    PaymentMode.other => 'Other',
  };
}
