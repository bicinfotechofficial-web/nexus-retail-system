/// An amount of money in integer **paise** (D-006).
///
/// An extension type, so it costs nothing at runtime but can't be mixed up
/// with a quantity or any other `int` by accident. Firestore stores the raw
/// [paise] value.
extension type const Money(int paise) {
  static const Money zero = Money(0);

  /// Whole rupees, e.g. `Money.rupees(120)` is ₹120.00.
  const Money.rupees(int rupees) : paise = rupees * 100;

  /// Parses user input such as `"120"`, `"120.5"`, `"1,20,000.50"` or
  /// `"₹99.99"`. At most two decimal places. Throws [FormatException].
  factory Money.parse(String input) {
    final cleaned = input.replaceAll(RegExp(r'[₹,\s]'), '');
    final match = RegExp(r'^(-?)(\d+)(?:\.(\d{1,2}))?$').firstMatch(cleaned);
    if (match == null) {
      throw FormatException('Not a money amount', input);
    }
    final sign = match.group(1) == '-' ? -1 : 1;
    final rupees = int.parse(match.group(2)!);
    final fraction = (match.group(3) ?? '').padRight(2, '0');
    return Money(sign * (rupees * 100 + int.parse(fraction)));
  }

  Money operator +(Money other) => Money(paise + other.paise);
  Money operator -(Money other) => Money(paise - other.paise);
  Money operator -() => Money(-paise);

  /// Multiplies by a whole quantity, e.g. unit price × qty.
  Money times(int factor) => Money(paise * factor);

  bool operator <(Money other) => paise < other.paise;
  bool operator <=(Money other) => paise <= other.paise;
  bool operator >(Money other) => paise > other.paise;
  bool operator >=(Money other) => paise >= other.paise;

  bool get isZero => paise == 0;
  bool get isNegative => paise < 0;
  bool get isPositive => paise > 0;

  /// True when this is a whole number of rupees.
  bool get isWholeRupees => paise % 100 == 0;

  /// Rounds to the nearest ₹1, halves away from zero (D-010, D-024).
  /// ₹10.49 → ₹10, ₹10.50 → ₹11, −₹10.50 → −₹11.
  Money roundToRupee() => Money(divideRounded(paise, 100) * 100);

  /// `₹1,23,456.78`, with Indian digit grouping. Negative amounts get a
  /// leading minus: `-₹5.00`.
  String format({String symbol = '₹'}) {
    final abs = paise.abs();
    final rupees = _groupIndian((abs ~/ 100).toString());
    final fraction = (abs % 100).toString().padLeft(2, '0');
    return '${paise < 0 ? '-' : ''}$symbol$rupees.$fraction';
  }
}

String _groupIndian(String digits) {
  if (digits.length <= 3) return digits;
  final last3 = digits.substring(digits.length - 3);
  var rest = digits.substring(0, digits.length - 3);
  final groups = <String>[];
  while (rest.length > 2) {
    groups.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) groups.insert(0, rest);
  return '${groups.join(',')},$last3';
}

/// Integer division rounded to the nearest whole number, halves away from
/// zero. The one rounding rule used by every calculator (D-024).
///
/// `divideRounded(5, 2) == 3`, `divideRounded(-5, 2) == -3`.
int divideRounded(int numerator, int denominator) {
  if (denominator == 0) {
    throw ArgumentError.value(denominator, 'denominator', 'must not be 0');
  }
  final negative = (numerator < 0) != (denominator < 0);
  final n = numerator.abs();
  final d = denominator.abs();
  final q = (2 * n + d) ~/ (2 * d);
  return negative ? -q : q;
}
