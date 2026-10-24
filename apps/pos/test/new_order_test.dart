import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';
import 'package:nexus_pos/fakes/fake_backend.dart';
import 'package:nexus_printer/nexus_printer.dart';

import 'helpers.dart';

/// POS-21: the new-order form and the saved page (D-043). "Today" is
/// 2026-09-26.
Future<(FakeBackend, PreorderFakes)> openForm(
  WidgetTester tester, {
  void Function(FakeBackend)? seed,
}) async {
  final b = fakeBackend();
  seed?.call(b);
  final f = PreorderFakes(b);
  await pumpPos(tester, backend: b, fakes: f);
  await openNav(tester, 'Orders');
  await tapKey(tester, 'new-order');
  expect(find.widgetWithText(AppBar, 'New order'), findsOneWidget);
  return (b, f);
}

/// Picks day [day] of September 2026 in the date picker.
Future<void> pickDay(WidgetTester tester, int day) async {
  await tapKey(tester, 'order-due-date');
  await tester.tap(find.text('$day').last);
  await tester.pumpAndSettle();
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

Future<void> fillForm(
  WidgetTester tester, {
  String name = 'Meera Nair',
  String phone = '9876543210',
  int day = 29,
  String description = 'Red Velvet, 2 kg\nWrite "Happy Birthday Ammu"',
  String price = '2400',
  String advance = '1000',
  String? mode = 'UPI',
}) async {
  await enterKey(tester, 'customer-name', name);
  await enterKey(tester, 'customer-phone', phone);
  await pickDay(tester, day);
  await enterKey(tester, 'order-description-input', description);
  await enterKey(tester, 'order-price-input', price);
  await enterKey(tester, 'order-advance-input', advance);
  if (mode != null) await tapKey(tester, 'order-mode-$mode');
}

String? errorOf(WidgetTester tester, String key) {
  final f = find.byKey(Key(key));
  if (f.evaluate().isEmpty) return null;
  final w = tester.widget(f);
  return w is Text ? w.data : null;
}

/// The error text of the TextField under [key], or null.
String? fieldError(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(Key(key))).decoration?.errorText;

void main() {
  group('validation', () {
    testWidgets('Save on an empty form says what is missing and saves '
        'nothing', (tester) async {
      final (_, f) = await openForm(tester);
      await tapKey(tester, 'save-order');
      expect(
        textOf(tester, 'order-customer-error'),
        CustomerValidator.nameError('')!,
      );
      expect(textOf(tester, 'order-date-error'), 'Pick the delivery date.');
      expect(
        fieldError(tester, 'order-description-input'),
        'Describe the cake.',
      );
      expect(fieldError(tester, 'order-price-input'), 'Enter the price.');
      expect(f.orders.createCalls, isEmpty);
      expect(find.widgetWithText(AppBar, 'New order'), findsOneWidget);
    });

    testWidgets('a bad mobile number is reported', (tester) async {
      final (_, f) = await openForm(tester);
      await enterKey(tester, 'customer-name', 'Meera');
      await enterKey(tester, 'customer-phone', '12345');
      await tapKey(tester, 'save-order');
      expect(
        textOf(tester, 'order-customer-error'),
        CustomerValidator.phoneError('12345')!,
      );
      expect(f.orders.createCalls, isEmpty);
    });

    testWidgets('a different WhatsApp number must be valid too', (
      tester,
    ) async {
      final (_, f) = await openForm(tester);
      await fillForm(tester, mode: 'CASH');
      await tapKey(tester, 'wa-different');
      await enterKey(tester, 'customer-whatsapp', '123');
      await tapKey(tester, 'save-order');
      expect(
        textOf(tester, 'order-customer-error'),
        CustomerValidator.phoneError('123')!,
      );
      expect(f.orders.createCalls, isEmpty);
    });

    testWidgets('price messages: not a number, paise, zero', (tester) async {
      await openForm(tester);
      await enterKey(tester, 'order-price-input', 'abc');
      expect(
        fieldError(tester, 'order-price-input'),
        'Enter an amount, like 1200.',
      );
      await enterKey(tester, 'order-price-input', '1200.50');
      expect(fieldError(tester, 'order-price-input'), 'Use whole rupees.');
      await enterKey(tester, 'order-price-input', '0');
      expect(fieldError(tester, 'order-price-input'), 'Enter the price.');
      await enterKey(tester, 'order-price-input', '1200');
      expect(fieldError(tester, 'order-price-input'), isNull);
    });

    testWidgets('advance messages: more than the price, paise, no mode', (
      tester,
    ) async {
      await openForm(tester);
      await enterKey(tester, 'order-price-input', '1000');
      await enterKey(tester, 'order-advance-input', '1500');
      expect(
        fieldError(tester, 'order-advance-input'),
        'The advance is more than the price.',
      );
      await enterKey(tester, 'order-advance-input', '500.25');
      expect(fieldError(tester, 'order-advance-input'), 'Use whole rupees.');
      await enterKey(tester, 'order-advance-input', 'five');
      expect(
        fieldError(tester, 'order-advance-input'),
        'Enter an amount, like 500.',
      );
      await enterKey(tester, 'order-advance-input', '500');
      expect(
        fieldError(tester, 'order-advance-input'),
        'Choose how the advance was paid.',
      );
      await tapKey(tester, 'order-mode-CARD');
      expect(fieldError(tester, 'order-advance-input'), isNull);
      // A full advance is allowed.
      await enterKey(tester, 'order-advance-input', '1000');
      expect(fieldError(tester, 'order-advance-input'), isNull);
    });

    testWidgets('a missing mode blocks Save with its message', (tester) async {
      final (_, f) = await openForm(tester);
      await fillForm(tester, mode: null);
      await tapKey(tester, 'save-order');
      expect(
        fieldError(tester, 'order-advance-input'),
        'Choose how the advance was paid.',
      );
      expect(f.orders.createCalls, isEmpty);
    });

    testWidgets('the description counts characters and complains past the '
        'limit', (tester) async {
      await openForm(tester);
      expect(find.text('0/${Limits.orderDescriptionMax}'), findsOneWidget);
      await enterKey(tester, 'order-description-input', 'a' * 120);
      expect(find.text('120/${Limits.orderDescriptionMax}'), findsOneWidget);
      expect(fieldError(tester, 'order-description-input'), isNull);
      await enterKey(
        tester,
        'order-description-input',
        'a' * (Limits.orderDescriptionMax + 1),
      );
      expect(
        find.text(
          '${Limits.orderDescriptionMax + 1}/${Limits.orderDescriptionMax}',
        ),
        findsOneWidget,
      );
      expect(
        fieldError(tester, 'order-description-input'),
        'At most ${Limits.orderDescriptionMax} characters.',
      );
      await enterKey(
        tester,
        'order-description-input',
        'a' * Limits.orderDescriptionMax,
      );
      expect(fieldError(tester, 'order-description-input'), isNull);
    });
  });

  group('the form', () {
    testWidgets('shows the live balance and only offers a mode with an '
        'advance', (tester) async {
      await openForm(tester);
      expect(textOf(tester, 'order-balance'), contains('—'));
      expect(find.byKey(const Key('order-mode-CASH')), findsNothing);

      await enterKey(tester, 'order-price-input', '1200');
      expect(textOf(tester, 'order-balance'), contains('₹1,200.00'));
      expect(find.byKey(const Key('order-mode-CASH')), findsNothing);

      await enterKey(tester, 'order-advance-input', '500');
      expect(textOf(tester, 'order-balance'), contains('₹700.00'));
      // The modes the counter offers, and never ADVANCE.
      for (final m in PaymentMode.selectable) {
        expect(find.byKey(Key('order-mode-${m.wire}')), findsOneWidget);
      }
      expect(find.byKey(const Key('order-mode-ADVANCE')), findsNothing);
      expect(find.text('Advance paid'), findsNothing);

      await enterKey(tester, 'order-advance-input', '1200');
      expect(textOf(tester, 'order-balance'), contains('₹0.00'));
      await enterKey(tester, 'order-advance-input', '');
      expect(textOf(tester, 'order-balance'), contains('₹1,200.00'));
      expect(find.byKey(const Key('order-mode-CASH')), findsNothing);
    });

    testWidgets('the date picker runs from today to 90 days ahead', (
      tester,
    ) async {
      await openForm(tester);
      await tapKey(tester, 'order-due-date');
      final cal = tester.widget<CalendarDatePicker>(
        find.byType(CalendarDatePicker),
      );
      expect(cal.firstDate, DateTime(2026, 9, 26));
      expect(cal.lastDate, DateTime(2026, 12, 25));
      expect(cal.initialDate, DateTime(2026, 9, 26));
    });

    testWidgets('the time is optional and can be removed', (tester) async {
      await openForm(tester);
      expect(find.byKey(const Key('order-due-time-clear')), findsNothing);
      await tapKey(tester, 'order-due-time');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const Key('order-due-time')),
          matching: find.text('12:00'),
        ),
        findsOneWidget,
      );
      await tapKey(tester, 'order-due-time-clear');
      expect(find.text('Add a time (optional)'), findsOneWidget);
    });

    testWidgets('a saved customer is offered from the mobile number, as on a '
        'bill', (tester) async {
      await openForm(
        tester,
        seed: (b) => b.customers.recordBill(
          Seed.locationId,
          BillCustomer(
            name: 'Radha Menon',
            phone: '9123456780',
            whatsapp: '9988776655',
          ),
          total: const Money(10000),
          billId: 'D01-000001',
          at: testNow,
        ),
      );
      await enterKey(tester, 'customer-phone', '9123');
      await tester.tap(find.textContaining('Radha Menon'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('customer-name')))
            .controller!
            .text,
        'Radha Menon',
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('customer-whatsapp')))
            .controller!
            .text,
        '9988776655',
      );
    });
  });

  group('saving', () {
    testWidgets('creates the order once, with everything entered, and shows '
        'the saved page', (tester) async {
      final (_, f) = await openForm(tester);
      await fillForm(tester);
      await tapKey(tester, 'order-due-time');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tapKey(tester, 'save-order');

      expect(f.orders.createCalls, hasLength(1));
      final c = f.orders.createCalls.single;
      expect(c.customer.name, 'Meera Nair');
      expect(c.customer.phone, '9876543210');
      expect(c.customer.whatsapp, '9876543210');
      expect(c.dueDate, '2026-09-29');
      expect(c.dueTime, '12:00');
      expect(c.description, 'Red Velvet, 2 kg\nWrite "Happy Birthday Ammu"');
      expect(c.price, const Money(240000));
      expect(c.advance, const Money(100000));
      expect(c.advanceMode, PaymentMode.upi);

      expect(find.widgetWithText(AppBar, 'Order saved'), findsOneWidget);
      expect(textOf(tester, 'order-no'), 'PTB-D01-O000001');
      expect(textOf(tester, 'order-customer'), contains('Meera Nair'));
      expect(textOf(tester, 'order-price'), contains('₹2,400.00'));
      expect(textOf(tester, 'order-advance'), contains('₹1,000.00'));
      expect(textOf(tester, 'order-advance'), contains('UPI'));
      expect(textOf(tester, 'order-balance'), contains('₹1,400.00'));
      expect(
        find.text('Red Velvet, 2 kg\nWrite "Happy Birthday Ammu"'),
        findsOneWidget,
      );
      // Nothing is printed or shared by itself.
      expect(f.slips.printed, isEmpty);
      expect(f.slips.shared, isEmpty);
    });

    testWidgets('no advance means no mode is sent, even if one was picked '
        'before', (tester) async {
      final (_, f) = await openForm(tester);
      await fillForm(tester, advance: '500', mode: 'CASH');
      await enterKey(tester, 'order-advance-input', '0');
      await tapKey(tester, 'save-order');
      final c = f.orders.createCalls.single;
      expect(c.advance, Money.zero);
      expect(c.advanceMode, isNull);
    });

    testWidgets('the WhatsApp choices follow the bill rules (D-034)', (
      tester,
    ) async {
      final (_, f) = await openForm(tester);
      await fillForm(tester, mode: 'CASH');
      await tapKey(tester, 'wa-none');
      await tapKey(tester, 'save-order');
      expect(f.orders.createCalls.single.customer.whatsapp, isNull);

      final (_, f2) = await openForm(tester);
      await fillForm(tester, mode: 'CASH');
      await tapKey(tester, 'wa-different');
      await enterKey(tester, 'customer-whatsapp', '9123456780');
      await tapKey(tester, 'save-order');
      expect(f2.orders.createCalls.single.customer.whatsapp, '9123456780');
    });

    testWidgets('a double tap on Save creates one order', (tester) async {
      final (_, f) = await openForm(tester);
      await fillForm(tester);
      f.orders.gate = Completer<void>();
      final save = find.byKey(const Key('save-order'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pump();
      await tester.tap(save, warnIfMissed: false);
      await tester.pump();
      expect(f.orders.createCalls, hasLength(1));
      expect(isEnabled(tester, 'save-order'), isFalse);
      f.orders.gate!.complete();
      await tester.pumpAndSettle();
      expect(f.orders.createCalls, hasLength(1));
      expect(find.widgetWithText(AppBar, 'Order saved'), findsOneWidget);
    });

    testWidgets('a refused order shows the mapped message and can be tried '
        'again', (tester) async {
      final (_, f) = await openForm(tester);
      await fillForm(tester);
      f.orders.failNext = const DataFailure(FailureReason.notPermitted);
      await tapKey(tester, 'save-order');
      expect(
        textOf(tester, 'save-error'),
        "You don't have permission to do this.",
      );
      expect(find.widgetWithText(AppBar, 'New order'), findsOneWidget);
      expect(isEnabled(tester, 'save-order'), isTrue);
      await tapKey(tester, 'save-order');
      expect(find.widgetWithText(AppBar, 'Order saved'), findsOneWidget);
      expect(f.orders.createCalls, hasLength(2));
      expect(f.orders.orders, hasLength(1));
    });

    testWidgets('an unknown failure locks Save, so no second order is made', (
      tester,
    ) async {
      final (_, f) = await openForm(tester);
      await fillForm(tester);
      f.orders.failNext = Exception('lost connection');
      await tapKey(tester, 'save-order');
      expect(textOf(tester, 'save-error'), contains('may have been saved'));
      expect(isEnabled(tester, 'save-order'), isFalse);
      expect(f.orders.createCalls, hasLength(1));
    });
  });

  group('the saved page', () {
    Future<PreorderFakes> saved(WidgetTester tester) async {
      final (_, f) = await openForm(tester);
      await fillForm(tester);
      await tapKey(tester, 'save-order');
      expect(find.widgetWithText(AppBar, 'Order saved'), findsOneWidget);
      return f;
    }

    testWidgets('prints the advance slip through the seam', (tester) async {
      final f = await saved(tester);
      expect(find.text('Print advance slip'), findsOneWidget);
      await tapKey(tester, 'print-button');
      expect(f.slips.printed.single.orderNo, 'PTB-D01-O000001');
      expect(textOf(tester, 'print-ok'), 'Slip printed.');
    });

    testWidgets('a printer fault offers a retry, not an error', (tester) async {
      final f = await saved(tester);
      f.slips.nextPrints.add(const PrintFailed('Printer is off'));
      await tapKey(tester, 'print-button');
      expect(
        textOf(tester, 'print-failed'),
        "The order is saved, but the slip didn't print: Printer is off",
      );
      await tapKey(tester, 'retry-print');
      expect(f.slips.printed, hasLength(2));
      expect(find.byKey(const Key('print-ok')), findsOneWidget);
      expect(isEnabled(tester, 'order-done'), isTrue);
    });

    testWidgets('shares the slip image through the seam', (tester) async {
      final f = await saved(tester);
      expect(find.text('Share slip image'), findsOneWidget);
      await tapKey(tester, 'share-slip');
      expect(f.slips.shared.single.id, 'D01-O000001');
      expect(find.byKey(const Key('slip-problem')), findsNothing);
    });

    testWidgets('a share that fails shows a message and can be retried', (
      tester,
    ) async {
      final f = await saved(tester);
      f.slips.failShare = Exception('no share sheet');
      await tapKey(tester, 'share-slip');
      expect(
        textOf(tester, 'slip-problem'),
        "Couldn't share the slip image. Please try again.",
      );
      await tapKey(tester, 'share-slip');
      expect(f.slips.shared, hasLength(1));
      expect(find.byKey(const Key('slip-problem')), findsNothing);
    });

    testWidgets('Done goes to the Orders list, where the order is', (
      tester,
    ) async {
      await saved(tester);
      await tapKey(tester, 'order-done');
      expect(find.widgetWithText(AppBar, 'Orders'), findsOneWidget);
      expect(find.byKey(const Key('order-D01-O000001')), findsOneWidget);
    });
  });
}
