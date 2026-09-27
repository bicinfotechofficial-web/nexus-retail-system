import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';

import 'plan_fixtures.dart';

Matcher _violation() => throwsA(
  isA<DataFailure>().having(
    (f) => f.reason,
    'reason',
    FailureReason.ruleViolation,
  ),
);

const _millis = 1790397000000; // Fx.now

Expense _stored(ExpenseInput i, String id) => Expense(
  id: id,
  locationId: i.locationId,
  category: i.category,
  amount: i.amount,
  date: i.date,
  note: i.note,
  createdBy: Fx.adminUid,
);

void main() {
  test('Fx.now is the millis the audit IDs use', () {
    expect(Fx.now.millisecondsSinceEpoch, _millis);
  });

  group('saveExpense', () {
    const rent = ExpenseInput(
      locationId: 'PTB',
      category: ExpenseCategory.rent,
      amount: Money(2500000),
      date: '2026-09-01',
      note: ' September rent ',
    );
    const auditPath = 'auditLog/EXP-e1-$_millis';

    test('create: expense, monthly summary naming the audit, audit', () {
      final p = AdminPlans.saveExpense(
        ctx: Fx.admin(),
        expenseId: 'e1',
        input: rent,
      );
      expect(p.plan.paths, [
        'expenses/e1',
        'locations/PTB/monthlySummary/2026-09',
        auditPath,
      ]);
      expect(p.plan.ops.first.kind, WriteKind.create);
      expect(p.plan.ops.first.data, {
        'locationId': 'PTB',
        'category': 'RENT',
        'amount': 2500000,
        'date': '2026-09-01',
        'note': 'September rent',
        'createdBy': Fx.adminUid,
        'createdAt': serverTimestamp,
        'updatedAt': serverTimestamp,
      });
      expect(p.plan.opAt('locations/PTB/monthlySummary/2026-09')!.data, {
        'expenses': const Increment(2500000),
        'byExpenseCategory': {'RENT': const Increment(2500000)},
        'lastWriteRef': auditPath,
      });
      expect(p.plan.opAt(auditPath)!.data, {
        'action': 'EXPENSE_CREATE',
        'entityPath': 'expenses/e1',
        'locationId': 'PTB',
        'before': null,
        'after': {
          'locationId': 'PTB',
          'category': 'RENT',
          'amount': 2500000,
          'date': '2026-09-01',
          'note': 'September rent',
        },
        'reason': null,
        'by': Fx.adminUid,
        'deviceId': null,
        'clientAt': Fx.now,
        'at': serverTimestamp,
      });
    });

    test('edit of the amount in the same month: one delta of new − old', () {
      final p = AdminPlans.saveExpense(
        ctx: Fx.admin(),
        expenseId: 'e1',
        input: const ExpenseInput(
          id: 'e1',
          locationId: 'PTB',
          category: ExpenseCategory.rent,
          amount: Money(2600000),
          date: '2026-09-02',
          note: 'Rent',
        ),
        before: _stored(rent, 'e1'),
      );
      expect(p.plan.paths, [
        'expenses/e1',
        'locations/PTB/monthlySummary/2026-09',
        auditPath,
      ]);
      expect(p.plan.ops.first.kind, WriteKind.update);
      expect(p.plan.ops.first.data, {
        'locationId': 'PTB',
        'category': 'RENT',
        'amount': 2600000,
        'date': '2026-09-02',
        'note': 'Rent',
        'updatedAt': serverTimestamp,
      });
      expect(p.plan.opAt('locations/PTB/monthlySummary/2026-09')!.data, {
        'expenses': const Increment(100000),
        'byExpenseCategory': {'RENT': const Increment(100000)},
        'lastWriteRef': auditPath,
      });
      final audit = p.plan.opAt(auditPath)!.data;
      expect(audit['action'], 'EXPENSE_UPDATE');
      expect((audit['before']! as Map)['amount'], 2500000);
      expect(p.value.createdBy, Fx.adminUid);
    });

    test('edit moving it to another month and location: two deltas', () {
      final p = AdminPlans.saveExpense(
        ctx: Fx.admin(),
        expenseId: 'e1',
        input: const ExpenseInput(
          id: 'e1',
          locationId: 'MNJ',
          category: ExpenseCategory.utilities,
          amount: Money(300000),
          date: '2026-08-31',
          note: 'Power',
        ),
        before: _stored(rent, 'e1'),
      );
      expect(p.plan.paths, [
        'expenses/e1',
        'locations/PTB/monthlySummary/2026-09',
        'locations/MNJ/monthlySummary/2026-08',
        auditPath,
      ]);
      expect(p.plan.opAt('locations/PTB/monthlySummary/2026-09')!.data, {
        'expenses': const Increment(-2500000),
        'byExpenseCategory': {'RENT': const Increment(-2500000)},
        'lastWriteRef': auditPath,
      });
      expect(p.plan.opAt('locations/MNJ/monthlySummary/2026-08')!.data, {
        'expenses': const Increment(300000),
        'byExpenseCategory': {'UTILITIES': const Increment(300000)},
        'lastWriteRef': auditPath,
      });
    });

    test('a category change moves money between categories only', () {
      final p = AdminPlans.saveExpense(
        ctx: Fx.admin(),
        expenseId: 'e1',
        input: const ExpenseInput(
          id: 'e1',
          locationId: 'PTB',
          category: ExpenseCategory.other,
          amount: Money(2500000),
          date: '2026-09-01',
          note: 'x',
        ),
        before: _stored(rent, 'e1'),
      );
      expect(p.plan.opAt('locations/PTB/monthlySummary/2026-09')!.data, {
        'byExpenseCategory': {
          'RENT': const Increment(-2500000),
          'OTHER': const Increment(2500000),
        },
        'lastWriteRef': auditPath,
      });
    });

    test('a note-only edit writes no summary', () {
      final p = AdminPlans.saveExpense(
        ctx: Fx.admin(),
        expenseId: 'e1',
        input: const ExpenseInput(
          id: 'e1',
          locationId: 'PTB',
          category: ExpenseCategory.rent,
          amount: Money(2500000),
          date: '2026-09-01',
          note: 'Renamed',
        ),
        before: _stored(rent, 'e1'),
      );
      expect(p.plan.paths, ['expenses/e1', auditPath]);
    });

    test('refuses a bad ID, amount, date, location or a future date', () {
      ExpenseInput input({
        String loc = 'PTB',
        int amount = 1,
        String date = '2026-09-01',
      }) => ExpenseInput(
        locationId: loc,
        category: ExpenseCategory.other,
        amount: Money(amount),
        date: date,
        note: '',
      );
      for (final (id, i) in [
        ('bad id', input()),
        ('e1', input(amount: -1)),
        ('e1', input(date: '2026-02-30')),
        ('e1', input(date: '2026-09-27')),
        ('e1', input(loc: 'ptb')),
      ]) {
        expect(
          () =>
              AdminPlans.saveExpense(ctx: Fx.admin(), expenseId: id, input: i),
          _violation(),
          reason: '$id ${i.date} ${i.amount.paise} ${i.locationId}',
        );
      }
      expect(
        () => AdminPlans.saveExpense(
          ctx: Fx.admin(),
          expenseId: 'e2',
          input: input(),
          before: _stored(rent, 'e1'),
        ),
        _violation(),
      );
    });
  });

  group('products', () {
    test('suggest: PENDING, no price, scoped to the SM location', () {
      final p = AdminPlans.suggestProduct(
        ctx: Fx.sm(),
        productId: 'p-special',
        name: ' Plum Cake ',
        category: 'Cakes',
        proposedPrice: const Money(45000),
      );
      expect(p.plan.paths, ['products/p-special']);
      expect(p.plan.ops.single.kind, WriteKind.create);
      expect(p.plan.ops.single.data, {
        'name': 'Plum Cake',
        'category': 'Cakes',
        'price': null,
        'proposedPrice': 45000,
        'unit': 'PCS',
        'gstRate': null,
        'scope': 'PTB',
        'status': 'PENDING',
        'recipe': null,
        'sortOrder': 0,
        'createdBy': Fx.smUid,
        'createdAt': serverTimestamp,
        'updatedAt': serverTimestamp,
      });
      expect(
        () => AdminPlans.suggestProduct(
          ctx: Fx.sm(),
          productId: 'p',
          name: 'x',
          category: 'c',
          proposedPrice: Money.zero,
        ),
        _violation(),
      );
    });

    const product = Product(
      id: 'bf1kg',
      name: 'Black Forest 1 kg',
      category: 'Cakes',
      price: Money(60000),
      scope: Product.globalScope,
      status: ProductStatus.active,
      sortOrder: 3,
      createdBy: Fx.adminUid,
    );

    test('save new: create with createdAt, no audit', () {
      final p = AdminPlans.saveProduct(ctx: Fx.admin(), product: product);
      expect(p.plan.paths, ['products/bf1kg']);
      expect(p.plan.ops.single.kind, WriteKind.create);
      expect(p.plan.ops.single.data['createdAt'], serverTimestamp);
      expect(p.plan.ops.single.data['createdBy'], Fx.adminUid);
    });

    test(
      'save edit with a new price: update without createdBy, and PRICE_CHANGE',
      () {
        final edited = Product(
          id: product.id,
          name: product.name,
          category: product.category,
          price: const Money(65000),
          scope: product.scope,
          status: product.status,
          sortOrder: product.sortOrder,
          createdBy: 'someone-else',
        );
        final p = AdminPlans.saveProduct(
          ctx: Fx.admin(),
          product: edited,
          existing: product,
        );
        const audit = 'auditLog/PRICE-bf1kg-$_millis';
        expect(p.plan.paths, ['products/bf1kg', audit]);
        expect(p.plan.ops.first.kind, WriteKind.update);
        expect(p.plan.ops.first.data, {
          'name': 'Black Forest 1 kg',
          'category': 'Cakes',
          'price': 65000,
          'proposedPrice': null,
          'unit': 'PCS',
          'gstRate': null,
          'scope': 'GLOBAL',
          'status': 'ACTIVE',
          'recipe': null,
          'sortOrder': 3,
          'updatedAt': serverTimestamp,
        });
        final a = p.plan.opAt(audit)!.data;
        expect(a['action'], 'PRICE_CHANGE');
        expect(a['entityPath'], 'products/bf1kg');
        expect(a['locationId'], isNull);
        expect(a['before'], {'price': 60000});
        expect(a['after'], {'price': 65000});
      },
    );

    test('save edit without a price change: no audit', () {
      final p = AdminPlans.saveProduct(
        ctx: Fx.admin(),
        product: product,
        existing: product,
      );
      expect(p.plan.paths, ['products/bf1kg']);
    });

    test('save refuses an active product without a price, or a bad ID', () {
      const unpriced = Product(
        id: 'x',
        name: 'X',
        category: 'c',
        scope: 'GLOBAL',
        status: ProductStatus.active,
        sortOrder: 0,
        createdBy: Fx.adminUid,
      );
      expect(
        () => AdminPlans.saveProduct(ctx: Fx.admin(), product: unpriced),
        _violation(),
      );
      const badId = Product(
        id: 'a b',
        name: 'X',
        category: 'c',
        scope: 'GLOBAL',
        status: ProductStatus.inactive,
        sortOrder: 0,
        createdBy: Fx.adminUid,
      );
      expect(
        () => AdminPlans.saveProduct(ctx: Fx.admin(), product: badId),
        _violation(),
      );
    });

    test('approve: ACTIVE at the price, with PRODUCT_APPROVE', () {
      const pending = Product(
        id: 'p-special',
        name: 'Plum Cake',
        category: 'Cakes',
        proposedPrice: Money(45000),
        scope: 'PTB',
        status: ProductStatus.pending,
        sortOrder: 0,
        createdBy: Fx.smUid,
      );
      final p = AdminPlans.approveProduct(
        ctx: Fx.admin(),
        existing: pending,
        price: const Money(48000),
      );
      const audit = 'auditLog/APPROVE-p-special-$_millis';
      expect(p.plan.paths, ['products/p-special', audit]);
      expect(p.plan.ops.first.data, {
        'status': 'ACTIVE',
        'price': 48000,
        'updatedAt': serverTimestamp,
      });
      expect(p.plan.opAt(audit)!.data['before'], {
        'status': 'PENDING',
        'price': null,
        'proposedPrice': 45000,
      });
      expect(p.plan.opAt(audit)!.data['after'], {
        'status': 'ACTIVE',
        'price': 48000,
        'proposedPrice': 45000,
      });
      expect(p.value.isSellableAt('PTB'), isTrue);
      expect(
        () => AdminPlans.approveProduct(
          ctx: Fx.admin(),
          existing: p.value,
          price: const Money(1),
        ),
        _violation(),
      );
    });
  });

  test('raw material: create with active true and createdBy', () {
    final p = AdminPlans.addRawMaterial(
      ctx: Fx.sm(),
      materialId: 'cocoa',
      name: 'Cocoa',
      unit: StockUnit.g,
    );
    expect(p.plan.paths, ['rawMaterials/cocoa']);
    expect(p.plan.ops.single.data, {
      'name': 'Cocoa',
      'unit': 'G',
      'active': true,
      'createdBy': Fx.smUid,
    });
    expect(
      () => AdminPlans.addRawMaterial(
        ctx: Fx.sm(),
        materialId: 'x',
        name: ' ',
        unit: StockUnit.g,
      ),
      _violation(),
    );
  });

  group('locations', () {
    const ktl = Location(
      code: 'KTL',
      name: 'Kottakkal',
      address: 'Main Road',
      phone: '0000000000',
      overridePinHash: '',
      receiptFooter: 'Thank you!',
      nextDeviceNo: 7,
      active: true,
      maxDiscountPct: 10,
    );
    const audit = 'auditLog/KTL-LOC-$_millis';

    test('create writes every field with nextDeviceNo 0 and the hash', () {
      final p = AdminPlans.saveLocation(
        ctx: Fx.admin(),
        location: ktl,
        newPinHash: 'salt\$hash',
      );
      expect(p.plan.paths, ['locations/KTL', audit]);
      expect(p.plan.ops.first.kind, WriteKind.create);
      expect(p.plan.ops.first.data, {
        'code': 'KTL',
        'name': 'Kottakkal',
        'address': 'Main Road',
        'phone': '0000000000',
        'gstin': null,
        'offlineLimitHours': 5,
        'overridePinHash': 'salt\$hash',
        'overrideExtensionHours': 2,
        'maxDiscountPct': 10,
        'receiptFooter': 'Thank you!',
        'nextDeviceNo': 0,
        'active': true,
      });
      final a = p.plan.opAt(audit)!.data;
      expect(a['action'], 'LOCATION_UPDATE');
      expect(a['locationId'], 'KTL');
      expect(a['before'], isNull);
      expect((a['after']! as Map).containsKey('overridePinHash'), isFalse);
    });

    test('create needs a PIN hash', () {
      expect(
        () => AdminPlans.saveLocation(ctx: Fx.admin(), location: ktl),
        _violation(),
      );
    });

    test('edit writes the explicit field list, never nextDeviceNo or code', () {
      final p = AdminPlans.saveLocation(
        ctx: Fx.admin(),
        location: ktl,
        existing: const Location(
          code: 'KTL',
          name: 'Old',
          address: 'Main Road',
          phone: '0000000000',
          overridePinHash: 'old\$hash',
          receiptFooter: 'Thank you!',
          nextDeviceNo: 3,
          active: true,
        ),
      );
      expect(p.plan.ops.first.kind, WriteKind.update);
      expect(p.plan.ops.first.data, {
        'name': 'Kottakkal',
        'address': 'Main Road',
        'phone': '0000000000',
        'gstin': null,
        'offlineLimitHours': 5,
        'overrideExtensionHours': 2,
        'maxDiscountPct': 10,
        'receiptFooter': 'Thank you!',
        'active': true,
      });
      expect(p.value.nextDeviceNo, 3);
      expect(p.value.overridePinHash, 'old\$hash');
      final a = p.plan.opAt(audit)!.data;
      expect((a['before']! as Map)['name'], 'Old');
      expect((a['after']! as Map)['name'], 'Kottakkal');
    });

    test(
      'edit with a new PIN replaces only the hash, and says so in the audit',
      () {
        final p = AdminPlans.saveLocation(
          ctx: Fx.admin(),
          location: ktl,
          existing: ktl,
          newPinHash: 'new\$hash',
        );
        expect(p.plan.ops.first.data['overridePinHash'], 'new\$hash');
        expect(p.plan.ops.first.data.containsKey('nextDeviceNo'), isFalse);
        expect(
          (p.plan.opAt(audit)!.data['after']! as Map)['pinChanged'],
          isTrue,
        );
      },
    );
  });

  group('users', () {
    const sm = AppUser(
      uid: 'sm-ptb',
      name: 'SM',
      email: 'sm@example.test',
      roleId: 'STORE_MANAGER',
      locationId: 'PTB',
      active: true,
      createdBy: Fx.adminUid,
    );

    test(
      'disable: active false and USER_DISABLE {loc}-USER-{uid}-{millis}',
      () {
        final p = AdminPlans.setUserActive(
          ctx: Fx.admin(),
          user: sm,
          active: false,
        );
        const audit = 'auditLog/PTB-USER-sm-ptb-$_millis';
        expect(p.plan.paths, ['users/sm-ptb', audit]);
        expect(p.plan.ops.first.kind, WriteKind.update);
        expect(p.plan.ops.first.data, {'active': false});
        expect(p.plan.opAt(audit)!.data, {
          'action': 'USER_DISABLE',
          'entityPath': 'users/sm-ptb',
          'locationId': 'PTB',
          'before': {'active': true},
          'after': {'active': false},
          'reason': null,
          'by': Fx.adminUid,
          'deviceId': null,
          'clientAt': Fx.now,
          'at': serverTimestamp,
        });
        expect(p.value.active, isFalse);
      },
    );

    test('enable: no audit; nobody changes their own flag', () {
      final p = AdminPlans.setUserActive(
        ctx: Fx.admin(),
        user: sm,
        active: true,
      );
      expect(p.plan.paths, ['users/sm-ptb']);
      expect(
        () => AdminPlans.setUserActive(
          ctx: PlanContext(uid: 'sm-ptb', now: Fx.now),
          user: sm,
          active: false,
        ),
        _violation(),
      );
      expect(PlanAuditIds.userDisable('a1', null, Fx.now), 'USER-a1-$_millis');
    });
  });
}
