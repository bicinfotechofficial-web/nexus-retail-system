import '../enums.dart';
import '../ids.dart';
import '../map_reader.dart';
import '../money.dart';
import 'sales.dart';

/// `locations/{loc}/orders/{orderId}` (D-043): a customised cake ordered in
/// advance with an advance payment. Delivering it creates an ordinary bill
/// (`Bill.orderId`) in the same batch that sets `status` to DELIVERED.
final class PreOrder {
  const PreOrder({
    required this.id,
    required this.orderNo,
    required this.deviceId,
    required this.seq,
    required this.customer,
    required this.dueDate,
    required this.description,
    required this.price,
    required this.advance,
    required this.status,
    required this.servedBy,
    required this.businessDate,
    required this.clientCreatedAt,
    required this.createdBy,
    this.dueTime,
    this.advanceMode,
    this.billId,
    this.deliveredAt,
    this.cancel,
    this.serverCreatedAt,
    this.locationId,
  });

  factory PreOrder.fromMap(String id, Map<String, Object?> map) {
    final r = MapReader(map, 'order $id');
    final customer = BillCustomer.fromBillMap(r);
    if (customer == null) {
      throw FormatException('order $id has no customer');
    }
    final mode = r.stringOrNull('advanceMode');
    return PreOrder(
      id: id,
      orderNo: r.string('orderNo'),
      deviceId: r.string('deviceId'),
      seq: r.integer('seq'),
      customer: customer,
      dueDate: r.string('dueDate'),
      dueTime: r.stringOrNull('dueTime'),
      description: r.string('description'),
      price: Money(r.integer('price')),
      advance: Money(r.integer('advance')),
      advanceMode: mode == null ? null : PaymentMode.fromWire(mode),
      status: r.enumValue('status', OrderStatus.fromWire),
      billId: r.stringOrNull('billId'),
      deliveredAt: r.dateTimeOrNull('deliveredAt'),
      cancel: switch (r.childOrNull('cancel')) {
        final c? => OrderCancel.fromReader(c),
        null => null,
      },
      servedBy: ServedBy.fromReader(r.child('servedBy')),
      businessDate: r.string('businessDate'),
      clientCreatedAt: r.dateTime('clientCreatedAt'),
      serverCreatedAt: r.dateTimeOrNull('serverCreatedAt'),
      createdBy: r.string('createdBy'),
    );
  }

  static const Set<String> serverTimestampFields = {
    'serverCreatedAt',
    'deliveredAt',
  };

  /// `D01-O000007`.
  final String id;

  /// `PTB-D01-O000007`, on the advance slip.
  final String orderNo;
  final String deviceId;
  final int seq;
  final BillCustomer customer;

  /// The business-date format, `YYYY-MM-DD`: the day the cake is wanted.
  final String dueDate;

  /// `HH:mm`, 24-hour, or null when no time was agreed.
  final String? dueTime;

  /// Free text: flavour, layers, weight, the message on the cake.
  final String description;

  /// The agreed price, in whole rupees.
  final Money price;

  /// Paid in advance, 0 to [price], in whole rupees.
  final Money advance;

  /// How the advance was paid; null when [advance] is zero.
  final PaymentMode? advanceMode;
  final OrderStatus status;

  /// The delivery bill, once DELIVERED.
  final String? billId;
  final DateTime? deliveredAt;
  final OrderCancel? cancel;
  final ServedBy servedBy;

  /// The day the order was taken (D-022).
  final String businessDate;
  final DateTime clientCreatedAt;
  final DateTime? serverCreatedAt;
  final String createdBy;

  /// Which location's order this is. Not stored: the repository fills it
  /// from the document path, so the Admin's all-stores list can show it.
  final String? locationId;

  /// What the customer still pays on delivery.
  Money get balance => price - advance;

  bool get isOpen => status == OrderStatus.open;

  /// The customer fields as stored on the order, the same flat names a bill
  /// uses.
  Map<String, Object?> toMap() => {
    'orderNo': orderNo,
    'deviceId': deviceId,
    'seq': seq,
    ...customer.toBillFields(),
    'dueDate': dueDate,
    'dueTime': dueTime,
    'description': description,
    'price': price.paise,
    'advance': advance.paise,
    'advanceMode': advanceMode?.wire,
    'status': status.wire,
    'billId': billId,
    if (cancel != null) 'cancel': cancel!.toMap(),
    'servedBy': servedBy.toMap(),
    'businessDate': businessDate,
    'clientCreatedAt': clientCreatedAt,
    'createdBy': createdBy,
  };

  /// The ID of this order's cancellation audit entry and, with the location,
  /// of its audit document (`Ids.auditId(loc, Ids.cancelId(orderId))`).
  String get cancelId => Ids.cancelId(id);
}

/// A cancelled pre-order: the reason, who, when, and how much of the
/// advance was handed back. The rest of the advance is kept by the shop.
final class OrderCancel {
  const OrderCancel({
    required this.reason,
    required this.by,
    required this.at,
    required this.businessDate,
    required this.refunded,
  });

  factory OrderCancel.fromReader(MapReader r) => OrderCancel(
    reason: r.string('reason'),
    by: r.string('by'),
    at: r.dateTime('at'),
    businessDate: r.string('businessDate'),
    refunded: Money(r.integerOr('refunded', 0)),
  );

  final String reason;
  final String by;
  final DateTime at;
  final String businessDate;

  /// 0 up to the order's `advance`, whole rupees.
  final Money refunded;

  Map<String, Object?> toMap() => {
    'reason': reason,
    'by': by,
    'at': at,
    'businessDate': businessDate,
    'refunded': refunded.paise,
  };
}
