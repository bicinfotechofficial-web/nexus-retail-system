import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_printer/nexus_printer.dart';
import 'package:nexus_printer/src/layout/print_line.dart';
import 'package:nexus_printer/src/layout/receipt_layout.dart';

import 'fixtures.dart';

/// PR-8 and PR-9 on the receipt image: the logo in colour at the top, the
/// text-only fallback, and the advance slip and delivery bill goldens.
void main() {
  const none = NoReceiptLogo();
  final logo = FakeReceiptLogo(syntheticLogo());

  ReceiptDocument bill(Bill b) => ReceiptDocument.fromBill(b, pilotLocation);
  OrderSlipDocument slip(PreOrder o) =>
      OrderSlipDocument.fromOrder(o, pilotLocation);

  Future<ui.Image> decode(Uint8List png) async {
    final codec = await ui.instantiateImageCodec(png);
    final image = (await codec.getNextFrame()).image;
    codec.dispose();
    return image;
  }

  Future<(int, int, Uint8List)> pixels(Uint8List png) async {
    final image = await decode(png);
    final data = (await image.toByteData())!;
    final out = (
      image.width,
      image.height,
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
    image.dispose();
    return out;
  }

  group('goldens, with the synthetic logo', () {
    final cases = <String, Future<Uint8List> Function(ReceiptLogo)>{
      'bill_normal_logo_mm80': (l) =>
          renderReceiptPng(bill(normalBill()), width: PaperWidth.mm80, logo: l),
      'bill_normal_logo_mm58': (l) =>
          renderReceiptPng(bill(normalBill()), width: PaperWidth.mm58, logo: l),
      'return_slip_logo_mm80': (l) {
        final b = discountedSplitBill();
        return renderReturnSlipPng(
          ReturnSlipDocument.fromReturn(partialReturn(b), b, pilotLocation),
          width: PaperWidth.mm80,
          logo: l,
        );
      },
      'bill_delivery_logo_mm80': (l) => renderReceiptPng(
        bill(deliveryBill()),
        width: PaperWidth.mm80,
        logo: l,
      ),
      'order_slip_logo_mm80': (l) =>
          renderOrderSlipPng(slip(normalOrder()), PaperWidth.mm80, logo: l),
      'order_slip_logo_mm58': (l) =>
          renderOrderSlipPng(slip(normalOrder()), PaperWidth.mm58, logo: l),
      'order_slip_long_logo_mm58': (l) => renderOrderSlipPng(
        slip(longDescriptionOrder()),
        PaperWidth.mm58,
        logo: l,
      ),
    };
    for (final MapEntry(key: name, value: render) in cases.entries) {
      testWidgets(name, (tester) async {
        final image = (await tester.runAsync(
          () async => decode(await render(logo)),
        ))!;
        addTearDown(image.dispose);
        await expectLater(image, matchesGoldenFile('goldens/image_$name.png'));
      });
    }
  }, skip: imageGoldenSkip);

  group('goldens, without a logo', () {
    final cases = <String, Future<Uint8List> Function()>{
      'bill_delivery_mm80': () => renderReceiptPng(
        bill(deliveryBill()),
        width: PaperWidth.mm80,
        logo: none,
      ),
      'order_slip_mm80': () =>
          renderOrderSlipPng(slip(normalOrder()), PaperWidth.mm80, logo: none),
      'order_slip_mm58': () =>
          renderOrderSlipPng(slip(normalOrder()), PaperWidth.mm58, logo: none),
      'order_slip_long_mm58': () => renderOrderSlipPng(
        slip(longDescriptionOrder()),
        PaperWidth.mm58,
        logo: none,
      ),
      'order_slip_no_advance_mm80': () => renderOrderSlipPng(
        slip(noAdvanceOrder()),
        PaperWidth.mm80,
        logo: none,
      ),
    };
    for (final MapEntry(key: name, value: render) in cases.entries) {
      testWidgets(name, (tester) async {
        final image = (await tester.runAsync(
          () async => decode(await render()),
        ))!;
        addTearDown(image.dispose);
        await expectLater(image, matchesGoldenFile('goldens/image_$name.png'));
      });
    }

    testWidgets('bill_normal_mm80 is still the committed golden', (
      tester,
    ) async {
      // The PR-7 golden was made before logos existed. With no logo the
      // image must be the very same one.
      final image = (await tester.runAsync(() async {
        return decode(
          await renderReceiptPng(
            bill(normalBill()),
            width: PaperWidth.mm80,
            logo: none,
          ),
        );
      }))!;
      addTearDown(image.dispose);
      await expectLater(
        image,
        matchesGoldenFile('goldens/image_bill_normal_mm80.png'),
      );
    });
  }, skip: imageGoldenSkip);

  group('the logo block', () {
    for (final width in PaperWidth.values) {
      testWidgets('${width.name}: same width, taller by whole text rows', (
        tester,
      ) async {
        await tester.runAsync(() async {
          final plain = await pixels(
            await renderReceiptPng(
              bill(normalBill()),
              width: width,
              logo: none,
            ),
          );
          final withLogo = await pixels(
            await renderReceiptPng(
              bill(normalBill()),
              width: width,
              logo: logo,
            ),
          );
          expect(withLogo.$1, plain.$1);
          final extra = withLogo.$2 - plain.$2;
          expect(extra, greaterThan(0));
          expect(extra % (receiptRowHeight * 2).round(), 0);
          // At most 120 dots of the paper, plus the air under it.
          final maxExtra =
              (120 *
                  width.columns *
                  receiptGlyphWidth *
                  2 /
                  (width == PaperWidth.mm80 ? 576 : 384)) +
              receiptRowHeight * 2 * 2;
          expect(extra, lessThanOrEqualTo(maxExtra));
          // Everything under the logo is the text-only slip, untouched.
          final rowBytes = plain.$1 * 4;
          final tail = withLogo.$3.sublist(extra * rowBytes);
          expect(tail, plain.$3);
        });
      });
    }

    testWidgets('the logo is in colour; a text-only slip is grey only', (
      tester,
    ) async {
      await tester.runAsync(() async {
        bool hasColour(Uint8List px) {
          for (var i = 0; i < px.length; i += 4) {
            if (px[i] != px[i + 1] || px[i + 1] != px[i + 2]) return true;
          }
          return false;
        }

        final plain = await pixels(
          await renderReceiptPng(
            bill(normalBill()),
            width: PaperWidth.mm80,
            logo: none,
          ),
        );
        final withLogo = await pixels(
          await renderReceiptPng(
            bill(normalBill()),
            width: PaperWidth.mm80,
            logo: logo,
          ),
        );
        expect(hasColour(plain.$3), isFalse);
        expect(hasColour(withLogo.$3), isTrue);
        // Transparent parts of the logo are paper: the top-left is white.
        expect(withLogo.$3.sublist(0, 4), [255, 255, 255, 255]);
      });
    });

    testWidgets('the logo is centred', (tester) async {
      await tester.runAsync(() async {
        final (w, h, px) = await pixels(
          await renderReceiptPng(
            bill(normalBill()),
            width: PaperWidth.mm80,
            logo: FakeReceiptLogo(syntheticLogo(width: 300, height: 300)),
          ),
        );
        // A 300 x 300 logo with a disc at the left of its box is not
        // symmetric, so look at the block's overall extent: first and last
        // non-white columns in the logo rows.
        var first = w, last = -1;
        for (var y = 0; y < 60; y++) {
          for (var x = 0; x < w; x++) {
            final i = (y * w + x) * 4;
            if (px[i] != 255 || px[i + 1] != 255 || px[i + 2] != 255) {
              if (x < first) first = x;
              if (x > last) last = x;
            }
          }
        }
        expect(last, greaterThan(first));
        expect(h, greaterThan(60));
        // The drawn logo box is centred; its ink sits inside it.
        expect(first, greaterThan(w ~/ 4));
        expect(last, lessThan(w - w ~/ 4));
      });
    });
  });

  group('the fallback', () {
    testWidgets('a missing logo gives the very same PNG bytes', (tester) async {
      await tester.runAsync(() async {
        final plain = await renderReceiptPng(
          bill(normalBill()),
          width: PaperWidth.mm80,
          logo: none,
        );
        for (final broken in <ReceiptLogo>[
          FakeReceiptLogo(null),
          ThrowingReceiptLogo(),
        ]) {
          final png = await renderReceiptPng(
            bill(normalBill()),
            width: PaperWidth.mm80,
            logo: broken,
          );
          expect(png, plain);
        }
      });
    });

    testWidgets(
      'the default logo is the shop logo, so it differs from text-only',
      (tester) async {
        await tester.runAsync(() async {
          final plain = await renderOrderSlipPng(
            slip(normalOrder()),
            PaperWidth.mm58,
            logo: none,
          );
          final dflt = await renderOrderSlipPng(
            slip(normalOrder()),
            PaperWidth.mm58,
          );
          expect(dflt, isNot(plain));
        });
      },
    );
  });

  group('the advance slip image carries the slip text', () {
    for (final width in PaperWidth.values) {
      testWidgets('${width.columns} columns', (tester) async {
        await tester.runAsync(() async {
          late List<PrintLine> painted;
          final png = await renderOrderSlipPng(
            slip(longDescriptionOrder()),
            width,
            logo: logo,
            spy: (l) => painted = l,
          );
          expect(png.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
          expect(
            renderText(painted),
            renderText(
              ReceiptLayout(width).orderSlip(slip(longDescriptionOrder())),
            ),
          );
        });
      });
    }
  });
}
