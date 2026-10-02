import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';

/// Shared inputs for the plan tests and the JSON fixtures. The uids and
/// locations are the rules suite's fixture actors
/// (`firebase/test/support/fixtures.js`), so the fixtures apply as-is.
abstract final class Fx {
  static const String smUid = 'sm-ptb';
  static const String adminUid = 'admin';
  static const String cashierUid = 'cashier-ptb';
  static const String counterUid = 'counter-ptb';

  /// 2026-09-26 10:00 IST: the rules suite's TODAY.
  static final DateTime now = DateTime.utc(2026, 9, 26, 4, 30);
  static const String today = '2026-09-26';

  static PlanContext sm({DateTime? at, String deviceId = 'D01'}) => PlanContext(
    uid: smUid,
    locationId: 'PTB',
    deviceId: deviceId,
    now: at ?? now,
  );

  static PlanContext admin({DateTime? at}) =>
      PlanContext(uid: adminUid, now: at ?? now);

  static const CartLine cake = CartLine(
    productId: 'cake-choco-1kg',
    name: 'Chocolate Cake 1 kg',
    qty: 1,
    unitPrice: Money(65000),
  );
  static const CartLine puff = CartLine(
    productId: 'puff-veg',
    name: 'Veg Puff',
    qty: 2,
    unitPrice: Money(2550),
  );

  /// The customer on every test bill.
  static final BillCustomer customer = BillCustomer(
    name: 'Test Customer',
    phone: '9876543210',
    whatsapp: '9876543210',
  );

  /// 1 × ₹650 + 2 × ₹25.50 = ₹701, 10% off (₹70.10) = ₹630.90, rounded to
  /// ₹631 (+₹0.10). Paid ₹500 cash + ₹131 UPI. Per-line nets: ₹585 and
  /// ₹45.90.
  static final NewBill newBill = NewBill(
    cart: const [cake, puff],
    discount: const DiscountInput.percent(10),
    payments: const [
      Payment(mode: PaymentMode.cash, amount: Money(50000)),
      Payment(mode: PaymentMode.upi, amount: Money(13100), ref: 'UPI-1'),
    ],
    cashTendered: const Money(50000),
    customer: customer,
  );

  /// The bill [newBill] makes as D01's 7th bill.
  static Bill bill({DateTime? at}) => SalesPlans.createBill(
    ctx: sm(at: at),
    seq: 7,
    input: newBill,
    servedByName: 'Store Manager PTB',
    maxDiscountPct: 20,
  ).value;

  static const StockRef flour = StockRef(
    kind: StockKind.raw,
    refId: 'flour',
    name: 'Flour',
    unit: StockUnit.g,
  );
  static const StockRef cream = StockRef(
    kind: StockKind.raw,
    refId: 'cream',
    name: 'Cream',
    unit: StockUnit.ml,
  );
  static final StockRef cakeStock = StockRef.product(
    'cake-choco-1kg',
    'Chocolate Cake 1 kg',
  );
}
