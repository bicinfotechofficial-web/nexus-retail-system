// Exports one JSON fixture per plan type to firebase/test/fixtures/plans/
// (D-027, docs/agents/BACKEND.md "Plan fixtures"). The rules suite
// (firebase/test/plans.test.js) applies each one on the emulator as `uid`
// and expects it to be accepted; QA's pure-Dart tests read them too.
//
// Format: {"description", "uid", "arrange": [{"path", "data"}], "ops": [...]}.
// `arrange` holds the docs that must exist before the batch (written with
// the rules off, on top of the rules suite's seeded roles, users and
// locations); `ops` is `WritePlan.toJson()`. Everything is deterministic,
// so re-running this test leaves the committed files unchanged.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';

import 'plan_fixtures.dart';

final Directory _dir = Directory('../../firebase/test/fixtures/plans');

final class _Fixture {
  _Fixture(
    this.name,
    this.description,
    this.uid,
    this.plan, {
    this.arrange = const {},
  });

  final String name;
  final String description;
  final String uid;
  final WritePlan plan;
  final Map<String, Map<String, Object?>> arrange;

  Map<String, Object?> toJson() => {
    'description': description,
    'uid': uid,
    'arrange': [
      for (final e in arrange.entries)
        {'path': e.key, 'data': encodePlanValue(e.value)},
    ],
    ...plan.toJson(),
  };
}

Map<String, Object?> _device({
  String code = 'D01',
  int bill = 0,
  int movement = 0,
  int ret = 0,
}) => {
  ...Device(
    code: code,
    label: 'Counter 1',
    registeredBy: Fx.smUid,
    lastBillSeq: bill,
    lastMovementSeq: movement,
    lastReturnSeq: ret,
    retired: false,
  ).toMap(),
  'registeredAt': Fx.now,
};

Map<String, Object?> _storedBill(
  Bill b, {
  Map<String, int>? returned,
  String? lastReturnId,
}) => {
  ...b.toMap(),
  'returnedQty': ?returned,
  'lastReturnId': ?lastReturnId,
  'serverCreatedAt': Fx.now,
};

Bill _withReturns(Bill b, Map<String, int> returned, String lastReturnId) =>
    Bill.fromMap(
      b.id,
      _storedBill(b, returned: returned, lastReturnId: lastReturnId),
    );

List<_Fixture> _buildFixtures() {
  final sm = Fx.sm();
  final later = Fx.sm(at: Fx.now.add(const Duration(hours: 2)));
  final bill = Fx.bill();
  final billPath = FirestorePaths.bill('PTB', bill.id);
  const d01 = 'locations/PTB/devices/D01';

  final maxCart = [
    for (var i = 1; i <= Limits.maxBillLines; i++)
      CartLine(
        productId: 'p${i.toString().padLeft(2, '0')}',
        name: 'Product $i',
        qty: i,
        unitPrice: Money(1000 + 37 * i),
      ),
  ];
  final maxTotals = BillCalculator.compute(
    maxCart,
    discount: DiscountInput.flat(const Money(1234)),
  );
  final quarter = Money(maxTotals.total.paise ~/ 400 * 100);
  final maxBill = NewBill(
    cart: maxCart,
    discount: DiscountInput.flat(const Money(1234)),
    payments: [
      Payment(mode: PaymentMode.cash, amount: quarter),
      Payment(mode: PaymentMode.upi, amount: quarter),
      Payment(mode: PaymentMode.card, amount: quarter),
      Payment(
        mode: PaymentMode.wallet,
        amount: maxTotals.total - quarter.times(3),
      ),
    ],
  );

  final afterFirstReturn = _withReturns(bill, {'puff-veg': 1}, 'D01-R000003');
  final pending = AdminPlans.suggestProduct(
    ctx: sm,
    productId: 'p-special',
    name: 'Plum Cake',
    category: 'Cakes',
    proposedPrice: const Money(45000),
  ).value;
  const bf = Product(
    id: 'bf1kg',
    name: 'Black Forest 1 kg',
    category: 'Cakes',
    price: Money(60000),
    scope: Product.globalScope,
    status: ProductStatus.active,
    sortOrder: 3,
    createdBy: Fx.adminUid,
  );
  Map<String, Object?> storedProduct(Product p) => {
    ...p.toMap(),
    'createdAt': Fx.now,
    'updatedAt': Fx.now,
  };
  const rentInput = ExpenseInput(
    locationId: 'PTB',
    category: ExpenseCategory.rent,
    amount: Money(2500000),
    date: '2026-09-01',
    note: 'September rent',
  );
  final rent = AdminPlans.saveExpense(
    ctx: Fx.admin(),
    expenseId: 'e1',
    input: rentInput,
  );
  final ptb = Location.fromMap('PTB', {
    'code': 'PTB',
    'name': 'Test Store PTB',
    'address': 'Test Store PTB address',
    'phone': '0000000000',
    'gstin': null,
    'offlineLimitHours': 5,
    'overridePinHash': 'seeded',
    'overrideExtensionHours': 2,
    'maxDiscountPct': 20,
    'receiptFooter': 'Thank you!',
    'nextDeviceNo': 0,
    'active': true,
  });

  return [
    _Fixture(
      'bill_create',
      'Create bill: 2 lines, 10% off, cash + UPI, as D01 bill 7',
      Fx.smUid,
      SalesPlans.createBill(
        ctx: sm,
        seq: 7,
        input: Fx.newBill,
        servedByName: 'Store Manager PTB',
        maxDiscountPct: 20,
      ).plan,
      arrange: {d01: _device(bill: 6)},
    ),
    _Fixture(
      'bill_create_max',
      'Create bill at the caps: 15 lines, a flat discount, 4 payments',
      Fx.smUid,
      SalesPlans.createBill(
        ctx: sm,
        seq: 1,
        input: maxBill,
        servedByName: 'SM',
      ).plan,
      arrange: {d01: _device()},
    ),
    _Fixture(
      'bill_cancel',
      'Same-day cancel of bill D01-000007 from device D02',
      Fx.smUid,
      SalesPlans.cancelBill(
        ctx: Fx.sm(at: Fx.now.add(const Duration(hours: 2)), deviceId: 'D02'),
        bill: bill,
        reason: 'Customer changed order',
      ).plan,
      arrange: {billPath: _storedBill(bill), d01: _device(bill: 7)},
    ),
    _Fixture(
      'return_first',
      'First return of bill D01-000007: 1 puff, refunded in cash',
      Fx.smUid,
      SalesPlans.createReturn(
        ctx: later,
        seq: 3,
        bill: bill,
        qtyByProduct: {'puff-veg': 1},
        refunds: const [Payment(mode: PaymentMode.cash, amount: Money(2300))],
        reason: 'Damaged',
      ).plan,
      arrange: {billPath: _storedBill(bill), d01: _device(bill: 7, ret: 2)},
    ),
    _Fixture(
      'return_second',
      'Second return of bill D01-000007: the rest, chained by prevReturnId',
      Fx.smUid,
      SalesPlans.createReturn(
        ctx: later,
        seq: 4,
        bill: afterFirstReturn,
        qtyByProduct: {'puff-veg': 1, 'cake-choco-1kg': 1},
        refunds: const [
          Payment(mode: PaymentMode.upi, amount: Money(40000)),
          Payment(mode: PaymentMode.cash, amount: Money(20800)),
        ],
        reason: 'Customer returned the rest',
      ).plan,
      arrange: {
        billPath: _storedBill(
          bill,
          returned: {'puff-veg': 1},
          lastReturnId: 'D01-R000003',
        ),
        d01: _device(bill: 7, ret: 3),
      },
    ),
    _Fixture(
      'stock_in',
      'STOCK_IN of two raw materials with a note',
      Fx.smUid,
      StockPlans.stockIn(
        ctx: sm,
        seq: 42,
        lines: const [StockQty(Fx.flour, 5000), StockQty(Fx.cream, 1000)],
        note: 'Supplier A',
      ).plan,
      arrange: {d01: _device(movement: 41)},
    ),
    _Fixture(
      'stock_out_raw',
      'STOCK_OUT_RAW with a reason',
      Fx.smUid,
      StockPlans.stockOutRaw(
        ctx: sm,
        seq: 42,
        lines: const [StockQty(Fx.flour, 700)],
        reason: 'Sent to MNJ',
      ).plan,
      arrange: {d01: _device(movement: 41)},
    ),
    _Fixture(
      'wastage_raw',
      'WASTAGE_RAW with its WASTAGE audit',
      Fx.smUid,
      StockPlans.wastage(
        ctx: sm,
        seq: 42,
        kind: StockKind.raw,
        lines: const [StockQty(Fx.cream, 200)],
        reason: 'Spoilt',
      ).plan,
      arrange: {d01: _device(movement: 41)},
    ),
    _Fixture(
      'wastage_fg',
      'WASTAGE_FG with its WASTAGE audit',
      Fx.smUid,
      StockPlans.wastage(
        ctx: sm,
        seq: 42,
        kind: StockKind.finished,
        lines: [StockQty(Fx.cakeStock, 1)],
        reason: 'Dropped',
      ).plan,
      arrange: {d01: _device(movement: 41)},
    ),
    _Fixture(
      'produce',
      'PRODUCE: 2 raw materials consumed, 1 cake made',
      Fx.smUid,
      StockPlans.produce(
        ctx: sm,
        seq: 42,
        consumed: const [StockQty(Fx.flour, 1000), StockQty(Fx.cream, 500)],
        produced: [StockQty(Fx.cakeStock, 2)],
      ).plan,
      arrange: {d01: _device(movement: 41)},
    ),
    _Fixture(
      'adjust',
      'ADJUST (physical count) with before/after and its STOCK_ADJUST audit',
      Fx.smUid,
      StockPlans.adjust(
        ctx: sm,
        seq: 42,
        item: Fx.flour,
        localQty: 1200,
        countedQty: 900,
        reason: 'Monthly count',
      ).plan,
      arrange: {d01: _device(movement: 41)},
    ),
    _Fixture(
      'adjust_stock_counter',
      'ADJUST by a role with stock.adjust but not stock.move (QA-029)',
      Fx.counterUid,
      StockPlans.adjust(
        ctx: PlanContext(
          uid: Fx.counterUid,
          locationId: 'PTB',
          deviceId: 'D01',
          now: Fx.now,
        ),
        seq: 42,
        item: Fx.flour,
        localQty: 0,
        countedQty: 250,
        reason: 'First count',
      ).plan,
      arrange: {d01: _device(movement: 41)},
    ),
    _Fixture(
      'threshold_set',
      'Set a low-stock threshold on an item that has no stock doc yet',
      Fx.smUid,
      StockPlans.setThreshold(ctx: sm, item: Fx.cream, threshold: 2000),
    ),
    _Fixture(
      'expense_create',
      'Expense create: expense, PTB 2026-09 monthly summary, audit',
      Fx.adminUid,
      rent.plan,
    ),
    _Fixture(
      'expense_edit',
      'Expense edit moving it to MNJ in August: two monthly deltas',
      Fx.adminUid,
      AdminPlans.saveExpense(
        ctx: Fx.admin(at: Fx.now.add(const Duration(minutes: 5))),
        expenseId: 'e1',
        input: const ExpenseInput(
          id: 'e1',
          locationId: 'MNJ',
          category: ExpenseCategory.utilities,
          amount: Money(300000),
          date: '2026-08-31',
          note: 'Power',
        ),
        before: rent.value,
      ).plan,
      arrange: {
        'expenses/e1': {
          ...rent.value.toMap(),
          'createdAt': Fx.now,
          'updatedAt': Fx.now,
        },
      },
    ),
    _Fixture(
      'product_suggest',
      "A Store Manager's local special: PENDING at PTB",
      Fx.smUid,
      AdminPlans.suggestProduct(
        ctx: sm,
        productId: 'p-special',
        name: 'Plum Cake',
        category: 'Cakes',
        proposedPrice: const Money(45000),
      ).plan,
    ),
    _Fixture(
      'product_create',
      'Admin creates a priced, active product',
      Fx.adminUid,
      AdminPlans.saveProduct(ctx: Fx.admin(), product: bf).plan,
    ),
    _Fixture(
      'product_price_change',
      'Admin changes a price, with the PRICE_CHANGE audit',
      Fx.adminUid,
      AdminPlans.saveProduct(
        ctx: Fx.admin(),
        product: Product(
          id: bf.id,
          name: bf.name,
          category: bf.category,
          price: const Money(65000),
          scope: bf.scope,
          status: bf.status,
          sortOrder: bf.sortOrder,
          createdBy: bf.createdBy,
        ),
        existing: bf,
      ).plan,
      arrange: {'products/bf1kg': storedProduct(bf)},
    ),
    _Fixture(
      'product_approve',
      'Admin approves the local special, with the PRODUCT_APPROVE audit',
      Fx.adminUid,
      AdminPlans.approveProduct(
        ctx: Fx.admin(),
        existing: pending,
        price: const Money(48000),
      ).plan,
      arrange: {'products/p-special': storedProduct(pending)},
    ),
    _Fixture(
      'raw_material_create',
      'A Store Manager adds a raw material',
      Fx.smUid,
      AdminPlans.addRawMaterial(
        ctx: sm,
        materialId: 'cocoa',
        name: 'Cocoa',
        unit: StockUnit.g,
      ).plan,
    ),
    _Fixture(
      'location_create',
      'Admin creates location KTL with nextDeviceNo 0 and a PIN hash',
      Fx.adminUid,
      AdminPlans.saveLocation(
        ctx: Fx.admin(),
        location: const Location(
          code: 'KTL',
          name: 'Kottakkal',
          address: 'Main Road',
          phone: '0000000000',
          overridePinHash: '',
          receiptFooter: 'Thank you!',
          nextDeviceNo: 0,
          active: true,
        ),
        // PinHasher().hash('24681357', salt: utf8.encode('fixture-KTL')).
        newPinHash: _ktlHash,
      ).plan,
    ),
    _Fixture(
      'location_edit',
      'Admin edits PTB with a new PIN; nextDeviceNo is not written',
      Fx.adminUid,
      AdminPlans.saveLocation(
        ctx: Fx.admin(),
        location: Location(
          code: 'PTB',
          name: 'Test Store PTB (renamed)',
          address: ptb.address,
          phone: ptb.phone,
          overridePinHash: '',
          receiptFooter: 'Thanks, visit again!',
          nextDeviceNo: 0,
          active: true,
          offlineLimitHours: 6,
          maxDiscountPct: 15,
        ),
        existing: ptb,
        newPinHash: _ktlHash,
      ).plan,
    ),
    _Fixture(
      'device_register',
      'Registration at PTB: nextDeviceNo 0 -> 1 and a clean devices/D01',
      Fx.smUid,
      DevicePlans.register(
        ctx: sm,
        locationId: 'PTB',
        currentNextDeviceNo: 0,
        label: 'Counter 1',
      ).plan,
    ),
    _Fixture(
      'device_retire',
      'Admin retires device D01 at PTB',
      Fx.adminUid,
      DevicePlans.retire(locationId: 'PTB', deviceId: 'D01'),
      arrange: {d01: _device(bill: 7)},
    ),
    _Fixture(
      'user_disable',
      'Admin disables the PTB Store Manager, with the USER_DISABLE audit',
      Fx.adminUid,
      AdminPlans.setUserActive(
        ctx: Fx.admin(),
        user: const AppUser(
          uid: 'sm-ptb',
          name: 'Store Manager PTB',
          email: 'sm-ptb@example.test',
          roleId: 'STORE_MANAGER',
          locationId: 'PTB',
          active: true,
          createdBy: 'seed',
        ),
        active: false,
      ).plan,
    ),
  ];
}

const String _ktlHash =
    r'Zml4dHVyZS1LVEw=$My24sNIbFGHL5UnbIT0eNVqKrnJiurgKBAVJXK0RRcc=';

void main() {
  final fixtures = _buildFixtures();

  test('the KTL fixture hash is PinHasher output', () async {
    expect(
      await PinHasher().hash('24681357', salt: utf8.encode('fixture-KTL')),
      _ktlHash,
    );
  });

  test('fixture names are unique', () {
    final names = fixtures.map((f) => f.name).toList();
    expect(names.toSet(), hasLength(names.length));
  });

  test('every fixture round-trips through the JSON encoding', () {
    for (final f in fixtures) {
      final back = decodePlan(
        jsonDecode(jsonEncode(f.toJson())) as Map<String, Object?>,
      );
      expect(back.paths, f.plan.paths, reason: f.name);
      for (var i = 0; i < back.ops.length; i++) {
        expect(back.ops[i].data, f.plan.ops[i].data, reason: f.name);
      }
    }
  });

  test('writes firebase/test/fixtures/plans/*.json', () {
    _dir.createSync(recursive: true);
    final wanted = {for (final f in fixtures) '${f.name}.json'};
    for (final stale in _dir.listSync().whereType<File>()) {
      final name = stale.uri.pathSegments.last;
      if (name.endsWith('.json') && !wanted.contains(name)) stale.deleteSync();
    }
    for (final f in fixtures) {
      File(
        '${_dir.path}/${f.name}.json',
      ).writeAsStringSync(prettyJson(f.toJson()));
    }
    expect(
      _dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json')),
      hasLength(fixtures.length),
    );
  });
}
