import 'package:nexus_core/nexus_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// fromMap → toMap gives back the same map, minus server-set fields.
void roundTrip<T>(
  String what,
  Map<String, Object?> map,
  T Function(String id, Map<String, Object?> m) fromMap,
  Map<String, Object?> Function(T) toMap, {
  Set<String> serverFields = const {},
}) {
  test('$what round-trips', () {
    final back = toMap(fromMap('id1', map));
    expect(back, {
      for (final e in map.entries)
        if (!serverFields.contains(e.key)) e.key: e.value,
    });
  });
}

void main() {
  final at = DateTime.utc(2026, 9, 25, 10);

  group('round trips', () {
    roundTrip(
      'Role',
      {
        'name': 'Store Manager',
        'permissions': SeedRoles.storeManagerPermissions,
        'allLocations': false,
      },
      Role.fromMap,
      (r) => r.toMap(),
    );

    roundTrip(
      'AppUser',
      {
        'name': 'SM',
        'email': 'sm@example.com',
        'roleId': 'STORE_MANAGER',
        'locationId': 'PTB',
        'active': true,
        'createdBy': 'admin',
        'createdAt': at,
      },
      AppUser.fromMap,
      (u) => u.toMap(),
      serverFields: AppUser.serverTimestampFields,
    );

    roundTrip(
      'Location',
      {
        'code': 'PTB',
        'name': 'Pattambi',
        'address': 'Main Road',
        'phone': '0000',
        'gstin': null,
        'offlineLimitHours': 5,
        'overridePinHash': 'salt\$hash',
        'overrideExtensionHours': 2,
        'maxDiscountPct': 15,
        'receiptFooter': 'Thank you!',
        'nextDeviceNo': 3,
        'active': true,
      },
      Location.fromMap,
      (l) => l.toMap(),
    );

    roundTrip(
      'Device',
      {
        'code': 'D01',
        'label': 'Counter 1',
        'registeredBy': 'u1',
        'registeredAt': at,
        'lastSeenAt': at,
        'lastBillSeq': 42,
        'lastMovementSeq': 7,
        'lastReturnSeq': 1,
        'retired': false,
      },
      Device.fromMap,
      (d) => d.toMap(),
      serverFields: Device.serverTimestampFields,
    );

    roundTrip(
      'RawMaterial',
      {'name': 'Cake mix', 'unit': 'G', 'active': true, 'createdBy': 'u1'},
      RawMaterial.fromMap,
      (m) => m.toMap(),
    );

    roundTrip(
      'Product',
      {
        'name': 'Black Forest 1 kg',
        'category': 'Cakes',
        'price': 90000,
        'proposedPrice': null,
        'unit': 'PCS',
        'gstRate': null,
        'scope': 'GLOBAL',
        'status': 'ACTIVE',
        'recipe': [
          {'materialId': 'mix', 'qty': 1000},
        ],
        'sortOrder': 1,
        'createdBy': 'u1',
        'createdAt': at,
        'updatedAt': at,
      },
      Product.fromMap,
      (p) => p.toMap(),
      serverFields: Product.serverTimestampFields,
    );

    roundTrip(
      'StockItem',
      {
        'kind': 'FINISHED',
        'refId': 'bf1kg',
        'name': 'Black Forest 1 kg',
        'unit': 'PCS',
        'qty': -2,
        'lowThreshold': 3,
        'lastMovementId': 'D01-000001',
        'updatedAt': at,
      },
      StockItem.fromMap,
      (s) => s.toMap(),
      serverFields: StockItem.serverTimestampFields,
    );

    roundTrip(
      'Movement (ADJUST)',
      {
        'type': 'ADJUST',
        'lines': [
          {'itemKey': 'RM_mix', 'delta': -50, 'before': 1050, 'after': 1000},
          {'itemKey': 'FG_bf', 'delta': 2},
        ],
        'reason': 'count',
        'note': null,
        'refId': null,
        'businessDate': '2026-09-25',
        'clientCreatedAt': at,
        'serverCreatedAt': at,
        'createdBy': 'u1',
        'deviceId': 'D01',
      },
      Movement.fromMap,
      (m) => m.toMap(),
      serverFields: Movement.serverTimestampFields,
    );

    final billMap = {
      'billNo': 'PTB-D01-000001',
      'deviceId': 'D01',
      'seq': 1,
      'lines': [
        {
          'productId': 'bf',
          'name': 'BF',
          'qty': 2,
          'unitPrice': 45000,
          'lineTotal': 90000,
        },
      ],
      'subtotal': 90000,
      'discount': {'type': 'PCT', 'value': 10, 'amount': 9000},
      'taxableValue': 81000,
      'taxLines': [
        {'rate': 5, 'taxable': 81000, 'cgst': 2025, 'sgst': 2025},
      ],
      'roundOff': 0,
      'total': 81000,
      'payments': [
        {'mode': 'CASH', 'amount': 1000},
        {'mode': 'UPI', 'amount': 80000, 'ref': 'UTR1'},
      ],
      'cashTendered': 2000,
      'status': 'CANCELLED',
      'cancel': {
        'reason': 'wrong item',
        'by': 'u1',
        'at': at,
        'businessDate': '2026-09-25',
      },
      'returnedQty': {'bf': 1},
      'soldQty': {'bf': 2},
      'lastReturnId': 'D01-R000001',
      'servedBy': {'uid': 'u1', 'name': 'SM'},
      'businessDate': '2026-09-25',
      'clientCreatedAt': at,
      'serverCreatedAt': at,
      'createdBy': 'u1',
    };
    roundTrip(
      'Bill',
      billMap,
      Bill.fromMap,
      (b) => b.toMap(),
      serverFields: Bill.serverTimestampFields,
    );

    roundTrip(
      'SaleReturn',
      {
        'billId': 'D01-000001',
        'billNo': 'PTB-D01-000001',
        'lines': [
          {'productId': 'bf', 'name': 'BF', 'qty': 1, 'amount': 40500},
        ],
        'refundTotal': 40500,
        'refunds': [
          {'mode': 'CASH', 'amount': 40500},
        ],
        'reason': 'damaged',
        'businessDate': '2026-09-26',
        'createdBy': 'u1',
        'deviceId': 'D01',
        'clientCreatedAt': at,
        'serverCreatedAt': at,
      },
      SaleReturn.fromMap,
      (r) => r.toMap(),
      serverFields: SaleReturn.serverTimestampFields,
    );

    roundTrip(
      'Summary',
      {
        'billCount': 2,
        'cancelCount': 1,
        'returnCount': 1,
        'grossSales': 100000,
        'discounts': 5000,
        'roundOff': -20,
        'netSales': 94980,
        'returns': 1000,
        'cancelled': 2000,
        'byMode': {'CASH': 50000, 'UPI': 41980},
        'byProduct': {
          'bf': {'qty': 2, 'amount': 90000},
        },
        'expenses': 700,
        'byExpenseCategory': {'RENT': 700},
        'lastWriteRef': 'locations/PTB/bills/D01-000002',
      },
      Summary.fromMap,
      (s) => s.toMap(),
    );

    roundTrip(
      'Expense',
      {
        'locationId': 'PTB',
        'category': 'UTILITIES',
        'amount': 150000,
        'date': '2026-09-01',
        'note': 'power',
        'createdBy': 'admin',
        'createdAt': at,
        'updatedAt': at,
      },
      Expense.fromMap,
      (e) => e.toMap(),
      serverFields: Expense.serverTimestampFields,
    );

    roundTrip(
      'AuditEntry',
      {
        'action': 'STOCK_ADJUST',
        'entityPath': 'locations/PTB/movements/D01-M000001',
        'locationId': 'PTB',
        'before': {'qty': 10},
        'after': {'qty': 8},
        'reason': 'count',
        'by': 'u1',
        'deviceId': 'D01',
        'at': at,
        'clientAt': at,
      },
      AuditEntry.fromMap,
      (a) => a.toMap(),
      serverFields: AuditEntry.serverTimestampFields,
    );
  });

  group('defaults and derived values', () {
    test('Location defaults offline limit, extension and no cap', () {
      final l = Location.fromMap('PTB', {
        'code': 'PTB',
        'name': 'n',
        'address': 'a',
        'phone': 'p',
        'overridePinHash': 'h',
        'receiptFooter': 'f',
        'nextDeviceNo': 1,
        'active': true,
      });
      expect(l.offlineLimitHours, 5);
      expect(l.overrideExtensionHours, 2);
      expect(l.maxDiscountPct, isNull);
    });

    test('an empty summary reads as zeros', () {
      final s = Summary.fromMap('2026-09-25', {});
      expect(s.billCount, 0);
      expect(s.netRevenue, Money.zero);
      expect(s.byProduct, isEmpty);
    });

    test('Device defaults', () {
      final d = Device.fromMap('D01', {
        'code': 'D01',
        'label': 'x',
        'registeredBy': 'u',
      });
      expect(d.lastBillSeq, 0);
      expect(d.lastMovementSeq, 0);
      expect(d.lastReturnSeq, 0);
      expect(d.retired, isFalse);
    });

    test('Role.can', () {
      const r = Role(
        id: 'X',
        name: 'x',
        permissions: [Permission.billCreate],
        allLocations: false,
      );
      expect(r.can(Permission.billCreate), isTrue);
      expect(r.can(Permission.billCancel), isFalse);
      expect(
        Role.fromMap('X', {
          'name': 'x',
          'permissions': <String>[],
        }).allLocations,
        isFalse,
      );
    });

    test('StockItem.isLow', () {
      StockItem s(int qty, int? low) => StockItem(
        itemKey: 'FG_x',
        kind: StockKind.finished,
        refId: 'x',
        name: 'x',
        unit: StockUnit.pcs,
        qty: qty,
        lowThreshold: low,
      );
      expect(s(3, 3).isLow, isTrue);
      expect(s(4, 3).isLow, isFalse);
      expect(s(-1, null).isLow, isFalse);
    });

    test('Product.isSellableAt', () {
      Product p({
        Money? price,
        String scope = 'GLOBAL',
        ProductStatus status = ProductStatus.active,
      }) => Product(
        id: 'x',
        name: 'x',
        category: 'c',
        scope: scope,
        status: status,
        sortOrder: 0,
        createdBy: 'u',
        price: price,
      );
      expect(p(price: const Money(100)).isSellableAt('PTB'), isTrue);
      expect(
        p(price: const Money(100), scope: 'PTB').isSellableAt('PTB'),
        isTrue,
      );
      expect(
        p(price: const Money(100), scope: 'MNJ').isSellableAt('PTB'),
        isFalse,
      );
      expect(p().isSellableAt('PTB'), isFalse);
      expect(
        p(
          price: const Money(1),
          status: ProductStatus.pending,
        ).isSellableAt('PTB'),
        isFalse,
      );
    });

    test('Bill.soldQty is derived from the lines', () {
      final b = billFrom(
        BillCalculator.compute([line('A', 2, 100), line('B', 1, 50)]),
      );
      expect(b.soldQty, {'A': 2, 'B': 1});
      expect(b.toMap()['soldQty'], {'A': 2, 'B': 1});
      expect(b.lastReturnId, isNull);
    });

    test('Bill.discountAmount is zero without a discount', () {
      final b = billFrom(BillCalculator.compute([line('A', 1, 100)]));
      expect(b.discountAmount, Money.zero);
      expect(b.toMap()['discount'], isNull);
      expect(Bill.fromMap(b.id, b.toMap()).cancel, isNull);
    });

    test('TaxLine.tax', () {
      const t = TaxLine(
        rate: 5,
        taxable: Money(100),
        cgst: Money(3),
        sgst: Money(2),
      );
      expect(t.tax, const Money(5));
    });
  });

  group('strict reading', () {
    test('a wrong type names the document and field', () {
      expect(
        () => Bill.fromMap('D01-000009', {'billNo': 7}),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            allOf(contains('bill D01-000009'), contains('"billNo"')),
          ),
        ),
      );
    });

    test('an unknown enum value is refused', () {
      expect(
        () => RawMaterial.fromMap('m', {
          'name': 'x',
          'unit': 'KG',
          'active': true,
          'createdBy': 'u',
        }),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'm',
            contains('"unit"'),
          ),
        ),
      );
    });

    final r = MapReader({
      'n': null,
      's': 'x',
      'i': 1,
      'b': true,
      'l': [1],
      'lm': [1],
      'm': {'k': 'v'},
      'im': {'a': 'b'},
      'om': {'a': 1},
      'd': 'not a date',
    }, 'ctx');
    final bad = <String, void Function()>{
      'string': () => r.string('i'),
      'stringOrNull': () => r.stringOrNull('i'),
      'integer': () => r.integer('s'),
      'integerOrNull': () => r.integerOrNull('s'),
      'boolean': () => r.boolean('s'),
      'booleanOr': () => r.booleanOr('s', false),
      'dateTime': () => r.dateTime('d'),
      'dateTimeOrNull': () => r.dateTimeOrNull('d'),
      'stringList (not a list)': () => r.stringList('s'),
      'stringList (bad item)': () => r.stringList('l'),
      'map': () => r.map('s'),
      'mapOrNull': () => r.mapOrNull('s'),
      'objects (not a list)': () => r.objects('s', (x) => x),
      'objects (bad item)': () => r.objects('lm', (x) => x),
      'intMap (not a map)': () => r.intMap('s'),
      'intMap (bad value)': () => r.intMap('im'),
      'objectMap (not a map)': () => r.objectMap('s', (x) => x),
      'objectMap (bad value)': () => r.objectMap('om', (x) => x),
    };
    for (final e in bad.entries) {
      test('MapReader.${e.key} refuses a bad value', () {
        expect(e.value, throwsFormatException);
      });
    }

    test('MapReader nullable and defaulted reads', () {
      expect(r.stringOrNull('n'), isNull);
      expect(r.integerOrNull('n'), isNull);
      expect(r.integerOr('n', 9), 9);
      expect(r.booleanOr('n', true), isTrue);
      expect(r.booleanOr('b', false), isTrue);
      expect(r.dateTimeOrNull('n'), isNull);
      expect(r.mapOrNull('n'), isNull);
      expect(r.childOrNull('n'), isNull);
      expect(r.childOrNull('m')!.string('k'), 'v');
      expect(r.objectsOrNull('n', (x) => x), isNull);
      expect(r.intMap('n'), isEmpty);
      expect(r.objectMap('n', (x) => x), isEmpty);
    });
  });

  group('enums', () {
    test('every enum round-trips through its wire name', () {
      for (final v in PaymentMode.values) {
        expect(PaymentMode.fromWire(v.wire), v);
      }
      for (final v in BillStatus.values) {
        expect(BillStatus.fromWire(v.wire), v);
      }
      for (final v in DiscountType.values) {
        expect(DiscountType.fromWire(v.wire), v);
      }
      for (final v in MovementType.values) {
        expect(MovementType.fromWire(v.wire), v);
      }
      for (final v in StockKind.values) {
        expect(StockKind.fromWire(v.wire), v);
      }
      for (final v in StockUnit.values) {
        expect(StockUnit.fromWire(v.wire), v);
      }
      for (final v in ProductStatus.values) {
        expect(ProductStatus.fromWire(v.wire), v);
      }
      for (final v in ExpenseCategory.values) {
        expect(ExpenseCategory.fromWire(v.wire), v);
      }
      for (final v in AuditAction.values) {
        expect(AuditAction.fromWire(v.wire), v);
      }
    });

    test('wire names are UPPER_SNAKE', () {
      final all = [
        ...PaymentMode.values.map((v) => v.wire),
        ...MovementType.values.map((v) => v.wire),
        ...AuditAction.values.map((v) => v.wire),
      ];
      for (final w in all) {
        expect(w, matches(RegExp(r'^[A-Z]+(_[A-Z]+)*$')));
      }
    });

    test('unknown wire names throw', () {
      expect(() => PaymentMode.fromWire('cash'), throwsFormatException);
    });

    test('which movements need a reason or an audit doc', () {
      expect(
        MovementType.values.where((t) => t.requiresReason).map((t) => t.wire),
        unorderedEquals(['WASTAGE_RAW', 'WASTAGE_FG', 'ADJUST', 'CANCEL']),
      );
      expect(
        MovementType.values.where((t) => t.requiresAudit).map((t) => t.wire),
        unorderedEquals([
          'WASTAGE_RAW',
          'WASTAGE_FG',
          'ADJUST',
          'CANCEL',
          'RETURN',
        ]),
      );
    });
  });
}
