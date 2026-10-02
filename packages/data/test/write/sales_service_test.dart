import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';

import 'support.dart';

void main() {
  group('createBill', () {
    test('writes the bill plan, numbered D01-000001, and ledgers its new '
        'docs (bill and SALE movement)', () async {
      final h = Harness();
      final bill = await h.sales.createBill(cashBill);
      expect(bill.id, 'D01-000001');
      expect(bill.billNo, 'PTB-D01-000001');
      expect(bill.servedBy.name, 'Store Manager PTB');
      final plan = h.committer.plans.single;
      expect(
        plan.opAt('locations/PTB/bills/D01-000001')!.kind,
        WriteKind.create,
      );
      expect(plan.opAt('locations/PTB/devices/D01')!.data, {'lastBillSeq': 1});
      expect(h.ledgerPaths, [
        'locations/PTB/bills/D01-000001',
        'locations/PTB/movements/D01-000001',
      ]);
      final e = h.ledger.entries.first;
      expect(e.uid, 'sm-ptb');
      expect(e.createdAt, t0);
      expect(e.check, LedgerCheck.serverGet);
      expect(e.label, contains('PTB-D01-000001'));
      expect(e.label, contains('Veg Puff × 2'));
      expect((await h.sales.createBill(cashBill)).id, 'D01-000002');
    });

    test('passes the customer through: on the bill, and as the customer '
        'record in the same batch (D-037)', () async {
      final h = Harness();
      final bill = await h.sales.createBill(cashBill);
      expect(bill.customer!.id, testCustomer.id);
      expect(bill.customer!.name, 'Test Customer');
      final plan = h.committer.plans.single;
      final billData = plan.opAt('locations/PTB/bills/D01-000001')!.data;
      expect(billData['customerId'], testCustomer.id);
      expect(billData['customerName'], 'Test Customer');
      expect(billData['customerPhone'], '9876543210');
      expect(billData['customerWhatsapp'], isNull);
      final c = plan.opAt('locations/PTB/customers/${testCustomer.id}')!;
      expect(c.kind, WriteKind.setMerge);
      expect(c.data['billCount'], const Increment(1));
      expect(c.data['totalSpend'], const Increment(70100));
      expect(c.data['lastWriteRef'], 'D01-000001');
      // The same customer's next bill writes the same record again.
      await h.sales.createBill(cashBill);
      final again = h.committer.plans.last.opAt(c.path)!;
      expect(again.data['lastWriteRef'], 'D01-000002');
      expect(again.data['billCount'], const Increment(1));
    });

    test('fails fast without bill.create: no number, no write', () async {
      final h = Harness(session: smSession(except: [Permission.billCreate]));
      await expectLater(
        h.sales.createBill(cashBill),
        failsWith(FailureReason.notPermitted),
      );
      expect(h.counters.current('D01', SeqKind.bill), 0);
      expect(h.committer.plans, isEmpty);
      expect(h.ledger.entries, isEmpty);
    });

    test('a disabled user, an Admin without a location and a signed-out '
        'device are not permitted', () async {
      for (final s in [smSession(active: false), adminSession, null]) {
        final h = Harness()..session = s;
        await expectLater(
          h.sales.createBill(cashBill),
          failsWith(FailureReason.notPermitted),
        );
        expect(h.committer.plans, isEmpty);
      }
    });

    test('an unregistered device gets deviceNotRegistered', () async {
      final h = Harness()..deviceId = null;
      await expectLater(
        h.sales.createBill(cashBill),
        failsWith(FailureReason.deviceNotRegistered),
      );
    });

    test('billing blocked by the offline limit: billingBlocked, no number '
        'used', () async {
      final h = Harness()..offline = const BillingBlocked();
      await expectLater(
        h.sales.createBill(cashBill),
        failsWith(FailureReason.billingBlocked),
      );
      expect(h.counters.current('D01', SeqKind.bill), 0);
      expect(h.committer.plans, isEmpty);
      // NearLimit still bills.
      h.offline = const NearLimit(Duration(minutes: 10));
      expect((await h.sales.createBill(cashBill)).seq, 1);
    });

    test(
      'the number is on disk before the plan reaches the committer',
      () async {
        final h = Harness();
        final seen = <Object?>[];
        h.committer.onCommit = (_) =>
            seen.add(h.store.disk[CounterStore.key('D01', SeqKind.bill)]);
        await h.sales.createBill(cashBill);
        expect(seen, [1]);
      },
    );

    test('killed after allocating: the restarted app skips the number, never '
        'reuses it', () async {
      final disk = <String, Object>{};
      final ledger = LedgerDisk();
      final first = Harness(disk: disk, ledgerDisk: ledger);
      first.committer.failWith = StateError('process killed');
      await expectLater(first.sales.createBill(cashBill), throwsStateError);
      expect(first.ledger.entries, isEmpty);

      final restarted = Harness(disk: disk, ledgerDisk: ledger);
      final bill = await restarted.sales.createBill(cashBill);
      expect(bill.id, 'D01-000002');
    });

    test('bad input is refused before a number is allocated', () async {
      final h = Harness();
      final short = NewBill(
        cart: const [cake],
        payments: const [Payment(mode: PaymentMode.cash, amount: Money(100))],
        customer: testCustomer,
      );
      await expectLater(
        h.sales.createBill(short),
        failsWith(FailureReason.ruleViolation),
      );
      await expectLater(
        h.sales.createBill(
          NewBill(
            cart: [
              for (var i = 0; i <= Limits.maxBillLines; i++)
                CartLine(
                  productId: 'p$i',
                  name: 'P$i',
                  qty: 1,
                  unitPrice: const Money(100),
                ),
            ],
            payments: const [],
            customer: testCustomer,
          ),
        ),
        throwsA(isA<BillValidationException>()),
      );
      expect(h.counters.current('D01', SeqKind.bill), 0);
      expect((await h.sales.createBill(cashBill)).seq, 1);
    });

    test('the counters are recovered from the device doc before the first '
        'number (03-SYNC §3.4), once per process', () async {
      final h = Harness();
      h.reads.devices['locations/PTB/devices/D01'] = const Device(
        code: 'D01',
        label: 'Counter 1',
        registeredBy: 'sm-ptb',
        lastBillSeq: 41,
        retired: false,
      );
      expect((await h.sales.createBill(cashBill)).seq, 42);
      expect((await h.sales.createBill(cashBill)).seq, 43);
      expect(h.reads.deviceReads, 1);
    });

    test('the location discount cap applies', () async {
      final h = Harness(session: smSession(location: ptb(maxDiscountPct: 5)));
      await expectLater(
        h.sales.createBill(
          NewBill(
            cart: const [cake],
            discount: const DiscountInput.percent(10),
            payments: const [
              Payment(mode: PaymentMode.cash, amount: Money(58500)),
            ],
            customer: testCustomer,
          ),
        ),
        throwsA(isA<BillValidationException>()),
      );
    });

    test(
      'a commit error reaches the caller as it is, with nothing ledgered',
      () async {
        final h = Harness();
        h.committer.failWith = const DataFailure(FailureReason.notPermitted);
        await expectLater(
          h.sales.createBill(cashBill),
          failsWith(FailureReason.notPermitted),
        );
        expect(h.ledger.entries, isEmpty);
      },
    );
  });

  group('cancelBill', () {
    late Harness h;
    late Bill bill;

    setUp(() async {
      h = Harness();
      bill = await h.sales.createBill(cashBill);
      h.reads.bills[FirestorePaths.bill('PTB', bill.id)] = bill;
    });

    test('writes the cancel plan and ledgers the CANCEL movement, not the '
        'audit', () async {
      final cancelled = await h.sales.cancelBill(
        billId: bill.id,
        reason: 'Wrong cake',
      );
      expect(cancelled.status, BillStatus.cancelled);
      final plan = h.committer.plans.last;
      expect(plan.paths, contains('auditLog/PTB-D01-000001-X'));
      expect(h.ledgerPaths, [
        'locations/PTB/bills/D01-000001',
        'locations/PTB/movements/D01-000001',
        'locations/PTB/movements/D01-000001-X',
      ]);
      expect(h.ledger.entries.last.label, startsWith('Cancel of Bill'));
    });

    test('permission, device, missing bill and rule checks', () async {
      h.session = smSession(except: [Permission.billCancel]);
      await expectLater(
        h.sales.cancelBill(billId: bill.id, reason: 'x'),
        failsWith(FailureReason.notPermitted),
      );
      h.session = smSession();
      await expectLater(
        h.sales.cancelBill(billId: 'D01-000099', reason: 'x'),
        failsWith(FailureReason.notFound),
      );
      h.clock.advance(const Duration(days: 1));
      await expectLater(
        h.sales.cancelBill(billId: bill.id, reason: 'x'),
        failsWith(FailureReason.ruleViolation),
      );
      h.deviceId = null;
      await expectLater(
        h.sales.cancelBill(billId: bill.id, reason: 'x'),
        failsWith(FailureReason.deviceNotRegistered),
      );
      expect(h.committer.plans, hasLength(1));
    });

    test('is not blocked by the offline limit (only new bills are)', () async {
      h.offline = const BillingBlocked();
      await h.sales.cancelBill(billId: bill.id, reason: 'Wrong cake');
      expect(h.committer.plans, hasLength(2));
    });
  });

  group('createReturn', () {
    late Harness h;
    late Bill bill;

    setUp(() async {
      h = Harness();
      bill = await h.sales.createBill(cashBill);
      h.reads.bills[FirestorePaths.bill('PTB', bill.id)] = bill;
    });

    test('numbered from the return counter; ledgers return and RETURN '
        'movement', () async {
      final qty = {'puff-veg': 1};
      final refund = ReturnCalculator.compute(bill, qty).refundTotal;
      final r = await h.sales.createReturn(
        billId: bill.id,
        qtyByProduct: qty,
        refunds: [Payment(mode: PaymentMode.cash, amount: refund)],
        reason: 'Stale',
      );
      expect(r.id, 'D01-R000001');
      expect(r.prevReturnId, isNull);
      expect(h.counters.current('D01', SeqKind.returned), 1);
      expect(h.counters.current('D01', SeqKind.bill), 1);
      expect(h.ledgerPaths.skip(2), [
        'locations/PTB/returns/D01-R000001',
        'locations/PTB/movements/D01-R000001',
      ]);
      expect(h.ledger.entries.last.label, contains('Return D01-R000001'));
    });

    test('refunds that don\'t add up and over-returns use no number', () async {
      await expectLater(
        h.sales.createReturn(
          billId: bill.id,
          qtyByProduct: {'puff-veg': 1},
          refunds: const [Payment(mode: PaymentMode.cash, amount: Money(1))],
          reason: 'x',
        ),
        failsWith(FailureReason.ruleViolation),
      );
      await expectLater(
        h.sales.createReturn(
          billId: bill.id,
          qtyByProduct: {'puff-veg': 5},
          refunds: const [],
          reason: 'x',
        ),
        throwsA(isA<ReturnValidationException>()),
      );
      expect(h.counters.current('D01', SeqKind.returned), 0);
    });

    test('without return.create: notPermitted before anything', () async {
      h.session = smSession(except: [Permission.returnCreate]);
      await expectLater(
        h.sales.createReturn(
          billId: bill.id,
          qtyByProduct: {'puff-veg': 1},
          refunds: const [],
          reason: 'x',
        ),
        failsWith(FailureReason.notPermitted),
      );
    });
  });

  test('a ledger that fails after the commit doesn\'t fail the write '
      '(a retry would bill twice)', () async {
    final h = Harness();
    final env = WriteEnv(
      session: () => h.session,
      deviceId: () => 'D01',
      counters: h.counters,
      committer: h.committer,
      ledger: _BrokenLedger(),
      reads: h.reads,
      clock: h.clock.call,
    );
    final bill = await FirestoreSalesService(
      env,
      offline: () => const WithinLimit(),
    ).createBill(cashBill);
    expect(bill.seq, 1);
    expect(h.committer.plans, hasLength(1));
  });
}

final class _BrokenLedger implements SyncLedger {
  final _inner = MemorySyncLedger();

  @override
  Future<void> addAll(Iterable<LedgerEntry> entries) =>
      Future.error(StateError('disk full'));

  @override
  List<LedgerEntry> get entries => _inner.entries;
  @override
  Future<void> remove(String path) => _inner.remove(path);
  @override
  List<SyncError> get errors => _inner.errors;
  @override
  Future<void> addError(SyncError error) => _inner.addError(error);
  @override
  Stream<void> get changes => _inner.changes;
}
