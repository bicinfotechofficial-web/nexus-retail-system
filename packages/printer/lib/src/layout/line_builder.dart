import 'print_line.dart';

/// Builds a list of [PrintLine]s of exactly [columns] characters: wrapping,
/// centring and label-amount rows. Knows nothing about receipts.
final class LineBuilder {
  LineBuilder(this.columns) : assert(columns >= 16, 'columns: $columns');

  final int columns;
  final List<PrintLine> _lines = [];

  List<PrintLine> build() => List.unmodifiable(_lines);

  /// Left-aligned text, wrapped at word boundaries. Newlines in [text]
  /// start a new line.
  void left(String text, {bool bold = false, int indent = 0}) {
    for (final l in wrap(text, columns - indent)) {
      _add(' ' * indent + l, bold: bold);
    }
  }

  /// Centred text, wrapped at word boundaries.
  void center(String text, {bool bold = false}) {
    for (final l in wrap(text, columns)) {
      final pad = (columns - textWidth(l)) ~/ 2;
      _add(' ' * pad + l, bold: bold);
    }
  }

  /// [label] on the left, [value] right-aligned on the same line. A label
  /// too long for the line wraps, and [value] goes on its last line.
  void row(
    String label,
    String value, {
    bool bold = false,
    bool doubleHeight = false,
    int indent = 0,
  }) {
    final valueWidth = textWidth(value);
    final labelWidth = columns - indent - valueWidth - 1;
    final parts = labelWidth > 0 ? wrap(label, labelWidth) : [label];
    for (var i = 0; i < parts.length; i++) {
      final text = ' ' * indent + parts[i];
      if (i < parts.length - 1) {
        _add(text, bold: bold, doubleHeight: doubleHeight);
      } else {
        final gap = columns - textWidth(text) - valueWidth;
        if (gap < 1) {
          _add(text, bold: bold, doubleHeight: doubleHeight);
          _add(
            ' ' * (columns - valueWidth) + value,
            bold: bold,
            doubleHeight: doubleHeight,
          );
        } else {
          _add(
            text + ' ' * gap + value,
            bold: bold,
            doubleHeight: doubleHeight,
          );
        }
      }
    }
  }

  /// A full-width rule of [char].
  void rule([String char = '-']) => _add(char * columns);

  /// [text] centred inside a rule of [char], e.g. `**** CANCELLED ****`.
  void banner(String text, {String char = '*'}) {
    final inner = ' $text ';
    final width = textWidth(inner);
    if (width + 2 > columns) {
      center(text, bold: true);
      return;
    }
    final leftFill = (columns - width) ~/ 2;
    final rightFill = columns - width - leftFill;
    _add(char * leftFill + inner + char * rightFill, bold: true);
  }

  void blank() => _add('');

  void _add(String text, {bool bold = false, bool doubleHeight = false}) {
    final width = textWidth(text);
    assert(width <= columns, '"$text" is $width wide, over $columns');
    _lines.add(
      PrintLine(
        text + ' ' * (columns - width),
        bold: bold,
        doubleHeight: doubleHeight,
      ),
    );
  }
}

/// Splits [text] into lines of at most [width] characters, breaking at
/// spaces. A word longer than [width] is cut. Newlines are kept as breaks;
/// runs of spaces collapse. Empty text gives no lines.
List<String> wrap(String text, int width) {
  assert(width > 0, 'width: $width');
  final out = <String>[];
  for (final para in text.split('\n')) {
    final words = para.split(' ').where((w) => w.isNotEmpty);
    var line = '';
    for (var word in words) {
      while (textWidth(word) > width) {
        if (line.isNotEmpty) {
          out.add(line);
          line = '';
        }
        final runes = word.runes.toList();
        out.add(String.fromCharCodes(runes.take(width)));
        word = String.fromCharCodes(runes.skip(width));
      }
      if (word.isEmpty) continue;
      if (line.isEmpty) {
        line = word;
      } else if (textWidth(line) + 1 + textWidth(word) <= width) {
        line = '$line $word';
      } else {
        out.add(line);
        line = word;
      }
    }
    if (line.isNotEmpty) out.add(line);
  }
  return out;
}
