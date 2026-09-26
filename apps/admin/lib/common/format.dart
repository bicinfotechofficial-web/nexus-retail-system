import 'package:intl/intl.dart';
import 'package:nexus_core/nexus_core.dart';

/// `2026-09-26` → `26 Sep 2026`. Business dates are already IST (D-022).
String formatBusinessDate(String businessDate) {
  final p = businessDate.split('-').map(int.parse).toList();
  return DateFormat('d MMM yyyy').format(DateTime.utc(p[0], p[1], p[2]));
}

/// `2026-09` → `September 2026`.
String formatMonthKey(String monthKey) {
  final p = monthKey.split('-').map(int.parse).toList();
  return DateFormat('MMMM yyyy').format(DateTime.utc(p[0], p[1]));
}

/// A stock quantity in its base unit, e.g. `4,000 g` or `12 pcs`.
String formatQty(int qty, StockUnit unit) {
  final n = NumberFormat.decimalPattern('en_IN').format(qty);
  return switch (unit) {
    StockUnit.g => '$n g',
    StockUnit.ml => '$n ml',
    StockUnit.pcs => '$n pcs',
  };
}

String paymentModeLabel(PaymentMode mode) => switch (mode) {
  PaymentMode.cash => 'Cash',
  PaymentMode.upi => 'UPI',
  PaymentMode.card => 'Card',
  PaymentMode.wallet => 'Wallet',
  PaymentMode.other => 'Other',
};

/// An instant in IST (D-022), e.g. `26 Sep 2026, 4:30 PM`.
String formatInstantIst(DateTime instant) => DateFormat(
  'd MMM yyyy, h:mm a',
).format(instant.toUtc().add(BusinessDate.istOffset));

/// How long ago [instant] was, relative to [now]: `just now`, `12 min ago`,
/// `3 h ago`, `2 days ago`.
String formatAgo(DateTime instant, DateTime now) {
  final d = now.difference(instant);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes} min ago';
  if (d.inDays < 1) return '${d.inHours} h ago';
  return d.inDays == 1 ? '1 day ago' : '${d.inDays} days ago';
}
