import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_printer/src/api.dart';
import 'package:nexus_printer/src/escpos/code_page.dart';
import 'package:nexus_printer/src/escpos/escpos_encoder.dart';
import 'package:nexus_printer/src/layout/print_line.dart';
import 'package:nexus_printer/src/layout/receipt_layout.dart';
import 'package:nexus_printer/src/receipt/receipt_document.dart';

import 'fixtures.dart';
import 'golden_text.dart';

/// A made-up table with a ₹ glyph, standing in for the pilot printer's
/// until its model is known (B-4).
const CodePage rupeeTable = CodePage(
  name: 'Test table with ₹',
  escPosNumber: 0x20,
  extra: {'₹': 0xB9},
);

void main() {
  group('EscPos commands', () {
    test('match the ESC/POS reference', () {
      expect(EscPos.init, [0x1B, 0x40]);
      expect(EscPos.codePage(0), [0x1B, 0x74, 0x00]);
      expect(EscPos.bold(on: true), [0x1B, 0x45, 0x01]);
      expect(EscPos.bold(on: false), [0x1B, 0x45, 0x00]);
      expect(EscPos.doubleHeight(on: true), [0x1D, 0x21, 0x01]);
      expect(EscPos.doubleHeight(on: false), [0x1D, 0x21, 0x00]);
      expect(EscPos.alignLeft, [0x1B, 0x61, 0x00]);
      expect(EscPos.feed(4), [0x1B, 0x64, 0x04]);
      expect(EscPos.cut, [0x1D, 0x56, 0x01]);
    });
  });

  group('EscPosEncoder', () {
    test('frames plain lines with init, table, feed and cut', () {
      const enc = EscPosEncoder();
      // dart format off
      expect(enc.encode(const [PrintLine('Hi'), PrintLine('Yo')]), [
        0x1B, 0x40, // init
        0x1B, 0x74, 0x00, // PC437
        0x1B, 0x61, 0x00, // left
        0x48, 0x69, 0x0A, // Hi
        0x59, 0x6F, 0x0A, // Yo
        0x1B, 0x64, 0x04, // feed 4
        0x1D, 0x56, 0x01, // cut
      ]);
      // dart format on
    });

    test('switches styles only when they change, and resets at the end', () {
      const enc = EscPosEncoder(feedLines: 0, cut: false);
      final bytes = enc.encode(const [
        PrintLine('a', bold: true),
        PrintLine('b', bold: true),
        PrintLine('T', bold: true, doubleHeight: true),
        PrintLine('c'),
        PrintLine('d', bold: true, doubleHeight: true),
      ]);
      // dart format off
      expect(bytes.sublist(8), [
        0x1B, 0x45, 0x01, 0x61, 0x0A, // bold on, a
        0x62, 0x0A, // b, still bold
        0x1D, 0x21, 0x01, 0x54, 0x0A, // tall on, T
        0x1B, 0x45, 0x00, 0x1D, 0x21, 0x00, 0x63, 0x0A, // both off, c
        0x1B, 0x45, 0x01, 0x1D, 0x21, 0x01, 0x64, 0x0A, // both on, d
        0x1B, 0x45, 0x00, 0x1D, 0x21, 0x00, // reset
      ]);
      // dart format on
    });

    test('encodes ₹ as the table byte when the table has it', () {
      const enc = EscPosEncoder(codePage: rupeeTable);
      expect(enc.encodeText('₹5.00'), [0xB9, 0x35, 0x2E, 0x30, 0x30]);
    });

    test('an unprintable character becomes one ? so widths hold', () {
      const enc = EscPosEncoder();
      expect(enc.encodeText('₹5 é'), [0x3F, 0x35, 0x20, 0x3F]);
    });

    test('one byte per column for every golden line', () {
      final layout = ReceiptLayout(PaperWidth.mm58);
      final lines = layout.bill(
        ReceiptDocument.fromBill(discountedSplitBill(), pilotLocation),
      );
      for (final l in lines) {
        expect(const EscPosEncoder().encodeText(l.text), hasLength(32));
      }
    });
  });

  group('code-page check for ₹', () {
    test('PC437 has no ₹, so receipts use Rs.', () {
      expect(CodePage.pc437.hasRupee, isFalse);
      expect(CodePage.pc437.currencySymbol, 'Rs.');
    });

    test('a table with the glyph keeps ₹', () {
      expect(rupeeTable.hasRupee, isTrue);
      expect(rupeeTable.currencySymbol, '₹');
    });

    test('laying out with the table symbol never prints a ?', () {
      final doc = ReceiptDocument.fromBill(normalBill(), pilotLocation);
      for (final table in [CodePage.pc437, rupeeTable]) {
        final layout = ReceiptLayout(
          PaperWidth.mm80,
          currencySymbol: table.currencySymbol,
        );
        final bytes = EscPosEncoder(codePage: table).encode(layout.bill(doc));
        expect(bytes, isNot(contains(EscPosEncoder.unknownChar)));
      }
    });
  });

  group('byte goldens', () {
    ReceiptDocument bill(Bill Function() make, {bool reprint = false}) =>
        ReceiptDocument.fromBill(make(), pilotLocation, reprint: reprint);

    final cases = <String, List<PrintLine> Function(ReceiptLayout)>{
      'bill_normal': (l) => l.bill(bill(normalBill)),
      'bill_discount_split': (l) => l.bill(bill(discountedSplitBill)),
      'bill_cancelled_reprint': (l) =>
          l.bill(bill(cancelledBill, reprint: true)),
      'return_slip': (l) {
        final b = discountedSplitBill();
        return l.returnSlip(
          ReturnSlipDocument.fromReturn(partialReturn(b), b, pilotLocation),
        );
      },
    };

    for (final width in PaperWidth.values) {
      for (final table in [CodePage.pc437, rupeeTable]) {
        final suffix = table.hasRupee ? 'rupee' : 'rs';
        for (final MapEntry(key: name, value: build) in cases.entries) {
          // PC437 for every slip; the ₹ table for one, to pin its byte.
          if (table.hasRupee && name != 'bill_normal') continue;
          test('${name}_${width.name}_$suffix', () {
            final layout = ReceiptLayout(
              width,
              currencySymbol: table.currencySymbol,
            );
            final bytes = EscPosEncoder(codePage: table).encode(build(layout));
            expectBytesGolden(bytes, '${name}_${width.name}_$suffix');
          });
        }
      }
    }
  });
}
