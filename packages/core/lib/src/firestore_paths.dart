/// Every Firestore path, relative to the database root (02-DATA-MODEL).
/// Nothing else in the codebase should build a path string by hand.
abstract final class FirestorePaths {
  static const String roles = 'roles';
  static const String users = 'users';
  static const String locations = 'locations';
  static const String products = 'products';
  static const String rawMaterials = 'rawMaterials';
  static const String expenses = 'expenses';
  static const String auditLog = 'auditLog';

  static String role(String roleId) => '$roles/$roleId';
  static String user(String uid) => '$users/$uid';
  static String location(String loc) => '$locations/$loc';

  static String devices(String loc) => '${location(loc)}/devices';
  static String device(String loc, String deviceId) =>
      '${devices(loc)}/$deviceId';

  static String stock(String loc) => '${location(loc)}/stock';
  static String stockItem(String loc, String itemKey) =>
      '${stock(loc)}/$itemKey';

  static String movements(String loc) => '${location(loc)}/movements';
  static String movement(String loc, String movementId) =>
      '${movements(loc)}/$movementId';

  static String bills(String loc) => '${location(loc)}/bills';
  static String bill(String loc, String billId) => '${bills(loc)}/$billId';

  static String returns(String loc) => '${location(loc)}/returns';
  static String saleReturn(String loc, String returnId) =>
      '${returns(loc)}/$returnId';

  static String dailySummaries(String loc) => '${location(loc)}/dailySummary';
  static String dailySummary(String loc, String businessDate) =>
      '${dailySummaries(loc)}/$businessDate';

  static String monthlySummaries(String loc) =>
      '${location(loc)}/monthlySummary';
  static String monthlySummary(String loc, String monthKey) =>
      '${monthlySummaries(loc)}/$monthKey';

  static String product(String productId) => '$products/$productId';
  static String rawMaterial(String materialId) => '$rawMaterials/$materialId';
  static String expense(String expenseId) => '$expenses/$expenseId';
  static String audit(String auditId) => '$auditLog/$auditId';
}
