import 'dart:typed_data';

import '../layout/print_line.dart';
import 'code_page.dart';

/// Standard ESC/POS commands only, so any ESC/POS printer takes them
/// (D-020). Nothing model-specific until the pilot printer is known (B-4).
abstract final class EscPos {
  static const int esc = 0x1B;
  static const int gs = 0x1D;
  static const int lf = 0x0A;

  /// `ESC @`: reset the printer to its power-on state.
  static const List<int> init = [esc, 0x40];

  /// `ESC t n`: select character table n.
  static List<int> codePage(int n) => [esc, 0x74, n];

  /// `ESC E n`: bold on or off.
  static List<int> bold({required bool on}) => [esc, 0x45, on ? 1 : 0];

  /// `GS ! n`: character size. 0x01 is double height, normal width.
  static List<int> doubleHeight({required bool on}) => [gs, 0x21, on ? 1 : 0];

  /// `ESC a n`: 0 left, 1 centre, 2 right.
  static const List<int> alignLeft = [esc, 0x61, 0];

  /// `ESC d n`: print and feed n lines.
  static List<int> feed(int lines) => [esc, 0x64, lines];

  /// `GS V 1`: partial cut. Printers without a cutter ignore it.
  static const List<int> cut = [gs, 0x56, 1];
}

/// Encodes laid-out lines (PR-2) as ESC/POS bytes.
///
/// Each line is sent as its exact text, so the slip matches the preview.
/// Alignment is already in the text as spaces; the encoder sets left
/// alignment once and only switches bold and double height when they
/// change from one line to the next.
final class EscPosEncoder {
  const EscPosEncoder({
    this.codePage = CodePage.pc437,
    this.feedLines = 4,
    this.cut = true,
  });

  final CodePage codePage;

  /// Blank lines fed after the last line, so it clears the tear bar.
  final int feedLines;
  final bool cut;

  /// Printed in place of a character the table can't print. One byte for
  /// one character, so line widths never change.
  static const int unknownChar = 0x3F; // '?'

  Uint8List encode(List<PrintLine> lines) {
    final out = BytesBuilder(copy: false)
      ..add(EscPos.init)
      ..add(EscPos.codePage(codePage.escPosNumber))
      ..add(EscPos.alignLeft);
    var bold = false;
    var tall = false;
    for (final line in lines) {
      if (line.bold != bold) {
        bold = line.bold;
        out.add(EscPos.bold(on: bold));
      }
      if (line.doubleHeight != tall) {
        tall = line.doubleHeight;
        out.add(EscPos.doubleHeight(on: tall));
      }
      out
        ..add(encodeText(line.text))
        ..addByte(EscPos.lf);
    }
    if (bold) out.add(EscPos.bold(on: false));
    if (tall) out.add(EscPos.doubleHeight(on: false));
    if (feedLines > 0) out.add(EscPos.feed(feedLines));
    if (cut) out.add(EscPos.cut);
    return out.takeBytes();
  }

  /// [text] as bytes on [codePage], one byte per character.
  List<int> encodeText(String text) => [
    for (final r in text.runes) codePage.byteFor(r) ?? unknownChar,
  ];
}
