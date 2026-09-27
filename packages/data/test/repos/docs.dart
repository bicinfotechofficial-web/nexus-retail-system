import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:nexus_core/nexus_core.dart';

/// Test docs shaped like 02-DATA-MODEL: each model's `toMap`, with every
/// `DateTime` stored as a [Timestamp] and the server timestamp fields set,
/// as Firestore holds them once synced.

/// [map] as Firestore stores it: `DateTime`s become [Timestamp]s at any
/// depth, and [serverTimes] are added as [Timestamp]s.
Map<String, Object?> stored(
  Map<String, Object?> map, {
  Map<String, DateTime> serverTimes = const {},
}) => {
  for (final e in map.entries) e.key: _stored(e.value),
  for (final e in serverTimes.entries) e.key: Timestamp.fromDate(e.value),
};

Object? _stored(Object? v) => switch (v) {
  DateTime() => Timestamp.fromDate(v),
  Map() => {for (final e in v.entries) e.key as String: _stored(e.value)},
  List() => [for (final e in v) _stored(e)],
  _ => v,
};

Future<void> put(
  FakeFirebaseFirestore db,
  String path,
  Map<String, Object?> map, {
  Map<String, DateTime> serverTimes = const {},
}) => db.doc(path).set(stored(map, serverTimes: serverTimes));

/// An IST wall-clock time as a UTC instant.
DateTime ist(int y, int mo, int d, [int h = 0, int mi = 0, int s = 0]) =>
    DateTime.utc(y, mo, d, h, mi, s).subtract(BusinessDate.istOffset);

Product product(
  String id, {
  String scope = Product.globalScope,
  ProductStatus status = ProductStatus.active,
  int? price = 50000,
  int sortOrder = 0,
  String? name,
}) => Product(
  id: id,
  name: name ?? 'Cake $id',
  category: 'Cakes',
  scope: scope,
  status: status,
  sortOrder: sortOrder,
  createdBy: 'admin1',
  price: price == null ? null : Money(price),
);

Map<String, DateTime> productTimes(DateTime at) => {
  'createdAt': at,
  'updatedAt': at,
};

StockItem stockItem(
  String itemKey, {
  required int qty,
  int? lowThreshold,
  StockKind kind = StockKind.finished,
  String? name,
}) => StockItem(
  itemKey: itemKey,
  kind: kind,
  refId: itemKey.substring(3),
  name: name ?? itemKey,
  unit: kind == StockKind.raw ? StockUnit.g : StockUnit.pcs,
  qty: qty,
  lowThreshold: lowThreshold,
  lastMovementId: 'D01-M000001',
);

/// A one-line COMPLETED bill, created at [at] with the business date
/// `BusinessDate.of(at)`.
Bill bill(String loc, String deviceId, int seq, DateTime at) {
  final id = Ids.billId(deviceId, seq);
  return Bill(
    id: id,
    billNo: Ids.billNo(loc, id),
    deviceId: deviceId,
    seq: seq,
    lines: const [
      BillLine(
        productId: 'bf1kg',
        name: 'Black Forest 1 kg',
        qty: 1,
        unitPrice: Money(80000),
        lineTotal: Money(80000),
      ),
    ],
    subtotal: const Money(80000),
    taxableValue: const Money(80000),
    roundOff: Money.zero,
    total: const Money(80000),
    payments: const [Payment(mode: PaymentMode.upi, amount: Money(80000))],
    status: BillStatus.completed,
    servedBy: const ServedBy(uid: 'sm1', name: 'Store Manager'),
    businessDate: BusinessDate.of(at),
    clientCreatedAt: at,
    createdBy: 'sm1',
  );
}

Future<void> putBill(FakeFirebaseFirestore db, String loc, Bill b) => put(
  db,
  FirestorePaths.bill(loc, b.id),
  b.toMap(),
  serverTimes: {'serverCreatedAt': b.clientCreatedAt},
);

SaleReturn saleReturn(
  String loc,
  String deviceId,
  int seq,
  String billId,
  DateTime at,
) => SaleReturn(
  id: Ids.returnId(deviceId, seq),
  billId: billId,
  billNo: Ids.billNo(loc, billId),
  lines: const [
    ReturnLine(
      productId: 'bf1kg',
      name: 'Black Forest 1 kg',
      qty: 1,
      amount: Money(80000),
    ),
  ],
  refundTotal: const Money(80000),
  refunds: const [Payment(mode: PaymentMode.cash, amount: Money(80000))],
  reason: 'Damaged',
  businessDate: BusinessDate.of(at),
  createdBy: 'sm1',
  deviceId: deviceId,
  clientCreatedAt: at,
);

Future<void> putReturn(FakeFirebaseFirestore db, String loc, SaleReturn r) =>
    put(
      db,
      FirestorePaths.saleReturn(loc, r.id),
      r.toMap(),
      serverTimes: {'serverCreatedAt': r.clientCreatedAt},
    );

AuditEntry audit(
  String id, {
  required AuditAction action,
  required DateTime at,
  String? locationId,
  String by = 'admin1',
}) => AuditEntry(
  id: id,
  action: action,
  entityPath: 'x/$id',
  locationId: locationId,
  by: by,
  clientAt: at,
  before: {'qty': 3, 'when': at},
  after: const {'qty': 5},
);

Future<void> putAudit(FakeFirebaseFirestore db, AuditEntry a, DateTime at) =>
    put(db, FirestorePaths.audit(a.id), a.toMap(), serverTimes: {'at': at});

Role role(String id, {required List<String> permissions, bool all = false}) =>
    Role(id: id, name: id, permissions: permissions, allLocations: all);

AppUser appUser(
  String uid, {
  String? locationId = 'PTB',
  String roleId = SeedRoles.storeManagerId,
  bool active = true,
  String? name,
}) => AppUser(
  uid: uid,
  name: name ?? 'User $uid',
  email: '$uid@example.com',
  roleId: roleId,
  locationId: locationId,
  active: active,
  createdBy: 'admin1',
);

Location location(String code, {String footer = 'Thank you!'}) => Location(
  code: code,
  name: 'Store $code',
  address: 'Main Road',
  phone: '0000000000',
  overridePinHash: 'c2FsdA==\$aGFzaA==',
  receiptFooter: footer,
  nextDeviceNo: 1,
  active: true,
);

Expense expense(
  String id, {
  required String locationId,
  required String date,
  int amount = 100000,
}) => Expense(
  id: id,
  locationId: locationId,
  category: ExpenseCategory.rent,
  amount: Money(amount),
  date: date,
  note: '',
  createdBy: 'admin1',
);

Future<void> putExpense(FakeFirebaseFirestore db, Expense e) => put(
  db,
  FirestorePaths.expense(e.id),
  e.toMap(),
  serverTimes: {
    'createdAt': DateTime.utc(2026),
    'updatedAt': DateTime.utc(2026),
  },
);
