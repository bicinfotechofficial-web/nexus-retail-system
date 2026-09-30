import 'package:nexus_core/nexus_core.dart';

import '../api/failures.dart';
import '../api/sales.dart';
import '../api/sync.dart';
import '../counters/counter_store.dart';
import '../plans/sales_plans.dart';
import 'write_env.dart';

/// [SalesService] on Firestore (03-SYNC §2): bills, same-day cancels and
/// returns, each one batch committed locally without waiting for the
/// server, and each new doc added to the sync ledger.
final class FirestoreSalesService implements SalesService {
  FirestoreSalesService(this._env, {required OfflineState Function() offline})
    : _offline = offline;

  final WriteEnv _env;

  /// The offline guard's state right now (03-SYNC §7).
  final OfflineState Function() _offline;

  @override
  Future<Bill> createBill(NewBill bill) async {
    final loc = _env.requireAtOwnLocation(Permission.billCreate);
    final dev = _env.requireDevice();
    if (_offline() is BillingBlocked) {
      throw const DataFailure(FailureReason.billingBlocked);
    }
    final s = _env.requireSession();
    final ctx = _env.context(s, locationId: loc, at: _env.now());
    return _env.numbered(
      locationId: loc,
      deviceId: dev,
      kind: SeqKind.bill,
      build: (seq) => SalesPlans.createBill(
        ctx: ctx,
        seq: seq,
        input: bill,
        servedByName: s.user.name,
        maxDiscountPct: s.location?.maxDiscountPct,
      ),
      label: billLabel,
    );
  }

  @override
  Future<Bill> cancelBill({
    required String billId,
    required String reason,
  }) async {
    final loc = _env.requireAtOwnLocation(Permission.billCancel);
    _env.requireDevice();
    final bill = await _bill(loc, billId);
    final s = _env.requireSession();
    final planned = SalesPlans.cancelBill(
      ctx: _env.context(s, locationId: loc, at: _env.now()),
      bill: bill,
      reason: reason,
    );
    await _env.write(
      planned.plan,
      label: 'Cancel of ${billLabel(planned.value)}',
    );
    return planned.value;
  }

  @override
  Future<SaleReturn> createReturn({
    required String billId,
    required Map<String, int> qtyByProduct,
    required List<Payment> refunds,
    required String reason,
  }) async {
    final loc = _env.requireAtOwnLocation(Permission.returnCreate);
    final dev = _env.requireDevice();
    final bill = await _bill(loc, billId);
    final s = _env.requireSession();
    final ctx = _env.context(s, locationId: loc, at: _env.now());
    return _env.numbered(
      locationId: loc,
      deviceId: dev,
      kind: SeqKind.returned,
      build: (seq) => SalesPlans.createReturn(
        ctx: ctx,
        seq: seq,
        bill: bill,
        qtyByProduct: qtyByProduct,
        refunds: refunds,
        reason: reason,
      ),
      label: returnLabel,
    );
  }

  Future<Bill> _bill(String loc, String billId) async {
    final bill = await _env.reads.bill(loc, billId);
    if (bill == null) {
      throw DataFailure(FailureReason.notFound, 'bill $billId');
    }
    return bill;
  }

  /// What the sync-health screen shows if the server rejects the bill.
  static String billLabel(Bill b) =>
      'Bill ${b.billNo}, ${b.total.format()}, ${b.businessDate}: '
      '${b.lines.map((l) => '${l.name} × ${l.qty}').join(', ')}; '
      'paid ${b.payments.map((p) => '${p.mode.wire} ${p.amount.format()}').join(' + ')}';

  static String returnLabel(SaleReturn r) =>
      'Return ${r.id} on bill ${r.billNo}, refund ${r.refundTotal.format()}: '
      '${r.lines.map((l) => '${l.name} × ${l.qty}').join(', ')}';
}
