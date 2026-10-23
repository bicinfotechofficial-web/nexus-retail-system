import 'package:nexus_core/nexus_core.dart';

/// What the new-order form hands over (D-043). Build the customer with
/// `BillCustomer(...)` after checking with `CustomerValidator`, and check the
/// rest with `OrderValidator`.
final class NewOrder {
  const NewOrder({
    required this.customer,
    required this.dueDate,
    required this.description,
    required this.price,
    required this.advance,
    this.dueTime,
    this.advanceMode,
  });

  final BillCustomer customer;

  /// `YYYY-MM-DD`, today or later.
  final String dueDate;

  /// `HH:mm` or null.
  final String? dueTime;
  final String description;
  final Money price;

  /// 0 up to [price]. Whole rupees.
  final Money advance;

  /// Null exactly when [advance] is zero; never `PaymentMode.advance`.
  final PaymentMode? advanceMode;
}

/// Taking, delivering and cancelling pre-orders (D-043). Each is one atomic
/// batch and works offline, like a bill.
abstract interface class OrderService {
  /// Allocates the next order number (persisted before the batch is built)
  /// and writes the order, `lastOrderSeq`, and the summaries'
  /// `advanceReceived` when the advance is above zero.
  ///
  /// Throws a
  /// `DataFailure(ruleViolation)` with the validator's message, `notPermitted`
  /// without `order.manage`, or `deviceNotRegistered`.
  Future<PreOrder> create(NewOrder order);

  /// Delivers an OPEN order as one ordinary bill in one batch: a single line
  /// for the seeded `CUSTOM-CAKE` product at the order's price, the order's
  /// customer, `orderId` on the bill, and these payments: an `ADVANCE`
  /// payment for the order's advance (added here, never passed in) plus
  /// [payments] for the balance. [payments] must add up to the balance and
  /// use only `PaymentMode.selectable` modes; it is empty when the balance is
  /// zero. Marks the order DELIVERED with the bill's ID.
  ///
  /// Throws `DataFailure(notFound)` for an unknown order and
  /// `ruleViolation` when it is not OPEN or the payments don't add up.
  Future<Bill> deliver({
    required String orderId,
    required List<Payment> payments,
    Money? cashTendered,
  });

  /// Cancels an OPEN order with a [reason] (1–`Limits.orderReasonMax` chars)
  /// and a [refund] of 0 up to the advance in whole rupees; the rest of the
  /// advance is kept. Writes the audit entry and `advanceRefunded` when the
  /// refund is above zero.
  Future<PreOrder> cancel({
    required String orderId,
    required String reason,
    required Money refund,
  });
}

abstract interface class OrderRepository {
  /// Open orders at [locationId], soonest due first (by `dueDate`, then
  /// `dueTime`, with orders that have no time last). Served from the local
  /// cache when offline.
  Stream<List<PreOrder>> watchOpen(String locationId);

  /// The most recent delivered and cancelled orders at [locationId], newest
  /// first, at most [limit].
  Stream<List<PreOrder>> watchClosed(String locationId, {int limit = 50});

  Future<PreOrder?> getOrder(String locationId, String orderId);

  /// Orders across every location for the Admin (`report.all`), soonest due
  /// first. [status] filters when given; [dueFrom] and [dueTo] (business
  /// dates, inclusive) bound the due date. At most [limit].
  Stream<List<PreOrder>> watchAllLocations({
    OrderStatus? status,
    String? dueFrom,
    String? dueTo,
    int limit = 300,
  });
}
