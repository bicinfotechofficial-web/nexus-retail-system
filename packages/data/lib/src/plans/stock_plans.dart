import 'package:nexus_core/nexus_core.dart';

import '../api/failures.dart';
import 'plan_support.dart';
import 'write_plan.dart';

/// Plans for stock operations (03-SYNC §2): one movement `{dev}-M{seq}`,
/// a `set(merge)` with `qty: increment(delta)` per line (D-005), an audit
/// doc `{loc}-{movementId}` for wastage and adjust (04-PERMISSIONS #10), and
/// the device's `lastMovementSeq`.
///
/// Invalid input throws `DataFailure(ruleViolation)`: no lines, more than
/// `Limits.maxMovementLines`, a quantity that isn't positive, an item twice,
/// an item of the wrong kind, or a missing reason.
abstract final class StockPlans {
  /// STOCK_IN: raw materials received. [note] goes to `Movement.note`.
  static PlannedWrite<Movement> stockIn({
    required PlanContext ctx,
    required int seq,
    required List<StockQty> lines,
    String? note,
  }) {
    _check(lines, StockKind.raw);
    final n = note?.trim();
    return _movement(
      ctx,
      seq,
      MovementType.stockIn,
      _signed(lines, 1),
      note: n == null || n.isEmpty ? null : n,
    );
  }

  /// STOCK_OUT_RAW: raw materials taken out for a reason other than wastage.
  static PlannedWrite<Movement> stockOutRaw({
    required PlanContext ctx,
    required int seq,
    required List<StockQty> lines,
    required String reason,
  }) {
    _check(lines, StockKind.raw);
    return _movement(
      ctx,
      seq,
      MovementType.stockOutRaw,
      _signed(lines, -1),
      reason: requireReason(reason),
    );
  }

  /// WASTAGE_RAW or WASTAGE_FG, by [kind], with a WASTAGE audit.
  static PlannedWrite<Movement> wastage({
    required PlanContext ctx,
    required int seq,
    required StockKind kind,
    required List<StockQty> lines,
    required String reason,
  }) {
    _check(lines, kind);
    return _movement(
      ctx,
      seq,
      kind == StockKind.raw ? MovementType.wastageRaw : MovementType.wastageFg,
      _signed(lines, -1),
      reason: requireReason(reason),
      audit: AuditAction.wastage,
    );
  }

  /// PRODUCE: [consumed] raw materials go down and [produced] finished
  /// goods go up, in one movement.
  static PlannedWrite<Movement> produce({
    required PlanContext ctx,
    required int seq,
    required List<StockQty> consumed,
    required List<StockQty> produced,
  }) {
    _check(consumed, StockKind.raw);
    _check(produced, StockKind.finished);
    return _movement(ctx, seq, MovementType.produce, [
      ..._signed(consumed, -1),
      ..._signed(produced, 1),
    ]);
  }

  /// ADJUST: a physical count. The delta is `countedQty − localQty`, the
  /// device's own view (03-SYNC §5), and the line carries both as
  /// before/after. With a STOCK_ADJUST audit.
  static PlannedWrite<Movement> adjust({
    required PlanContext ctx,
    required int seq,
    required StockRef item,
    required int localQty,
    required int countedQty,
    required String reason,
  }) {
    if (countedQty < 0) {
      throw const DataFailure(FailureReason.ruleViolation, 'count below 0');
    }
    return _movement(
      ctx,
      seq,
      MovementType.adjust,
      [(item, countedQty - localQty, localQty, countedQty)],
      reason: requireReason(reason),
      audit: AuditAction.stockAdjust,
    );
  }

  /// Sets or clears (null) an item's `lowThreshold` (`stock.threshold`).
  /// A `set(merge)` with the item's identity, so it also works before the
  /// item's first movement, and never touches `qty`. The contract asks for
  /// no audit entry here (04-PERMISSIONS #10, `StockService`).
  static WritePlan setThreshold({
    required PlanContext ctx,
    required StockRef item,
    required int? threshold,
  }) {
    final loc = ctx.requireLocation();
    if (threshold != null && threshold < 0) {
      throw const DataFailure(FailureReason.ruleViolation, 'threshold below 0');
    }
    return (PlanBuilder()..setMerge(
          FirestorePaths.stockItem(loc, item.itemKey),
          item.thresholdWrite(threshold),
        ))
        .build();
  }

  static List<(StockRef, int, int?, int?)> _signed(
    List<StockQty> lines,
    int sign,
  ) => [for (final l in lines) (l.item, sign * l.qty, null, null)];

  static void _check(List<StockQty> lines, StockKind kind) {
    if (lines.isEmpty) {
      throw const DataFailure(FailureReason.ruleViolation, 'no lines');
    }
    for (final l in lines) {
      if (l.qty <= 0) {
        throw DataFailure(
          FailureReason.ruleViolation,
          '${l.item.itemKey}: qty ${l.qty}',
        );
      }
      if (l.item.kind != kind) {
        throw DataFailure(
          FailureReason.ruleViolation,
          '${l.item.itemKey} is not ${kind.wire}',
        );
      }
    }
  }

  static PlannedWrite<Movement> _movement(
    PlanContext ctx,
    int seq,
    MovementType type,
    List<(StockRef, int, int?, int?)> lines, {
    String? reason,
    String? note,
    AuditAction? audit,
  }) {
    final loc = ctx.requireLocation();
    final dev = ctx.requireDevice();
    if (lines.length > Limits.maxMovementLines) {
      throw DataFailure(
        FailureReason.ruleViolation,
        '${lines.length} lines > ${Limits.maxMovementLines}',
      );
    }
    final keys = <String>{};
    for (final (item, _, _, _) in lines) {
      if (!keys.add(item.itemKey)) {
        throw DataFailure(
          FailureReason.ruleViolation,
          '${item.itemKey} twice in one movement',
        );
      }
    }
    final id = Ids.movementId(dev, seq);
    final movementLines = [
      for (final (item, delta, before, after) in lines)
        MovementLine(
          itemKey: item.itemKey,
          delta: delta,
          before: before,
          after: after,
        ),
    ];
    final movement = Movement(
      id: id,
      type: type,
      lines: movementLines,
      reason: reason,
      note: note,
      businessDate: ctx.businessDate,
      clientCreatedAt: ctx.now,
      createdBy: ctx.uid,
      deviceId: dev,
    );
    final path = FirestorePaths.movement(loc, id);
    final b = PlanBuilder()
      ..create(
        path,
        movementDoc(ctx, dev, type, movementLines, reason: reason, note: note),
      );
    for (final (item, delta, _, _) in lines) {
      b.setMerge(
        FirestorePaths.stockItem(loc, item.itemKey),
        item.qtyWrite(delta, id),
      );
    }
    if (audit != null) {
      final single = movementLines.length == 1 ? movementLines.single : null;
      b.create(
        FirestorePaths.audit(Ids.auditId(loc, id)),
        auditDoc(
          action: audit,
          entityPath: path,
          ctx: ctx,
          locationId: loc,
          before: single?.before == null
              ? null
              : {'itemKey': single!.itemKey, 'qty': single.before},
          after: single?.after != null
              ? {'itemKey': single!.itemKey, 'qty': single.after}
              : {
                  'type': type.wire,
                  'lines': {for (final l in movementLines) l.itemKey: l.delta},
                },
          reason: reason,
        ),
      );
    }
    b.update(FirestorePaths.device(loc, dev), {'lastMovementSeq': seq});
    return PlannedWrite(movement, b.build());
  }
}
