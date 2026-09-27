// QA-4: paths that must be refused, on the device or by the server, and
// what the Store Manager sees. PLAN C-2 (next-day cancel, client-side),
// M-6 / A1-7 (over-return, client and server), A3-4 (another location through
// the SDK), S6-2 / S8-2 (a user disabled while offline: the queued writes
// become sync errors).

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';

import 'support/backend.dart';
import 'support/fixtures.dart';
import 'support/oracle.dart';
import 'support/scenario.dart';

Matcher failsWith(FailureReason reason) =>
    throwsA(isA<DataFailure>().having((f) => f.reason, 'reason', reason));

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final cart = [Fx.line(Fx.blackForest, 1), Fx.line(Fx.vegPuff, 2)];

  for (final offline in [false, true]) {
    test(
      'C-2: a next-day cancel is refused on the device and writes nothing '
      '(D-009, client-enforced, D-031)${offline ? ', offline' : ''}',
      () async {
        final s = await Scenario.open();
        addTearDown(s.close);
        final yesterday = BusinessDate.addDays(s.today, -1);
        final old = await seedBill(
          s.admin,
          locationId: Fx.ptb,
          businessDate: yesterday,
          createdBy: s.uids[Fx.smPtb.key]!,
          cart: cart,
        );
        final a = await s.device(Fx.smPtb, label: 'Counter A');
        // The device has yesterday's bill (from the bill search).
        expect((await a.salesRepo.getBill(Fx.ptb, old.id))?.id, old.id);
        if (offline) await a.goOffline();

        await expectLater(
          a.sales.cancelBill(billId: old.id, reason: 'Customer changed mind'),
          failsWith(FailureReason.ruleViolation),
        );
        await syncInOrder([a]);

        final server = await expectStockOracle(s.admin, Fx.ptb);
        expect(server.bill(old.id).status, BillStatus.completed);
        expect(server.bill(old.id).cancel, isNull);
        expect(server.movementsOf(MovementType.cancel), isEmpty);
        expect(
          await s.admin.get(
            FirestorePaths.audit(Ids.auditId(Fx.ptb, Ids.cancelId(old.id))),
          ),
          isNull,
        );
        await expectSummaryOracle(s.admin, Fx.ptb, yesterday);
        expect(await syncErrorPaths(a), isEmpty);
      },
      skip: backendSkip,
      timeout: scenarioTimeout,
    );
  }

  test(
    'M-6: returning more than was sold is refused on the device and writes '
    'nothing',
    () async {
      final s = await Scenario.open();
      addTearDown(s.close);
      final a = await s.device(Fx.smPtb, label: 'Counter A');
      final bill = await a.sales.createBill(paidBill(cart));
      await a.sync.syncNow();

      await expectLater(
        a.sales.createReturn(
          billId: bill.id,
          qtyByProduct: {Fx.vegPuff.id: 3},
          refunds: const [Payment(mode: PaymentMode.cash, amount: Money(7700))],
          reason: 'Too many',
        ),
        throwsA(isA<ReturnValidationException>()),
      );
      await a.sync.syncNow();
      final server = await expectStockOracle(s.admin, Fx.ptb);
      expect(server.returns, isEmpty);
      expect(server.bill(bill.id).returnedQty, isEmpty);
    },
    skip: backendSkip,
    timeout: scenarioTimeout,
  );

  test(
    'A1-7: two offline returns that together exceed the sold qty: the '
    'second to sync is rejected and shows as a sync error (D-029)',
    () async {
      final s = await Scenario.open();
      addTearDown(s.close);
      final a = await s.device(Fx.smPtb, label: 'Counter A');
      final b = await s.device(Fx.smPtb, label: 'Counter B');
      final bill = await a.sales.createBill(paidBill(cart));
      await a.sync.syncNow();
      // B has the bill in its cache, as after a bill search.
      expect((await b.salesRepo.getBill(Fx.ptb, bill.id))?.id, bill.id);

      await a.goOffline();
      await b.goOffline();
      final two = {Fx.vegPuff.id: 2};
      final one = {Fx.vegPuff.id: 1};
      final retA = await a.sales.createReturn(
        billId: bill.id,
        qtyByProduct: two,
        refunds: cashRefund(bill, two),
        reason: 'Stale',
      );
      final retB = await b.sales.createReturn(
        billId: bill.id,
        qtyByProduct: one,
        refunds: cashRefund(bill, one),
        reason: 'Stale',
      );
      await syncInOrder([a, b]);

      final server = await expectStockOracle(s.admin, Fx.ptb);
      expect(server.returns.map((r) => r.id), [retA.id]);
      expect(server.bill(bill.id).returnedQty, two);
      expect(server.bill(bill.id).lastReturnId, retA.id);
      expect(server.movementsOf(MovementType.returned).map((m) => m.id), [
        retA.id,
      ]);
      expect(
        server.qty('FG_${Fx.vegPuff.id}'),
        Fx.opening['FG_${Fx.vegPuff.id}']!,
        reason: 'sold 2, returned 2 once',
      );
      expect(await syncErrorPaths(a), isEmpty);
      expect(
        await syncErrorPaths(b),
        contains(FirestorePaths.saleReturn(Fx.ptb, retB.id)),
      );
      await expectSummaryOracle(s.admin, Fx.ptb, s.today);
    },
    skip: backendSkip,
    timeout: scenarioTimeout,
  );

  test(
    'A3-4: a PTB Store Manager gets notPermitted and no data for MNJ',
    () async {
      final s = await Scenario.open();
      addTearDown(s.close);
      final mnjBill = await seedBill(
        s.admin,
        locationId: Fx.mnj,
        businessDate: s.today,
        createdBy: s.uids[Fx.smMnj.key]!,
        cart: cart,
      );
      final a = await s.device(Fx.smPtb, label: 'Counter A');

      await expectLater(
        a.salesRepo.getBill(Fx.mnj, mnjBill.id),
        failsWith(FailureReason.notPermitted),
      );
      await expectLater(
        a.salesRepo.findByBillNo(mnjBill.billNo),
        failsWith(FailureReason.notPermitted),
      );
      await expectLater(
        current(a.stockRepo.watchStock(Fx.mnj)),
        failsWith(FailureReason.notPermitted),
      );
      await expectLater(
        a.summaries.daily(Fx.mnj, s.today, s.today),
        failsWith(FailureReason.notPermitted),
      );

      // Its own work stays at PTB: MNJ is exactly as seeded.
      await a.sales.createBill(paidBill(cart));
      await a.sync.syncNow();
      final mnj = await expectStockOracle(s.admin, Fx.mnj);
      expect(mnj.bills.map((b) => b.id), [mnjBill.id]);
      expect(mnj.movements, hasLength(1), reason: 'only the opening stock');
      await expectSummaryOracle(s.admin, Fx.mnj, s.today);
    },
    skip: backendSkip,
    timeout: scenarioTimeout,
  );

  test(
    'S8-2: a user disabled while offline: every queued write becomes a sync '
    'error and none reaches the server, and lastSyncAt still moves',
    () async {
      final s = await Scenario.open();
      addTearDown(s.close);
      final a = await s.device(Fx.smPtb, label: 'Counter A');
      final x = await a.sales.createBill(paidBill(cart));
      final y = await a.sales.createBill(paidBill(cart));
      await a.sync.syncNow();
      final before = await ServerState.read(s.admin, Fx.ptb);

      await a.goOffline();
      final n1 = await a.sales.createBill(paidBill(cart));
      final n2 = await a.sales.createBill(paidBill([Fx.line(Fx.cookie, 4)]));
      await a.sales.cancelBill(billId: x.id, reason: 'Wrong cake');
      final qty = {Fx.vegPuff.id: 1};
      final ret = await a.sales.createReturn(
        billId: y.id,
        qtyByProduct: qty,
        refunds: cashRefund(y, qty),
        reason: 'Damaged',
      );
      final queued = await a.stock.stockIn(const [
        StockLineInput(itemKey: 'RM_flour', qty: 1000),
      ]);

      await s.setActive(Fx.smPtb, active: false);
      final passStart = DateTime.now();
      await syncInOrder([a]);

      expect(
        await syncErrorPaths(a),
        containsAll([
          FirestorePaths.bill(Fx.ptb, n1.id),
          FirestorePaths.bill(Fx.ptb, n2.id),
          FirestorePaths.movement(Fx.ptb, Ids.cancelId(x.id)),
          FirestorePaths.saleReturn(Fx.ptb, ret.id),
          FirestorePaths.movement(Fx.ptb, queued.id),
        ]),
      );
      final after = await expectStockOracle(s.admin, Fx.ptb);
      expect(
        after.bills.map((b) => b.id),
        unorderedEquals(before.bills.map((b) => b.id)),
      );
      expect(after.bill(x.id).status, BillStatus.completed);
      expect(after.bill(y.id).returnedQty, isEmpty);
      expect(after.returns, isEmpty);
      expect(after.movements, hasLength(before.movements.length));
      expect(
        {for (final e in after.stock.entries) e.key: e.value.qty},
        {for (final e in before.stock.entries) e.key: e.value.qty},
      );
      await expectSummaryOracle(s.admin, Fx.ptb, s.today);
      // A6-8 (b): the rejected entries don't hold lastSyncAt back.
      expect(a.sync.lastSyncAt, isNotNull);
      expect(a.sync.lastSyncAt!.isBefore(passStart), isFalse);
    },
    skip: backendSkip,
    timeout: scenarioTimeout,
  );
}
