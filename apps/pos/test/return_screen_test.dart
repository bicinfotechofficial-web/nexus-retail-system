import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';
import 'package:nexus_pos/app/router.dart';
import 'package:nexus_pos/fakes/fake_backend.dart';
import 'package:nexus_printer/nexus_printer.dart';

import 'helpers.dart';

/// A Black Forest 500 g (₹450) and 4 Veg Puffs (₹25 each): ₹550 in cash.
Future<(FakeBackend, Bill)> openReturn(
  WidgetTester tester, {
  FakeBackend? backend,
  Map<String, int> alreadyReturned = const {},
}) async {
  final b = backend ?? fakeBackend();
  final bill = await addBill(b, {'bf-500': 1, 'veg-puff': 4});
  if (alreadyReturned.isNotEmpty) {
    final r = ReturnCalculator.compute(bill, alreadyReturned);
    await b.sales.createReturn(
      billId: bill.id,
      qtyByProduct: alreadyReturned,
      refunds: [Payment(mode: PaymentMode.cash, amount: r.refundTotal)],
      reason: 'Earlier return',
    );
    b.sales.returnCalls.clear();
  }
  await openBill(tester, b, bill.id);
  await tapKey(tester, 'start-return');
  expect(find.widgetWithText(AppBar, 'Return · PTB-D01-000001'), findsOne);
  return (b, bill);
}

Future<void> tapTimes(WidgetTester tester, String key, int n) async {
  for (var i = 0; i < n; i++) {
    await tapKey(tester, key);
  }
}

bool isIconEnabled(WidgetTester tester, String key) =>
    tester.widget<IconButton>(find.byKey(Key(key))).onPressed != null;

void main() {
  testWidgets('quantities are capped by ReturnCalculator.returnable', (
    tester,
  ) async {
    final (b, _) = await openReturn(tester, alreadyReturned: {'veg-puff': 1});
    expect(textOf(tester, 'ret-line-veg-puff'), contains('1 returned'));
    expect(textOf(tester, 'ret-line-veg-puff'), contains('up to 3'));
    expect(isIconEnabled(tester, 'ret-minus-veg-puff'), isFalse);

    await tapTimes(tester, 'ret-plus-veg-puff', 3);
    expect(textOf(tester, 'ret-qty-veg-puff'), '3');
    expect(isIconEnabled(tester, 'ret-plus-veg-puff'), isFalse);

    // The refund total comes from ReturnCalculator.compute.
    final bill = (await b.bills.getBill(Seed.locationId, 'D01-000001'))!;
    final expected = ReturnCalculator.compute(bill, {'veg-puff': 3});
    expect(textOf(tester, 'refund-total'), contains('₹75.00'));
    expect(
      textOf(tester, 'refund-total'),
      contains(expected.refundTotal.format()),
    );
    // The single refund row follows the total.
    expect(find.widgetWithText(TextField, '75.00'), findsOneWidget);

    await tapKey(tester, 'ret-minus-veg-puff');
    expect(textOf(tester, 'refund-total'), contains('₹50.00'));
    expect(find.widgetWithText(TextField, '50.00'), findsOneWidget);
  });

  testWidgets('a fully returned line can take no more', (tester) async {
    await openReturn(tester, alreadyReturned: {'veg-puff': 4});
    expect(textOf(tester, 'ret-line-veg-puff'), contains('All 4 returned'));
    expect(isIconEnabled(tester, 'ret-plus-veg-puff'), isFalse);
    expect(isIconEnabled(tester, 'ret-plus-bf-500'), isTrue);
  });

  testWidgets('a refund split mismatch blocks Save; a matching split saves', (
    tester,
  ) async {
    final (b, _) = await openReturn(tester);
    expect(isEnabled(tester, 'save-return'), isFalse);
    await tapKey(tester, 'ret-plus-bf-500');
    expect(textOf(tester, 'refund-total'), contains('₹450.00'));
    // The reason is required.
    expect(isEnabled(tester, 'save-return'), isFalse);
    await enterKey(tester, 'return-reason', 'Wrong flavour');
    expect(isEnabled(tester, 'save-return'), isTrue);

    await enterKey(tester, 'refund-amount-0', '400');
    expect(isEnabled(tester, 'save-return'), isFalse);
    expect(find.byKey(const Key('refund-error-sumMismatch')), findsOneWidget);

    await tapKey(tester, 'add-refund');
    // The new row takes the remainder, on the next unused mode.
    expect(find.widgetWithText(TextField, '50.00'), findsOneWidget);
    expect(find.byKey(const Key('refund-error-sumMismatch')), findsNothing);
    expect(isEnabled(tester, 'save-return'), isTrue);

    await tapKey(tester, 'save-return');
    expect(b.sales.returnCalls, ['D01-000001']);
    final bill = (await b.bills.getBill(Seed.locationId, 'D01-000001'))!;
    expect(bill.returnedQty, {'bf-500': 1});
    expect(textOf(tester, 'return-id'), 'D01-R000001');
    expect(textOf(tester, 'saved-refund'), contains('₹450.00'));
  });

  testWidgets('refunds are limited to Limits.maxRefunds rows', (tester) async {
    await openReturn(tester);
    await tapKey(tester, 'ret-plus-bf-500');
    for (var i = 1; i < Limits.maxRefunds; i++) {
      await tapKey(tester, 'add-refund');
    }
    expect(find.byKey(Key('refund-amount-${Limits.maxRefunds - 1}')), findsOne);
    final add = tester.widget<TextButton>(find.byKey(const Key('add-refund')));
    expect(add.onPressed, isNull);
  });

  testWidgets('a double tap creates one return, then prints the slip', (
    tester,
  ) async {
    final (b, _) = await openReturn(tester);
    await tapKey(tester, 'ret-plus-veg-puff');
    await enterKey(tester, 'return-reason', 'Stale');
    final gate = Completer<void>();
    b.sales.gate = gate;

    final save = find.byKey(const Key('save-return'));
    await tester.tap(save);
    await tester.tap(save, warnIfMissed: false);
    await tester.pump();
    expect(isEnabled(tester, 'save-return'), isFalse);
    gate.complete();
    await tester.pumpAndSettle();

    expect(b.sales.returnCalls, hasLength(1));
    expect(b.printer.printedReturns.single.id, 'D01-R000001');
    expect(find.byKey(const Key('print-ok')), findsOneWidget);
    expect(find.textContaining('RETURN D01-R000001'), findsOneWidget);
  });

  testWidgets('a failed slip print offers a retry', (tester) async {
    final (b, _) = await openReturn(tester);
    await tapKey(tester, 'ret-plus-veg-puff');
    await enterKey(tester, 'return-reason', 'Stale');
    b.printer.nextResults.add(const PrintFailed('Printer is off'));
    await tapKey(tester, 'save-return');
    expect(textOf(tester, 'print-failed'), contains('The return is saved'));
    await tapKey(tester, 'retry-print');
    expect(find.byKey(const Key('print-ok')), findsOneWidget);
    expect(b.printer.printedReturns, hasLength(2));
    expect(b.sales.returnCalls, hasLength(1));
  });

  testWidgets('back on the bill, the return shows and Cancel is blocked', (
    tester,
  ) async {
    await openReturn(tester);
    await tapKey(tester, 'ret-plus-veg-puff');
    await enterKey(tester, 'return-reason', 'Stale');
    await tapKey(tester, 'save-return');
    await tapKey(tester, 'return-done');
    expect(find.byKey(const Key('return-D01-R000001')), findsOneWidget);
    expect(find.textContaining('1 returned'), findsOneWidget);
    expect(isEnabled(tester, 'cancel-bill'), isFalse);
    expect(textOf(tester, 'cancel-blocked'), contains('has returns'));
  });

  testWidgets('a ReturnValidationException shows why and allows retry', (
    tester,
  ) async {
    final (b, _) = await openReturn(tester);
    await tapKey(tester, 'ret-plus-veg-puff');
    await enterKey(tester, 'return-reason', 'Stale');
    b.sales.failNext = const ReturnValidationException(
      ReturnError.exceedsReturnable,
      'veg-puff: 1 > 0',
    );
    await tapKey(tester, 'save-return');
    expect(textOf(tester, 'return-error'), contains('more than is left'));
    expect(isEnabled(tester, 'save-return'), isTrue);
  });

  testWidgets('a DataFailure shows a message; an unknown one locks Save', (
    tester,
  ) async {
    final (b, _) = await openReturn(tester);
    await tapKey(tester, 'ret-plus-veg-puff');
    await enterKey(tester, 'return-reason', 'Stale');

    b.sales.failNext = const DataFailure(FailureReason.notPermitted);
    await tapKey(tester, 'save-return');
    expect(textOf(tester, 'return-error'), contains("don't have permission"));
    expect(isEnabled(tester, 'save-return'), isTrue);

    b.sales.failNext = const DataFailure(FailureReason.unknown);
    await tapKey(tester, 'save-return');
    expect(textOf(tester, 'return-error'), contains('may have been saved'));
    expect(isEnabled(tester, 'save-return'), isFalse);
    expect(b.sales.returnCalls, hasLength(2));
  });

  test('without return.create the return page is out of reach', () {
    expect(
      Routes.redirect(
        AsyncData(sessionWith([Permission.reportOwn])),
        Routes.billReturn('D01-000001'),
      ),
      '/bills',
    );
    expect(
      Routes.redirect(
        AsyncData(sessionWith([Permission.reportOwn, Permission.returnCreate])),
        Routes.billReturn('D01-000001'),
      ),
      isNull,
    );
  });
}
