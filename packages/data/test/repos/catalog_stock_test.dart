import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';

import 'docs.dart';

void main() {
  final at = DateTime.utc(2026, 9, 1);

  group('FirestoreCatalogRepository', () {
    late FakeFirebaseFirestore db;
    late FirestoreCatalogRepository repo;

    Future<void> putProduct(Product p) => put(
      db,
      FirestorePaths.product(p.id),
      p.toMap(),
      serverTimes: productTimes(at),
    );

    setUp(() async {
      db = FakeFirebaseFirestore();
      repo = FirestoreCatalogRepository(db);
      for (final p in [
        product('global2', sortOrder: 2),
        product('ptbSpecial', scope: 'PTB', sortOrder: 1),
        product('mnjSpecial', scope: 'MNJ', sortOrder: 0),
        product('global3', sortOrder: 3),
        product(
          'pending',
          scope: 'PTB',
          status: ProductStatus.pending,
          price: null,
        ),
        product('inactive', status: ProductStatus.inactive, sortOrder: -1),
        product('unpriced', price: null, sortOrder: 4),
      ]) {
        await putProduct(p);
      }
    });

    test(
      'sellable: active, priced, GLOBAL or this location, by sortOrder',
      () async {
        final ptb = await repo.watchSellable('PTB').first;
        expect(ptb.map((p) => p.id), ['ptbSpecial', 'global2', 'global3']);
        final mnj = await repo.watchSellable('MNJ').first;
        expect(mnj.map((p) => p.id), ['mnjSpecial', 'global2', 'global3']);
        expect(ptb.first.createdAt!.isAtSameMomentAs(at), isTrue);
      },
    );

    test('sellable updates when a product is approved', () async {
      final stream = repo.watchSellable('PTB');
      final seen = <List<String>>[];
      final sub = stream.listen((l) => seen.add([for (final p in l) p.id]));
      await pumpEventQueue();
      await db.doc(FirestorePaths.product('pending')).update({
        'status': 'ACTIVE',
        'price': 45000,
        'sortOrder': 5,
      });
      await pumpEventQueue();
      await sub.cancel();
      expect(seen.last, ['ptbSpecial', 'global2', 'global3', 'pending']);
    });

    test('all products in every status, by sortOrder then name', () async {
      final all = await repo.watchAll().first;
      expect(all.map((p) => p.id), [
        'inactive',
        'mnjSpecial',
        'pending',
        'ptbSpecial',
        'global2',
        'global3',
        'unpriced',
      ]);
    });

    test('pending products only', () async {
      final pending = await repo.watchPending().first;
      expect(pending.map((p) => p.id), ['pending']);
    });

    group('my suggestions (D-038)', () {
      Product suggestion(
        String id, {
        String by = 'sm-ptb',
        String scope = 'PTB',
        ProductStatus status = ProductStatus.pending,
        String? reviewNote,
      }) => Product(
        id: id,
        name: 'Special $id',
        category: 'Cakes',
        proposedPrice: const Money(45000),
        scope: scope,
        status: status,
        sortOrder: 0,
        createdBy: by,
        reviewedBy: status == ProductStatus.pending ? null : 'admin1',
        reviewNote: reviewNote,
      );

      Future<void> putAt(Product p, DateTime created) => put(
        db,
        FirestorePaths.product(p.id),
        p.toMap(),
        serverTimes: {'createdAt': created, 'updatedAt': created},
      );

      setUp(() async {
        await putAt(suggestion('oldest'), at.subtract(const Duration(days: 3)));
        await putAt(
          suggestion(
            'declined',
            status: ProductStatus.inactive,
            reviewNote: 'Too similar to an existing cake',
          ),
          at.subtract(const Duration(days: 2)),
        );
        await putAt(
          suggestion('approved', status: ProductStatus.active),
          at.subtract(const Duration(days: 1)),
        );
        await putAt(suggestion('newest'), at);
        // Not mine: another user at PTB, the same user's other location.
        await putAt(suggestion('theirs', by: 'sm-ptb-2'), at);
        await putAt(suggestion('elsewhere', scope: 'MNJ'), at);
        await putAt(suggestion('global', scope: Product.globalScope), at);
      });

      test('only this user\'s suggestions at this location, any status, '
          'newest first', () async {
        final mine = await repo.watchMySuggestions('PTB', 'sm-ptb').first;
        expect(mine.map((p) => p.id), [
          'newest',
          'approved',
          'declined',
          'oldest',
        ]);
        expect(mine.map((p) => p.status), [
          ProductStatus.pending,
          ProductStatus.active,
          ProductStatus.inactive,
          ProductStatus.pending,
        ]);
        final declined = mine.firstWhere((p) => p.id == 'declined');
        expect(declined.reviewNote, 'Too similar to an existing cake');
        expect(declined.reviewedBy, 'admin1');
      });

      test('another user or location sees only its own', () async {
        expect(
          (await repo.watchMySuggestions('PTB', 'sm-ptb-2').first).map(
            (p) => p.id,
          ),
          ['theirs'],
        );
        expect(
          (await repo.watchMySuggestions('MNJ', 'sm-ptb').first).map(
            (p) => p.id,
          ),
          ['elsewhere'],
        );
        expect(await repo.watchMySuggestions('PTB', 'nobody').first, isEmpty);
      });

      test('follows a decision made after the listener started', () async {
        final seen = <List<ProductStatus>>[];
        final sub = repo
            .watchMySuggestions('PTB', 'sm-ptb')
            .listen((l) => seen.add([for (final p in l) p.status]));
        await pumpEventQueue();
        await db.doc(FirestorePaths.product('newest')).update({
          'status': 'INACTIVE',
          'reviewNote': 'No',
          'reviewedBy': 'admin1',
        });
        await pumpEventQueue();
        await sub.cancel();
        expect(seen.last.first, ProductStatus.inactive);
      });
    });

    test('raw materials by name, inactive included', () async {
      for (final m in [
        const RawMaterial(
          id: 'sugar',
          name: 'Sugar',
          unit: StockUnit.g,
          active: true,
          createdBy: 'sm1',
        ),
        const RawMaterial(
          id: 'cream',
          name: 'cream',
          unit: StockUnit.ml,
          active: false,
          createdBy: 'sm1',
        ),
      ]) {
        await put(db, FirestorePaths.rawMaterial(m.id), m.toMap());
      }
      final ms = await repo.watchRawMaterials().first;
      expect(ms.map((m) => m.id), ['cream', 'sugar']);
      expect(ms.first.unit, StockUnit.ml);
    });
  });

  group('FirestoreStockRepository', () {
    late FakeFirebaseFirestore db;
    late FirestoreStockRepository repo;

    Future<void> putItem(String loc, StockItem s) => put(
      db,
      FirestorePaths.stockItem(loc, s.itemKey),
      s.toMap(),
      serverTimes: {'updatedAt': at},
    );

    setUp(() async {
      db = FakeFirebaseFirestore();
      repo = FirestoreStockRepository(db);
      await putItem('PTB', stockItem('FG_below', qty: 1, lowThreshold: 2));
      await putItem('PTB', stockItem('FG_equal', qty: 2, lowThreshold: 2));
      await putItem('PTB', stockItem('FG_above', qty: 3, lowThreshold: 2));
      await putItem('PTB', stockItem('FG_nothreshold', qty: -4));
      await putItem(
        'PTB',
        stockItem('RM_cream', qty: -500, lowThreshold: 0, kind: StockKind.raw),
      );
      await putItem('MNJ', stockItem('FG_other', qty: 0, lowThreshold: 5));
    });

    test('every stock doc of one location, raw first, then by name', () async {
      final items = await repo.watchStock('PTB').first;
      expect(items.map((s) => s.itemKey), [
        'RM_cream',
        'FG_above',
        'FG_below',
        'FG_equal',
        'FG_nothreshold',
      ]);
      expect(items.first.qty, -500, reason: 'negative stock is kept');
      expect(items.first.updatedAt!.isAtSameMomentAs(at), isTrue);
    });

    test('low stock: at or below the threshold, never without one', () async {
      final low = await repo.watchLowStock('PTB').first;
      expect(low.map((s) => s.itemKey), ['RM_cream', 'FG_below', 'FG_equal']);
    });

    group('movements of a day (D-039)', () {
      Movement movement(
        String id,
        MovementType type,
        int delta,
        DateTime at, {
        String? businessDate,
      }) => Movement(
        id: id,
        type: type,
        lines: [MovementLine(itemKey: 'FG_cake', delta: delta)],
        businessDate: businessDate ?? BusinessDate.of(at),
        clientCreatedAt: at,
        createdBy: 'sm1',
        deviceId: 'D01',
      );

      Future<void> putMovement(String loc, Movement m) => put(
        db,
        FirestorePaths.movement(loc, m.id),
        m.toMap(),
        serverTimes: {'serverCreatedAt': m.clientCreatedAt},
      );

      test('every movement of that day at that location, newest first, '
          'in and out together', () async {
        final morning = ist(2026, 9, 1, 9);
        await putMovement(
          'PTB',
          movement('D01-M000001', MovementType.produce, 5, morning),
        );
        await putMovement(
          'PTB',
          movement(
            'D01-000001',
            MovementType.sale,
            -1,
            morning.add(const Duration(hours: 2)),
          ),
        );
        await putMovement(
          'PTB',
          movement(
            'D02-M000001',
            MovementType.wastageFg,
            -1,
            morning.add(const Duration(hours: 4)),
          ),
        );
        // Another day, and another location.
        await putMovement(
          'PTB',
          movement(
            'D01-M000002',
            MovementType.produce,
            3,
            morning.subtract(const Duration(days: 1)),
          ),
        );
        await putMovement(
          'MNJ',
          movement('D01-M000003', MovementType.produce, 9, morning),
        );
        final day = await repo.watchMovements('PTB', '2026-09-01').first;
        expect(day.map((m) => m.id), [
          'D02-M000001',
          'D01-000001',
          'D01-M000001',
        ]);
        expect(day.map((m) => m.lines.single.delta), [-1, -1, 5]);
        expect(
          day.first.serverCreatedAt!.isAtSameMomentAs(
            day.first.clientCreatedAt,
          ),
          isTrue,
        );
        expect(await repo.watchMovements('PTB', '2026-09-03').first, isEmpty);
      });

      test('a movement made at the same instant sorts by ID, so the order '
          'is stable', () async {
        final t = ist(2026, 9, 1, 9);
        await putMovement(
          'PTB',
          movement('D01-M000001', MovementType.stockIn, 1, t),
        );
        await putMovement(
          'PTB',
          movement('D01-M000002', MovementType.stockIn, 1, t),
        );
        final day = await repo.watchMovements('PTB', '2026-09-01').first;
        expect(day.map((m) => m.id), ['D01-M000002', 'D01-M000001']);
      });
    });

    test('low stock follows increments', () async {
      final seen = <List<String>>[];
      final sub = repo
          .watchLowStock('PTB')
          .listen((l) => seen.add([for (final s in l) s.itemKey]));
      await pumpEventQueue();
      await db.doc(FirestorePaths.stockItem('PTB', 'FG_above')).update({
        'qty': 2,
      });
      await pumpEventQueue();
      await sub.cancel();
      expect(seen.last, ['RM_cream', 'FG_above', 'FG_below', 'FG_equal']);
    });
  });
}
