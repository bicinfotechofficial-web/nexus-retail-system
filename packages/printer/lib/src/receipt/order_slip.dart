import 'package:nexus_core/nexus_core.dart';

import 'receipt_document.dart';

/// What the advance slip says (D-043), in print order, with no layout. The
/// customer gets it when an order is taken. Built from a saved [PreOrder]
/// and its [Location]; internal layout lives in `ReceiptLayout.orderSlip`.
final class OrderSlipDocument {
  const OrderSlipDocument({
    required this.header,
    required this.orderNo,
    required this.issuedAt,
    required this.customerName,
    required this.dueDate,
    required this.description,
    required this.price,
    required this.advance,
    required this.servedBy,
    required this.footer,
    this.dueTime,
    this.advanceMode,
  });

  /// Pure: the same order always gives the same document. The phone number
  /// is left off, as on the bill (D-034).
  factory OrderSlipDocument.fromOrder(PreOrder order, Location location) =>
      OrderSlipDocument(
        header: ReceiptHeader.of(location),
        orderNo: order.orderNo,
        issuedAt: order.clientCreatedAt,
        customerName: order.customer.name,
        dueDate: order.dueDate,
        dueTime: order.dueTime,
        description: order.description,
        price: order.price,
        advance: order.advance,
        advanceMode: order.advance.isPositive ? order.advanceMode : null,
        servedBy: order.servedBy.name,
        footer: location.receiptFooter,
      );

  final ReceiptHeader header;

  /// `PTB-D01-O000007`.
  final String orderNo;

  /// When the order was taken, as an instant. Printed in IST.
  final DateTime issuedAt;

  final String customerName;

  /// `YYYY-MM-DD`; printed as `dd-MM-yyyy`.
  final String dueDate;

  /// `HH:mm`, or null when no time was agreed ("Time: any").
  final String? dueTime;

  /// Free text; its line breaks are kept.
  final String description;

  final Money price;

  /// Zero when no advance was taken.
  final Money advance;

  /// Null when [advance] is zero.
  final PaymentMode? advanceMode;

  final String servedBy;

  /// The location's `receiptFooter`.
  final String footer;

  /// What the customer still pays on delivery.
  Money get balance => price - advance;

  DateTime get issuedAtIst => toIst(issuedAt);
}
