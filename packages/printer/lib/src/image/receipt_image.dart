import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/painting.dart';

import '../api.dart';
import '../layout/print_line.dart';
import '../layout/receipt_layout.dart';
import '../logo/logo_raster.dart';
import '../logo/receipt_logo.dart';
import '../receipt/order_slip.dart';
import '../receipt/receipt_document.dart';

/// Width of one character cell, in logical pixels, before `scale`.
///
/// Every character is drawn into its own cell, so columns line up whatever
/// font the device substitutes. The image is exactly
/// `columns * receiptGlyphWidth * scale` pixels wide.
const double receiptGlyphWidth = 9;

/// Height of one text row, in logical pixels, before `scale`. A
/// double-height line (the TOTAL row) takes two rows.
const double receiptRowHeight = 20;

const double _fontSize = 15;

/// On a device this resolves to the platform monospace face. In
/// `flutter test` there is no such font, so the default test font draws
/// solid blocks; the layout and the goldens are unaffected by that.
const List<String> _fontFallback = ['monospace', 'Roboto Mono', 'Courier'];

/// Called with the lines handed to the painter. Tests use it to prove the
/// image carries the same text as the plain-text renderer.
@visibleForTesting
typedef PaintedLinesSpy = void Function(List<PrintLine> lines);

/// Renders [doc] as a PNG that looks like the printed slip: white
/// background, black text, [width] columns of monospace-style text.
///
/// The text comes from the same [ReceiptLayout] the printer and the
/// plain-text preview use (with `₹`, since an image has no code page), so
/// the image and the slip never disagree.
///
/// The shop logo (D-041) is drawn in colour at the top, from [logo] or, when
/// that is null, the bundled asset. A missing or broken logo leaves the
/// slip exactly as it is without one; it never fails the render.
Future<Uint8List> renderReceiptPng(
  ReceiptDocument doc, {
  required PaperWidth width,
  double scale = 2,
  ReceiptLogo? logo,
  @visibleForTesting PaintedLinesSpy? spy,
}) => _encode(ReceiptLayout(width).bill(doc), width, scale, spy, logo);

/// The same for a return slip.
Future<Uint8List> renderReturnSlipPng(
  ReturnSlipDocument doc, {
  required PaperWidth width,
  double scale = 2,
  ReceiptLogo? logo,
  @visibleForTesting PaintedLinesSpy? spy,
}) => _encode(ReceiptLayout(width).returnSlip(doc), width, scale, spy, logo);

/// The same for the advance slip given when an order is taken (D-043).
Future<Uint8List> renderOrderSlipPng(
  OrderSlipDocument doc,
  PaperWidth paperWidth, {
  double scale = 2,
  ReceiptLogo? logo,
  @visibleForTesting PaintedLinesSpy? spy,
}) => _encode(
  ReceiptLayout(paperWidth).orderSlip(doc),
  paperWidth,
  scale,
  spy,
  logo,
);

/// The slip as a decoded image, for golden tests. The caller owns it and
/// must dispose it.
@visibleForTesting
Future<ui.Image> renderReceiptImage(
  ReceiptDocument doc, {
  required PaperWidth width,
  double scale = 2,
  ReceiptLogo? logo,
}) => _paint(
  ReceiptLayout(width).bill(doc),
  width.columns,
  scale,
  _logoImage(logo),
);

Future<Uint8List> _encode(
  List<PrintLine> lines,
  PaperWidth width,
  double scale,
  PaintedLinesSpy? spy,
  ReceiptLogo? logo,
) async {
  spy?.call(lines);
  final image = await _paint(lines, width.columns, scale, _logoImage(logo));
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('PNG encoding returned no data');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
  }
}

/// The logo as a drawable image, or null when there is none or it fails.
Future<ui.Image?> _logoImage(ReceiptLogo? logo) async {
  final bitmap = await loadLogoSafely(logo ?? defaultReceiptLogo);
  if (bitmap == null) return null;
  try {
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      bitmap.rgba,
      bitmap.width,
      bitmap.height,
      ui.PixelFormat.rgba8888,
      done.complete,
    );
    return await done.future;
  } on Object {
    return null;
  }
}

/// Where the logo goes: its drawn size and the whole rows it takes at the
/// top. It fits the slip's width and, in proportion, the same share of it
/// that [maxLogoDots] is of the paper's dots, so the picture and the
/// printout look alike.
({double width, double height, int rows}) _logoBox(ui.Image logo, int columns) {
  final slipWidth = columns * receiptGlyphWidth;
  final dots = columns == PaperWidth.mm80.columns ? dotsMm80 : dotsMm58;
  final maxHeight = maxLogoDots * slipWidth / dots;
  final s = math.min(slipWidth / logo.width, maxHeight / logo.height);
  final w = logo.width * s;
  final h = logo.height * s;
  // A little air under the logo, in whole text rows.
  final rows = ((h + 6) / receiptRowHeight).ceil();
  return (width: w, height: h, rows: rows);
}

Future<ui.Image> _paint(
  List<PrintLine> lines,
  int columns,
  double scale,
  Future<ui.Image?> logoFuture,
) async {
  assert(scale > 0, 'scale must be positive');
  final logo = await logoFuture;
  try {
    return await _paintWith(lines, columns, scale, logo);
  } finally {
    logo?.dispose();
  }
}

Future<ui.Image> _paintWith(
  List<PrintLine> lines,
  int columns,
  double scale,
  ui.Image? logo,
) {
  final box = logo == null ? null : _logoBox(logo, columns);
  final rows =
      lines.fold<int>(0, (n, l) => n + (l.doubleHeight ? 2 : 1)) +
      (box?.rows ?? 0);
  final pxWidth = (columns * receiptGlyphWidth * scale).round();
  final pxHeight = (rows * receiptRowHeight * scale).round();

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)
    ..drawRect(
      ui.Rect.fromLTWH(0, 0, pxWidth.toDouble(), pxHeight.toDouble()),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    )
    ..scale(scale);

  var y = 0.0;
  if (logo != null && box != null) {
    final slipWidth = columns * receiptGlyphWidth;
    final top = (box.rows * receiptRowHeight - box.height) / 2;
    canvas.drawImageRect(
      logo,
      ui.Rect.fromLTWH(0, 0, logo.width.toDouble(), logo.height.toDouble()),
      ui.Rect.fromLTWH((slipWidth - box.width) / 2, top, box.width, box.height),
      ui.Paint()..filterQuality = ui.FilterQuality.high,
    );
    y = box.rows * receiptRowHeight;
  }
  for (final line in lines) {
    final tall = line.doubleHeight;
    final rowHeight = receiptRowHeight * (tall ? 2 : 1);
    final style = TextStyle(
      color: const ui.Color(0xFF000000),
      fontFamily: 'monospace',
      fontFamilyFallback: _fontFallback,
      fontSize: _fontSize,
      height: 1,
      fontWeight: line.bold ? FontWeight.w700 : FontWeight.w400,
    );
    var col = 0;
    for (final rune in line.text.runes) {
      final ch = String.fromCharCode(rune);
      if (ch != ' ') {
        final painter = TextPainter(
          text: TextSpan(text: ch, style: style),
          textDirection: ui.TextDirection.ltr,
        )..layout();
        canvas.save();
        canvas.translate(col * receiptGlyphWidth, y);
        // Double height stretches the glyph, never the cell width.
        if (tall) canvas.scale(1, 2);
        final dx = (receiptGlyphWidth - painter.width) / 2;
        final dy = (receiptRowHeight - painter.height) / 2;
        painter.paint(canvas, ui.Offset(dx, dy));
        canvas.restore();
        painter.dispose();
      }
      col++;
    }
    y += rowHeight;
  }
  return recorder.endRecording().toImage(pxWidth, pxHeight);
}
