/// Size limits that keep every write batch within the Firestore rules
/// budget and let the rules check lists without loops (D-030).
abstract final class Limits {
  /// Lines on one bill. Each line is a stock doc in the bill's batch.
  static const int maxBillLines = 20;

  /// Lines on one stock movement (STOCK_IN, PRODUCE, ...).
  static const int maxMovementLines = 20;

  /// Payment entries on a bill (04-PERMISSIONS #6).
  static const int maxPayments = 4;

  /// Refund entries on a return (04-PERMISSIONS #7).
  static const int maxRefunds = 4;

  /// Minimum length of a location's offline override PIN, in digits (D-031).
  static const int minOverridePinDigits = 8;
}
