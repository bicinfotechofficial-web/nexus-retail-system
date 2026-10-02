import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_printer/nexus_printer.dart';
import 'package:nexus_printer/src/image/receipt_image.dart';
import 'package:nexus_printer/src/layout/print_line.dart';
import 'package:nexus_printer/src/layout/receipt_layout.dart';

import 'fixtures.dart';

/// PR-7: the receipt as an image. In `flutter test` the default test font
/// draws solid blocks, so the goldens pin the grid, the line count and the
/// bold and tall rows; the wording is pinned by the line comparison below.
void main() {
  ReceiptDocument normal() =>
      ReceiptDocument.fromBill(normalBill(), pilotLocation);
  ReceiptDocument split() =>
      ReceiptDocument.fromBill(discountedSplitBill(), pilotLocation);

  group('goldens', () {
    final cases = <String, (ReceiptDocument, PaperWidth)>{
      'bill_normal_mm80': (normal(), PaperWidth.mm80),
      'bill_discount_split_mm80': (split(), PaperWidth.mm80),
      'bill_normal_mm58': (normal(), PaperWidth.mm58),
    };
    for (final MapEntry(key: name, value: (doc, width)) in cases.entries) {
      testWidgets(name, (tester) async {
        final image = (await tester.runAsync(
          () => renderReceiptImage(doc, width: width),
        ))!;
        addTearDown(image.dispose);
        await expectLater(image, matchesGoldenFile('goldens/image_$name.png'));
      });
    }
  });

  group('PNG', () {
    for (final width in PaperWidth.values) {
      for (final scale in [1.0, 2.0, 3.0]) {
        testWidgets('${width.name} at x$scale decodes at the grid size', (
          tester,
        ) async {
          await tester.runAsync(() async {
            final png = await renderReceiptPng(
              split(),
              width: width,
              scale: scale,
            );
            // PNG signature.
            expect(png.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
            final codec = await ui.instantiateImageCodec(png);
            final frame = await codec.getNextFrame();
            final image = frame.image;
            expect(
              image.width,
              (width.columns * receiptGlyphWidth * scale).round(),
            );
            expect(image.height, greaterThan(0));
            expect(image.height % (receiptRowHeight * scale).round(), 0);
            image.dispose();
            codec.dispose();
          });
        });
      }
    }

    testWidgets('background is white and ink is black only', (tester) async {
      await tester.runAsync(() async {
        final png = await renderReceiptPng(normal(), width: PaperWidth.mm80);
        final codec = await ui.instantiateImageCodec(png);
        final image = (await codec.getNextFrame()).image;
        final data = (await image.toByteData())!;
        final px = data.buffer.asUint8List();
        var sawInk = false;
        for (var i = 0; i < px.length; i += 4) {
          final isWhite = px[i] == 255 && px[i + 1] == 255 && px[i + 2] == 255;
          final isGrey = px[i] == px[i + 1] && px[i] == px[i + 2];
          expect(px[i + 3], 255);
          expect(isGrey, isTrue, reason: 'only greys, no colour');
          if (!isWhite) sawInk = true;
        }
        expect(sawInk, isTrue);
        expect(px[0], 255, reason: 'top-left corner is paper');
        image.dispose();
        codec.dispose();
      });
    });

    testWidgets('a return slip renders too', (tester) async {
      await tester.runAsync(() async {
        final bill = discountedSplitBill();
        final slip = ReturnSlipDocument.fromReturn(
          partialReturn(bill),
          bill,
          pilotLocation,
        );
        late List<PrintLine> painted;
        final png = await renderReturnSlipPng(
          slip,
          width: PaperWidth.mm58,
          spy: (l) => painted = l,
        );
        expect(png, isNotEmpty);
        expect(
          renderText(painted),
          renderText(ReceiptLayout(PaperWidth.mm58).returnSlip(slip)),
        );
      });
    });
  });

  group('the image carries the same text as the slip', () {
    final docs = <String, ReceiptDocument>{
      'normal': normal(),
      'discounted split': split(),
      'cancelled reprint': ReceiptDocument.fromBill(
        cancelledBill(),
        pilotLocation,
        reprint: true,
      ),
    };
    for (final width in PaperWidth.values) {
      for (final MapEntry(key: name, value: doc) in docs.entries) {
        testWidgets('$name, ${width.columns} columns', (tester) async {
          await tester.runAsync(() async {
            late List<PrintLine> painted;
            await renderReceiptPng(
              doc,
              width: width,
              spy: (lines) => painted = lines,
            );
            final expected = ReceiptLayout(width).bill(doc);
            expect(painted, expected);
            expect(renderText(painted), renderText(expected));
            for (final l in painted) {
              expect(textWidth(l.text), width.columns);
            }
          });
        });
      }
    }
  });

  group('ReceiptSharer', () {
    test('the share_plus implementation sits behind the interface', () {
      const ReceiptSharer sharer = SharePlusReceiptSharer();
      expect(sharer, isA<ReceiptSharer>());
    });

    test('a fake records what the POS shares', () async {
      final fake = _FakeSharer();
      await fake.shareImage(
        Uint8List.fromList([1, 2, 3]),
        fileName: 'bill.png',
        text: 'Thank you',
      );
      expect(fake.calls.single.fileName, 'bill.png');
      expect(fake.calls.single.text, 'Thank you');
    });
  });
}

final class _FakeSharer implements ReceiptSharer {
  final calls = <({Uint8List png, String fileName, String? text})>[];

  @override
  Future<void> shareImage(
    Uint8List png, {
    required String fileName,
    String? text,
  }) async => calls.add((png: png, fileName: fileName, text: text));
}
