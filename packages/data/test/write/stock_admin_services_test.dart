import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';

import 'support.dart';

void main() {
  group('StockService', () {
    late Harness h;

    setUp(() {
      h = Harness();
      h.reads.materials['flour'] = const RawMaterial(
        id: 'flour',
        name: 'Flour',
        unit: StockUnit.g,
        active: true,
        createdBy: 'admin',
      );
      h.reads.products['cake'] = Product(
        id: 'cake',
        name: 'Chocolate Cake 1 kg',
        category: 'Cakes',
        scope: Product.globalScope,
        status: ProductStatus.active,
        sortOrder: 0,
        createdBy: 'admin',
        price: const Money(65000),
      );
    });

    test('stock in: identity from the catalog, numbered D01-M000001, the '
        'movement ledgered', () async {
      final m = await h.stock.stockIn(const [
        StockLineInput(itemKey: 'RM_flour', qty: 2500),
      ], note: 'Supplier');
      expect(m.id, 'D01-M000001');
      final plan = h.committer.plans.single;
      final stock = plan.opAt('locations/PTB/stock/RM_flour')!;
      expect(stock.kind, WriteKind.setMerge);
      expect(stock.data['name'], 'Flour');
      expect(stock.data['unit'], 'G');
      expect(stock.data['qty'], const Increment(2500));
      expect(h.ledgerPaths, ['locations/PTB/movements/D01-M000001']);
      expect(h.ledger.entries.single.label, contains('RM_flour +2500'));
    });

    test('an item only known from its stock doc still works; an unknown '
        'item or key is refused before a number is used', () async {
      h.reads.stock['locations/PTB/stock/RM_sugar'] = const StockItem(
        itemKey: 'RM_sugar',
        kind: StockKind.raw,
        refId: 'sugar',
        name: 'Sugar',
        unit: StockUnit.g,
        qty: 10,
      );
      await h.stock.stockOutRaw(const [
        StockLineInput(itemKey: 'RM_sugar', qty: 5),
      ], reason: 'Staff tea');
      await expectLater(
        h.stock.stockIn(const [StockLineInput(itemKey: 'RM_salt', qty: 1)]),
        failsWith(FailureReason.notFound),
      );
      await expectLater(
        h.stock.stockIn(const [StockLineInput(itemKey: 'XX_salt', qty: 1)]),
        failsWith(FailureReason.ruleViolation),
      );
      await expectLater(
        h.stock.stockIn(const [StockLineInput(itemKey: 'RM_flour', qty: 0)]),
        failsWith(FailureReason.ruleViolation),
      );
      expect(h.counters.current('D01', SeqKind.movement), 1);
    });

    test('wastage and produce write their plans; wastage is audited, and '
        'the audit is not ledgered', () async {
      await h.stock.wastage(StockKind.finished, const [
        StockLineInput(itemKey: 'FG_cake', qty: 1),
      ], reason: 'Dropped');
      expect(
        h.committer.plans.last.paths,
        contains('auditLog/PTB-D01-M000001'),
      );
      await h.stock.produce(
        consumed: const [StockLineInput(itemKey: 'RM_flour', qty: 1000)],
        produced: const [StockLineInput(itemKey: 'FG_cake', qty: 2)],
      );
      expect(h.ledgerPaths, [
        'locations/PTB/movements/D01-M000001',
        'locations/PTB/movements/D01-M000002',
      ]);
    });

    test('adjust records counted − local qty from the device view', () async {
      h.reads.stock['locations/PTB/stock/FG_cake'] = const StockItem(
        itemKey: 'FG_cake',
        kind: StockKind.finished,
        refId: 'cake',
        name: 'Old name',
        unit: StockUnit.pcs,
        qty: 7,
      );
      final m = await h.stock.adjust(
        itemKey: 'FG_cake',
        countedQty: 4,
        reason: 'Count',
      );
      expect(m.lines.single.delta, -3);
      expect((m.lines.single.before, m.lines.single.after), (7, 4));
      final op = h.committer.plans.single.opAt('locations/PTB/stock/FG_cake')!;
      expect(op.data['qty'], const Increment(-3));
      expect(op.data['name'], 'Chocolate Cake 1 kg', reason: 'fresh name');
    });

    test('adjust of an item without a stock doc counts from 0', () async {
      final m = await h.stock.adjust(
        itemKey: 'RM_flour',
        countedQty: 300,
        reason: 'First count',
      );
      expect(m.lines.single.delta, 300);
    });

    test('each operation checks its own permission first', () async {
      h.session = smSession(except: [Permission.stockMove]);
      await expectLater(
        h.stock.stockIn(const [StockLineInput(itemKey: 'RM_flour', qty: 1)]),
        failsWith(FailureReason.notPermitted),
      );
      await expectLater(
        h.stock.produce(consumed: const [], produced: const []),
        failsWith(FailureReason.notPermitted),
      );
      // stock.adjust alone still adjusts (QA-029).
      await h.stock.adjust(itemKey: 'RM_flour', countedQty: 1, reason: 'x');
      h.session = smSession(except: [Permission.stockAdjust]);
      await expectLater(
        h.stock.adjust(itemKey: 'RM_flour', countedQty: 1, reason: 'x'),
        failsWith(FailureReason.notPermitted),
      );
      h.session = smSession(except: [Permission.stockThreshold]);
      await expectLater(
        h.stock.setThreshold('RM_flour', 100),
        failsWith(FailureReason.notPermitted),
      );
      expect(h.committer.plans, hasLength(1));
    });

    test('setThreshold merges the threshold and ledgers nothing', () async {
      await h.stock.setThreshold('RM_flour', 500);
      final op = h.committer.plans.single.ops.single;
      expect(op.kind, WriteKind.setMerge);
      expect(op.data['lowThreshold'], 500);
      expect(op.data.containsKey('qty'), isFalse);
      expect(h.ledger.entries, isEmpty);
      expect(h.counters.current('D01', SeqKind.movement), 0);
    });
  });

  group('CatalogService', () {
    test('a Store Manager suggests a local special, ledgered', () async {
      final h = Harness();
      final catalog = FirestoreCatalogService(h.env);
      final p = await catalog.suggest(
        name: ' Plum Cake ',
        category: 'Cakes',
        proposedPrice: const Money(45000),
      );
      expect(p.status, ProductStatus.pending);
      expect(p.scope, 'PTB');
      expect(Ids.isSafeKey(p.id), isTrue);
      expect(h.ledgerPaths, ['products/${p.id}']);
    });

    test('save creates or edits; approve needs a PENDING product; both need '
        'catalog.manage', () async {
      final h = Harness(session: adminSession)..deviceId = null;
      final catalog = FirestoreCatalogService(h.env);
      final bf = Product(
        id: 'bf1kg',
        name: 'Black Forest 1 kg',
        category: 'Cakes',
        scope: Product.globalScope,
        status: ProductStatus.active,
        sortOrder: 1,
        createdBy: 'admin',
        price: const Money(60000),
      );
      await catalog.save(bf);
      expect(h.committer.plans.last.ops.single.kind, WriteKind.create);
      h.reads.products['bf1kg'] = bf;
      await catalog.save(
        Product(
          id: bf.id,
          name: bf.name,
          category: bf.category,
          scope: bf.scope,
          status: bf.status,
          sortOrder: bf.sortOrder,
          createdBy: bf.createdBy,
          price: const Money(65000),
        ),
      );
      expect(
        h.committer.plans.last.paths.last,
        startsWith('auditLog/PRICE-bf1kg-'),
      );
      await expectLater(
        catalog.approve(productId: 'nope', price: const Money(1)),
        failsWith(FailureReason.notFound),
      );
      await expectLater(
        catalog.approve(productId: 'bf1kg', price: const Money(1)),
        failsWith(FailureReason.ruleViolation),
      );

      h.session = smSession();
      await expectLater(
        catalog.save(bf),
        failsWith(FailureReason.notPermitted),
      );
      await expectLater(
        catalog.approve(productId: 'bf1kg', price: const Money(1)),
        failsWith(FailureReason.notPermitted),
      );
    });

    test('addRawMaterial needs rawMaterial.create', () async {
      final h = Harness();
      final catalog = FirestoreCatalogService(h.env);
      final m = await catalog.addRawMaterial(name: 'Cocoa', unit: StockUnit.g);
      expect(h.ledgerPaths, ['rawMaterials/${m.id}']);
      h.session = smSession(except: [Permission.rawMaterialCreate]);
      await expectLater(
        catalog.addRawMaterial(name: 'Salt', unit: StockUnit.g),
        failsWith(FailureReason.notPermitted),
      );
    });
  });

  group('ExpenseService', () {
    test('create and edit with expense.manage at the location', () async {
      final h = Harness(session: adminSession)..deviceId = null;
      final expenses = FirestoreExpenseService(h.env);
      final e = await expenses.save(
        const ExpenseInput(
          locationId: 'PTB',
          category: ExpenseCategory.rent,
          amount: Money(1000000),
          date: '2026-09-01',
          note: 'September',
        ),
      );
      expect(h.ledgerPaths, ['expenses/${e.id}']);
      await expectLater(
        expenses.save(
          const ExpenseInput(
            id: 'missing',
            locationId: 'PTB',
            category: ExpenseCategory.rent,
            amount: Money(1),
            date: '2026-09-01',
            note: '',
          ),
        ),
        failsWith(FailureReason.notFound),
      );
      h.reads.expenses[e.id] = e;
      await expenses.save(
        ExpenseInput(
          id: e.id,
          locationId: 'PTB',
          category: ExpenseCategory.rent,
          amount: const Money(1100000),
          date: '2026-09-01',
          note: 'September',
        ),
      );
      expect(
        h.committer.plans.last.opAt('expenses/${e.id}')!.kind,
        WriteKind.update,
      );

      h.session = smSession();
      await expectLater(
        expenses.save(
          const ExpenseInput(
            locationId: 'PTB',
            category: ExpenseCategory.other,
            amount: Money(1),
            date: '2026-09-01',
            note: '',
          ),
        ),
        failsWith(FailureReason.notPermitted),
      );
    });
  });

  group('LocationService', () {
    test('edits without a PIN keep the hash and never write nextDeviceNo; a '
        'short PIN is refused; a Store Manager is not permitted', () async {
      final h = Harness(session: adminSession)..deviceId = null;
      final locations = FirestoreLocationService(h.env);
      h.reads.locations['PTB'] = ptb();
      final saved = await locations.save(ptb(limitHours: 6));
      expect(saved.overridePinHash, ptb().overridePinHash);
      final update = h.committer.plans.single.opAt('locations/PTB')!;
      expect(update.kind, WriteKind.update);
      expect(update.data.containsKey('nextDeviceNo'), isFalse);
      expect(update.data.containsKey('overridePinHash'), isFalse);
      expect(update.data['offlineLimitHours'], 6);

      await expectLater(
        locations.save(ptb(), newPin: '1234'),
        failsWith(FailureReason.ruleViolation),
      );
      h.session = smSession();
      await expectLater(
        locations.save(ptb()),
        failsWith(FailureReason.notPermitted),
      );
      expect(h.committer.plans, hasLength(1));
    });

    test('a new PIN is hashed with PBKDF2 and verifies', () async {
      final h = Harness(session: adminSession)..deviceId = null;
      final saved = await FirestoreLocationService(
        h.env,
      ).save(ptb(), newPin: '24681357');
      expect(
        h.committer.plans.single.opAt('locations/PTB')!.kind,
        WriteKind.create,
      );
      expect(
        await PinHasher().verify('24681357', saved.overridePinHash),
        isTrue,
      );
    });
  });
}
