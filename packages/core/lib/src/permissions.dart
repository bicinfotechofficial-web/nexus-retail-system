/// Permission strings (04-PERMISSIONS). Code checks these, never role names
/// (D-017).
abstract final class Permission {
  static const String catalogView = 'catalog.view';
  static const String catalogSuggest = 'catalog.suggest';
  static const String catalogManage = 'catalog.manage';
  static const String rawMaterialCreate = 'rawMaterial.create';
  static const String billCreate = 'bill.create';
  static const String billCancel = 'bill.cancel';
  static const String returnCreate = 'return.create';
  static const String stockMove = 'stock.move';
  static const String stockAdjust = 'stock.adjust';
  static const String stockThreshold = 'stock.threshold';
  static const String reportOwn = 'report.own';
  static const String reportAll = 'report.all';
  static const String expenseManage = 'expense.manage';
  static const String auditView = 'audit.view';
  static const String userManage = 'user.manage';
  static const String locationManage = 'location.manage';
  static const String deviceRegister = 'device.register';

  static const List<String> all = [
    catalogView,
    catalogSuggest,
    catalogManage,
    rawMaterialCreate,
    billCreate,
    billCancel,
    returnCreate,
    stockMove,
    stockAdjust,
    stockThreshold,
    reportOwn,
    reportAll,
    expenseManage,
    auditView,
    userManage,
    locationManage,
    deviceRegister,
  ];
}

/// Seeded role IDs and their permission sets (04-PERMISSIONS role matrix).
/// Only the seed script (BE-14) and tests use these; the apps read roles
/// from Firestore.
abstract final class SeedRoles {
  static const String adminId = 'ADMIN';
  static const String storeManagerId = 'STORE_MANAGER';

  static const List<String> adminPermissions = Permission.all;

  static const List<String> storeManagerPermissions = [
    Permission.catalogView,
    Permission.catalogSuggest,
    Permission.rawMaterialCreate,
    Permission.billCreate,
    Permission.billCancel,
    Permission.returnCreate,
    Permission.stockMove,
    Permission.stockAdjust,
    Permission.stockThreshold,
    Permission.reportOwn,
    Permission.deviceRegister,
  ];
}
