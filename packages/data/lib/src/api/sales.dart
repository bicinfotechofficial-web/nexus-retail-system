import 'package:nexus_core/nexus_core.dart';

/// Everything the payment screen hands over when the Store Manager taps Save.
final class NewBill {
  const NewBill({
    required this.cart,
    required this.payments,
    this.discount,
    this.cashTendered,
  });

  final List<CartLine> cart;
  final DiscountInput? discount;
  final List<Payment> payments;
  final Money? cashTendered;
}

/// Bills and returns. All writes use the signed-in user's location and this
/// device's code, and are one atomic batch each (03-SYNC §2).
///
/// Writes complete when the batch is committed to the local cache; they do
/// not wait for the server, so they work offline. `SyncService` confirms
/// them later.
abstract interface class SalesService {
  /// Computes totals with `BillCalculator`, validates the payments, allocates
  /// the next bill number (persisted before the batch is built), and writes
  /// the bill, stock, SALE movement, summaries and `lastBillSeq`.
  ///
  /// Throws the calculator's exceptions, or `DataFailure` with
  /// billingBlocked, deviceNotRegistered or notPermitted. Call it once per
  /// Save tap; a second call is a second bill.
  Future<Bill> createBill(NewBill bill);

  /// Same-day cancellation with a reason (D-009). Throws
  /// `DataFailure(ruleViolation)` when `cancelBlocker` says no.
  Future<Bill> cancelBill({required String billId, required String reason});

  /// A return against [billId], computed with `ReturnCalculator`. [refunds]
  /// must add up to the computed refund total.
  Future<SaleReturn> createReturn({
    required String billId,
    required Map<String, int> qtyByProduct,
    required List<Payment> refunds,
    required String reason,
  });
}

abstract interface class SalesRepository {
  /// Bills of one business day at a location, newest first.
  Stream<List<Bill>> watchBills(String locationId, String businessDate);

  Future<Bill?> getBill(String locationId, String billId);

  /// Finds a bill by its printed number, e.g. `PTB-D01-000123`.
  Future<Bill?> findByBillNo(String billNo);

  Stream<List<SaleReturn>> watchReturns(String locationId, String businessDate);

  Future<List<SaleReturn>> returnsForBill(String locationId, String billId);
}
