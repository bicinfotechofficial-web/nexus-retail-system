import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_pos/app/share.dart';
import 'package:nexus_pos/fakes/fake_backend.dart';
import 'package:nexus_printer/nexus_printer.dart';

import 'helpers.dart';

/// POS-13 result screen and POS-14 WhatsApp sharing (D-035, D-036).
Future<void> saveBill(
  WidgetTester tester, {
  String name = 'Test Customer',
  String phone = '9876543210',
  String? choice,
  String? whatsapp,
}) async {
  await tapKey(tester, 'product-bf-500');
  await tapKey(tester, 'charge');
  await fillCustomer(tester, name: name, phone: phone);
  if (choice != null) await tapKey(tester, choice);
  if (whatsapp != null) await enterKey(tester, 'customer-whatsapp', whatsapp);
  await tapKey(tester, 'save');
  await tapKey(tester, 'confirm');
}

String expectedText(FakeBackend b) => WhatsappReceipt.build(
  shopName: 'Caramel Cottage',
  locationName: Seed.location.name,
  bill: b.bills.all(Seed.locationId).single,
);

void main() {
  group('result screen', () {
    testWidgets('shows the bill number and total, with all four buttons', (
      tester,
    ) async {
      final b = await pumpPos(tester);
      await saveBill(tester);
      expect(find.widgetWithText(AppBar, 'Bill saved'), findsOneWidget);
      expect(textOf(tester, 'bill-no'), 'PTB-D01-000001');
      expect(find.text('₹450.00'), findsWidgets);
      expect(find.byKey(const Key('print-button')), findsOneWidget);
      expect(find.byKey(const Key('whatsapp-message')), findsOneWidget);
      expect(find.byKey(const Key('whatsapp-image')), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Done'), findsOneWidget);
      // Nothing was printed or shared by itself.
      expect(b.printer.printedBills, isEmpty);
      expect(b.fakeLinks.opened, isEmpty);
      expect(b.fakeShares.shared, isEmpty);
    });

    testWidgets('a bill with no print is fine: Done goes to a fresh cart', (
      tester,
    ) async {
      final b = await pumpPos(tester);
      await saveBill(tester);
      await tapKey(tester, 'new-bill');
      expect(find.widgetWithText(AppBar, 'Billing'), findsOneWidget);
      expect(isEnabled(tester, 'charge'), isFalse);
      expect(b.printer.printedBills, isEmpty);
      expect(b.bills.all(Seed.locationId), hasLength(1));
    });

    testWidgets('Print is optional and a printer fault never blocks', (
      tester,
    ) async {
      final b = await pumpPos(tester);
      b.printer.nextResults.add(const PrintFailed('Printer is off'));
      await saveBill(tester);
      await tapKey(tester, 'print-button');
      expect(textOf(tester, 'print-failed'), contains('The bill is saved'));
      // The other buttons and Done still work after the fault.
      expect(isEnabled(tester, 'new-bill'), isTrue);
      await tapKey(tester, 'whatsapp-message');
      expect(b.fakeLinks.opened, hasLength(1));
      await tapKey(tester, 'new-bill');
      expect(find.widgetWithText(AppBar, 'Billing'), findsOneWidget);
      expect(b.sales.createCalls, hasLength(1));
    });

    testWidgets('the WhatsApp buttons are hidden for No WhatsApp', (
      tester,
    ) async {
      final b = await pumpPos(tester);
      await saveBill(tester, choice: 'wa-none');
      expect(textOf(tester, 'bill-no'), 'PTB-D01-000001');
      expect(find.byKey(const Key('whatsapp-message')), findsNothing);
      expect(find.byKey(const Key('whatsapp-image')), findsNothing);
      expect(find.byKey(const Key('print-button')), findsOneWidget);
      expect(find.byKey(const Key('new-bill')), findsOneWidget);
      expect(b.bills.all(Seed.locationId).single.customer?.whatsapp, isNull);
    });
  });

  group('WhatsApp message', () {
    testWidgets('opens the wa.me link with the receipt text', (tester) async {
      final b = await pumpPos(tester);
      await saveBill(tester);
      await tapKey(tester, 'whatsapp-message');
      final link = b.fakeLinks.opened.single;
      expect(link.host, 'wa.me');
      expect(link.path, '/919876543210');
      expect(link.queryParameters['text'], expectedText(b));
      expect(link, WhatsappReceipt.link('9876543210', expectedText(b)));
      expect(link.queryParameters['text'], contains('PTB-D01-000001'));
      expect(link.queryParameters['text'], contains('Caramel Cottage'));
      expect(link.queryParameters['text'], contains(Seed.location.name));
      expect(link.queryParameters['text'], contains('Hi Test Customer'));
      expect(find.byKey(const Key('whatsapp-problem')), findsNothing);
      // Opening WhatsApp creates nothing.
      expect(b.sales.createCalls, hasLength(1));
    });

    testWidgets('goes to the different number when one was typed', (
      tester,
    ) async {
      final b = await pumpPos(tester);
      await saveBill(tester, choice: 'wa-different', whatsapp: '9123456780');
      await tapKey(tester, 'whatsapp-message');
      expect(b.fakeLinks.opened.single.path, '/919123456780');
    });

    testWidgets("says so when WhatsApp isn't installed", (tester) async {
      final b = await pumpPos(tester);
      b.fakeLinks.canOpen = false;
      await saveBill(tester);
      await tapKey(tester, 'whatsapp-message');
      expect(
        textOf(tester, 'whatsapp-problem'),
        "WhatsApp isn't installed on this phone.",
      );
      // The buttons stay usable, so it can be tried again.
      b.fakeLinks.canOpen = true;
      await tapKey(tester, 'whatsapp-message');
      expect(find.byKey(const Key('whatsapp-problem')), findsNothing);
      expect(b.fakeLinks.opened, hasLength(2));
    });
  });

  group('WhatsApp image', () {
    testWidgets('renders at the paper width and hands it to the sharer', (
      tester,
    ) async {
      final b = await pumpPos(tester);
      await b.printer.setPaperWidth(PaperWidth.mm58);
      await saveBill(tester);
      await tapKey(tester, 'whatsapp-image');
      expect(b.fakeRenders.calls, hasLength(1));
      expect(b.fakeRenders.calls.single.$2, PaperWidth.mm58);
      final shared = b.fakeShares.shared.single;
      expect(shared.fileName, 'D01-000001.png');
      expect(shared.png, FakeReceiptRenderer.bytes);
      expect(shared.text, contains('PTB-D01-000001'));
      expect(find.byKey(const Key('whatsapp-problem')), findsNothing);
    });

    testWidgets('a share that fails shows a message and can be retried', (
      tester,
    ) async {
      final b = await pumpPos(tester);
      b.fakeShares.failNext = Exception('no share sheet');
      await saveBill(tester);
      await tapKey(tester, 'whatsapp-image');
      expect(
        textOf(tester, 'whatsapp-problem'),
        "Couldn't share the receipt image. Please try again.",
      );
      await tapKey(tester, 'whatsapp-image');
      expect(b.fakeShares.shared, hasLength(1));
      expect(find.byKey(const Key('whatsapp-problem')), findsNothing);
    });

    testWidgets('the real renderer makes a PNG of the saved bill', (
      tester,
    ) async {
      final b = fakeBackend();
      final bill = await addBill(b, {'bf-500': 1});
      final png = await tester.runAsync(
        () => renderReceiptImage(
          ReceiptDocument.fromBill(bill, Seed.location),
          PaperWidth.mm80,
        ),
      );
      expect(png!.sublist(0, 8), [
        0x89,
        0x50,
        0x4e,
        0x47,
        0x0d,
        0x0a,
        0x1a,
        0x0a,
      ]);
    });
  });

  group('saved bill detail', () {
    testWidgets('shows the customer and re-sends by message and image', (
      tester,
    ) async {
      final b = fakeBackend();
      final bill = await addBill(
        b,
        {'bf-500': 1},
        customer: testCustomer(
          name: 'Sample Buyer',
          phone: '9123456780',
          whatsapp: '9988776655',
        ),
      );
      await openBill(tester, b, bill.id);
      expect(textOf(tester, 'detail-customer-name'), contains('Sample Buyer'));
      expect(textOf(tester, 'detail-customer-phone'), contains('9123456780'));
      expect(
        textOf(tester, 'detail-customer-whatsapp'),
        contains('9988776655'),
      );

      await tapKey(tester, 'whatsapp-message');
      expect(b.fakeLinks.opened.single.path, '/919988776655');
      expect(
        b.fakeLinks.opened.single.queryParameters['text'],
        contains('Hi Sample Buyer'),
      );
      await tapKey(tester, 'whatsapp-image');
      expect(b.fakeShares.shared.single.fileName, '${bill.id}.png');
      expect(b.sales.createCalls, isEmpty);
    });

    testWidgets('no WhatsApp buttons for a customer without WhatsApp', (
      tester,
    ) async {
      final b = fakeBackend();
      final bill = await addBill(b, {
        'bf-500': 1,
      }, customer: testCustomer(whatsapp: null));
      await openBill(tester, b, bill.id);
      expect(
        textOf(tester, 'detail-customer-whatsapp'),
        contains('No WhatsApp'),
      );
      expect(find.byKey(const Key('whatsapp-message')), findsNothing);
      expect(find.byKey(const Key('whatsapp-image')), findsNothing);
    });

    testWidgets('an old bill without a customer shows a dash', (tester) async {
      final b = fakeBackend();
      final made = await addBill(b, {'bf-500': 1});
      final old = Bill.fromMap(
        made.id,
        {...made.toMap()}
          ..remove('customerId')
          ..remove('customerName')
          ..remove('customerPhone')
          ..remove('customerWhatsapp'),
      );
      b.bills.put(Seed.locationId, old);
      await openBill(tester, b, old.id);
      expect(textOf(tester, 'detail-customer-name'), contains('—'));
      expect(find.byKey(const Key('whatsapp-message')), findsNothing);
    });

    testWidgets("the bills list shows each customer's name", (tester) async {
      final b = fakeBackend();
      await addBill(b, {
        'bf-500': 1,
      }, customer: testCustomer(name: 'Sample Buyer'));
      await pumpPos(tester, backend: b);
      await openNav(tester, 'Bills');
      expect(find.textContaining('Sample Buyer'), findsOneWidget);
    });
  });
}
