import 'dart:typed_data';

import '../api.dart';
import 'receipt_logo.dart';

/// Printable dots across the paper (203 dpi): 384 for 58 mm, 576 for 80 mm.
const int dotsMm58 = 384;
const int dotsMm80 = 576;

extension PaperDots on PaperWidth {
  /// Printable dots across this paper.
  int get dots => this == PaperWidth.mm80 ? dotsMm80 : dotsMm58;
}

/// The tallest logo printed, in dots (about 15 mm).
const int maxLogoDots = 120;

/// A 1-bit image ready for `GS v 0`: [bytes] holds [height] rows of
/// [widthBytes] bytes, most significant bit on the left, 1 meaning black.
final class LogoRaster {
  const LogoRaster({
    required this.widthBytes,
    required this.height,
    required this.bytes,
  });

  final int widthBytes;
  final int height;
  final Uint8List bytes;

  int get widthDots => widthBytes * 8;
}

/// Turns [logo] into a black-and-white raster exactly [dotWidth] dots wide
/// (a multiple of 8), so it is centred by padding and needs no alignment
/// command. The logo is scaled to fit [dotWidth] by [maxHeight], keeping its
/// proportions, laid over white, and dithered (Floyd-Steinberg).
LogoRaster rasterizeLogo(
  LogoBitmap logo, {
  required int dotWidth,
  int maxHeight = maxLogoDots,
}) {
  assert(dotWidth > 0 && dotWidth % 8 == 0, 'dotWidth: $dotWidth');
  assert(maxHeight > 0, 'maxHeight: $maxHeight');
  final (w, h) = fitSize(logo.width, logo.height, dotWidth, maxHeight);
  final grey = _scale(_luminance(logo), logo.width, logo.height, w, h);
  final black = _dither(grey, w, h);

  final widthBytes = dotWidth ~/ 8;
  final left = (dotWidth - w) ~/ 2;
  final out = Uint8List(widthBytes * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (black[y * w + x]) {
        final dot = left + x;
        out[y * widthBytes + (dot >> 3)] |= 0x80 >> (dot & 7);
      }
    }
  }
  return LogoRaster(widthBytes: widthBytes, height: h, bytes: out);
}

/// The size of a [w] x [h] image scaled to fit [maxW] x [maxH], proportions
/// kept, at least 1 x 1. Small images are scaled up to fit too.
(int, int) fitSize(int w, int h, int maxW, int maxH) {
  final s = (maxW / w) < (maxH / h) ? maxW / w : maxH / h;
  final fw = (w * s).round().clamp(1, maxW);
  final fh = (h * s).round().clamp(1, maxH);
  return (fw, fh);
}

/// 0 (black) to 255 (white) per pixel, with transparency read as white.
Float64List _luminance(LogoBitmap logo) {
  final n = logo.width * logo.height;
  final out = Float64List(n);
  final p = logo.rgba;
  for (var i = 0; i < n; i++) {
    final a = p[i * 4 + 3] / 255;
    final y = 0.299 * p[i * 4] + 0.587 * p[i * 4 + 1] + 0.114 * p[i * 4 + 2];
    out[i] = y * a + 255 * (1 - a);
  }
  return out;
}

/// Area-averaged resize: each target pixel is the mean of the source
/// pixels it covers (or the nearest one when scaling up).
Float64List _scale(Float64List src, int sw, int sh, int tw, int th) {
  if (sw == tw && sh == th) return src;
  final out = Float64List(tw * th);
  for (var y = 0; y < th; y++) {
    final y0 = (y * sh / th).floor();
    final y1 = ((y + 1) * sh / th).ceil().clamp(y0 + 1, sh);
    for (var x = 0; x < tw; x++) {
      final x0 = (x * sw / tw).floor();
      final x1 = ((x + 1) * sw / tw).ceil().clamp(x0 + 1, sw);
      var sum = 0.0;
      for (var yy = y0; yy < y1; yy++) {
        for (var xx = x0; xx < x1; xx++) {
          sum += src[yy * sw + xx];
        }
      }
      out[y * tw + x] = sum / ((y1 - y0) * (x1 - x0));
    }
  }
  return out;
}

/// Floyd-Steinberg error diffusion; true is black.
List<bool> _dither(Float64List grey, int w, int h) {
  final px = Float64List.fromList(grey);
  final black = List<bool>.filled(w * h, false);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      final old = px[i];
      final isBlack = old < 128;
      black[i] = isBlack;
      final err = old - (isBlack ? 0 : 255);
      if (x + 1 < w) px[i + 1] += err * 7 / 16;
      if (y + 1 < h) {
        if (x > 0) px[i + w - 1] += err * 3 / 16;
        px[i + w] += err * 5 / 16;
        if (x + 1 < w) px[i + w + 1] += err * 1 / 16;
      }
    }
  }
  return black;
}
