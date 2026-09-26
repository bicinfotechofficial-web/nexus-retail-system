/// QA-5: the summary equals the sum of the documents (acceptance #5,
/// D-012, D-014, D-024), for every day and month at every location and for
/// all locations combined.
///
/// A fixed-seed property test over random bills (up to the 20-line cap,
/// D-030), same-day cancellations, partial or full returns, and conflicting
/// offline cancels and returns resolved first-to-sync-wins (D-029), across
/// several days, a month boundary and two locations. The summaries are built only from `SummaryDeltas` (as the
/// batches write them); the oracle below recomputes every figure from the
/// bill and return documents alone, using the definitions in
/// 02-DATA-MODEL and 00-DECISIONS.
///
/// Scope today: `nexus_core` only. When the backend's `WritePlan` builders
/// land (BE-10), the same oracle runs against the plans (see PLAN.md, P-01).
library;

import 'dart:math';

import 'package:nexus_core/nexus_core.dart';
import 'package:test/test.dart';

import 'support/shop_sim.dart';

/// Fixed so a failure always reproduces. Change it only on purpose.
const int masterSeed = 20260926;
const int runs = 40;
const List<String> locations = ['PTB', 'MNJ'];
const List<String> devices = ['D01', 'D02'];

/// Seven business days that cross a month boundary, so returns processed in
/// October against September bills are covered (D-012).
final List<String> days = [
  for (var i = 0; i < 7; i++) BusinessDate.addDays('2026-09-27', i),
];
final List<String> months = {
  for (final d in days) BusinessDate.monthOf(d),
}.toList();

void main() {
  final sims = <ShopSim>[];
  final total = Coverage();
  final master = Random(masterSeed);
  for (var r = 0; r < runs; r++) {
    final sim = ShopSim(
      random: Random(master.nextInt(1 << 31)),
      locations: locations,
      devices: devices,
      // MNJ has a 20% cap; PTB has none (D-011).
      discountCap: const {'MNJ': 20},
    );
    days.forEach(sim.simulateDay);
    sims.add(sim);
    total.add(sim.coverage);
  }

  test('the fixed seed reaches every edge case', () {
    final c = total;
    final reached = {
      'bills': c.bills,
      'zero-total bills': c.zeroTotalBills,
      'percent discounts': c.pctDiscounts,
      'flat discounts': c.flatDiscounts,
      'cap rejections': c.capRejections,
      'split payments': c.splitPayments,
      'cancellations': c.cancels,
      'returns': c.returns,
      'full returns': c.fullReturns,
      'partial returns': c.partialReturns,
      'zero-refund returns': c.zeroRefundReturns,
      'cross-day returns': c.crossDayReturns,
      'cross-month returns': c.crossMonthReturns,
      'split refunds': c.splitRefunds,
      'next-day cancel refused': c.deniedNextDayCancels,
      'cancel after return refused': c.deniedCancelAfterReturn,
      'over-return refused': c.deniedOverReturns,
      'return on cancelled bill refused': c.deniedReturnOnCancelled,
      'bills over 10 lines': c.wideBills,
      'bills at the 20-line cap': c.maxLineBills,
      '21-line cart refused': c.deniedTooManyLines,
      'stale cancel lost to a return': c.conflictCancelLost,
      'stale return lost to a cancel': c.conflictReturnLost,
      'stale return over soldQty lost': c.conflictOverReturnLost,
    };
    for (final e in reached.entries) {
      expect(e.value, greaterThanOrEqualTo(5), reason: e.key);
    }
  });

  for (var r = 0; r < runs; r++) {
    group('run $r', () {
      final sim = sims[r];

      test('every bill and return document is well-formed', () {
        for (final loc in locations) {
          for (final b in sim.billsAt(loc)) {
            checkBill(b);
          }
          for (final ret in sim.returnsAt(loc)) {
            checkReturn(ret);
          }
        }
      });

      test('bills stay within the list limits and carry soldQty (D-030)', () {
        for (final loc in locations) {
          for (final e in sim.billDocsAt(loc).entries) {
            checkLimitsAndSoldQty(e.key, e.value);
          }
        }
      });

      test('returnedQty never exceeds soldQty, and a bill with a return is '
          'never cancelled (D-025, D-029)', () {
        for (final loc in locations) {
          final returns = {for (final r in sim.returnsAt(loc)) r.id: r};
          for (final e in sim.billDocsAt(loc).entries) {
            checkReturnState(e.key, e.value, returns);
          }
        }
      });

      test('every lost conflict is a sync error and wrote nothing', () {
        final c = sim.coverage;
        expect(
          sim.syncErrors.length,
          c.conflictCancelLost +
              c.conflictReturnLost +
              c.conflictOverReturnLost,
        );
        for (final loc in locations) {
          final returnIds = {for (final r in sim.returnsAt(loc)) r.id};
          for (final path in sim.syncErrors) {
            if (path.startsWith('${FirestorePaths.returns(loc)}/')) {
              expect(returnIds, isNot(contains(path.split('/').last)));
            }
          }
        }
      });

      test('a bill\'s refunds never exceed its total, and add up exactly', () {
        for (final loc in locations) {
          final returns = sim.returnsAt(loc);
          for (final b in sim.billsAt(loc)) {
            checkRefundsOf(b, [
              for (final ret in returns)
                if (ret.billId == b.id) ret,
            ]);
          }
        }
      });

      test('each daily summary equals its documents', () {
        for (final loc in locations) {
          for (final d in days) {
            final path = FirestorePaths.dailySummary(loc, d);
            final want = oracle(sim, [loc], (date) => date == d);
            expectSummary(sim.summaries[path], want, '$path (Summary.+)');
            expectSummary(sim.wireSummary(path), want, '$path (increments)');
            expectRevenueIdentities(sim, [loc], (date) => date == d, want);
          }
        }
      });

      test('each monthly summary equals its documents and its days', () {
        for (final loc in locations) {
          for (final m in months) {
            final path = FirestorePaths.monthlySummary(loc, m);
            bool inMonth(String date) => BusinessDate.monthOf(date) == m;
            final want = oracle(sim, [loc], inMonth);
            expectSummary(sim.summaries[path], want, '$path (Summary.+)');
            expectSummary(sim.wireSummary(path), want, '$path (increments)');
            expectRevenueIdentities(sim, [loc], inMonth, want);

            final ofDays = days
                .where(inMonth)
                .map(
                  (d) =>
                      sim.summaries[FirestorePaths.dailySummary(loc, d)] ??
                      const Summary(),
                )
                .fold(const Summary(), (a, s) => a + s);
            expectSummary(ofDays, want, '$path (sum of its days)');
          }
        }
      });

      test('all locations combined equal the documents of both', () {
        for (final d in days) {
          final combined = locations
              .map(
                (loc) =>
                    sim.summaries[FirestorePaths.dailySummary(loc, d)] ??
                    const Summary(),
              )
              .fold(const Summary(), (a, s) => a + s);
          expectSummary(
            combined,
            oracle(sim, locations, (date) => date == d),
            'all locations $d',
          );
        }
      });
    });
  }
}

// ---------------------------------------------------------------------------
// The oracle: every summary field, from the documents alone.
// ---------------------------------------------------------------------------

/// Recomputes a summary for [locs] over the business dates [inPeriod]
/// accepts, from the bill and return documents, per 02-DATA-MODEL:
///
/// * billCount, grossSales, discounts, roundOff, netSales: every bill
///   created in the period, including ones cancelled later that day
///   (`netSales` is not reduced by a cancellation; `cancelled` is, so that
///   net revenue = netSales − returns − cancelled; see QA-013).
/// * cancelCount, cancelled: bills whose `cancel.businessDate` is in the
///   period.
/// * returnCount, returns: returns whose own `businessDate` is in the
///   period (D-012), whatever the bill's date.
/// * byMode: payments of bills in the period that are still COMPLETED,
///   minus refunds of returns in the period.
/// * byProduct: qty and per-line net (D-024 c) of bills in the period that
///   are still COMPLETED, minus returned qty and amounts in the period.
Summary oracle(ShopSim sim, List<String> locs, bool Function(String) inPeriod) {
  var billCount = 0, cancelCount = 0, returnCount = 0;
  var gross = 0, discounts = 0, roundOff = 0, netSales = 0;
  var returns = 0, cancelled = 0;
  final byMode = <PaymentMode, int>{};
  final qty = <String, int>{};
  final amount = <String, int>{};

  for (final loc in locs) {
    for (final b in sim.billsAt(loc)) {
      if (inPeriod(b.businessDate)) {
        billCount++;
        gross += b.subtotal.paise;
        discounts += b.discount?.amount.paise ?? 0;
        roundOff += b.roundOff.paise;
        netSales += b.total.paise;
        if (b.status == BillStatus.completed) {
          for (final p in b.payments) {
            byMode[p.mode] = (byMode[p.mode] ?? 0) + p.amount.paise;
          }
          final nets = expectedLineNets(b);
          for (var i = 0; i < b.lines.length; i++) {
            final id = b.lines[i].productId;
            qty[id] = (qty[id] ?? 0) + b.lines[i].qty;
            amount[id] = (amount[id] ?? 0) + nets[i];
          }
        }
      }
      final cancel = b.cancel;
      if (b.status == BillStatus.cancelled && cancel != null) {
        if (inPeriod(cancel.businessDate)) {
          cancelCount++;
          cancelled += b.total.paise;
        }
      }
    }
    for (final r in sim.returnsAt(loc)) {
      if (!inPeriod(r.businessDate)) continue;
      returnCount++;
      returns += r.refundTotal.paise;
      for (final p in r.refunds) {
        byMode[p.mode] = (byMode[p.mode] ?? 0) - p.amount.paise;
      }
      for (final l in r.lines) {
        qty[l.productId] = (qty[l.productId] ?? 0) - l.qty;
        amount[l.productId] = (amount[l.productId] ?? 0) - l.amount.paise;
      }
    }
  }

  return Summary(
    billCount: billCount,
    cancelCount: cancelCount,
    returnCount: returnCount,
    grossSales: Money(gross),
    discounts: Money(discounts),
    roundOff: Money(roundOff),
    netSales: Money(netSales),
    returns: Money(returns),
    cancelled: Money(cancelled),
    byMode: {for (final e in byMode.entries) e.key: Money(e.value)},
    byProduct: {
      for (final id in {...qty.keys, ...amount.keys})
        id: ProductTally(qty: qty[id] ?? 0, amount: Money(amount[id] ?? 0)),
    },
  );
}

/// Business-level identities that must hold whatever the field semantics:
/// net revenue is what was kept, and it is split exactly by payment mode.
void expectRevenueIdentities(
  ShopSim sim,
  List<String> locs,
  bool Function(String) inPeriod,
  Summary s,
) {
  var kept = 0, keptBeforeRounding = 0;
  for (final loc in locs) {
    for (final b in sim.billsAt(loc)) {
      if (inPeriod(b.businessDate) && b.status == BillStatus.completed) {
        kept += b.total.paise;
        keptBeforeRounding += (b.total - b.roundOff).paise;
      }
    }
    for (final r in sim.returnsAt(loc)) {
      if (!inPeriod(r.businessDate)) continue;
      kept -= r.refundTotal.paise;
      keptBeforeRounding -= r.lines.fold<int>(0, (a, l) => a + l.amount.paise);
    }
  }
  expect(s.netRevenue.paise, kept, reason: 'net revenue = money kept');
  expect(
    s.byMode.values.fold<int>(0, (a, m) => a + m.paise),
    kept,
    reason: 'Σ byMode = net revenue',
  );
  expect(
    s.byProduct.values.fold<int>(0, (a, t) => a + t.amount.paise),
    keptBeforeRounding,
    reason: 'Σ byProduct.amount = net before round-off',
  );
}

/// D-024 (c): the bill's net (total − roundOff) split across its lines by
/// largest remainder. Checked here against the definition, not just taken
/// from `BillCalculator.lineNetAmounts`.
List<int> expectedLineNets(Bill b) {
  final nets = BillCalculator.lineNetAmounts(b).map((m) => m.paise).toList();
  final net = (b.total - b.roundOff).paise;
  expect(nets.fold<int>(0, (a, n) => a + n), net, reason: '${b.id} Σ nets');
  final sum = b.subtotal.paise;
  for (var i = 0; i < b.lines.length; i++) {
    final exact = b.lines[i].lineTotal.paise * net;
    final floor = sum == 0 ? 0 : exact ~/ sum;
    final hasRemainder = sum != 0 && exact % sum != 0;
    expect(
      nets[i],
      anyOf(floor, hasRemainder ? floor + 1 : floor),
      reason: '${b.id} line $i is its proportional share, ±1 paisa',
    );
  }
  return nets;
}

// ---------------------------------------------------------------------------
// Document-level checks.
// ---------------------------------------------------------------------------

void checkBill(Bill b) {
  final why = b.id;
  expect(b.billNo, Ids.billNo(b.billNo.split('-').first, b.id), reason: why);
  expect(b.total.isWholeRupees, isTrue, reason: '$why total ₹1 (D-010)');
  expect(
    b.subtotal.paise,
    b.lines.fold<int>(0, (a, l) => a + l.lineTotal.paise),
    reason: '$why subtotal = Σ lineTotal',
  );
  for (final l in b.lines) {
    expect(l.lineTotal, l.unitPrice.times(l.qty), reason: why);
  }
  expect(
    {for (final l in b.lines) l.productId}.length,
    b.lines.length,
    reason: '$why one line per product (D-024 e)',
  );
  expect(b.taxableValue, b.subtotal - b.discountAmount, reason: why);
  expect(b.total, b.taxableValue + b.roundOff, reason: why);
  expect(b.roundOff.paise.abs(), lessThanOrEqualTo(50), reason: why);
  expect(b.payments.length, lessThanOrEqualTo(4), reason: '$why ≤ 4 payments');
  expect(
    BillCalculator.checkPayments(
      b.total,
      b.payments,
      cashTendered: b.cashTendered,
    ).errors,
    isEmpty,
    reason: '$why Σ payments = total',
  );
  if (b.status == BillStatus.cancelled) {
    expect(b.cancel, isNotNull, reason: why);
    expect(
      b.cancel!.businessDate,
      b.businessDate,
      reason: '$why same-day cancel (D-009)',
    );
    expect(
      b.returnedQty.values.every((q) => q == 0),
      isTrue,
      reason: '$why no cancel after a return (D-025)',
    );
  }
}

void checkReturn(SaleReturn r) {
  expect(r.refundTotal.isWholeRupees, isTrue, reason: '${r.id} whole rupees');
  expect(r.refundTotal.isNegative, isFalse, reason: r.id);
  expect(
    ReturnCalculator.checkRefunds(r.refundTotal, r.refunds),
    isEmpty,
    reason: '${r.id} Σ refunds = refundTotal',
  );
  for (final l in r.lines) {
    expect(l.qty, greaterThan(0), reason: r.id);
    expect(l.amount.isNegative, isFalse, reason: r.id);
  }
}

/// D-030 and 04-PERMISSIONS #6: at most 20 lines and 4 payments, and a
/// stored `soldQty` with one key per line holding that line's qty.
void checkLimitsAndSoldQty(String billId, Map<String, Object?> doc) {
  final lines = (doc['lines']! as List).cast<Map<String, Object?>>();
  expect(
    lines.length,
    inInclusiveRange(1, Limits.maxBillLines),
    reason: billId,
  );
  expect(
    (doc['payments']! as List).length,
    lessThanOrEqualTo(Limits.maxPayments),
    reason: billId,
  );
  expect(doc['soldQty'], {
    for (final l in lines) l['productId']: l['qty'],
  }, reason: '$billId soldQty = the qty of each line');
}

/// D-025, D-029: cumulative `returnedQty` stays within `soldQty` and never
/// holds a 0; a cancelled bill has an empty `returnedQty`; `lastReturnId`
/// names the bill's latest return.
void checkReturnState(
  String billId,
  Map<String, Object?> doc,
  Map<String, SaleReturn> returns,
) {
  final sold = (doc['soldQty']! as Map).cast<String, int>();
  final returned = (doc['returnedQty']! as Map).cast<String, int>();
  for (final e in returned.entries) {
    expect(e.value, greaterThan(0), reason: '$billId never writes a 0');
    expect(
      e.value,
      lessThanOrEqualTo(sold[e.key] ?? 0),
      reason: '$billId ${e.key} returnedQty <= soldQty',
    );
  }
  if (doc['status'] == BillStatus.cancelled.wire) {
    expect(returned, isEmpty, reason: '$billId cancelled with a return');
  }
  final mine = [
    for (final r in returns.values)
      if (r.billId == billId) r,
  ];
  final last = doc['lastReturnId'] as String?;
  if (mine.isEmpty) {
    expect(last, isNull, reason: billId);
  } else {
    expect(returns[last]?.billId, billId, reason: '$billId lastReturnId');
    expect(
      returns[last]!.clientCreatedAt,
      mine.map((r) => r.clientCreatedAt).reduce((a, b) => a.isAfter(b) ? a : b),
      reason: '$billId lastReturnId is the latest return',
    );
  }
}

/// D-024 (d): refunds are cumulative, so whatever the split into returns,
/// a line's refunded amount is the value of everything returned so far,
/// and the refunds add up to the rupee-rounded value of it all.
void checkRefundsOf(Bill b, List<SaleReturn> rets) {
  final why = b.id;
  final nets = expectedLineNets(b);
  var refunded = 0, value = 0;
  for (final r in rets) {
    refunded += r.refundTotal.paise;
  }
  var fully = true;
  for (var i = 0; i < b.lines.length; i++) {
    final line = b.lines[i];
    var q = 0, amt = 0;
    for (final r in rets) {
      for (final l in r.lines) {
        if (l.productId == line.productId) {
          q += l.qty;
          amt += l.amount.paise;
        }
      }
    }
    expect(q, lessThanOrEqualTo(line.qty), reason: '$why ${line.productId}');
    expect(
      b.returnedQty[line.productId] ?? 0,
      q,
      reason: '$why returnedQty matches its returns',
    );
    final lineValue = q == line.qty
        ? nets[i]
        : divideRounded(nets[i] * q, line.qty);
    expect(amt, lineValue, reason: '$why ${line.productId} cumulative amount');
    expect(amt, lessThanOrEqualTo(nets[i]), reason: why);
    value += lineValue;
    if (q < line.qty) fully = false;
  }
  expect(
    refunded,
    Money(value).roundToRupee().paise,
    reason: '$why Σ refundTotal = rounded value returned',
  );
  expect(refunded, lessThanOrEqualTo(b.total.paise), reason: '$why ≤ total');
  if (fully) {
    expect(refunded, b.total.paise, reason: '$why full return refunds total');
  }
}

// ---------------------------------------------------------------------------
// Comparison.
// ---------------------------------------------------------------------------

/// Summaries compared field by field. Zero map entries are dropped on both
/// sides: an increment of 0 is never written, and a mode that nets to 0
/// reads the same as an absent one.
void expectSummary(Summary? actual, Summary want, String what) {
  expect(canonical(actual ?? const Summary()), canonical(want), reason: what);
}

Map<String, Object> canonical(Summary s) => {
  'billCount': s.billCount,
  'cancelCount': s.cancelCount,
  'returnCount': s.returnCount,
  'grossSales': s.grossSales.paise,
  'discounts': s.discounts.paise,
  'roundOff': s.roundOff.paise,
  'netSales': s.netSales.paise,
  'returns': s.returns.paise,
  'cancelled': s.cancelled.paise,
  'byMode': {
    for (final e in s.byMode.entries)
      if (!e.value.isZero) e.key.wire: e.value.paise,
  },
  'byProduct': {
    for (final e in s.byProduct.entries)
      if (e.value.qty != 0 || !e.value.amount.isZero)
        e.key: [e.value.qty, e.value.amount.paise],
  },
  'expenses': s.expenses.paise,
};
