import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';
import 'package:nexus_pos/app/messages.dart';

import 'helpers.dart';

final DateTime yesterday = testNow.subtract(const Duration(days: 1));

void main() {
  group('bills list', () {
    testWidgets("shows today's bills, newest first, and earlier days", (
      tester,
    ) async {
      final b = fakeBackend();
      await addBill(b, {'bf-500': 1}, at: yesterday);
      await addBill(b, {
        'rv-pastry': 2,
      }, at: testNow.subtract(const Duration(hours: 1)));
      await addBill(b, {'veg-puff': 3}, mode: PaymentMode.upi);
      await pumpPos(tester, backend: b);
      await openNav(tester, 'Bills');

      expect(textOf(tester, 'date-label'), 'Today · Sat, 26 Sep 2026');
      expect(
        tester.widget<IconButton>(find.byKey(const Key('date-next'))).onPressed,
        isNull,
      );
      final tiles = tester
          .widgetList<ListTile>(find.byType(ListTile))
          .map((t) => t.key)
          .toList();
      expect(tiles, [
        const Key('bill-D01-000003'),
        const Key('bill-D01-000002'),
      ]);
      expect(textOf(tester, 'bill-D01-000003'), contains('PTB-D01-000003'));
      expect(textOf(tester, 'bill-D01-000003'), contains('10:30'));
      expect(textOf(tester, 'bill-D01-000003'), contains('₹75.00'));

      await tapKey(tester, 'date-prev');
      expect(textOf(tester, 'date-label'), 'Fri, 25 Sep 2026');
      expect(find.byKey(const Key('bill-D01-000001')), findsOneWidget);
      expect(find.byKey(const Key('bill-D01-000003')), findsNothing);

      await tapKey(tester, 'date-prev');
      expect(find.byKey(const Key('no-bills')), findsOneWidget);

      await tapKey(tester, 'date-next');
      await tapKey(tester, 'date-next');
      expect(find.byKey(const Key('bill-D01-000003')), findsOneWidget);
    });

    testWidgets('the date picker opens an earlier day', (tester) async {
      final b = fakeBackend();
      await addBill(b, {
        'bf-500': 1,
      }, at: testNow.subtract(const Duration(days: 3)));
      await pumpPos(tester, backend: b);
      await openNav(tester, 'Bills');
      await tapKey(tester, 'date-pick');
      await tester.tap(find.text('23'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(textOf(tester, 'date-label'), 'Wed, 23 Sep 2026');
      expect(find.byKey(const Key('bill-D01-000001')), findsOneWidget);
    });

    testWidgets('a new bill appears in the list as it is saved', (
      tester,
    ) async {
      final b = fakeBackend();
      await pumpPos(tester, backend: b);
      await openNav(tester, 'Bills');
      expect(find.byKey(const Key('no-bills')), findsOneWidget);
      await addBill(b, {'brownie': 1});
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('bill-D01-000001')), findsOneWidget);
    });

    testWidgets('finds a bill by its number, full or short', (tester) async {
      final b = fakeBackend();
      await addBill(b, {'bf-500': 1}, at: yesterday);
      await addBill(b, {'brownie': 1});
      await pumpPos(tester, backend: b);
      await openNav(tester, 'Bills');

      await enterKey(tester, 'bill-search', 'ptb-d01-000001');
      await tapKey(tester, 'bill-search-go');
      expect(textOf(tester, 'detail-bill-no'), 'PTB-D01-000001');

      await tester.pageBack();
      await tester.pumpAndSettle();
      await enterKey(tester, 'bill-search', '2');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(textOf(tester, 'detail-bill-no'), 'PTB-D01-000002');

      await tester.pageBack();
      await tester.pumpAndSettle();
      await enterKey(tester, 'bill-search', 'D01-99');
      await tapKey(tester, 'bill-search-go');
      expect(textOf(tester, 'find-error'), 'No bill PTB-D01-000099 was found.');
    });

    testWidgets("won't open another store's bill", (tester) async {
      final b = fakeBackend();
      final bill = await addBill(b, {'bf-500': 1});
      // The same bill ID at MNJ.
      b.bills.put(
        'MNJ',
        Bill.fromMap(bill.id, {
          ...bill.toMap(),
          'billNo': Ids.billNo('MNJ', bill.id),
        }),
      );
      await pumpPos(tester, backend: b);
      await openNav(tester, 'Bills');
      await enterKey(tester, 'bill-search', 'MNJ-D01-000001');
      await tapKey(tester, 'bill-search-go');
      expect(textOf(tester, 'find-error'), contains('from another store'));
    });
  });

  group('bill detail and cancel', () {
    testWidgets('shows lines, totals and payments', (tester) async {
      final b = fakeBackend();
      await addBill(b, {
        'bf-500': 1,
        'rv-pastry': 2,
      }, discount: const DiscountInput.percent(5));
      await openBill(tester, b, 'D01-000001');
      expect(textOf(tester, 'detail-bill-no'), 'PTB-D01-000001');
      // 610.00 − 5% (30.50) = 579.50 → ₹580.
      expect(textOf(tester, 'detail-total'), contains('₹580.00'));
      expect(find.text('Black Forest 500 g × 1'), findsOneWidget);
      expect(find.text('-₹30.50'), findsOneWidget);
      expect(find.byKey(const Key('cancelled-banner')), findsNothing);
    });

    testWidgets('same-day cancel needs a reason and calls cancelBill once', (
      tester,
    ) async {
      final b = fakeBackend();
      await addBill(b, {'bf-500': 1});
      await openBill(tester, b, 'D01-000001');
      expect(isEnabled(tester, 'cancel-bill'), isTrue);
      expect(find.byKey(const Key('cancel-blocked')), findsNothing);

      await tapKey(tester, 'cancel-bill');
      expect(isEnabled(tester, 'cancel-confirm'), isFalse);
      await enterKey(tester, 'cancel-reason', '   ');
      expect(isEnabled(tester, 'cancel-confirm'), isFalse);
      await enterKey(tester, 'cancel-reason', ' Wrong cake ');
      expect(isEnabled(tester, 'cancel-confirm'), isTrue);
      await tester.tap(find.byKey(const Key('cancel-confirm')));
      await tester.tap(
        find.byKey(const Key('cancel-confirm')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      expect(b.sales.cancelCalls, [('D01-000001', 'Wrong cake')]);
      expect(textOf(tester, 'cancelled-banner'), 'CANCELLED: Wrong cake');
      expect(isEnabled(tester, 'cancel-bill'), isFalse);
      expect(
        textOf(tester, 'cancel-blocked'),
        'This bill is already cancelled.',
      );
      // A cancelled bill can't take a return either.
      expect(isEnabled(tester, 'start-return'), isFalse);
      expect(textOf(tester, 'return-blocked'), contains('cancelled'));
    });

    testWidgets('dismissing the reason dialog cancels nothing', (tester) async {
      final b = fakeBackend();
      await addBill(b, {'bf-500': 1});
      await openBill(tester, b, 'D01-000001');
      await tapKey(tester, 'cancel-bill');
      await enterKey(tester, 'cancel-reason', 'Oops');
      await tapKey(tester, 'cancel-dismiss');
      expect(b.sales.cancelCalls, isEmpty);
      expect(isEnabled(tester, 'cancel-bill'), isTrue);
    });

    testWidgets('a failed cancel shows why', (tester) async {
      final b = fakeBackend();
      await addBill(b, {'bf-500': 1});
      await openBill(tester, b, 'D01-000001');
      b.sales.failNext = const DataFailure(FailureReason.notPermitted);
      await tapKey(tester, 'cancel-bill');
      await enterKey(tester, 'cancel-reason', 'Wrong cake');
      await tapKey(tester, 'cancel-confirm');
      expect(textOf(tester, 'cancel-error'), contains("don't have permission"));
      expect(find.byKey(const Key('cancelled-banner')), findsNothing);
    });

    testWidgets('Cancel is disabled on a later day, and says why', (
      tester,
    ) async {
      final b = fakeBackend();
      await addBill(b, {'bf-500': 1}, at: yesterday);
      await pumpPos(tester, backend: b);
      await openNav(tester, 'Bills');
      await tapKey(tester, 'date-prev');
      await tapKey(tester, 'bill-D01-000001');
      expect(isEnabled(tester, 'cancel-bill'), isFalse);
      expect(
        textOf(tester, 'cancel-blocked'),
        Messages.cancelBlocker(CancelBlocker.differentDay),
      );
      // Returns are still possible.
      expect(isEnabled(tester, 'start-return'), isTrue);
    });

    testWidgets('Cancel is disabled once a bill has returns (D-025)', (
      tester,
    ) async {
      final b = fakeBackend();
      final bill = await addBill(b, {'bf-500': 1, 'veg-puff': 2});
      await b.sales.createReturn(
        billId: bill.id,
        qtyByProduct: {'veg-puff': 1},
        refunds: const [Payment(mode: PaymentMode.cash, amount: Money(2500))],
        reason: 'Stale',
      );
      await openBill(tester, b, bill.id);
      expect(isEnabled(tester, 'cancel-bill'), isFalse);
      expect(
        textOf(tester, 'cancel-blocked'),
        Messages.cancelBlocker(CancelBlocker.hasReturns),
      );
      expect(find.byKey(const Key('return-D01-R000001')), findsOneWidget);
      expect(isEnabled(tester, 'start-return'), isTrue);
    });

    testWidgets('Cancel is disabled on a cancelled bill', (tester) async {
      final b = fakeBackend();
      final bill = await addBill(b, {'bf-500': 1});
      await b.sales.cancelBill(billId: bill.id, reason: 'Duplicate');
      await openBill(tester, b, bill.id);
      expect(textOf(tester, 'cancelled-banner'), 'CANCELLED: Duplicate');
      expect(isEnabled(tester, 'cancel-bill'), isFalse);
      expect(
        textOf(tester, 'cancel-blocked'),
        Messages.cancelBlocker(CancelBlocker.notCompleted),
      );
    });

    testWidgets('Cancel and Return are hidden without their permissions', (
      tester,
    ) async {
      final b = fakeBackend(
        session: sessionWith([Permission.reportOwn, Permission.billCreate]),
      );
      await addBill(b, {'bf-500': 1});
      await openBill(tester, b, 'D01-000001');
      expect(find.byKey(const Key('cancel-bill')), findsNothing);
      expect(find.byKey(const Key('start-return')), findsNothing);
      // Reprint is still there.
      expect(find.byKey(const Key('print-button')), findsOneWidget);
    });

    testWidgets('an unknown bill ID says so', (tester) async {
      await pumpPos(tester);
      await openNav(tester, 'Bills');
      unawaited(
        GoRouter.of(
          tester.element(find.byType(Scaffold).first),
        ).push<void>('/bills/D01-000999'),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('not-found')), findsOneWidget);
    });
  });
}
