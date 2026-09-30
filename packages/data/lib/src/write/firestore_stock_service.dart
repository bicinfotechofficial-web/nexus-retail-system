import 'package:nexus_core/nexus_core.dart';

import '../api/failures.dart';
import '../api/stock.dart';
import '../counters/counter_store.dart';
import '../plans/plan_support.dart';
import '../plans/stock_plans.dart';
import 'write_env.dart';

/// [StockService] on Firestore: one movement per operation, numbered from
/// the device's movement counter, with increments only (D-005).
///
/// Each line's item identity (kind, name, unit) comes from its product or
/// raw material, so a rename shows up on the next movement (QA-023), or
/// from the stock doc if the catalog doc can't be read.
final class FirestoreStockService implements StockService {
  FirestoreStockService(this._env);

  final WriteEnv _env;

  @override
  Future<Movement> stockIn(List<StockLineInput> lines, {String? note}) =>
      _movement(
        Permission.stockMove,
        lines,
        (ctx, seq, qty) =>
            StockPlans.stockIn(ctx: ctx, seq: seq, lines: qty, note: note),
      );

  @override
  Future<Movement> stockOutRaw(
    List<StockLineInput> lines, {
    required String reason,
  }) => _movement(
    Permission.stockMove,
    lines,
    (ctx, seq, qty) =>
        StockPlans.stockOutRaw(ctx: ctx, seq: seq, lines: qty, reason: reason),
  );

  @override
  Future<Movement> wastage(
    StockKind kind,
    List<StockLineInput> lines, {
    required String reason,
  }) => _movement(
    Permission.stockMove,
    lines,
    (ctx, seq, qty) => StockPlans.wastage(
      ctx: ctx,
      seq: seq,
      kind: kind,
      lines: qty,
      reason: reason,
    ),
  );

  @override
  Future<Movement> produce({
    required List<StockLineInput> consumed,
    required List<StockLineInput> produced,
  }) async {
    final loc = _env.requireAtOwnLocation(Permission.stockMove);
    final dev = _env.requireDevice();
    final c = await _resolve(loc, consumed);
    final p = await _resolve(loc, produced);
    final ctx = _env.context(
      _env.requireSession(),
      locationId: loc,
      at: _env.now(),
    );
    return _env.numbered(
      locationId: loc,
      deviceId: dev,
      kind: SeqKind.movement,
      build: (seq) =>
          StockPlans.produce(ctx: ctx, seq: seq, consumed: c, produced: p),
      label: movementLabel,
    );
  }

  @override
  Future<Movement> adjust({
    required String itemKey,
    required int countedQty,
    required String reason,
  }) async {
    final loc = _env.requireAtOwnLocation(Permission.stockAdjust);
    final dev = _env.requireDevice();
    final stock = await _env.reads.stockItem(loc, itemKey);
    final ref = await _ref(loc, itemKey, stock);
    final ctx = _env.context(
      _env.requireSession(),
      locationId: loc,
      at: _env.now(),
    );
    return _env.numbered(
      locationId: loc,
      deviceId: dev,
      kind: SeqKind.movement,
      build: (seq) => StockPlans.adjust(
        ctx: ctx,
        seq: seq,
        item: ref,
        localQty: stock?.qty ?? 0,
        countedQty: countedQty,
        reason: reason,
      ),
      label: movementLabel,
    );
  }

  @override
  Future<void> setThreshold(String itemKey, int? threshold) async {
    final loc = _env.requireAtOwnLocation(Permission.stockThreshold);
    final ref = await _ref(
      loc,
      itemKey,
      await _env.reads.stockItem(loc, itemKey),
    );
    final plan = StockPlans.setThreshold(
      ctx: _env.context(_env.requireSession(), locationId: loc, at: _env.now()),
      item: ref,
      threshold: threshold,
    );
    await _env.write(plan);
  }

  Future<Movement> _movement(
    String permission,
    List<StockLineInput> lines,
    PlannedWrite<Movement> Function(PlanContext, int, List<StockQty>) build,
  ) async {
    final loc = _env.requireAtOwnLocation(permission);
    final dev = _env.requireDevice();
    final qty = await _resolve(loc, lines);
    final ctx = _env.context(
      _env.requireSession(),
      locationId: loc,
      at: _env.now(),
    );
    return _env.numbered(
      locationId: loc,
      deviceId: dev,
      kind: SeqKind.movement,
      build: (seq) => build(ctx, seq, qty),
      label: movementLabel,
    );
  }

  Future<List<StockQty>> _resolve(String loc, List<StockLineInput> lines) =>
      Future.wait([
        for (final l in lines)
          _env.reads
              .stockItem(loc, l.itemKey)
              .then((s) => _ref(loc, l.itemKey, s))
              .then((ref) => StockQty(ref, l.qty)),
      ]);

  /// The item's identity from its catalog doc, else from [stock].
  Future<StockRef> _ref(String loc, String itemKey, StockItem? stock) async {
    final (kind, id) = _parse(itemKey);
    if (kind == StockKind.raw) {
      final m = await _env.reads.rawMaterial(id);
      if (m != null) return StockRef.material(m);
    } else {
      final p = await _env.reads.product(id);
      if (p != null) return StockRef.product(p.id, p.name);
    }
    if (stock != null) return StockRef.of(stock);
    throw DataFailure(FailureReason.notFound, itemKey);
  }

  static (StockKind, String) _parse(String itemKey) {
    for (final (prefix, kind) in [
      ('RM_', StockKind.raw),
      ('FG_', StockKind.finished),
    ]) {
      if (itemKey.startsWith(prefix)) {
        final id = itemKey.substring(prefix.length);
        if (Ids.isSafeKey(id)) return (kind, id);
      }
    }
    throw DataFailure(FailureReason.ruleViolation, 'item key $itemKey');
  }

  static String movementLabel(Movement m) =>
      '${m.type.wire} ${m.id}: '
      '${m.lines.map((l) => '${l.itemKey} ${l.delta > 0 ? '+' : ''}${l.delta}').join(', ')}'
      '${m.reason == null ? '' : ' (${m.reason})'}';
}
