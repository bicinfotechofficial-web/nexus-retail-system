import 'package:nexus_core/nexus_core.dart';

import '../api/failures.dart';
import '../api/orders.dart';
import '../api/sync.dart';
import '../counters/counter_store.dart';
import '../plans/order_plans.dart';
import 'firestore_sales_service.dart';
import 'write_env.dart';

/// [OrderService] on Firestore (D-043): taking, delivering and cancelling
/// pre-orders, each one atomic batch committed locally without waiting for
/// the server, so all three work offline, like a bill. Order and bill
/// numbers come from the per-device counters, persisted before the batch is
/// built (03-SYNC §3), so a retry reuses the same IDs and is idempotent.
final class FirestoreOrderService implements OrderService {
  FirestoreOrderService(this._env, {required OfflineState Function() offline})
    : _offline = offline;

  final WriteEnv _env;

  /// The offline guard's state right now (03-SYNC §7).
  final OfflineState Function() _offline;

  @override
  Future<PreOrder> create(NewOrder order) async {
    final loc = _env.requireAtOwnLocation(Permission.orderManage);
    final dev = _env.requireDevice();
    final s = _env.requireSession();
    final ctx = _env.context(s, locationId: loc, at: _env.now());
    return _env.numbered(
      locationId: loc,
      deviceId: dev,
      kind: SeqKind.order,
      build: (seq) => OrderPlans.create(
        ctx: ctx,
        seq: seq,
        input: order,
        servedByName: s.user.name,
      ),
      label: orderLabel,
    );
  }

  @override
  Future<Bill> deliver({
    required String orderId,
    required List<Payment> payments,
    Money? cashTendered,
  }) async {
    final loc = _env.requireAtOwnLocation(Permission.orderManage);
    _env.requireAtOwnLocation(Permission.billCreate);
    final dev = _env.requireDevice();
    // A delivery is a bill, so it stops where billing stops (03-SYNC §7).
    if (_offline() is BillingBlocked) {
      throw const DataFailure(FailureReason.billingBlocked);
    }
    final order = await _order(loc, orderId);
    final s = _env.requireSession();
    final ctx = _env.context(s, locationId: loc, at: _env.now());
    final name = (await _env.reads.product(
      OrderPlans.customCakeProductId,
    ))?.name;
    return _env.numbered(
      locationId: loc,
      deviceId: dev,
      kind: SeqKind.bill,
      build: (seq) => OrderPlans.deliver(
        ctx: ctx,
        seq: seq,
        order: order,
        payments: payments,
        cashTendered: cashTendered,
        servedByName: s.user.name,
        productName: name ?? OrderPlans.customCakeName,
      ),
      label: (bill) =>
          'Delivery of order ${order.orderNo}: '
          '${FirestoreSalesService.billLabel(bill)}',
    );
  }

  @override
  Future<PreOrder> cancel({
    required String orderId,
    required String reason,
    required Money refund,
  }) async {
    final loc = _env.requireAtOwnLocation(Permission.orderManage);
    _env.requireDevice();
    final order = await _order(loc, orderId);
    final s = _env.requireSession();
    final planned = OrderPlans.cancel(
      ctx: _env.context(s, locationId: loc, at: _env.now()),
      order: order,
      reason: reason,
      refund: refund,
    );
    // The audit entry is the only new doc, so the ledger follows that.
    await _env.write(
      planned.plan,
      label: 'Cancel of order ${order.orderNo}, refund ${refund.format()}',
      includeAudit: true,
    );
    return planned.value;
  }

  Future<PreOrder> _order(String loc, String orderId) async {
    final order = await _env.reads.order(loc, orderId);
    if (order == null) {
      throw DataFailure(FailureReason.notFound, 'order $orderId');
    }
    return order;
  }

  /// What the sync-health screen shows if the server rejects the order.
  static String orderLabel(PreOrder o) =>
      'Order ${o.orderNo}, ${o.price.format()}, advance '
      '${o.advance.format()}, due ${o.dueDate}: ${o.description}';
}
