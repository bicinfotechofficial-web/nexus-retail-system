// QA-3 (acceptance #2): a kill or reboot mid-bill, or the same batch
// submitted twice, never duplicates a bill or a stock deduction. PLAN A2-2,
// A2-3, A2-4. (A2-1, a kill between allocating the number and building the
// batch, is BE-8's counter-store unit test: nothing reaches Firestore.)

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

  final cart = [Fx.line(Fx.blackForest, 1), Fx.line(Fx.vegPuff, 2)];

  test(
    'A2-2: kill after the local commit, before sync: the bill survives the '
    'restart and lands once',
    () async {
      final s = await Scenario.open();
      addTearDown(s.close);
      var a = await s.device(Fx.smPtb, label: 'Counter A');

      await a.goOffline();
      final bill = await a.sales.createBill(paidBill(cart));
      a = s.track(await a.restart());

      // Still offline after the restart, and the bill is still there.
      final local = await current(a.salesRepo.watchBills(Fx.ptb, s.today));
      expect(local.map((b) => b.id), [bill.id]);

      await syncInOrder([a]);
      final server = await expectStockOracle(s.admin, Fx.ptb);
      expect(server.bills.map((b) => b.id), [bill.id]);
      expect(server.movementsOf(MovementType.sale).map((m) => m.id), [bill.id]);
      expect(
        server.qty('FG_${Fx.vegPuff.id}'),
        Fx.opening['FG_${Fx.vegPuff.id}']! - 2,
      );
      await expectSummaryOracle(s.admin, Fx.ptb, s.today);
      expect(await syncErrorPaths(a), isEmpty);

      // The counter survived too: the next bill doesn't reuse the number.
      final next = await a.sales.createBill(paidBill(cart));
      expect(next.seq, bill.seq + 1);
    },
    skip: backendSkip,
    timeout: scenarioTimeout,
  );

  test(
    'A2-3: restart with 10 bills, a cancel and 2 returns queued: all 13 land '
    'exactly once',
    () async {
      final s = await Scenario.open();
      addTearDown(s.close);
      var a = await s.device(Fx.smPtb, label: 'Counter A');

      await a.goOffline();
      List<CartLine> cartNo(int i) {
        final main = Fx.products[i % Fx.products.length];
        final extra = identical(main, Fx.cookie) ? Fx.plumCake : Fx.cookie;
        return [Fx.line(main, 1 + i % 2), Fx.line(extra, 2)];
      }

      final bills = [
        for (var i = 0; i < 10; i++)
          await a.sales.createBill(paidBill(cartNo(i), split: i.isOdd)),
      ];
      await a.sales.cancelBill(billId: bills[0].id, reason: 'Wrong item');
      for (final b in [bills[1], bills[2]]) {
        final qty = {b.lines.last.productId: 1};
        await a.sales.createReturn(
          billId: b.id,
          qtyByProduct: qty,
          refunds: cashRefund(b, qty),
          reason: 'Damaged',
        );
      }
      a = s.track(await a.restart());
      await syncInOrder([a]);

      final server = await expectStockOracle(s.admin, Fx.ptb);
      expect(server.bills, hasLength(10));
      expect(server.bill(bills[0].id).status, BillStatus.cancelled);
      expect(server.returns, hasLength(2));
      expect(server.movementsOf(MovementType.sale), hasLength(10));
      expect(server.movementsOf(MovementType.cancel), hasLength(1));
      expect(server.movementsOf(MovementType.returned), hasLength(2));
      for (final id in [
        Ids.auditId(Fx.ptb, Ids.cancelId(bills[0].id)),
        for (final r in server.returns) Ids.auditId(Fx.ptb, r.id),
      ]) {
        expect(await s.admin.get(FirestorePaths.audit(id)), isNotNull);
      }
      await expectSummaryOracle(s.admin, Fx.ptb, s.today);
      expect(await syncErrorPaths(a), isEmpty);
    },
    skip: backendSkip,
    timeout: scenarioTimeout,
  );

  // A2-4: the same WritePlan applied twice. The second batch is denied as a
  // whole by create-only + !exists (03-SYNC §4, 04 #7, #9): no second
  // document, stock change or summary increment. The ledger finds its docs
  // on the server (the first copy), so there is no sync error either.
  final kinds = <String, Future<void> Function(TestDevice a, Bill synced)>{
    'bill': (a, _) async {
      await a.sales.createBill(paidBill(cart));
    },
    'cancel': (a, synced) async {
      await a.sales.cancelBill(billId: synced.id, reason: 'Customer left');
    },
    'return': (a, synced) async {
      final qty = {Fx.vegPuff.id: 1};
      await a.sales.createReturn(
        billId: synced.id,
        qtyByProduct: qty,
        refunds: cashRefund(synced, qty),
        reason: 'Stale',
      );
    },
    'stock in': (a, _) async {
      await a.stock.stockIn(const [
        StockLineInput(itemKey: 'RM_flour', qty: 2500),
        StockLineInput(itemKey: 'RM_eggs', qty: 30),
      ], note: 'Supplier');
    },
    'adjust': (a, _) async {
      await a.stock.adjust(
        itemKey: 'RM_milk',
        countedQty: 4200,
        reason: 'Count',
      );
    },
  };

  for (final MapEntry(key: kind, value: act) in kinds.entries) {
    for (final restartBetween in [false, true]) {
      final how = restartBetween ? ', with a restart before sync' : '';
      test(
        'A2-4: a $kind plan applied twice offline$how lands once',
        () async {
          final s = await Scenario.open();
          addTearDown(s.close);
          var a = await s.device(Fx.smPtb, label: 'Counter A');
          // A synced bill for the cancel and return plans to act on.
          final synced = await a.sales.createBill(paidBill(cart));
          await a.sync.syncNow();
          final before = await ServerState.read(s.admin, Fx.ptb);

          await a.goOffline();
          await act(a, synced);
          await a.reapplyLastPlan();
          if (restartBetween) a = s.track(await a.restart());
          await syncInOrder([a]);
          // And once more online, after the first copy is confirmed.
          await a.reapplyLastPlan();
          await a.sync.syncNow();

          final after = await expectStockOracle(s.admin, Fx.ptb);
          expect(
            after.movements.length,
            before.movements.length + 1,
            reason: 'exactly one new movement',
          );
          expect(
            after.bills.length,
            before.bills.length + (kind == 'bill' ? 1 : 0),
          );
          expect(
            after.returns.length,
            before.returns.length + (kind == 'return' ? 1 : 0),
          );
          if (kind == 'cancel') {
            expect(after.bill(synced.id).status, BillStatus.cancelled);
          }
          if (kind == 'return') {
            expect(after.bill(synced.id).returnedQty, {Fx.vegPuff.id: 1});
          }
          if (kind == 'stock in') {
            expect(
              after.qty('RM_flour'),
              before.qty('RM_flour') + 2500,
              reason: 'one increment, not two',
            );
          }
          if (kind == 'adjust') {
            expect(after.qty('RM_milk'), 4200, reason: 'one delta, not two');
          }
          await expectSummaryOracle(s.admin, Fx.ptb, s.today);
          expect(await syncErrorPaths(a), isEmpty);
        },
        skip: backendSkip,
        timeout: scenarioTimeout,
      );
    }
  }
}
