import 'package:nexus_core/nexus_core.dart';
import 'package:nexus_data/nexus_data.dart';

import 'fake_data.dart';
import 'latest.dart';
import 'seed.dart';

/// Stock docs and movements in memory, with the same checks as the real
/// service: the permission for each operation, at most
/// `Limits.maxMovementLines` lines, a reason where 02-DATA-MODEL requires
/// one, and quantities changed only by adding deltas (D-005).
final class FakeStock implements StockRepository, StockService {
  FakeStock({
    required this.auth,
    required this.catalog,
    DateTime Function()? now,
    this.deviceId = Seed.deviceId,
  }) : _now = now ?? DateTime.now;

  final FakeAuthService auth;
  final FakeCatalogRepository catalog;
  final String deviceId;
  final DateTime Function() _now;
  final Map<String, Latest<Map<String, StockItem>>> _byLocation = {};
  int _seq = 0;

  /// Every movement written, oldest first.
  final List<Movement> movements = [];

  /// Every [setThreshold] call as (itemKey, threshold).
  final List<(String, int?)> thresholdCalls = [];

  /// When set, the next write throws it instead of saving.
  Exception? failNext;

  Latest<Map<String, StockItem>> _docs(String locationId) =>
      _byLocation[locationId] ??= Latest(const {});

  /// Replaces the stock docs at [locationId].
  void seed(String locationId, List<StockItem> items) =>
      _docs(locationId).value = {for (final i in items) i.itemKey: i};

  StockItem? item(String locationId, String itemKey) =>
      _docs(locationId).value[itemKey];

  static List<StockItem> _sorted(Iterable<StockItem> items) =>
      items.toList()..sort((a, b) {
        final k = a.kind.index.compareTo(b.kind.index);
        return k != 0 ? k : a.name.compareTo(b.name);
      });

  @override
  Stream<List<StockItem>> watchStock(String locationId) =>
      _docs(locationId).stream.map((m) => _sorted(m.values));

  @override
  Stream<List<StockItem>> watchLowStock(String locationId) => _docs(
    locationId,
  ).stream.map((m) => _sorted(m.values.where((i) => i.isLow)));

  String _location(String permission) {
    final session = auth.current;
    final location = session?.location;
    if (session == null || location == null) {
      throw const DataFailure(FailureReason.noProfile);
    }
    if (!session.canAt(permission, location.code)) {
      throw const DataFailure(FailureReason.notPermitted);
    }
    final failure = failNext;
    if (failure != null) {
      failNext = null;
      throw failure;
    }
    return location.code;
  }

  /// A new stock doc for [itemKey], named from the catalog, at zero.
  StockItem _blank(String itemKey) {
    if (itemKey.startsWith('RM_')) {
      final id = itemKey.substring(3);
      final m = catalog.rawMaterials.where((m) => m.id == id).firstOrNull;
      if (m == null) throw DataFailure(FailureReason.notFound, itemKey);
      return StockItem(
        itemKey: itemKey,
        kind: StockKind.raw,
        refId: id,
        name: m.name,
        unit: m.unit,
        qty: 0,
      );
    }
    if (itemKey.startsWith('FG_')) {
      final id = itemKey.substring(3);
      final p = catalog.products.where((p) => p.id == id).firstOrNull;
      if (p == null) throw DataFailure(FailureReason.notFound, itemKey);
      return StockItem(
        itemKey: itemKey,
        kind: StockKind.finished,
        refId: id,
        name: p.name,
        unit: p.unit,
        qty: 0,
      );
    }
    throw DataFailure(FailureReason.notFound, itemKey);
  }

  static void _checkLines(
    List<StockLineInput> lines, {
    StockKind? kind,
    bool allowEmpty = false,
  }) {
    if (lines.isEmpty && !allowEmpty) {
      throw const DataFailure(FailureReason.ruleViolation, 'no lines');
    }
    if (lines.length > Limits.maxMovementLines) {
      throw const DataFailure(FailureReason.ruleViolation, 'too many lines');
    }
    final keys = <String>{};
    for (final l in lines) {
      if (l.qty <= 0) {
        throw const DataFailure(FailureReason.ruleViolation, 'qty');
      }
      if (!keys.add(l.itemKey)) {
        throw const DataFailure(FailureReason.ruleViolation, 'duplicate');
      }
      final prefix = switch (kind) {
        StockKind.raw => 'RM_',
        StockKind.finished => 'FG_',
        null => '',
      };
      if (!l.itemKey.startsWith(prefix)) {
        throw DataFailure(FailureReason.ruleViolation, l.itemKey);
      }
    }
  }

  static String _reason(String reason) {
    final r = reason.trim();
    if (r.isEmpty) {
      throw const DataFailure(FailureReason.ruleViolation, 'reason');
    }
    return r;
  }

  Movement _write(
    String locationId,
    MovementType type,
    List<MovementLine> lines, {
    String? reason,
    String? note,
  }) {
    _seq++;
    final now = _now();
    final movement = Movement(
      id: Ids.movementId(deviceId, _seq),
      type: type,
      lines: lines,
      reason: reason,
      note: note,
      businessDate: BusinessDate.of(now),
      clientCreatedAt: now,
      createdBy: auth.current!.user.uid,
      deviceId: deviceId,
    );
    final docs = {..._docs(locationId).value};
    for (final l in lines) {
      final before = docs[l.itemKey] ?? _blank(l.itemKey);
      docs[l.itemKey] = _copy(
        before,
        qty: before.qty + l.delta,
        lastMovementId: movement.id,
      );
    }
    _docs(locationId).value = docs;
    movements.add(movement);
    return movement;
  }

  static StockItem _copy(
    StockItem i, {
    int? qty,
    String? lastMovementId,
    int? Function()? threshold,
  }) => StockItem(
    itemKey: i.itemKey,
    kind: i.kind,
    refId: i.refId,
    name: i.name,
    unit: i.unit,
    qty: qty ?? i.qty,
    lowThreshold: threshold == null ? i.lowThreshold : threshold(),
    lastMovementId: lastMovementId ?? i.lastMovementId,
  );

  static List<MovementLine> _deltas(List<StockLineInput> lines, int sign) => [
    for (final l in lines)
      MovementLine(itemKey: l.itemKey, delta: sign * l.qty),
  ];

  @override
  Future<Movement> stockIn(List<StockLineInput> lines, {String? note}) async {
    final loc = _location(Permission.stockMove);
    _checkLines(lines, kind: StockKind.raw);
    final n = note?.trim();
    return _write(
      loc,
      MovementType.stockIn,
      _deltas(lines, 1),
      note: n == null || n.isEmpty ? null : n,
    );
  }

  @override
  Future<Movement> stockOutRaw(
    List<StockLineInput> lines, {
    required String reason,
  }) async {
    final loc = _location(Permission.stockMove);
    _checkLines(lines, kind: StockKind.raw);
    return _write(
      loc,
      MovementType.stockOutRaw,
      _deltas(lines, -1),
      reason: _reason(reason),
    );
  }

  @override
  Future<Movement> wastage(
    StockKind kind,
    List<StockLineInput> lines, {
    required String reason,
  }) async {
    final loc = _location(Permission.stockMove);
    _checkLines(lines, kind: kind);
    return _write(
      loc,
      kind == StockKind.raw ? MovementType.wastageRaw : MovementType.wastageFg,
      _deltas(lines, -1),
      reason: _reason(reason),
    );
  }

  @override
  Future<Movement> produce({
    required List<StockLineInput> consumed,
    required List<StockLineInput> produced,
  }) async {
    final loc = _location(Permission.stockMove);
    _checkLines(consumed, kind: StockKind.raw);
    _checkLines(produced, kind: StockKind.finished);
    if (consumed.length + produced.length > Limits.maxMovementLines) {
      throw const DataFailure(FailureReason.ruleViolation, 'too many lines');
    }
    return _write(loc, MovementType.produce, [
      ..._deltas(consumed, -1),
      ..._deltas(produced, 1),
    ]);
  }

  @override
  Future<Movement> adjust({
    required String itemKey,
    required int countedQty,
    required String reason,
  }) async {
    final loc = _location(Permission.stockAdjust);
    if (countedQty < 0) {
      throw const DataFailure(FailureReason.ruleViolation, 'count');
    }
    final r = _reason(reason);
    final local = (item(loc, itemKey) ?? _blank(itemKey)).qty;
    return _write(loc, MovementType.adjust, [
      MovementLine(
        itemKey: itemKey,
        delta: countedQty - local,
        before: local,
        after: countedQty,
      ),
    ], reason: r);
  }

  @override
  Future<void> setThreshold(String itemKey, int? threshold) async {
    final loc = _location(Permission.stockThreshold);
    if (threshold != null && threshold < 0) {
      throw const DataFailure(FailureReason.ruleViolation, 'threshold');
    }
    thresholdCalls.add((itemKey, threshold));
    final docs = {..._docs(loc).value};
    final before = docs[itemKey] ?? _blank(itemKey);
    docs[itemKey] = _copy(before, threshold: () => threshold);
    _docs(loc).value = docs;
  }
}
