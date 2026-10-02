import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/painting.dart';

import '../api.dart';
import '../layout/print_line.dart';
import '../layout/receipt_layout.dart';
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
Future<Uint8List> renderReceiptPng(
  ReceiptDocument doc, {
  required PaperWidth width,
  double scale = 2,
  @visibleForTesting PaintedLinesSpy? spy,
}) => _encode(ReceiptLayout(width).bill(doc), width, scale, spy);

/// The same for a return slip.
Future<Uint8List> renderReturnSlipPng(
  ReturnSlipDocument doc, {
  required PaperWidth width,
  double scale = 2,
  @visibleForTesting PaintedLinesSpy? spy,
}) => _encode(ReceiptLayout(width).returnSlip(doc), width, scale, spy);

/// The slip as a decoded image, for golden tests. The caller owns it and
/// must dispose it.
@visibleForTesting
Future<ui.Image> renderReceiptImage(
  ReceiptDocument doc, {
  required PaperWidth width,
  double scale = 2,
}) => _paint(ReceiptLayout(width).bill(doc), width.columns, scale);

Future<Uint8List> _encode(
  List<PrintLine> lines,
  PaperWidth width,
  double scale,
  PaintedLinesSpy? spy,
) async {
  spy?.call(lines);
  final image = await _paint(lines, width.columns, scale);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('PNG encoding returned no data');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
  }
}

Future<ui.Image> _paint(List<PrintLine> lines, int columns, double scale) {
  assert(scale > 0, 'scale must be positive');
  final rows = lines.fold<int>(0, (n, l) => n + (l.doubleHeight ? 2 : 1));
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
