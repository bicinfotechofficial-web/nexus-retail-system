import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';
import 'package:nexus_pos/fakes/fake_backend.dart';
import 'package:nexus_printer/nexus_printer.dart';

import 'helpers.dart';

/// Black Forest 500 g, 2 × Red Velvet Pastry and a Walnut Brownie:
/// 450.00 + 160.00 + 72.50 = ₹682.50.
Future<FakeBackend> openPayment(
  WidgetTester tester, {
  FakeBackend? backend,
}) async {
  final b = await pumpPos(tester, backend: backend);
  await tapKey(tester, 'product-bf-500');
  await tapKey(tester, 'product-rv-pastry');
  await tapKey(tester, 'product-rv-pastry');
  await tapKey(tester, 'product-brownie');
  await tapKey(tester, 'charge');
  expect(find.widgetWithText(AppBar, 'Payment'), findsOneWidget);
  return b;
}

Future<void> choosePercent(WidgetTester tester, String pct) async {
  await tester.tap(find.text('% Off'));
  await tester.pumpAndSettle();
  await enterKey(tester, 'discount-input', pct);
}

void main() {
  testWidgets('full flow: cart → discount → split payment → save → print', (
    tester,
  ) async {
    final b = await openPayment(tester);
    expect(textOf(tester, 'total'), contains('₹683.00'));
    expect(textOf(tester, 'round-off'), contains('₹0.50'));
    // One Cash row that follows the total.
    expect(find.widgetWithText(TextField, '683.00'), findsOneWidget);

    // 5% of 682.50 = 34.125 → ₹34.13; 648.37 rounds to ₹648 (D-010, D-024).
    await choosePercent(tester, '5');
    expect(textOf(tester, 'discount-amount'), contains('-₹34.13'));
    expect(textOf(tester, 'round-off'), contains('-₹0.37'));
    expect(textOf(tester, 'total'), contains('₹648.00'));
    expect(find.widgetWithText(TextField, '648.00'), findsOneWidget);

    // Split: ₹400 cash, the rest on UPI.
    await enterKey(tester, 'payment-amount-0', '400');
    expect(isEnabled(tester, 'save'), isFalse);
    await tapKey(tester, 'add-payment');
    expect(find.widgetWithText(TextField, '248.00'), findsOneWidget);
    expect(find.byKey(const Key('remaining')), findsNothing);

    await enterKey(tester, 'cash-tendered', '500');
    expect(textOf(tester, 'change'), contains('₹100.00'));
    expect(isEnabled(tester, 'save'), isTrue);

    await tapKey(tester, 'save');

    expect(b.sales.createCalls, hasLength(1));
    final sent = b.sales.createCalls.single;
    expect(sent.cart.map((l) => (l.productId, l.qty)), [
      ('bf-500', 1),
      ('rv-pastry', 2),
      ('brownie', 1),
    ]);
    expect(sent.discount?.type, DiscountType.pct);
    expect(sent.discount?.value, 5);
    expect(sent.payments.map((p) => (p.mode, p.amount)), [
      (PaymentMode.cash, const Money(40000)),
      (PaymentMode.upi, const Money(24800)),
    ]);
    expect(sent.cashTendered, const Money(50000));

    // Saved, then printed.
    expect(textOf(tester, 'bill-no'), 'PTB-D01-000001');
    expect(textOf(tester, 'saved-change'), contains('₹100.00'));
    expect(b.printer.printedBills, hasLength(1));
    expect(b.printer.printedBills.single.id, 'D01-000001');
    expect(b.printer.printedBills.single.total, const Money(64800));
    expect(find.byKey(const Key('print-ok')), findsOneWidget);

    // New bill starts with an empty cart.
    await tapKey(tester, 'new-bill');
    expect(find.widgetWithText(AppBar, 'Billing'), findsOneWidget);
    expect(isEnabled(tester, 'charge'), isFalse);
  });

  testWidgets('a sum mismatch blocks Save', (tester) async {
    final b = await openPayment(tester);
    expect(isEnabled(tester, 'save'), isTrue);

    await tapKey(tester, 'add-payment'); // nothing remains, so it's empty
    await enterKey(tester, 'payment-amount-1', '100');
    expect(find.byKey(const Key('payment-error-sumMismatch')), findsOneWidget);
    expect(textOf(tester, 'remaining'), contains('Over by'));
    expect(isEnabled(tester, 'save'), isFalse);

    await tester.tap(find.byKey(const Key('save')), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(b.sales.createCalls, isEmpty);

    await enterKey(tester, 'payment-amount-0', '583');
    expect(find.byKey(const Key('payment-error-sumMismatch')), findsNothing);
    expect(isEnabled(tester, 'save'), isTrue);

    await tapKey(tester, 'payment-remove-1');
    expect(isEnabled(tester, 'save'), isFalse); // 583 ≠ 683
  });

  testWidgets('a cash tender below the cash payment blocks Save', (
    tester,
  ) async {
    await openPayment(tester);
    await enterKey(tester, 'cash-tendered', '500');
    expect(find.text('Cash tendered is less than the Cash payment.'), findsOne);
    expect(isEnabled(tester, 'save'), isFalse);
  });

  testWidgets('a double tap saves once', (tester) async {
    final b = await openPayment(tester);
    final gate = Completer<void>();
    b.sales.gate = gate;

    final save = find.byKey(const Key('save'));
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    // Two taps in the same frame: the second still hits the enabled button.
    await tester.tap(save);
    await tester.tap(save);
    await tester.pump();
    expect(isEnabled(tester, 'save'), isFalse);
    await tester.tap(save, warnIfMissed: false);
    await tester.pump();

    gate.complete();
    await tester.pumpAndSettle();

    expect(b.sales.createCalls, hasLength(1));
    expect(b.bills.all(Seed.locationId), hasLength(1));
    expect(b.printer.printedBills, hasLength(1));
    expect(textOf(tester, 'bill-no'), 'PTB-D01-000001');
  });

  testWidgets("the discount cap is the location's maxDiscountPct", (
    tester,
  ) async {
    final b = await openPayment(tester);
    expect(Seed.location.maxDiscountPct, 10);

    await choosePercent(tester, '15');
    expect(
      find.text("The discount is over this store's limit of 10%."),
      findsOne,
    );
    expect(find.byKey(const Key('discount-amount')), findsNothing);
    expect(textOf(tester, 'total'), contains('₹683.00'));
    expect(isEnabled(tester, 'save'), isFalse);

    await enterKey(tester, 'discount-input', '10');
    expect(find.textContaining('limit of 10%'), findsNothing);
    expect(textOf(tester, 'discount-amount'), contains('-₹68.25'));
    expect(textOf(tester, 'total'), contains('₹614.00'));
    expect(isEnabled(tester, 'save'), isTrue);

    // The cap applies to flat discounts too: ₹70 is over 10% of ₹682.50.
    await tester.tap(find.text('₹ Flat'));
    await tester.pumpAndSettle();
    await enterKey(tester, 'discount-input', '70');
    expect(find.textContaining('limit of 10%'), findsOne);
    expect(isEnabled(tester, 'save'), isFalse);
    await enterKey(tester, 'discount-input', '68');
    expect(textOf(tester, 'total'), contains('₹615.00'));
    expect(isEnabled(tester, 'save'), isTrue);

    await tapKey(tester, 'save');
    expect(b.sales.createCalls.single.discount?.type, DiscountType.flat);
    expect(b.sales.createCalls.single.discount?.value, 6800);
  });

  testWidgets('no cap when the location has none', (tester) async {
    const uncapped = Location(
      code: 'PTB',
      name: 'Caramel Cottage Pattambi',
      address: 'Main Road, Pattambi',
      phone: '0466 000 0000',
      overridePinHash: 'x',
      receiptFooter: 'Thank you!',
      nextDeviceNo: 2,
      active: true,
    );
    await openPayment(
      tester,
      backend: fakeBackend(
        session: const SessionContext(
          user: Seed.storeManager,
          role: Seed.storeManagerRole,
          location: uncapped,
        ),
      ),
    );
    await choosePercent(tester, '50');
    expect(find.textContaining('limit'), findsNothing);
    expect(isEnabled(tester, 'save'), isTrue);
  });

  testWidgets('a DataFailure shows a friendly message and allows retry', (
    tester,
  ) async {
    final b = await openPayment(tester);
    b.sales.failNext = const DataFailure(FailureReason.billingBlocked);
    await tapKey(tester, 'save');
    expect(textOf(tester, 'save-error'), contains('Billing is paused'));
    expect(isEnabled(tester, 'save'), isTrue);
    expect(b.printer.printedBills, isEmpty);

    await tapKey(tester, 'save');
    expect(b.sales.createCalls, hasLength(2));
    expect(textOf(tester, 'bill-no'), 'PTB-D01-000001');
  });

  testWidgets('a BillValidationException shows a friendly message', (
    tester,
  ) async {
    final b = await openPayment(tester);
    b.sales.failNext = const BillValidationException(
      BillError.discountOverCap,
      'over',
    );
    await tapKey(tester, 'save');
    expect(
      textOf(tester, 'save-error'),
      "The discount is over this store's limit of 10%.",
    );
    expect(find.textContaining('BillValidationException'), findsNothing);
  });

  testWidgets('an unknown failure keeps Save off to avoid a second bill', (
    tester,
  ) async {
    final b = await openPayment(tester);
    b.sales.failNext = const DataFailure(FailureReason.unknown);
    await tapKey(tester, 'save');
    expect(textOf(tester, 'save-error'), contains("Check today's bills"));
    expect(isEnabled(tester, 'save'), isFalse);
  });

  testWidgets('a print failure offers a retry, not an error', (tester) async {
    final b = await openPayment(tester);
    b.printer.nextResults.add(const PrintFailed('Printer is off'));
    await tapKey(tester, 'save');

    expect(textOf(tester, 'bill-no'), 'PTB-D01-000001');
    expect(textOf(tester, 'print-failed'), contains('The bill is saved'));
    await tapKey(tester, 'retry-print');
    expect(find.byKey(const Key('print-ok')), findsOneWidget);
    expect(b.printer.printedBills, hasLength(2));
    expect(b.sales.createCalls, hasLength(1));
  });

  testWidgets('split payment is limited to four rows', (tester) async {
    await openPayment(tester);
    for (var i = 0; i < 3; i++) {
      await tapKey(tester, 'add-payment');
    }
    expect(find.byKey(const Key('payment-row-3')), findsOneWidget);
    final add = tester.widget<TextButton>(find.byKey(const Key('add-payment')));
    expect(add.onPressed, isNull);
  });
}
