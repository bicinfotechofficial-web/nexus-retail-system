import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';
import 'package:nexus_pos/app/messages.dart';
import 'package:nexus_pos/app/phone_store.dart';
import 'package:nexus_pos/fakes/fake_backend.dart';

import 'helpers.dart';
import 'support/preorder_fakes.dart';

/// POS-21: the order detail, Cancel and Deliver (D-043). "Today" is
/// 2026-09-26.
const _description = 'Red Velvet, 2 kg\nWrite "Happy Birthday Ammu"\nNo nuts';

Future<(FakeBackend, PreorderFakes, PreOrder)> openDetail(
  WidgetTester tester, {
  int price = 1200,
  int advance = 500,
  PaymentMode? mode,
  bool reviewOff = false,
  bool cartItem = false,
}) async {
  final b = fakeBackend();
  if (reviewOff) {
    (b.phoneStore as MemoryPhoneStore).values[PhoneKeys.reviewBeforeSave(
          Seed.userId,
        )] =
        false;
  }
  final f = PreorderFakes(b);
  final order = f.orders.add(
    dueDate: '2026-09-27',
    dueTime: '16:30',
    customer: 'Meera Nair',
    description: _description,
    price: price,
    advance: advance,
    advanceMode: mode ?? PaymentMode.upi,
  );
  await pumpPos(tester, backend: b, fakes: f);
  if (cartItem) await tapKey(tester, 'product-bf-500');
  await openNav(tester, 'Orders');
  await tapKey(tester, 'order-${order.id}');
  expect(find.widgetWithText(AppBar, 'Order'), findsOneWidget);
  return (b, f, order);
}

String? fieldError(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(Key(key))).decoration?.errorText;

void main() {
  group('the detail', () {
    testWidgets('shows the whole description, the customer and the amounts', (
      tester,
    ) async {
      final (_, _, o) = await openDetail(tester);
      expect(textOf(tester, 'order-no'), o.orderNo);
      expect(textOf(tester, 'order-status'), 'Open');
      expect(textOf(tester, 'order-description'), _description);
      expect(textOf(tester, 'order-customer'), contains('Meera Nair'));
      expect(textOf(tester, 'order-phone'), contains('9876543210'));
      expect(textOf(tester, 'order-whatsapp'), contains('Same as mobile'));
      expect(textOf(tester, 'order-due'), contains('Sun, 27 Sep'));
      expect(textOf(tester, 'order-due'), contains('16:30'));
      expect(textOf(tester, 'order-price'), contains('₹1,200.00'));
      expect(textOf(tester, 'order-advance'), contains('₹500.00'));
      expect(textOf(tester, 'order-advance'), contains('UPI'));
      expect(textOf(tester, 'order-balance'), contains('₹700.00'));
      expect(find.byKey(const Key('deliver')), findsOneWidget);
      expect(find.byKey(const Key('cancel-order')), findsOneWidget);
    });

    testWidgets('can reprint and share the advance slip', (tester) async {
      final (_, f, o) = await openDetail(tester);
      await tapKey(tester, 'print-button');
      expect(f.slips.printed.single.id, o.id);
      await tapKey(tester, 'share-slip');
      expect(f.slips.shared.single.id, o.id);
    });

    testWidgets('a delivered order shows its bill and has no actions', (
      tester,
    ) async {
      final b = fakeBackend();
      final f = PreorderFakes(b);
      final o = f.orders.add(dueDate: '2026-09-26');
      final bill = await f.orders.deliver(
        orderId: o.id,
        payments: [Payment(mode: PaymentMode.cash, amount: o.balance)],
      );
      await pumpPos(tester, backend: b, fakes: f);
      await openNav(tester, 'Orders');
      await tapKey(tester, 'tab-recent');
      await tapKey(tester, 'recent-${o.id}');
      expect(textOf(tester, 'order-status'), 'Delivered');
      expect(textOf(tester, 'order-bill'), contains(bill.id));
      expect(find.byKey(const Key('deliver')), findsNothing);
      expect(find.byKey(const Key('cancel-order')), findsNothing);
      await tapKey(tester, 'view-bill');
      expect(textOf(tester, 'detail-bill-no'), contains(bill.billNo));
    });

    testWidgets('a cancelled order shows the reason and the refund', (
      tester,
    ) async {
      final b = fakeBackend();
      final f = PreorderFakes(b);
      final o = f.orders.add(dueDate: '2026-09-26', advance: 500);
      await f.orders.cancel(
        orderId: o.id,
        reason: 'Customer travelled',
        refund: const Money(20000),
      );
      await pumpPos(tester, backend: b, fakes: f);
      await openNav(tester, 'Orders');
      await tapKey(tester, 'tab-recent');
      await tapKey(tester, 'recent-${o.id}');
      expect(textOf(tester, 'order-status'), 'Cancelled');
      expect(textOf(tester, 'order-cancel-reason'), 'Customer travelled');
      expect(textOf(tester, 'order-refunded'), contains('₹200.00'));
      expect(textOf(tester, 'order-kept'), contains('₹300.00'));
      expect(find.byKey(const Key('deliver')), findsNothing);
      expect(find.byKey(const Key('cancel-order')), findsNothing);
    });

    testWidgets('an unknown order says so', (tester) async {
      await pumpPos(tester);
      final ctx = tester.element(find.byType(Scaffold).first);
      GoRouter.of(ctx).go('/orders/D01-O999999');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('order-missing')), findsOneWidget);
    });
  });

  group('Cancel', () {
    Future<void> openCancel(WidgetTester tester) async {
      await tapKey(tester, 'cancel-order');
      expect(find.text('Cancel order'), findsWidgets);
      expect(find.byKey(const Key('cancel-reason')), findsOneWidget);
    }

    testWidgets('asks for a reason and a refund, and calls nothing until '
        'both are right', (tester) async {
      final (_, f, _) = await openDetail(tester);
      await openCancel(tester);
      expect(
        textOf(tester, 'cancel-advance-note'),
        contains('Advance paid: ₹500.00'),
      );
      await tapKey(tester, 'cancel-confirm');
      expect(fieldError(tester, 'cancel-reason'), 'Enter a reason.');
      expect(
        fieldError(tester, 'cancel-refund'),
        'Enter the refund, 0 if none.',
      );
      expect(f.orders.cancelCalls, isEmpty);

      await enterKey(tester, 'cancel-reason', 'x' * 101);
      expect(
        fieldError(tester, 'cancel-reason'),
        'At most ${Limits.orderReasonMax} characters.',
      );
      await tapKey(tester, 'cancel-confirm');
      expect(f.orders.cancelCalls, isEmpty);
    });

    testWidgets('the refund is from 0 to the advance, in whole rupees', (
      tester,
    ) async {
      final (_, f, _) = await openDetail(tester, advance: 500);
      await openCancel(tester);
      await enterKey(tester, 'cancel-reason', 'Changed plans');
      for (final (text, message) in [
        ('-1', 'The refund cannot be negative.'),
        ('501', 'More than the advance.'),
        ('500.01', 'Use whole rupees.'),
        ('600', 'More than the advance.'),
        ('100.50', 'Use whole rupees.'),
        ('abc', 'Enter an amount, like 500.'),
        ('', 'Enter the refund, 0 if none.'),
      ]) {
        await enterKey(tester, 'cancel-refund', text);
        expect(fieldError(tester, 'cancel-refund'), message, reason: text);
        await tapKey(tester, 'cancel-confirm');
        expect(f.orders.cancelCalls, isEmpty, reason: text);
      }
      for (final ok in ['0', '1', '499', '500']) {
        await enterKey(tester, 'cancel-refund', ok);
        expect(fieldError(tester, 'cancel-refund'), isNull, reason: ok);
      }
    });

    testWidgets('a refund of 0 keeps the whole advance', (tester) async {
      final (_, f, o) = await openDetail(tester, advance: 500);
      await openCancel(tester);
      await enterKey(tester, 'cancel-reason', '  Customer changed mind ');
      await enterKey(tester, 'cancel-refund', '0');
      await tapKey(tester, 'cancel-confirm');
      expect(f.orders.cancelCalls, hasLength(1));
      final c = f.orders.cancelCalls.single;
      expect(c.orderId, o.id);
      expect(c.reason, 'Customer changed mind');
      expect(c.refund, Money.zero);
      expect(textOf(tester, 'order-status'), 'Cancelled');
      expect(textOf(tester, 'order-refunded'), contains('₹0.00'));
      expect(textOf(tester, 'order-kept'), contains('₹500.00'));
      expect(find.byKey(const Key('cancel-order')), findsNothing);
      expect(find.text('Order cancelled.'), findsOneWidget);
    });

    testWidgets('a refund of the whole advance keeps nothing', (tester) async {
      final (_, f, _) = await openDetail(tester, advance: 500);
      await openCancel(tester);
      await enterKey(tester, 'cancel-reason', 'Shop could not make it');
      await enterKey(tester, 'cancel-refund', '500');
      await tapKey(tester, 'cancel-confirm');
      expect(f.orders.cancelCalls.single.refund, const Money(50000));
      expect(textOf(tester, 'order-refunded'), contains('₹500.00'));
      expect(textOf(tester, 'order-kept'), contains('₹0.00'));
    });

    testWidgets('a part refund is sent as entered', (tester) async {
      final (_, f, _) = await openDetail(tester, advance: 500);
      await openCancel(tester);
      await enterKey(tester, 'cancel-reason', 'Changed plans');
      await enterKey(tester, 'cancel-refund', '350');
      await tapKey(tester, 'cancel-confirm');
      expect(f.orders.cancelCalls.single.refund, const Money(35000));
    });

    testWidgets('with no advance there is no refund to ask for', (
      tester,
    ) async {
      final (_, f, _) = await openDetail(tester, advance: 0);
      await openCancel(tester);
      expect(find.byKey(const Key('cancel-refund')), findsNothing);
      await enterKey(tester, 'cancel-reason', 'Not needed any more');
      await tapKey(tester, 'cancel-confirm');
      expect(f.orders.cancelCalls.single.refund, Money.zero);
    });

    testWidgets('Keep order cancels nothing', (tester) async {
      final (_, f, _) = await openDetail(tester);
      await openCancel(tester);
      await enterKey(tester, 'cancel-reason', 'Changed plans');
      await tapKey(tester, 'cancel-keep');
      expect(f.orders.cancelCalls, isEmpty);
      expect(textOf(tester, 'order-status'), 'Open');
    });

    testWidgets('a double tap cancels once', (tester) async {
      final (_, f, _) = await openDetail(tester);
      await openCancel(tester);
      await enterKey(tester, 'cancel-reason', 'Changed plans');
      await enterKey(tester, 'cancel-refund', '0');
      f.orders.gate = Completer<void>();
      final confirm = find.byKey(const Key('cancel-confirm'));
      await tester.tap(confirm);
      await tester.pump();
      await tester.tap(confirm, warnIfMissed: false);
      await tester.pump();
      expect(f.orders.cancelCalls, hasLength(1));
      f.orders.gate!.complete();
      await tester.pumpAndSettle();
      expect(f.orders.cancelCalls, hasLength(1));
    });

    testWidgets('a refused cancel shows why inside the dialog and can be '
        'retried', (tester) async {
      final (_, f, _) = await openDetail(tester);
      await openCancel(tester);
      await enterKey(tester, 'cancel-reason', 'Changed plans');
      await enterKey(tester, 'cancel-refund', '0');
      f.orders.failNext = const DataFailure(FailureReason.notPermitted);
      await tapKey(tester, 'cancel-confirm');
      expect(
        textOf(tester, 'cancel-error'),
        "You don't have permission to do this.",
      );
      expect(isEnabled(tester, 'cancel-confirm'), isTrue);
      await tapKey(tester, 'cancel-confirm');
      expect(f.orders.cancelCalls, hasLength(2));
      expect(textOf(tester, 'order-status'), 'Cancelled');
    });

    testWidgets('a cancelled order leaves the open list and the banner', (
      tester,
    ) async {
      final (_, _, o) = await openDetail(tester);
      await openCancel(tester);
      await enterKey(tester, 'cancel-reason', 'Changed plans');
      await enterKey(tester, 'cancel-refund', '0');
      await tapKey(tester, 'cancel-confirm');
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byKey(Key('order-${o.id}')), findsNothing);
      expect(find.byKey(const Key('orders-empty')), findsOneWidget);
      await tapKey(tester, 'tab-recent');
      expect(textOf(tester, 'recent-status-${o.id}'), 'Cancelled');
    });
  });

  group('Deliver', () {
    testWidgets('opens the payment page in delivery mode: one CUSTOM-CAKE '
        'line, the advance, and only the balance to collect', (tester) async {
      await openDetail(tester);
      expect(textOf(tester, 'deliver'), 'Deliver and collect ₹700.00');
      await tapKey(tester, 'deliver');
      expect(find.widgetWithText(AppBar, 'Deliver order'), findsOneWidget);
      expect(find.text('Custom cake × 1'), findsOneWidget);
      expect(textOf(tester, 'total'), contains('₹1,200.00'));
      expect(textOf(tester, 'delivery-advance'), contains('-₹500.00'));
      expect(find.text('Advance paid'), findsOneWidget);
      expect(textOf(tester, 'delivery-balance'), contains('₹700.00'));
      // The customer is the order's, and can't be edited.
      expect(find.byKey(const Key('customer-name')), findsNothing);
      expect(find.byKey(const Key('customer-phone')), findsNothing);
      expect(textOf(tester, 'delivery-customer-name'), contains('Meera Nair'));
      expect(textOf(tester, 'delivery-customer-phone'), contains('9876543210'));
      // No discount and no round-off for an agreed price.
      expect(find.byKey(const Key('discount-input')), findsNothing);
      expect(find.text('Discount'), findsNothing);
      expect(find.byKey(const Key('round-off')), findsNothing);
      // One payment row, for the balance.
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('payment-amount-0')))
            .controller!
            .text,
        '700.00',
      );
      expect(find.byKey(const Key('payment-row-1')), findsNothing);
      expect(textOf(tester, 'save'), 'Review · collect ₹700.00');
    });

    testWidgets('payment modes are the selectable ones: never Advance paid', (
      tester,
    ) async {
      await openDetail(tester);
      await tapKey(tester, 'deliver');
      await tapKey(tester, 'payment-mode-0');
      for (final m in PaymentMode.selectable) {
        expect(
          find.text(Messages.paymentMode(m)).evaluate().isNotEmpty,
          isTrue,
          reason: m.wire,
        );
      }
      // The only "Advance paid" is the bill's own line, not a menu entry.
      expect(
        find.descendant(
          of: find.byType(DropdownMenuItem<PaymentMode>),
          matching: find.text('Advance paid'),
          skipOffstage: false,
        ),
        findsNothing,
      );
      expect(
        tester
            .widgetList<DropdownMenuItem<PaymentMode>>(
              find.byType(DropdownMenuItem<PaymentMode>, skipOffstage: false),
            )
            .map((i) => i.value),
        everyElement(isIn(PaymentMode.selectable)),
      );
    });

    testWidgets('review, then Confirm makes exactly one deliver call and '
        'shows the saved bill', (tester) async {
      final (b, f, o) = await openDetail(tester, cartItem: true);
      await tapKey(tester, 'deliver');
      await tapKey(tester, 'save');
      expect(find.widgetWithText(AppBar, 'Review delivery'), findsOneWidget);
      expect(textOf(tester, 'review-customer-name'), contains('Meera Nair'));
      expect(textOf(tester, 'review-order-no'), contains(o.orderNo));
      expect(textOf(tester, 'review-total'), contains('₹1,200.00'));
      // The review lists the advance already paid and the cash now.
      expect(find.text('Advance paid'), findsOneWidget);
      expect(find.text('Cash'), findsOneWidget);
      expect(f.orders.deliverCalls, isEmpty);

      await tapKey(tester, 'confirm');
      expect(f.orders.deliverCalls, hasLength(1));
      final call = f.orders.deliverCalls.single;
      expect(call.orderId, o.id);
      // Only the balance goes in; the service adds the advance itself.
      expect(call.payments, hasLength(1));
      expect(call.payments.single.mode, PaymentMode.cash);
      expect(call.payments.single.amount, const Money(70000));
      expect(call.cashTendered, isNull);

      // The normal bill-saved screen for the returned bill.
      expect(find.widgetWithText(AppBar, 'Bill saved'), findsOneWidget);
      final bill = b.bills.all(Seed.locationId).single;
      expect(bill.orderId, o.id);
      expect(textOf(tester, 'bill-no'), bill.billNo);
      expect(bill.total, const Money(120000));
      expect(bill.payments.map((p) => (p.mode, p.amount)), [
        (PaymentMode.advance, const Money(50000)),
        (PaymentMode.cash, const Money(70000)),
      ]);
      expect(f.orders.byId(o.id).status, OrderStatus.delivered);
      expect(f.orders.byId(o.id).billId, bill.id);
      expect(b.sales.createCalls, isEmpty);

      // The shop's cart in progress was not touched.
      await tapKey(tester, 'new-bill');
      expect(find.byKey(const Key('cart-line-bf-500')), findsOneWidget);
    });

    testWidgets('Back from the review keeps what was entered', (tester) async {
      await openDetail(tester);
      await tapKey(tester, 'deliver');
      await tapKey(tester, 'payment-mode-0');
      await tester.tap(find.text('UPI').last);
      await tester.pumpAndSettle();
      await tapKey(tester, 'save');
      await tapKey(tester, 'review-back');
      expect(find.widgetWithText(AppBar, 'Deliver order'), findsOneWidget);
      expect(find.text('UPI'), findsWidgets);
    });

    testWidgets('a double tap on Confirm delivers once', (tester) async {
      final (_, f, _) = await openDetail(tester);
      await tapKey(tester, 'deliver');
      await tapKey(tester, 'save');
      f.orders.gate = Completer<void>();
      final confirm = find.byKey(const Key('confirm'));
      await tester.tap(confirm);
      await tester.pump();
      await tester.tap(confirm, warnIfMissed: false);
      await tester.pump();
      expect(f.orders.deliverCalls, hasLength(1));
      f.orders.gate!.complete();
      await tester.pumpAndSettle();
      expect(f.orders.deliverCalls, hasLength(1));
      expect(find.widgetWithText(AppBar, 'Bill saved'), findsOneWidget);
    });

    testWidgets('with the review off, the button delivers straight away', (
      tester,
    ) async {
      final (_, f, _) = await openDetail(tester, reviewOff: true);
      await tapKey(tester, 'deliver');
      expect(textOf(tester, 'save'), 'Deliver · collect ₹700.00');
      await tapKey(tester, 'save');
      expect(f.orders.deliverCalls, hasLength(1));
      expect(find.widgetWithText(AppBar, 'Bill saved'), findsOneWidget);
    });

    testWidgets('a balance of zero skips the payment step', (tester) async {
      final (_, f, o) = await openDetail(
        tester,
        price: 1000,
        advance: 1000,
        reviewOff: true,
      );
      expect(textOf(tester, 'deliver'), 'Deliver (nothing to collect)');
      await tapKey(tester, 'deliver');
      expect(find.byKey(const Key('nothing-to-collect')), findsOneWidget);
      expect(find.byKey(const Key('payment-row-0')), findsNothing);
      expect(find.byKey(const Key('add-payment')), findsNothing);
      expect(textOf(tester, 'delivery-balance'), contains('₹0.00'));
      expect(textOf(tester, 'save'), 'Deliver');
      await tapKey(tester, 'save');
      final call = f.orders.deliverCalls.single;
      expect(call.orderId, o.id);
      expect(call.payments, isEmpty);
      expect(find.widgetWithText(AppBar, 'Bill saved'), findsOneWidget);
    });

    testWidgets('a balance of zero still goes through the review', (
      tester,
    ) async {
      final (_, f, _) = await openDetail(tester, price: 1000, advance: 1000);
      await tapKey(tester, 'deliver');
      await tapKey(tester, 'save');
      expect(find.widgetWithText(AppBar, 'Review delivery'), findsOneWidget);
      await tapKey(tester, 'confirm');
      expect(f.orders.deliverCalls.single.payments, isEmpty);
    });

    testWidgets('the balance can be split, and must add up', (tester) async {
      final (_, f, _) = await openDetail(tester, reviewOff: true);
      await tapKey(tester, 'deliver');
      await tapKey(tester, 'add-payment');
      await enterKey(tester, 'payment-amount-0', '400');
      expect(textOf(tester, 'remaining'), contains('₹300.00'));
      expect(isEnabled(tester, 'save'), isFalse);
      await enterKey(tester, 'payment-amount-1', '300');
      expect(find.byKey(const Key('remaining')), findsNothing);
      expect(isEnabled(tester, 'save'), isTrue);
      await tapKey(tester, 'save');
      final p = f.orders.deliverCalls.single.payments;
      expect(p.map((x) => x.amount), [const Money(40000), const Money(30000)]);
      expect(p.map((x) => x.mode), everyElement(isNot(PaymentMode.advance)));
      expect(p.map((x) => x.mode).toSet(), hasLength(2));
    });

    testWidgets('a wrong amount blocks Save: it must be the balance', (
      tester,
    ) async {
      await openDetail(tester);
      await tapKey(tester, 'deliver');
      await enterKey(tester, 'payment-amount-0', '1200');
      expect(textOf(tester, 'remaining'), contains('₹500.00'));
      expect(
        find.byKey(const Key('payment-error-sumMismatch')),
        findsOneWidget,
      );
      expect(isEnabled(tester, 'save'), isFalse);
    });

    testWidgets('cash tendered gives the change on the balance only', (
      tester,
    ) async {
      final (_, f, _) = await openDetail(tester, reviewOff: true);
      await tapKey(tester, 'deliver');
      await enterKey(tester, 'cash-tendered', '1000');
      expect(textOf(tester, 'change'), contains('₹300.00'));
      await tapKey(tester, 'save');
      expect(f.orders.deliverCalls.single.cashTendered, const Money(100000));
      expect(textOf(tester, 'saved-change'), contains('₹300.00'));
    });

    testWidgets('a refused delivery shows why and can be retried', (
      tester,
    ) async {
      final (_, f, o) = await openDetail(tester);
      await tapKey(tester, 'deliver');
      await tapKey(tester, 'save');
      f.orders.failNext = const DataFailure(
        FailureReason.ruleViolation,
        'not open',
      );
      await tapKey(tester, 'confirm');
      expect(textOf(tester, 'save-error'), contains('store rules'));
      expect(find.widgetWithText(AppBar, 'Review delivery'), findsOneWidget);
      expect(isEnabled(tester, 'confirm'), isTrue);
      await tapKey(tester, 'confirm');
      expect(f.orders.deliverCalls, hasLength(2));
      expect(f.orders.byId(o.id).status, OrderStatus.delivered);
      expect(f.orders.orders.where((x) => x.billId != null), hasLength(1));
    });

    testWidgets('an unknown failure locks Confirm so no second bill is made', (
      tester,
    ) async {
      final (_, f, _) = await openDetail(tester);
      await tapKey(tester, 'deliver');
      await tapKey(tester, 'save');
      f.orders.failNext = Exception('lost connection');
      await tapKey(tester, 'confirm');
      expect(textOf(tester, 'save-error'), contains('may have been saved'));
      expect(isEnabled(tester, 'confirm'), isFalse);
      expect(f.orders.deliverCalls, hasLength(1));
    });

    testWidgets('the delivered order moves to Recent', (tester) async {
      final (_, _, o) = await openDetail(tester, reviewOff: true);
      await tapKey(tester, 'deliver');
      await tapKey(tester, 'save');
      await tapKey(tester, 'new-bill');
      await openNav(tester, 'Orders');
      expect(find.byKey(Key('order-${o.id}')), findsNothing);
      await tapKey(tester, 'tab-recent');
      expect(textOf(tester, 'recent-status-${o.id}'), 'Delivered');
    });
  });

  group('a delivery bill', () {
    testWidgets('lists the advance as a paid line, and can not be cancelled, '
        'but can still be returned', (tester) async {
      final (_, _, _) = await openDetail(tester, reviewOff: true);
      await tapKey(tester, 'deliver');
      await tapKey(tester, 'save');
      await tapKey(tester, 'new-bill');
      await openNav(tester, 'Bills');
      await tester.tap(find.textContaining('PTB-D01-000501'));
      await tester.pumpAndSettle();
      expect(find.text('Advance paid'), findsOneWidget);
      expect(
        textOf(tester, 'cancel-blocked'),
        Messages.cancelBlocker(CancelBlocker.deliversOrder),
      );
      expect(isEnabled(tester, 'cancel-bill'), isFalse);
      expect(isEnabled(tester, 'start-return'), isTrue);
    });

    testWidgets('a return from it offers only the counter payment modes', (
      tester,
    ) async {
      await openDetail(tester, reviewOff: true);
      await tapKey(tester, 'deliver');
      await tapKey(tester, 'save');
      await tapKey(tester, 'new-bill');
      await openNav(tester, 'Bills');
      await tester.tap(find.textContaining('PTB-D01-000501'));
      await tester.pumpAndSettle();
      await tapKey(tester, 'start-return');
      await tapKey(tester, 'ret-plus-CUSTOM-CAKE');
      // It starts on how the balance was paid, not on the advance.
      expect(
        tester
            .widget<DropdownButtonFormField<PaymentMode>>(
              find.byKey(const Key('refund-mode-0')),
            )
            .initialValue,
        PaymentMode.cash,
      );
      await tapKey(tester, 'add-refund');
      for (final i in [0, 1]) {
        await tapKey(tester, 'refund-mode-$i');
        expect(
          tester
              .widgetList<DropdownMenuItem<PaymentMode>>(
                find.byType(DropdownMenuItem<PaymentMode>, skipOffstage: false),
              )
              .map((m) => m.value),
          everyElement(isIn(PaymentMode.selectable)),
        );
        await tester.tap(find.text('Cash').last);
        await tester.pumpAndSettle();
      }
    });

    test('the blocker has a message', () {
      expect(
        Messages.cancelBlocker(CancelBlocker.deliversOrder),
        contains('pre-order'),
      );
    });
  });
}
