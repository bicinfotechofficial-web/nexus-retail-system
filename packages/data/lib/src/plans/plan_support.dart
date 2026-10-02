import 'package:nexus_core/nexus_core.dart';

import '../api/failures.dart';
import 'write_plan.dart';

/// Who is writing, where, and when. Every plan builder takes one.
final class PlanContext {
  const PlanContext({
    required this.uid,
    required this.now,
    this.locationId,
    this.deviceId,
  });

  /// The signed-in user; written as `createdBy` / `by`.
  final String uid;

  /// The user's location; null for roles with `allLocations` (Admin).
  final String? locationId;

  /// This install's device code, or null before registration (D-004).
  final String? deviceId;

  /// The device clock at the moment of the operation. Written as
  /// `clientCreatedAt` / `clientAt`, and the business date comes from it.
  final DateTime now;

  /// Today's business date in IST (D-022).
  String get businessDate => BusinessDate.of(now);

  /// The location, or `DataFailure(notPermitted)` for a user without one.
  String requireLocation() {
    final loc = locationId;
    if (loc == null || !Ids.isLocationCode(loc)) {
      throw const DataFailure(FailureReason.notPermitted, 'no location');
    }
    return loc;
  }

  /// The device code, or `DataFailure(deviceNotRegistered)`.
  String requireDevice() {
    final d = deviceId;
    if (d == null || !Ids.isDeviceCode(d)) {
      throw const DataFailure(FailureReason.deviceNotRegistered);
    }
    return d;
  }
}

/// A plan and the model it writes, for the service to return.
final class PlannedWrite<T> {
  const PlannedWrite(this.value, this.plan);

  final T value;
  final WritePlan plan;
}

/// What a stock doc carries besides `qty` (02-DATA-MODEL stock): written
/// with every `set(merge)`, so the first use creates the doc and a rename
/// shows up on the next write (QA-023).
final class StockRef {
  const StockRef({
    required this.kind,
    required this.refId,
    required this.name,
    required this.unit,
  });

  /// A finished good. Always PCS in the MVP (02-DATA-MODEL products).
  factory StockRef.product(String productId, String name) => StockRef(
    kind: StockKind.finished,
    refId: productId,
    name: name,
    unit: StockUnit.pcs,
  );

  factory StockRef.material(RawMaterial m) =>
      StockRef(kind: StockKind.raw, refId: m.id, name: m.name, unit: m.unit);

  factory StockRef.of(StockItem i) =>
      StockRef(kind: i.kind, refId: i.refId, name: i.name, unit: i.unit);

  final StockKind kind;
  final String refId;
  final String name;
  final StockUnit unit;

  /// `RM_{materialId}` or `FG_{productId}`.
  String get itemKey => kind == StockKind.raw
      ? Ids.rawItemKey(refId)
      : Ids.finishedItemKey(refId);

  /// The `set(merge)` data for a quantity change of [delta], tied to the
  /// movement [movementId] written in the same batch (04-PERMISSIONS #8).
  Map<String, Object?> qtyWrite(int delta, String movementId) => {
    ..._identity,
    'qty': Increment(delta),
    'lastMovementId': movementId,
    'updatedAt': serverTimestamp,
  };

  Map<String, Object?> get _identity => {
    'kind': kind.wire,
    'refId': refId,
    'name': name,
    'unit': unit.wire,
  };

  /// The `set(merge)` data for a threshold change; never touches `qty`.
  Map<String, Object?> thresholdWrite(int? threshold) => {
    ..._identity,
    'lowThreshold': threshold,
    'updatedAt': serverTimestamp,
  };
}

/// A stock item and a positive quantity in base units (D-006).
final class StockQty {
  const StockQty(this.item, this.qty);

  final StockRef item;
  final int qty;
}

/// Audit IDs for events that can repeat on one entity. Thin names over the
/// builders in `Ids` (D-032), kept so the plan builders read clearly.
abstract final class PlanAuditIds {
  static String priceChange(String productId, DateTime at) =>
      Ids.priceChangeAuditId(productId, at);

  static String productApprove(String productId, DateTime at) =>
      Ids.productApproveAuditId(productId, at);

  static String productDecline(String productId, DateTime at) =>
      Ids.productDeclineAuditId(productId, at);

  static String userDisable(String uid, String? locationId, DateTime at) =>
      Ids.userAuditId(locationId, uid, at);

  static String locationUpdate(String locationId, DateTime at) =>
      Ids.locationAuditId(locationId, at);
}

/// A model's map with each of its `serverTimestampFields` set to the
/// sentinel.
Map<String, Object?> withServerTimestamps(
  Map<String, Object?> map,
  Set<String> fields,
) => {...map, for (final f in fields) f: serverTimestamp};

/// The audit doc written in the same batch as the change (D-019).
Map<String, Object?> auditDoc({
  required AuditAction action,
  required String entityPath,
  required PlanContext ctx,
  String? locationId,
  Map<String, Object?>? before,
  Map<String, Object?>? after,
  String? reason,
}) => withServerTimestamps(
  AuditEntry(
    id: '',
    action: action,
    entityPath: entityPath,
    locationId: locationId,
    before: before,
    after: after,
    reason: reason,
    by: ctx.uid,
    deviceId: ctx.deviceId,
    clientAt: ctx.now,
  ).toMap(),
  AuditEntry.serverTimestampFields,
);

/// Adds the summary increments of [delta] to the daily doc of
/// [businessDate] (unless [daily] is false) and to its monthly doc, each
/// naming [lastWriteRef] (04-PERMISSIONS #9). A delta with nothing to add
/// writes nothing.
void addSummaryWrites(
  PlanBuilder b, {
  required String locationId,
  required Summary delta,
  required String lastWriteRef,
  String? businessDate,
  String? monthKey,
}) {
  final inc = SummaryDeltas.increments(delta);
  if (inc.isEmpty) return;
  final data = {
    ...nestFieldPaths({for (final e in inc.entries) e.key: Increment(e.value)}),
    'lastWriteRef': lastWriteRef,
  };
  if (businessDate != null) {
    b.setMerge(FirestorePaths.dailySummary(locationId, businessDate), data);
  }
  final month = monthKey ?? BusinessDate.monthOf(businessDate!);
  b.setMerge(FirestorePaths.monthlySummary(locationId, month), data);
}

/// A non-empty trimmed reason, or `DataFailure(ruleViolation)`.
String requireReason(String reason) {
  final r = reason.trim();
  if (r.isEmpty) {
    throw const DataFailure(FailureReason.ruleViolation, 'a reason is needed');
  }
  return r;
}

/// A new movement doc (02-DATA-MODEL movements).
Map<String, Object?> movementDoc(
  PlanContext ctx,
  String deviceId,
  MovementType type,
  List<MovementLine> lines, {
  String? reason,
  String? note,
  String? refId,
}) => withServerTimestamps(
  Movement(
    id: '',
    type: type,
    lines: lines,
    reason: reason,
    note: note,
    refId: refId,
    businessDate: ctx.businessDate,
    clientCreatedAt: ctx.now,
    createdBy: ctx.uid,
    deviceId: deviceId,
  ).toMap(),
  Movement.serverTimestampFields,
);

/// `locations/{loc}/customers` (D-037).
String customersPath(String loc) => FirestorePaths.customers(loc);

/// `locations/{loc}/customers/{customerId}`.
String customerPath(String loc, String customerId) =>
    FirestorePaths.customer(loc, customerId);

/// The customer record's write in a bill's batch (D-037), as `set(merge)`.
/// A device can't know offline whether the record exists, so every bill
/// writes the same shape: `name`, `phone` and `whatsapp` as on the bill,
/// `lastBillAt` as the server time, `lastWriteRef` as the bill's ID (the rules'
/// #14 ties the write to that new bill), and the two counters as increments. The first bill therefore
/// creates the record with `billCount` 1 and `totalSpend` equal to its total.
Map<String, Object?> customerWrite(
  BillCustomer customer, {
  required String billId,
  required Money total,
}) => {
  'name': customer.name,
  'phone': customer.phone,
  'whatsapp': customer.whatsapp,
  'lastBillAt': serverTimestamp,
  'billCount': const Increment(1),
  'totalSpend': Increment(total.paise),
  'lastWriteRef': billId,
};

/// Longest `reviewNote` on a declined suggestion, in characters (D-038).
/// Rule #11 repeats it.
const int reviewNoteMax = Limits.reviewNoteMax;
