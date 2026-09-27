// QA-2 (acceptance #1): two devices at one location bill offline at the
// same time, then sync. No duplicate IDs, exact stock, summaries equal the
// bills. PLAN A1-1 and A1-2.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';

import 'support/backend.dart';
import 'support/fixtures.dart';
import 'support/oracle.dart';
import 'support/scenario.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// The i-th bill of a device: overlapping products, now and then a flat
  /// or % discount, every third one split between cash and UPI.
  NewBill billNo(int i, {required bool deviceB}) {
    final p = Fx.products;
    // One line per product (D-024 e): merge repeats.
    final qty = <Product, int>{};
    void add(Product x, int n) => qty[x] = (qty[x] ?? 0) + n;
    add(p[i % p.length], 1 + i % 3);
    add(p[(i + (deviceB ? 2 : 1)) % p.length], 1);
    if (i.isEven) add(Fx.cupcake, 3);
    final cart = [for (final e in qty.entries) Fx.line(e.key, e.value)];
    final discount = switch (i % 5) {
      1 => DiscountInput.flat(const Money.rupees(10)),
      3 => const DiscountInput.percent(5),
      _ => null,
    };
    return paidBill(cart, discount: discount, split: i % 3 == 0);
  }

  test(
    'A1-1: 20 + 20 offline bills at PTB sync with 40 distinct IDs, '
    'exact stock and matching summaries',
    () async {
      final s = await Scenario.open();
      addTearDown(s.close);
      final a = await s.device(Fx.smPtb, label: 'Counter A');
      final b = await s.device(Fx.smPtb, label: 'Counter B');
      expect(a.devices.deviceId, 'D01');
      expect(b.devices.deviceId, 'D02');

      await a.goOffline();
      await b.goOffline();
      final madeA = <Bill>[];
      final madeB = <Bill>[];
      for (var i = 0; i < 20; i++) {
        madeA.add(await a.sales.createBill(billNo(i, deviceB: false)));
        madeB.add(await b.sales.createBill(billNo(i, deviceB: true)));
      }
      // Offline, each device already sees its own bills.
      expect(
        await current(a.salesRepo.watchBills(Fx.ptb, s.today)),
        hasLength(20),
      );

      await syncInOrder([a, b]);

      final server = await expectStockOracle(s.admin, Fx.ptb);
      final ids = server.bills.map((x) => x.id).toList();
      expect(ids, hasLength(40));
      expect(ids.toSet(), hasLength(40), reason: 'no duplicate bill IDs');
      expect(server.bills.map((x) => x.billNo).toSet(), hasLength(40));
      for (final (code, made) in [('D01', madeA), ('D02', madeB)]) {
        expect(
          server.bills.where((x) => x.deviceId == code).map((x) => x.seq),
          unorderedEquals([for (var n = 1; n <= 20; n++) n]),
          reason: '$code numbers its bills 1..20 with no reuse',
        );
        expect(made.map((x) => x.id), [
          for (var n = 1; n <= 20; n++) Ids.billId(code, n),
        ]);
        final device = await s.admin.get(FirestorePaths.device(Fx.ptb, code));
        expect(device?['lastBillSeq'], 20);
      }
      // Every bill has its SALE movement, and nothing else was added.
      expect(
        server.movementsOf(MovementType.sale).map((m) => m.id).toSet(),
        ids.toSet(),
      );
      // Exact stock, spelled out for one item as well as by the oracle.
      final soldPuffs = server.bills
          .expand((x) => x.lines)
          .where((l) => l.productId == Fx.vegPuff.id)
          .fold<int>(0, (n, l) => n + l.qty);
      expect(
        server.qty('FG_${Fx.vegPuff.id}'),
        Fx.opening['FG_${Fx.vegPuff.id}']! - soldPuffs,
      );
      await expectSummaryOracle(s.admin, Fx.ptb, s.today);
      expect(await syncErrorPaths(a), isEmpty);
      expect(await syncErrorPaths(b), isEmpty);
      expect(await current(a.sync.status), isA<Online>());
    },
    skip: backendSkip,
    timeout: scenarioTimeout,
  );

  test(
    'A1-2: both devices sell the last piece offline; both bills stand and '
    'stock goes to -1 (03-SYNC §5)',
    () async {
      final s = await Scenario.open();
      addTearDown(s.close);
      final a = await s.device(Fx.smPtb, label: 'Counter A');
      final b = await s.device(Fx.smPtb, label: 'Counter B');
      final key = 'FG_${Fx.blackForest.id}';

      // Bring Black Forest down to 1 and give it a threshold, online.
      final opening = Fx.opening[key]!;
      await a.sales.createBill(
        paidBill([Fx.line(Fx.blackForest, opening - 1)]),
      );
      await a.stock.setThreshold(key, 0);
      await a.sync.syncNow();
      await b.sync.syncNow();

      await a.goOffline();
      await b.goOffline();
      await a.sales.createBill(paidBill([Fx.line(Fx.blackForest, 1)]));
      await b.sales.createBill(paidBill([Fx.line(Fx.blackForest, 1)]));
      await syncInOrder([a, b]);
      await a.sync.syncNow();

      final server = await expectStockOracle(s.admin, Fx.ptb);
      expect(server.bills, hasLength(3));
      expect(server.qty(key), -1);
      final low = await current(a.stockRepo.watchLowStock(Fx.ptb));
      expect(low.map((i) => i.itemKey), contains(key));
      await expectSummaryOracle(s.admin, Fx.ptb, s.today);
      expect(await syncErrorPaths(a), isEmpty);
      expect(await syncErrorPaths(b), isEmpty);
    },
    skip: backendSkip,
    timeout: scenarioTimeout,
  );
}
