import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_printer/nexus_printer.dart';
import 'package:nexus_printer/src/escpos/escpos_encoder.dart';
import 'package:nexus_printer/src/layout/print_line.dart';
import 'package:nexus_printer/src/logo/logo_raster.dart';
import 'package:nexus_printer/src/logo/receipt_logo.dart';

import 'fixtures.dart';

/// PR-8: the logo on the thermal printout. Dithering, raster bytes, the
/// ESC/POS framing and the fallbacks.
LogoBitmap solid(int w, int h, int r, int g, int b, [int a = 255]) =>
    LogoBitmap(
      width: w,
      height: h,
      rgba: Uint8List.fromList([
        for (var i = 0; i < w * h; i++) ...[r, g, b, a],
      ]),
    );

/// Whether dot [x] of row [y] is black.
bool dot(LogoRaster r, int x, int y) =>
    r.bytes[y * r.widthBytes + (x >> 3)] & (0x80 >> (x & 7)) != 0;

int blackDots(LogoRaster r) {
  var n = 0;
  for (final b in r.bytes) {
    n += b.toRadixString(2).replaceAll('0', '').length;
  }
  return n;
}

void main() {
  group('fitSize', () {
    test('a wide logo is limited by the paper width', () {
      expect(fitSize(1200, 100, 576, 120), (576, 48));
    });

    test('a tall or square logo is limited by the maximum height', () {
      expect(fitSize(600, 600, 576, 120), (120, 120));
      expect(fitSize(800, 300, 576, 120), (320, 120));
    });

    test('a small logo is scaled up to fit', () {
      expect(fitSize(60, 20, 576, 120), (360, 120));
    });

    test('never smaller than one dot', () {
      expect(fitSize(5000, 1, 384, 120), (384, 1));
    });
  });

  group('rasterizeLogo', () {
    test('widths: 384 dots for 58 mm, 576 for 80 mm', () {
      expect(PaperWidth.mm58.dots, 384);
      expect(PaperWidth.mm80.dots, 576);
      final logo = syntheticLogo();
      final r58 = rasterizeLogo(logo, dotWidth: PaperWidth.mm58.dots);
      final r80 = rasterizeLogo(logo, dotWidth: PaperWidth.mm80.dots);
      expect(r58.widthBytes, 48);
      expect(r80.widthBytes, 72);
      expect(r58.widthDots, 384);
      expect(r80.widthDots, 576);
    });

    test('at most 120 dots tall; the 800 x 300 logo is exactly 120', () {
      final r = rasterizeLogo(syntheticLogo(), dotWidth: 576);
      expect(r.height, 120);
      expect(r.bytes, hasLength(r.widthBytes * r.height));
      final tall = rasterizeLogo(solid(100, 900, 0, 0, 0), dotWidth: 576);
      expect(tall.height, 120);
    });

    test('a logo narrower than the paper is centred by padding', () {
      final r = rasterizeLogo(solid(300, 300, 0, 0, 0), dotWidth: 576);
      expect(r.height, 120);
      // 120 dots wide in 576: 228 white dots each side.
      for (var y = 0; y < r.height; y++) {
        expect(dot(r, 227, y), isFalse);
        expect(dot(r, 228, y), isTrue);
        expect(dot(r, 347, y), isTrue);
        expect(dot(r, 348, y), isFalse);
      }
      expect(blackDots(r), 120 * 120);
    });

    test('black is all black, white and transparent are all white', () {
      expect(
        blackDots(rasterizeLogo(solid(576, 100, 0, 0, 0), dotWidth: 576)),
        576 * 100,
      );
      expect(
        blackDots(rasterizeLogo(solid(576, 100, 255, 255, 255), dotWidth: 576)),
        0,
      );
      // Black ink at zero alpha is paper, not ink.
      expect(
        blackDots(rasterizeLogo(solid(576, 100, 0, 0, 0, 0), dotWidth: 576)),
        0,
      );
    });

    test('half-transparent black lands on mid grey and dithers', () {
      final r = rasterizeLogo(solid(576, 100, 0, 0, 0, 128), dotWidth: 576);
      final share = blackDots(r) / (576 * 100);
      expect(share, closeTo(0.5, 0.02));
    });

    test('a mid grey dithers to about half black, in a fine pattern', () {
      final r = rasterizeLogo(solid(576, 100, 128, 128, 128), dotWidth: 576);
      final share = blackDots(r) / (576 * 100);
      expect(share, closeTo(0.5, 0.02));
      // Not blobs: no row is a solid run of 16 black dots.
      for (var y = 0; y < r.height; y++) {
        var run = 0;
        for (var x = 0; x < 576; x++) {
          run = dot(r, x, y) ? run + 1 : 0;
          expect(run, lessThan(16));
        }
      }
    });

    test('a light grey is mostly white and a dark grey mostly black', () {
      double share(int v) {
        final r = rasterizeLogo(solid(576, 100, v, v, v), dotWidth: 576);
        return blackDots(r) / (576 * 100);
      }

      expect(share(200), closeTo(1 - 200 / 255, 0.02));
      expect(share(50), closeTo(1 - 50 / 255, 0.02));
    });

    test('is deterministic', () {
      final a = rasterizeLogo(syntheticLogo(), dotWidth: 384);
      final b = rasterizeLogo(syntheticLogo(), dotWidth: 384);
      expect(a.bytes, b.bytes);
    });

    test('a left-black right-white image keeps its sides', () {
      final w = 200, h = 100;
      final rgba = Uint8List(w * h * 4);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final v = x < w ~/ 2 ? 0 : 255;
          rgba.setAll((y * w + x) * 4, [v, v, v, 255]);
        }
      }
      final r = rasterizeLogo(
        LogoBitmap(width: w, height: h, rgba: rgba),
        dotWidth: 576,
      );
      expect(r.height, 120);
      // 240 x 120 in the middle: black 168..287, white 288..407.
      expect(dot(r, 167, 60), isFalse);
      expect(dot(r, 168, 60), isTrue);
      expect(dot(r, 287, 60), isTrue);
      expect(dot(r, 288, 60), isFalse);
      expect(dot(r, 407, 60), isFalse);
    });
  });

  group('GS v 0 bytes', () {
    test('header: GS v 0, m 0, width in bytes and height, little-endian', () {
      final r = rasterizeLogo(syntheticLogo(), dotWidth: 576);
      final cmd = EscPos.raster(r);
      expect(cmd.sublist(0, 8), [
        0x1D, 0x76, 0x30, 0x00, // GS v 0, normal density
        0x48, 0x00, // 72 bytes wide
        0x78, 0x00, // 120 dots high
      ]);
      expect(cmd, hasLength(8 + 72 * 120));
      expect(cmd.sublist(8), r.bytes);
    });

    test('58 mm: 48 bytes wide', () {
      final r = rasterizeLogo(syntheticLogo(), dotWidth: 384);
      final cmd = EscPos.raster(r);
      expect(cmd.sublist(4, 8), [0x30, 0x00, 0x78, 0x00]);
      expect(cmd, hasLength(8 + 48 * 120));
    });

    test('a width or height over 255 uses the high byte', () {
      final r = LogoRaster(
        widthBytes: 300,
        height: 258,
        bytes: Uint8List(300 * 258),
      );
      expect(EscPos.raster(r).sublist(4, 8), [0x2C, 0x01, 0x02, 0x01]);
    });

    test('bits run left to right, most significant first, 1 is black', () {
      // Two rows of two bytes: row 0 = 0x81 0x00, row 1 = 0x01 0x81.
      final r = LogoRaster(widthBytes: 2, height: 2, bytes: _bytes);
      expect(dot(r, 0, 0), isTrue);
      expect(dot(r, 1, 0), isFalse);
      expect(dot(r, 7, 0), isTrue);
      expect(dot(r, 8, 0), isFalse);
      expect(dot(r, 7, 1), isTrue);
      expect(dot(r, 8, 1), isTrue);
      expect(dot(r, 15, 1), isTrue);
      expect(dot(r, 9, 1), isFalse);
    });

    test('a pixel in the image sets the matching bit', () {
      // One black pixel at the left edge of a 8 x 8 logo, dot width 8.
      final rgba = Uint8List(8 * 8 * 4);
      for (var i = 0; i < 64; i++) {
        rgba.setAll(i * 4, [255, 255, 255, 255]);
      }
      rgba.setAll(0, [0, 0, 0, 255]);
      final r = rasterizeLogo(
        LogoBitmap(width: 8, height: 8, rgba: rgba),
        dotWidth: 8,
        maxHeight: 8,
      );
      expect(r.bytes[0], 0x80);
      expect(r.bytes.skip(1), everyElement(0));
    });
  });

  group('the encoder with a logo', () {
    final lines = const [PrintLine('Hi')];

    test('puts the raster first, then one line feed, then the text', () {
      final r = rasterizeLogo(syntheticLogo(), dotWidth: 384);
      final bytes = const EscPosEncoder(
        feedLines: 0,
        cut: false,
      ).encode(lines, logo: r);
      final head = [
        0x1B, 0x40, // init
        0x1B, 0x74, 0x00, // table
        0x1B, 0x61, 0x00, // left
      ];
      final raster = EscPos.raster(r);
      expect(bytes.sublist(0, head.length), head);
      expect(bytes.sublist(head.length, head.length + raster.length), raster);
      expect(bytes.sublist(head.length + raster.length), [
        0x1B, 0x64, 0x01, // feed 1
        0x48, 0x69, 0x0A, // Hi
      ]);
    });

    test('without a logo the bytes are exactly the text-only slip', () {
      const enc = EscPosEncoder();
      expect(enc.encode(lines, logo: null), enc.encode(lines));
      expect(enc.encode(lines), isNot(contains(0x76)));
    });
  });

  group('AssetReceiptLogo', () {
    test('a missing asset is null, not an error', () async {
      final logo = AssetReceiptLogo(bundle: _MapBundle({}));
      expect(await logo.load(), isNull);
    });

    test('bytes that are not an image are null', () async {
      final logo = AssetReceiptLogo(
        bundle: _MapBundle({
          AssetReceiptLogo.defaultAssetKey: Uint8List.fromList([1, 2, 3, 4]),
        }),
      );
      expect(await logo.load(), isNull);
    });

    testWidgets('a PNG decodes to its size and pixels', (tester) async {
      await tester.runAsync(() async {
        final png = await _png(syntheticLogo(width: 40, height: 20));
        final bundle = _MapBundle({AssetReceiptLogo.defaultAssetKey: png});
        final logo = AssetReceiptLogo(bundle: bundle);
        final bitmap = (await logo.load())!;
        expect(bitmap.width, 40);
        expect(bitmap.height, 20);
        expect(bitmap.rgba, hasLength(40 * 20 * 4));
        // The corner is transparent, the disc centre is opaque.
        expect(bitmap.rgba[3], 0);
        expect(bitmap.rgba[((10 * 40) + 12) * 4 + 3], 255);
        // Loaded once, kept.
        await logo.load();
        expect(bundle.loads, 1);
      });
    });

    test('rootBundle without the asset gives null', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      expect(await AssetReceiptLogo().load(), isNull);
    });

    test('loadLogoSafely turns a throwing logo into null', () async {
      expect(await loadLogoSafely(ThrowingReceiptLogo()), isNull);
      expect(await loadLogoSafely(const NoReceiptLogo()), isNull);
    });
  });
}

final Uint8List _bytes = Uint8List.fromList([0x81, 0x00, 0x01, 0x81]);

final class _MapBundle extends CachingAssetBundle {
  _MapBundle(this.assets);

  final Map<String, Uint8List> assets;
  int loads = 0;

  @override
  Future<ByteData> load(String key) async {
    loads++;
    final data = assets[key];
    if (data == null) throw StateError('Unable to load asset: $key');
    return ByteData.sublistView(data);
  }
}

Future<Uint8List> _png(LogoBitmap b) async {
  final done = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    b.rgba,
    b.width,
    b.height,
    ui.PixelFormat.rgba8888,
    done.complete,
  );
  final image = await done.future;
  final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
  image.dispose();
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}
