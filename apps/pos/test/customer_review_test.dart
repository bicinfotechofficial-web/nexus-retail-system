import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_core/nexus_core.dart';

import 'helpers.dart';

/// POS-13: the Customer section, the review before saving, and the
/// WhatsApp choice (D-034, D-035).
void main() {
  group('Customer section', () {
    testWidgets('cannot continue without a valid name and mobile', (
      tester,
    ) async {
      final b = await openPaymentPage(tester);
      // Nothing entered: the button is off and says Review.
      expect(isEnabled(tester, 'save'), isFalse);
      expect(textOf(tester, 'save'), contains('Review'));

      // A name alone is not enough.
      await enterKey(tester, 'customer-name', 'Test Customer');
      expect(isEnabled(tester, 'save'), isFalse);

      // A short, then a wrong-start mobile shows a message as you type.
      await enterKey(tester, 'customer-phone', '98765');
      expect(
        find.text('Enter a 10-digit mobile number starting with 6, 7, 8 or 9.'),
        findsOneWidget,
      );
      expect(isEnabled(tester, 'save'), isFalse);
      await enterKey(tester, 'customer-phone', '1234567890');
      expect(find.textContaining('starting with 6, 7, 8 or 9'), findsOne);
      expect(isEnabled(tester, 'save'), isFalse);

      await enterKey(tester, 'customer-phone', '9876543210');
      expect(find.textContaining('starting with'), findsNothing);
      expect(isEnabled(tester, 'save'), isTrue);

      // A blank name (spaces) and an over-long name turn it off again.
      await enterKey(tester, 'customer-name', '   ');
      expect(isEnabled(tester, 'save'), isFalse);
      await enterKey(tester, 'customer-name', 'A' * 61);
      expect(find.text('Name can be at most 60 characters.'), findsOneWidget);
      expect(isEnabled(tester, 'save'), isFalse);
      await enterKey(tester, 'customer-name', 'A' * 60);
      expect(isEnabled(tester, 'save'), isTrue);
      expect(b.sales.createCalls, isEmpty);
    });

    testWidgets('a pasted +91 number is accepted and tidied', (tester) async {
      final b = await openPaymentPage(tester);
      await enterKey(tester, 'customer-name', 'Test Customer');
      await enterKey(tester, 'customer-phone', '+91 98765 43210');
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('customer-phone')))
            .controller!
            .text,
        '9876543210',
      );
      await tapKey(tester, 'save');
      await tapKey(tester, 'confirm');
      expect(b.sales.createCalls.single.customer.phone, '9876543210');
    });

    testWidgets('Same as mobile is the default and sends the mobile', (
      tester,
    ) async {
      final b = await openPaymentPage(tester);
      expect(find.byKey(const Key('customer-whatsapp')), findsNothing);
      await fillCustomer(tester, name: '  Test   Customer ');
      await saveWithReview(tester, fill: false);
      final c = b.sales.createCalls.single.customer;
      expect(c.name, 'Test Customer'); // trimmed and collapsed
      expect(c.phone, '9876543210');
      expect(c.whatsapp, '9876543210');
      expect(c.id, CustomerId.of('9876543210', 'Test Customer'));
    });

    testWidgets('Different number sends the typed number, validated', (
      tester,
    ) async {
      final b = await openPaymentPage(tester);
      await fillCustomer(tester);
      await tapKey(tester, 'wa-different');
      expect(find.byKey(const Key('customer-whatsapp')), findsOneWidget);
      // Chosen but empty: not valid yet.
      expect(isEnabled(tester, 'save'), isFalse);
      await enterKey(tester, 'customer-whatsapp', '12345');
      expect(find.textContaining('starting with'), findsOneWidget);
      expect(isEnabled(tester, 'save'), isFalse);
      await enterKey(tester, 'customer-whatsapp', '+91 91234 56780');
      expect(isEnabled(tester, 'save'), isTrue);

      await saveWithReview(tester, fill: false);
      final c = b.sales.createCalls.single.customer;
      expect(c.phone, '9876543210');
      expect(c.whatsapp, '9123456780');
    });

    testWidgets('No WhatsApp sends null', (tester) async {
      final b = await openPaymentPage(tester);
      await fillCustomer(tester);
      await tapKey(tester, 'wa-none');
      expect(find.byKey(const Key('customer-whatsapp')), findsNothing);
      expect(isEnabled(tester, 'save'), isTrue);
      await saveWithReview(tester, fill: false);
      final c = b.sales.createCalls.single.customer;
      expect(c.phone, '9876543210');
      expect(c.whatsapp, isNull);
    });
  });

  group('Review', () {
    testWidgets('shows everything read-only, and Confirm saves it', (
      tester,
    ) async {
      final b = await openPaymentPage(tester);
      await tapText(tester, '% Off');
      await enterKey(tester, 'discount-input', '5');
      await enterKey(tester, 'cash-tendered', '500');
      await fillCustomer(tester);
      await tapKey(tester, 'wa-none');
      await tapKey(tester, 'save');

      expect(find.widgetWithText(AppBar, 'Review bill'), findsOneWidget);
      expect(textOf(tester, 'review-customer-name'), contains('Test Customer'));
      expect(textOf(tester, 'review-customer-phone'), contains('9876543210'));
      expect(
        textOf(tester, 'review-customer-whatsapp'),
        contains('No WhatsApp'),
      );
      expect(find.text('Black Forest 500 g × 1'), findsOneWidget);
      // 5% of 450.00 = 22.50; 427.50 rounds to 428 (round-off +0.50).
      expect(textOf(tester, 'review-discount'), contains('-₹22.50'));
      expect(textOf(tester, 'review-round-off'), contains('₹0.50'));
      expect(textOf(tester, 'review-total'), contains('₹428.00'));
      expect(find.text('Cash'), findsOneWidget);
      expect(textOf(tester, 'review-tendered'), contains('₹500.00'));
      expect(textOf(tester, 'review-change'), contains('₹72.00'));
      // Nothing is saved yet.
      expect(b.sales.createCalls, isEmpty);
      expect(b.bills.all('PTB'), isEmpty);

      await tapKey(tester, 'confirm');
      expect(b.sales.createCalls, hasLength(1));
      expect(textOf(tester, 'bill-no'), 'PTB-D01-000001');
    });

    testWidgets('Same as mobile reads as such on the review', (tester) async {
      await openPaymentPage(tester);
      await fillCustomer(tester);
      await tapKey(tester, 'save');
      expect(
        textOf(tester, 'review-customer-whatsapp'),
        contains('Same as mobile'),
      );
    });

    testWidgets('Back keeps the cart, payments and customer entries', (
      tester,
    ) async {
      final b = await openPaymentPage(tester);
      await tapText(tester, '₹ Flat');
      await enterKey(tester, 'discount-input', '20');
      await tapKey(tester, 'add-payment');
      await enterKey(tester, 'payment-amount-0', '200');
      await enterKey(tester, 'payment-amount-1', '230');
      await enterKey(tester, 'cash-tendered', '250');
      await fillCustomer(tester, name: 'Sample Buyer', phone: '9123456780');
      await tapKey(tester, 'wa-different');
      await enterKey(tester, 'customer-whatsapp', '9988776655');
      await tapKey(tester, 'save');
      expect(find.widgetWithText(AppBar, 'Review bill'), findsOneWidget);

      await tapKey(tester, 'review-back');
      expect(find.widgetWithText(AppBar, 'Payment'), findsOneWidget);
      String text(String key) =>
          tester.widget<TextField>(find.byKey(Key(key))).controller!.text;
      expect(text('customer-name'), 'Sample Buyer');
      expect(text('customer-phone'), '9123456780');
      expect(text('customer-whatsapp'), '9988776655');
      expect(text('discount-input'), '20');
      expect(text('payment-amount-0'), '200');
      expect(text('payment-amount-1'), '230');
      expect(text('cash-tendered'), '250');
      expect(textOf(tester, 'total'), contains('₹430.00'));
      expect(b.sales.createCalls, isEmpty);

      // And the same entries go through when confirmed.
      await tapKey(tester, 'save');
      await tapKey(tester, 'confirm');
      final sent = b.sales.createCalls.single;
      expect(sent.customer.name, 'Sample Buyer');
      expect(sent.customer.whatsapp, '9988776655');
      expect(sent.payments, hasLength(2));
      expect(sent.cashTendered, const Money(25000));
    });

    testWidgets('Confirm twice makes one bill', (tester) async {
      final b = await openPaymentPage(tester);
      await fillCustomer(tester);
      await tapKey(tester, 'save');
      final confirm = find.byKey(const Key('confirm'));
      await tester.tap(confirm);
      await tester.tap(confirm, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(b.sales.createCalls, hasLength(1));
      expect(b.bills.all('PTB'), hasLength(1));
    });

    testWidgets('a double tap on Review opens it once', (tester) async {
      await openPaymentPage(tester);
      await fillCustomer(tester);
      final save = find.byKey(const Key('save'));
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.tap(save, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Review bill'), findsOneWidget);
      await tapKey(tester, 'review-back');
      expect(find.widgetWithText(AppBar, 'Payment'), findsOneWidget);
    });
  });
}
