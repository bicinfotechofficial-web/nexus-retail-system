import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_printer/src/api.dart';
import 'package:nexus_printer/src/layout/print_line.dart';
import 'package:nexus_printer/src/layout/receipt_layout.dart';
import 'package:nexus_printer/src/receipt/receipt_document.dart';

import 'fixtures.dart';

/// PR-6: the golden set, and proof that paper matches the preview.
///
/// The text goldens (`<slip>_<width>.txt`, PR-2) are the preview with ₹.
/// The byte goldens (`<slip>_<width>_<table>.hex`, PR-3) are what the
/// printer gets, on PC437 (`rs`) or a table with ₹ (`rupee`). Each byte
/// golden is decoded back to text and compared with the preview the POS
/// shows for the same slip and symbol, and the `rupee` ones also with the
/// text golden itself. So a slip can't print differently from its preview
/// without a golden diff showing it (acceptance #4).
final Map<String, List<PrintLine> Function(ReceiptLayout)> requiredSlips = {
  'bill_normal': (l) =>
      l.bill(ReceiptDocument.fromBill(normalBill(), pilotLocation)),
  'bill_discount_split': (l) =>
      l.bill(ReceiptDocument.fromBill(discountedSplitBill(), pilotLocation)),
  'return_slip': (l) {
    final b = discountedSplitBill();
    return l.returnSlip(
      ReturnSlipDocument.fromReturn(partialReturn(b), b, pilotLocation),
    );
  },
  'bill_cancelled_reprint': (l) => l.bill(
    ReceiptDocument.fromBill(cancelledBill(), pilotLocation, reprint: true),
  ),
};

final Directory goldens = Directory('test/goldens');

void main() {
  group('the required set is committed', () {
    for (final slip in requiredSlips.keys) {
      for (final width in PaperWidth.values) {
        test('${slip}_${width.name}: text and bytes', () {
          expect(
            File('${goldens.path}/${slip}_${width.name}.txt').existsSync(),
            isTrue,
          );
          expect(
            File('${goldens.path}/${slip}_${width.name}_rs.hex').existsSync(),
            isTrue,
          );
        });
      }
    }
  });

  group('every byte golden prints exactly its preview', () {
    final hexFiles =
        goldens
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.hex'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));

    test('there are byte goldens to check', () {
      expect(hexFiles.length, greaterThanOrEqualTo(requiredSlips.length * 2));
    });

    for (final hex in hexFiles) {
      final name = hex.uri.pathSegments.last.replaceAll('.hex', '');
      test(name, () {
        final match = RegExp(r'^(.+)_(mm80|mm58)_(rs|rupee)$').firstMatch(name);
        expect(match, isNotNull, reason: 'unexpected golden name $name');
        final slip = match!.group(1)!;
        final width = match.group(2)!;
        final rupee = match.group(3) == 'rupee';

        final printed = _decode(_readHex(hex), rupeeByte: rupee ? 0xB9 : null);
        final layOut = requiredSlips[slip];
        expect(layOut, isNotNull, reason: 'no builder for $slip');
        final preview = renderText(
          layOut!(
            ReceiptLayout(
              width == 'mm80' ? PaperWidth.mm80 : PaperWidth.mm58,
              currencySymbol: rupee ? '₹' : 'Rs.',
            ),
          ),
        );
        expect(_lines(printed), _lines(preview));
        if (rupee) {
          final golden = File('${goldens.path}/${slip}_$width.txt');
          expect(_lines(printed), _lines(golden.readAsStringSync()));
        }
      });
    }
  });
}

List<int> _readHex(File f) => [
  for (final h in f.readAsStringSync().split(RegExp(r'\s+')))
    if (h.isNotEmpty) int.parse(h, radix: 16),
];

/// Strips the framing and style commands the encoder uses, then maps the
/// bytes back to characters. Fails on any byte it doesn't expect, so a new
/// command can't slip into a golden unnoticed.
String _decode(List<int> b, {int? rupeeByte}) {
  expect(b.sublist(0, 2), [0x1B, 0x40], reason: 'starts with ESC @');
  var i = 2;
  final out = StringBuffer();
  while (i < b.length) {
    final x = b[i];
    if (x == 0x1B || x == 0x1D) {
      final cmd = [x, b[i + 1]];
      final known = {
        '1b74': 3, // ESC t n
        '1b61': 3, // ESC a n
        '1b45': 3, // ESC E n
        '1d21': 3, // GS ! n
        '1b64': 3, // ESC d n
        '1d56': 3, // GS V 1
      };
      final key = cmd.map((c) => c.toRadixString(16).padLeft(2, '0')).join();
      expect(known, contains(key), reason: 'unknown command $key at $i');
      i += known[key]!;
    } else if (x == 0x0A) {
      out.write('\n');
      i++;
    } else if (x == rupeeByte) {
      out.write('₹');
      i++;
    } else {
      expect(x, inInclusiveRange(0x20, 0x7E), reason: 'byte $x at $i');
      out.writeCharCode(x);
      i++;
    }
  }
  return out.toString();
}

/// Lines exactly as printed, padding kept; only a final newline dropped.
List<String> _lines(String s) =>
    (s.endsWith('\n') ? s.substring(0, s.length - 1) : s).split('\n');
