/// A pure-Dart model of what the batches in 03-SYNC §2 write, for the
/// reconciliation property (QA-5). It keeps two things side by side:
///
/// * the **documents**: bills (with their later `status`, `cancel` and
///   `returnedQty` updates) and returns, stored as maps and read back with
///   `fromMap`, the way Firestore would hold them;
/// * the **summaries**: every `SummaryDeltas` result applied to the daily and
///   monthly doc of the operation's business date, both with `Summary.+`
///   and as `FieldValue.increment` field paths (`SummaryDeltas.increments`)
///   merged into a flat map, the way Firestore would apply them.
///
/// The oracle in the test recomputes each summary from the documents alone.
///
/// Every batch passes through [ShopSim.serverAccepts], a model of the
/// update rules in 04-PERMISSIONS #5–6 as revised for D-029 and D-030. The
/// simulation also plays conflicting offline writes: a device builds a
/// cancel or a return from a stale copy of a bill while another device has
/// already synced a return or a cancel of it. The rules model decides which
/// one lands (first to sync wins); a rejected batch writes nothing and is
/// counted as a sync error.
///
/// Once the backend's `WritePlan` builders land (BE-10), this model is
/// replaced by applying the plans themselves to an in-memory store.
library;

import 'dart:math';

import 'package:nexus_core/nexus_core.dart';

/// A product for sale in the simulation. IDs are safe map keys (`Ids`).
typedef SimProduct = ({String id, String name, int price});

/// Prices include odd paise so proration and round-off both get exercised.
const List<SimProduct> simCatalog = [
  (id: 'P_BF1KG', name: 'Black Forest 1 kg', price: 85000),
  (id: 'P_BF500', name: 'Black Forest 500 g', price: 45000),
  (id: 'P_RVSLICE', name: 'Red Velvet slice', price: 12050),
  (id: 'P_PUFF', name: 'Veg puff', price: 1875),
  (id: 'P_BROWNIE', name: 'Brownie', price: 9999),
  (id: 'P_CUPCAKE', name: 'Cupcake', price: 3333),
  (id: 'P_CANDLE', name: 'Candle (free)', price: 0),
];

/// [simCatalog] plus enough extra items to build bills at and past the
/// 20-line limit (D-030).
final List<SimProduct> simWideCatalog = [
  ...simCatalog,
  for (var i = 1; i <= 20; i++)
    (
      id: 'P_X${i.toString().padLeft(2, '0')}',
      name: 'Pastry $i',
      price: 1111 * i + 7,
    ),
];

/// Counts of the edge cases one run produced, so the test can prove the
/// fixed seed actually reaches them.
final class Coverage {
  int bills = 0;
  int zeroTotalBills = 0;
  int pctDiscounts = 0;
  int flatDiscounts = 0;
  int capRejections = 0;
  int splitPayments = 0;
  int cancels = 0;
  int returns = 0;
  int fullReturns = 0;
  int partialReturns = 0;
  int zeroRefundReturns = 0;
  int crossDayReturns = 0;
  int crossMonthReturns = 0;
  int splitRefunds = 0;
  int deniedNextDayCancels = 0;
  int deniedCancelAfterReturn = 0;
  int deniedOverReturns = 0;
  int deniedReturnOnCancelled = 0;

  /// Bills with more than 10 lines, and bills at exactly the 20-line cap.
  int wideBills = 0;
  int maxLineBills = 0;

  /// 21-line carts refused by `BillCalculator` (D-030).
  int deniedTooManyLines = 0;

  /// Stale offline cancels rejected because a return synced first (D-029).
  int conflictCancelLost = 0;

  /// Stale offline returns rejected because a cancel synced first (D-029).
  int conflictReturnLost = 0;

  /// Stale offline returns rejected by `returnedQty <= soldQty` (D-029).
  int conflictOverReturnLost = 0;

  void add(Coverage o) {
    bills += o.bills;
    zeroTotalBills += o.zeroTotalBills;
    pctDiscounts += o.pctDiscounts;
    flatDiscounts += o.flatDiscounts;
    capRejections += o.capRejections;
    splitPayments += o.splitPayments;
    cancels += o.cancels;
    returns += o.returns;
    fullReturns += o.fullReturns;
    partialReturns += o.partialReturns;
    zeroRefundReturns += o.zeroRefundReturns;
    crossDayReturns += o.crossDayReturns;
    crossMonthReturns += o.crossMonthReturns;
    splitRefunds += o.splitRefunds;
    deniedNextDayCancels += o.deniedNextDayCancels;
    deniedCancelAfterReturn += o.deniedCancelAfterReturn;
    deniedOverReturns += o.deniedOverReturns;
    deniedReturnOnCancelled += o.deniedReturnOnCancelled;
    wideBills += o.wideBills;
    maxLineBills += o.maxLineBills;
    deniedTooManyLines += o.deniedTooManyLines;
    conflictCancelLost += o.conflictCancelLost;
    conflictReturnLost += o.conflictReturnLost;
    conflictOverReturnLost += o.conflictOverReturnLost;
  }
}

/// One shop network: several locations, each with its own devices,
/// counters, documents and summary docs.
final class ShopSim {
  ShopSim({
    required this.random,
    required this.locations,
    required this.devices,
    required this.discountCap,
  });

  final Random random;
  final List<String> locations;
  final List<String> devices;

  /// `maxDiscountPct` per location; a missing key means no cap (D-011).
  final Map<String, int> discountCap;

  final Coverage coverage = Coverage();

  /// Paths of batches the rules model rejected (they became sync errors).
  final List<String> syncErrors = [];

  /// Bill doc path → stored map. Insertion order is creation order.
  final Map<String, Map<String, Object?>> _billDocs = {};

  /// Return doc path → stored map.
  final Map<String, Map<String, Object?>> _returnDocs = {};

  /// Summary doc path → summary built with `Summary.+`.
  final Map<String, Summary> summaries = {};

  /// Summary doc path → field path → value, built from
  /// `SummaryDeltas.increments`, as Firestore would apply increments.
  final Map<String, Map<String, int>> wireSummaries = {};

  final Map<String, int> _billSeq = {};
  final Map<String, int> _returnSeq = {};

  /// The stored bill maps at [loc], as Firestore holds them (including
  /// `soldQty`, which `Bill.fromMap` doesn't read back).
  Map<String, Map<String, Object?>> billDocsAt(String loc) => {
    for (final e in _billDocs.entries)
      if (e.key.startsWith('${FirestorePaths.bills(loc)}/'))
        e.key.split('/').last: e.value,
  };

  List<Bill> billsAt(String loc) => [
    for (final e in _billDocs.entries)
      if (e.key.startsWith('${FirestorePaths.bills(loc)}/'))
        Bill.fromMap(e.key.split('/').last, e.value),
  ];

  List<SaleReturn> returnsAt(String loc) => [
    for (final e in _returnDocs.entries)
      if (e.key.startsWith('${FirestorePaths.returns(loc)}/'))
        SaleReturn.fromMap(e.key.split('/').last, e.value),
  ];

  Bill _bill(String loc, String billId) =>
      Bill.fromMap(billId, _billDocs[FirestorePaths.bill(loc, billId)]!);

  /// Runs a random mix of bills, cancellations and returns at every
  /// location for [businessDate].
  void simulateDay(String businessDate) {
    for (final loc in locations) {
      final ops = 4 + random.nextInt(12);
      for (var i = 0; i < ops; i++) {
        final roll = random.nextInt(100);
        final at = BusinessDate.startOf(
          businessDate,
        ).add(Duration(hours: 9, minutes: i * 7));
        if (roll < 55) {
          _createBill(loc, businessDate, at);
        } else if (roll < 67) {
          _cancelOne(loc, businessDate, at);
        } else if (roll < 92) {
          _returnOne(loc, businessDate, at);
        } else {
          _conflictOne(loc, businessDate, at);
        }
      }
    }
  }

  void _createBill(String loc, String today, DateTime at) {
    // Now and then a wide bill, up to the 20-line cap (D-030).
    final wide = random.nextInt(100) < 6;
    final picked = [...(wide ? simWideCatalog : simCatalog)]..shuffle(random);
    final n = wide
        ? (random.nextInt(3) == 0
              ? Limits.maxBillLines
              : 11 + random.nextInt(Limits.maxBillLines - 11))
        : 1 + random.nextInt(4);
    CartLine line(SimProduct p) => CartLine(
      productId: p.id,
      name: p.name,
      qty: 1 + random.nextInt(6),
      unitPrice: Money(p.price),
    );
    final cart = [for (final p in picked.take(n)) line(p)];
    if (n == Limits.maxBillLines) {
      // One more line is refused before anything is written.
      try {
        BillCalculator.compute([...cart, line(picked[n])]);
        throw StateError('a ${n + 1}-line cart was accepted');
      } on BillValidationException catch (e) {
        if (e.error != BillError.tooManyLines) rethrow;
        coverage.deniedTooManyLines++;
      }
    }
    final subtotal = cart.fold<int>(0, (a, c) => a + c.unitPrice.paise * c.qty);

    DiscountInput? discount;
    final d = random.nextInt(100);
    if (d < 25) {
      // Includes 100% now and then: a zero-total bill.
      discount = DiscountInput.percent(
        random.nextInt(10) == 0 ? 100 : 1 + random.nextInt(40),
      );
    } else if (d < 50 && subtotal > 0) {
      discount = DiscountInput.flat(Money(random.nextInt(subtotal ~/ 3 + 1)));
    }

    BillTotals totals;
    try {
      totals = BillCalculator.compute(
        cart,
        discount: discount,
        maxDiscountPct: discountCap[loc],
      );
    } on BillValidationException catch (e) {
      if (e.error != BillError.discountOverCap) rethrow;
      // The payment screen refuses it; the Store Manager bills without.
      coverage.capRejections++;
      totals = BillCalculator.compute(cart, maxDiscountPct: discountCap[loc]);
    }
    switch (totals.discount?.type) {
      case DiscountType.pct:
        coverage.pctDiscounts++;
      case DiscountType.flat:
        coverage.flatDiscounts++;
      case null:
        break;
    }

    final payments = _split(totals.total, BillCalculator.maxPayments);
    if (payments.length > 1) coverage.splitPayments++;
    final cash = payments
        .where((p) => p.mode == PaymentMode.cash)
        .fold(Money.zero, (a, p) => a + p.amount);
    final tendered = cash.isPositive && random.nextBool()
        ? cash + Money(random.nextInt(50000))
        : null;
    final check = BillCalculator.checkPayments(
      totals.total,
      payments,
      cashTendered: tendered,
    );
    if (!check.isValid) {
      throw StateError('generated an invalid payment split: ${check.errors}');
    }

    final device = devices[random.nextInt(devices.length)];
    final key = '$loc/$device';
    final seq = (_billSeq[key] ?? 0) + 1;
    _billSeq[key] = seq;
    final id = Ids.billId(device, seq);
    final bill = Bill(
      id: id,
      billNo: Ids.billNo(loc, id),
      deviceId: device,
      seq: seq,
      lines: totals.lines,
      subtotal: totals.subtotal,
      discount: totals.discount,
      taxableValue: totals.taxableValue,
      taxLines: totals.taxLines,
      roundOff: totals.roundOff,
      total: totals.total,
      payments: payments,
      cashTendered: tendered,
      status: BillStatus.completed,
      servedBy: ServedBy(uid: 'uid-sm-$loc', name: 'Store Manager $loc'),
      businessDate: today,
      clientCreatedAt: at,
      createdBy: 'uid-sm-$loc',
    );
    final path = FirestorePaths.bill(loc, id);
    final doc = bill.toMap();
    if (!serverAcceptsBillCreate(loc, id, doc)) {
      throw StateError('the rules model rejected bill $path');
    }
    _billDocs[path] = doc;
    coverage.bills++;
    if (bill.lines.length > 10) coverage.wideBills++;
    if (bill.lines.length == Limits.maxBillLines) coverage.maxLineBills++;
    if (bill.total.isZero) coverage.zeroTotalBills++;
    _apply(loc, today, SummaryDeltas.forBill(bill));
  }

  void _cancelOne(String loc, String today, DateTime at) {
    final all = billsAt(loc);
    if (all.isEmpty) return;

    // Probe the blockers the POS and the rules must honour (D-009, D-025).
    final older = all.where(
      (b) => b.status == BillStatus.completed && b.businessDate != today,
    );
    if (older.isNotEmpty &&
        cancelBlocker(older.first, today) == CancelBlocker.differentDay) {
      coverage.deniedNextDayCancels++;
    }
    final returned = all.where(
      (b) =>
          b.status == BillStatus.completed &&
          b.businessDate == today &&
          b.returnedQty.values.any((q) => q > 0),
    );
    if (returned.isNotEmpty &&
        cancelBlocker(returned.first, today) == CancelBlocker.hasReturns) {
      coverage.deniedCancelAfterReturn++;
    }

    final open = all.where((b) => cancelBlocker(b, today) == null).toList();
    if (open.isEmpty) return;
    final bill = open[random.nextInt(open.length)];
    if (!_syncCancel(loc, bill, today, at)) {
      throw StateError('the rules model rejected a valid cancel of ${bill.id}');
    }
  }

  /// A cancel batch built by a device from [seen] (possibly stale), applied
  /// only if the rules model accepts it against the server's current doc.
  bool _syncCancel(String loc, Bill seen, String today, DateTime at) {
    final path = FirestorePaths.bill(loc, seen.id);
    // The update rule #5(a) allows: status and cancel only.
    final after = {
      ..._billDocs[path]!,
      'status': BillStatus.cancelled.wire,
      'cancel': BillCancel(
        reason: 'Customer changed order',
        by: 'uid-sm-$loc',
        at: at,
        businessDate: today,
      ).toMap(),
    };
    if (!serverAcceptsCancel(_billDocs[path]!, after)) {
      syncErrors.add(
        '${FirestorePaths.movements(loc)}/${Ids.cancelId(seen.id)}',
      );
      return false;
    }
    _billDocs[path] = after;
    coverage.cancels++;
    // The summary delta comes from the device's copy; a cancel never
    // depends on returnedQty, which must be empty for it to land.
    _apply(loc, today, SummaryDeltas.forCancel(seen));
    return true;
  }

  void _returnOne(String loc, String today, DateTime at) {
    final all = billsAt(loc);
    final cancelled = all.where((b) => b.status == BillStatus.cancelled);
    if (cancelled.isNotEmpty) {
      try {
        ReturnCalculator.compute(cancelled.first, {
          cancelled.first.lines.first.productId: 1,
        });
      } on ReturnValidationException catch (e) {
        if (e.error == ReturnError.billNotCompleted) {
          coverage.deniedReturnOnCancelled++;
        }
      }
    }

    final candidates = [
      for (final b in all)
        if (b.status == BillStatus.completed &&
            b.businessDate.compareTo(today) <= 0 &&
            ReturnCalculator.returnable(b).values.any((q) => q > 0))
          b,
    ];
    if (candidates.isEmpty) return;
    final bill = candidates[random.nextInt(candidates.length)];
    final returnable = ReturnCalculator.returnable(bill);

    // Over-return must be refused before anything is written.
    final probe = returnable.entries.firstWhere((e) => e.value > 0);
    try {
      ReturnCalculator.compute(bill, {probe.key: probe.value + 1});
      throw StateError('over-return was accepted for ${bill.id}');
    } on ReturnValidationException catch (e) {
      if (e.error == ReturnError.exceedsReturnable) {
        coverage.deniedOverReturns++;
      }
    }

    final full = random.nextInt(4) == 0;
    var qty = <String, int>{
      for (final e in returnable.entries)
        if (e.value > 0)
          e.key: full
              ? e.value
              : (random.nextBool() ? random.nextInt(e.value + 1) : 0),
    };
    if (qty.values.every((q) => q == 0)) qty = {probe.key: 1};

    if (!_syncReturn(loc, bill, qty, today, at)) {
      throw StateError('the rules model rejected a valid return of ${bill.id}');
    }
  }

  /// A return batch built by a device from [seen] (possibly stale), applied
  /// only if the rules model accepts it against the server's current doc.
  /// `returnedQty` is written with increments (03-SYNC §2), so a stale
  /// device adds to what the server holds rather than overwriting it.
  bool _syncReturn(
    String loc,
    Bill seen,
    Map<String, int> qty,
    String today,
    DateTime at,
  ) {
    final totals = ReturnCalculator.compute(seen, qty);
    final refunds = _split(totals.refundTotal, 3);
    if (ReturnCalculator.checkRefunds(totals.refundTotal, refunds).isNotEmpty) {
      throw StateError('generated an invalid refund split');
    }

    final device = devices[random.nextInt(devices.length)];
    final key = '$loc/$device';
    final seq = (_returnSeq[key] ?? 0) + 1;
    _returnSeq[key] = seq;
    final ret = SaleReturn(
      id: Ids.returnId(device, seq),
      billId: seen.id,
      billNo: seen.billNo,
      lines: totals.lines,
      refundTotal: totals.refundTotal,
      refunds: refunds,
      reason: 'Damaged in transit',
      businessDate: today,
      createdBy: 'uid-sm-$loc',
      deviceId: device,
      clientCreatedAt: at,
    );
    final retPath = FirestorePaths.saleReturn(loc, ret.id);
    if (_returnDocs.containsKey(retPath)) {
      throw StateError('duplicate return id $retPath');
    }

    // The update rule #5(b) allows: returnedQty increments and lastReturnId.
    final billPath = FirestorePaths.bill(loc, seen.id);
    final before = _billDocs[billPath]!;
    final returnedQty = {
      ...(before['returnedQty']! as Map).cast<String, int>(),
    };
    for (final l in ret.lines) {
      returnedQty[l.productId] = (returnedQty[l.productId] ?? 0) + l.qty;
    }
    final after = {
      ...before,
      'returnedQty': returnedQty,
      'lastReturnId': ret.id,
    };
    if (!serverAcceptsReturn(before, after, newReturn: true)) {
      syncErrors.add(retPath);
      return false;
    }
    _returnDocs[retPath] = ret.toMap();
    _billDocs[billPath] = after;

    coverage.returns++;
    final nowFull = ReturnCalculator.returnable(
      _bill(loc, seen.id),
    ).values.every((q) => q == 0);
    if (nowFull) {
      coverage.fullReturns++;
    } else {
      coverage.partialReturns++;
    }
    if (ret.refundTotal.isZero) coverage.zeroRefundReturns++;
    if (refunds.length > 1) coverage.splitRefunds++;
    if (seen.businessDate != today) coverage.crossDayReturns++;
    if (BusinessDate.monthOf(seen.businessDate) !=
        BusinessDate.monthOf(today)) {
      coverage.crossMonthReturns++;
    }
    // D-012: the return counts on the day it is processed.
    _apply(loc, today, SummaryDeltas.forReturn(ret));
    return true;
  }

  /// Two devices act on the same bill while offline; the first batch to
  /// sync lands and the second is rejected by the rules (D-029). The second
  /// device built its batch from the bill as it was before the first one.
  ///
  /// Only conflicts the rules can decide are played here. Two stale returns
  /// that both stay within `soldQty` are both accepted and can over-refund
  /// by up to ₹1 each; that case is QA-024 (see concurrent_returns_test).
  void _conflictOne(String loc, String today, DateTime at) {
    final open = billsAt(
      loc,
    ).where((b) => cancelBlocker(b, today) == null && b.total.isPositive);
    if (open.isEmpty) return;
    final stale = open.elementAt(random.nextInt(open.length));
    final line = stale.lines[random.nextInt(stale.lines.length)];
    switch (random.nextInt(3)) {
      case 0:
        // A returns one unit and syncs; B's stale cancel is rejected.
        _syncReturn(loc, stale, {line.productId: 1}, today, at);
        if (!_syncCancel(loc, stale, today, at)) coverage.conflictCancelLost++;
      case 1:
        // A cancels and syncs; B's stale return is rejected.
        _syncCancel(loc, stale, today, at);
        if (!_syncReturn(loc, stale, {line.productId: 1}, today, at)) {
          coverage.conflictReturnLost++;
        }
      default:
        // A returns the whole line and syncs; B's stale return of any of
        // it would take returnedQty over soldQty and is rejected.
        _syncReturn(loc, stale, {line.productId: line.qty}, today, at);
        final more = 1 + random.nextInt(line.qty);
        if (!_syncReturn(loc, stale, {line.productId: more}, today, at)) {
          coverage.conflictOverReturnLost++;
        }
    }
  }

  // -------------------------------------------------------------------------
  // The rules model: 04-PERMISSIONS #5 (a) and (b) and #6, for the fields
  // this simulation writes.
  // -------------------------------------------------------------------------

  /// Rule #6 on the fields that matter here: at most 20 lines, one
  /// `soldQty` key per line with that line's qty, empty `returnedQty`,
  /// COMPLETED, and `billNo == loc-billId`.
  static bool serverAcceptsBillCreate(
    String loc,
    String billId,
    Map<String, Object?> doc,
  ) {
    final lines = (doc['lines']! as List).cast<Map<String, Object?>>();
    final sold = (doc['soldQty']! as Map).cast<String, int>();
    if (lines.length > Limits.maxBillLines) return false;
    if ((doc['payments']! as List).length > Limits.maxPayments) return false;
    if (sold.length != lines.length) return false;
    for (final l in lines) {
      if (sold[l['productId']] != l['qty']) return false;
    }
    return (doc['returnedQty']! as Map).isEmpty &&
        doc['status'] == BillStatus.completed.wire &&
        doc['billNo'] == Ids.billNo(loc, billId);
  }

  /// Rule #5(a): COMPLETED → CANCELLED, no returns yet (D-025, D-029), and
  /// the cancel's business date equals the bill's.
  static bool serverAcceptsCancel(
    Map<String, Object?> before,
    Map<String, Object?> after,
  ) {
    final cancel = after['cancel']! as Map;
    return before['status'] == BillStatus.completed.wire &&
        (before['returnedQty']! as Map).isEmpty &&
        after['status'] == BillStatus.cancelled.wire &&
        cancel['businessDate'] == before['businessDate'] &&
        _onlyChanged(before, after, {'status', 'cancel'});
  }

  /// Rule #5(b): the bill is COMPLETED, `lastReturnId` names a new return,
  /// and every `returnedQty` value only grows and stays within `soldQty`.
  static bool serverAcceptsReturn(
    Map<String, Object?> before,
    Map<String, Object?> after, {
    required bool newReturn,
  }) {
    if (before['status'] != BillStatus.completed.wire || !newReturn) {
      return false;
    }
    if (after['lastReturnId'] == before['lastReturnId']) return false;
    final sold = (before['soldQty']! as Map).cast<String, int>();
    final was = (before['returnedQty']! as Map).cast<String, int>();
    final now = (after['returnedQty']! as Map).cast<String, int>();
    for (final e in now.entries) {
      final cap = sold[e.key];
      if (cap == null || e.value > cap || e.value < (was[e.key] ?? 0)) {
        return false;
      }
    }
    return _onlyChanged(before, after, {'returnedQty', 'lastReturnId'});
  }

  static bool _onlyChanged(
    Map<String, Object?> before,
    Map<String, Object?> after,
    Set<String> allowed,
  ) {
    for (final k in {...before.keys, ...after.keys}) {
      if (allowed.contains(k)) continue;
      if (before[k].toString() != after[k].toString()) return false;
    }
    return true;
  }

  /// Splits a whole-rupee [total] into 1..[maxParts] positive amounts with
  /// random modes. Zero gives no entries.
  List<Payment> _split(Money total, int maxParts) {
    if (total.isZero) return const [];
    final rupees = total.paise ~/ 100;
    final parts = min(1 + random.nextInt(maxParts), rupees);
    final cuts = <int>{};
    while (cuts.length < parts - 1) {
      cuts.add(1 + random.nextInt(rupees - 1));
    }
    final points = [0, ...cuts.toList()..sort(), rupees];
    return [
      for (var i = 0; i < parts; i++)
        Payment(
          mode: PaymentMode.values[random.nextInt(PaymentMode.values.length)],
          amount: Money.rupees(points[i + 1] - points[i]),
          ref: random.nextInt(3) == 0 ? 'REF$i' : null,
        ),
    ];
  }

  /// One summary delta lands on the daily and the monthly doc of the
  /// operation's business date, in the same batch (D-014).
  void _apply(String loc, String businessDate, Summary delta) {
    for (final path in [
      FirestorePaths.dailySummary(loc, businessDate),
      FirestorePaths.monthlySummary(loc, BusinessDate.monthOf(businessDate)),
    ]) {
      summaries[path] = (summaries[path] ?? const Summary()) + delta;
      final wire = wireSummaries.putIfAbsent(path, () => {});
      SummaryDeltas.increments(delta).forEach((field, by) {
        wire[field] = (wire[field] ?? 0) + by;
      });
    }
  }

  /// The summary doc at [path] as Firestore would return it after all the
  /// field-path increments, read back with `Summary.fromMap`.
  Summary wireSummary(String path) {
    final flat = wireSummaries[path];
    if (flat == null) return const Summary();
    final root = <String, Object?>{};
    for (final e in flat.entries) {
      final parts = e.key.split('.');
      var node = root;
      for (final p in parts.take(parts.length - 1)) {
        node =
            node.putIfAbsent(p, () => <String, Object?>{})!
                as Map<String, Object?>;
      }
      node[parts.last] = ((node[parts.last] as int?) ?? 0) + e.value;
    }
    return Summary.fromMap(path.split('/').last, root);
  }
}
