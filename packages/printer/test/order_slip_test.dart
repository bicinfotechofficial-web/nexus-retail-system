import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_printer/src/api.dart';
import 'package:nexus_printer/src/layout/print_line.dart';
import 'package:nexus_printer/src/layout/receipt_layout.dart';
import 'package:nexus_printer/src/receipt/order_slip.dart';

import 'fixtures.dart';

/// PR-9: the advance slip. The goldens live in `receipt_layout_test.dart`
/// with the other slips; this file pins the content rules.
void main() {
  OrderSlipDocument slip(PreOrder o) =>
      OrderSlipDocument.fromOrder(o, pilotLocation);

  List<String> lines(PreOrder o, PaperWidth w) => [
    for (final l in ReceiptLayout(w).orderSlip(slip(o))) l.text.trimRight(),
  ];

  group('OrderSlipDocument.fromOrder', () {
    test('copies what the slip prints, and leaves the phone off', () {
      final doc = slip(normalOrder());
      expect(doc.orderNo, 'PTB-D01-O000007');
      expect(doc.customerName, 'Anita Menon');
      expect(doc.dueDate, '2026-10-26');
      expect(doc.dueTime, '16:30');
      expect(doc.price, const Money.rupees(2400));
      expect(doc.advance, const Money.rupees(1000));
      expect(doc.advanceMode, PaymentMode.upi);
      expect(doc.balance, const Money.rupees(1400));
      expect(doc.header.name, 'Caramel Cottage');
      expect(doc.footer, pilotLocation.receiptFooter);
    });

    test('the same order gives the same layout', () {
      const layout = ReceiptLayout(PaperWidth.mm80);
      expect(
        renderText(layout.orderSlip(slip(normalOrder()))),
        renderText(layout.orderSlip(slip(normalOrder()))),
      );
    });

    test('no advance means no mode, even if the order carries one', () {
      expect(slip(noAdvanceOrder()).advanceMode, isNull);
      expect(slip(noAdvanceOrder()).balance, const Money.rupees(900));
    });
  });

  for (final width in PaperWidth.values) {
    group('layout, ${width.columns} columns', () {
      test('every line is exactly as wide as the paper', () {
        for (final o in [
          normalOrder(),
          longDescriptionOrder(),
          noAdvanceOrder(),
        ]) {
          for (final l in ReceiptLayout(width).orderSlip(slip(o))) {
            expect(textWidth(l.text), width.columns, reason: '"${l.text}"');
          }
        }
      });

      test('header, title, order number, name and times', () {
        final l = lines(normalOrder(), width);
        expect(l.first.trim(), 'Caramel Cottage');
        expect(l.map((e) => e.trim()), contains('ADVANCE RECEIPT'));
        expect(l, contains('Order No: PTB-D01-O000007'));
        expect(l, contains('Date: 23-10-2026 16:20'));
        expect(l, contains('Customer: Anita Menon'));
        expect(l, contains('Due date: 26-10-2026'));
        expect(l, contains('Time: 16:30'));
        expect(l.join('\n'), isNot(contains('9847012345')));
      });

      test('"Time: any" when no time was agreed', () {
        final l = lines(longDescriptionOrder(), width);
        expect(l, contains('Due date: 12-11-2026'));
        expect(l, contains('Time: any'));
      });

      test('price, advance with its mode, and the balance due', () {
        final l = lines(normalOrder(), width);
        expect(
          l.firstWhere((e) => e.startsWith('Price')),
          endsWith('₹2,400.00'),
        );
        expect(
          l.firstWhere((e) => e.startsWith('Advance (')),
          matches(RegExp(r'^Advance \(UPI\) +₹1,000\.00$')),
        );
        final balance = ReceiptLayout(
          width,
        ).orderSlip(slip(normalOrder())).singleWhere((e) => e.doubleHeight);
        expect(balance.text, startsWith('BALANCE DUE'));
        expect(balance.text.trimRight(), endsWith('₹1,400.00'));
        expect(balance.bold, isTrue);
      });

      test('a cash advance says Cash', () {
        final l = lines(longDescriptionOrder(), width);
        expect(
          l.firstWhere((e) => e.startsWith('Advance (')),
          matches(RegExp(r'^Advance \(Cash\) +₹2,500\.00$')),
        );
      });

      test('no advance: a zero advance line without a mode', () {
        final l = lines(noAdvanceOrder(), width);
        expect(
          l.firstWhere((e) => e.startsWith('Advance')),
          matches(RegExp(r'^Advance +₹0\.00$')),
        );
        expect(
          l.firstWhere((e) => e.startsWith('BALANCE DUE')),
          endsWith('₹900.00'),
        );
      });

      test('a long description wraps to the paper and keeps its breaks', () {
        final l = lines(longDescriptionOrder(), width);
        final start = l.indexOf('Order details:') + 1;
        final end = l.indexOf(
          l.firstWhere((e) => e.startsWith('---'), orElse: () => ''),
          start,
        );
        final body = l.sublist(start, end).where((e) => e.isNotEmpty).toList();
        // Indented under the label, never over the width.
        for (final line in body) {
          expect(line, startsWith('  '));
          expect(textWidth(line), lessThanOrEqualTo(width.columns));
        }
        final text = body.map((e) => e.trim()).toList();
        expect(text.first, startsWith('Three tier wedding cake'));
        // The three paragraphs each start on a new line.
        expect(
          text.where((e) => e.startsWith('Message on top tier')),
          hasLength(1),
        );
        expect(text.where((e) => e.startsWith('Eggless.')), hasLength(1));
        // Nothing is lost: the words come back in order.
        final words = text.join(' ').split(' ');
        expect(
          words,
          containsAllInOrder(['wedding', 'cake,', 'strawberry', '5', 'kg.']),
        );
        expect(words.last, 'allergic.');
        expect(body.length, greaterThan(3));
      });

      test('the footer comes last', () {
        final l = lines(normalOrder(), width);
        // The footer may wrap on 58 mm; its words are the last thing printed.
        final tail = l.reversed
            .takeWhile((e) => e.isNotEmpty)
            .toList()
            .reversed
            .map((e) => e.trim())
            .join(' ');
        expect(tail, pilotLocation.receiptFooter);
      });
    });
  }

  test('a description over one paper width still lays out on 58 mm', () {
    final o = longDescriptionOrder();
    final narrow = lines(o, PaperWidth.mm58);
    final wide = lines(o, PaperWidth.mm80);
    expect(narrow.length, greaterThan(wide.length));
  });
}
