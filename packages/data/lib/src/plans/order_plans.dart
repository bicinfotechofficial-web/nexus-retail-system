import 'package:nexus_core/nexus_core.dart';

import '../api/failures.dart';
import '../api/orders.dart';
import '../api/sales.dart';
import 'plan_support.dart';
import 'sales_plans.dart';
import 'write_plan.dart';

/// Plans for pre-orders (D-043): take, deliver and cancel. Pure, like
/// [SalesPlans]: the caller reads the order, allocates the number (persisted
/// first, 03-SYNC §3) and applies the plan as one batch.
abstract final class OrderPlans {
  /// The seeded open-price product a delivery bill sells (D-043 (c)).
  static const String customCakeProductId = 'CUSTOM-CAKE';

  /// Its name when the product document can't be read (offline, uncached).
  static const String customCakeName = 'Custom cake';

  /// Take an order: the order (OPEN, the customer fields as on a bill), the
  /// device's `lastOrderSeq`, and, when the advance is above zero, the daily
  /// and monthly summaries' `advanceReceived` naming the order (rules #18
  /// and #20). Taking an order does not touch stock or the customer record.
  ///
  /// Throws `DataFailure(ruleViolation)` with the validator's message when
  /// the description, due date or time, price or advance is not acceptable.
  static PlannedWrite<PreOrder> create({
    required PlanContext ctx,
    required int seq,
    required NewOrder input,
    required String servedByName,
  }) {
    final loc = ctx.requireLocation();
    final dev = ctx.requireDevice();
    final today = ctx.businessDate;
    final description = OrderValidator.cleanDescription(input.description);
    final problem =
        OrderValidator.descriptionError(description) ??
        OrderValidator.dueDateError(input.dueDate, today) ??
        OrderValidator.dueTimeError(input.dueTime) ??
        OrderValidator.priceError(input.price) ??
        OrderValidator.advanceError(
          input.advance,
          input.price,
          input.advanceMode,
        );
    if (problem != null) {
      throw DataFailure(FailureReason.ruleViolation, problem);
    }
    final id = Ids.orderId(dev, seq);
    final order = PreOrder(
      id: id,
      orderNo: Ids.orderNo(loc, id),
      deviceId: dev,
      seq: seq,
      customer: input.customer,
      dueDate: input.dueDate,
      dueTime: input.dueTime,
      description: description,
      price: input.price,
      advance: input.advance,
      advanceMode: input.advance.isZero ? null : input.advanceMode,
      status: OrderStatus.open,
      servedBy: ServedBy(uid: ctx.uid, name: servedByName),
      businessDate: today,
      clientCreatedAt: ctx.now,
      createdBy: ctx.uid,
      locationId: loc,
    );
    final path = FirestorePaths.order(loc, id);
    final b = PlanBuilder()
      ..create(
        path,
        // Only the creation stamp: `deliveredAt` is set on delivery.
        withServerTimestamps(order.toMap(), const {'serverCreatedAt'}),
      )
      ..update(FirestorePaths.device(loc, dev), {'lastOrderSeq': seq});
    addSummaryWrites(
      b,
      locationId: loc,
      businessDate: today,
      delta: SummaryDeltas.forOrderCreated(order),
      lastWriteRef: path,
    );
    return PlannedWrite(order, b.build());
  }

  /// Deliver an OPEN [order] as one ordinary bill, built by
  /// `SalesPlans.createBill`: a single line for `CUSTOM-CAKE` at the order's
  /// price, the order's customer, `orderId` on the bill, the customer-record
  /// merge, stock, SALE movement and summaries as for any bill, and the
  /// order's update to DELIVERED in the same batch (rules #18 (a), #19).
  ///
  /// The payments are an `ADVANCE` entry for the order's advance (none when
  /// it is zero), then [payments] for the balance, which must add up to it
  /// and use only `PaymentMode.selectable`. [productName] is the product's
  /// current name.
  ///
  /// Throws `DataFailure(ruleViolation)` when the order is not OPEN or the
  /// payments don't check out, and the calculator's exceptions otherwise.
  static PlannedWrite<Bill> deliver({
    required PlanContext ctx,
    required int seq,
    required PreOrder order,
    required List<Payment> payments,
    required String servedByName,
    Money? cashTendered,
    String productName = customCakeName,
  }) {
    if (!order.isOpen) {
      throw DataFailure(
        FailureReason.ruleViolation,
        'order ${order.id} is ${order.status.wire}, not OPEN',
      );
    }
    if (payments.any((p) => !PaymentMode.selectable.contains(p.mode))) {
      throw const DataFailure(
        FailureReason.ruleViolation,
        'the balance cannot be paid with ADVANCE',
      );
    }
    final paid = payments.fold(Money.zero, (a, p) => a + p.amount);
    if (paid != order.balance) {
      throw DataFailure(
        FailureReason.ruleViolation,
        'payments ${paid.format()} do not add up to the balance '
        '${order.balance.format()}',
      );
    }
    return SalesPlans.createBill(
      ctx: ctx,
      seq: seq,
      servedByName: servedByName,
      delivers: order,
      input: NewBill(
        cart: [
          CartLine(
            productId: customCakeProductId,
            name: productName,
            qty: 1,
            unitPrice: order.price,
          ),
        ],
        payments: [
          if (order.advance.isPositive)
            Payment(mode: PaymentMode.advance, amount: order.advance),
          ...payments,
        ],
        cashTendered: cashTendered,
        customer: order.customer,
      ),
    );
  }

  /// Cancel an OPEN [order]: its status and `cancel` (the reason, who, when
  /// and `refunded`), the ORDER_CANCEL audit entry
  /// `{loc}-{orderId}-X`, and, when the refund is above zero, the summaries'
  /// `advanceRefunded` naming that audit entry (rules #18 (b), #20). The
  /// part of the advance not refunded is kept by the shop.
  ///
  /// Throws `DataFailure(ruleViolation)` when the order is not OPEN, the
  /// reason is empty or longer than `Limits.orderReasonMax`, or the refund is
  /// not 0 up to the advance in whole rupees.
  static PlannedWrite<PreOrder> cancel({
    required PlanContext ctx,
    required PreOrder order,
    required String reason,
    required Money refund,
  }) {
    final loc = ctx.requireLocation();
    ctx.requireDevice();
    if (!order.isOpen) {
      throw DataFailure(
        FailureReason.ruleViolation,
        'order ${order.id} is ${order.status.wire}, not OPEN',
      );
    }
    final r = reason.trim();
    if (r.isEmpty) {
      throw const DataFailure(
        FailureReason.ruleViolation,
        'a reason is needed',
      );
    }
    if (r.length > Limits.orderReasonMax) {
      throw DataFailure(
        FailureReason.ruleViolation,
        'the reason is longer than ${Limits.orderReasonMax} characters',
      );
    }
    final refundProblem = OrderValidator.refundError(refund, order.advance);
    if (refundProblem != null) {
      throw DataFailure(FailureReason.ruleViolation, refundProblem);
    }
    final cancel = OrderCancel(
      reason: r,
      by: ctx.uid,
      at: ctx.now,
      businessDate: ctx.businessDate,
      refunded: refund,
    );
    final orderPath = FirestorePaths.order(loc, order.id);
    final auditPath = FirestorePaths.audit(Ids.auditId(loc, order.cancelId));
    final b = PlanBuilder()
      ..update(orderPath, {
        'status': OrderStatus.cancelled.wire,
        'cancel': cancel.toMap(),
      })
      ..create(
        auditPath,
        auditDoc(
          action: AuditAction.orderCancel,
          entityPath: orderPath,
          ctx: ctx,
          locationId: loc,
          before: {'status': OrderStatus.open.wire},
          after: {
            'status': OrderStatus.cancelled.wire,
            'refunded': refund.paise,
          },
          reason: r,
        ),
      );
    addSummaryWrites(
      b,
      locationId: loc,
      businessDate: cancel.businessDate,
      delta: SummaryDeltas.forOrderCancelled(cancel),
      lastWriteRef: auditPath,
    );
    return PlannedWrite(
      copyOrder(order, status: OrderStatus.cancelled, cancel: cancel),
      b.build(),
    );
  }

  /// [order] with the given fields replaced.
  static PreOrder copyOrder(
    PreOrder order, {
    OrderStatus? status,
    String? billId,
    DateTime? deliveredAt,
    OrderCancel? cancel,
    String? locationId,
  }) => PreOrder(
    id: order.id,
    orderNo: order.orderNo,
    deviceId: order.deviceId,
    seq: order.seq,
    customer: order.customer,
    dueDate: order.dueDate,
    dueTime: order.dueTime,
    description: order.description,
    price: order.price,
    advance: order.advance,
    advanceMode: order.advanceMode,
    status: status ?? order.status,
    billId: billId ?? order.billId,
    deliveredAt: deliveredAt ?? order.deliveredAt,
    cancel: cancel ?? order.cancel,
    servedBy: order.servedBy,
    businessDate: order.businessDate,
    clientCreatedAt: order.clientCreatedAt,
    serverCreatedAt: order.serverCreatedAt,
    createdBy: order.createdBy,
    locationId: locationId ?? order.locationId,
  );
}
