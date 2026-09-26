/// One printed line: exactly `PaperWidth.columns` characters of text, plus
/// the style the ESC/POS encoder (PR-3) wraps around it.
///
/// Alignment is already baked into [text] as spaces, so the plain-text
/// preview and the printed slip always match character for character.
final class PrintLine {
  const PrintLine(this.text, {this.bold = false, this.doubleHeight = false});

  final String text;
  final bool bold;

  /// Double height only, never double width, so [text] still fits.
  final bool doubleHeight;

  @override
  bool operator ==(Object other) =>
      other is PrintLine &&
      other.text == text &&
      other.bold == bold &&
      other.doubleHeight == doubleHeight;

  @override
  int get hashCode => Object.hash(text, bold, doubleHeight);

  @override
  String toString() =>
      'PrintLine(${bold ? 'bold ' : ''}${doubleHeight ? 'tall ' : ''}"$text")';
}

/// The plain-text preview: one line per [PrintLine], styles dropped.
String renderText(List<PrintLine> lines) => lines.map((l) => l.text).join('\n');

/// The printed width of [s]. Counts Unicode code points, so `₹` is one
/// column.
int textWidth(String s) => s.runes.length;
