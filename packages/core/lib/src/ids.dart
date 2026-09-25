/// Builders and validators for every deterministic ID (02-DATA-MODEL,
/// 03-SYNC §3–4). Deterministic IDs are what make retries idempotent.
abstract final class Ids {
  static final RegExp _location = RegExp(r'^[A-Z]{2,4}$');
  static final RegExp _device = RegExp(r'^D\d{2}$');
  static final RegExp _safeKey = RegExp(r'^[A-Za-z0-9_-]{1,100}$');

  /// Seq numbers are zero-padded to 6 digits so IDs sort in order (D-024).
  static const int seqWidth = 6;
  static const int maxSeq = 999999;
  static const int maxDeviceNo = 99;

  /// A location code: 2–4 uppercase letters, e.g. `PTB`.
  static bool isLocationCode(String s) => _location.hasMatch(s);

  /// A device code: `D01` … `D99`.
  static bool isDeviceCode(String s) => _device.hasMatch(s);

  /// Product, material and expense IDs become Firestore map keys and field
  /// path segments (`byProduct.<id>.qty`), so they must not contain dots,
  /// slashes or spaces.
  static bool isSafeKey(String s) => _safeKey.hasMatch(s);

  /// `D01` for device number 1. Codes are never reused (D-004).
  static String deviceCode(int deviceNo) {
    RangeError.checkValueInInterval(deviceNo, 1, maxDeviceNo, 'deviceNo');
    return 'D${deviceNo.toString().padLeft(2, '0')}';
  }

  /// `D01-000123` (the bill doc ID).
  static String billId(String deviceId, int seq) =>
      '${_dev(deviceId)}-${_seq(seq)}';

  /// `PTB-D01-000123` (printed on the receipt, D-003).
  static String billNo(String locationId, String billId) =>
      '${_loc(locationId)}-$billId';

  /// `D01-M000042`, for stock in/out, wastage, produce and adjust.
  static String movementId(String deviceId, int seq) =>
      '${_dev(deviceId)}-M${_seq(seq)}';

  /// `D01-R000007`.
  static String returnId(String deviceId, int seq) =>
      '${_dev(deviceId)}-R${_seq(seq)}';

  /// The SALE movement of a bill shares the bill's ID.
  static String saleMovementId(String billId) => billId;

  /// The RETURN movement of a return shares the return's ID.
  static String returnMovementId(String returnId) => returnId;

  /// `D01-000123-X`: the CANCEL movement of a bill. Its audit doc is
  /// `auditId(loc, cancelId(billId))`.
  static String cancelId(String billId) => '$billId-X';

  /// `PTB-D01-000123-X`: the audit doc for a location-scoped entity (a
  /// cancellation, return, wastage or adjust movement). `auditLog` is a root
  /// collection and device codes repeat across locations, so the location
  /// prefix keeps IDs unique (D-028).
  static String auditId(String locationId, String entityId) =>
      '${_loc(locationId)}-$entityId';

  /// `PTB-D01-OVR-1790000000000`: one audit doc per offline PIN override,
  /// which can be repeated (D-016, D-028).
  static String overrideAuditId(
    String locationId,
    String deviceId,
    DateTime at,
  ) => '${_loc(locationId)}-${_dev(deviceId)}-OVR-${at.millisecondsSinceEpoch}';

  /// `EXP-{expenseId}-{millis}`: one audit doc per expense create or edit.
  static String expenseAuditId(String expenseId, DateTime at) =>
      'EXP-$expenseId-${at.millisecondsSinceEpoch}';

  /// `RM_{materialId}`.
  static String rawItemKey(String materialId) => 'RM_${_key(materialId)}';

  /// `FG_{productId}`.
  static String finishedItemKey(String productId) => 'FG_${_key(productId)}';

  static String _dev(String d) {
    if (!isDeviceCode(d)) throw ArgumentError.value(d, 'deviceId');
    return d;
  }

  static String _loc(String l) {
    if (!isLocationCode(l)) throw ArgumentError.value(l, 'locationId');
    return l;
  }

  static String _key(String k) {
    if (!isSafeKey(k)) throw ArgumentError.value(k, 'id');
    return k;
  }

  static String _seq(int seq) {
    RangeError.checkValueInInterval(seq, 1, maxSeq, 'seq');
    return seq.toString().padLeft(seqWidth, '0');
  }
}
