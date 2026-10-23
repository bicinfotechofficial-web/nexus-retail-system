/// Every enum stored in Firestore, with its UPPER_SNAKE wire name
/// (02-DATA-MODEL conventions). `fromWire` throws [FormatException] on an
/// unknown value so a bad document fails loudly instead of defaulting.
library;

T _fromWire<T extends Enum>(
  List<T> values,
  String wire,
  String Function(T) name,
) {
  for (final v in values) {
    if (name(v) == wire) return v;
  }
  throw FormatException('Unknown ${T.toString()}', wire);
}

enum PaymentMode {
  cash('CASH'),
  upi('UPI'),
  card('CARD'),
  wallet('WALLET'),
  other('OTHER'),

  /// An advance paid earlier on a pre-order and credited on its delivery
  /// bill (D-043). Never offered as a choice at the counter.
  advance('ADVANCE');

  const PaymentMode(this.wire);
  final String wire;

  /// The modes a cashier can pick when taking or refunding money. Excludes
  /// [advance], which only the delivery of a pre-order creates.
  static const List<PaymentMode> selectable = [cash, upi, card, wallet, other];
  static PaymentMode fromWire(String w) => _fromWire(values, w, (v) => v.wire);
}

enum BillStatus {
  completed('COMPLETED'),
  cancelled('CANCELLED');

  const BillStatus(this.wire);
  final String wire;
  static BillStatus fromWire(String w) => _fromWire(values, w, (v) => v.wire);
}

enum DiscountType {
  /// `value` is paise.
  flat('FLAT'),

  /// `value` is a whole percentage.
  pct('PCT');

  const DiscountType(this.wire);
  final String wire;
  static DiscountType fromWire(String w) => _fromWire(values, w, (v) => v.wire);
}

enum MovementType {
  stockIn('STOCK_IN'),
  stockOutRaw('STOCK_OUT_RAW'),
  wastageRaw('WASTAGE_RAW'),
  produce('PRODUCE'),
  wastageFg('WASTAGE_FG'),
  adjust('ADJUST'),
  sale('SALE'),
  returned('RETURN'),
  cancel('CANCEL');

  const MovementType(this.wire);
  final String wire;
  static MovementType fromWire(String w) => _fromWire(values, w, (v) => v.wire);

  /// WASTAGE_*, ADJUST and CANCEL need a reason (02-DATA-MODEL).
  bool get requiresReason =>
      this == wastageRaw ||
      this == wastageFg ||
      this == adjust ||
      this == cancel;

  /// These movements need an audit doc with the same ID (04-PERMISSIONS #10).
  bool get requiresAudit =>
      this == wastageRaw ||
      this == wastageFg ||
      this == adjust ||
      this == cancel ||
      this == returned;
}

enum StockKind {
  raw('RAW'),
  finished('FINISHED');

  const StockKind(this.wire);
  final String wire;
  static StockKind fromWire(String w) => _fromWire(values, w, (v) => v.wire);
}

/// Base units (D-006).
enum StockUnit {
  g('G'),
  ml('ML'),
  pcs('PCS');

  const StockUnit(this.wire);
  final String wire;
  static StockUnit fromWire(String w) => _fromWire(values, w, (v) => v.wire);
}

enum ProductStatus {
  active('ACTIVE'),
  pending('PENDING'),
  inactive('INACTIVE');

  const ProductStatus(this.wire);
  final String wire;
  static ProductStatus fromWire(String w) =>
      _fromWire(values, w, (v) => v.wire);
}

enum ExpenseCategory {
  rent('RENT'),
  salary('SALARY'),
  utilities('UTILITIES'),
  other('OTHER');

  const ExpenseCategory(this.wire);
  final String wire;
  static ExpenseCategory fromWire(String w) =>
      _fromWire(values, w, (v) => v.wire);
}

enum AuditAction {
  stockAdjust('STOCK_ADJUST'),
  wastage('WASTAGE'),
  billCancel('BILL_CANCEL'),
  returned('RETURN'),
  expenseCreate('EXPENSE_CREATE'),
  expenseUpdate('EXPENSE_UPDATE'),
  priceChange('PRICE_CHANGE'),
  productApprove('PRODUCT_APPROVE'),
  productDecline('PRODUCT_DECLINE'),
  userCreate('USER_CREATE'),
  userDisable('USER_DISABLE'),
  userEnable('USER_ENABLE'),
  offlineOverride('OFFLINE_OVERRIDE'),
  thresholdChange('THRESHOLD_CHANGE'),
  locationUpdate('LOCATION_UPDATE'),
  orderCancel('ORDER_CANCEL');

  const AuditAction(this.wire);
  final String wire;
  static AuditAction fromWire(String w) => _fromWire(values, w, (v) => v.wire);
}

/// A staff member's attendance for one day (D-042).
enum AttendanceStatus {
  present('PRESENT', 1),
  halfDay('HALF_DAY', 0.5),
  absent('ABSENT', 0);

  const AttendanceStatus(this.wire, this.dayValue);
  final String wire;

  /// What the day adds to a monthly total.
  final double dayValue;
  static AttendanceStatus fromWire(String w) =>
      _fromWire(values, w, (v) => v.wire);
}

/// A pre-order's state (D-043).
enum OrderStatus {
  open('OPEN'),
  delivered('DELIVERED'),
  cancelled('CANCELLED');

  const OrderStatus(this.wire);
  final String wire;
  static OrderStatus fromWire(String w) => _fromWire(values, w, (v) => v.wire);
}
