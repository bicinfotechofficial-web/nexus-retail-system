import '../enums.dart';
import '../map_reader.dart';

/// `locations/{loc}/stock/{itemKey}`. `qty` changes only through
/// `increment()` (D-005) and may be negative (03-SYNC §5).
final class StockItem {
  const StockItem({
    required this.itemKey,
    required this.kind,
    required this.refId,
    required this.name,
    required this.unit,
    required this.qty,
    this.lowThreshold,
    this.lastMovementId,
    this.updatedAt,
  });

  factory StockItem.fromMap(String itemKey, Map<String, Object?> map) {
    final r = MapReader(map, 'stock $itemKey');
    return StockItem(
      itemKey: itemKey,
      kind: r.enumValue('kind', StockKind.fromWire),
      refId: r.string('refId'),
      name: r.string('name'),
      unit: r.enumValue('unit', StockUnit.fromWire),
      qty: r.integer('qty'),
      lowThreshold: r.integerOrNull('lowThreshold'),
      lastMovementId: r.stringOrNull('lastMovementId'),
      updatedAt: r.dateTimeOrNull('updatedAt'),
    );
  }

  static const Set<String> serverTimestampFields = {'updatedAt'};

  final String itemKey;
  final StockKind kind;
  final String refId;
  final String name;
  final StockUnit unit;

  /// Base units. May be negative.
  final int qty;
  final int? lowThreshold;
  final String? lastMovementId;
  final DateTime? updatedAt;

  /// At or below the threshold. Items without a threshold are never low.
  bool get isLow => lowThreshold != null && qty <= lowThreshold!;

  Map<String, Object?> toMap() => {
    'kind': kind.wire,
    'refId': refId,
    'name': name,
    'unit': unit.wire,
    'qty': qty,
    'lowThreshold': lowThreshold,
    'lastMovementId': lastMovementId,
  };
}

/// `locations/{loc}/movements/{movementId}`.
final class Movement {
  const Movement({
    required this.id,
    required this.type,
    required this.lines,
    required this.businessDate,
    required this.clientCreatedAt,
    required this.createdBy,
    required this.deviceId,
    this.reason,
    this.refId,
    this.serverCreatedAt,
  });

  factory Movement.fromMap(String id, Map<String, Object?> map) {
    final r = MapReader(map, 'movement $id');
    return Movement(
      id: id,
      type: r.enumValue('type', MovementType.fromWire),
      lines: r.objects('lines', MovementLine._fromReader),
      reason: r.stringOrNull('reason'),
      refId: r.stringOrNull('refId'),
      businessDate: r.string('businessDate'),
      clientCreatedAt: r.dateTime('clientCreatedAt'),
      serverCreatedAt: r.dateTimeOrNull('serverCreatedAt'),
      createdBy: r.string('createdBy'),
      deviceId: r.string('deviceId'),
    );
  }

  static const Set<String> serverTimestampFields = {'serverCreatedAt'};

  final String id;
  final MovementType type;
  final List<MovementLine> lines;
  final String? reason;

  /// billId or returnId.
  final String? refId;
  final String businessDate;
  final DateTime clientCreatedAt;
  final DateTime? serverCreatedAt;
  final String createdBy;
  final String deviceId;

  Map<String, Object?> toMap() => {
    'type': type.wire,
    'lines': lines.map((l) => l.toMap()).toList(),
    'reason': reason,
    'refId': refId,
    'businessDate': businessDate,
    'clientCreatedAt': clientCreatedAt,
    'createdBy': createdBy,
    'deviceId': deviceId,
  };
}

final class MovementLine {
  const MovementLine({
    required this.itemKey,
    required this.delta,
    this.before,
    this.after,
  });

  static MovementLine _fromReader(MapReader r) => MovementLine(
    itemKey: r.string('itemKey'),
    delta: r.integer('delta'),
    before: r.integerOrNull('before'),
    after: r.integerOrNull('after'),
  );

  final String itemKey;

  /// Signed, base units.
  final int delta;

  /// Only on ADJUST, from the device's local view.
  final int? before;
  final int? after;

  Map<String, Object?> toMap() => {
    'itemKey': itemKey,
    'delta': delta,
    if (before != null) 'before': before,
    if (after != null) 'after': after,
  };
}
