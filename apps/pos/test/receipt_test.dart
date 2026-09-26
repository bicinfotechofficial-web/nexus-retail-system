import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_pos/fakes/fake_backend.dart';
import 'package:nexus_printer/nexus_printer.dart';

import 'helpers.dart';

/// Rings up a Black Forest 500 g and saves it with the whole amount in cash.
Future<void> saveOneBill(WidgetTester tester) async {
  await tapKey(tester, 'product-bf-500');
  await tapKey(tester, 'charge');
  await tapKey(tester, 'save');
}

void main() {
  group('after Save (POS-6)', () {
    testWidgets('previews the receipt text from PrinterService.previewBill', (
      tester,
    ) async {
      final b = await pumpPos(tester);
      await saveOneBill(tester);
      final bill = b.printer.printedBills.single;
      final text = tester.widget<Text>(find.byKey(const Key('receipt-text')));
      expect(text.data, b.printer.previewBill(bill, Seed.location));
      expect(text.data, contains('PTB-D01-000001'));
      expect(text.data, isNot(contains('REPRINT')));
      expect(text.style?.fontFamily, 'monospace');
    });

    testWidgets('a retry after a failure is the first copy, not a reprint', (
      tester,
    ) async {
      final b = await pumpPos(tester);
      b.printer.nextResults.add(const PrintFailed('Paper out'));
      await saveOneBill(tester);
      expect(textOf(tester, 'print-failed'), contains('Paper out'));
      expect(textOf(tester, 'print-failed'), contains('The bill is saved'));

      await tapKey(tester, 'retry-print');
      expect(find.byKey(const Key('print-ok')), findsOneWidget);
      expect(b.printer.reprintFlags, [false, false]);

      // Printing again after a good copy is a reprint.
      await tapKey(tester, 'print-again');
      expect(b.printer.reprintFlags, [false, false, true]);
      expect(b.sales.createCalls, hasLength(1));
    });

    testWidgets('a printer that throws is handled like a failed print', (
      tester,
    ) async {
      final b = await pumpPos(tester);
      b.printer.throwNext = StateError('Bluetooth off');
      await saveOneBill(tester);
      expect(textOf(tester, 'print-failed'), contains('Bluetooth off'));
      expect(find.byKey(const Key('retry-print')), findsOneWidget);
    });
  });

  group('reprint from a past bill (POS-6)', () {
    testWidgets('passes reprint: true and previews it', (tester) async {
      final b = fakeBackend();
      await addBill(b, {
        'bf-500': 1,
      }, at: testNow.subtract(const Duration(days: 1)));
      await pumpPos(tester, backend: b);
      await openNav(tester, 'Bills');
      await tapKey(tester, 'date-prev');
      await tapKey(tester, 'bill-D01-000001');

      await tapKey(tester, 'view-receipt');
      final preview = tester.widget<Text>(
        find.byKey(const Key('receipt-text')),
      );
      expect(preview.data, contains('REPRINT'));
      await tapKey(tester, 'close-preview');

      await tapKey(tester, 'print-button');
      expect(b.printer.printedBills.single.id, 'D01-000001');
      expect(b.printer.reprintFlags, [true]);
      expect(find.byKey(const Key('print-ok')), findsOneWidget);
    });

    testWidgets('a failed reprint offers a retry', (tester) async {
      final b = fakeBackend();
      await addBill(b, {'bf-500': 1});
      await openBill(tester, b, 'D01-000001');
      b.printer.nextResults.add(const PrintFailed('Printer is off'));
      await tapKey(tester, 'print-button');
      expect(textOf(tester, 'print-failed'), contains('Printer is off'));
      await tapKey(tester, 'retry-print');
      expect(find.byKey(const Key('print-ok')), findsOneWidget);
      expect(b.printer.reprintFlags, [true, true]);
    });

    testWidgets('a cancelled bill reprints with its banner', (tester) async {
      final b = fakeBackend();
      final bill = await addBill(b, {'bf-500': 1});
      await b.sales.cancelBill(billId: bill.id, reason: 'Duplicate');
      await openBill(tester, b, bill.id);
      await tapKey(tester, 'print-button');
      expect(b.printer.printedBills.single.status.name, 'cancelled');
      await tapKey(tester, 'view-receipt');
      expect(find.textContaining('CANCELLED'), findsWidgets);
    });
  });
}
