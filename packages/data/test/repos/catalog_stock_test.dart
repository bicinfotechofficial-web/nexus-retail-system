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
