import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_printer/src/layout/line_builder.dart';
import 'package:nexus_printer/src/layout/print_line.dart';

void main() {
  group('wrap', () {
    test('breaks at spaces and keeps each line within the width', () {
      expect(wrap('Red Velvet Jar Cake with Cream Cheese', 16), [
        'Red Velvet Jar',
        'Cake with Cream',
        'Cheese',
      ]);
    });

    test('an exact fit stays on one line', () {
      expect(wrap('abcd efgh', 9), ['abcd efgh']);
    });

    test('cuts a word longer than the width', () {
      expect(wrap('ab 0123456789 cd', 4), ['ab', '0123', '4567', '89', 'cd']);
    });

    test('keeps newlines and collapses spaces', () {
      expect(wrap('12  Main Rd\nPattambi', 20), ['12 Main Rd', 'Pattambi']);
    });

    test('empty text gives no lines', () {
      expect(wrap('', 10), isEmpty);
      expect(wrap('   ', 10), isEmpty);
    });

    test('counts ₹ as one column', () {
      expect(wrap('₹1,234.00 x', 11), ['₹1,234.00 x']);
    });
  });

  group('LineBuilder', () {
    List<String> texts(LineBuilder b) => b.build().map((l) => l.text).toList();

    test('every line is exactly the column width', () {
      final b = LineBuilder(32)
        ..center('Caramel Cottage', bold: true)
        ..left('A product name long enough to wrap onto two lines')
        ..row('Subtotal', '₹1,23,456.00')
        ..rule()
        ..banner('CANCELLED')
        ..blank();
      for (final l in b.build()) {
        expect(textWidth(l.text), 32, reason: '"${l.text}"');
      }
    });

    test('row right-aligns the value', () {
      final b = LineBuilder(20)..row('Cash', '₹50.00');
      expect(texts(b), ['Cash          ₹50.00']);
    });

    test('row wraps a long label and puts the value on its last line', () {
      final b = LineBuilder(20)..row('Discount on a long label', '₹5.00');
      expect(texts(b), ['Discount on a       ', 'long label     ₹5.00']);
    });

    test('row with an indent', () {
      final b = LineBuilder(20)..row('2 x ₹5.00', '₹10.00', indent: 2);
      expect(texts(b), ['  2 x ₹5.00   ₹10.00']);
    });

    test('row carries its style', () {
      final b = LineBuilder(20)
        ..row('TOTAL', '₹9.00', bold: true, doubleHeight: true);
      expect(b.build().single.bold, isTrue);
      expect(b.build().single.doubleHeight, isTrue);
    });

    test('raw keeps spaces and does not wrap', () {
      final b = LineBuilder(20)..raw('<${' ' * 18}>');
      expect(texts(b), ['<                  >']);
    });

    test('center pads on the left and fills to the width', () {
      final b = LineBuilder(20)..center('abcd');
      expect(texts(b), ['        abcd        ']);
    });

    test('banner centres its text in the fill character', () {
      final b = LineBuilder(20)..banner('VOID');
      expect(texts(b), ['******* VOID *******']);
      expect(b.build().single.bold, isTrue);
    });

    test('banner falls back to centred text when it cannot fit', () {
      final b = LineBuilder(16)..banner('A VERY LONG BANNER');
      expect(texts(b).first.trim(), 'A VERY LONG');
    });

    test('renderText joins lines', () {
      final b = LineBuilder(16)
        ..left('a')
        ..left('b');
      expect(renderText(b.build()), '${'a'.padRight(16)}\n${'b'.padRight(16)}');
    });
  });
}
