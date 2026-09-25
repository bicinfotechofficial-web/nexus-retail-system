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
  other('OTHER');

  const PaymentMode(this.wire);
  final String wire;
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
  userCreate('USER_CREATE'),
  userDisable('USER_DISABLE'),
  offlineOverride('OFFLINE_OVERRIDE'),
  thresholdChange('THRESHOLD_CHANGE'),
  locationUpdate('LOCATION_UPDATE');

  const AuditAction(this.wire);
  final String wire;
  static AuditAction fromWire(String w) => _fromWire(values, w, (v) => v.wire);
}
