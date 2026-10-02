import 'package:nexus_core/nexus_core.dart';

import '../api/failures.dart';
import '../api/sales.dart';
import 'plan_support.dart';
import 'write_plan.dart';

/// Plans for bills, cancellations and returns (03-SYNC §2). Pure: the
/// caller reads the bill, allocates the sequence number (persisted first,
/// 03-SYNC §3) and applies the plan as one batch.
abstract final class SalesPlans {
  /// Create bill: the bill (with `soldQty` and the customer fields), a
  /// `FG_*` stock decrement per line, the SALE movement (the bill's ID), the
  /// daily and monthly summary increments naming the bill, the customer
  /// record (`set(merge)` in every bill, D-037; see [customerWrite]) and the
  /// device's `lastBillSeq`.
  ///
  /// Throws the calculator's `BillValidationException`, or
  /// `DataFailure(ruleViolation)` when the payments don't check out.
  static PlannedWrite<Bill> createBill({
    required PlanContext ctx,
    required int seq,
    required NewBill input,
    required String servedByName,
    int? maxDiscountPct,
  }) {
    final loc = ctx.requireLocation();
    final dev = ctx.requireDevice();
    final totals = BillCalculator.compute(
      input.cart,
      discount: input.discount,
      maxDiscountPct: maxDiscountPct,
    );
    final check = BillCalculator.checkPayments(
      totals.total,
      input.payments,
      cashTendered: input.cashTendered,
    );
    if (!check.isValid) {
      throw DataFailure(
        FailureReason.ruleViolation,
        'payments: ${check.errors.map((e) => e.name).join(', ')}',
      );
    }
    final id = Ids.billId(dev, seq);
    final bill = Bill(
      id: id,
      billNo: Ids.billNo(loc, id),
      deviceId: dev,
      seq: seq,
      lines: totals.lines,
      subtotal: totals.subtotal,
      discount: totals.discount,
      taxableValue: totals.taxableValue,
      taxLines: totals.taxLines,
      roundOff: totals.roundOff,
      total: totals.total,
      payments: input.payments,
      cashTendered: input.cashTendered,
      status: BillStatus.completed,
      servedBy: ServedBy(uid: ctx.uid, name: servedByName),
      businessDate: ctx.businessDate,
      clientCreatedAt: ctx.now,
      createdBy: ctx.uid,
      customer: input.customer,
    );

    final billPath = FirestorePaths.bill(loc, id);
    final movementId = Ids.saleMovementId(id);
    final b = PlanBuilder()
      ..create(
        billPath,
        withServerTimestamps(bill.toMap(), Bill.serverTimestampFields),
      );
    for (final l in bill.lines) {
      final ref = StockRef.product(l.productId, l.name);
      b.setMerge(
        FirestorePaths.stockItem(loc, ref.itemKey),
        ref.qtyWrite(-l.qty, movementId),
      );
    }
    b.create(
      FirestorePaths.movement(loc, movementId),
      movementDoc(ctx, dev, MovementType.sale, [
        for (final l in bill.lines)
          MovementLine(
            itemKey: Ids.finishedItemKey(l.productId),
            delta: -l.qty,
          ),
      ], refId: id),
    );
    addSummaryWrites(
      b,
      locationId: loc,
      businessDate: bill.businessDate,
      delta: SummaryDeltas.forBill(bill),
      lastWriteRef: billPath,
    );
    b
      ..setMerge(
        customerPath(loc, input.customer.id),
        customerWrite(input.customer, billId: id, total: bill.total),
      )
      ..update(FirestorePaths.device(loc, dev), {'lastBillSeq': seq});
    return PlannedWrite(bill, b.build());
  }

  /// Same-day cancel (D-009): the bill's status and `cancel`, a `FG_*`
  /// increment per line, the CANCEL movement `{billId}-X`, the summaries of
  /// `SummaryDeltas.forCancel` naming that movement, and the BILL_CANCEL
  /// audit `{loc}-{billId}-X`. The cancelling device may differ from the
  /// bill's; no device counter moves.
  ///
  /// Throws `DataFailure(ruleViolation)` when `cancelBlocker` says no
  /// (another day, already cancelled, or returned, D-025).
  static PlannedWrite<Bill> cancelBill({
    required PlanContext ctx,
    required Bill bill,
    required String reason,
  }) {
    final loc = ctx.requireLocation();
    final dev = ctx.requireDevice();
    final r = requireReason(reason);
    final blocker = cancelBlocker(bill, ctx.businessDate);
    if (blocker != null) {
      throw DataFailure(FailureReason.ruleViolation, 'cancel: ${blocker.name}');
    }
    final cancel = BillCancel(
      reason: r,
      by: ctx.uid,
      at: ctx.now,
      businessDate: bill.businessDate,
    );
    final cancelled = _withStatus(bill, BillStatus.cancelled, cancel);
    final xId = Ids.cancelId(bill.id);
    final billPath = FirestorePaths.bill(loc, bill.id);
    final movementPath = FirestorePaths.movement(loc, xId);

    final b = PlanBuilder()
      ..update(billPath, {
        'status': BillStatus.cancelled.wire,
        'cancel': cancel.toMap(),
      });
    for (final l in bill.lines) {
      final ref = StockRef.product(l.productId, l.name);
      b.setMerge(
        FirestorePaths.stockItem(loc, ref.itemKey),
        ref.qtyWrite(l.qty, xId),
      );
    }
    b.create(
      movementPath,
      movementDoc(
        ctx,
        dev,
        MovementType.cancel,
        [
          for (final l in bill.lines)
            MovementLine(
              itemKey: Ids.finishedItemKey(l.productId),
              delta: l.qty,
            ),
        ],
        reason: r,
        refId: bill.id,
      ),
    );
    addSummaryWrites(
      b,
      locationId: loc,
      businessDate: bill.businessDate,
      delta: SummaryDeltas.forCancel(bill),
      lastWriteRef: movementPath,
    );
    b.create(
      FirestorePaths.audit(Ids.auditId(loc, xId)),
      auditDoc(
        action: AuditAction.billCancel,
        entityPath: billPath,
        ctx: ctx,
        locationId: loc,
        before: {'status': BillStatus.completed.wire},
        after: {'status': BillStatus.cancelled.wire},
        reason: r,
      ),
    );
    return PlannedWrite(cancelled, b.build());
  }

  /// Return: the return doc (`prevReturnId` = the bill's `lastReturnId`),
  /// the bill's `returnedQty` increments and `lastReturnId`, a `FG_*`
  /// increment per line, the RETURN movement (the return's ID), the
  /// summaries of `SummaryDeltas.forReturn` on today's date naming the
  /// return (D-012), the RETURN audit `{loc}-{returnId}`, and the device's
  /// `lastReturnSeq`.
  ///
  /// [bill] must be the bill as this device last read it; the rules reject
  /// the batch if another return landed since (D-029). Throws the
  /// calculator's `ReturnValidationException`, or
  /// `DataFailure(ruleViolation)` when the refunds don't check out.
  static PlannedWrite<SaleReturn> createReturn({
    required PlanContext ctx,
    required int seq,
    required Bill bill,
    required Map<String, int> qtyByProduct,
    required List<Payment> refunds,
    required String reason,
  }) {
    final loc = ctx.requireLocation();
    final dev = ctx.requireDevice();
    final totals = ReturnCalculator.compute(bill, qtyByProduct);
    final errors = ReturnCalculator.checkRefunds(totals.refundTotal, refunds);
    if (errors.isNotEmpty) {
      throw DataFailure(
        FailureReason.ruleViolation,
        'refunds: ${errors.map((e) => e.name).join(', ')}',
      );
    }
    final id = Ids.returnId(dev, seq);
    final ret = SaleReturn(
      id: id,
      billId: bill.id,
      billNo: bill.billNo,
      lines: totals.lines,
      refundTotal: totals.refundTotal,
      refunds: refunds,
      reason: reason.trim(),
      prevReturnId: bill.lastReturnId,
      businessDate: ctx.businessDate,
      createdBy: ctx.uid,
      deviceId: dev,
      clientCreatedAt: ctx.now,
    );
    final returnPath = FirestorePaths.saleReturn(loc, id);
    final movementId = Ids.returnMovementId(id);

    final b = PlanBuilder()
      ..create(
        returnPath,
        withServerTimestamps(ret.toMap(), SaleReturn.serverTimestampFields),
      )
      ..update(FirestorePaths.bill(loc, bill.id), {
        for (final l in ret.lines)
          'returnedQty.${l.productId}': Increment(l.qty),
        'lastReturnId': id,
      });
    for (final l in ret.lines) {
      final ref = StockRef.product(l.productId, l.name);
      b.setMerge(
        FirestorePaths.stockItem(loc, ref.itemKey),
        ref.qtyWrite(l.qty, movementId),
      );
    }
    b.create(
      FirestorePaths.movement(loc, movementId),
      movementDoc(ctx, dev, MovementType.returned, [
        for (final l in ret.lines)
          MovementLine(itemKey: Ids.finishedItemKey(l.productId), delta: l.qty),
      ], refId: id),
    );
    addSummaryWrites(
      b,
      locationId: loc,
      businessDate: ret.businessDate,
      delta: SummaryDeltas.forReturn(ret),
      lastWriteRef: returnPath,
    );
    b
      ..create(
        FirestorePaths.audit(Ids.auditId(loc, id)),
        auditDoc(
          action: AuditAction.returned,
          entityPath: returnPath,
          ctx: ctx,
          locationId: loc,
          after: {
            'billId': bill.id,
            'refundTotal': ret.refundTotal.paise,
            'lines': {for (final l in ret.lines) l.productId: l.qty},
          },
          reason: ret.reason.isEmpty ? null : ret.reason,
        ),
      )
      ..update(FirestorePaths.device(loc, dev), {'lastReturnSeq': seq});
    return PlannedWrite(ret, b.build());
  }

  static Bill _withStatus(Bill b, BillStatus status, BillCancel cancel) => Bill(
    id: b.id,
    billNo: b.billNo,
    deviceId: b.deviceId,
    seq: b.seq,
    lines: b.lines,
    subtotal: b.subtotal,
    discount: b.discount,
    taxableValue: b.taxableValue,
    taxLines: b.taxLines,
    roundOff: b.roundOff,
    total: b.total,
    payments: b.payments,
    cashTendered: b.cashTendered,
    status: status,
    cancel: cancel,
    returnedQty: b.returnedQty,
    lastReturnId: b.lastReturnId,
    servedBy: b.servedBy,
    businessDate: b.businessDate,
    clientCreatedAt: b.clientCreatedAt,
    serverCreatedAt: b.serverCreatedAt,
    createdBy: b.createdBy,
  );
}
