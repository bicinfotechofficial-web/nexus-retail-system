/// Size limits that keep every write batch within the Firestore rules
/// budget and let the rules check lists without loops (D-030).
abstract final class Limits {
  /// Lines on one bill, and so on one return. Each line is a stock doc in
  /// the batch, and the rules unroll per-line checks, which must stay under
  /// Firestore's 1000-expression limit per evaluation (CR-001).
  static const int maxBillLines = 15;

  /// Lines on one stock movement (STOCK_IN, PRODUCE, ...).
  static const int maxMovementLines = 20;

  /// Payment entries on a bill (04-PERMISSIONS #6).
  static const int maxPayments = 4;

  /// Refund entries on a return (04-PERMISSIONS #7).
  static const int maxRefunds = 4;

  /// Minimum length of a location's offline override PIN, in digits (D-031).
  static const int minOverridePinDigits = 8;

  /// Longest customer name, in characters (D-034).
  static const int customerNameMax = 60;

  /// Longest note on a declined suggestion, in characters (D-038).
  static const int reviewNoteMax = 200;

  /// Longest staff name and role label, in characters (D-042).
  static const int staffNameMax = 60;
  static const int staffRoleMax = 30;

  /// Longest attendance note, in characters (D-042).
  static const int attendanceNoteMax = 100;

  /// Attendance documents in one batch, so the rules budget holds (D-030).
  static const int maxAttendanceBatch = 15;

  /// How many days back the POS lets the manager mark attendance (D-042).
  static const int attendanceBackDays = 7;

  /// Longest pre-order description, in characters (D-043).
  static const int orderDescriptionMax = 500;

  /// Longest reason on a cancelled pre-order (D-043).
  static const int orderReasonMax = 100;
}
