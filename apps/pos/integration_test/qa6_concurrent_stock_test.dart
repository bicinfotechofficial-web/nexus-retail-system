// QA-6: PRODUCE, SALE and ADJUST on the same items from two offline
// devices, synced in either order. Increments merge, nothing is lost, and
// every stock doc equals the sum of its movements (03-SYNC §5, D-005).
// PLAN S5-4, with S5-2's adjust-against-the-local-view arithmetic.

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

  const cake = 'FG_black-forest-1kg';
  const flour = 'RM_flour';
  const eggs = 'RM_eggs';

  for (final aFirst in [true, false]) {
    test(
      'S5-4: concurrent PRODUCE + SALE + ADJUST offline, '
      '${aFirst ? 'A' : 'B'} syncs first: every increment lands',
      () async {
        final s = await Scenario.open();
        addTearDown(s.close);
        final a = await s.device(Fx.smPtb, label: 'Counter A');
        final b = await s.device(Fx.smPtb, label: 'Counter B');
        final open = Fx.opening;

        await a.goOffline();
        await b.goOffline();

        // A bakes 4 cakes from 2 kg flour and 12 eggs.
        final produce = await a.stock.produce(
          consumed: const [
            StockLineInput(itemKey: flour, qty: 2000),
            StockLineInput(itemKey: eggs, qty: 12),
          ],
          produced: const [StockLineInput(itemKey: cake, qty: 4)],
        );
        // B sells 3 cakes it believes are there.
        final sale = await b.sales.createBill(
          paidBill([Fx.line(Fx.blackForest, 3)]),
        );
        // A counts the flour: its local view is 10000 − 2000 = 8000, the
        // shelf holds 7500, so it records −500.
        final adjustA = await a.stock.adjust(
          itemKey: flour,
          countedQty: 7500,
          reason: 'Monthly count',
        );
        // B counts the cakes: its local view is 10 − 3 = 7, it finds 6, so
        // −1, without knowing about A's 4 new cakes.
        final adjustB = await b.stock.adjust(
          itemKey: cake,
          countedQty: 6,
          reason: 'Evening count',
        );

        await syncInOrder(aFirst ? [a, b] : [b, a]);
        await a.sync.syncNow();

        final server = await expectStockOracle(s.admin, Fx.ptb);
        expect(server.qty(flour), open[flour]! - 2000 - 500);
        expect(server.qty(eggs), open[eggs]! - 12);
        expect(
          server.qty(cake),
          open[cake]! + 4 - 3 - 1,
          reason:
              'the adjust is off by the concurrent produce, as 03-SYNC §5 '
              'accepts; no increment is lost',
        );

        // The movements carry what each device saw.
        final byId = {for (final m in server.movements) m.id: m};
        final p = byId[produce.id]!;
        expect(p.type, MovementType.produce);
        expect(
          {for (final l in p.lines) l.itemKey: l.delta},
          {flour: -2000, eggs: -12, cake: 4},
        );
        expect(byId[sale.id]!.type, MovementType.sale);
        final adjA = byId[adjustA.id]!.lines.single;
        expect(
          (adjA.itemKey, adjA.before, adjA.after, adjA.delta),
          (flour, 8000, 7500, -500),
        );
        final adjB = byId[adjustB.id]!.lines.single;
        expect(
          (adjB.itemKey, adjB.before, adjB.after, adjB.delta),
          (cake, 7, 6, -1),
        );
        for (final m in [adjustA, adjustB]) {
          expect(
            await s.admin.get(FirestorePaths.audit(Ids.auditId(Fx.ptb, m.id))),
            isNotNull,
            reason: 'STOCK_ADJUST audit for ${m.id} (04 #10, D-028)',
          );
        }
        // Movement IDs come from each device's own counter.
        expect(produce.id, Ids.movementId('D01', 1));
        expect(adjustA.id, Ids.movementId('D01', 2));
        expect(adjustB.id, Ids.movementId('D02', 1));
        final d1 = await s.admin.get(FirestorePaths.device(Fx.ptb, 'D01'));
        final d2 = await s.admin.get(FirestorePaths.device(Fx.ptb, 'D02'));
        expect(d1?['lastMovementSeq'], 2);
        expect(d2?['lastMovementSeq'], 1);

        // Both devices converge on the server's numbers.
        for (final d in [a, b]) {
          final local = await current(d.stockRepo.watchStock(Fx.ptb));
          expect(
            {for (final i in local) i.itemKey: i.qty},
            {for (final e in server.stock.entries) e.key: e.value.qty},
          );
        }
        await expectSummaryOracle(s.admin, Fx.ptb, s.today);
        expect(await syncErrorPaths(a), isEmpty);
        expect(await syncErrorPaths(b), isEmpty);
      },
      skip: backendSkip,
      timeout: scenarioTimeout,
    );
  }
}
