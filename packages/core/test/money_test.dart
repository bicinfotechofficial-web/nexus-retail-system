import 'package:nexus_core/nexus_core.dart';
import 'package:test/test.dart';

void main() {
  group('divideRounded', () {
    test('rounds halves away from zero', () {
      expect(divideRounded(5, 2), 3);
      expect(divideRounded(-5, 2), -3);
      expect(divideRounded(5, -2), -3);
      expect(divideRounded(-5, -2), 3);
      expect(divideRounded(4, 3), 1);
      expect(divideRounded(149, 100), 1);
      expect(divideRounded(150, 100), 2);
      expect(divideRounded(0, 7), 0);
    });

    test('rejects a zero denominator', () {
      expect(() => divideRounded(1, 0), throwsArgumentError);
    });
  });

  group('roundToRupee', () {
    const cases = {
      0: 0,
      1: 0,
      49: 0,
      50: 100,
      51: 100,
      99: 100,
      100: 100,
      1049: 1000,
      1050: 1100,
      -49: 0,
      -50: -100,
      -151: -200,
    };
    for (final e in cases.entries) {
      test('${e.key} → ${e.value}', () {
        expect(Money(e.key).roundToRupee(), Money(e.value));
      });
    }
  });

  group('parse', () {
    test('accepts rupees, paise, grouping and the symbol', () {
      expect(Money.parse('120'), const Money(12000));
      expect(Money.parse('120.5'), const Money(12050));
      expect(Money.parse('120.05'), const Money(12005));
      expect(Money.parse('₹1,20,000.50'), const Money(12000050));
      expect(Money.parse(' 0.99 '), const Money(99));
      expect(Money.parse('-5'), const Money(-500));
    });

    test('rejects anything else', () {
      for (final bad in ['', '1.234', 'abc', '1.2.3', '.5', '12.']) {
        expect(() => Money.parse(bad), throwsFormatException, reason: bad);
      }
    });
  });

  group('format', () {
    test('uses Indian grouping', () {
      expect(const Money(0).format(), '₹0.00');
      expect(const Money(5).format(), '₹0.05');
      expect(const Money(123400).format(), '₹1,234.00');
      expect(const Money(12345678).format(), '₹1,23,456.78');
      expect(const Money(1234567800).format(), '₹1,23,45,678.00');
      expect(const Money(-500).format(), '-₹5.00');
      expect(const Money(99900).format(symbol: 'Rs.'), 'Rs.999.00');
    });
  });

  test('arithmetic and comparisons', () {
    const a = Money(250);
    const b = Money.rupees(1);
    expect(a + b, const Money(350));
    expect(a - b, const Money(150));
    expect(-a, const Money(-250));
    expect(a.times(3), const Money(750));
    expect(a > b && b < a && a >= a && a <= a, isTrue);
    expect(Money.zero.isZero, isTrue);
    expect(const Money(-1).isNegative, isTrue);
    expect(a.isPositive, isTrue);
    expect(b.isWholeRupees, isTrue);
    expect(a.isWholeRupees, isFalse);
  });
}
