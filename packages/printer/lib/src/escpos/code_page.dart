/// A printer character table, selected with `ESC t n`.
///
/// Printable ASCII (0x20–0x7E) is the same on every ESC/POS table. [extra]
/// maps the few non-ASCII characters we print to their byte on this table.
/// The pilot printer's model isn't known yet (B-4), so tables are data: a
/// printer whose table has a ₹ glyph gets a [CodePage] with `'₹'` in
/// [extra], and nothing else changes.
final class CodePage {
  const CodePage({
    required this.name,
    required this.escPosNumber,
    this.extra = const {},
  });

  /// PC437 (USA, standard Europe), table 0. Every ESC/POS printer has it,
  /// and it has no ₹.
  static const CodePage pc437 = CodePage(name: 'PC437', escPosNumber: 0);

  final String name;

  /// `n` in `ESC t n`.
  final int escPosNumber;

  /// Character (one code point) → byte on this table.
  final Map<String, int> extra;

  /// True when this table prints the ₹ glyph.
  bool get hasRupee => extra.containsKey(rupee);

  /// The currency symbol to lay receipts out with: `₹` when this table has
  /// the glyph, otherwise `Rs.` (PR-3). Choose it *before* layout, because
  /// the two differ in width.
  String get currencySymbol => hasRupee ? rupee : rupeeFallback;

  /// The byte for [codePoint], or null when this table can't print it.
  int? byteFor(int codePoint) {
    if (codePoint >= 0x20 && codePoint <= 0x7E) return codePoint;
    return extra[String.fromCharCode(codePoint)];
  }

  static const String rupee = '₹';
  static const String rupeeFallback = 'Rs.';
}
